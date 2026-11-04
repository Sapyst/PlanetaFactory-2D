class_name Construtor
extends RefCounted
## O que o jogador faz com a ferramenta de construção, sem desenho nenhum (testável sem janela):
##  - planejar uma peça solta, uma linha arrastada (esteira/cano fazem curva em L sozinhos) ou uma remoção em retângulo;
##  - cada item do plano diz se pode (motivo "") ou por que não — é isso que pinta o fantasma de verde/vermelho;
##  - executar o plano no MapaOcupacao e devolver um Relatório (o que entrou, saiu e foi limpo) para o desenho sincronizar;
##  - desfazer (histórico de relatórios).
##
## Peças "virtuais" do menu: "esteira" e "cano" escolhem sozinhas reta/curva/início/fim pelo caminho e pelos vizinhos.
## Traço de esteira inteligente: desvia de obstáculos (A* que evita curvas), nasce ligado em quem entrega no primeiro
## tile e termina virado para quem recebe ao lado do último; ponta "fim" encostada no começo vira curva para o traço,
## e "início" encostado de lado no fim vira curva para receber dele.

const FAMILIA_ESTEIRA := ["esteira_reta", "esteira_curva_dir", "esteira_curva_esq", "esteira_inicio", "esteira_fim", "esteira_juncao"]
const TUNEIS := ["esteira_tunel_entrada", "esteira_tunel_saida"]
const FAMILIA_CANO := ["cano_reto", "cano_curva"]
## Peças que se arrastam em linha reta (uma por tile, mesma rotação).
const LINHA_RETA := ["muro_centro", "muro_tijolo", "muro_liga", "muro_escudo", "trilho_reto", "trilho_energizado", "poste_energia",
		"poste_alto"]
## Poste arrastado: um a cada N tiles (até na diagonal o próximo fica no alcance do fio: 9 m e 30 m).
const PASSO_POSTE := {"poste_energia": 6, "poste_alto": 20}
const HISTORICO := 50
## Classes de esteira (pesquisa logistica_3…): as MESMAS peças (reta, curvas, início, fim, junção, rampa, passagem) com
## outro modelo (<peça>_<sufixo>, que tem regra própria em estruturas.json: velocidade, alcance da passagem) e o campo
## "classe" na estrutura do mapa. Sem o campo = 1 (básica). No menu a peça vem com o sufixo ("esteira_rapida").
const CLASSES_ESTEIRA := {2: "rapida", 3: "expressa", 4: "quantica"}
const PECAS_COM_CLASSE := ["esteira", "esteira_rampa", "rampa_desce", "esteira_tunel_entrada", "esteira_tunel_saida"]

var mapa: MapaOcupacao
var _historico: Array[Dictionary] = []
## Progressão (modo "novo"): construir custa itens do núcleo; remover devolve; limpar obstáculo rende material.
## `cobrar` = false no modo livre (demonstração e testes antigos).
var cobrar := false
var inventario: Dictionary = {}
var pesquisa: Pesquisa = null
## Postos avançados (núcleos-filhos): func(tile) -> {id, estoque: Dictionary} do posto que cobre o tile ({} = nenhum).
## A obra que cai perto de um posto paga primeiro com o estoque dele; o que faltar sai do núcleo (`inventario`).
var estoque_local: Callable
## func(id) -> Dictionary: o estoque do posto `id` agora (null se ele saiu) — o desfazer devolve para ele.
var estoque_do_posto: Callable
## Nível em que se constrói esteira (0 = chão, 1 = 0,5 m, 2 = 1,0 m). Rampa ↑ sobe do nível atual; ↓ desce dele.
var nivel := 0
const MARGEM_ROTA := 8           ## quanto o desvio pode sair do retângulo entre as pontas
const NOS_ROTA := 6000           ## limite de busca (traço impossível cai no L, que fica vermelho)
var _cache_rota := {}


func _init(p_mapa: MapaOcupacao) -> void:
	mapa = p_mapa


# ------------------------------------------------------------------ rotação e fluxo
## Rotação (quartos anti-horários) que faz uma peça "sul → norte" fluir na direção d (0 N, 1 L, 2 S, 3 O).
static func rot_do_fluxo(d: int) -> int:
	return posmod(-d, 4)


static func fluxo_da_rot(r: int) -> int:
	return posmod(-r, 4)


## Direção (0..3) de a para o vizinho b.
static func direcao(a: Vector2i, b: Vector2i) -> int:
	return Grade.DIRECOES.find(b - a)


static func arrastavel(nome: String) -> bool:
	nome = separar_classe(nome)[0]
	return nome in ["esteira", "cano"] or nome in LINHA_RETA


## Peça do menu com sufixo de classe → [peça base, classe]: "esteira_rapida" → ["esteira", 2]; sem sufixo → [nome, 1].
static func separar_classe(nome: String) -> Array:
	for c in CLASSES_ESTEIRA:
		var suf: String = "_" + CLASSES_ESTEIRA[c]
		if nome.ends_with(suf) and nome.trim_suffix(suf) in PECAS_COM_CLASSE:
			return [nome.trim_suffix(suf), c]
	return [nome, 1]


## Modelo (e regra de estruturas.json) de uma estrutura do mapa: esteira rápida → "esteira_reta_rapida".
static func modelo_de(e: Dictionary) -> String:
	return modelo_classe(e.nome, int(e.get("classe", 1)))


static func modelo_classe(nome: String, classe: int) -> String:
	return nome + "_" + CLASSES_ESTEIRA[classe] if classe > 1 and CLASSES_ESTEIRA.has(classe) else nome


## Esteira de que classe (1 básica, 2 rápida…) — regra do modelo da classe: velocidade e alcance da passagem.
static func regra_esteira(nome: String, classe: int) -> Dictionary:
	return Registro.estruturas.get(modelo_classe(nome, classe), Registro.estruturas.get(nome, {}))


