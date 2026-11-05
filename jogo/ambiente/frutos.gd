class_name Frutos
extends RefCounted
## Patch fauna, fase 3 (docs/PLANO_FAUNA.md), lógica pura: frutos no chão e sementes no vento.
##  frutos    perto da câmera, embaixo das árvores e arbustos que dão fruto na estação (bolota do carvalho no outono,
##            pinha do pinheiro, baga do arbusto no verão), os frutos caem e viram comida no Ecossistema (tipo
##            "fruta"). Os pássaros comem e levam a semente da árvore (Passaros); os ratos vão comer (fase 5). Se ninguém
##            come, apodrecem e somem (o Ecossistema envelhece a comida pela `vida`).
##  sementes  na troca de estação, as árvores de semente com asa (bétula, salgueiro, pinheiro) soltam sementes no
##            vento. Algumas pegam no chão aberto a favor do vento, de preferência no chão morto (queimado, cicatriz de
##            árvore que caiu ou foi corroída), e nascem mudas da mesma espécie (AmbienteVivo.plantar_em): a mata volta
##            sozinha onde a causa sumiu. O desenho das sementes voando é do DesenhoPlantasReagem.

const FONTES := {"arv_carvalho": "bolota", "arv_pinheiro": "pinha", "arbusto": "baga"}

var eco: Ecossistema
var ambiente: AmbienteVivo
var t := 0.0
var semeadas := 0               ## mudas nascidas de semente no vento (contagem)
var eventos: Array = []         ## {tipo: "muda_semente", tile, de} do último tick
var _estacao_ant := -1
var _t_fruto := 0.0
var _rng := RandomNumberGenerator.new()
var _d: Dictionary


func _init(p_eco: Ecossistema, p_ambiente: AmbienteVivo, semente := 91) -> void:
	eco = p_eco
	ambiente = p_ambiente
	_rng.seed = semente
	_d = Registro.fauna.get("frutos", {})


func _n(grupo: String, chave: String, padrao: float) -> float:
	return float(_d.get(grupo, {}).get(chave, padrao))


## Que fruto a planta dá ("" = nenhum).
static func fruto_de(nome: String) -> String:
	for pre in FONTES:
		if nome.begins_with(pre):
			return FONTES[pre]
	return ""


func tick(dt: float, clima: Clima, foco: Vector2) -> void:
	t += dt
	eventos.clear()
	if clima == null:
		return
	_t_fruto -= dt
	if _t_fruto <= 0.0:
		_t_fruto = _n("cair", "intervalo_s", 3.0)
		cair(foco, clima.estacao)
	if _estacao_ant >= 0 and clima.estacao != _estacao_ant:
		semear(foco, clima.estacao, clima.direcao_vento)
	_estacao_ant = clima.estacao


func _chao_livre(p: Vector2) -> bool:
	var tl := Vector2i(p.floor())
	return eco.gerador.terreno(tl) == GeradorMundo.Terreno.TERRA and not eco.mapa.tiles.has(tl) \
			and eco.gerador.aplainado_em(tl) == null


# ------------------------------------------------------------------ frutos
## Um passo de queda: cada planta com fruto na estação, perto da câmera, pode soltar um no chão embaixo da copa.
## Não passa de `max` perto da câmera nem de `por_fonte` embaixo da mesma planta. Devolve quantos caíram.
func cair(foco: Vector2, estacao: int) -> int:
	if not bool(_d.get("liga", true)):
		return 0
	var c: Dictionary = _d.get("cair", {})
	var raio := float(c.get("raio", 26.0))
	var tipos: Dictionary = _d.get("tipos", {})
	var total := eco.comida_perto(foco, raio * 1.3, "fruta").size()
	var mx := int(c.get("max", 90))
	var poe := 0
	for a in eco.arvores_perto(foco, raio) + eco.arbustos_perto(foco, raio):
		if total + poe >= mx:
			break
		var tipo := fruto_de(String(a.nome))
		if tipo == "" or not tipos.has(tipo):
			continue
		var dt_: Dictionary = tipos[tipo]
		var taxa := float((dt_.get("estacoes", [0, 0, 1, 0]) as Array)[clampi(estacao, 0, 3)])
		if taxa <= 0.0 or _rng.randf() > taxa * float(dt_.get("chance", 0.1)):
			continue
		var copa := float(a.copa)
		if eco.comida_perto(a.pos, copa + 0.8, "fruta").size() >= int(dt_.get("por_fonte", 6)):
			continue
		var p: Vector2 = a.pos + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.3, copa * 1.05 + 0.3)
		if not _chao_livre(p):
			continue
		var id := eco.por_comida("fruta", p, float(dt_.get("valor", 1.0)))
		var f: Dictionary = eco.comida[id]
		f.especie = tipo
		f.fonte = "" if tipo == "baga" else Ecossistema.especie_arvore(String(a.nome))
		f.vida = float(dt_.get("vida_s", 900.0)) * _rng.randf_range(0.8, 1.2)
		f.ang = _rng.randf() * TAU
		f.tam = _rng.randf_range(0.8, 1.2)
		poe += 1
	return poe


