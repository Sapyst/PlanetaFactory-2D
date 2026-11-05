class_name Ecossistema
extends RefCounted
## Patch fauna, fase 0 (docs/PLANO_FAUNA.md): a fundação que todo bicho usa, lógica pura (sem desenho).
##
##  índice    quem tem bichos se apresenta com uma fonte (`registrar_fonte(tipo, func() -> Array)`): pássaros,
##            aranhas e larvas, tocas. A cada `indice_s` o índice espacial (células de `cel` m) é refeito a partir
##            das fontes — ninguém mexe por dentro do outro; quem precisa saber o que tem perto pergunta `perto()`.
##  eventos   `morreu`, `comeu`, `fugiu`: quem produz chama `avisar()`; no tick viram `eventos` (valem um passo).
##            As fases seguintes (carcaças, moscas, ratos) leem daqui.
##  comida    fontes de comida no chão (fruta, semente, carcaça — fases 3 e 4); vai no save. Envelhece no tick: a que
##            tem `vida` e passou dela apodrece e some (evento "apodreceu").
##  fértil    (fase 4) chão adubado onde uma carcaça apodreceu: a semente pega e o cogumelo brota ali primeiro, e o
##            lugar conta como mais vivo. Some devagar (`fertil_some_s`); vai no save.
##  saúde     quanto o chão está vivo (mato, árvore, sem cinza, ácido, teia, fábrica): decide onde a vida pequena,
##            os pássaros e, depois, os ratos ficam. Era dos Passaros; agora é de todos.
##  orçamento `detalhe(p)`: 2 = perto da câmera (lógica e desenho completos), 1 = meio, 0 = longe (só contagem).
##  recuperação (fase 7) o chão que morreu (fogo, cinza, sujeira, ácido, construção) e foi limpo volta em etapas, por
##            célula de `cel` m: insetos → mato → ratos → pássaros → árvores (`etapa_em`). Quem nunca foi ferido está
##            completo. Quando a célula chega às árvores, brotam mudas do bioma nela (a mata volta). Vai no save.
##  distúrbio (fase 7) barulho de máquina trabalhando e poluição do ar (`disturbio`): a fauna se afasta; em volta da
##            fábrica fica quieto.

enum Rec { MORTA, INSETOS, MATO, RATOS, PASSAROS, ARVORES }

var gerador: GeradorMundo
var mapa: MapaOcupacao
var ambiente: AmbienteVivo
var infestacao: Infestacao
var foco := Vector2.ZERO
var fontes: Dictionary = {}              ## tipo → Callable() -> Array[{id, pos: Vector2, especie?, n?}]
var contagem: Dictionary = {}            ## tipo → quantos no último índice
var comida: Dictionary = {}              ## id → {id, tipo, pos, valor, idade}
var fertil: Dictionary = {}              ## tile (Vector2i) → 0..1: adubado pela podridão (fase 4)
var eventos: Array[Dictionary] = []      ## os avisos do último tick
var _novos: Array[Dictionary] = []
var _indice: Dictionary = {}             ## célula (Vector2i) → Array[{tipo, id, pos, especie, n}]
var _t := 0.0
var _t_comida := 0.0
var _prox_comida := 1
var _d: Dictionary
var recuperacao: Dictionary = {}         ## célula (Vector2i) → s desde que voltou a ficar boa (−1 = morta ainda)
var _t_rec := 0.0


func _init(p_gerador: GeradorMundo, p_mapa: MapaOcupacao, p_ambiente: AmbienteVivo = null, p_infestacao: Infestacao = null) -> void:
	gerador = p_gerador
	mapa = p_mapa
	ambiente = p_ambiente
	infestacao = p_infestacao
	_d = Registro.fauna.get("ecossistema", {})


func _n(chave: String, padrao: float) -> float:
	return float(_d.get(chave, padrao))


