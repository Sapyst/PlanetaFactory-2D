class_name AmbienteVivo
extends RefCounted
## Ambiente vivo (lógica pura, passo de 1 s): o que a fábrica faz com o planeta sem o jogador querer.
##  - sujeira: máquinas que poluem sujam o chão em volta; a chuva lava devagar; o resto some muito devagar
##    (o ambiente tende a sujar com o tempo);
##  - óleo: vazamentos ao acaso de máquinas trabalhando (manchas que demoram a sumir);
##  - água suja: despejo de máquinas perto de água; corre rio abaixo (fluxo da hidrologia) e se espalha no lago;
##  - enxurrada: com chuva, a sujeira do chão escorre morro abaixo (relevo contínuo) e o lixo acaba no rio/lago;
##  - fogo: máquinas quentes podem acender a vegetação seca em volta (estação + chão seco); o fogo anda com o vento,
##    queima o tile (vira chão queimado), machuca construção encostada e apaga com chuva;
##  - tufão: vento extremo — espalha fogo e sujeira e danifica estruturas frágeis.
##  - consequências: bomba de seiva com poça contaminada rende menos e se desgasta; o chão sujo em volta de um ninho
##    deixa as aranhas furiosas (furia_em, lida pela Colonia);
##  - limpeza: coletor aspira sujeira e óleo, filtro limpa a água, viveiro planta mudas que crescem, viram árvore,
##    limpam o chão em volta e absorvem poluição do ar.
##  - água (fase 2.3): bomba d'água com água suja na tomada rende menos; supressor de incêndio com água apaga o fogo
##    no raio dele e, enquanto tem água, a vegetação em volta não pega fogo (molhada).
##  - limpeza nova (fase 2.6): coletor de lixo 2 também tira a cinza (queimado) e compacta o que recolhe em resíduo;
##    purificadores tiram poluição do ar do chunk (o atmosférico condensa em resíduo); viveiro 2 planta no dobro do
##    ritmo mudas da espécie do bioma que crescem 2× mais rápido; semeador de bioma tira o queimado do chão, devolve as
##    árvores carbonizadas/caídas e planta mudas do bioma; estação de tratamento limpa a água suja em 16 m.
##  - clima local (fase 2.5, ClimaLocal): o fogo sente a chuva e o vento do lugar (semeador de nuvens: chove ali,
##    nada pega fogo e o que queima apaga; defletor: o fogo anda para onde ele aponta); tufão não machuca construção
##    no raio do defletor ou do regulador. Os raios (Raios) acendem fogo e deixam o chão queimado.
## Os valores são por tile (dado de simulação); o desenho é contínuo (mistura suave + ruído, nunca em quadrados).
## Só existem chunks com algum valor: o custo segue a sujeira, não o tamanho do mapa.

const CANAIS := 4            ## sujeira, óleo, água suja, queimado
const SUJ := 0
const OLEO := 1
const AGUA := 2
const QUEIM := 3
const T := Grade.TAM_CHUNK

var gerador: GeradorMundo
var mapa: MapaOcupacao
var dados: Dictionary = {}           ## chunk → PackedFloat32Array(32·32·4)
var fogo: Dictionary = {}            ## tile → segundos restantes queimando
var sujos: Dictionary = {}           ## chunks mudados desde o último desenho
var eventos: Array[Dictionary] = []  ## {tipo: "fogo_inicio"|"dano", ...}
var dano: Callable                   ## func(id, pontos): o mundo aplica (pode destruir)
var _rng := RandomNumberGenerator.new()
var _acum := 0.0
var _d: Dictionary
var _agua_perto := {}                ## id da máquina → tile de água mais perto (ou nulo)
var _rumo := {}                      ## tile → para onde a enxurrada leva (tile vizinho mais baixo ou água; nulo = baixada)
var plantas: Dictionary = {}         ## tile → crescimento 0..1 (muda do viveiro; 1 = árvore adulta)
var versao_plantas := 0              ## muda quando alguma planta nasce, cai ou cresce um degrau (o desenho refaz)
var contaminacao: Dictionary = {}    ## id da bomba → contaminação 0..1 da poça (último passo)
var poluicao: Poluicao               ## (opcional) as árvores plantadas absorvem dela
var _plantou: Dictionary = {}        ## id do viveiro → ciclos já transformados em muda
var _versao_mapa := -1
var queima_arvore: Dictionary = {}   ## tile → segundos que a árvore já queimou (fogo longo derruba)
var encardido: Dictionary = {}       ## id da estrutura → 0 limpa .. 1 imunda (tempo e trabalho sujam, chuva lava)
var _estacao_ant := -1
var _protegidos: Array[Vector3] = []  ## (x, y, raio) dos supressores com água e energia: ali não pega fogo
var clima_local: ClimaLocal          ## (opcional) máquinas de clima: chuva/vento do lugar no fogo, tufão não machuca
var especies: Dictionary = {}        ## tile → espécie da muda (viveiro 2 / semeador: a árvore do bioma; sem = a lista padrão)
var rapidas: Dictionary = {}         ## tile → fator de crescimento da muda (viveiro 2: 2×)
var residuo_acum: Dictionary = {}    ## id → o que já recolheu/absorveu e ainda não virou 1 resíduo (fração)
var _restaurou: Dictionary = {}      ## id do semeador de bioma → ciclos já transformados em restauração
var ritmo_estacao := 1.0             ## patch fauna, fase 3: a muda cresce pela estação (e mais com o chão molhado)


func _init(p_gerador: GeradorMundo, p_mapa: MapaOcupacao, semente := 9) -> void:
	gerador = p_gerador
	mapa = p_mapa
	_rng.seed = semente
	_d = Registro.ambiente


