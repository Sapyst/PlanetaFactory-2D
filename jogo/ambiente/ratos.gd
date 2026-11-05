class_name Ratos
extends RefCounted
## Patch fauna, fase 5 (docs/PLANO_FAUNA.md), lógica pura: os ratos do mato. Duas espécies: o rato-pardo, com toca ao
## pé de arbusto ou árvore, e o saltador, com toca em campo aberto (anda aos pulos, mais rápido, vaga mais longe).
##  tocas     nascem no mato saudável perto da câmera, de preferência ao pé de arbusto ou árvore (abrigo), longe de
##            construção e de outra toca; cada uma tem alguns ratos. Ficam no save; longe da câmera, os ratos ficam
##            dentro (sem simular). Chão que morreu ou construção encostada: a toca é abandonada.
##  rotina    roedor de crepúsculo e de noite: sai mais ao amanhecer, ao anoitecer e à noite, pouco ao meio-dia e no
##            inverno. Fora da toca anda, para e fareja, procura fruto (comida "fruta" do Ecossistema) perto da toca e
##            come sentado. Bolota e pinha às vezes leva e ENTERRA num chão livre ali perto; a que ele esquece vira muda
##            da árvore dela (AmbienteVivo.plantar_em): o rato refloresta.
##  medo      aranha e larva (fonte "alien"), fogo, susto (tiro, explosão, raio) e construção encostada: corre para a
##            toca; se o perigo está na toca, foge para longe e espera.
##  presa     aranha ou larva encostando mata o rato; fogo também. A morte vai ao Ecossistema (`morreu`): vira carcaça
##            com mosca (fase 4).
##  trilha    por onde os ratos passam muito o chão marca a passagem (`passagem`, tile → 0..1, some devagar): o
##            desenho deita o capim ali.
## Os desenhos 3D e 2D leem `ratos` (posição, rumo, estado) e `tocas`. Eventos: "saiu", "entrou", "comeu", "enterrou",
## "nasceu_muda", "fugiu", "chiou".

enum E { TOCA, SAINDO, ANDANDO, FAREJANDO, COMENDO, CAVANDO, FUGINDO, ENTRANDO }
const TRILHA_RES := 4            ## células da trilha por metro (25 cm: a trilha de rato tem uns palmos)

var eco: Ecossistema
var ambiente: AmbienteVivo
var tocas: Dictionary = {}       ## id → {id, pos: Vector2, n: int, especie}
var ratos: Dictionary = {}       ## id → {id, toca, especie, pos, rumo, estado, t, alvo, comida, carga, fome, pasto}
var passagem: Dictionary = {}    ## célula de 25 cm (Vector2i(pos × TRILHA_RES)) → 0..1
var eventos: Array = []
var mortos: Dictionary = {}      ## id → s desde que morreu (os últimos segundos: o desenho deita o corpo)
var versao_passagem := 0
var enterradas := 0              ## sementes enterradas (contagem)
var mudas := 0                   ## mudas que nasceram delas
var _sustos: Array = []          ## [centro, raio] deste passo
var _prox := 1
var _t_toca := 0.0
var _t_marca := 0.0
var _rng := RandomNumberGenerator.new()
var _d: Dictionary


func _init(p_eco: Ecossistema, p_ambiente: AmbienteVivo = null, semente := 101) -> void:
	eco = p_eco
	ambiente = p_ambiente
	_rng.seed = semente
	_d = Registro.fauna.get("ratos", {})


func _n(chave: String, padrao: float) -> float:
	return float(_d.get(chave, padrao))


## Número da espécie (fauna.json ratos.especies.<esp>), senão o geral.
func _ne(r: Dictionary, chave: String, padrao: float) -> float:
	return float(_d.get("especies", {}).get(String(r.get("especie", "pardo")), {}).get(chave, _d.get(chave, padrao)))


## Os ratos como o Ecossistema os vê (fonte "rato"): os que estão fora da toca.
func para_ecossistema() -> Array:
	var out: Array = []
	for r in ratos.values():
		if r.estado != E.TOCA:
			out.append({"id": r.id, "pos": r.pos, "especie": "rato"})
	return out


func assustar(c: Vector2, raio: float) -> void:
	_sustos.append([c, raio])