# ------------------------------------------------------------------ índice
func registrar_fonte(tipo: String, f: Callable) -> void:
	fontes[tipo] = f
	_t = 0.0                                             # refaz no próximo tick


func tick(dt: float, p_foco: Vector2) -> void:
	foco = p_foco
	eventos = _novos
	_novos = []
	_t -= dt
	if _t <= 0.0:
		_t = _n("indice_s", 0.5)
		reindexar()
	_t_comida += dt
	if _t_comida >= 1.0:
		envelhecer(_t_comida)
		_t_comida = 0.0
	_t_rec -= dt
	if _t_rec <= 0.0:
		var passo := float(_r().get("passo_s", 2.0))
		_t_rec = passo
		recuperar(passo)


func reindexar() -> void:
	_indice.clear()
	contagem.clear()
	var cel := _n("cel", 8.0)
	for tipo in fontes:
		var f: Callable = fontes[tipo]
		if not f.is_valid():
			continue
		var lista: Array = f.call()
		contagem[tipo] = lista.size()
		for s in lista:
			var p: Vector2 = s.pos
			var k := Vector2i(floori(p.x / cel), floori(p.y / cel))
			if not _indice.has(k):
				_indice[k] = []
			_indice[k].append({"tipo": tipo, "id": s.get("id", -1), "pos": p, "especie": String(s.get("especie", "")),
					"n": int(s.get("n", 1)), "espreita": bool(s.get("espreita", false))})


## Quem está a até `raio` de `c` (do último índice), de um tipo ou de todos ("").
func perto(c: Vector2, raio: float, tipo := "") -> Array:
	var cel := _n("cel", 8.0)
	var out: Array = []
	var k0 := Vector2i(floori((c.x - raio) / cel), floori((c.y - raio) / cel))
	var k1 := Vector2i(floori((c.x + raio) / cel), floori((c.y + raio) / cel))
	for y in range(k0.y, k1.y + 1):
		for x in range(k0.x, k1.x + 1):
			for s in _indice.get(Vector2i(x, y), []):
				if (tipo == "" or s.tipo == tipo) and (s.pos as Vector2).distance_to(c) <= raio:
					out.append(s)
	return out


## Distância até o mais perto de um tipo (INF se nenhum no raio).
func distancia(c: Vector2, tipo: String, raio: float) -> float:
	var m := INF
	for s in perto(c, raio, tipo):
		m = minf(m, (s.pos as Vector2).distance_to(c))
	return m


## Orçamento: 2 perto da câmera, 1 no meio, 0 longe.
func detalhe(p: Vector2) -> int:
	var d := p.distance_to(foco)
	if d <= _n("raio_perto", 40.0):
		return 2
	return 1 if d <= _n("raio_medio", 80.0) else 0


# ------------------------------------------------------------------ eventos
func avisar(ev: Dictionary) -> void:
	_novos.append(ev)


func morreu(tipo: String, especie: String, pos: Vector2, extra := {}) -> void:
	var ev := {"tipo": "morreu", "quem": tipo, "especie": especie, "pos": pos}
	ev.merge(extra)
	avisar(ev)


# ------------------------------------------------------------------ comida (fases 3 e 4)
func por_comida(tipo: String, pos: Vector2, valor := 1.0) -> int:
	var id := _prox_comida
	_prox_comida += 1
	comida[id] = {"id": id, "tipo": tipo, "pos": pos, "valor": valor, "idade": 0.0}
	return id


## A comida envelhece; a que tem `vida` e passou dela apodrece e some. O adubo do chão vai sumindo.
func envelhecer(dt: float) -> void:
	if not fertil.is_empty():
		var some := dt / _n("fertil_some_s", 2880.0)
		for t in fertil.keys():
			var v := float(fertil[t]) - some
			if v <= 0.0:
				fertil.erase(t)
			else:
				fertil[t] = v
	var podres: Array = []
	for f in comida.values():
		f.idade = float(f.idade) + dt
		if float(f.get("vida", 0.0)) > 0.0 and float(f.idade) >= float(f.vida):
			podres.append(f)
	for f in podres:
		comida.erase(int(f.id))
		avisar({"tipo": "apodreceu", "comida": f.tipo, "especie": String(f.get("especie", "")), "pos": f.pos})