# ------------------------------------------------------------------ leitura/escrita por tile
func valor(t: Vector2i, canal: int) -> float:
	var a: Variant = dados.get(Grade.chunk_de(t))
	if a == null:
		return 0.0
	var l := Grade.local_de(t)
	return (a as PackedFloat32Array)[(l.y * T + l.x) * CANAIS + canal]


func somar(t: Vector2i, canal: int, v: float) -> void:
	var k := Grade.chunk_de(t)
	var a: PackedFloat32Array = dados.get(k, PackedFloat32Array())
	if a.is_empty():
		if v <= 0.0:
			return
		a.resize(T * T * CANAIS)
	var l := Grade.local_de(t)
	var i := (l.y * T + l.x) * CANAIS + canal
	a[i] = clampf(a[i] + v, 0.0, 1.0)
	dados[k] = a
	sujos[k] = true


func _mancha(c: Vector2, raio: float, canal: int, v: float) -> void:
	var r := int(ceil(raio))
	for y in range(floori(c.y) - r, floori(c.y) + r + 1):
		for x in range(floori(c.x) - r, floori(c.x) + r + 1):
			var d := (Vector2(x, y) + Vector2(0.5, 0.5)).distance_to(c)
			if d < raio:
				somar(Vector2i(x, y), canal, v * (1.0 - d / raio))


# ------------------------------------------------------------------ passo
func tick(dt: float, fabrica: Fabrica, clima: Clima) -> void:
	_acum += dt
	while _acum >= 1.0:
		_acum -= 1.0
		_passo(fabrica, clima)


func _passo(fabrica: Fabrica, clima: Clima) -> void:
	var chuva: float = clima.valores.chuva if clima != null else 0.0
	var vento: Vector2 = clima.direcao_vento * (0.4 + clima.valores.vento) if clima != null else Vector2.ZERO
	var tufao := clima != null and clima.eh_tufao()
	var secura := clima.secura() if clima != null else 0.0
	if clima != null:
		_rebrota(clima.estacao)
		var es: Array = _d.plantas.get("estacoes", [1.0, 1.0, 1.0, 1.0])
		ritmo_estacao = float(es[clampi(clima.estacao, 0, 3)]) * (1.0 + float(_d.plantas.get("molhado_bonus", 0.0)) * clima.molhado)
	# fontes: quem trabalhou neste passo
	for id in fabrica.emissao:
		if not mapa.estruturas.has(id):
			continue
		var e: Dictionary = mapa.estruturas[id]
		var c := Grade.centro_da_area(e.minimo, e.area, e.rot)
		var raio: float = float(_d.sujeira_raio) + 0.5 * maxf(e.area.x, e.area.y)
		_mancha(c, raio, SUJ, float(fabrica.emissao[id]) * float(_d.sujeira_por_ponto))
		var ch: float = _d.oleo_chance.get(e.nome, 0.0)
		if ch > 0.0 and _rng.randf() < ch:
			var p: Vector2 = c + Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * (0.6 + 0.5 * e.area.x)
			_mancha(p, _rng.randf_range(0.9, 1.8), OLEO, 0.8)
		var desp: float = _d.despejo.get(e.nome, 0.0)
		if desp > 0.0:
			var w: Variant = _agua_mais_perto(id, c)
			if w != null:
				somar(w, AGUA, desp)
		# fogo: máquina quente acende vegetação seca em volta
		if e.nome in _d.fogo.maquinas_quentes and secura > 0.3 and _rng.randf() < float(_d.fogo.chance_maquina) * secura:
			var alvo: Vector2i = Vector2i((c + Vector2.from_angle(_rng.randf() * TAU) * (1.2 + 0.5 * e.area.x)).floor())
			if _inflamavel(alvo):
				_acender(alvo)
	_limpeza(fabrica)
	_bombas(fabrica)
	_supressores(fabrica)
	_plantas()
	_escorrer(chuva)
	_agua()
	_fogo(chuva, vento, secura, tufao)
	if tufao:
		_tufao(vento, clima)
	_decair(chuva)
	_encardir(fabrica, chuva)


## Estruturas encardem com o tempo (mais rápido trabalhando e em chão sujo); a chuva lava e o ciclo recomeça.
func _encardir(fabrica: Fabrica, chuva: float) -> void:
	var p: Dictionary = _d.get("encardido", {})
	if p.is_empty():
		return
	var tempo := 1.0 / float(p.cheio_s)
	var lava := chuva / float(p.chuva_limpa_s)
	for id in mapa.estruturas:
		var e: Dictionary = mapa.estruturas[id]
		if e.get("grupo", "") == "inimigo" or Registro.estruturas.get(e.nome, {}).get("grupo", "") == "inimigo":
			continue
		var v: float = encardido.get(id, 0.0)
		v += tempo + float(fabrica.emissao.get(id, 0.0)) * float(p.por_emissao)
		v += valor(Vector2i(Grade.centro_da_area(e.minimo, e.area, e.rot).floor()), SUJ) * float(p.do_chao)
		encardido[id] = clampf(v - lava, 0.0, 1.0)
	if encardido.size() > mapa.estruturas.size():
		for id in encardido.keys():
			if not mapa.estruturas.has(id):
				encardido.erase(id)