## Quanto querem estar fora agora (0..1): crepúsculo e noite muito, meio-dia pouco, inverno pouco.
func atividade(clima: Clima) -> float:
	if clima == null:
		return 0.6
	var luz := clima.luz_dia()
	var dia := clampf((luz - 0.55) / 0.3, 0.0, 1.0)
	var es: Array = _d.get("estacoes", [1.0, 1.0, 0.9, 0.3])
	return lerpf(1.0, float(_d.get("meio_dia", 0.3)), dia) * float(es[clampi(clima.estacao, 0, 3)]) \
			* (1.0 - 0.7 * float(clima.valores.get("chuva", 0.0)))


func tick(dt: float, clima: Clima, foco: Vector2) -> void:
	eventos.clear()
	if not bool(_d.get("liga", true)):
		_sustos.clear()
		return
	_t_toca -= dt
	if _t_toca <= 0.0:
		_t_toca = _n("tocas_s", 8.0)
		_cuidar_tocas(foco)
	var ativo := atividade(clima)
	var raio := _n("raio_vida", 45.0)
	for r in ratos.values():
		var perto: bool = (r.pos as Vector2).distance_to(foco) <= raio
		if not perto:
			if r.estado != E.TOCA:                         # longe da câmera: volta para dentro (sem simular)
				r.estado = E.TOCA
				r.pos = tocas[r.toca].pos if tocas.has(r.toca) else r.pos
				r.t = _rng.randf_range(5.0, 20.0)
			continue
		_rato(r, dt, ativo)
	_t_marca -= dt
	if _t_marca <= 0.0:
		_t_marca = 0.5
		_marcar_e_desmarcar(0.5)
	for id in mortos.keys():
		mortos[id] = float(mortos[id]) + dt
		if float(mortos[id]) > 5.0:
			mortos.erase(id)
	var morreram: Array = ratos.values().filter(func(r): return r.get("morto", false))
	for r in morreram:
		ratos.erase(r.id)
		mortos[r.id] = 0.0
		if tocas.has(r.toca):
			tocas[r.toca].n = maxi(0, int(tocas[r.toca].n) - 1)
		eco.morreu("rato", "rato", r.pos, {"id": r.id, "variante": String(r.get("especie", "pardo")), "rumo": float(r.rumo)})
	_sustos.clear()


# ------------------------------------------------------------------ tocas
func _cuidar_tocas(foco: Vector2) -> void:
	var raio := _n("raio_vida", 45.0)
	# abandono: o chão morreu ou encostaram construção
	for id in tocas.keys():
		var tc: Dictionary = tocas[id]
		var tl := Vector2i((tc.pos as Vector2).floor())
		if (tc.pos as Vector2).distance_to(foco) <= raio and (eco.saude(tl) < _n("saude_min", 0.45) * 0.6 \
				or eco.perto_de_construcao(tl, int(_n("longe_construcao", 6)) - 2)):
			abandonar(id)
	var perto := tocas.values().filter(func(tc): return (tc.pos as Vector2).distance_to(foco) <= raio)
	if perto.size() >= int(_n("tocas_max", 6)):
		return
	for tentativa in 10:
		var p := foco + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(6.0, raio * 0.9)
		var tl := Vector2i(p.floor())
		var esp := especie_de_toca(tl)
		if esp == "":
			continue
		nova_toca(Vector2(tl) + Vector2(0.5, 0.5), esp)
		return


## Mato saudável, terra seca e livre, longe de construção, de água e de outra toca.
func lugar_de_toca(tl: Vector2i) -> bool:
	return especie_de_toca(tl) != ""


## Quem cava aqui: com abrigo (arbusto ou árvore a até 3 m) o rato-pardo; em campo aberto, às vezes, o saltador.
## "" = não serve para toca.
func especie_de_toca(tl: Vector2i) -> String:
	if eco.gerador.terreno(tl) != GeradorMundo.Terreno.TERRA or eco.mapa.tiles.has(tl) or eco.gerador.aplainado_em(tl) != null:
		return ""
	if not eco.gerador.distribuicao.obstaculo(tl).is_empty() and not eco.mapa.limpos.has(tl):
		return ""
	if eco.saude(tl) < _n("saude_min", 0.45) or eco.perto_de_construcao(tl, int(_n("longe_construcao", 6))):
		return ""
	if eco.perto_da_agua(tl, 1):
		return ""
	for tc in tocas.values():
		if (tc.pos as Vector2).distance_to(Vector2(tl)) < _n("entre_tocas", 10.0):
			return ""
	var c := Vector2(tl) + Vector2(0.5, 0.5)
	if not eco.arbustos_perto(c, 3.0).is_empty() or not eco.arvores_perto(c, 3.0).is_empty():
		return "pardo"
	return "saltador" if _rng.randf() < _n("aberto_chance", 0.5) else ""