## Aduba o chão em volta de `c` (mais no meio): onde a carcaça apodreceu.
func adubar(c: Vector2, raio: float, v: float) -> void:
	var r := int(ceil(raio))
	var ct := Vector2i(c.floor())
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			var t := ct + Vector2i(x, y)
			var d := (Vector2(t) + Vector2(0.5, 0.5)).distance_to(c)
			if d <= raio:
				fertil[t] = minf(1.0, float(fertil.get(t, 0.0)) + v * (1.0 - 0.5 * d / maxf(raio, 0.01)))


func fertil_em(t: Vector2i) -> float:
	return float(fertil.get(t, 0.0))


## 0..1: quanto já apodreceu (0 até `inicio` da vida, 1 no fim). Comida sem `vida` não apodrece.
static func podre(f: Dictionary, inicio := 0.65) -> float:
	var v := float(f.get("vida", 0.0))
	if v <= 0.0:
		return 0.0
	return clampf((float(f.idade) / v - inicio) / (1.0 - inicio), 0.0, 1.0)


func comida_perto(c: Vector2, raio: float, tipo := "") -> Array:
	var out: Array = []
	for f in comida.values():
		if (tipo == "" or f.tipo == tipo) and (f.pos as Vector2).distance_to(c) <= raio:
			out.append(f)
	return out


func comer(id: int, quem: String) -> bool:
	if not comida.has(id):
		return false
	var f: Dictionary = comida[id]
	comida.erase(id)
	avisar({"tipo": "comeu", "quem": quem, "comida": f.tipo, "pos": f.pos})
	return true


# ------------------------------------------------------------------ saúde do chão
## Saúde do lugar (0..1): mato e árvore (de pé, de muda crescida) contam; cinza, sujeira, ácido, teia, construção e
## água tiram. Média de 9 pontos em volta (2 m de passo).
func saude(t: Vector2i) -> float:
	var soma := 0.0
	for j in range(-2, 3, 2):
		for i in range(-2, 3, 2):
			soma += saude_tile(t + Vector2i(i, j))
	return soma / 9.0


func saude_tile(t: Vector2i) -> float:
	if mapa.tiles.has(t) or gerador.aplainado_em(t) != null:
		return 0.0
	if gerador.terreno(t) != GeradorMundo.Terreno.TERRA:
		return 0.15
	var v := 0.4
	if not mapa.limpos.has(t):
		var o := gerador.distribuicao.obstaculo(t)
		if not o.is_empty() and Registro.modelos.get(o.nome, {}).get("categoria", "") == "mapa/vegetacao":
			v = 1.0 if mapa.arvores.get(Vector2i(o.ancora), {}).is_empty() else 0.2
	if ambiente != null:
		if float(ambiente.plantas.get(t, 0.0)) > 0.3:
			v = 1.0
		v *= (1.0 - ambiente.valor(t, AmbienteVivo.QUEIM)) * (1.0 - 0.7 * ambiente.valor(t, AmbienteVivo.SUJ))
		if ambiente.fogo.has(t):
			return 0.0
	if not fertil.is_empty():
		v += 0.3 * float(fertil.get(t, 0.0))
	if infestacao != null:
		v *= 1.0 - infestacao.valor(t)
	return clampf(v, 0.0, 1.0)


## Chão morto onde a semente pega: dá para plantar, está queimado ou sem vida em volta, e o ácido/teia já não está ali.
func morto(t: Vector2i) -> bool:
	if ambiente == null or not ambiente.pode_plantar(t):
		return false
	if infestacao != null and infestacao.valor(t) > 0.15:
		return false
	return ambiente.valor(t, AmbienteVivo.QUEIM) > 0.15 or saude(t) < 0.3