# ------------------------------------------------------------------ consequências e limpeza
## Tira `v` (por s) do canal em volta de `c`: cheio no meio, metade na borda do raio. Devolve quanto tirou (soma dos
## tiles; o coletor 2 compacta isso em resíduo).
func _limpar(c: Vector2, raio: float, canal: int, v: float) -> float:
	if v <= 0.0:
		return 0.0
	var r := int(ceil(raio))
	var tirou := 0.0
	for y in range(floori(c.y) - r, floori(c.y) + r + 1):
		for x in range(floori(c.x) - r, floori(c.x) + r + 1):
			var d := (Vector2(x, y) + Vector2(0.5, 0.5)).distance_to(c)
			if d < raio:
				var t := Vector2i(x, y)
				var antes := valor(t, canal)
				if antes <= 0.0:
					continue
				somar(t, canal, -v * (1.0 - 0.5 * d / raio))
				tirou += antes - valor(t, canal)
	return tirou


## Recuperação de solo (pesquisa recuperar_solo): o tile aplainado fica sem sujeira, óleo e marca de queimado.
func recuperar(t: Vector2i) -> void:
	for canal in [SUJ, OLEO, QUEIM]:
		if valor(t, canal) > 0.0:
			somar(t, canal, -1.0)


## Espécie de árvore do bioma do tile (as "arv_*" dos obstáculos do bioma, pelo peso); "" = bioma sem árvore.
func especie_do_bioma(t: Vector2i) -> String:
	var tipos: Dictionary = Registro.biomas.get(gerador.bioma(t), {}).get("obstaculos", {}).get("tipos", {})
	var lista: Array[String] = []
	for k in tipos:
		if String(k).begins_with("arv_"):
			for i in int(tipos[k]):
				lista.append(String(k))
	if lista.is_empty():
		return ""
	return lista[int(Distribuicao.h(t.x, t.y, 907) * lista.size()) % lista.size()]


## O que a máquina recolheu vira resíduo (1 a cada unidade de `mais`), até `maximo` na saída (braço tira).
func _compactar(id: int, m: Maquina, mais: float, maximo: int) -> void:
	var a := float(residuo_acum.get(id, 0.0)) + mais
	while a >= 1.0 - 1e-6 and int(m.saidas.get("residuo", 0)) < maximo:
		m.saidas["residuo"] = int(m.saidas.get("residuo", 0)) + 1
		a -= 1.0
	residuo_acum[id] = minf(a, 1.0)                     # saída cheia: o que sobra não acumula sem fim
	m.acordar()


## Coletor e filtro limpam em volta enquanto trabalham (na proporção da energia); viveiro: cada ciclo pronto = uma muda.
## Purificador tira poluição do chunk; semeador de bioma restaura o chão queimado (fase 2.6).
func _limpeza(fabrica: Fabrica) -> void:
	for id in fabrica.maquinas:
		var m: Maquina = fabrica.maquinas[id]
		var r: Dictionary = Registro.estruturas.get(m.nome, {})
		if not mapa.estruturas.has(id) or not (r.has("limpa") or r.has("planta") or r.has("purifica") or r.has("restaura")):
			continue
		var e: Dictionary = mapa.estruturas[id]
		var c := Grade.centro_da_area(e.minimo, e.area, e.rot)
		if r.has("planta"):
			var feitos: int = m.produzidos - int(_plantou.get(id, 0))
			_plantou[id] = m.produzidos
			var pl: Dictionary = r.planta
			for i in feitos:
				plantar_perto(c, float(pl.raio), bool(pl.get("especie_bioma", false)), float(pl.get("cresce", 1.0)))
			continue
		var forca: float = m.energia * float(fabrica.modo(id)[0]) * (1.0 + fabrica.bonus_de("limpeza"))      # modo eco/turbo limpa menos/mais; Purificação N: +10% por nível
		if r.has("restaura"):
			_restaurar(id, m, c, r.restaura, forca)
			continue
		if m.estado != Maquina.Estado.TRABALHANDO:
			continue
		if r.has("purifica"):
			var pu: Dictionary = r.purifica
			if poluicao != null:
				var tirou := poluicao.absorver(Grade.chunk_de(Vector2i(c.floor())), float(pu.por_min) / 60.0 * forca)
				if pu.has("residuo_por"):
					_compactar(id, m, tirou / float(pu.residuo_por), int(pu.get("max", 10)))
			continue
		var l: Dictionary = r.limpa
		var raio := float(l.raio)
		var recolheu := _limpar(c, raio, SUJ, float(l.get("sujeira", 0.0)) * forca)
		recolheu += _limpar(c, raio, OLEO, float(l.get("oleo", 0.0)) * forca)
		recolheu += _limpar(c, raio, QUEIM, float(l.get("queimado", 0.0)) * forca)
		_limpar(c, raio, AGUA, float(l.get("agua", 0.0)) * forca)
		if r.has("residuo"):
			_compactar(id, m, recolheu / float(r.residuo.get("por", 1.0)), int(r.residuo.get("max", 10)))


## Semeador de bioma: trabalhando, tira o queimado do chão no raio; cada ciclo pronto devolve árvores carbonizadas ou
## caídas (voltam inteiras) e planta mudas da espécie do bioma no chão mais queimado.
func _restaurar(id: int, m: Maquina, c: Vector2, rs: Dictionary, forca: float) -> void:
	var raio := float(rs.get("raio", 14.0))
	if m.estado == Maquina.Estado.TRABALHANDO:
		_limpar(c, raio, QUEIM, float(rs.get("queimado", 0.02)) * forca)
	var feitos: int = m.produzidos - int(_restaurou.get(id, 0))
	_restaurou[id] = m.produzidos
	for k in feitos:
		var voltaram: Array = []
		for t: Vector2i in mapa.arvores.keys():
			if voltaram.size() >= int(rs.get("arvores", 3)):
				break
			if (Vector2(t) + Vector2(0.5, 0.5)).distance_to(c) <= raio and not fogo.has(t):
				mapa.arvores.erase(t)
				queima_arvore.erase(t)
				voltaram.append(t)
		if not voltaram.is_empty():
			eventos.append({"tipo": "arvores_mudaram", "tiles": voltaram})
		for i in int(rs.get("mudas", 2)):
			plantar_perto(c, raio, true, 1.0)