func nova_toca(p: Vector2, especie := "pardo") -> int:
	var id := _prox
	_prox += 1
	var faixa: Array = _d.get("por_toca", [2, 4])
	var n := _rng.randi_range(int(faixa[0]), int(faixa[1]))
	tocas[id] = {"id": id, "pos": p, "n": n, "especie": especie}
	for k in n:
		_novo_rato(id)
	return id


func _novo_rato(toca: int) -> Dictionary:
	var id := _prox
	_prox += 1
	var r := {"id": id, "toca": toca, "especie": String(tocas[toca].get("especie", "pardo")), "pos": tocas[toca].pos,
			"rumo": _rng.randf() * TAU, "estado": E.TOCA, "t": _rng.randf_range(2.0, 25.0), "alvo": tocas[toca].pos,
			"comida": -1, "carga": "", "fome": _rng.randf(), "pasto": false}
	ratos[id] = r
	return r


func abandonar(id: int) -> void:
	for r in ratos.values().filter(func(r): return r.toca == id):
		ratos.erase(r.id)
	tocas.erase(id)


# ------------------------------------------------------------------ um rato
func _rato(r: Dictionary, dt: float, ativo: float) -> void:
	var casa: Vector2 = tocas[r.toca].pos if tocas.has(r.toca) else r.pos
	r.t = float(r.t) - dt
	if r.estado == E.TOCA:
		if r.t <= 0.0:
			r.t = _rng.randf_range(3.0, 12.0)
			if _rng.randf() < ativo and _perigo(casa) == null:
				r.estado = E.SAINDO
				r.pos = casa
				r.t = float(_d.get("sair_s", 0.8))
				eventos.append({"tipo": "saiu", "id": r.id, "pos": casa})
		return
	# perigo: predador, fogo, susto, construção
	var de: Variant = _perigo(r.pos)
	if de != null and r.estado != E.FUGINDO and r.estado != E.ENTRANDO:
		_fugir(r, de, casa)
	if _morre(r):
		r.morto = true
		return
	match int(r.estado):
		E.SAINDO:
			if r.t <= 0.0:
				_escolher(r, casa, ativo)
		E.ANDANDO:
			var vel := _ne(r, "vel", 0.55)
			if _andar(r, r.alvo, vel, dt):
				_chegou(r, casa, ativo)
			elif r.t <= 0.0:
				r.estado = E.FAREJANDO                     # para no caminho e fareja
				r.t = _rng.randf_range(0.8, 2.5)
		E.FAREJANDO:
			if r.t <= 0.0:
				r.estado = E.ANDANDO
				r.t = _rng.randf_range(1.5, 4.0)
				if _rng.randf() < 0.15:
					eventos.append({"tipo": "chiou", "id": r.id, "pos": r.pos})
		E.COMENDO:
			if r.t <= 0.0:
				var f: Dictionary = eco.comida.get(int(r.comida), {})
				r.comida = -1
				if not f.is_empty():
					var leva := String(f.get("fonte", "")) != "" and _rng.randf() < _n("leva_chance", 0.45)
					if eco.comer(int(f.id), "rato"):
						r.fome = 0.0
						eventos.append({"tipo": "comeu", "id": r.id, "pos": r.pos, "especie": String(f.get("especie", ""))})
						if leva:                               # leva a bolota/pinha para enterrar ali perto
							r.carga = String(f.fonte)
							r.alvo = _lugar_de_enterrar(r.pos, casa)
							r.estado = E.ANDANDO
							r.t = 8.0
							return
				if f.is_empty() and _rng.randf() < 0.5:
					_escolher(r, casa, ativo)              # comeu semente do capim: segue procurando
				else:
					_voltar(r, casa)
		E.CAVANDO:
			if r.t <= 0.0:
				_enterrar(r)
				_voltar(r, casa)
		E.FUGINDO:
			if _andar(r, r.alvo, _ne(r, "vel_fuga", 2.4), dt) or r.t <= 0.0:
				if (r.alvo as Vector2).distance_to(casa) < 0.3:
					_entrar(r)
				else:
					r.estado = E.FAREJANDO                 # escondido longe: espera e volta
					r.t = _rng.randf_range(4.0, 9.0)
					r.alvo = casa
		E.ENTRANDO:
			if r.t <= 0.0:
				r.estado = E.TOCA
				r.t = _rng.randf_range(6.0, 30.0) / maxf(ativo, 0.2)
				r.pos = casa
				eventos.append({"tipo": "entrou", "id": r.id, "pos": casa})