# ------------------------------------------------------------------ sementes no vento
## Na troca de estação: as árvores de semente com asa daquela estação soltam sementes a favor do vento; algumas viram
## muda em chão aberto (fora da sombra de outra árvore), de preferência chão morto. Devolve quantas mudas nasceram.
func semear(foco: Vector2, estacao: int, vento: Vector2) -> int:
	var c: Dictionary = _d.get("sementes", {})
	if not bool(c.get("liga", true)) or ambiente == null:
		return 0
	var esps: Dictionary = c.get("especies", {})
	var arvs: Array = eco.arvores_perto(foco, float(c.get("raio", 30.0))).duplicate()
	for i in range(arvs.size() - 1, 0, -1):                       # ordem sorteada (pelo rng: o mesmo jogo, o mesmo sorteio)
		var j := _rng.randi_range(0, i)
		var tmp = arvs[i]
		arvs[i] = arvs[j]
		arvs[j] = tmp
	var dist: Array = c.get("dist", [4.0, 22.0])
	var v := vento.normalized() if vento.length() > 0.01 else Vector2.RIGHT
	var lado := Vector2(-v.y, v.x)
	var poe := 0
	for a in arvs:
		if poe >= int(c.get("max_por_vez", 8)):
			break
		var esp := Ecossistema.especie_arvore(String(a.nome))
		if not esps.has(esp) or _rng.randf() > float((esps[esp] as Array)[clampi(estacao, 0, 3)]) * float(c.get("chance", 0.35)):
			continue
		var melhor: Variant = null
		var nota := -1.0
		for k in 5:
			var d := _rng.randf_range(float(dist[0]), float(dist[1]))
			var p: Vector2 = a.pos + v * d + lado * _rng.randf_range(-0.35, 0.35) * d
			var tl := Vector2i(p.floor())
			if not ambiente.pode_plantar(tl) or _na_sombra(tl):
				continue
			var nt := 2.0 * ambiente.valor(tl, AmbienteVivo.QUEIM) + (0.6 if eco.mapa.limpos.has(tl) else 0.0) \
					+ (0.4 if eco.morto(tl) else 0.0) + _rng.randf() * 0.1
			if nt > nota:
				nota = nt
				melhor = tl
		if melhor != null and ambiente.plantar_em(melhor, esp):
			poe += 1
			eventos.append({"tipo": "muda_semente", "tile": melhor, "de": a.pos, "especie": esp})
	semeadas += poe
	return poe


## Sombra de árvore (de pé, a até 2 tiles) ou muda encostada: ali a semente não pega.
func _na_sombra(tl: Vector2i) -> bool:
	for y in range(-2, 3):
		for x in range(-2, 3):
			var q := tl + Vector2i(x, y)
			if ambiente.plantas.has(q):
				return true
			if eco.mapa.limpos.has(q) or not eco.mapa.arvores.get(q, {}).is_empty():
				continue
			var o := eco.gerador.distribuicao.obstaculo(q)
			if not o.is_empty() and String(o.nome).begins_with("arv") and String(o.nome) != "arvore_morta":
				return true
	return false


func estado() -> Dictionary:
	return {"t": t, "semeadas": semeadas, "estacao_ant": _estacao_ant, "rng": _rng.state}


func restaurar(d: Dictionary) -> void:
	t = float(d.get("t", 0.0))
	semeadas = int(d.get("semeadas", 0))
	_estacao_ant = int(d.get("estacao_ant", -1))
	_rng.state = int(d.get("rng", _rng.state))