## Contaminação da poça de uma bomba (0..1): água suja perto (pesa menos com a distância), óleo e sujeira debaixo dela.
func contaminacao_bomba(e: Dictionary) -> float:
	var b: Dictionary = _d.get("bomba", {})
	var c := 0.0
	for t in Grade.tiles_da_area(e.minimo, e.area, e.rot):
		c = maxf(c, maxf(valor(t, OLEO), valor(t, SUJ) * float(b.get("peso_sujeira", 0.6))))
	var meio := Grade.centro_da_area(e.minimo, e.area, e.rot)
	var r: int = b.get("raio", 4)
	for y in range(floori(meio.y) - r, floori(meio.y) + r + 1):
		for x in range(floori(meio.x) - r, floori(meio.x) + r + 1):
			var t := Vector2i(x, y)
			var a := valor(t, AGUA)
			if a > 0.0:
				var d := (Vector2(t) + Vector2(0.5, 0.5)).distance_to(meio)
				c = maxf(c, a * clampf(1.2 - d / float(r + 1), 0.0, 1.0))
	return clampf(c, 0.0, 1.0)


## Água suja na tomada da bomba d'água (0..1): o pior dos tiles de água logo além do lado sul e dos vizinhos deles.
func contaminacao_tomada(e: Dictionary) -> float:
	var c := 0.0
	for t in MapaOcupacao.tiles_da_tomada(e.minimo, e.area, e.rot):
		for y in range(-1, 2):
			for x in range(-1, 2):
				c = maxf(c, valor(t + Vector2i(x, y), AGUA))
	return clampf(c, 0.0, 1.0)


## Bomba com poça contaminada: rende menos (velocidade) e se desgasta trabalhando (perde vida).
## Bomba d'água com água suja na tomada: só rende menos (`agua_suja_perde` em estruturas.json).
func _bombas(fabrica: Fabrica) -> void:
	var b: Dictionary = _d.get("bomba", {})
	for id in fabrica.maquinas:
		var m: Maquina = fabrica.maquinas[id]
		if m.nome == "bomba_agua" and mapa.estruturas.has(id):
			var ca := contaminacao_tomada(mapa.estruturas[id])
			contaminacao[id] = ca
			var r: Dictionary = Registro.estruturas.bomba_agua
			m.velocidade = float(r.get("velocidade", 1.0)) * float(fabrica.modo(id)[0]) * (1.0 - float(r.get("agua_suja_perde", 0.6)) * ca)
			continue
		if m.nome != "bomba" or not mapa.estruturas.has(id):
			continue
		var c := contaminacao_bomba(mapa.estruturas[id])
		if c < float(b.get("minimo", 0.05)):
			c = 0.0
		contaminacao[id] = c
		m.velocidade = float(Registro.estruturas.bomba.get("velocidade", 1.0)) * float(fabrica.modo(id)[0]) * (1.0 - float(b.get("perda_producao", 0.75)) * c)
		if c > 0.0 and m.estado == Maquina.Estado.TRABALHANDO and dano.is_valid():
			dano.call(id, float(b.get("desgaste", 0.5)) * c)
	for id in contaminacao.keys():
		if not fabrica.maquinas.has(id):
			contaminacao.erase(id)


## Supressor de incêndio (passo de 1 s): com energia e água no reservatório vigia o raio; havendo fogo, gasta
## `agua_por_s` e tira `segundos_por_s` de cada foco no raio (apaga em 1–2 passos). Enquanto tiver água, o raio fica
## protegido (a vegetação molhada não pega fogo). O alvo (foco mais perto) vai em `fabrica.jatos` para o desenho.
func _supressores(fabrica: Fabrica) -> void:
	_protegidos.clear()
	fabrica.jatos.clear()
	for id in fabrica.maquinas:
		var m: Maquina = fabrica.maquinas[id]
		if m.receita_id != "borrifar_agua" or not mapa.estruturas.has(id):
			continue
		var e: Dictionary = mapa.estruturas[id]
		var ap: Dictionary = Registro.estruturas.get(e.nome, {}).get("apaga", {})
		var raio := float(ap.get("raio", 8.0))
		var gasto := float(ap.get("agua_por_s", 10.0))
		var c := Grade.centro_da_area(e.minimo, e.area, e.rot)
		var agua := float(m.fluidos.get("agua", 0.0))
		if not fabrica.ligada(id):
			m.estado = Maquina.Estado.DESLIGADA
			continue
		if m.energia <= 0.0:
			m.estado = Maquina.Estado.SEM_ENERGIA
			continue
		if agua < gasto:
			m.estado = Maquina.Estado.SEM_INSUMO
			continue
		_protegidos.append(Vector3(c.x, c.y, raio))
		var focos: Array[Vector2i] = []
		for t in fogo:
			if (Vector2(t) + Vector2(0.5, 0.5)).distance_to(c) <= raio:
				focos.append(t)
		if focos.is_empty():
			m.estado = Maquina.Estado.PRONTIDAO
			continue
		m.estado = Maquina.Estado.TRABALHANDO
		m.fluidos["agua"] = agua - gasto
		m.produzidos += 1
		var perto: Vector2i = focos[0]
		for t in focos:
			if (Vector2(t) + Vector2(0.5, 0.5)).distance_to(c) < (Vector2(perto) + Vector2(0.5, 0.5)).distance_to(c):
				perto = t
			fogo[t] = float(fogo[t]) - float(ap.get("segundos_por_s", 25.0))
			if fogo[t] <= 0.0:
				fogo[t] = 0.001                     # o passo do fogo apaga (cinza, árvore queimada) no mesmo segundo
		fabrica.jatos[id] = Vector2(perto) + Vector2(0.5, 0.5)