## Ao sair ou depois de parar: vai a um fruto perto (com fome), senão vaga em volta da toca; tarde ou cansado, volta.
func _escolher(r: Dictionary, casa: Vector2, ativo: float) -> void:
	if _rng.randf() > ativo * 1.3:
		_voltar(r, casa)
		return
	r.fome = minf(1.0, float(r.fome) + 0.35)
	var busca := _n("raio_busca", 12.0)
	if float(r.fome) > 0.3:
		var melhor: Dictionary = {}
		var d := INF
		for f in eco.comida_perto(casa, busca, "fruta"):
			var dd := (f.pos as Vector2).distance_to(r.pos)
			if dd < d and not _fruto_tomado(int(f.id), r.id):
				d = dd
				melhor = f
		if not melhor.is_empty():
			r.comida = int(melhor.id)
			r.alvo = melhor.pos
			r.estado = E.ANDANDO
			r.t = _rng.randf_range(2.0, 5.0)
			return
	r.comida = -1
	r.pasto = _rng.randf() < _n("pasto_chance", 0.35)           # sem fruto: vai comer semente do capim ali
	r.alvo = casa + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(1.5, _ne(r, "raio_vagar", 8.0))
	if not _chao_bom(r.alvo):
		r.alvo = casa + Vector2.from_angle(_rng.randf() * TAU) * 1.5
	r.estado = E.ANDANDO
	r.t = _rng.randf_range(2.0, 5.0)


func _fruto_tomado(id: int, quem: int) -> bool:
	for o in ratos.values():
		if o.id != quem and int(o.comida) == id:
			return true
	return false


func _chegou(r: Dictionary, casa: Vector2, ativo: float) -> void:
	if String(r.carga) != "":
		r.estado = E.CAVANDO
		r.t = float(_d.get("cavar_s", 2.5))
		return
	if bool(r.get("pasto", false)):
		r.pasto = false
		r.estado = E.COMENDO
		r.t = _rng.randf_range(2.5, 5.0)
		return
	if int(r.comida) >= 0:
		if eco.comida.has(int(r.comida)):
			r.estado = E.COMENDO
			r.t = _rng.randf_range(float((_d.get("comer_s", [4.0, 8.0]) as Array)[0]), float((_d.get("comer_s", [4.0, 8.0]) as Array)[1]))
			return
		r.comida = -1                                       # outro comeu primeiro
	if (r.alvo as Vector2).distance_to(casa) < 0.3:
		_entrar(r)
		return
	if _rng.randf() < 0.5:
		r.estado = E.FAREJANDO
		r.t = _rng.randf_range(1.0, 3.0)
	else:
		_escolher(r, casa, ativo)


func _voltar(r: Dictionary, casa: Vector2) -> void:
	r.alvo = casa
	r.comida = -1
	r.estado = E.ANDANDO
	r.t = 30.0


func _entrar(r: Dictionary) -> void:
	r.estado = E.ENTRANDO
	r.t = float(_d.get("entrar_s", 0.6))


func _fugir(r: Dictionary, de: Vector2, casa: Vector2) -> void:
	var dir := ((r.pos as Vector2) - de)
	dir = dir.normalized() if dir.length() > 0.01 else Vector2.from_angle(_rng.randf() * TAU)
	var toca_ok := (casa.distance_to(de) > _n("medo_raio", 6.0)) and tocas.has(r.toca)
	r.alvo = casa if toca_ok else (r.pos as Vector2) + dir * _rng.randf_range(8.0, 12.0)
	r.estado = E.FUGINDO
	r.t = 10.0
	r.comida = -1
	if String(r.carga) != "":
		r.carga = ""                                       # largou a bolota correndo
	eventos.append({"tipo": "fugiu", "id": r.id, "pos": r.pos})


## Anda até `alvo` (m/s), virando para ele; devolve se chegou.
func _andar(r: Dictionary, alvo: Vector2, vel: float, dt: float) -> bool:
	var d := alvo - (r.pos as Vector2)
	if d.length() < 0.08:
		return true
	r.rumo = d.angle()
	r.pos = (r.pos as Vector2) + d.normalized() * minf(d.length(), vel * dt)
	return (alvo - (r.pos as Vector2)).length() < 0.08