func perto_de_construcao(t: Vector2i, r: int) -> bool:
	for j in range(-r, r + 1, 2):
		for i in range(-r, r + 1, 2):
			if mapa.tiles.has(t + Vector2i(i, j)):
				return true
	return false


## Água a até `r` tiles (passo 1): margem de rio, lago ou lagoa.
func perto_da_agua(t: Vector2i, r: int) -> bool:
	for j in range(-r, r + 1):
		for i in range(-r, r + 1):
			if gerador.eh_agua(gerador.terreno(t + Vector2i(i, j))):
				return true
	return false


# ------------------------------------------------------------------ árvores e arbustos perto (fases 2 e 3)
## A árvore de pé no tile `t` (âncora da árvore natural): o nome do modelo, ou "" se não há (cortada, queimada,
## caída, corroída, construção em cima, árvore morta). Fase 6: os ninhos dos pássaros conferem a árvore deles.
func arvore_em(t: Vector2i) -> String:
	if mapa.limpos.has(t) or mapa.tiles.has(t) or not mapa.arvores.get(t, {}).is_empty():
		return ""
	var o := gerador.distribuicao.obstaculo(t)
	if o.is_empty() or Vector2i(o.ancora) != t:
		return ""
	var nome := String(o.nome)
	if not Distribuicao.eh_arvore(nome) or nome == "arvore_morta":
		return ""
	return nome


## Perfil da folhagem pela árvore, o mesmo do material 3D (Materiais.PERFIL_FOLHA, pelo material de cada modelo):
## -1 copa que não muda (campina, fungo), 0 perene (pinheiro), 1 caduca laranja (carvalho), 2 salgueiro (amarela e
## perde um pouco no inverno), 3 acácia (seca e perde no verão), 4 caduca amarela (bétula).
const PERFIS := {"arv_carvalho": 1, "arv_betula": 4, "arv_salgueiro": 2, "arv_acacia": 3, "arv_pinheiro": 0}
var _veg_cache := {}             ## "arvore|raio" / "arbusto|raio" → {chave, lista}


static func perfil_folha(nome: String) -> int:
	for pre in PERFIS:
		if nome.begins_with(pre):
			return PERFIS[pre]
	return -1


## Espécie da árvore pelo nome do modelo ("arv_carvalho_3" → "arv_carvalho"), a mesma de AmbienteVivo.especies.
static func especie_arvore(nome: String) -> String:
	var u := nome.get_slice("_", nome.get_slice_count("_") - 1)
	return nome.substr(0, nome.length() - u.length() - 1) if u.is_valid_int() else nome


## Árvores de pé (não queimadas, caídas, corroídas nem limpas) a até `raio` de `c`:
## [{tile, pos: Vector2, nome, alto (m), copa (raio m), perfil (perfil_folha), caduca: perde folha em alguma
## estação}]. Guarda a última busca de cada raio (a câmera parada não refaz) e refaz quando o mapa muda.
func arvores_perto(c: Vector2, raio: float) -> Array:
	return _vegetacao_perto(c, raio, false)


## Arbustos de pé a até `raio` de `c` (fase 3: dão bagas), no mesmo formato.
func arbustos_perto(c: Vector2, raio: float) -> Array:
	return _vegetacao_perto(c, raio, true)