## Tile dentro do raio de um supressor com água (molhado: não pega fogo).
func protegido(t: Vector2i) -> bool:
	var p := Vector2(t) + Vector2(0.5, 0.5)
	for s in _protegidos:
		if p.distance_to(Vector2(s.x, s.y)) <= s.z:
			return true
	return false


## Fúria das aranhas de um ninho (0..1): média de sujeira + óleo + água suja num raio em volta (amostra a cada 3 tiles).
func furia_em(c: Vector2) -> float:
	var f: Dictionary = Registro.inimigos.get("furia", {})
	var r: int = f.get("raio", 24)
	var soma := 0.0
	var n := 0
	for y in range(-r, r + 1, 3):
		for x in range(-r, r + 1, 3):
			if x * x + y * y > r * r:
				continue
			var t := Vector2i((c + Vector2(x, y)).floor())
			n += 1
			if dados.has(Grade.chunk_de(t)):
				soma += valor(t, SUJ) + valor(t, OLEO) + valor(t, AGUA)
	return clampf(soma / maxf(1.0, n) / float(f.get("sujo_cheio", 0.12)), 0.0, 1.0)


## Pode nascer muda aqui? Terra seca e livre: fora do piso de fábrica (nenhuma construção a 3 tiles), sem
## obstáculo, jazida, fogo, terraplenagem nem outra planta encostada.
func pode_plantar(t: Vector2i) -> bool:
	if gerador.terreno(t) != GeradorMundo.Terreno.TERRA or gerador.superficie_em(t) != null or gerador.aplainado_em(t) != null:
		return false
	if fogo.has(t) or not gerador.distribuicao.jazida(t).is_empty() or _perto_de_construcao(t, PISO + 1):
		return false
	if not mapa.limpos.has(t) and not gerador.distribuicao.obstaculo(t).is_empty():
		return false
	for y in range(-1, 2):
		for x in range(-1, 2):
			if plantas.has(t + Vector2i(x, y)):
				return false
	return true


## Planta uma muda num tile livre perto de `c` (prefere o chão mais sujo/queimado). Devolve o tile ou nulo.
## `do_bioma`: a muda é da espécie de árvore do bioma daquele tile (viveiro 2, semeador); `cresce`: fator de crescimento.
func plantar_perto(c: Vector2, raio: float, do_bioma := false, cresce := 1.0) -> Variant:
	if plantas.size() >= int(_d.plantas.max):
		return null
	var melhor: Variant = null
	var nota := -1.0
	for i in 16:
		var p := c + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(1.8, raio)
		var t := Vector2i(p.floor())
		if not pode_plantar(t):
			continue
		var v := valor(t, SUJ) + valor(t, OLEO) + valor(t, QUEIM) + _rng.randf() * 0.02
		if v > nota:
			nota = v
			melhor = t
	if melhor != null:
		plantas[melhor] = 0.05
		_brotar(melhor)
		if do_bioma:
			var esp := especie_do_bioma(melhor)
			if esp != "":
				especies[melhor] = esp
		if cresce != 1.0:
			rapidas[melhor] = cresce
		versao_plantas += 1
	return melhor


## Muda num tile exato (semente que o vento levou, fase 3 do patch fauna). `especie` = "arv_betula"… ("" = padrão).
func plantar_em(t: Vector2i, especie := "") -> bool:
	if plantas.size() >= int(_d.plantas.max) or not pode_plantar(t):
		return false
	plantas[t] = 0.05
	_brotar(t)
	if especie != "":
		especies[t] = especie
	versao_plantas += 1
	return true


## A muda que brota abre um ponto vivo na cinza: o tile dela deixa de ser carvão (senão a folhagem dela nasceria
## carbonizada e sem folha: o material da vegetação lê o queimado do tile, fase 6 do patch fauna).
func _brotar(t: Vector2i) -> void:
	somar(t, QUEIM, -0.75)


## Mudas crescem (mais devagar no chão sujo; rápido na primavera, quase parando no inverno — `ritmo_estacao`); planta
## crescida limpa o chão em volta e absorve poluição do ar.
## Construção em cima corta a planta; água do canal afoga.
func _plantas() -> void:
	if plantas.is_empty():
		return
	var p: Dictionary = _d.plantas
	var cai: Array[Vector2i] = []
	var mapa_mudou := mapa.versao != _versao_mapa
	_versao_mapa = mapa.versao
	for t: Vector2i in plantas:
		# construção nova perto: o piso de fábrica chega até aqui (a planta é cortada); canal escavado afoga
		if gerador.superficie_em(t) != null or (mapa_mudou and (_perto_de_construcao(t, PISO) or gerador.aplainado_em(t) != null)):
			cai.append(t)
			continue
		var g: float = plantas[t]
		if g < 1.0:
			var suj := clampf(valor(t, SUJ) + valor(t, OLEO), 0.0, 1.0)
			var novo := minf(1.0, g + (1.0 - 0.6 * suj) / float(p.cresce_s) * float(rapidas.get(t, 1.0)) * ritmo_estacao)
			if int(novo * 10.0) != int(g * 10.0):
				versao_plantas += 1
			plantas[t] = novo
			g = novo
		if g < 0.3:
			continue
		if poluicao != null:
			poluicao.absorver(Grade.chunk_de(t), float(p.absorve_poluicao) * g)
		var meio := Vector2(t) + Vector2(0.5, 0.5)
		if valor(t, SUJ) + valor(t, OLEO) + valor(t, QUEIM) > 0.002 or _vizinho_sujo(t):
			_limpar(meio, float(p.raio_limpa), SUJ, float(p.limpa_sujeira) * g)
			_limpar(meio, float(p.raio_limpa), OLEO, float(p.limpa_oleo) * g)
			_limpar(meio, float(p.raio_limpa), QUEIM, float(p.limpa_queimado) * g)
	for t in cai:
		plantas.erase(t)
		especies.erase(t)
		rapidas.erase(t)
	if not cai.is_empty():
		versao_plantas += 1