func _chao_bom(p: Vector2) -> bool:
	var tl := Vector2i(p.floor())
	return eco.gerador.terreno(tl) == GeradorMundo.Terreno.TERRA and not eco.mapa.tiles.has(tl)


## Chão livre ali perto para enterrar (entre 2 e 6 m da toca, sem árvore em cima).
func _lugar_de_enterrar(de: Vector2, casa: Vector2) -> Vector2:
	for tentativa in 16:
		var p := casa + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(2.0, 6.0 + tentativa * 0.2)
		if _chao_bom(p) and (ambiente == null or ambiente.pode_plantar(Vector2i(p.floor()))):
			return p
	return de


## Enterra a semente que carrega; a que ele esquece (chance) vira muda da árvore dela.
func _enterrar(r: Dictionary) -> void:
	if String(r.carga) == "":
		return
	enterradas += 1
	var esp := String(r.carga)
	r.carga = ""
	eventos.append({"tipo": "enterrou", "id": r.id, "pos": r.pos, "especie": esp})
	if ambiente != null and _rng.randf() < _n("esquece_chance", 0.35):
		var tl := Vector2i((r.pos as Vector2).floor())
		if ambiente.plantar_em(tl, esp):
			mudas += 1
			eventos.append({"tipo": "nasceu_muda", "tile": tl, "especie": esp})


## O que assusta em `p`: susto do passo, predador (aranha, larva), fogo, construção encostada. Devolve de onde vem.
func _perigo(p: Vector2) -> Variant:
	for s in _sustos:
		if p.distance_to(s[0]) < float(s[1]):
			return s[0]
	var r := _n("medo_raio", 6.0)
	for a in eco.perto(p, r, "alien"):
		return a.pos
	if ambiente != null and not ambiente.fogo.is_empty():
		var n := 0
		for t: Vector2i in ambiente.fogo:
			if p.distance_to(Vector2(t) + Vector2(0.5, 0.5)) < r:
				return Vector2(t)
			n += 1
			if n > 300:
				break
	if eco.mapa.tiles.has(Vector2i(p.floor())):
		return p + Vector2(0.1, 0.0)
	return null


## Aranha ou larva encostando (presa), ou fogo no tile: morre.
func _morre(r: Dictionary) -> bool:
	for a in eco.perto(r.pos, _n("pego_raio", 0.7), "alien"):
		return true
	return ambiente != null and ambiente.fogo.has(Vector2i((r.pos as Vector2).floor()))


# ------------------------------------------------------------------ trilhas
func _marcar_e_desmarcar(dt: float) -> void:
	var mudou := false
	for r in ratos.values():
		if r.estado in [E.ANDANDO, E.FUGINDO]:
			var tl := Vector2i(((r.pos as Vector2) * TRILHA_RES).floor())
			var v := minf(1.0, float(passagem.get(tl, 0.0)) + _n("trilha_passo", 0.03))
			if int(v * 10.0) != int(float(passagem.get(tl, 0.0)) * 10.0):
				mudou = true
			passagem[tl] = v
	var some := dt / _n("trilha_some_s", 1800.0)
	for tl in passagem.keys():
		var v := float(passagem[tl]) - some
		if v <= 0.0:
			passagem.erase(tl)
			mudou = true
		else:
			passagem[tl] = v
	if mudou:
		versao_passagem += 1


func estado() -> Dictionary:
	return {"tocas": tocas, "ratos": ratos, "passagem": passagem, "prox": _prox, "rng": _rng.state,
			"enterradas": enterradas, "mudas": mudas}


func restaurar(d: Dictionary) -> void:
	tocas = {}
	for k in d.get("tocas", {}):
		tocas[int(k)] = d.tocas[k]
	ratos = {}
	for k in d.get("ratos", {}):
		var r: Dictionary = d.ratos[k]
		r.estado = E.TOCA                                  # carregou: todos em casa
		r.pasto = false
		if not r.has("especie"):
			r.especie = String(tocas.get(int(r.toca), {}).get("especie", "pardo"))
		r.pos = tocas[int(r.toca)].pos if tocas.has(int(r.toca)) else r.pos
		r.carga = ""
		ratos[int(k)] = r
	passagem = d.get("passagem", {})
	_prox = int(d.get("prox", 1))
	_rng.state = int(d.get("rng", _rng.state))
	enterradas = int(d.get("enterradas", 0))
	mudas = int(d.get("mudas", 0))
	versao_passagem += 1