func _vegetacao_perto(c: Vector2, raio: float, arbusto: bool) -> Array:
	var k := "%s|%d" % ["arbusto" if arbusto else "arvore", int(raio)]
	var chave := "%s|%d|%d|%d" % [str(Vector2i((c / 3.0).floor())), mapa.versao, mapa.arvores.size(), mapa.limpos.size()]
	var cc: Dictionary = _veg_cache.get(k, {})
	if cc.get("chave", "") == chave:
		return cc.lista
	var out: Array = []
	var r := int(ceil(raio))
	var ct := Vector2i(c.round())
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			var t := ct + Vector2i(x, y)
			if Vector2(x, y).length() > raio or mapa.limpos.has(t) or mapa.tiles.has(t):
				continue
			var o := gerador.distribuicao.obstaculo(t)
			if o.is_empty() or Vector2i(o.ancora) != t:
				continue
			var nome := String(o.nome)
			var md: Dictionary = Registro.modelos.get(nome, {})
			if md.get("categoria", "") != "mapa/vegetacao" or nome.begins_with("arbusto") != arbusto:
				continue
			if not arbusto and not nome.begins_with("arv"):          # "arv_*" e "arvore_*"
				continue
			if nome == "arvore_morta" or not mapa.arvores.get(t, {}).is_empty():
				continue
			var dims: Array = md.get("dims", [1, 1, 2])
			var perfil := perfil_folha(nome)
			out.append({"tile": t, "pos": Vector2(t) + Vector2(0.5, 0.5), "nome": nome, "alto": float(dims[2]),
					"copa": maxf(float(dims[0]), float(dims[1])) * 0.5, "perfil": perfil, "caduca": perfil >= 1})
	_veg_cache[k] = {"chave": chave, "lista": out}
	return out


# ------------------------------------------------------------------ recuperação em etapas (fase 7)
func _r() -> Dictionary:
	return Registro.fauna.get("recuperacao", {})


func celula_de(p: Vector2) -> Vector2i:
	var cel := _n("cel", 8.0)
	return Vector2i(floori(p.x / cel), floori(p.y / cel))


## Saúde média da célula (9 pontos dentro dela).
func saude_celula(k: Vector2i) -> float:
	var cel := _n("cel", 8.0)
	var soma := 0.0
	for j in 3:
		for i in 3:
			soma += saude_tile(Vector2i(floori((k.x + 0.17 + 0.33 * i) * cel), floori((k.y + 0.17 + 0.33 * j) * cel)))
	return soma / 9.0


## Um passo da recuperação: perto do foco, a célula que está morta (saúde abaixo de `morta`) volta para o começo; a
## que está ferida e já ficou boa (saúde ≥ `boa`, sem distúrbio forte) anda no relógio. Longe da câmera o relógio só
## anda. Ao passar de cada etapa avisa ("etapa"); nas árvores, brotam mudas do bioma e a célula sai da lista.
func recuperar(dt: float) -> void:
	var r := _r()
	if not bool(r.get("liga", true)):
		return
	var cel := _n("cel", 8.0)
	var raio := int(ceil(float(r.get("raio", 56.0)) / cel))
	var k0 := celula_de(foco)
	var vistas := {}
	for j in range(-raio, raio + 1):
		for i in range(-raio, raio + 1):
			if i * i + j * j > raio * raio:
				continue
			var k := k0 + Vector2i(i, j)
			vistas[k] = true
			var h := saude_celula(k)
			var centro := (Vector2(k) + Vector2(0.5, 0.5)) * cel
			if h < float(r.get("morta", 0.2)):
				if not recuperacao.has(k) and _ocupada(k):
					continue                                 # fábrica ou água: não é chão ferido
				recuperacao[k] = -1.0
			elif recuperacao.has(k):
				var t := float(recuperacao[k])
				if t < 0.0:
					if h >= float(r.get("boa", 0.33)) and disturbio(centro) < float(r.get("disturbio_max", 0.35)):
						recuperacao[k] = 0.0
						avisar({"tipo": "etapa", "cel": k, "etapa": Rec.INSETOS, "pos": centro})
				else:
					_andar(k, t, dt, centro)
	for k in recuperacao.keys():                         # longe: o relógio de quem já está voltando só anda
		if not vistas.has(k) and float(recuperacao[k]) >= 0.0:
			_andar(k, float(recuperacao[k]), dt, (Vector2(k) + Vector2(0.5, 0.5)) * cel)