const PISO := 2              ## o piso de fábrica se espalha 2 tiles em volta de cada construção (DesenhoChunk.ESPALHA)


func _perto_de_construcao(t: Vector2i, r: int) -> bool:
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			if mapa.tiles.has(t + Vector2i(x, y)):
				return true
	return false


func _vizinho_sujo(t: Vector2i) -> bool:
	for d in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
		if valor(t + d, SUJ) + valor(t + d, OLEO) + valor(t + d, QUEIM) > 0.002:
			return true
	return false


func _agua_mais_perto(id: int, c: Vector2) -> Variant:
	if _agua_perto.has(id):
		return _agua_perto[id]
	var melhor: Variant = null
	var md := INF
	var r: int = _d.despejo_raio
	for y in range(floori(c.y) - r, floori(c.y) + r + 1):
		for x in range(floori(c.x) - r, floori(c.x) + r + 1):
			var t := Vector2i(x, y)
			if gerador.eh_agua(gerador.terreno(t)):
				var d := Vector2(t).distance_squared_to(c)
				if d < md:
					md = d
					melhor = t
	_agua_perto[id] = melhor
	return melhor


## Enxurrada: chovendo, parte da sujeira de cada tile desce para o vizinho mais baixo; se o vizinho é água,
## vira água suja ali (o lixo chega ao rio e ao lago e segue com a correnteza). Baixada sem saída segura a sujeira.
func _escorrer(chuva: float) -> void:
	if chuva < 0.2:
		return
	var taxa: float = float(_d.get("enxurrada", 0.05)) * chuva
	var muda := {}
	for k in dados:
		var a: PackedFloat32Array = dados[k]
		var base: Vector2i = k * T
		for i in T * T:
			var v := a[i * CANAIS + SUJ]
			if v < 0.01:
				continue
			var t := base + Vector2i(i % T, i / T)
			var r: Variant = _rumo_de(t)
			if r == null:
				continue
			var q := v * taxa
			muda[t] = float(muda.get(t, 0.0)) - q
			if gerador.eh_agua(gerador.terreno(r)):
				somar(r, AGUA, q * float(_d.get("lixo_na_agua", 1.0)))
			else:
				muda[r] = float(muda.get(r, 0.0)) + q
	for t in muda:
		somar(t, SUJ, muda[t])


func _rumo_de(t: Vector2i) -> Variant:
	if _rumo.has(t):
		return _rumo[t]
	var r: Variant = null
	if not gerador.eh_agua(gerador.terreno(t)):
		var h := gerador.relevo_em(Vector2(t) + Vector2(0.5, 0.5))
		var menor := h - 1e-4
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
			var n: Vector2i = t + d
			if gerador.eh_agua(gerador.terreno(n)):
				r = n                                   # água encostada: a enxurrada cai nela
				break
			var hn := gerador.relevo_em(Vector2(n) + Vector2(0.5, 0.5))
			if hn < menor:
				menor = hn
				r = n
	_rumo[t] = r
	return r


## Água suja: rio leva para o tile rio abaixo; lago espalha para os vizinhos de água.
func _agua() -> void:
	var muda := {}
	for k in dados:
		var a: PackedFloat32Array = dados[k]
		var base: Vector2i = k * T
		for i in T * T:
			var v := a[i * CANAIS + AGUA]
			if v < 0.002:
				continue
			var t := base + Vector2i(i % T, i / T)
			var ter := gerador.terreno(t)
			if ter == GeradorMundo.Terreno.RIO:
				var f := gerador.direcao_rio(t)
				if f != Vector2.ZERO:
					var prox := Vector2i((Vector2(t) + Vector2(0.5, 0.5) + f).floor())
					var q: float = v * float(_d.agua_corre)
					muda[t] = float(muda.get(t, 0.0)) - q
					muda[prox] = float(muda.get(prox, 0.0)) + q
			else:
				var q: float = v * float(_d.agua_espalha)
				for d in Grade.DIRECOES:
					var n: Vector2i = t + d
					if gerador.eh_agua(gerador.terreno(n)):
						muda[t] = float(muda.get(t, 0.0)) - q
						muda[n] = float(muda.get(n, 0.0)) + q
	for t in muda:
		somar(t, AGUA, muda[t])


func _tem_arvore(t: Vector2i) -> bool:
	if mapa.limpos.has(t):
		return false
	var o := gerador.distribuicao.obstaculo(t)
	return not o.is_empty() and Distribuicao.eh_arvore(o.nome)