## Tile do cursor → canto sudoeste da área (o cursor fica no meio da peça).
static func minimo_no_cursor(nome: String, tile: Vector2i, rot: int) -> Vector2i:
	var a := Grade.area_girada(Registro.area(_modelo_base(nome)), rot)
	return tile - Vector2i((a.x - 1) / 2, (a.y - 1) / 2)


static func _modelo_base(nome: String) -> String:
	match nome:
		"esteira": return "esteira_reta"
		"cano": return "cano_reto"
	return nome


# ------------------------------------------------------------------ caminhos
## Caminho em L de a até b, sem repetir tile. O primeiro trecho segue o eixo de maior distância.
static func caminho_l(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = [a]
	var d := b - a
	var passos: Array[Vector2i] = []
	var px := Vector2i(signi(d.x), 0)
	var py := Vector2i(0, signi(d.y))
	if absi(d.x) >= absi(d.y):
		for i in absi(d.x): passos.append(px)
		for i in absi(d.y): passos.append(py)
	else:
		for i in absi(d.y): passos.append(py)
		for i in absi(d.x): passos.append(px)
	var t := a
	for p in passos:
		t += p
		out.append(t)
	return out


## Linha reta de a no eixo dominante até a projeção de b.
static func caminho_reto(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var d := b - a
	var fim := Vector2i(b.x, a.y) if absi(d.x) >= absi(d.y) else Vector2i(a.x, b.y)
	return caminho_l(a, fim)


# ------------------------------------------------------------------ planos
## Item de plano: {nome, minimo, rot, motivo ("" = pode), acao ("colocar" | "substituir" | "igual"), id_antigo}.
func plano_peca(nome: String, tile: Vector2i, rot: int) -> Array[Dictionary]:
	var sc := separar_classe(nome)
	return _cobrar_plano(_com_classe(_plano_peca(sc[0], tile, rot), sc[1]), nome)


func _plano_peca(nome: String, tile: Vector2i, rot: int) -> Array[Dictionary]:
	if nome == "esteira_rampa" or nome == "rampa_desce":
		return [_item_rampa(nome == "rampa_desce", tile, rot)]
	if nome in Trem.COMPOSICOES:
		return [_item_trem(tile, nome)]
	if nome in ["esteira", "cano"]:
		return _plano_linha(nome, tile, tile, rot)
	var minimo := minimo_no_cursor(nome, tile, rot)
	return [_item(nome, minimo, rot)]


## Arrasto de a até b. `rot` só vale quando a == b (sem direção de arrasto).
func plano_linha(nome: String, a: Vector2i, b: Vector2i, rot: int) -> Array[Dictionary]:
	var sc := separar_classe(nome)
	return _cobrar_plano(_com_classe(_plano_linha(sc[0], a, b, rot), sc[1]), nome)


## Peças de esteira do plano ficam da classe escolhida (traçar esteira rápida por cima da básica troca a peça, e o
## contrário também); as curvas "extra" (fim/início vizinho que vira curva) mantêm a classe que já tinham.
func _com_classe(plano: Array[Dictionary], classe: int) -> Array[Dictionary]:
	for it in plano:
		if no_esteira({"nome": it.get("nome", ""), "rot": 0}).is_empty() or it.get("extra", false):
			continue
		if classe > 1:
			it["classe"] = classe
		else:
			it.erase("classe")
		if it.get("acao", "") == "igual" and int(it.get("classe_antiga", 1)) != classe:
			it.acao = "substituir"
	return plano


func _plano_linha(nome: String, a: Vector2i, b: Vector2i, rot: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if nome == "esteira":
		return _plano_esteira(a, b, rot)
	if nome == "cano":
		var cam := caminho_l(a, b)
		var dirs := _direcoes(cam, fluxo_da_rot(rot))
		for i in cam.size():
			var d_in: int = dirs[i - 1] if i > 0 else dirs[0]
			var d_out: int = dirs[i]
			var p := _peca_cano(d_in, d_out)
			out.append(_item_trocavel(p.nome, cam[i], p.rot, 0))
		return out
	if not nome in LINHA_RETA or a == b:
		return _plano_peca(nome, a, rot)
	var cam := caminho_reto(a, b)
	var d := direcao(cam[0], cam[1])
	var r := rot_do_fluxo(d) if nome in GrafoTrilhos.RETOS else rot
	for i in cam.size():
		if PASSO_POSTE.has(nome) and i % int(PASSO_POSTE[nome]) != 0 and i != cam.size() - 1:
			continue
		out.append(_item(nome, cam[i], r))
	return out


func _plano_esteira(a: Vector2i, b: Vector2i, rot: int) -> Array[Dictionary]:
	var n := nivel
	var cam := rota(a, b) if n == 0 else caminho_l(a, b)
	var dirs := _direcoes(cam, fluxo_da_rot(rot))
	var no_traco := {}
	for t in cam:
		no_traco[t] = true
	var extra: Array[Dictionary] = []
	# começo: quem já entrega no primeiro tile define a entrada; senão, um "fim" encostado de lado vira curva para cá
	var d_ini := -1
	for d in 4:
		if not no_traco.has(a - Grade.DIRECOES[d]) and _alimenta(a, d, n):
			d_ini = d
			break
	if d_ini < 0:
		for d in 4:
			var t := a - Grade.DIRECOES[d]
			var x := _estrutura_em(t, n)
			if no_traco.has(t) or x.is_empty() or x.nome != "esteira_fim":
				continue
			var dx := fluxo_da_rot(x.rot)
			if dx == posmod(d + 2, 4):
				continue                              # o fim aponta para longe: o traço está atrás dele
			var cv := _curva(dx, d)
			extra.append(_item_trocavel(cv.nome, t, cv.rot, n))
			extra[-1]["extra"] = true
			d_ini = d
			break
	if cam.size() == 1 and d_ini >= 0:
		dirs[0] = d_ini
	# fim: vira para quem recebe ao lado do último tile (em frente primeiro, depois os lados; nunca para trás)
	var ult := cam[-1]
	var d_fim := -1
	for d in [dirs[-1], posmod(dirs[-1] + 1, 4), posmod(dirs[-1] - 1, 4)]:
		var t: Vector2i = ult + Grade.DIRECOES[d]
		if no_traco.has(t):
			continue
		var y := _estrutura_em(t, n)
		if not y.is_empty() and y.nome == "esteira_inicio":
			var dy := fluxo_da_rot(y.rot)
			if d == posmod(dy + 2, 4):
				continue                              # o início aponta para cá: não dá para entrar
			if d != dy:
				var cv := _curva(d, dy)
				extra.append(_item_trocavel(cv.nome, t, cv.rot, n))
				extra[-1]["extra"] = true
			d_fim = d
			break
		if _recebe(ult, d, n, d == dirs[-1]):            # núcleo sem boca: só em frente, o traço não vira sozinho para ele
			d_fim = d
			break
	if d_fim >= 0:
		dirs[-1] = d_fim
	var out: Array[Dictionary] = []
	var degrau := false
	for i in cam.size():
		var p := _peca_esteira(cam, dirs, i, n, d_ini, d_fim >= 0)
		var it := _item_trocavel(p.nome, cam[i], p.rot, n)
		degrau = degrau or (i > 0 and mapa.gerador.nivel(cam[i]) != mapa.gerador.nivel(cam[i - 1]))
		if degrau and it.motivo == "":
			it.motivo = "desnivel"                       # depois do barranco o traço não continua
		out.append(it)
	if n > 0:
		_planejar_pilares(out, cam, dirs)
	out.append_array(extra)
	return out


static func _curva(d_in: int, d_out: int) -> Dictionary:
	var nome := "esteira_curva_dir" if d_out == posmod(d_in + 1, 4) else "esteira_curva_esq"
	return {"nome": nome, "rot": rot_do_fluxo(d_in)}


## Caminho de esteira no chão de a até b: o L de sempre se estiver livre (passar por cima de esteira vale: troca a
## peça); senão o menor desvio por tiles livres, pagando cada curva (fica com poucas curvas, "de fábrica").
## Sem caminho possível, devolve o L (que aparece vermelho onde bate).
func rota(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var l := caminho_l(a, b)
	var ok := true
	for i in l.size():
		var t := l[i]
		if (t != a and t != b and not _livre_rota(t, true)) or (i > 0 and mapa.gerador.nivel(t) != mapa.gerador.nivel(l[i - 1])):
			ok = false
			break
	if ok:
		return l
	var chave := [a, b, mapa.versao]
	if _cache_rota.has(chave):
		return _cache_rota[chave]
	if _cache_rota.size() > 64:
		_cache_rota.clear()
	var achou := _a_estrela(a, b, l)
	var r: Array[Vector2i] = achou if not achou.is_empty() else l
	_cache_rota[chave] = r
	return r


func _livre_rota(t: Vector2i, esteira_vale: bool) -> bool:
	if mapa.tiles.has(t):
		return esteira_vale and mapa.estruturas[mapa.tiles[t]].nome in FAMILIA_ESTEIRA
	return mapa.motivo_bloqueio("esteira_reta", t, 0) == ""


## `linha` = o L pretendido: sair dele custa um pouco, então o traço segue reto até perto do obstáculo e só ali contorna.
func _a_estrela(a: Vector2i, b: Vector2i, linha: Array[Vector2i]) -> Array[Vector2i]:
	var na_linha := {}
	for t in linha:
		na_linha[t] = true
	var lo := Vector2i(mini(a.x, b.x), mini(a.y, b.y)) - Vector2i.ONE * MARGEM_ROTA
	var hi := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y)) + Vector2i.ONE * MARGEM_ROTA
	# estado = (tile, direção de chegada); 4 = começo (sem direção)
	var ini := Vector3i(a.x, a.y, 4)
	var custo := {ini: 0.0}
	var veio := {}
	var heap: Array = [[_h(a, b), ini]]
	var livre := {}
	var nos := 0
	while not heap.is_empty() and nos < NOS_ROTA:
		var atual: Vector3i = _heap_tirar(heap)[1]
		var t := Vector2i(atual.x, atual.y)
		if t == b:
			var cam: Array[Vector2i] = []
			var s := atual
			while true:
				cam.push_front(Vector2i(s.x, s.y))
				if not veio.has(s):
					break
				s = veio[s]
			return cam
		nos += 1
		for d in 4:
			var v: Vector2i = t + Grade.DIRECOES[d]
			if v.x < lo.x or v.y < lo.y or v.x > hi.x or v.y > hi.y:
				continue
			if mapa.gerador.nivel(v) != mapa.gerador.nivel(t):
				continue                                  # barranco: esteira não sobe nem desce sozinha
			if v != b:
				if not livre.has(v):
					livre[v] = _livre_rota(v, false)
				if not livre[v]:
					continue
			var c: float = custo[atual] + 1.0 + (0.6 if atual.z != 4 and atual.z != d else 0.0) + (0.0 if na_linha.has(v) else 0.3)
			var e := Vector3i(v.x, v.y, d)
			if c < float(custo.get(e, INF)):
				custo[e] = c
				veio[e] = atual
				_heap_por(heap, [c + _h(v, b), e])
	return []


static func _h(a: Vector2i, b: Vector2i) -> float:
	return absi(a.x - b.x) + absi(a.y - b.y)


static func _heap_por(h: Array, x: Array) -> void:
	h.append(x)
	var i := h.size() - 1
	while i > 0:
		var p := (i - 1) / 2
		if h[p][0] <= h[i][0]:
			break
		var tmp = h[p]
		h[p] = h[i]
		h[i] = tmp
		i = p


static func _heap_tirar(h: Array) -> Array:
	var topo: Array = h[0]
	var ult: Array = h.pop_back()
	if h.is_empty():
		return topo
	h[0] = ult
	var i := 0
	while true:
		var m := i
		for f in [2 * i + 1, 2 * i + 2]:
			if f < h.size() and h[f][0] < h[m][0]:
				m = f
		if m == i:
			break
		var tmp = h[m]
		h[m] = h[i]
		h[i] = tmp
		i = m
	return topo


## Remoção em retângulo: estruturas inteiras que encostam no retângulo + obstáculos naturais.
## Itens: {acao: "remover", id, nome, minimo, rot} ou {acao: "limpar", tile, nome, minimo, rot}.
func plano_remocao(a: Vector2i, b: Vector2i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var vistos := {}
	for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
		for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
			var t := Vector2i(x, y)
			for id in mapa.ids_no_tile(t):
				if not vistos.has(id):
					vistos[id] = true
					var e: Dictionary = mapa.estruturas[id]
					var motivo := "inimigo" if Colonia.eh_toca(e.nome) else ""      # toca (ninho, cratera) só cai na bala
					if e.nome == "nucleo":
						motivo = "nucleo"
					out.append({"acao": "remover", "id": id, "nome": e.nome, "minimo": e.minimo, "rot": e.rot, "motivo": motivo,
							"nivel": e.get("nivel", 0), "desce": e.get("desce", false)})
			if mapa.tiles.has(t):
				continue
			if mapa.limpos.has(t):
				continue
			var o := mapa.gerador.distribuicao.obstaculo(t)
			if not o.is_empty() and not vistos.has(o.ancora):
				vistos[o.ancora] = true
				out.append({"acao": "limpar", "tile": t, "nome": o.nome, "minimo": o.ancora, "rot": o.rot, "motivo": ""})
	return out


## Aplainar (Terraplenagem): o retângulo vira patamar no nível do tile onde o arraste começou. Sem obra no local;
## corta/aterra e limpa a vegetação. Água não; construção em outro nível bloqueia aquele tile.
## Itens: {acao: "aplainar", tile, nivel, motivo, muda (o nível muda?)}.
## `fundo` > 0 = Escavar: o patamar fica `fundo` nível(is) abaixo de onde o arraste começou (buraco/canal; perto de
## rio ou lago, enche d'água — ver AguaJogo).
func plano_aplainar(a: Vector2i, b: Vector2i, fundo := 0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var alvo := maxi(mapa.gerador.nivel(a) - fundo, -3)
	var sem := not mapa.tem_terraplenagem()
	var sem_canal := fundo > 0 and pesquisa != null and not pesquisa.modo_liberado("escavar_canal")
	for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
		for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
			var t := Vector2i(x, y)
			var motivo := ""
			if sem:
				motivo = "sem_terraplenagem"
			elif sem_canal:
				motivo = "sem_pesquisa_canal"
			elif mapa.gerador.eh_agua(mapa.gerador.terreno(t)):
				motivo = "agua"
			elif fundo > 0 and mapa.gerador.superficie_em(t) != null:
				motivo = "agua"                      # já está cheio: escavar debaixo d'água não
			elif mapa.tiles.has(t) and mapa.gerador.nivel(t) != alvo:
				motivo = "ocupado"
			out.append({"acao": "aplainar", "tile": t, "minimo": t, "nome": "aplainar", "rot": 0, "nivel": alvo, "motivo": motivo,
					"muda": mapa.gerador.nivel(t) != alvo or mapa.gerador.em_encosta(t)})
	if cobrar and not sem:
		var gasto := 0
		var por: Dictionary = Registro.progressao.get("custo_aplainar", {})
		for it in out:
			if it.motivo == "" and it.muda:
				var cabe := true
				for k in por:
					if int(inventario.get(k, 0)) < (gasto + 1) * int(por[k]):
						cabe = false
				if not cabe:
					it.motivo = "sem_recursos"
				else:
					gasto += 1
	return out


# ------------------------------------------------------------------ custos
## Chave de custo: as peças de esteira/cano escolhidas sozinhas custam como "esteira"/"cano"; a classe da esteira
## entra como sufixo ("esteira_rapida", "esteira_rampa_rapida"…).
static func chave_custo(nome: String, classe := 1) -> String:
	var sc := separar_classe(nome)
	var n: String = sc[0]
	var c := maxi(classe, int(sc[1]))
	var k := n
	if n == "rampa_desce": k = "esteira_rampa"
	elif n in FAMILIA_ESTEIRA: k = "esteira"
	elif n in FAMILIA_CANO: k = "cano"
	return k + ("_" + CLASSES_ESTEIRA[c] if c > 1 and CLASSES_ESTEIRA.has(c) else "")


static func custo_de(nome: String, classe := 1) -> Dictionary:
	return Registro.progressao.get("custos", {}).get(chave_custo(nome, classe), {})


## Marca "em_desenvolvimento" (peça que ainda não está no jogo: sem modelo, ou só uma pesquisa em desenvolvimento a
## libera — no modo demonstração só a sem modelo), "bloqueado" (falta pesquisa) e "sem_recursos" (o estoque acaba no
## meio do traço: o que cabe fica verde).
func _cobrar_plano(plano: Array[Dictionary], escolhido: String) -> Array[Dictionary]:
	if pesquisa != null and pesquisa.peca_em_desenvolvimento(escolhido):
		for it in plano:
			it.motivo = "em_desenvolvimento"
		return plano
	if not cobrar:
		return plano
	if pesquisa != null and not pesquisa.peca_liberada(escolhido):
		for it in plano:
			it.motivo = "bloqueado"
		return plano
	var gasto := {}
	var gasto_l := {}                     # posto → {item: n} (o que a obra já tirou do estoque de cada posto)
	for it in plano:
		var troca: bool = it.get("acao", "") == "substituir" and int(it.get("classe", 1)) != int(it.get("classe_antiga", 1))
		if it.motivo != "" or not (it.get("acao", "colocar") in ["colocar", "trem"] or troca):
			continue
		var c := custo_de(it.nome, int(it.get("classe", 1)))
		var loc := _local(it.minimo)
		var do_l := {}
		var cabe := true
		for k in c:
			var tem_l := 0
			if not loc.is_empty():
				tem_l = maxi(0, int(loc.estoque.get(k, 0)) - int(gasto_l.get(loc.id, {}).get(k, 0)))
			do_l[k] = mini(tem_l, int(c[k]))
			if int(gasto.get(k, 0)) + int(c[k]) - int(do_l[k]) > int(inventario.get(k, 0)):
				cabe = false
		if not cabe:
			it.motivo = "sem_recursos"
			continue
		for k in c:
			gasto[k] = int(gasto.get(k, 0)) + int(c[k]) - int(do_l[k])
			if not loc.is_empty():
				if not gasto_l.has(loc.id):
					gasto_l[loc.id] = {}
				gasto_l[loc.id][k] = int(gasto_l[loc.id].get(k, 0)) + int(do_l[k])
	return plano


func _local(tile: Vector2i) -> Dictionary:
	if not estoque_local.is_valid():
		return {}
	var r: Variant = estoque_local.call(tile)
	return r if r is Dictionary else {}


## Paga o custo de uma peça posta em `tile`: primeiro o estoque do posto avançado que cobre o tile, o resto do núcleo
## (anota os dois no relatório, para o desfazer devolver a cada um).
func _pagar(itens: Dictionary, tile: Vector2i, rel: Dictionary) -> void:
	if not cobrar:
		return
	var loc := _local(tile)
	var resto := {}
	for k in itens:
		var n := int(itens[k])
		if not loc.is_empty():
			var d := mini(n, int(loc.estoque.get(k, 0)))
			if d > 0:
				loc.estoque[k] = int(loc.estoque[k]) - d
				if not rel.locais.has(loc.id):
					rel.locais[loc.id] = {}
				rel.locais[loc.id][k] = int(rel.locais[loc.id].get(k, 0)) + d
				n -= d
		if n > 0:
			resto[k] = n
	_mexer_estoque(resto, -1, rel)


## Soma (ou tira, com sinal −1) itens no estoque e anota no relatório (para o desfazer devolver).
func _mexer_estoque(itens: Dictionary, sinal: int, rel: Dictionary) -> void:
	if not cobrar:
		return
	for k in itens:
		var n := int(itens[k]) * sinal
		inventario[k] = maxi(0, int(inventario.get(k, 0)) + n)
		rel.estoque[k] = int(rel.estoque.get(k, 0)) + n


## Devolve o custo de algo que o mundo não conseguiu pôr (trem sem espaço).
func devolver(nome: String) -> void:
	_mexer_estoque(custo_de(nome), 1, _relatorio_vazio())


static func pode_tudo(plano: Array[Dictionary]) -> bool:
	for it in plano:
		if it.motivo != "":
			return false
	return true


## Quantos itens do plano fazem alguma coisa (para o texto da interface).
static func contar(plano: Array[Dictionary]) -> Dictionary:
	var ok := 0
	var bloq := 0
	for it in plano:
		if it.get("acao", "") == "igual":
			continue
		if it.motivo == "": ok += 1
		else: bloq += 1
	return {"ok": ok, "bloqueados": bloq}


# ------------------------------------------------------------------ executar / desfazer
## Executa o que pode do plano (itens bloqueados são pulados). Relatório:
## {colocados: [id], removidos: [{id, nome, minimo, rot}], limpos: [{tile, area_tiles}]}.
func executar(plano: Array[Dictionary]) -> Dictionary:
	var rel := _relatorio_vazio()
	for it in plano:
		if it.motivo != "":
			continue
		match it.get("acao", "colocar"):
			"igual":
				pass
			"trem":
				rel.trens.append({"tile": it.minimo, "rot": it.rot, "nome": it.nome})   # o mundo põe o trem na malha
				_pagar(custo_de(it.nome), it.minimo, rel)
			"limpar":
				var o := mapa.limpar_obstaculo(it.tile)
				if not o.is_empty():
					rel.limpos.append({"tile": it.tile, "tiles": Grade.tiles_da_area(o.ancora, o.area, 0)})
					_mexer_estoque(MapaOcupacao.drops_de(o), 1, rel)
			"aplainar":
				var t: Vector2i = it.tile
				rel.aplainados.append([t, mapa.gerador.aplainado_em(t)])
				mapa.gerador.aplainar(t, it.nivel)
				if it.muda:
					_mexer_estoque(Registro.progressao.get("custo_aplainar", {}), -1, rel)
				if not mapa.limpos.has(t):
					var o := mapa.limpar_obstaculo(t)
					if not o.is_empty():
						rel.limpos.append({"tile": t, "tiles": Grade.tiles_da_area(o.ancora, o.area, 0)})
						_mexer_estoque(MapaOcupacao.drops_de(o), 1, rel)
				mapa.versao += 1
			"remover":
				if mapa.estruturas.has(it.id):
					var ev: Dictionary = mapa.estruturas[it.id]
					_mexer_estoque(custo_de(ev.nome, int(ev.get("classe", 1))), 1, rel)
					for md in ev.get("modulos", []):         # módulos encaixados voltam junto
						_mexer_estoque({md: 1}, 1, rel)
				_remover(it.id, rel)
			"substituir":
				# troca de classe (esteira básica ↔ rápida): devolve a peça velha e cobra a nova
				var velho: Dictionary = mapa.estruturas.get(it.id_antigo, {}).duplicate()
				var troca: bool = not velho.is_empty() and int(velho.get("classe", 1)) != int(it.get("classe", 1))
				_remover(it.id_antigo, rel)
				if _colocar(it, rel) and troca:
					_mexer_estoque(custo_de(velho.nome, int(velho.get("classe", 1))), 1, rel)
					_pagar(custo_de(it.nome, int(it.get("classe", 1))), it.minimo, rel)
			_:
				if _colocar(it, rel):
					_pagar(custo_de(it.nome, int(it.get("classe", 1))), it.minimo, rel)
	_recalcular_pontas(rel)
	if not _relatorio_vazio_de_fato(rel) or not rel.estoque.is_empty() or not rel.locais.is_empty():
		_historico.append(rel)
		if _historico.size() > HISTORICO:
			_historico.pop_front()
	return rel


## Estrutura destruída (aranha): sai do mapa e as pontas de esteira em volta se ajustam. Não entra no desfazer.
func destruir(id: int) -> Dictionary:
	var rel := _relatorio_vazio()
	_remover(id, rel)
	_recalcular_pontas(rel)
	return rel


func pode_desfazer() -> bool:
	return not _historico.is_empty()


## Desfaz a última execução. Devolve o relatório do que mudou agora (mesmo formato).
func desfazer() -> Dictionary:
	var rel := _relatorio_vazio()
	if _historico.is_empty():
		return rel
	var h: Dictionary = _historico.pop_back()
	for id in h.colocados:
		_remover(id, rel)
	for i in range(h.removidos.size() - 1, -1, -1):
		var e: Dictionary = h.removidos[i]
		if e.nome == "pilar":
			continue                        # volta junto com a esteira dona dele
		var it := {"nome": e.nome, "minimo": e.minimo, "rot": e.rot}
		it.merge(e.get("extras", {}))
		_colocar(it, rel)
	for l in h.limpos:
		for t in l.tiles:
			mapa.limpos.erase(t)
		rel.restaurados.append(l)
	for i in range(h.aplainados.size() - 1, -1, -1):
		var ap: Array = h.aplainados[i]
		mapa.gerador.aplainar(ap[0], ap[1])
		rel.aplainados.append([ap[0], null])
	if not h.aplainados.is_empty():
		mapa.versao += 1
	_mexer_estoque(h.estoque, -1, rel)
	for pid in h.get("locais", {}):                # o que saiu do estoque de um posto volta para ele (saiu: para o núcleo)
		var est: Variant = estoque_do_posto.call(pid) if estoque_do_posto.is_valid() and mapa.estruturas.has(pid) else null
		for k in h.locais[pid]:
			if est is Dictionary:
				est[k] = int(est.get(k, 0)) + int(h.locais[pid][k])
			else:
				_mexer_estoque({k: h.locais[pid][k]}, 1, rel)
	return rel


func _relatorio_vazio() -> Dictionary:
	return {"colocados": [] as Array[int], "removidos": [] as Array[Dictionary], "limpos": [] as Array[Dictionary],
			"restaurados": [] as Array[Dictionary], "trens": [] as Array[Dictionary], "estoque": {}, "locais": {}, "aplainados": []}


func _relatorio_vazio_de_fato(r: Dictionary) -> bool:
	return r.colocados.is_empty() and r.removidos.is_empty() and r.limpos.is_empty() and r.aplainados.is_empty()


func _colocar(it: Dictionary, rel: Dictionary) -> bool:
	var extras := {}
	if it.get("nivel", 0) > 0: extras["nivel"] = it.nivel
	if it.get("desce", false): extras["desce"] = true
	if int(it.get("classe", 1)) > 1: extras["classe"] = int(it.classe)
	if not it.get("pilares", []).is_empty(): extras["pilares"] = it.pilares
	if not it.get("modulos", []).is_empty(): extras["modulos"] = it.modulos     # desfazer a demolição: os módulos voltam encaixados
	var id := mapa.colocar(it.nome, it.minimo, it.rot, extras)
	if id < 0:
		return false
	rel.colocados.append(id)
	if Fiacao.papel(it.nome) != "":
		Fiacao.ligar_novo(mapa, id)            # fios automáticos
	for p in it.get("pilares", []):
		var pid := mapa.reservar_pilar(p[0], p[1])
		if pid >= 0:
			rel.colocados.append(pid)
	return true


func _remover(id: int, rel: Dictionary) -> void:
	if not mapa.estruturas.has(id):
		return
	var e: Dictionary = mapa.estruturas[id]
	rel.removidos.append(_registro(id))
	rel.colocados.erase(id)
	# os pilares desta esteira elevada saem junto (voltam com ela no desfazer)
	for p in e.get("pilares", []):
		var pid: int = mapa.cantos.get(p[0], -1)
		if pid >= 0 and mapa.estruturas[pid].nome == "pilar":
			rel.removidos.append(_registro(pid))
			rel.colocados.erase(pid)
			mapa.remover(pid)
	Fiacao.desligar(mapa, id)                    # tira os fios; órfãos procuram outro poste
	mapa.remover(id)


func _registro(id: int) -> Dictionary:
	var e: Dictionary = mapa.estruturas[id]
	var extras := {}
	for k in ["nivel", "desce", "pilares", "fontes", "classe", "modulos"]:
		if e.has(k):
			extras[k] = e[k]
	return {"id": id, "nome": e.nome, "minimo": e.minimo, "rot": e.rot, "extras": extras}


## Troca a peça no lugar (mesmo id, mesmo nível e pilares) — pontas automáticas.
func _trocar_nome(id: int, novo: String, rel: Dictionary) -> void:
	if rel.colocados.has(id):
		mapa.estruturas[id].nome = novo      # posta agora mesmo: só acerta a peça
		return
	rel.removidos.append(_registro(id))
	mapa.estruturas[id].nome = novo
	rel.colocados.append(id)


## Pontas automáticas: em volta de tudo que entrou ou saiu, cada esteira reta/início/fim vira a peça certa —
## "início" se ninguém a alimenta por trás, "fim" se nada recebe na frente, "reta" se as duas pontas estão ligadas.
## (Continuar um traço a partir de um fim o transforma em reta; remover um pedaço fecha a ponta que sobrou.)
func _recalcular_pontas(rel: Dictionary) -> void:
	var tiles := {}
	var areas: Array[Dictionary] = []
	for id in rel.colocados:
		if mapa.estruturas.has(id):
			areas.append(mapa.estruturas[id])
	areas.append_array(rel.removidos)
	for e in areas:
		for t in Grade.tiles_da_area(e.minimo, Registro.area(e.nome), e.rot):
			tiles[t] = true
			for d in Grade.DIRECOES:
				tiles[t + d] = true
	for t in tiles:
		for id in mapa.ids_no_tile(t):
			var e: Dictionary = mapa.estruturas[id]
			if not e.nome in ["esteira_reta", "esteira_inicio", "esteira_fim", "esteira_juncao"]:
				continue
			var d := fluxo_da_rot(e.rot)
			var n: int = e.get("nivel", 0)
			var alimentado := _alimenta(t, d, n)
			var escoa := _recebe(t, d, n)
			var certo: String = e.nome
			if escoa and _lateral(t, d, n): certo = "esteira_juncao"
			elif alimentado and escoa: certo = "esteira_reta"
			elif alimentado: certo = "esteira_fim"
			elif escoa: certo = "esteira_inicio"
			if certo != e.nome:
				_trocar_nome(id, certo, rel)


# ------------------------------------------------------------------ escolha das peças
## Direção de fluxo de cada tile do caminho (o último repete o anterior; caminho de 1 tile usa `padrao`).
static func _direcoes(cam: Array[Vector2i], padrao: int) -> Array[int]:
	var out: Array[int] = []
	for i in cam.size():
		if i + 1 < cam.size():
			out.append(direcao(cam[i], cam[i + 1]))
		elif i > 0:
			out.append(out[i - 1])
		else:
			out.append(padrao)
	return out


## `d_ini` = de onde o primeiro tile é alimentado (-1: ninguém); `liga_fim` = o último entrega a um vizinho.
func _peca_esteira(cam: Array[Vector2i], dirs: Array[int], i: int, n := 0, d_ini := -1, liga_fim := false) -> Dictionary:
	var d_out: int = dirs[i]
	var d_in: int = dirs[i - 1] if i > 0 else (d_ini if d_ini >= 0 else d_out)
	var r := rot_do_fluxo(d_in)
	if d_out == posmod(d_in + 1, 4):
		return {"nome": "esteira_curva_dir", "rot": r}
	if d_out == posmod(d_in - 1, 4):
		return {"nome": "esteira_curva_esq", "rot": r}
	var primeiro := i == 0
	var ultimo := i == cam.size() - 1
	var alimentado := not primeiro or d_ini >= 0 or _alimenta(cam[i], d_in, n)
	var escoa := not ultimo or liga_fim or _recebe(cam[i], d_out, n)
	if ultimo and _recebe(cam[i], d_out, n) and _lateral(cam[i], d_out, n):
		return {"nome": "esteira_juncao", "rot": r}
	if not alimentado and escoa:
		return {"nome": "esteira_inicio", "rot": r}
	if alimentado and not escoa:
		return {"nome": "esteira_fim", "rot": r}
	if not alimentado and not escoa and cam.size() > 1:
		return {"nome": "esteira_inicio", "rot": r}
	return {"nome": "esteira_reta", "rot": r}


## Cano: reto na mesma direção; curva liga o lado de trás (oposto a d_in) ao lado de saída.
static func _peca_cano(d_in: int, d_out: int) -> Dictionary:
	if d_in == d_out:
		return {"nome": "cano_reto", "rot": rot_do_fluxo(d_in)}
	var lados := [posmod(d_in + 2, 4), d_out]
	for r in 4:
		# cano_curva em r = 0 liga S (2) e L (1); girar r anti-horário leva o lado s em s − r
		var l := [posmod(2 - r, 4), posmod(1 - r, 4)]
		if l.has(lados[0]) and l.has(lados[1]):
			return {"nome": "cano_curva", "rot": r}
	return {"nome": "cano_reto", "rot": rot_do_fluxo(d_out)}


## Nó de esteira de uma estrutura (reta, curva, início, fim, rampa): direções e níveis de entrada/saída.
## {} se não é esteira. Rampa guarda o nível de baixo; sobe (entra em n, sai em n+1) ou desce (o contrário).
static func no_esteira(e: Dictionary) -> Dictionary:
	var nome: String = e.nome
	if not (nome in FAMILIA_ESTEIRA or nome == "esteira_rampa" or nome in TUNEIS):
		return {}
	var d := fluxo_da_rot(e.rot)
	var s := d
	match nome:
		"esteira_curva_dir": s = posmod(d + 1, 4)
		"esteira_curva_esq": s = posmod(d - 1, 4)
		"esteira_fim": s = -1
	var n: int = e.get("nivel", 0)
	var n_in := n
	var n_out := n
	if nome == "esteira_rampa":
		if e.get("desce", false): n_in = n + 1
		else: n_out = n + 1
	var no := {"entra": d, "sai": s, "n_in": n_in, "n_out": n_out, "classe": int(e.get("classe", 1))}
	if nome in TUNEIS:
		no["tunel"] = "entrada" if nome == "esteira_tunel_entrada" else "saida"
	return no


## Alguma coisa entrega itens neste tile (no nível n) vindo de trás (fluxo d)? Esteira/rampa ou porta de máquina.
func _alimenta(tile: Vector2i, d: int, n := 0) -> bool:
	var t_atras := tile - Grade.DIRECOES[d]
	for id in mapa.ids_no_tile(t_atras):
		var e: Dictionary = mapa.estruturas[id]
		var no := no_esteira(e)
		if no.is_empty() or no.n_out != n or no.get("tunel", "") == "entrada":
			continue                              # entrada de passagem entrega por baixo, não para o vizinho
		if no.sai == d or (e.nome == "esteira_fim" and no.entra == d):
			return true                           # fim apontando para cá vira reta no recálculo
	if n > 0:
		return false
	var atras := _estrutura_em(t_atras)
	if atras.is_empty() or atras.nome.begins_with("braco") or not no_esteira(atras).is_empty():
		return false
	for p in _portas(atras):
		if p.io == "SAI" and p.tipo == "ITEM" and p.tile_fora == tile and p.dir == Grade.DIRECOES[d]:
			return true
	return false


## O tile da frente recebe itens no nível n? Esteira (que não venha de frente) ou porta de entrada de máquina.
## Braço não conta: a esteira termina em "fim" (para-choque) para o braço pegar.
func _recebe(tile: Vector2i, d: int, n := 0, nucleo_todo := true) -> bool:
	var t_frente := tile + Grade.DIRECOES[d]
	for id in mapa.ids_no_tile(t_frente):
		var no := no_esteira(mapa.estruturas[id])
		if no.has("tunel") and (no.tunel == "saida" or no.entra != d):
			continue                              # passagem só recebe por trás, na entrada
		if not no.is_empty() and no.n_in == n and no.entra != posmod(d + 2, 4):
			return true
	if n > 0:
		return false
	var frente := _estrutura_em(t_frente)
	if frente.is_empty() or frente.nome.begins_with("braco") or not no_esteira(frente).is_empty():
		return false
	if nucleo_todo and frente.nome == "nucleo" and mapa.gerador.nivel(t_frente) == mapa.gerador.nivel(tile):
		return true                               # o núcleo recebe a esteira por qualquer lado (Fabrica._entrega_no_nucleo)
	for p in _portas(frente):
		if p.io == "ENT" and p.tipo == "ITEM" and p.tile_fora == tile and p.dir == -Grade.DIRECOES[d]:
			return true
	return false


## A esteira da frente corre de lado (carga lateral)? Então a ponta vira rampa de junção.
func _lateral(tile: Vector2i, d: int, n := 0) -> bool:
	for id in mapa.ids_no_tile(tile + Grade.DIRECOES[d]):
		var no := no_esteira(mapa.estruturas[id])
		if not no.is_empty() and not no.has("tunel") and no.n_in == n and no.entra != d and no.entra != posmod(d + 2, 4):
			return true
	return false


## Estrutura no tile, no chão (n = 0) ou num nível de cima.
func _estrutura_em(t: Vector2i, n := 0) -> Dictionary:
	var id: int = mapa.tiles.get(t, -1) if n == 0 else mapa.altos.get(Vector3i(t.x, t.y, n), -1)
	if id < 0:
		return {}
	var e: Dictionary = mapa.estruturas[id].duplicate()
	e["id"] = id
	return e


## Pilares do traço elevado (EsteiraElevada): cada pilar fica com o tile cujo canto de entrada ele usa.
func _planejar_pilares(itens: Array[Dictionary], cam: Array[Vector2i], dirs: Array[int]) -> void:
	var entradas: Array[int] = []
	var niveis: Array[float] = []
	for i in cam.size():
		entradas.append(dirs[i - 1] if i > 0 else dirs[0])
		niveis.append(nivel * 0.5)
	var plano := EsteiraElevada.planejar(mapa, cam, entradas, niveis)
	if not plano.ok:
		for it in itens:
			if it.minimo == plano.tile and it.motivo == "":
				it.motivo = plano.erro
		return
	for p in plano.pilares:
		for k in cam.size():
			if p.canto in EsteiraElevada.cantos_de_entrada(cam[k], entradas[k]) and itens[k].acao != "igual":
				if not itens[k].has("pilares"):
					itens[k]["pilares"] = []
				itens[k].pilares.append([p.canto, p.altura])
				break


## Rampa: ↑ sobe do nível atual para o próximo; ↓ desce do nível atual. Rampa no alto também precisa de pilar.
func _item_rampa(desce: bool, tile: Vector2i, rot: int) -> Dictionary:
	var baixo := nivel - 1 if desce else nivel
	var it := {"nome": "esteira_rampa", "minimo": tile, "rot": rot, "acao": "colocar", "id_antigo": -1,
			"nivel": baixo, "desce": desce, "motivo": ""}
	if baixo < 0:
		it.motivo = "nivel_chao"
	elif baixo + 1 > MapaOcupacao.NIVEIS:
		it.motivo = "nivel_maximo"
	elif baixo == 0:
		it.motivo = mapa.motivo_bloqueio("esteira_rampa", tile, rot)
	else:
		it.motivo = mapa.motivo_alto(tile, baixo)
		if it.motivo == "":
			var d := fluxo_da_rot(rot)
			var pl := EsteiraElevada.planejar(mapa, [tile] as Array[Vector2i], [d] as Array[int], [baixo * 0.5 + 0.5] as Array[float])
			if not pl.ok:
				it.motivo = pl.erro
			else:
				it["pilares"] = pl.pilares.map(func(p): return [p.canto, p.altura])
	return it


func _portas(e: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in Registro.modelos.get(e.nome, {}).get("portas", []):
		out.append(Grade.porta_no_mundo(p, e.minimo, e.area, e.rot))
	return out


## Trem: vai em cima de um trilho reto já construído (fica na direção do trilho).
func _item_trem(tile: Vector2i, nome := "trem") -> Dictionary:
	var e := _estrutura_em(tile)
	var ok: bool = not e.is_empty() and e.nome in GrafoTrilhos.RETOS
	return {"nome": nome, "minimo": tile, "rot": e.rot if ok else 0, "motivo": "" if ok else "sem_trilho",
			"acao": "trem", "id_antigo": -1}


func _item(nome: String, minimo: Vector2i, rot: int, n := 0) -> Dictionary:
	if n > 0:
		return {"nome": nome, "minimo": minimo, "rot": rot, "motivo": mapa.motivo_alto(minimo, n), "acao": "colocar",
				"id_antigo": -1, "nivel": n}
	return {"nome": nome, "minimo": minimo, "rot": rot, "motivo": mapa.motivo_bloqueio(nome, minimo, rot),
			"acao": "colocar", "id_antigo": -1}


## Em cima de esteira/cano já existente da mesma família: troca a peça (ou nada, se for igual).
func _item_trocavel(nome: String, tile: Vector2i, rot: int, n := 0) -> Dictionary:
	var atual := _estrutura_em(tile, n)
	var familia := FAMILIA_ESTEIRA if nome in FAMILIA_ESTEIRA else FAMILIA_CANO
	if not atual.is_empty() and atual.nome in familia:
		var acao := "igual" if atual.nome == nome and atual.rot == rot else "substituir"
		var it := {"nome": nome, "minimo": tile, "rot": rot, "motivo": "", "acao": acao, "id_antigo": atual.id, "nivel": n,
				"classe_antiga": int(atual.get("classe", 1))}
		if int(atual.get("classe", 1)) > 1:
			it["classe"] = int(atual.classe)         # (a classe do traço vem depois, em _com_classe)
		if atual.has("pilares"):
			it["pilares"] = atual.pilares            # troca mantém os pilares que já estão lá
		return it
	return _item(nome, tile, rot, n)