func _andar(k: Vector2i, t: float, dt: float, centro: Vector2) -> void:
	var antes := _etapa_de(t)
	t += dt
	var agora := _etapa_de(t)
	recuperacao[k] = t
	if agora != antes:
		avisar({"tipo": "etapa", "cel": k, "etapa": agora, "pos": centro})
		if agora == Rec.ARVORES:
			recuperacao.erase(k)                             # completa
			if ambiente != null:                             # a mata volta: mudas do bioma brotam na célula
				for i in int(_r().get("mudas", 2)):
					ambiente.plantar_perto(centro, _n("cel", 8.0) * 0.45, true)


## A célula é mais fábrica (piso, máquina) ou água que chão: não conta como chão morto a recuperar.
func _ocupada(k: Vector2i) -> bool:
	var cel := _n("cel", 8.0)
	var n := 0
	for j in 3:
		for i in 3:
			var t := Vector2i(floori((k.x + 0.17 + 0.33 * i) * cel), floori((k.y + 0.17 + 0.33 * j) * cel))
			if mapa.tiles.has(t) or gerador.terreno(t) != GeradorMundo.Terreno.TERRA:
				n += 1
	return n >= 5


func _etapa_de(t: float) -> int:
	if t < 0.0:
		return Rec.MORTA
	var e: Array = _r().get("etapas_s", [0, 90, 240, 420, 720])
	var et := Rec.INSETOS
	for i in range(1, e.size()):
		if t >= float(e[i]):
			et = Rec.INSETOS + i
	return mini(et, Rec.ARVORES)


## Em que etapa da volta está o chão em `p`: ARVORES (completo) se nunca foi ferido; MORTA se ainda está morto.
func etapa_em(p: Vector2) -> int:
	var k := celula_de(p)
	if not recuperacao.has(k):
		return Rec.ARVORES
	return _etapa_de(float(recuperacao[k]))


## O capim voltando (0 = ainda pelado, 1 = cheio): cresce do começo da volta até a etapa do mato.
func mato_em(p: Vector2) -> float:
	var k := celula_de(p)
	if not recuperacao.has(k):
		return 1.0
	var t := float(recuperacao[k])
	var e: Array = _r().get("etapas_s", [0, 90, 240, 420, 720])
	return 0.0 if t < 0.0 else clampf(t / maxf(1.0, float(e[Rec.MATO - 1])), 0.0, 1.0)


## Distúrbio em `p` (0..1): barulho de máquina trabalhando e poluição do ar. Preenchido pelo mundo (`fonte_disturbio`);
## sem ela, 0.
var fonte_disturbio: Callable
var fonte_fuligem: Callable             ## a fumaça no ar (0..1): o capim fica cinza (fase 7)

func disturbio(p: Vector2) -> float:
	return clampf(float(fonte_disturbio.call(p)), 0.0, 1.0) if fonte_disturbio.is_valid() else 0.0


func fuligem(p: Vector2) -> float:
	return clampf(float(fonte_fuligem.call(p)), 0.0, 1.0) if fonte_fuligem.is_valid() else 0.0


# ------------------------------------------------------------------ salvamento
func estado() -> Dictionary:
	return {"comida": comida, "prox": _prox_comida, "fertil": fertil, "recuperacao": recuperacao}


func restaurar(d: Dictionary) -> void:
	comida.clear()
	var c: Dictionary = d.get("comida", {})
	for k in c:
		comida[int(k)] = c[k]
	_prox_comida = int(d.get("prox", 1))
	recuperacao = d.get("recuperacao", {}).duplicate()
	fertil.clear()
	var fe: Dictionary = d.get("fertil", {})
	for k in fe:
		fertil[k if k is Vector2i else str_to_var("Vector2i" + str(k))] = float(fe[k])