## Para onde a árvore carbonizada cai: a favor do vento, a não ser que haja construção nos 2 tiles daquele lado
## (tenta os outros rumos, do mais a favor para o menos); sem saída, cai em cima e a construção apanha.
func _rumo_queda(t: Vector2i, vento: Vector2) -> Vector2:
	var v := vento.normalized() if vento.length() > 1e-4 else Vector2.RIGHT
	var opcoes: Array[Vector2] = [v, v.rotated(PI / 4), v.rotated(-PI / 4), v.rotated(PI / 2), v.rotated(-PI / 2), -v]
	for d in opcoes:
		var livre := true
		for k in [1, 2]:
			if mapa.tiles.has(Vector2i((Vector2(t) + Vector2(0.5, 0.5) + d * k).floor())):
				livre = false
		if livre:
			return d
	var id: int = mapa.tiles.get(Vector2i((Vector2(t) + Vector2(0.5, 0.5) + v).floor()), -1)
	if id >= 0 and dano.is_valid():
		dano.call(id, float(_d.fogo.get("arvore_dano", 40.0)))
	return v


## Primavera: as árvores queimadas de pé rebrotam (as caídas ficam até alguém tirar).
func _rebrota(estacao: int) -> void:
	if _estacao_ant >= 0 and estacao != _estacao_ant and estacao == 0:
		var tiles: Array = []
		for t in mapa.arvores.keys():
			if mapa.arvores[t].e == "queimada":
				mapa.arvores.erase(t)
				tiles.append(t)
		if not tiles.is_empty():
			eventos.append({"tipo": "arvores_mudaram", "tiles": tiles})
	_estacao_ant = estacao


## Árvore/arbusto/cogumelo no tile queima mais tempo (é combustível); 1 = só grama.
func _madeira(t: Vector2i) -> float:
	if float(plantas.get(t, 0.0)) > 0.5:
		return float(_d.fogo.get("madeira", {}).get("arvore_campina_a", 4.0))
	if mapa.limpos.has(t):
		return 1.0
	var o := gerador.distribuicao.obstaculo(t)
	if o.is_empty():
		return 1.0
	var mad: Dictionary = _d.fogo.get("madeira", {})
	var m := float(mad.get(o.nome, mad.get(Distribuicao.especie(o.nome), 1.0)))
	return m * (0.5 if mapa.arvores.has(t) else 1.0)        # já carbonizada: sobra pouco para queimar


func _inflamavel(t: Vector2i) -> bool:
	if not mapa.limpos.has(t):
		var o := gerador.distribuicao.obstaculo(t)
		var mad: Dictionary = _d.fogo.get("madeira", {})
		if not o.is_empty() and float(mad.get(o.nome, mad.get(Distribuicao.especie(o.nome), 1.0))) <= 0.0:
			return false
	if fogo.has(t) or mapa.tiles.has(t) or gerador.terreno(t) != GeradorMundo.Terreno.TERRA:
		return false
	if not _protegidos.is_empty() and protegido(t):
		return false
	if clima_local != null and not clima_local.zonas.is_empty() and clima_local.chuva_em(Vector2(t) + Vector2(0.5, 0.5), 0.0) >= 0.5:
		return false                                          # chovendo ali (semeador, regulador em chuva): molhado
	if not gerador.distribuicao.jazida(t).is_empty() or valor(t, QUEIM) > 0.6:
		return false
	return gerador.bioma(t) in _d.fogo.inflamavel


func _acender(t: Vector2i) -> void:
	if fogo.size() >= int(_d.fogo.max_focos):
		return
	var dur: Array = _d.fogo.duracao_s
	fogo[t] = _rng.randf_range(dur[0], dur[1]) * _madeira(t)
	if fogo.size() == 1:
		eventos.append({"tipo": "fogo_inicio", "tile": t})


func _fogo(chuva: float, vento: Vector2, secura: float, tufao: bool) -> void:
	if fogo.is_empty():
		return
	var novos: Array[Vector2i] = []
	var apagar: Array[Vector2i] = []
	var esp: float = float(_d.fogo.espalha) * (0.3 + secura) * (3.0 if tufao else 1.0)
	var local := clima_local != null and not clima_local.zonas.is_empty()
	for t in fogo:
		var ch := chuva
		var vt := vento
		if local:
			var pt := Vector2(t) + Vector2(0.5, 0.5)
			ch = clima_local.chuva_em(pt, chuva)
			vt = clima_local.vento_em(pt, vento.normalized(), vento.length())
		fogo[t] -= 1.0 + ch * float(_d.fogo.chuva_apaga) * 10.0
		somar(t, QUEIM, 0.22)
		if _tem_arvore(t):
			queima_arvore[t] = float(queima_arvore.get(t, 0.0)) + 1.0
		if fogo[t] <= 0.0:
			apagar.append(t)
			continue
		for d in Grade.DIRECOES:
			var n: Vector2i = t + d
			var a_favor := maxf(0.0, Vector2(d).dot(vt))
			if _rng.randf() < esp * (1.0 + a_favor * float(_d.fogo.vento_mult)) * (1.0 - ch):
				if _inflamavel(n):
					novos.append(n)
			var id: int = mapa.tiles.get(n, -1)
			if id >= 0 and dano.is_valid():
				dano.call(id, float(_d.fogo.dano_estrutura))
	for t in apagar:
		fogo.erase(t)
		somar(t, QUEIM, 1.0)
		if plantas.erase(t):
			especies.erase(t)
			rapidas.erase(t)
			versao_plantas += 1
		# árvore: fogo curto deixa de pé, carbonizada (rebrota na primavera); fogo longo derruba vento abaixo.
		# o resto da vegetação (arbusto, cogumelo...) vira cinza e some (o mundo redesenha o chunk)
		if not mapa.limpos.has(t):
			var o := gerador.distribuicao.obstaculo(t)
			if not o.is_empty() and Distribuicao.eh_arvore(o.nome):
				var queimou: float = queima_arvore.get(t, 0.0)
				queima_arvore.erase(t)
				var antes: String = mapa.arvores.get(t, {}).get("e", "")
				if antes == "caida":
					continue
				if queimou >= float(_d.fogo.get("arvore_cai_s", 18.0)):
					var dir := _rumo_queda(t, vento)
					mapa.arvores[t] = {"e": "caida", "dir": dir}
					eventos.append({"tipo": "arvore_caiu", "tile": t, "dir": dir, "nome": o.nome})
				elif antes != "queimada":
					mapa.arvores[t] = {"e": "queimada"}
					eventos.append({"tipo": "arvores_mudaram", "tiles": [t]})
			elif not o.is_empty():
				mapa.limpar_obstaculo(t)
				_mancha(Vector2(t) + Vector2(0.5, 0.5), 1.8, QUEIM, 0.8)
				eventos.append({"tipo": "vegetacao_queimada", "tile": t, "tiles": Grade.tiles_da_area(o.ancora, o.area, 0)})
	for t in novos:
		_acender(t)


## Tufão: estruturas frágeis apanham — só enquanto uma rajada passa por cima delas (com `clima`; sem ele, em todas),
## e o mundo avisa (evento "tufao_dano"). A sujeira das áreas sujas é arrastada vento abaixo.
func _tufao(vento: Vector2, clima: Clima = null) -> void:
	var frageis: Array = _d.tufao.frageis
	var minimo := float(_d.tufao.get("rajada_minima", 1.2))
	var n := 0
	for id in mapa.estruturas.keys():
		if mapa.estruturas.has(id) and mapa.estruturas[id].nome in frageis and dano.is_valid():
			var e: Dictionary = mapa.estruturas[id]
			var c := Grade.centro_da_area(e.minimo, e.area, e.rot)
			if clima_local != null and clima_local.sem_tufao(c):
				continue                                      # defletor / regulador: sem ventania aqui
			if clima != null and clima.vento_em(c) < minimo:
				continue                                      # a rajada não está aqui agora
			dano.call(id, float(_d.tufao.dano))
			n += 1
	if n > 0:
		eventos.append({"tipo": "tufao_dano", "n": n})
	var leva: float = _d.tufao.espalha_sujeira
	var passo := Vector2i(Vector2(vento.normalized() * 2.0).round())
	for k in dados.keys():
		var a: PackedFloat32Array = dados[k]
		var base: Vector2i = k * T
		for i in T * T:
			var v := a[i * CANAIS + SUJ]
			if v > 0.05:
				var t := base + Vector2i(i % T, i / T)
				somar(t, SUJ, -v * leva)
				somar(t + passo, SUJ, v * leva)


func _decair(chuva: float) -> void:
	var s_suj: float = float(_d.sujeira_some) + float(_d.chuva_lava) * chuva
	var vazios: Array = []
	for k in dados:
		var a: PackedFloat32Array = dados[k]
		var soma := 0.0
		for i in T * T:
			var j := i * CANAIS
			a[j] = maxf(0.0, a[j] - s_suj)
			a[j + 1] = maxf(0.0, a[j + 1] - float(_d.oleo_some))
			a[j + 2] = maxf(0.0, a[j + 2] - float(_d.agua_some))
			a[j + 3] = maxf(0.0, a[j + 3] - float(_d.queimado_some))
			soma += a[j] + a[j + 1] + a[j + 2] + a[j + 3]
		dados[k] = a
		if soma <= 0.0:
			vazios.append(k)
		sujos[k] = true
	for k in vazios:
		dados.erase(k)


## Imagem RGBA8 34×34 do chunk (com 1 tile de margem) para o shader do chão: R sujeira, G óleo, B água, A queimado.
func imagem(k: Vector2i) -> Image:
	var img := Image.create(T + 2, T + 2, false, Image.FORMAT_RGBA8)
	var base: Vector2i = k * T - Vector2i.ONE
	for j in T + 2:
		for i in T + 2:
			var t := base + Vector2i(i, j)
			var a: Variant = dados.get(Grade.chunk_de(t))
			if a == null:
				continue
			var l := Grade.local_de(t)
			var o := (l.y * T + l.x) * CANAIS
			var arr: PackedFloat32Array = a
			# B divide faixas: água suja em 0..0,45 e brasa (tile queimando agora) em 0,5..1 — assim, na margem, onde o
			# filtro mistura tiles de água e de terra, água suja nunca vira fogo
			var b := arr[o + 2] * 0.45
			if fogo.has(t):
				b = 0.5 + 0.5 * clampf(float(fogo[t]) / 4.5, 0.0, 1.0)   # recém-aceso = 1, quase apagando = 0,5
			img.set_pixel(i, j, Color(arr[o], arr[o + 1], b, arr[o + 3]))
	return img


func estado() -> Dictionary:
	return {"dados": dados, "fogo": fogo, "rng": _rng.state, "plantas": plantas, "plantou": _plantou, "queima_arvore": queima_arvore,
			"encardido": encardido, "especies": especies, "rapidas": rapidas, "residuo_acum": residuo_acum, "restaurou": _restaurou}


func restaurar(d: Dictionary) -> void:
	dados = d.get("dados", {})
	fogo = d.get("fogo", {})
	plantas = d.get("plantas", {})
	_plantou = d.get("plantou", {})
	queima_arvore = d.get("queima_arvore", {})
	encardido = d.get("encardido", {})
	especies = d.get("especies", {})
	rapidas = d.get("rapidas", {})
	residuo_acum = d.get("residuo_acum", {})
	_restaurou = d.get("restaurou", {})
	versao_plantas += 1
	_rng.state = d.get("rng", _rng.state)
	for k in dados:
		sujos[k] = true
