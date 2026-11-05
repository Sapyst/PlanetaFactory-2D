extends Node3D
## Cena de demonstração: mundo procedural em streaming por chunks; mini-fábrica perto do spawn
## (extrator → esteira → braço → estação A → trem → estação B); a poluição dela se espalha, ninhos de aranha
## absorvem e mandam ataques; a torre defende; o jogador constrói (controles em interface/controle_construcao.gd).
## Argumentos: -- camera X Z DIST · acelerar N (tempo N×) · roteiro <nome> · clima <estado>
## Teste sem janela: godot --headless --path jogo --quit-after 600   (o jogo roda e sai)
## Roteiro visual automático: ... -- roteiro construir   (ver interface/roteiro_teste.gd)

const RAIO_MIN := 2                 ## chunks em volta do centro da câmera (cresce com o zoom, até RAIO_MAX)
const RAIO_MAX := 5
const SEMENTE := 1337               ## demonstração e testes; jogo novo sorteia a sua
const NUCLEO_EM := Vector2i(-1, -1)  ## núcleo 3×3 em volta do spawn (modo novo)

## Eventos de combate do quadro (tiro, salto, explosão, pulso…), antes do desenho 3D: a versão 2D desenha os seus.
signal eventos_desenho(eventos: Array)
## Versão 2D: abertura própria (núcleo, ao terminar) no lugar da cena 3D do espaço.
var abertura_2d: Callable

var gerador: GeradorMundo
var mapa: MapaOcupacao
var relogio := RelogioSim.new()
var chunks: Dictionary = {}
var fabrica: Fabrica
var _desenho_itens: DesenhoItens
var _fabrica_suja := false
var poluicao: Poluicao
var clima: Clima
var ambiente: AmbienteVivo
var clima_local: ClimaLocal             ## máquinas de clima (semeador, defletor, cúpula, regulador)
var raios: Raios                        ## raios da tempestade (caem no mapa, para-raios pegam)
var varredura: Varredura                ## sensores de varredura (revelam chunks e marcam ninhos)
var farol: Farol                        ## faróis de cristal (luz de 10 m à noite, avisam das aranhas)
var lancador: Lancador                  ## lançadores de sementes (o núcleo-semente voa e vira posto avançado)
var genese: Genese                      ## colônias (pacote gênese por cápsula) e receptores de cápsulas
var transportador: Transportador        ## transportadores quânticos (itens entre colônias, por canal)
var silo: SiloLancamento                ## silos de lançamento (foguete de proliferação: fim da campanha)
var agua: AguaJogo                     ## buracos/canais escavados que enchem a partir de rio/lago
var colonia: Colonia
var infestacao: Infestacao               ## teia e sujeira no chão em volta das tocas (cresce com a idade da toca)
var passaros: Passaros                   ## pássaros nativos (patch fauna): bandos, fuga, sementes que reflorestam
var ecossistema: Ecossistema             ## patch fauna, fase 0: índice de quem vive perto, saúde do chão, eventos
var _vida_pequena: DesenhoVidaPequena    ## patch fauna, fase 1: vagalumes, insetos, olhos no mato, sons de ambiente
var plantas_reagem: PlantasReagem        ## patch fauna, fase 2: galhos depois da tempestade, cogumelos depois da chuva
var _desenho_plantas_reagem: DesenhoPlantasReagem   ## + folhas caindo no outono, frutos no chão, sementes no vento
var frutos: Frutos                       ## patch fauna, fase 3: frutos que viram comida, sementes que viram mata
var _desenho_passaros: DesenhoPassaros
var _raios_passaros := 0
var _teia_versao := -1
var _teia_chunks: Dictionary = {}        ## chunk → nó DesenhoChunk que já recebeu a infestação (o nó pode ser refeito)
var _t_teia := 0.0
var drones: Drones                      ## drones das estações (reparo, combate, logística)
var _desenho_drones: DesenhoDrones
var obras: Obras                        ## patch RTS: obras encomendadas que os drones construtores do núcleo fazem
var _desenho_obras: DesenhoObras
var _eventos_drones: Array[Dictionary] = []
var grafo := GrafoTrilhos.new()
var trens: Array[Trem] = []
var estoques: Dictionary = {}       ## id da estação → {enviar: {item: n}, recebido: {item: n}}
var _prox_trem := 1
var _poluiu_em: Dictionary = {}     ## id → instante (s) da última emissão: quem poluiu há pouco é alvo das aranhas
var _eventos: Array[Dictionary] = []
var _desenho_colonia: DesenhoColonia
var _desenho_trens: DesenhoTrens
var _desenho_poluicao: DesenhoPoluicao
var _visao: VisaoRecursos
var vento_local: VentoLocal
var descoberta := Descoberta.new()
var _fluxo: DesenhoFluxo
var animar_tudo := false             ## mostruário (vídeos): toda máquina e braço mexendo
var _no_nucleo: Node3D
var _rotulos: Dictionary = {}       ## id da estação → Label3D
var _t_hud := 0.0
var _t_som_maquinas := 0.0
var _sel := {}                       ## selecionado: {trem: id} ou {estrutura: id}
var _relatorio := false              ## -- relatorio: imprime o estado a cada 30 s de jogo (para calibrar números)
var _t_rel := 0.0
var _tempo := 0.0
var _raios_vistos := 0                  ## Raios.total já avisado
var _aviso_tufao_em := -1.0e9           ## _tempo do último aviso de tufão
var modo := "demo"
var semente := SEMENTE
var inventario: Dictionary = {}     ## estoque do núcleo (o mesmo dicionário no Construtor e na Fabrica)
var pesquisa: Pesquisa
var pausa: MenuPausa
var _auto_salvar := AutoSalvar.new()
var _autosalvar := true                 ## esta partida salva sozinha? (demo, roteiros e relatório não)
var _abertura_rodando := false
var _indicador_salvando := 0.0          ## segundos que o "Salvando…" ainda fica na tela (para dar tempo de ler)
var _salvar_no_quadro := false          ## o aviso aparece um quadro antes de montar os dados, para já estar na tela
var _salvando_auto := false
var construtor: Construtor
var controle: ControleConstrucao
var _nos: Dictionary = {}           ## id da estrutura → Node3D (peças miúdas vão para _lotes)
var _lotes: DesenhoLotes
var _silo_total: Dictionary = {}          ## id do silo → itens guardados no último quadro (anima quando muda)
var _silo_mexeu: Dictionary = {}          ## id do silo → _tempo da última mudança
var _efeitos: Efeitos
var _fios: DesenhoFios
var luzes: DesenhoLuzes

@onready var camera: CameraJogo = $Camera3D


func _ready() -> void:
	# câmera por argumento (fotos automáticas): -- camera <x> <z> <distância>
	var args := OS.get_cmdline_user_args()
	var i := args.find("camera")
	if camera != null:
		if i >= 0 and args.size() > i + 3:
			camera.alvo = Vector3(float(args[i + 1]), 0, float(args[i + 2]))
			camera.distancia = float(args[i + 3])
		camera.posicionar()
	_relatorio = args.has("relatorio")
	var ac := args.find("acelerar")
	if ac >= 0 and args.size() > ac + 1:
		Engine.time_scale = float(args[ac + 1])
	# modo da partida: o menu decide (Sessao); rodando a cena direto (testes), é a demonstração
	modo = Sessao.modo
	if args.has("novo"):
		modo = "novo"                         # testes/fotos: jogo novo direto (com abertura)
	var dados := {}
	if modo == "continuar":
		dados = Salvamento.ler_partida()        # o salvo, ou a cópia de segurança se ele estiver quebrado
		modo = dados.get("modo", "novo") if not dados.is_empty() else "novo"
	_autosalvar = modo != "demo" and not args.has("roteiro") and not _relatorio
	if not dados.is_empty():
		semente = dados.semente
	elif modo == "novo":
		semente = randi() % 1000000
	gerador = GeradorMundo.new(semente)
	Grade.gerador = gerador                  # tudo que se desenha passa a assentar no relevo
	mapa = MapaOcupacao.new(gerador)
	DesenhoChunk.preparar(gerador)
	DesenhoChunk.aquecer()
	poluicao = Poluicao.new(gerador)
	if args.has("densidade_grama"):               # medição: -- densidade_grama N
		DesenhoChunk.densidade_grama = float(args[args.find("densidade_grama") + 1])
	clima = Clima.new(semente)
	clima.tempo_real = true                    # estações: 7 dias reais cada
	colonia = Colonia.new(mapa, poluicao, semente)
	infestacao = Infestacao.new(colonia, semente)
	passaros = Passaros.new(gerador, mapa, ambiente, colonia, infestacao, semente + 41)
	pesquisa = Pesquisa.new(modo == "demo")
	fabrica = Fabrica.new(mapa)
	ambiente = AmbienteVivo.new(gerador, mapa, semente)
	# (os pássaros nasceram antes do ambiente: sem isto não viam fogo, cinza nem chão morto — e não plantavam)
	passaros.ambiente = ambiente
	ecossistema = Ecossistema.new(gerador, mapa, ambiente, infestacao)
	passaros.eco = ecossistema
	ecossistema.registrar_fonte("passaro", passaros.para_ecossistema)
	ecossistema.registrar_fonte("alien", func() -> Array:
		var out: Array = []
		for ar in colonia.aranhas.values():
			out.append({"id": ar.id, "pos": ar.pos, "especie": ar.get("especie", "aranha")})
		return out)
	plantas_reagem = PlantasReagem.new(ecossistema, semente + 53)
	frutos = Frutos.new(ecossistema, ambiente, semente + 59)
	ecossistema.registrar_fonte("toca", func() -> Array:
		var out: Array = []
		for id in colonia.ninhos:
			out.append({"id": id, "pos": colonia.ninhos[id].centro, "especie": colonia.ninhos[id].get("especie", "aranha")})
		return out)
	vento_local = VentoLocal.new(gerador, mapa, ambiente)
	agua = AguaJogo.new(gerador, mapa)
	ambiente.dano = func(id: int, pontos: float) -> void: _danificar(id, pontos)
	ambiente.poluicao = poluicao
	clima_local = ClimaLocal.new(mapa)
	clima_local.energia = fabrica.energia
	ambiente.clima_local = clima_local
	raios = Raios.new(mapa, semente)
	raios.fabrica = fabrica
	raios.ambiente = ambiente
	raios.colonia = colonia
	raios.clima_local = clima_local
	raios.dano = func(id: int, pontos: float) -> void: _danificar(id, pontos)
	colonia.ambiente = ambiente
	varredura = Varredura.new(mapa, descoberta)
	varredura.colonia = colonia
	varredura.energia = fabrica.energia
	varredura.profunda = func() -> bool: return pesquisa.modo_liberado("varredura_profunda")
	farol = Farol.new(mapa, descoberta)
	farol.colonia = colonia
	farol.energia = fabrica.energia
	farol.luz_dia = clima.luz_dia
	lancador = Lancador.new(mapa, descoberta)
	lancador.colonia = colonia
	lancador.energia = fabrica.energia
	lancador.colonias = func() -> bool: return pesquisa.modo_liberado("colonias")
	genese = Genese.new(mapa, fabrica)
	transportador = Transportador.new(mapa)
	transportador.energia = fabrica.energia
	silo = SiloLancamento.new(mapa)
	silo.energia = fabrica.energia
	silo.carga_liberada = func() -> bool: return pesquisa.modo_liberado("carga_semente")
	fabrica.estoques = estoques
	fabrica.estoque_nucleo = inventario
	fabrica.pesquisa = pesquisa
	fabrica.torre_receber = func(id: int, n: int) -> void: colonia.carregar_torre(id, n)
	fabrica.torre_aceita = colonia.aceita_municao               # metralhadora cheia não recebe mais
	fabrica.torre_especial = colonia.carregar_especial          # perfurante, carregada, enxame
	colonia.artilharia_auto = func() -> bool: return pesquisa.modo_liberado("artilharia_automatica")
	colonia.harmonia = func() -> bool: return pesquisa.concluidas.has("harmonia_ninhos")   # (só de verdade: na demonstração as aranhas seguem atacando)
	colonia.ninhos_paz = func() -> bool: return pesquisa.concluidas.has("simbiose")
	colonia.torre_energia = fabrica.gastar_torre                # torre atira com a energia guardada da rede (e o escudo absorve)
	colonia.energia = fabrica.energia                           # muro de campo regenera com energia
	colonia.bonus = pesquisa.bonus                              # melhorias pesquisadas (dano da torre)
	drones = Drones.new(mapa, fabrica, colonia)
	drones.bonus = pesquisa.bonus
	drones.livre = pesquisa.livre
	drones.logistica_ok = func() -> bool: return pesquisa.concluidas.has("drones_logisticos")
	drones.inventario = inventario
	drones.raios_agora = func() -> bool: return bool(Registro.clima.estados.get(clima.atual, {}).get("raios", false))
	_lotes = DesenhoLotes.new()
	add_child(_lotes)
	_criar_construcao()
	construtor.cobrar = modo != "demo"
	drones.cobrar = construtor.cobrar                          # reparo por drone paga placas como o reparo à mão
	construtor.inventario = inventario
	construtor.pesquisa = pesquisa
	construtor.estoque_local = func(t: Vector2i) -> Dictionary:     # obra perto de um posto avançado paga com o estoque dele
		var p := fabrica.posto_que_cobre(t)
		return {} if p < 0 else {"id": p, "estoque": fabrica.baus[p]}
	construtor.estoque_do_posto = func(p: int) -> Variant: return fabrica.baus.get(p)
	obras = Obras.new(mapa, construtor, drones, inventario)
	obras.cobrar = construtor.cobrar
	obras.aplicar = sincronizar
	construtor.fila_de_obras = true
	colonia.destruir = func(id: int) -> void: _destruido(id)
	if not dados.is_empty():
		_carregar(dados)
	elif modo == "demo":
		_montar_fabrica()
	else:
		_comecar_novo()
	_criar_desenhos()
	pausa = MenuPausa.new()
	pausa.pode_salvar = modo != "demo"
	pausa.pediu_salvar.connect(salvar)
	add_child(pausa)
	Sessao.aplicar.call_deferred()
	# jogo novo: o núcleo chega do espaço (abertura; um toque pula)
	if modo == "novo" and dados.is_empty() and _no_nucleo != null and (not args.has("roteiro") or args.has("abertura")) and abertura_2d.is_valid():
		controle.process_mode = Node.PROCESS_MODE_DISABLED       # versão 2D: a abertura é desenhada em 2D
		_abertura_rodando = true
		abertura_2d.call(_no_nucleo, func():
			controle.process_mode = Node.PROCESS_MODE_INHERIT
			_abertura_rodando = false)
	elif modo == "novo" and dados.is_empty() and _no_nucleo != null and (not args.has("roteiro") or args.has("abertura")):
		var ab := Abertura.new()
		ab.nucleo = _no_nucleo
		ab.camera_jogo = camera
		ab.barra = controle.barra
		controle.process_mode = Node.PROCESS_MODE_DISABLED
		_abertura_rodando = true
		ab.terminou.connect(func():
			controle.process_mode = Node.PROCESS_MODE_INHERIT
			_abertura_rodando = false)
		add_child(ab)
	var ci := args.find("clima")
	if ci >= 0 and args.size() > ci + 1:
		clima.forcar(args[ci + 1], true)
	var ei := args.find("estacao")                # fotos: -- estacao 2 0.5 (outono pela metade)
	if ei >= 0 and args.size() > ei + 2:
		clima.tempo_real = false
		clima.estacao = int(args[ei + 1])
		clima.t_estacao = float(args[ei + 2]) * float(Registro.clima.estacao_s)
	# fotos: relógio parado (de dia, ou -- hora 0.0 meia-noite … 0.5 meio-dia); -- ciclo deixa o dia andar
	var hi := args.find("hora")
	if args.has("roteiro") and not args.has("ciclo"):
		clima.ciclo = false
		clima.tempo_real = false
		if not args.has("estacao"):
			clima.t_estacao = float(Registro.clima.estacao_s) * 0.5     # meio da estação (vento no rumo dela)
		clima.hora = 0.45
	if hi >= 0 and args.size() > hi + 1:
		clima.hora = float(args[hi + 1])
	_atualizar_chunks()
	var r := args.find("roteiro")
	if r >= 0 and args.size() > r + 1:
		var rt := RoteiroTeste.new()
		rt.roteiro = args[r + 1]
		rt.cena = self
		add_child(rt)


## Jogo novo: núcleo no spawn, kit inicial de itens, pesquisa do zero.
func _comecar_novo() -> void:
	for x in range(-4, 3):
		for y in range(-4, 3):
			mapa.limpar_obstaculo(NUCLEO_EM + Vector2i(x, y))
	_no_nucleo = _instanciar("nucleo", NUCLEO_EM, 0)
	inventario.merge(Registro.progressao.get("kit_inicial", {}))
	obras.dar_iniciais()
	fabrica.reconstruir()
	camera.alvo = Grade.ponto_mundo(Vector2(NUCLEO_EM) + Vector2(1.5, 1.5))
	camera.posicionar()


## Reparo: 1 placa de ferro a cada 25 pontos de integridade que faltam (vazio = inteira).
func custo_reparo(id: int) -> Dictionary:
	if not colonia.vida.has(id) or not mapa.estruturas.has(id):
		return {}
	var falta: float = float(Registro.estruturas.get(mapa.estruturas[id].nome, {}).get("vida", 0)) - colonia.vida[id]
	return {"placa_ferro": int(ceil(falta / 25.0))} if falta > 0.0 else {}


func reparar(id: int) -> bool:
	var custo := custo_reparo(id)
	if custo.is_empty():
		return false
	if construtor.cobrar:
		for k in custo:
			if int(inventario.get(k, 0)) < int(custo[k]):
				controle._avisar("Faltam itens no núcleo para reparar")
				return false
		for k in custo:
			inventario[k] = int(inventario[k]) - int(custo[k])
	colonia.vida.erase(id)
	Som.tocar("construir")
	return true


## Dano do ambiente (fogo, tufão) na mesma vida que as aranhas usam; zerou, cai.
func _danificar(id: int, pontos: float) -> void:
	if not mapa.estruturas.has(id):
		return
	var nome: String = mapa.estruturas[id].nome
	if Colonia.eh_toca(nome):
		return
	var v: float = colonia.vida.get(id, float(Registro.estruturas.get(nome, {}).get("vida", 100)))
	v -= pontos
	colonia.vida[id] = v
	if v <= 0.0:
		colonia.vida.erase(id)
		var e: Dictionary = mapa.estruturas[id]
		_efeitos.marcar_destruicao(Grade.centro_da_area(e.minimo, e.area, e.rot), Registro.area(nome).x)
		_destruido(id)


## Estrutura derrubada pelas aranhas. Núcleo caído = derrota.
func _destruido(id: int) -> void:
	var era_nucleo: bool = mapa.estruturas.has(id) and mapa.estruturas[id].nome == "nucleo"
	sincronizar(construtor.destruir(id))
	if era_nucleo:
		Som.tocar("derrota")
		_autosalvar = false                     # partida acabou: nem o relógio nem fechar o jogo recriam o save
		Salvamento.apagar()
		pausa.abrir(true)


# ------------------------------------------------------------------ salvar / carregar
func salvar() -> void:
	if modo == "demo":
		return
	var ok := Salvamento.gravar(_dados_salvar())
	if is_instance_valid(controle):
		controle._avisar("Jogo salvo" if ok else "Não consegui salvar")


## Salvar automático: os dados saem aqui (quadro atual) e o disco fica em segundo plano; a partida não para.
func _salvar_auto() -> void:
	_salvando_auto = Salvamento.gravar_em_segundo_plano(_dados_salvar())


func _dados_salvar() -> Dictionary:
	return {"modo": modo, "semente": semente, "tempo": _tempo,
			"camera": [camera.alvo, camera.distancia, camera.angulo],
			"mapa": {"estruturas": mapa.estruturas, "limpos": mapa.limpos.keys(), "prox": mapa._prox_id, "arvores": mapa.arvores},
			"fabrica": fabrica.estado(), "colonia": colonia.estado(), "poluicao": poluicao.valores, "clima": clima.estado(), "aplainado": gerador.aplainados(), "ambiente": ambiente.estado(), "agua": agua.estado(), "descoberta": descoberta.estado(), "varredura": varredura.estado(), "lancador": lancador.estado(), "genese": genese.estado(), "raios": raios.estado(), "drones": drones.estado(), "obras": obras.estado(), "ecossistema": ecossistema.estado(), "plantas_reagem": plantas_reagem.estado(), "frutos": frutos.estado(),
			"estoques": estoques, "inventario": inventario, "pesquisa": pesquisa.estado(),
			"trens": trens.map(func(t: Trem): return t.para_salvar()), "prox_trem": _prox_trem}


## Relógio do salvar automático e o aviso "Salvando…" (fica ao menos 0,8 s para dar para ler).
func _passo_autosalvar(dt: float) -> void:
	if not _autosalvar:
		return
	if _salvar_no_quadro:
		_salvar_no_quadro = false
		_salvar_auto()
	elif _auto_salvar.avancar(dt, float(Sessao.config.autosalvar_s), not _abertura_rodando and not Salvamento.em_andamento()):
		_salvar_no_quadro = true
		_indicador_salvando = 0.8
		controle.barra.indicador_salvando(true)
	if _indicador_salvando > 0.0:
		_indicador_salvando -= dt
		if _indicador_salvando <= 0.0 and Salvamento.em_andamento():
			_indicador_salvando = 0.05           # disco lento: o aviso fica até acabar
		elif _indicador_salvando <= 0.0:
			controle.barra.indicador_salvando(false)
	if _salvando_auto and not Salvamento.em_andamento():
		_salvando_auto = false
		if not Salvamento.concluir():
			controle._avisar("Não consegui salvar")


func _carregar(d: Dictionary) -> void:
	mapa.restaurar(d.mapa.estruturas, d.mapa.limpos, d.mapa.prox, d.mapa.get("arvores", {}))
	inventario.merge(d.inventario, true)
	pesquisa.restaurar(d.pesquisa)
	for id in d.estoques:
		estoques[id] = d.estoques[id]
	poluicao.valores = d.poluicao
	if d.has("clima"):
		clima.restaurar(d.clima)
	if d.has("ambiente"):
		ambiente.restaurar(d.ambiente)
	descoberta.restaurar(d.get("descoberta", {}))
	varredura.restaurar(d.get("varredura", {}))
	raios.restaurar(d.get("raios", {}))
	lancador.restaurar(d.get("lancador", {}))
	genese.restaurar(d.get("genese", {}))
	for t in d.get("aplainado", {}):
		gerador.aplainar(t, d.aplainado[t])
	agua.restaurar(d.get("agua", {}))
	agua.recalcular()
	agua.encher_tudo()
	colonia.restaurar(d.colonia)
	drones.restaurar(d.get("drones", {}))
	obras.restaurar(d.get("obras", {}))
	ecossistema.restaurar(d.get("ecossistema", {}))
	plantas_reagem.restaurar(d.get("plantas_reagem", {}))
	frutos.restaurar(d.get("frutos", {}))
	obras.dar_iniciais()                          # save de antes do patch RTS: ganha os construtores uma vez
	for id in mapa.estruturas:
		var nome: String = mapa.estruturas[id].nome
		if not Colonia.eh_toca(nome) and nome != "pilar":
			_criar_no(id)
	for id in mapa.estruturas:
		if MUROS.has(mapa.estruturas[id].nome):
			_ligar_muro(mapa.estruturas[id].minimo)
	fabrica.restaurar(d.fabrica)
	_remontar_trilhos()
	for td in d.trens:
		var t := Trem.de_salvo(td, grafo)
		if t != null:
			trens.append(t)
	_prox_trem = d.prox_trem
	_tempo = d.tempo
	camera.alvo = d.camera[0]
	camera.distancia = d.camera[1]
	camera.angulo = d.camera[2]
	camera.posicionar()


func _notification(what: int) -> void:
	# fechar a janela / celular mandar o app para o fundo: salva antes
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		if _autosalvar and not _abertura_rodando:
			salvar()


func abrir_pausa() -> void:
	pausa.abrir()


func abrir_pesquisa() -> void:
	_tela_pesquisa.alternar()


var _tela_pesquisa: TelaPesquisa


func modal_aberto() -> bool:
	return _tela_pesquisa != null and _tela_pesquisa.visible


func _criar_desenhos() -> void:
	_desenho_passaros = DesenhoPassaros.new()
	_desenho_passaros.passaros = passaros
	add_child(_desenho_passaros)
	_vida_pequena = DesenhoVidaPequena.new()
	_vida_pequena.eco = ecossistema
	_vida_pequena.clima = clima
	_vida_pequena.camera = camera
	add_child(_vida_pequena)
	_desenho_plantas_reagem = DesenhoPlantasReagem.new()
	_desenho_plantas_reagem.eco = ecossistema
	_desenho_plantas_reagem.clima = clima
	_desenho_plantas_reagem.plantas = plantas_reagem
	_desenho_plantas_reagem.camera = camera
	add_child(_desenho_plantas_reagem)
	_desenho_colonia = DesenhoColonia.new()
	_desenho_colonia.colonia = colonia
	_desenho_colonia.mapa = mapa
	_desenho_colonia.animadores_torre = _animador
	_desenho_colonia.carga = func(id: int) -> float: return float(fabrica.carga_torre.get(id, 0.0))
	_desenho_colonia.carga_max = fabrica.carga_max
	add_child(_desenho_colonia)
	_desenho_drones = DesenhoDrones.new()
	_desenho_drones.drones = drones
	_desenho_drones.mapa = mapa
	_desenho_drones.desenho_colonia = _desenho_colonia
	_desenho_drones.no_estrutura = func(id: int) -> Node3D: return _nos.get(id)
	add_child(_desenho_drones)
	_desenho_obras = DesenhoObras.new()
	_desenho_obras.obras = obras
	_desenho_obras.mapa = mapa
	add_child(_desenho_obras)
	_desenho_trens = DesenhoTrens.new()
	add_child(_desenho_trens)
	_desenho_itens = DesenhoItens.new()
	_desenho_itens.fabrica = fabrica
	_desenho_itens.mapa = mapa
	_desenho_itens.garra = ponto_garra
	_desenho_itens.process_priority = 100          # depois dos Animadores: o item usa a pose deste quadro
	add_child(_desenho_itens)
	_fios = DesenhoFios.new()
	_fios.mapa = mapa
	_fios.fabrica = fabrica
	add_child(_fios)
	_efeitos = Efeitos.new()
	_efeitos.fabrica = fabrica
	_efeitos.mapa = mapa
	add_child(_efeitos)
	var portas_soltas := DesenhoPortas.new()        # aviso de entrada/saída sem nada ligado
	portas_soltas.mapa = mapa
	add_child(portas_soltas)
	_desenho_poluicao = DesenhoPoluicao.new()
	_desenho_poluicao.poluicao = poluicao
	add_child(_desenho_poluicao)
	_fluxo = DesenhoFluxo.new()
	_fluxo.mapa = mapa
	add_child(_fluxo)
	_visao = VisaoRecursos.new()
	_visao.gerador = gerador
	_visao.mapa = mapa
	_visao.camera = camera
	_visao.clima = clima
	_visao.vento_local = vento_local
	_visao.poluicao = poluicao
	_visao.ambiente = ambiente
	_visao.colonia = colonia
	_visao.camada_liberada = pesquisa.camada_liberada
	_visao.areas_interface = func() -> Array[Rect2]: return controle.barra.areas_ocupadas()
	add_child(_visao)
	var da := DesenhoAmbiente.new()
	da.ambiente = ambiente
	da.chunks = chunks
	da.camera = camera
	da.clima = clima
	add_child(da)
	var dc := DesenhoClima.new()
	dc.clima = clima
	dc.camera = camera
	dc.ambiente = $Ambiente
	dc.sol = $Sol
	dc.fontes_calor = _fontes_calor
	dc.mapa = mapa
	dc.raios = raios
	add_child(dc)
	var dcl := DesenhoClimaLocal.new()               # cúpula de campo, chuva do semeador, clarão na cúpula
	dcl.clima_local = clima_local
	dcl.raios = raios
	dcl.camera = camera
	dcl.clima = clima
	add_child(dcl)
	var dpl := DesenhoPlataformas.new()
	dpl.mapa = mapa
	dpl.agua = agua
	add_child(dpl)
	var dpt := DesenhoPlantas.new()
	dpt.ambiente = ambiente
	add_child(dpt)
	add_child(_arcos)
	var dvr := DesenhoVarredura.new()              # marcas do sensor de varredura (ninhos, jazidas medidas)
	dvr.varredura = varredura
	add_child(dvr)
	var dfa := DesenhoFarol.new()                  # luz dos faróis de cristal à noite
	dfa.farol = farol
	add_child(dfa)
	luzes = DesenhoLuzes.new()                     # luz das estruturas e dos postes à noite, labaredas e arcos
	luzes.mapa = mapa
	luzes.fabrica = fabrica
	luzes.clima = clima
	luzes.farol = farol
	luzes.nos = _nos
	luzes.arcos = _arcos
	luzes.animar_tudo = func() -> bool: return animar_tudo
	add_child(luzes)
	var dla := DesenhoLancador.new()               # cápsula-semente em voo e o alvo de cada lançador
	dla.lancador = lancador
	dla.genese = genese
	add_child(dla)
	var dsi := DesenhoSilo.new()                   # foguete crescendo no silo e subindo no lançamento
	dsi.silo = silo
	add_child(dsi)
	var dv := DesenhoVisao.new()                  # oval de visão + névoa do não visto
	dv.camera = camera
	dv.descoberta = descoberta
	dv.chunks = chunks
	add_child(dv)


func alternar_recursos() -> bool:
	return _visao.alternar()


func camada_visao() -> String:
	return _visao.camada


func alternar_poluicao() -> bool:
	_desenho_poluicao.visible = not _desenho_poluicao.visible
	return _desenho_poluicao.visible


func _criar_construcao() -> void:
	construtor = Construtor.new(mapa)
	var fantasma := Fantasma.new()
	fantasma.mapa = mapa
	add_child(fantasma)
	var barra := BarraConstrucao.new()
	add_child(barra)
	controle = ControleConstrucao.new()
	add_child(controle)
	barra.liberado = func(nome: String) -> bool: return pesquisa == null or pesquisa.peca_liberada(nome)
	barra.em_desenvolvimento = func(nome: String) -> bool: return pesquisa != null and pesquisa.peca_em_desenvolvimento(nome)
	controle.configurar(construtor, camera, barra, fantasma, self)
	_tela_pesquisa = TelaPesquisa.new()            # pesquisa em tela própria (a lista no painel não cabia no celular)
	_tela_pesquisa.pesquisa = pesquisa
	_tela_pesquisa.tema = barra._tema
	_tela_pesquisa.rotulo = barra.rotulo
	_tela_pesquisa.nome_item = _nome_item
	add_child(_tela_pesquisa)


# ------------------------------------------------------------------ mundo
## Streaming do mapa sem travar a câmera:
##  - quer os chunks no raio da vista + 1 de folga (pré-carrega antes de aparecer);
##  - gerar e calcular a malha vai para a fila de trabalho em segundo plano (até TAREFAS ao mesmo tempo, os mais
##    perto do centro primeiro);
##  - na linha principal só monta o que ficou pronto: 1 chunk por quadro;
##  - descarrega só quando passa 2 chunks da vista (ir e voltar não recarrega).
const TAREFAS := 3

var _fila_pronta: Dictionary = {}      ## chunk → dados prontos (escrito pelas tarefas de fundo)
var _em_preparo: Dictionary = {}       ## chunk → id da tarefa
var _trava := Mutex.new()


func _atualizar_chunks() -> void:
	var c := Grade.chunk_de(Grade.tile_de_mundo(camera.alvo))
	var raio := clampi(ceili(camera.distancia * 0.75 / Grade.TAM_CHUNK) + 1, RAIO_MIN, RAIO_MAX - (1 if OS.has_feature("mobile") else 0))
	# descarrega o que ficou bem para trás
	for k in chunks.keys():
		if maxi(absi(k.x - c.x), absi(k.y - c.y)) > raio + 2:
			chunks[k].queue_free()
			chunks.erase(k)
	# monta 1 chunk pronto por quadro (o mais perto)
	_trava.lock()
	var prontos := _fila_pronta.keys()
	_trava.unlock()
	if not prontos.is_empty():
		prontos.sort_custom(func(a, b): return (a - c).length_squared() < (b - c).length_squared())
		var k: Vector2i = prontos[0]
		_trava.lock()
		var dados: Dictionary = _fila_pronta[k]
		_fila_pronta.erase(k)
		_trava.unlock()
		WorkerThreadPool.wait_for_task_completion(_em_preparo[k])
		_em_preparo.erase(k)
		if maxi(absi(k.x - c.x), absi(k.y - c.y)) <= raio + 2:
			if chunks.has(k):
				chunks[k].queue_free()            # redesenho: troca o velho pelo novo
			colonia.descobrir_chunk(k)
			var d := DesenhoChunk.new()
			add_child(d)
			d.montar(dados, mapa)
			d.ajustar_grama(Visao.centro, camera.distancia >= 80.0 or not bool(Sessao.config.get("grama", true)))
			chunks[k] = d
			if ambiente.dados.has(k) or ambiente.dados.has(k + Vector2i(1, 0)) or ambiente.dados.has(k - Vector2i(1, 0)) \
					or ambiente.dados.has(k + Vector2i(0, 1)) or ambiente.dados.has(k - Vector2i(0, 1)):
				d.atualizar_ambiente(ambiente.imagem(k))   # já nasce suja/queimada (sem piscar o chão limpo)
				ambiente.sujos.erase(k)
			if infestacao != null and infestacao.chunks().has(k):
				d.atualizar_teia(infestacao.imagem(k))     # já nasce com teia/corrosão (redesenho não pisca o chão limpo)
				_teia_chunks[k] = d.get_instance_id()
	# encomenda os que faltam, do centro para fora
	if _em_preparo.size() >= TAREFAS:
		return
	var faltam: Array[Vector2i] = []
	for dx in range(-raio - 1, raio + 2):
		for dy in range(-raio - 1, raio + 2):
			var k := c + Vector2i(dx, dy)
			if not chunks.has(k) and not _em_preparo.has(k):
				faltam.append(k)
	faltam.sort_custom(func(a, b): return (a - c).length_squared() < (b - c).length_squared())
	for k in faltam.slice(0, TAREFAS - _em_preparo.size()):
		_encomendar(k)


func _encomendar(k: Vector2i) -> void:
	var g := gerador
	_em_preparo[k] = WorkerThreadPool.add_task(func():
		var dados := DesenhoChunk.preparar_dados(k, g)
		_trava.lock()
		_fila_pronta[k] = dados
		_trava.unlock())


## Redesenha um chunk já visível (obstáculo limpo ou devolvido): o novo é preparado no fundo e troca o velho.
## Árvores mudaram de estado (queimada, rebrotou): refaz só os objetos dos chunks (rápido, na hora).
func _refazer_arvores(tiles: Array) -> void:
	var ks := {}
	for t in tiles:
		ks[Grade.chunk_de(t)] = true
	for k in ks:
		if chunks.has(k):
			chunks[k].refazer_objetos()


## Árvore carbonizada cai vento abaixo: o chunk esconde a de pé, uma cópia tomba acelerando (1,4 s), bate no chão
## e o chunk passa a desenhar a caída.
func _derrubar(t: Vector2i, dir: Vector2, nome: String) -> void:
	var o := gerador.distribuicao.obstaculo(t)
	if o.is_empty():
		return
	var centro := Grade.centro_da_area(o.ancora, o.area, 0)
	var t0 := Transform3D(Basis(Vector3.UP, Grade.angulo(o.rot)), Grade.ponto_mundo(centro, gerador.micro_em(centro - Vector2(0.5, 0.5))))
	var t1 := DesenhoChunk.tombada(t0, dir)
	var no := MeshInstance3D.new()
	no.mesh = DesenhoChunk.malha(nome + "#queimada", 1.0)
	no.transform = t0
	add_child(no)
	DesenhoChunk.ocultos[t] = true
	_refazer_arvores([t])
	var tw := create_tween()
	tw.tween_method(func(p: float): no.transform = t0.interpolate_with(t1, p * p), 0.0, 1.0, 1.4)
	tw.tween_callback(func():
		Som.tocar("impacto", t1.origin, -14.0)
		no.queue_free()
		DesenhoChunk.ocultos.erase(t)
		_refazer_arvores([t]))


## Vegetação morta pelo ácido afunda no chão corroído: o chunk já não a desenha (o tile ficou limpo); uma cópia
## desbotada afunda devagar, tombando um pouco e encolhendo (4 s), com a gosma borbulhando no pé.
func _dissolver(t: Vector2i, nome: String, tiles: Array, silencioso: bool) -> void:
	var o := gerador.distribuicao.obstaculo(t)
	var rel := construtor._relatorio_vazio()
	rel.limpos.append({"tile": t, "tiles": tiles})
	if silencioso or o.is_empty():
		sincronizar(rel)
		return
	var centro := Grade.centro_da_area(o.ancora, o.area, 0)
	var t0 := Transform3D(Basis(Vector3.UP, Grade.angulo(o.rot)), Grade.ponto_mundo(centro, gerador.micro_em(centro - Vector2(0.5, 0.5))))
	var no := MeshInstance3D.new()
	no.mesh = DesenhoChunk.malha(nome + "#corroida", 1.0)
	no.transform = t0
	add_child(no)
	sincronizar(rel)
	no.add_to_group("pf_afundando")                    # a versão 2D desenha o tronco afundando junto
	no.set_meta("origem", t0.origin)
	no.set_meta("modelo", nome)
	var alto := maxf(1.0, no.mesh.get_aabb().size.y) if no.mesh != null else 3.0
	var lado := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	var eixo := Vector3.UP.cross(lado).normalized() if lado.length() > 0.1 else Vector3.RIGHT
	var bolhas := CPUParticles3D.new()
	bolhas.amount = 18
	bolhas.lifetime = 0.9
	bolhas.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	bolhas.emission_sphere_radius = 0.45
	bolhas.direction = Vector3.UP
	bolhas.spread = 25.0
	bolhas.initial_velocity_min = 0.3
	bolhas.initial_velocity_max = 0.8
	bolhas.gravity = Vector3(0, -1.0, 0)
	bolhas.scale_amount_min = 0.04
	bolhas.scale_amount_max = 0.09
	var esf := SphereMesh.new()
	esf.radius = 0.5
	esf.height = 1.0
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.32, 0.46, 0.08)
	m.emission_enabled = true
	m.emission = Color(0.25, 0.4, 0.05)
	esf.material = m
	bolhas.mesh = esf
	bolhas.position = t0.origin + Vector3(0, 0.05, 0)
	add_child(bolhas)
	Som.tocar("acido_respingo", t0.origin, -12.0)
	var tw := create_tween()
	tw.tween_method(func(p: float):
		var b := Basis(eixo, deg_to_rad(14.0) * p) * t0.basis
		b = b.scaled(Vector3(1.0 - 0.25 * p, 1.0 - 0.35 * p, 1.0 - 0.25 * p))
		no.transform = Transform3D(b, t0.origin - Vector3(0, alto * 0.95 * p * p, 0)), 0.0, 1.0, 4.0)
	no.set_meta("alto", alto)
	tw.tween_callback(func():
		no.queue_free()
		bolhas.emitting = false
		get_tree().create_timer(1.0).timeout.connect(bolhas.queue_free))


func _redesenhar_chunk(k: Vector2i) -> void:
	if chunks.has(k) and not _em_preparo.has(k):
		_encomendar(k)


func _exit_tree() -> void:
	for k in _em_preparo:
		WorkerThreadPool.wait_for_task_completion(_em_preparo[k])


# ------------------------------------------------------------------ construção → desenho
## Desenha o que o Construtor mudou no mapa (relatório de executar/desfazer).
## Tiles que encheram ou secaram: o chão daqueles chunks refaz o mapa da fábrica (canal A = água de jogo).
func _redesenhar_agua() -> void:
	if agua.mudados.is_empty():
		return
	var ks := {}
	for t in agua.mudados:
		for d in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
			ks[Grade.chunk_de(t + d)] = true
	agua.mudados.clear()
	for k in ks:
		if chunks.has(k):
			(chunks[k] as DesenhoChunk).atualizar_fabrica()


func sincronizar(rel: Dictionary) -> void:
	if (not rel.get("aplainados", []).is_empty() or not rel.removidos.is_empty() or not rel.colocados.is_empty()) and agua != null:
		agua.recalcular()                    # escavou, aterrou, fez ou desfez dique: a água refaz o caminho
		_redesenhar_agua()
	var muros := {}
	for e in rel.removidos:
		if _nos.has(e.id):
			_nos[e.id].queue_free()
			_nos.erase(e.id)
		if _lotes != null:
			_lotes.remover(e.id)
		if MUROS.has(e.nome):
			muros[e.minimo] = true
	for id in rel.colocados:
		_criar_no(id, true)
		if MUROS.has(mapa.estruturas[id].nome):
			muros[mapa.estruturas[id].minimo] = true
	var redesenhar := {}
	for l in rel.limpos + rel.restaurados:
		for t in l.tiles:
			redesenhar[Grade.chunk_de(t)] = true
	for k in redesenhar:
		_redesenhar_chunk(k)
	# piso de fábrica e objetos naturais debaixo de construção: só os chunks tocados (com 1 tile de margem)
	var tocados := {}
	var areas: Array = rel.removidos.duplicate()
	for id in rel.colocados:
		if mapa.estruturas.has(id):
			areas.append(mapa.estruturas[id])
	for e in areas:
		if e.nome == "pilar":
			continue
		for t in Grade.tiles_da_area(e.minimo, Registro.area(e.nome), e.rot):
			var m := DesenhoChunk.ESPALHA                 # o piso se espalha até aqui, inclusive no chunk vizinho
			for d in [Vector2i(-m, -m), Vector2i(m, -m), Vector2i(-m, m), Vector2i(m, m)]:
				tocados[Grade.chunk_de(t + d)] = true
	for ap in rel.get("aplainados", []):
		for d in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
			tocados[Grade.chunk_de(ap[0] + d)] = true
	if pesquisa != null and (pesquisa.livre or pesquisa.concluidas.has("recuperar_solo")):
		for ap in rel.get("aplainados", []):
			ambiente.recuperar(ap[0])                   # recuperação de solo: o chão aplainado sai limpo
	var centros: Array = []
	for id in rel.colocados:
		if mapa.estruturas.has(id):
			var en: Dictionary = mapa.estruturas[id]
			if not DesenhoLotes.aceita(en.nome):
				centros.append(Grade.centro_da_area(en.minimo, en.area, en.rot))
	for k in tocados:
		if chunks.has(k) and not redesenhar.has(k):
			chunks[k].atualizar(mapa, centros)
	var religar := {}
	for t in muros:
		for d in [Vector2i.ZERO] + Array(Grade.DIRECOES):
			religar[t + d] = true
	for t in religar:
		_ligar_muro(t)
	var malha_mudou := false
	for e in rel.removidos:
		malha_mudou = malha_mudou or _eh_ferrovia(e.nome)
	for id in rel.colocados:
		malha_mudou = malha_mudou or _eh_ferrovia(mapa.estruturas[id].nome)
	if malha_mudou:
		_remontar_trilhos()
	if not (rel.colocados.is_empty() and rel.removidos.is_empty()):
		_fabrica_suja = true                    # remonta uma vez no próximo tick (vários eventos no mesmo quadro)
	for t in rel.trens:
		if not criar_trem(t.tile, t.get("nome", "trem")):
			construtor.devolver(t.get("nome", "trem"))
			controle._avisar("Não coube: o trem precisa de 12 m de trilho livre (bloco sem outro trem)")


## Nó visual de uma estrutura do mapa. `nova` = posta agora pelo jogador (anima a entrada; máquina parada até
## a simulação dela existir).
func _criar_no(id: int, nova := false) -> Node3D:
	var e: Dictionary = mapa.estruturas[id]
	if e.nome == "pilar":
		return _criar_pilar(id)
	var pos := Grade.ponto_mundo(Grade.centro_da_area(e.minimo, e.area, e.rot), e.get("nivel", 0) * 0.5)
	# rampa de descida: o mesmo modelo virado (a ponta alta fica atrás, de onde vem o item)
	var ang := Grade.angulo(e.rot) + (PI if e.get("desce", false) else 0.0)
	if DesenhoLotes.aceita(e.nome):
		_lotes.adicionar(id, Construtor.modelo_de(e) + ("#desce" if e.get("desce", false) else ""), Transform3D(Basis(Vector3.UP, ang), pos))
		return null
	var cena: PackedScene = load(Registro.modelos[e.nome].modelo)
	var n: Node3D = cena.instantiate()
	add_child(n)
	Materiais.converter(n)
	n.position = pos
	n.rotation.y = ang
	var a: Animador = null
	if Registro.modelos[e.nome].get("partes", []).size() > 1 or Registro.modelos[e.nome].get("anima", false):   # só quem tem peça móvel
		a = Animador.new()
		a.ativo = not nova
		a.modelo = e.nome
		if e.nome.begins_with("braco"):
			_posar_braco(a, e)
		n.add_child(a)
	_nos[id] = n
	if nova:
		var mo := Montagem.new()               # monta parte por parte; o Animador assume no fim
		mo.animador = a
		n.add_child(mo)
	return n


## Pilar de esteira elevada no canto da grade: base + n segmentos de 0,5 m + topo (que segura a esteira).
func _criar_pilar(id: int) -> Node3D:
	var e: Dictionary = mapa.estruturas[id]
	var raiz := Node3D.new()
	raiz.position = Grade.ponto_mundo(Vector2(e.minimo))
	add_child(raiz)
	var k := EsteiraElevada.segmentos(e.altura)
	var pecas: Array = [["pilar_base", 0.0]]
	for i in k:
		pecas.append(["pilar_segmento", i * 0.5])
	pecas.append(["pilar_topo", k * 0.5])
	for p in pecas:
		var no: Node3D = (load(Registro.modelos[p[0]].modelo) as PackedScene).instantiate()
		no.position.y = p[1]
		raiz.add_child(no)
		Materiais.converter(no)
	_nos[id] = raiz
	return raiz


## Pilar de muro → o pano que ele ganha para cada vizinho muro (pedra ou tijolo; muros de tipos diferentes também
## se ligam, cada pilar com o próprio pano até a borda).
const MUROS := {"muro_centro": "muro_lado", "muro_tijolo": "muro_tijolo_lado", "muro_liga": "muro_liga_lado", "muro_escudo": "muro_escudo_lado"}


## Muro: o pilar do tile ganha um pano (muro_lado) para cada vizinho que também é muro.
func _ligar_muro(t: Vector2i) -> void:
	var id: int = mapa.tiles.get(t, -1)
	if id < 0 or not MUROS.has(mapa.estruturas[id].nome) or not _nos.has(id):
		return
	var n: Node3D = _nos[id]
	for c in n.get_children():
		if c.has_meta("muro_lado"):
			n.remove_child(c)
			c.queue_free()
	for d in 4:
		var v: int = mapa.tiles.get(t + Grade.DIRECOES[d], -1)
		if v < 0 or not MUROS.has(mapa.estruturas[v].nome):
			continue
		var lado: Node3D = (load(Registro.modelos[MUROS[mapa.estruturas[id].nome]].modelo) as PackedScene).instantiate()
		lado.set_meta("muro_lado", d)
		n.add_child(lado)
		Materiais.converter(lado)
		lado.rotation.y = Grade.angulo(Construtor.rot_do_fluxo(d)) - n.rotation.y
		var cp: Dictionary = Registro.modelos[MUROS[mapa.estruturas[id].nome]].get("campo", {})
		if not cp.is_empty():
			lado.add_child(parede_de_campo(cp))


## Parede translúcida do muro de campo sobre o trilho do pano ("campo" em modelos.json: faixa y0..y1 × z0..z1, Blender).
static func parede_de_campo(cp: Dictionary) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(float(cp.y1) - float(cp.y0), float(cp.z1) - float(cp.z0))
	var m := ShaderMaterial.new()
	m.shader = preload("res://render/shaders/campo_parede.gdshader")
	m.set_shader_parameter("forca", 0.8)
	m.set_shader_parameter("escala_hex", 1.2)
	var mi := MeshInstance3D.new()
	mi.name = "parede_campo"
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0.0, (float(cp.z0) + float(cp.z1)) * 0.5, -(float(cp.y0) + float(cp.y1)) * 0.5)
	mi.rotation.y = PI * 0.5                      # o quad olha para +Z: a parede corre ao longo do pano (Z), de frente para X
	return mi


# ------------------------------------------------------------------ trens
static func _eh_ferrovia(nome: String) -> bool:
	return nome.begins_with("trilho") or nome in ["sinal_trem", "sinal_cadeia", "estacao"]


## Remonta o grafo depois de mudança na malha; trem sem trilho embaixo some (descarrilou).
func _remontar_trilhos() -> void:
	grafo = GrafoTrilhos.de_mapa(mapa)
	for est in grafo.estacoes:
		if not estoques.has(est.estrutura):
			estoques[est.estrutura] = {"enviar": {}, "recebido": {}}
		Fabrica.tanque_estacao(estoques[est.estrutura])
		if not _rotulos.has(est.estrutura):
			_rotulo_estacao(est.estrutura)
	for t in trens.duplicate():
		if not t.reancorar(grafo):
			trens.erase(t)
			_desenho_colonia._faiscas(Grade.ponto_mundo(t.ponto_em(t.s - t.comprimento() / 2.0).pos, 0.6), 50)


## Põe um trem (locomotiva + 2 vagões + locomotiva; `peca` "trem_tanque" = 2 vagões-tanque) no trilho reto do tile,
## com a cauda na ponta sul/oeste.
func criar_trem(tile: Vector2i, peca := "trem") -> bool:
	var r := grafo.peca_no_ponto(Vector2(tile) + Vector2(0.5, 0.5), 0.1)
	if r.is_empty():
		return false
	var carros: Array[String] = []
	carros.assign(Trem.COMPOSICOES.get(peca, Trem.COMPOSICOES.trem))
	var t := Trem.new(_prox_trem, grafo, carros)
	if not t.colocar(r.peca, grafo.pecas[r.peca].a):
		return false
	_prox_trem += 1
	trens.append(t)
	return true


func _rotulo_estacao(id: int) -> void:
	var e: Dictionary = mapa.estruturas[id]
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 30
	l.outline_size = 10
	l.fixed_size = true                 # mesmo tamanho na tela de perto ou de longe
	l.pixel_size = 0.0011
	l.no_depth_test = true
	l.position = Grade.ponto_mundo(Grade.centro_da_area(e.minimo, e.area, e.rot), 2.7)
	add_child(l)
	_rotulos[id] = l


func _atualizar_rotulos() -> void:
	for id in _rotulos.keys():
		if not estoques.has(id) or not mapa.estruturas.has(id):
			_rotulos[id].queue_free()
			_rotulos.erase(id)
			continue
		var es: Dictionary = estoques[id]
		var linhas: Array[String] = []
		var env := _soma(es.enviar)
		var rec := _soma(es.recebido)
		if env > 0: linhas.append("Para enviar: %d" % env)
		if rec > 0: linhas.append("Recebido: %d" % rec)
		var tq: Dictionary = es.get("fluido", {})
		if float(tq.get("qtd", 0.0)) > 0.0:
			linhas.append("%s: %.0f" % [Registro.nome_fluido(tq.f), float(tq.qtd)])
		_rotulos[id].text = "Estação %d" % _numero_estacao(id) + ("\n" + "\n".join(linhas) if not linhas.is_empty() else "")


## Vagão-tanque: tanque da estação e o modo do cano (só aparece com cano encostado ou fluido no tanque).
func _opcoes_estacao_fluido(id: int, linhas: Array[String], botoes: Array) -> void:
	var tq := Fabrica.tanque_estacao(estoques[id])
	if not fabrica.estacao_tem_bomba(id) and float(tq.qtd) <= 0.0:
		linhas.append("Fluido (vagão-tanque): encoste uma bomba de estação e ligue um cano nela")
		return
	var cap := float(Registro.estruturas.get("estacao", {}).get("tanque_fluido", 25000))
	linhas.append("Tanque: %s %.0f de %.0f" % [Registro.nome_fluido(tq.f) if tq.f != "" else "vazio", float(tq.qtd), cap])
	for m in [["desligado", "Bomba desligada"], ["carregar", "Cano → trem (carregar)"], ["descarregar", "Trem → cano (descarregar)"]]:
		var modo: String = m[0]
		botoes.append({"texto": m[1], "ligado": tq.get("modo", "desligado") == modo, "acao": func():
			tq["modo"] = modo
			_detalhe()})


static func _soma(d: Dictionary) -> int:
	var n := 0
	for k in d:
		n += int(d[k])
	return n




# ------------------------------------------------------------------ fábrica de demonstração
## Procura, em espiral, o lugar livre mais perto de `perto` (para a demo não cair em cima de árvore).
func _achar_lugar(nome: String, perto: Vector2i, rot := 0) -> Vector2i:
	for r in 12:
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) == r and mapa.motivo_bloqueio(nome, perto + Vector2i(dx, dy), rot) == "":
					return perto + Vector2i(dx, dy)
	return perto


func _instanciar(nome: String, minimo: Vector2i, rot: int, procurar := false) -> Node3D:
	if procurar:
		minimo = _achar_lugar(nome, minimo, rot)
	# a demo limpa os obstáculos da área e de 1 tile em volta (no jogo, quem limpa é o jogador)
	var ar := Grade.area_girada(Registro.area(nome), rot)
	for dx in range(-1, ar.x + 1):
		for dy in range(-1, ar.y + 1):
			mapa.limpar_obstaculo(minimo + Vector2i(dx, dy))
	var motivo := mapa.motivo_bloqueio(nome, minimo, rot)
	var id := mapa.colocar(nome, minimo, rot)
	if id < 0:
		push_warning("demo: não coube %s em %s (%s)" % [nome, minimo, motivo])
		return null
	return _criar_no(id)


## Igual a _instanciar, mas devolve o id da estrutura (−1 se não coube).
func _instanciar_id(nome: String, minimo: Vector2i, rot: int, procurar := false) -> int:
	var id := mapa._prox_id
	_instanciar(nome, minimo, rot, procurar)
	return id if mapa.estruturas.has(id) else -1


## Mini-fábrica pronta, montada só com peças do mapa — quem faz funcionar é a mesma Fabrica que roda o que o
## jogador constrói: extrator → esteira → braço → estação A → trem → estação B; gerador + postes; torre abastecida
## por braço a partir de um baú de munição.
func _montar_fabrica() -> void:
	_instanciar("extrator_cristal", Vector2i(14, 4), 0)
	var porta := Grade.porta_no_mundo(Registro.estruturas["extrator_cristal"].portas[0], Vector2i(14, 4), Vector2i(3, 3), 0)
	var t0: Vector2i = porta.tile_fora
	var tb := t0 + Vector2i(0, -5)
	for k in 5:
		mapa.limpar_obstaculo(t0 + Vector2i(0, -k))
	sincronizar(construtor.executar(construtor.plano_linha("esteira", t0, t0 + Vector2i(0, -4), 2)))
	_instanciar("braco", tb, 2)
	_instanciar("estacao", tb + Vector2i(-1, -3), 0)
	# ferrovia norte–sul encostada a oeste das estações: A (carrega) e B, 18 tiles ao sul
	var xl := tb.x - 2
	_instanciar("trilho_fim", Vector2i(xl, tb.y + 5), 0)
	for y in range(tb.y - 26, tb.y + 5):
		_instanciar("trilho_reto", Vector2i(xl, y), 0)
	_instanciar("trilho_fim", Vector2i(xl, tb.y - 27), 2)
	_instanciar("estacao", tb + Vector2i(-1, -22), 0)
	_remontar_trilhos()
	criar_trem(Vector2i(xl, tb.y - 14))
	# energia: gerador (com carvão para começar) e postes até o extrator e os braços
	var g := _instanciar_id("gerador", Vector2i(8, 6), 0)
	for p in [Vector2i(11, 6), Vector2i(17, 3), Vector2i(17, -2)]:
		_instanciar("poste_energia", p, 0)
	# defesa: torre com braço trazendo munição de um baú; outra torre só com a munição inicial
	_instanciar("torre_defesa", Vector2i(18, -6), 0)
	var bau := _instanciar_id("bau", Vector2i(19, -3), 0)
	_instanciar("braco", Vector2i(19, -4), 2)
	_instanciar("torre_defesa", Vector2i(4, -2), 0, true)
	_instanciar("fornalha", Vector2i(9, -4), 0, true)
	fabrica.reconstruir()
	_fabrica_suja = false
	construtor._historico.clear()                 # a demo não entra no desfazer do jogador
	obras.dar_iniciais()
	if g >= 0:
		fabrica.combustivel[g] = 300.0
	if bau >= 0:
		fabrica.baus[bau]["municao"] = 30


# ------------------------------------------------------------------ simulação
func _process(delta: float) -> void:
	_passo_autosalvar(delta / maxf(Engine.time_scale, 0.001))
	for i in relogio.avancar(delta):
		_tick_mundo(relogio.dt())
	_animar_estruturas()
	_t_teia -= delta
	if _t_teia <= 0.0:
		_t_teia = 1.0
		_desenhar_teia()
	# modo construção (peça na mão): caminho e sentido das esteiras em destaque
	_fluxo.ligado = controle != null and controle.peca != ""
	# grama: por quadrante, perto do ponto olhado e dentro do oval de visão (DesenhoVisao → DesenhoChunk.ajustar_grama)
	RenderingServer.global_shader_parameter_set("alvo_camera", camera.alvo)
	# letreiros só de perto (a névoa por zoom e clima fica no DesenhoClima)
	# sombra até onde se vê (celular: mais curta — de cima a diferença quase não aparece)
	($Sol as DirectionalLight3D).directional_shadow_max_distance = clampf(camera.distancia * 1.1, 25.0, 60.0) if OS.has_feature("mobile") \
			else clampf(camera.distancia * 1.6, 30.0, 110.0)
	for l in _rotulos.values():
		l.visible = camera.distancia < 75.0 and not _visao.ligada     # na visão de recursos só os nomes do mapa
	_desenho_trens.sincronizar(trens)
	for ev in _eventos:
		match ev.tipo:
			"destruida":
				_efeitos.marcar_destruicao(ev.centro, Registro.area(ev.nome).x)
				Som.tocar("aranha_morre", Grade.ponto_mundo(ev.centro), -4.0)
			"aranha_morta":
				Som.tocar("aranha_morre", Grade.ponto_mundo(ev.pos))
			"ataque":
				Som.tocar("alerta")
	eventos_desenho.emit(_eventos)                    # versão 2D: desenha os mesmos tiros/explosões
	_desenho_colonia.atualizar(_eventos, delta)
	_eventos.clear()
	for ev in _eventos_drones:
		if ev.tipo == "drone_sem_placa" and is_instance_valid(controle):
			controle._avisar("Drones de reparo sem placas de ferro no núcleo")
	_eventos_obras(delta)
	eventos_desenho.emit(_eventos_drones)             # versão 2D: tiro dos drones
	_desenho_drones.atualizar(_eventos_drones, delta)
	_eventos_drones.clear()
	_t_hud -= delta
	if _t_hud <= 0.0:
		_t_hud = 0.25
		_atualizar_rotulos()
		_hud()
	_t_som_maquinas -= delta
	if _t_som_maquinas <= 0.0:
		_t_som_maquinas = 0.35
		_atualizar_sons_mundo()
	_atualizar_chunks()


## Infestação no chão: refaz a imagem dos chunks que ela toca (e dos que ela deixou) quando muda ou o chunk é novo.
func _desenhar_teia() -> void:
	var atuais := infestacao.chunks()
	var tocados := atuais.duplicate()
	var mudou := infestacao.versao != _teia_versao
	_teia_versao = infestacao.versao
	for k in _teia_chunks.keys():
		if not tocados.has(k):
			tocados[k] = true                    # saiu da infestação: limpa uma vez
	for k in tocados:
		var d: DesenhoChunk = chunks.get(k)
		if d == null or not is_instance_valid(d):
			_teia_chunks.erase(k)
			continue
		if not mudou and _teia_chunks.get(k) == d.get_instance_id():
			continue
		d.atualizar_teia(infestacao.imagem(k))
		_teia_chunks[k] = d.get_instance_id()
	for k in _teia_chunks.keys():
		if not atuais.has(k):
			_teia_chunks.erase(k)            # já limpo acima


## Sons contínuos de máquinas trabalhando, da esteira e dos trens perto da câmera: cada um é um laço (Som.loop_maquina)
## renovado aqui a cada 0,35 s; quando a máquina para ou sai do alcance, o laço some com fade. Só as 6 máquinas mais
## perto tocam (máquina igual soa igual; muitas juntas viram ruído).
const MAQ_SONS := [["broca", "maq_broca", -5.0], ["fornalha", "maq_fornalha", -6.0], ["montadora", "maq_montadora", -5.0]]
const MAQ_PERTO := 6


func _atualizar_sons_mundo() -> void:
	if DisplayServer.get_name() == "headless" or camera == null:
		return
	var p_cam: Vector3 = camera.alvo
	var perto: Array = []
	for id in fabrica.maquinas:
		if not fabrica.trabalhando(id):
			continue
		var e: Dictionary = mapa.estruturas.get(id, {})
		if e.is_empty():
			continue
		for m in MAQ_SONS:
			if String(e.nome).begins_with(m[0]):
				var p := Grade.ponto_mundo(Grade.centro_da_area(e.minimo, e.area, e.rot))
				var d := p.distance_to(p_cam)
				if d <= 55.0:
					perto.append([d, id, p, m[1], m[2]])
				break
	perto.sort_custom(func(a, b): return a[0] < b[0])
	for k in mini(perto.size(), MAQ_PERTO):
		var m: Array = perto[k]
		Som.loop_maquina("maq%d" % m[1], m[3], m[2], m[4])
	var melhor := INF                                           # esteira: a mais perto que está levando item
	var p_est := Vector3.ZERO
	for c in fabrica.caminhos:
		if c.esteira.itens.size() == 0:
			continue
		for t in c.tiles:
			var pt := Grade.centro_mundo(t)
			var d := pt.distance_squared_to(p_cam)
			if d < melhor:
				melhor = d
				p_est = pt
	if melhor <= 45.0 * 45.0:
		Som.loop_maquina("esteira", "maq_esteira", p_est, -9.0, 45.0)
	for i in trens.size():
		var t = trens[i]
		if absf(t.v) > 0.15 and t.acum.size() > 1:             # v = velocidade (m/s); acum vazio = sem trilho
			var pt := Grade.ponto_mundo(t.ponto_em(t.s).pos)
			if pt.distance_to(p_cam) <= 55.0:
				Som.loop_maquina("trem%d" % i, "trem_trilho", pt, -5.0)


## Distância e altura do pulso nas duas pontas do braço: esteira/chão baixo; baú/máquina mais alto e um pouco antes
## do centro (a garra para em cima da borda, não dentro do corpo).
func _posar_braco(a: Animador, e: Dictionary) -> void:
	var alc := float(Registro.estruturas.get(e.nome, {}).get("alcance", 1))
	if Registro.estruturas.get(e.nome, {}).has("alcance_max"):     # braço quântico: a lança estica até a origem escolhida
		a.alcance = float(Fabrica.alcance_origem(e))
		return
	var fr := Grade.DIRECOES[Construtor.fluxo_da_rot(e.rot)] * int(alc)
	var ponta := func(t: Vector2i) -> Vector2:
		var id: int = mapa.tiles.get(t, -1)
		if id < 0 or Construtor.no_esteira(mapa.estruturas[id]).size() > 0:
			return Vector2(alc, 0.42)
		var dims: Array = Registro.modelos.get(mapa.estruturas[id].nome, {}).get("dims", [1, 1, 0.6])
		return Vector2(alc - 0.22, minf(float(dims[2]) + 0.1, 0.9))
	a.pega = ponta.call(e.minimo - fr)
	a.solta = ponta.call(e.minimo + fr)


func ponto_garra(id: int) -> Vector3:
	var a := _animador(id)
	return a.ponto_garra() if a != null else Vector3.INF


## Onde a neblina abre: máquinas queimando/trabalhando (as que poluíram neste passo) e trens. (x, z do mundo, raio)
func _fontes_calor() -> Array:
	var r: Array = []
	for id in fabrica.emissao:
		var e: Dictionary = mapa.estruturas.get(id, {})
		if e.is_empty():
			continue
		var p := Grade.ponto_mundo(Grade.centro_da_area(e.minimo, e.area, e.rot))
		r.append(Vector3(p.x, p.z, 3.0 + 0.8 * maxf(e.area.x, e.area.y)))
	for t in trens:
		var p := Grade.ponto_mundo(t.ponto_em(t.s).pos)
		r.append(Vector3(p.x, p.z, 4.0))
	return r


const GIRO_ORIGEM := [PI, PI / 2.0, -PI / 2.0]      ## atrás, esquerda, direita do braço (modo Radial)


## Animação segue a simulação: máquina mexe só trabalhando; braço pela fase do ciclo.
var _versao_bracos := -1
var _turbinas: Array = []
var _maq_clima: Array = []                  ## semeador, defletor, cúpula, regulador (animam com a zona ativa)
var _bombas_est: Array = []                 ## bombas de estação (animam bombeando)
var _logica: Array = []                     ## sensores, comparadores e válvulas (rede lógica)
var _sensores_v: Array = []                 ## sensores de varredura (giram com energia)
var _farois: Array = []                     ## faróis de cristal (o carrossel gira aceso)
var _lancadores: Array = []                 ## lançadores de sementes (o laço do estudo toca uma vez por disparo)
var _receptores: Array = []                 ## receptores de cápsulas (o laço toca uma vez por cápsula)
var _transportadores: Array = []            ## transportadores quânticos (anéis giram enquanto trocam itens)
var _silos: Array = []                      ## silos de lançamento (robôs e umbilicais montando ou lançando)
var _labs_2: Array = []                     ## laboratórios 2 e quânticos (carrossel, gaveta e braço enquanto pesquisam)
var _irradiadores: Array = []               ## irradiadores de módulos
var _postes_altos: Array = []               ## postes altos (o anel de ressonância gira passando energia)
var _turbinas_rio: Array = []               ## turbinas de correnteza (rotor e boia no ritmo do rio)
var _geradores_fl: Array = []               ## geradores a fluido (ventiladores, volante e anel enquanto queimam)
var _paineis_2: Array = []                  ## painéis solares 2 (o rastreador segue o sol de dia)
var _singularidades: Array = []             ## núcleos de singularidade (anéis e disco enquanto ligados)
var _arcos := ArcosEletricos.new()
var _grupos_anim: Dictionary = {}           ## nome da estrutura → índices (em _listas_anim) das listas em que entra


## As listas acima, numa passada só pelo mapa (17 filtros separados custavam 25 ms numa fábrica de 1 700 peças).
## A que listas um nome pertence é decidido uma vez por nome.
func _refazer_listas_animacao() -> void:
	var listas: Array = []
	for i in 17:
		listas.append([])
	for id in mapa.estruturas:
		var nome: String = mapa.estruturas[id].nome
		var grupos: Array = _grupos_anim.get(nome, [])
		if not _grupos_anim.has(nome):
			var regra: Dictionary = Registro.estruturas.get(nome, {})
			var testes := [regra.get("renovavel", "") == "vento", regra.has("clima_local"), nome == "bomba_estacao",
					regra.get("grupo", "") == "logica", Varredura.eh_sensor(nome), Farol.eh_farol(nome), Lancador.eh_lancador(nome),
					Genese.eh_receptor(nome), Transportador.eh_transportador(nome), SiloLancamento.eh_silo(nome), nome == "poste_alto",
					nome in ["laboratorio_2", "laboratorio_quantico"], regra.has("irradiador"), regra.has("perda_nuvem"),
					nome == "nucleo_singularidade", Fabrica.eh_gerador_fluido(nome) or Fabrica.eh_reator(nome), regra.get("renovavel", "") == "rio"]
			for i in testes.size():
				if testes[i]:
					grupos.append(i)
			_grupos_anim[nome] = grupos
		for g in grupos:
			listas[g].append(id)
	_turbinas = listas[0]
	_maq_clima = listas[1]
	_bombas_est = listas[2]
	_logica = listas[3]
	_sensores_v = listas[4]
	_farois = listas[5]
	_lancadores = listas[6]
	_receptores = listas[7]
	_transportadores = listas[8]
	_silos = listas[9]
	_postes_altos = listas[10]
	_labs_2 = listas[11]
	_irradiadores = listas[12]
	_paineis_2 = listas[13]
	_singularidades = listas[14]
	_geradores_fl = listas[15]
	_turbinas_rio = listas[16]


func _animar_estruturas() -> void:
	if _versao_bracos != mapa.versao:              # vizinho mudou: refaz onde cada braço pega/solta
		_versao_bracos = mapa.versao
		_refazer_listas_animacao()
		for id in fabrica.bracos:
			var ab := _animador(id)
			if ab != null and mapa.estruturas.has(id):
				_posar_braco(ab, mapa.estruturas[id])
	for id in fabrica.maquinas:
		var a := _animador(id)
		if a != null:
			a.ativo = animar_tudo or fabrica.trabalhando(id)
	# irradiador: antenas e cristal giram com energia e módulo encaixado
	for id in _irradiadores:
		var a := _animador(id)
		if a != null:
			a.ativo = animar_tudo or (fabrica.energia(id) > 0.0 and not fabrica.modulos_de(id).is_empty())
	# laboratório 2 e quântico: carrossel, gaveta e braço (laço do estudo) só enquanto pesquisam
	for id in _labs_2:
		var a := _animador(id)
		if a != null:
			a.ativo = animar_tudo or fabrica.lab_trabalhando(id)
	# bomba de estação: ventoinha, ponteiro e setas trabalham enquanto ela move fluido
	for id in _bombas_est:
		var a := _animador(id)
		if a != null:
			a.ativo = animar_tudo or fabrica.bomba_ativa(id)
	# rede lógica: sensor de esteira anima contando; válvula, passando fluido; comparador, ligado
	for id in _logica:
		var a := _animador(id)
		if a == null or not mapa.estruturas.has(id):
			continue
		match mapa.estruturas[id].nome:
			"sensor_esteira": a.ativo = animar_tudo or fabrica.sensor_contando(id)
			"valvula": a.ativo = animar_tudo or fabrica.valvula_passou.has(id)
			"comparador": a.ativo = animar_tudo or fabrica.ligada(id)
			"sensor_tanque": a.ativo = animar_tudo or float(fabrica.rede_de(id).get("qtd", 0.0)) > 0.0
	# sensor de varredura: o giro e a antena (laço do estudo) trabalham com energia, no ritmo dela
	for id in _sensores_v:
		var a := _animador(id)
		if a != null:
			var en := 1.0 if animar_tudo else varredura.energia_de(id)
			a.ativo = en > 0.0
			a.ritmo = clampf(en, 0.2, 1.0)
	# farol de cristal: o carrossel óptico (laço do estudo) gira enquanto a luz está acesa
	for id in _farois:
		var a := _animador(id)
		if a != null:
			a.ativo = farol.aceso(id) or (animar_tudo and farol.energia_de(id) > 0.0)
			a.ritmo = 1.0
	# lançador de sementes: culatra, recuo e pistões (laço do estudo) só durante o disparo
	for id in _lancadores:
		var a := _animador(id)
		if a != null:
			a.ativo = lancador.disparando(id)
	for id in _receptores:
		var a := _animador(id)
		if a != null:
			a.ativo = genese.animando(id)
	for id in _silos:
		var a := _animador(id)
		if a != null:
			a.ativo = silo.montando(id)
	# poste alto: o anel de ressonância (laço do estudo) gira enquanto passa energia pela rede dele
	for id in _postes_altos:
		var a := _animador(id)
		if a != null:
			a.ativo = animar_tudo or fabrica.transmitindo(id)
	# gerador a fluido e reatores: o laço do estudo (ventiladores, anéis, plasma) enquanto queimam para a rede
	for id in _geradores_fl:
		var a := _animador(id)
		if a != null:
			a.ativo = animar_tudo or (float(fabrica.combustivel.get(id, 0.0)) > 0.0 and fabrica.kw_de(id) < 0.0 and fabrica.transmitindo(id))
	for id in _singularidades:
		var a := _animador(id)
		if a != null:
			a.ativo = animar_tudo or fabrica.ligada(id)
	# painel solar 2: rastreador, limpadores e lentes (laço do estudo) de dia, com ele ligado
	for id in _paineis_2:
		var a := _animador(id)
		if a != null:
			a.ativo = animar_tudo or (fabrica.sol_limpo > 0.05 and fabrica.ligada(id))
	# turbina de correnteza: o rotor gira (e a boia sobe e desce) no ritmo da vazão do rio; desligada, para
	for id in _turbinas_rio:
		var a := _animador(id)
		if a != null:
			var v := 1.0 if animar_tudo else (fabrica.rio if fabrica.ligada(id) else 0.0)
			a.ativo = v > 0.0
			a.ritmo = clampf(v, 0.2, 1.0)
	for id in _transportadores:
		var a := _animador(id)
		if a != null:
			a.ativo = transportador.trabalhando(id) or (animar_tudo and transportador.energia_de(id) > 0.0)
	# estação de drones: garras, plugue e braço abastecedor trabalham quando um drone nasce, pousa ou decola
	for est in drones.estacoes():
		var a := _animador(est)
		if a == null:
			continue
		var mexe: bool = animar_tudo or (fabrica.maquinas.has(est) and fabrica.maquinas[est].estado == Maquina.Estado.TRABALHANDO)
		for dr in drones.drones.values():
			if dr.est == est and dr.e in [Drones.E.NASCENDO, Drones.E.DECOLANDO, Drones.E.POUSANDO]:
				mexe = true
		a.ativo = mexe
	# acumulador: cristal acende com a carga; faíscas entre as bobinas (mais ainda carregando/descarregando)
	_arcos.fontes.clear()
	for id in fabrica.acumulado:
		var a := _animador(id)
		if a == null or not mapa.estruturas.has(id):
			continue
		a.ativo = animar_tudo or fabrica.ligada(id)
		var cap := float(Registro.estruturas.get(mapa.estruturas[id].nome, {}).get("acumula_mj", 1.0))
		var cheio: float = 1.0 if animar_tudo else clampf(float(fabrica.acumulado[id]) / cap, 0.0, 1.0)
		var fluxo := absf(float(fabrica.rede.estat_de(id).get("carga", 0.0))) > 1.0
		a.brilho = cheio if a.ativo else 0.0
		if a.ativo and (cheio > 0.02 or fluxo):
			_arcos.fontes[id] = {"no": _nos[id], "forca": clampf(cheio * 0.7 + (0.5 if fluxo else 0.0), 0.0, 1.0)}
	# gerador de escudo: cardã, pistões e ventoinhas trabalham enquanto há carga; o cristal acende com ela
	for id in colonia._lista_escudos:
		var a := _animador(id)
		if a == null or not mapa.estruturas.has(id):
			continue
		var cap := fabrica.carga_max(id)
		var f := 1.0 if animar_tudo else clampf(float(fabrica.carga_torre.get(id, 0.0)) / cap, 0.0, 1.0)
		a.ativo = f > 0.01
		a.brilho = f
	# máquinas de clima: a animação do estudo toca enquanto a zona delas está ativa (ligada e com energia)
	if not _maq_clima.is_empty():
		var ativas := {}
		for z in clima_local.zonas:
			ativas[z.id] = true
		for id in _maq_clima:
			var a := _animador(id)
			if a != null:
				a.ativo = animar_tudo or ativas.has(id)
				a.brilho = 1.0 if a.ativo else 0.2
	for id in _turbinas:
		if mapa.estruturas.has(id):
			var a := _animador(id)
			if a != null:
				a.ativo = animar_tudo or fabrica.ligada(id)
				var et: Dictionary = mapa.estruturas[id]
				a.rumo_vento = clima_local.vento_em(Grade.centro_da_area(et.minimo, et.area, et.rot), clima.direcao_vento, 1.0).normalized()
				var vt := float(fabrica.vento_turbina.get(id, fabrica.vento))
				a.ritmo = 0.15 if fabrica.em_protecao(id) else (0.0 if Fabrica.curva_turbina(vt) <= 0.0 else 0.3 + vt)
	# silo de granel: canecas, rosca e comporta trabalham por 2 s depois que algo entra ou sai
	for id in fabrica.baus:
		if not fabrica.um_tipo(id):
			continue
		var a := _animador(id)
		if a == null:
			continue
		var n := 0
		for k in fabrica.baus[id]:
			n += int(fabrica.baus[id][k])
		if n != int(_silo_total.get(id, -1)):
			_silo_total[id] = n
			_silo_mexeu[id] = _tempo
		a.ativo = animar_tudo or _tempo - float(_silo_mexeu.get(id, -99.0)) < 2.0
	for id in fabrica.bracos:
		var a := _animador(id)
		if a != null:
			a.fase_braco = fposmod(_tempo * 0.45 + id * 0.137, 1.0) if animar_tudo else fabrica.bracos[id].fase()
			a.giro_origem = GIRO_ORIGEM[fabrica.bracos[id].origem_i]


func _animador(id: int) -> Animador:
	var n: Node3D = _nos.get(id)
	if n == null:
		return null
	for c in n.get_children():
		if c is Animador:
			return c
	return null


## Poluição, aranhas e trens (rodam mesmo se a mini-fábrica parar).
func _tick_mundo(dt: float) -> void:
	# renováveis: sol (luz, menos nuvem e chuva) e vento do clima de agora
	fabrica.sol = clampf(clima.luz_dia() * float(clima.valores.luz) * (1.0 - 0.5 * float(clima.valores.nuvens)) * (1.0 - 0.6 * float(clima.valores.chuva)), 0.0, 1.0)
	fabrica.sol_limpo = clampf(clima.luz_dia(), 0.0, 1.0)                 # painel solar 2: perde só "perda_nuvem" com o tempo
	fabrica.encoberto = clampf(maxf(float(clima.valores.nuvens), float(clima.valores.chuva)), 0.0, 1.0)
	# vento: cada turbina sente o vento do lugar dela (relevo, mata, sombra de construção) e as rajadas que passam
	clima.foco = Vector2(Grade.tile_de_mundo(camera.alvo))
	fabrica.vento = float(clima.valores.vento)
	fabrica.chuva = float(clima.valores.chuva)          # coletor de chuva
	fabrica.neblina = float(clima.valores.neblina)      # condensador de neblina
	fabrica.rio = clima.vazao_rio()                     # turbina de correnteza (seca no verão, cheia com chuva)
	clima_local.atualizar()                             # máquinas de clima com energia mudam o tempo em volta
	fabrica.vento_turbina.clear()
	for id in _turbinas:
		if mapa.estruturas.has(id):
			var et: Dictionary = mapa.estruturas[id]
			var c := Grade.centro_da_area(et.minimo, et.area, et.rot)
			fabrica.vento_turbina[id] = clima_local.forca_vento_em(c, clima.vento_em(c) * vento_local.fator(Vector2i(c.floor()), clima.direcao_vento, float(Registro.estruturas.get(et.nome, {}).get("altura_vento", 0.0))))
	fabrica.chuva_maq.clear()
	if not clima_local.zonas.is_empty():
		for id in fabrica.maquinas:
			if fabrica.maquinas[id].receita_id == "coletar_chuva" and mapa.estruturas.has(id):
				var ec: Dictionary = mapa.estruturas[id]
				fabrica.chuva_maq[id] = clima_local.chuva_em(Grade.centro_da_area(ec.minimo, ec.area, ec.rot), fabrica.chuva)
	poluicao.vento = clima.direcao_vento * float(clima.valores.vento)
	poluicao.vento_chunks = clima_local.vento_chunks()
	if _fabrica_suja:
		fabrica.reconstruir()
		_fabrica_suja = false
	poluicao.fator = maxf(0.1, 1.0 + pesquisa.bonus("poluicao_global"))     # Simbiose: −50%
	var fator_trem := 1.0 + pesquisa.bonus("velocidade_trens")              # Velocidade de frota N
	for t in trens:
		t.fator_vel = fator_trem
	fabrica.tick(dt)
	for id in fabrica.concluidas:
		if pesquisa.infinita(id):
			controle._avisar("%s: nível %d concluído (segue no %d)" % [pesquisa.pesquisas()[id].nome, pesquisa.nivel(id), pesquisa.nivel(id) + 1])
		else:
			controle._avisar("Pesquisa concluída: %s" % pesquisa.pesquisas()[id].nome)
		Som.tocar("pesquisa")
		controle.barra.atualizar_bloqueios()
	# quem trabalhou polui no próprio chunk e vira alvo das aranhas por 60 s
	var fontes_vivas: Array[Dictionary] = []
	for id in fabrica.emissao:
		var e: Dictionary = mapa.estruturas[id]
		poluicao.emitir(e.minimo, fabrica.emissao[id])
		_poluiu_em[id] = _tempo
	for id in _poluiu_em.keys():
		if not mapa.estruturas.has(id) or _tempo - _poluiu_em[id] > 60.0:
			_poluiu_em.erase(id)
			continue
		var e: Dictionary = mapa.estruturas[id]
		fontes_vivas.append({"id": id, "pos": Grade.centro_da_area(e.minimo, e.area, e.rot)})
	clima.poluicao_total = poluicao.total()
	clima.tick(dt)
	raios.tick(clima)                                   # o raio cai num ponto do mapa (para-raios, dano, fogo)
	if raios.total != _raios_vistos and is_instance_valid(controle):     # a vida caiu por causa do raio: diga
		_raios_vistos = raios.total
		for q in raios.quedas:                          # (o desenho limpa a lista depois, no quadro)
			if q.tipo == "estrutura" and mapa.estruturas.has(q.id):
				controle._avisar("Raio atingiu %s (−%d de vida): para-raios e cúpula protegem" % [controle.barra.rotulo(mapa.estruturas[q.id].nome), int(q.dano)])
	poluicao.chuva = clima.valores.chuva
	ambiente.tick(dt, fabrica, clima)
	agua.tick(dt)
	_redesenhar_agua()
	for ev in ambiente.eventos:
		if ev.tipo == "fogo_inicio" and is_instance_valid(controle):
			controle._avisar("Incêndio! A vegetação seca pegou fogo perto de uma máquina quente")
		elif ev.tipo == "tufao_dano" and is_instance_valid(controle) and _tempo - _aviso_tufao_em > 20.0:
			_aviso_tufao_em = _tempo
			controle._avisar("Tufão: a rajada castiga %d peça(s) frágil(eis) — postes, rampas, sinais; o defletor de vento protege" % int(ev.n))
		elif ev.tipo == "arvores_mudaram":
			_refazer_arvores(ev.tiles)
		elif ev.tipo == "arvore_caiu":
			_derrubar(ev.tile, ev.dir, ev.nome)
		elif ev.tipo == "vegetacao_queimada":
			var rel := construtor._relatorio_vazio()
			rel.limpos.append({"tile": ev.tile, "tiles": ev.tiles})
			sincronizar(rel)
	ambiente.eventos.clear()
	poluicao.tick(dt)
	colonia.tick(dt, fontes_vivas)
	infestacao.tick(dt)
	for ev in infestacao.eventos:                       # o ácido das larvas consome as árvores do chão corroído
		if ev.tipo == "arvores_mudaram":
			_refazer_arvores(ev.tiles)
		elif ev.tipo == "arvore_dissolvida":
			_dissolver(ev.tile, ev.nome, ev.tiles, bool(ev.silencioso))
	infestacao.eventos.clear()
	# pássaros: tiro, explosão e raio espantam; o foco é onde a câmera olha
	for ev in colonia.eventos:
		if ev.tipo == "tiro":
			passaros.assustar(ev.de, 14.0)
		elif ev.tipo == "explosao":
			passaros.assustar(ev.pos, 16.0 + 6.0 * float(ev.get("raio", 1.0)))
	while _raios_passaros < raios.total:
		_raios_passaros += 1
		if not raios.quedas.is_empty():
			passaros.assustar(raios.quedas[-1].get("pos", Vector2.ZERO), 30.0)
	passaros.tick(dt, Vector2(camera.alvo.x, -camera.alvo.z), clima)
	for ev in colonia.eventos:                          # quem morre avisa o ecossistema (fase 4: vira carcaça)
		if ev.tipo == "aranha_morta":
			ecossistema.morreu("alien", String(ev.get("especie", "aranha")), ev.pos)
	ecossistema.tick(dt, Vector2(camera.alvo.x, -camera.alvo.z))
	plantas_reagem.tick(dt, clima, ecossistema.foco)
	frutos.tick(dt, clima, ecossistema.foco)
	_desenho_passaros.efeitos_de(passaros.eventos)
	passaros.eventos.clear()
	_eventos.append_array(colonia.eventos)
	varredura.tick(dt)                                  # sensores revelam chunks (e os ninhos deles) com energia
	varredura.eventos.clear()
	farol.tick(dt)                                      # faróis acesos à noite: tiram a névoa e veem as aranhas
	for ev in farol.eventos:
		if ev.tipo == "aranhas_no_farol" and is_instance_valid(controle):
			var d: Vector2 = (ev.de as Vector2) - farol.centro(ev.id)
			controle._avisar("🔦 Farol: %d aranha(s) na luz, chegando %s" % [ev.n, Clima.nome_rumo(-d)])
	farol.eventos.clear()
	for id in lancador.lancadores:                      # parado (sem semente, alvo inválido) puxa só 5% da energia
		fabrica.fator_kw[id] = 0.05 if lancador.ocioso(id) else 1.0
	for id in fabrica.fator_kw.keys():
		if not lancador.lancadores.has(id):
			fabrica.fator_kw.erase(id)
	lancador.tick(dt)                                   # lançadores carregam, disparam; a semente pousa e vira posto
	for ev in lancador.eventos:
		match ev.tipo:
			"disparo_inicio":
				var a := _animador(ev.id)
				if a != null:
					a.reiniciar()
					a.ativo = true
			"semente_lancada":
				Som.tocar("tiro", Grade.ponto_mundo(lancador.centro(ev.id), 3.0), 0.0)
				if is_instance_valid(controle):
					controle._avisar("🚀 Núcleo-semente lançado: pousa a %d m, %s" % [roundi(lancador.centro(ev.id).distance_to(ev.para)),
							Lancador.RUMOS[lancador.rumo(ev.id)]])
			"semente_pousou":
				sincronizar(ev.rel)
				Som.tocar("impacto", Grade.ponto_mundo(ev.para, 0.5), 0.0)
				if is_instance_valid(controle):
					controle._avisar("🌱 A semente pousou: nasceu uma colônia (fabrica pacote gênese)" if ev.get("colonia", false)
							else "🌱 A semente pousou: nasceu um posto avançado (núcleo-filho)")
			"semente_perdida":
				if is_instance_valid(controle):
					controle._avisar("⚠ A semente se perdeu: o pouso estava ocupado, na água ou num desnível")
	lancador.eventos.clear()
	genese.tick(dt)                                     # colônias fabricam pacote gênese e mandam por cápsula
	for ev in genese.eventos:
		match ev.tipo:
			"capsula_chegou":
				var a := _animador(ev.receptor)
				if a != null:
					a.reiniciar()
					a.ativo = true
				Som.tocar("impacto", Grade.ponto_mundo(genese.centro(ev.receptor), 1.0), -8.0)
			"capsula_perdida":
				if is_instance_valid(controle):
					controle._avisar("⚠ Uma cápsula de pacote gênese se perdeu (o receptor saiu ou encheu)")
	genese.eventos.clear()
	transportador.tick(dt)                              # transportadores quânticos trocam itens pelo canal
	silo.tick(dt)                                       # silos montam o foguete; o lançamento encerra a campanha
	for ev in silo.eventos:
		match ev.tipo:
			"carga_pronta":
				if is_instance_valid(controle):
					controle._avisar("🚀 Foguete de proliferação pronto: lance pelo painel do silo")
			"lancamento_inicio":
				var a := _animador(ev.id)
				if a != null:
					a.reiniciar()
					a.ativo = true
				if mapa.estruturas.has(ev.id):
					Som.tocar("trovao", Grade.ponto_mundo(genese.centro(ev.id), 2.0), 0.0)
			"foguete_lancado":
				Som.tocar("pesquisa")
				if is_instance_valid(pausa) and not OS.get_cmdline_user_args().has("roteiro"):
					pausa.abrir(false, true)               # tela de vitória (dá para continuar jogando)
	silo.eventos.clear()
	drones.tick(dt)
	_eventos_drones.append_array(drones.eventos)
	_obras_eventos.append_array(obras.eventos)
	obras.eventos.clear()
	_tempo += dt
	if _relatorio:
		_t_rel -= dt
		if _t_rel <= 0.0:
			_t_rel = 30.0
			var est := {}
			for a in colonia.aranhas.values():
				est[a.estado] = int(est.get(a.estado, 0)) + 1
			var perto := INF
			for n in colonia.ninhos.values():
				perto = minf(perto, n.centro.distance_to(Vector2(15, 0)))
			var maq := {}
			for id in fabrica.maquinas:
				maq[mapa.estruturas[id].nome] = Maquina.Estado.keys()[fabrica.maquinas[id].estado]
			print("t=%4.0fs  polu=%.0f (chunks %d)  ninhos=%d (mais perto %.0f)  aranhas=%s  trens=%s  municao=%s  estruturas=%d  maq=%s  comb=%s  estoques=%s" % [
					_tempo, poluicao.total(), poluicao.valores.size(), colonia.ninhos.size(), perto, est,
					trens.map(func(t): return "%s/%d" % [Trem.Estado.keys()[t.estado], t.total_carga()]),
					colonia.torres.values().map(func(t): return t.municao), mapa.estruturas.size(), maq,
					fabrica.combustivel.values().map(func(v): return snappedf(v, 0.1)), estoques.values()])
	var energia_trilho := fabrica.energia_trilho
	for t in trens:
		var alimenta := t.energizar(energia_trilho)          # elétrica: 2× no trilho energizado com energia
		if alimenta >= 0 and t.v > 0.05:
			fabrica.pedir_trilho(alimenta, Trem.KW_ELETRICA)
		var diesel := t.locomotivas_diesel()
		if diesel > 0 and t.v > 0.05:                     # a diesel polui andando (a elétrica não)
			poluicao.emitir(Vector2i((t.ponto_em(t.s).pos as Vector2).floor()), Trem.POLUICAO_DIESEL * diesel / 60.0 * dt)
		t.tick(dt)
		if t.chegada >= 0:
			Som.tocar("apito_trem", Grade.ponto_mundo(t.ponto_em(t.s).pos), -3.0)
			if estoques.has(t.chegada):
				t.trocar_carga(estoques[t.chegada], t.chegada)
			t.chegada = -1
		if t.retroca >= 0:                       # esperando a condição da rota: troca de novo (sem apito)
			if estoques.has(t.retroca):
				t.trocar_carga(estoques[t.retroca], t.retroca)
			t.retroca = -1


# ------------------------------------------------------------------ seleção (painel de detalhe)
const NOMES_ESTADO := {Maquina.Estado.SEM_RECEITA: "sem receita — escolha abaixo", Maquina.Estado.SEM_INSUMO: "esperando insumo",
		Maquina.Estado.SAIDA_CHEIA: "saída cheia (tire os produtos)", Maquina.Estado.SEM_ENERGIA: "sem energia",
		Maquina.Estado.SEM_JAZIDA: "jazida esgotada", Maquina.Estado.TRABALHANDO: "trabalhando",
		Maquina.Estado.ESPERANDO_CLIMA: "esperando o tempo mudar", Maquina.Estado.PRONTIDAO: "de prontidão (com água, vigiando)",
		Maquina.Estado.DESLIGADA: "desligada"}


## Clique/toque de mão vazia: trem perto do ponto, senão a estrutura do tile. Vector2.INF fecha.
## Gira uma estrutura já construída (mesmo id, mesmo estado) e redesenha; avisa se não couber.
func girar_estrutura(id: int) -> void:
	if not mapa.estruturas.has(id):
		return
	var antes: Dictionary = mapa.estruturas[id].duplicate()
	antes["id"] = id
	if not mapa.girar(id):
		controle._avisar("Não dá para girar: a peça girada encosta em outra construção")
		return
	Som.tocar("clique")
	sincronizar({"colocados": [id] as Array[int], "removidos": [antes] as Array[Dictionary], "limpos": [] as Array[Dictionary],
			"restaurados": [] as Array[Dictionary], "trens": [] as Array[Dictionary], "estoque": {}, "aplainados": []})
	_detalhe()


## Ações da estrutura selecionada (botões do painel e atalhos do PC). false = não fez nada.
func alternar_ligada(id: int) -> bool:
	if not mapa.estruturas.has(id) or not _tem_liga(id):
		return false
	var e: Dictionary = mapa.estruturas[id]
	if e.get("desligada", false):
		e.erase("desligada")
	else:
		e["desligada"] = true
	Som.tocar("clique")
	_fabrica_suja = true
	_detalhe()
	return true


func _tem_liga(id: int) -> bool:
	var e: Dictionary = mapa.estruturas[id]
	return Fiacao.papel(e.nome) in ["consumo", "fonte"] or fabrica.maquinas.has(id) or e.nome in ["comparador", "valvula"]


var _confirmando_remocao_bau: int = -1


func total_itens_bau(id: int) -> int:
	if not fabrica.baus.has(id):
		return 0
	var total := 0
	for k in fabrica.baus[id]:
		total += int(fabrica.baus[id][k])
	return total


func eh_armazem_com_itens(id: int) -> bool:
	if not mapa.estruturas.has(id):
		return false
	var nome: String = mapa.estruturas[id].nome
	if nome in ["bau", "bau_grande", "silo_granel", "bau_estoque"] or Registro.estruturas.get(nome, {}).get("grupo", "") == "armazem":
		return total_itens_bau(id) > 0
	return false


func pedir_confirmacao_remocao_bau(id: int) -> void:
	if not mapa.estruturas.has(id):
		return
	_sel = {"estrutura": id}
	_confirmando_remocao_bau = id
	_detalhe()
	if is_instance_valid(controle):
		controle._avisar("Este baú tem %d itens. Remover e perder?" % total_itens_bau(id))


func confirmar_remocao_bau(id: int, enviar_central: bool = false) -> bool:
	if not mapa.estruturas.has(id):
		_confirmando_remocao_bau = -1
		return false
	if enviar_central:
		enviar_bau_para_central(id)
	_confirmando_remocao_bau = -1
	return remover_estrutura(id, true)


func enviar_bau_para_central(id: int, item_especifico: String = "") -> int:
	if not fabrica.baus.has(id):
		return 0
	var b: Dictionary = fabrica.baus[id]
	var transferidos := 0
	if item_especifico != "":
		var q := int(b.get(item_especifico, 0))
		if q > 0:
			inventario[item_especifico] = int(inventario.get(item_especifico, 0)) + q
			b.erase(item_especifico)
			transferidos = q
	else:
		for it in b.keys():
			var q := int(b[it])
			if q > 0:
				inventario[it] = int(inventario.get(it, 0)) + q
				transferidos += q
		b.clear()
	if transferidos > 0:
		Som.tocar("clique")
		if is_instance_valid(controle):
			if is_instance_valid(controle.barra):
				controle.barra.estoque(inventario)
			if item_especifico != "":
				controle._avisar("Enviado para a central: %d %s" % [transferidos, _nome_item(item_especifico)])
			else:
				controle._avisar("Enviado para a central: %d item(ns)" % transferidos)
	return transferidos


func remover_estrutura(id: int, forcar: bool = false) -> bool:
	if not mapa.estruturas.has(id) or mapa.estruturas[id].nome == "nucleo":
		return false
	if not forcar and eh_armazem_com_itens(id):
		pedir_confirmacao_remocao_bau(id)
		return false
	_confirmando_remocao_bau = -1
	if obras != null:                             # patch RTS: o drone vai lá desmontar
		if not obras.remover(id):
			return false
		Som.tocar("remover")
		if is_instance_valid(controle):
			controle._avisar("Remoção encomendada: o drone construtor vai desmontar")
		_sel = {}
		_detalhe()
		return true
	var e: Dictionary = mapa.estruturas[id]
	var plano: Array[Dictionary] = []
	for it in construtor.plano_remocao(e.minimo, e.minimo):
		if it.get("id", -1) == id and it.motivo == "":
			plano.append(it)
	if plano.is_empty():
		return false
	sincronizar(construtor.executar(plano))
	Som.tocar("remover")
	if is_instance_valid(controle):
		controle._avisar("Removido (Ctrl+Z desfaz)" if Tema.estilo("atalhos") else "Removido")
	_sel = {}
	_detalhe()
	return true


var _copia: Dictionary = {}          ## configuração copiada no painel (só na sessão, não vai no save)


func copiar_config_de(id: int) -> bool:
	if not mapa.estruturas.has(id) or not fabrica.tem_config(id):
		return false
	_copia = fabrica.copiar_config(id)
	controle._avisar("Configuração copiada: %s" % controle.barra.rotulo(_copia.nome))
	_detalhe()
	return true


func colar_config_em(id: int) -> bool:
	if not fabrica.pode_colar(id, _copia):
		if not _copia.is_empty():
			controle._avisar("A cópia é de %s: só cola em outra igual" % controle.barra.rotulo(_copia.nome))
		return false
	var r := fabrica.colar_config(id, _copia, func(rc: String) -> bool: return pesquisa.receita_liberada(rc))
	if r.remontar:
		_fabrica_suja = true
	Som.tocar("clique")
	controle._avisar("Configuração colada" + (" (receita ainda não pesquisada ficou de fora)" if r.receita_pulada != "" else ""))
	_detalhe()
	return true


## Atalho de teclado na estrutura selecionada. acao: "ligar", "girar", "remover", "copiar", "colar", "fechar". false = não havia o que fazer.
func atalho_selecao(acao: String) -> bool:
	if not _sel.has("estrutura") or not mapa.estruturas.has(_sel.estrutura):
		return false
	var id: int = _sel.estrutura
	match acao:
		"ligar": return alternar_ligada(id)
		"girar":
			if mapa.estruturas[id].nome == "pilar" or mapa.estruturas[id].get("nivel", 0) != 0:
				return false
			girar_estrutura(id)
			return true
		"remover": return remover_estrutura(id)
		"copiar": return copiar_config_de(id)
		"colar": return colar_config_em(id)
		"fechar":
			_sel = {}
			_detalhe()
			return true
	return false


func selecionar(p: Vector2) -> void:
	_confirmando_remocao_bau = -1
	_sel = {}
	if p != Vector2.INF:
		for t in trens:
			for pose in t.poses():
				if pose.pos.distance_to(p) < 1.6:
					_sel = {"trem": t.id}
		if _sel.is_empty():
			var id: int = mapa.tiles.get(Vector2i(p.floor()), -1)
			if id >= 0 and not Colonia.eh_toca(mapa.estruturas[id].nome):
				_sel = {"estrutura": id}
	_detalhe()


## Contorno no mundo da estrutura aberta no painel; some quando o painel fecha.
func _atualizar_selecao() -> void:
	if not is_inside_tree() or get_tree() == null:
		return
	if _desenho_selecao == null:
		_desenho_selecao = DesenhoSelecao.new()
		add_child(_desenho_selecao)
	if _sel.has("estrutura") and mapa.estruturas.has(_sel.estrutura):
		_desenho_selecao.mostrar(mapa.estruturas[_sel.estrutura])
	else:
		_desenho_selecao.esconder()


var _desenho_selecao: DesenhoSelecao


func _nome_item(i: String) -> String:
	return Registro.itens.get(i, {}).get("nome", i)


## Itens e fluidos de um lado da receita ("1 Resina + 20 Água").
func _lista_receita(rec: Dictionary, lado: String) -> String:
	var partes: Array[String] = []
	var it := _lista_itens(rec.get(lado, {}))
	if it != "—":
		partes.append(it)
	var fl: Dictionary = rec.get(lado + "_fluido", {})
	for f in fl:
		partes.append("%d %s" % [fl[f], Registro.nome_fluido(f)])
	return ", ".join(partes) if not partes.is_empty() else "—"


func _lista_itens(d: Dictionary) -> String:
	var partes: Array[String] = []
	for k in d:
		if int(d[k]) > 0:
			partes.append("%d %s" % [d[k], _nome_item(k)])
	return ", ".join(partes) if not partes.is_empty() else "—"


func _numero_estacao(id: int) -> int:
	for i in grafo.estacoes.size():
		if grafo.estacoes[i].estrutura == id:
			return i + 1
	return 0


## Munição especial guardada na torre (perfurante, carregada, enxame): gasta a mais forte primeiro.
func _linha_especiais(t: Dictionary, linhas: Array[String]) -> void:
	var es: Dictionary = t.get("especial", {})
	var partes: Array[String] = []
	for k in es:
		if int(es[k]) > 0:
			partes.append("%s %d" % [_nome_item(k), int(es[k])])
	if not partes.is_empty():
		linhas.append("Especial: %s (gasta a mais forte primeiro)" % ", ".join(partes))


## Encaixes de módulo no painel: o que está encaixado (tocar tira e devolve ao núcleo), o efeito de agora e um botão por
## módulo do estoque do núcleo que cabe. `vel` < 0 = sem linha de velocidade (irradiador).
func _opcoes_modulos(id: int, e: Dictionary, vel: float, linhas: Array[String], botoes: Array) -> void:
	var lista := fabrica.modulos_de(id)
	var total := Fabrica.encaixes(e.nome)
	var ef: Dictionary = fabrica.efeito_modulos(id)
	var cab := "Módulos: %d de %d" % [lista.size(), total]
	if vel >= 0.0:
		cab = "Velocidade %.2f · %s" % [vel, cab]
		if ef != Fabrica.EFEITO_NEUTRO:
			cab += " · energia ×%.2f · poluição ×%.2f%s" % [float(ef.energia), float(ef.poluicao), (" · +%d%% de produto" % roundi(float(ef.produtividade) * 100.0)) if float(ef.produtividade) > 0.0 else ""]
	linhas.append(cab)
	for i in lista.size():
		botoes.append({"texto": "✕ Tirar %s" % _nome_item(lista[i]), "acao": func(): fabrica.tirar_modulo(id, i); _detalhe()})
	if lista.size() >= total:
		return
	var gratis := not construtor.cobrar
	var tem := false
	for item in Registro.itens:
		if not Fabrica.eh_modulo(item) or not fabrica.aceita_modulo(id, item):
			continue
		var n := int(inventario.get(item, 0))
		if (gratis and pesquisa.receita_liberada(item)) or n > 0:
			tem = true
			botoes.append({"texto": "＋ %s%s" % [_nome_item(item), "" if gratis else " (%d no núcleo)" % n], "acao": func(): fabrica.por_modulo(id, item, gratis); _detalhe()})
	if not tem:
		linhas.append("Para encaixar: leve módulos prontos ao núcleo (montadora → braço ou esteira → núcleo)")


## Painel do silo de lançamento: partes, propelente, carga-semente e o botão de lançar.
func _detalhe_silo(id: int, linhas: Array[String], opcoes: Array) -> void:
	var r := SiloLancamento.regra(mapa.estruturas[id].nome)
	var it := silo.itens(id)
	linhas.append("Foguete de proliferação: %d de %d partes%s" % [silo.partes(id), int(r.get("partes", 100)), " · carga-semente dentro" if silo.tem_carga(id) else ""])
	var pede: Array[String] = []
	for k in r.get("parte", {}):
		pede.append("%d %s (%d dentro)" % [int(r.parte[k]), _nome_item(k).to_lower().replace("_", " "), int(it.get(k, 0))])
	for fl in r.get("parte_fluido", {}):
		pede.append("%d %s pelo cano (%.0f no tanque)" % [int(r.parte_fluido[fl]), fl.replace("_", " "), silo.propelente(id)])
	linhas.append("Cada parte: %s" % ", ".join(pede))
	var pc: Array[String] = []
	for k in r.get("carga", {}):
		pc.append("%d %s (%d)" % [int(r.carga[k]), _nome_item(k).to_lower().replace("_", " "), int(it.get(k, 0))])
	linhas.append("Carga-semente (pesquisa Foguete de proliferação): %s" % ", ".join(pc))
	match silo.motivo(id):
		"": linhas.append("Montando: %d%%" % (float(mapa.estruturas[id].get("silo_t", 0.0)) / float(r.get("parte_s" if silo.partes(id) < int(r.get("partes", 100)) else "carga_s", 10)) * 100))
		"sem_energia": linhas.append("Parado: sem energia (%d kW)" % int(Registro.estruturas[mapa.estruturas[id].nome].get("energia_kw", 0)))
		"faltam_itens": linhas.append("Esperando as peças (braço nas bocas sul e oeste)")
		"falta_propelente": linhas.append("Esperando o propelente de cristal (cano na boca leste)%s" % ("" if fabrica.silo_no_cano(id) else " — SEM CANO na boca"))
		"falta_pesquisa_carga": linhas.append("Partes prontas: a carga-semente espera a pesquisa Foguete de proliferação")
		"pronto": linhas.append("PRONTO PARA LANÇAR")
		"lancando": linhas.append("LANÇANDO…")
	if int(mapa.estruturas[id].get("lancados", 0)) > 0:
		linhas.append("Foguetes lançados daqui: %d" % int(mapa.estruturas[id].lancados))
	if silo.pronto(id) and not silo.lancando.has(id):
		opcoes.append({"texto": "🚀 Lançar o foguete (fim da campanha)", "acao": func(): silo.lancar(id); _detalhe()})


## Painel do lançador de sementes: semente, alvo (rumo e distância), carga e por que está parado.
func _detalhe_lancador(id: int, linhas: Array[String], opcoes: Array, botoes: Array) -> void:
	var r := Lancador.regra(mapa.estruturas[id].nome)
	linhas.append("Núcleo-semente: %d de %d (entra por braço; boca sul)" % [lancador.sementes(id), int(r.get("capacidade", 1))])
	var d := lancador.distancia(id)
	linhas.append("Alvo: %d m a %s — onde pousa nasce um posto avançado (núcleo-filho)" % [roundi(d), Lancador.RUMOS[lancador.rumo(id)]])
	match lancador.motivo(id):
		"": linhas.append("Carregando: %d%% (%d kW)" % [lancador.carga(id) * 100, int(Registro.estruturas[mapa.estruturas[id].nome].get("energia_kw", 0))])
		"disparando": linhas.append("DISPARANDO")
		"sem_semente": linhas.append("Parado: sem núcleo-semente (montadora; receita da pesquisa Núcleo-semente)")
		"desligado": linhas.append("Desligado")
		"sem_energia": linhas.append("Parado: sem energia (poste perto)")
		"alvo_invalido": linhas.append("Alvo inválido: água, desnível ou ocupado em volta — escolha outro rumo ou distância")
	if not lancador.voos.is_empty():
		linhas.append("Sementes no ar: %d" % lancador.voos.filter(func(v): return int(v.lancador) == id).size())
	for i in 8:
		var ri: int = i
		opcoes.append({"texto": "Rumo: %s" % Lancador.RUMOS[ri], "ligado": lancador.rumo(id) == ri, "acao": func(): lancador.mirar(id, ri, lancador.distancia(id)); _detalhe()})
	var passo := 50
	var dmin := int(r.get("alcance_min", 60))
	var dmax := int(r.get("alcance", 400))
	for dd in [-100, -passo, passo, 100]:
		var ddd: int = dd
		botoes.append({"texto": "Distância %+d m (agora %d, de %d a %d)" % [ddd, roundi(d), dmin, dmax], "acao": func():
			lancador.mirar(id, lancador.rumo(id), lancador.distancia(id) + ddd); _detalhe()})


## Painel do posto avançado (núcleo-filho): energia própria, estoque e o raio da obra que paga com ele.
func _detalhe_posto(id: int, e: Dictionary, regra: Dictionary, linhas: Array[String], botoes_posto: Array, grade: Array) -> void:
	_opcoes_filtro_bau(id, e, linhas, grade)
	var b: Dictionary = fabrica.baus[id]
	var n := 0
	for k in b:
		n += int(b[k])
	var maquinas := 0
	for o in Fiacao.fios(e):
		if mapa.estruturas.has(o) and Fiacao.papel(mapa.estruturas[o].nome) in ["consumo", "fonte"]:
			maquinas += 1
	linhas.append("Núcleo-filho: %d kW próprios, sem cabo, para as máquinas até %d m da borda (%d ligada%s)" % [-int(regra.get("energia_kw", 0)),
			int(regra.get("raio_ligacao", 7)), maquinas, "" if maquinas == 1 else "s"])
	linhas.append("Estoque próprio: %d de %d itens (entra e sai por braço; drones logísticos usam como estoque)" % [n, fabrica.capacidade_bau(id)])
	_inventario_bau(id, e, botoes_posto)
	if construtor.cobrar:
		linhas.append("Obras a até %d m pagam primeiro com este estoque; o que faltar sai do núcleo" % int(regra.posto.get("raio_obra", 32)))
	if genese.eh_colonia(id):
		var rr := genese.receptor_para(genese.centro(id))
		linhas.append("COLÔNIA: fabrica 1 pacote gênese a cada %d s (próximo em %d s) → %s" % [int(Genese.cfg(e.nome).get("genese_s", 30)), ceili(genese.falta_s(id)),
				"cápsula para o receptor a %d m" % roundi(genese.centro(rr).distance_to(genese.centro(id))) if rr >= 0
				else "sem receptor de cápsulas com energia e lugar: %d esperando aqui" % genese.esperando(id)])


## Painel do sensor de varredura: quantos chunks já revelou, o próximo, os ninhos marcados e (profunda) as jazidas.
func _detalhe_varredura(id: int, linhas: Array[String]) -> void:
	var lim := varredura.limite(id)
	var feito := varredura.feitos(id)
	var en := varredura.energia_de(id)
	var regra_v: Dictionary = Varredura.regra(mapa.estruturas[id].nome)
	linhas.append("Revela os chunks em volta, 1 a cada %d s: %d de %d revelados%s" % [int(regra_v.get("intervalo_s", 60)), feito, lim,
			"" if varredura.e_profunda() else " (Varredura profunda: até %d)" % int(regra_v.get("chunks_profunda", 16))])
	if feito >= lim:
		linhas.append("Varredura completa: segue vigiando os ninhos desses chunks")
	elif en <= 0.0:
		linhas.append("Parado (precisa de energia: poste perto)")
	else:
		linhas.append("Próximo chunk em %d s%s" % [ceili(varredura.falta_s(id)), "" if en >= 0.99 else " (energia em %d%%)" % (en * 100)])
	var ns := varredura.ninhos_do_sensor(id)
	if ns.is_empty():
		linhas.append("Nenhum ninho nos chunks revelados")
	else:
		var c := varredura.centro(id)
		var partes: Array[String] = []
		for n in ns:
			var d: Vector2 = (colonia.ninhos[n].centro as Vector2) - c
			partes.append("%d m a %s" % [roundi(d.length()), Clima.nome_rumo(-d).trim_prefix("de ")])
		linhas.append("Ninhos marcados no mapa (%d): %s" % [ns.size(), ", ".join(partes)])
	if varredura.e_profunda():
		var jz := varredura.jazidas(id)
		if jz.is_empty():
			linhas.append("Jazidas: nenhuma nos chunks revelados")
		for j in jz.slice(0, 6):
			var info: Dictionary = Registro.recursos.get("jazidas", {}).get(j.tipo, {"nome": j.tipo})
			var dj: Vector2 = (j.centro as Vector2) - varredura.centro(id)
			linhas.append("Jazida de %s: ≈ %s (%s, riqueza ×%s) a %d m, %s" % [str(info.nome).to_lower(), VisaoRecursos._quantidade(int(j.total)),
					j.nivel, String.num(float(j.riqueza), 2), roundi(dj.length()), Clima.nome_rumo(-dj).trim_prefix("de ")])


func _detalhe() -> void:
	_atualizar_selecao()
	if not is_instance_valid(controle) or not is_instance_valid(controle.barra):
		return
	var barra := controle.barra
	if _sel.has("pesquisa"):
		_detalhe_pesquisa()
		return
	if _sel.has("trem"):
		var t: Trem = null
		for x in trens:
			if x.id == _sel.trem: t = x
		if t == null:
			_sel = {}
		else:
			var est := {Trem.Estado.ANDANDO: "andando", Trem.Estado.PARADO: "parado na estação" + (" (esperando a condição)" if t.espera <= 1.0 and t.condicao(t.parado_em) in ["cheio", "vazio"] else ""),
					Trem.Estado.ESPERANDO_BLOCO: "esperando sinal", Trem.Estado.SEM_ROTA: "sem rota"}
			var texto := "Estado: %s\nCarga: %s (%d de %d)\nRota: toque nas estações para ligar/desligar.\nSem nenhuma ligada, passa por todas." % [
					est[t.estado], _lista_itens(t.carga), t.total_carga(), t.capacidade()]
			if t.capacidade_fluido() > 0.0:
				texto += "\nVagões-tanque: %s %.0f de %.0f" % [Registro.nome_fluido(t.fluido) if t.fluido != "" else "vazios",
						t.fluido_qtd, t.capacidade_fluido()]
			var botoes := []
			for e in grafo.estacoes:
				var id: int = e.estrutura
				var na_rota := t.rota.has(id)
				var ordem := t.rota.find(id) + 1
				botoes.append({"texto": "Estação %d%s" % [_numero_estacao(id), "  (parada %d)" % ordem if na_rota else ""],
						"ligado": na_rota, "acao": func():
							if t.rota.has(id): t.rota.erase(id)
							else: t.rota.append(id)
							t.proxima = 0
							t.planejar()
							_detalhe()})
			if pesquisa.modo_liberado("trem_condicao"):
				# rotas com condição (trem_automatico): toque troca a espera da parada (parada curta → 30 s → até encher
				# → até esvaziar)
				var nomes_c := {"": "parada curta", "tempo": "espera %d s" % int(Trem.ESPERA_TEMPO), "cheio": "até encher",
						"vazio": "até esvaziar"}
				for e in t.paradas():
					var id_c: int = e.estrutura
					var c_atual := t.condicao(id_c)
					botoes.append({"texto": "Estação %d: %s" % [_numero_estacao(id_c), nomes_c[c_atual]], "acao": func():
						var i := Trem.CONDICOES.find(c_atual)
						var prox: String = Trem.CONDICOES[(i + 1) % Trem.CONDICOES.size()]
						if prox == "":
							t.condicoes.erase(str(id_c))
						else:
							t.condicoes[str(id_c)] = prox
						_detalhe()})
			botoes.append({"texto": "Desmontar trem (devolve o material)", "acao": func():
				trens.erase(t)
				grafo.liberar(t.id)
				construtor.devolver(t.peca())
				_sel = {}
				_detalhe()})
			barra.detalhe("Trem %d" % t.id, texto, botoes)
			barra.detalhe_maquina({})
			return
	if _sel.has("estrutura") and not mapa.estruturas.has(_sel.estrutura):
		_sel = {}
	if _sel.is_empty():
		barra.fechar_detalhe()
		return
	var id: int = _sel.estrutura
	var e: Dictionary = mapa.estruturas[id]
	var titulo: String = controle.barra.rotulo(e.nome)
	if int(e.get("classe", 1)) > 1:
		titulo += " (%s)" % {2: "rápida", 3: "expressa", 4: "quântica"}.get(int(e.classe), "nível %d" % int(e.classe))
	var linhas: Array[String] = []
	var botoes := []
	var opcoes := []                     ## opções internas (reparar, ligar, modo) vêm antes das receitas
	var grade_filtro := []               ## escolha de itens do braço (grade de ícones): por último no painel
	var regra: Dictionary = Registro.estruturas.get(e.nome, {})
	var vida_max: float = regra.get("vida", 0)
	var compacto := Tema.estilo("painel_compacto")   # PC: o que tem cabeçalho, barra ou casa própria não repete em texto
	if vida_max > 0.0:
		var v: float = colonia.vida.get(id, vida_max)
		if not compacto:
			linhas.append("Integridade: %d de %d (%d%%)%s" % [ceilf(v), vida_max, v / vida_max * 100.0, "" if v < vida_max else " — inteira"])
		var custo := custo_reparo(id)
		if not custo.is_empty() and not Colonia.eh_toca(e.nome):
			opcoes.append({"texto": "Reparar (%s)" % _lista_itens(custo), "acao": func(): reparar(id); _detalhe(), "secao": "acoes", "icone_txt": "✚ Reparar"})
	if fabrica.maquinas.has(id):
		var m: Maquina = fabrica.maquinas[id]
		if not compacto:
			linhas.append("Estado: %s" % NOMES_ESTADO[m.estado])
			if m.receita_id != "":
				linhas.append("Receita: %s → %s" % [_lista_receita(m.receita, "entradas"), _lista_receita(m.receita, "saidas")])
			linhas.append("Dentro: %s\nPronto: %s" % [_lista_itens(m.entradas), _lista_itens(m.saidas)])
			if m.tempo_total >= 10.0:
				linhas.append(_texto_estatistica(m))
		if fabrica.combustivel.has(id):
			linhas.append("Combustível: %.1f MJ" % fabrica.combustivel[id])
		for fl in m.fluidos:
			linhas.append("%s: %.0f" % [Registro.nome_fluido(fl), m.fluidos[fl]])
		if regra.has("encaixes_modulo"):
			_opcoes_modulos(id, e, m.velocidade, linhas, botoes)
		var tipo: String = Registro.estruturas[e.nome].get("maquina", "")
		match tipo:
			"broca", "extrator":
				var est_j := fabrica.estado_jazida_de(id)
				var ext_j := fabrica.extraido_jazida_de(id)
				var ritmo_txt := "100%" if est_j == "rica" else ("50%" if est_j == "cansada" else "25%")
				linhas.append("Jazida: %s (%s extraídos · %s ritmo)" % [est_j, PainelRecursos.numero_curto(ext_j), ritmo_txt])
			"bomba":
				var c: float = ambiente.contaminacao.get(id, 0.0)
				linhas.append("Poça limpa" if c <= 0.0 else "Poça contaminada: %d%% — rende %d%% menos e desgasta a bomba (um Filtro de água ou Coletor perto limpa)"
						% [c * 100, c * float(Registro.ambiente.bomba.perda_producao) * 100])
			"filtro":
				linhas.append("Limpa a água suja num raio de %d m enquanto tem energia" % Registro.estruturas[e.nome].limpa.raio)
				if m.receita_id == "filtrar_agua_limpa":
					linhas.append("Solta %d de água limpa/s pelo cano enquanto limpa (sem cano, a sobra volta ao rio)" % Registro.receitas.filtrar_agua_limpa.saidas_fluido.agua_limpa)
			"bomba_agua":
				var ca: float = ambiente.contaminacao.get(id, 0.0)
				linhas.append("Tomada limpa: %d de água/s" % Registro.receitas.bombear_agua.saidas_fluido.agua if ca <= 0.0
						else "Água suja na tomada: %d%% — rende %d%% menos (um Filtro de água perto limpa)" % [ca * 100, ca * float(regra.get("agua_suja_perde", 0.6)) * 100])
			"coletor_chuva":
				var ch := float(fabrica.chuva_maq.get(id, fabrica.chuva))
				linhas.append("Chuva aqui: %d%% → %.0f de água/s (até %d com chuva forte); tanque %.0f de %d"
						% [ch * 100, ch * Registro.receitas.coletar_chuva.saidas_fluido.agua, Registro.receitas.coletar_chuva.saidas_fluido.agua,
						float(m.fluidos.get("agua", 0.0)), m.tanque_fluido])
			"captador":
				var cr: Dictionary = regra.capta_raio
				linhas.append("Pega os raios a até %d m (antes dos para-raios) · raios pegos: %d" % [cr.raio, int(raios.descargas.get(id, 0))])
				linhas.append("Cada raio carrega 1 cristal lapidado (30 de água) em 1 cristal carregado; a sobra (%d MJ) vai para os acumuladores da rede" % cr.mj)
				linhas.append("Tempo agora: %s%s" % [clima.nome(), " — raios caindo" if Registro.clima.estados[clima.atual].get("raios", false) else " (raios só em tempestade e tufão)"])
			"condensador":
				linhas.append("Neblina agora: %d%% → %.0f de água/s (até %d com neblina; mais no inverno)"
						% [fabrica.neblina * 100, fabrica.neblina * Registro.receitas.condensar_neblina.saidas_fluido.agua, Registro.receitas.condensar_neblina.saidas_fluido.agua])
			"supressor":
				var ap: Dictionary = regra.get("apaga", {})
				var c0s := Grade.centro_da_area(e.minimo, e.area, e.rot)
				var focos := 0
				for t in ambiente.fogo:
					if (Vector2(t) + Vector2(0.5, 0.5)).distance_to(c0s) <= float(ap.get("raio", 8)):
						focos += 1
				linhas.append("Reservatório: %.0f de %d de água · gasta %d/s só quando há fogo" % [float(m.fluidos.get("agua", 0.0)), m.tanque_fluido, ap.get("agua_por_s", 10)])
				linhas.append(("Fogo no raio de %d m: %d foco(s)" % [ap.get("raio", 8), focos]) if focos > 0
						else "Com água, a vegetação num raio de %d m não pega fogo" % ap.get("raio", 8))
			"coletor":
				if regra.has("residuo"):
					linhas.append("Aspira sujeira, óleo e cinza num raio de %d m e compacta em resíduo (1 a cada %.1f recolhido; guarda até %d)"
							% [regra.limpa.raio, float(regra.residuo.por), int(regra.residuo.max)])
				else:
					linhas.append("Aspira sujeira e óleo do chão num raio de %d m enquanto tem energia" % Registro.estruturas[e.nome].limpa.raio)
			"purificador":
				var pu: Dictionary = regra.purifica
				var k_c := Grade.chunk_de(Vector2i(Grade.centro_da_area(e.minimo, e.area, e.rot).floor()))
				linhas.append("Tira %d de poluição por minuto do ar deste chunk (agora: %.1f)%s" % [pu.por_min, poluicao.em_chunk(k_c),
						" e condensa em resíduo (1 a cada %d)" % int(pu.residuo_por) if pu.has("residuo_por") else ""])
			"biodigestor":
				linhas.append("Resíduo (braço) + água (cano sul) → biomassa (braço) + seiva (cano leste)")
			"tratamento":
				linhas.append("Limpa a água suja num raio de %d m e solta %d de água limpa/s pelo cano leste (sem cano, a sobra volta ao rio)"
						% [regra.limpa.raio, Registro.receitas.tratar_agua.saidas_fluido.agua_limpa])
			"semeador_bioma":
				var rs: Dictionary = regra.restaura
				var c_s := Grade.centro_da_area(e.minimo, e.area, e.rot)
				var queimadas := 0
				for t in mapa.arvores:
					if (Vector2(t) + Vector2(0.5, 0.5)).distance_to(c_s) <= float(rs.raio):
						queimadas += 1
				linhas.append("Com seiva: tira o queimado do chão em %d m e, a cada ciclo, devolve até %d árvores carbonizadas e planta %d mudas do bioma · árvores queimadas no raio: %d"
						% [rs.raio, rs.arvores, rs.mudas, queimadas])
			"estacao_drones":
				_detalhe_estacao_drones(id, e, linhas, opcoes)
			"viveiro":
				var c0 := Grade.centro_da_area(e.minimo, e.area, e.rot)
				var r: float = Registro.estruturas[e.nome].planta.raio
				var n := 0
				for t in ambiente.plantas:
					if (Vector2(t) + Vector2(0.5, 0.5)).distance_to(c0) <= r + 0.5:
						n += 1
				linhas.append("Plantas em volta: %d (cada ciclo com 10 de seiva planta uma muda)" % n)
				if Registro.estruturas[e.nome].planta.get("especie_bioma", false):
					var esp := ambiente.especie_do_bioma(Vector2i(c0.floor()))
					linhas.append("Espécie do bioma: %s · mudas crescem %.0f× mais rápido" % [Registro.recursos.get("elementos", {}).get(esp, esp) if esp != "" else "a padrão (bioma sem árvore)",
							float(Registro.estruturas[e.nome].planta.get("cresce", 1.0))])
		if tipo in ["montadora", "refinador", "fornalha", "forja"]:
			var l2: Maquina = fabrica.linha2.get(id)
			if l2 != null:
				linhas.append("Linha 2: %s · %s\nDentro: %s\nPronto: %s" % [NOMES_ESTADO[l2.estado], ("%s → %s" % [_lista_receita(l2.receita, "entradas"), _lista_receita(l2.receita, "saidas")]) if l2.receita_id != "" else "sem receita",
						_lista_itens(l2.entradas), _lista_itens(l2.saidas)])
			for r in Registro.receitas_da_maquina(tipo):
				if not pesquisa.receita_liberada(r) or not Registro.receita_cabe(r, e.nome):
					continue
				var rec: Dictionary = Registro.receitas[r]
				botoes.append({"texto": "%s%s  ←  %s" % ["1: " if l2 != null else "", _lista_receita(rec, "saidas"), _lista_receita(rec, "entradas")],
						"receita": _dados_receita(rec), "grupo_receita": "Receita (linha 1)" if l2 != null else "Receita",
						"ligado": m.receita_id == r, "acao": func(): fabrica.escolher_receita(id, r); _detalhe()})
			if l2 != null:
				for r in Registro.receitas_da_maquina(tipo):
					if not pesquisa.receita_liberada(r) or not Registro.receita_cabe(r, e.nome):
						continue
					var rec: Dictionary = Registro.receitas[r]
					botoes.append({"texto": "2: %s  ←  %s" % [_lista_receita(rec, "saidas"), _lista_receita(rec, "entradas")],
							"receita": _dados_receita(rec), "grupo_receita": "Receita (linha 2)",
							"ligado": l2.receita_id == r, "acao": func(): fabrica.escolher_receita(id, r, 2); _detalhe()})
	elif regra.has("irradiador"):
		var ci: Dictionary = regra.irradiador
		linhas.append("Energia: %d%% · divide cada módulo (%d%%) com as máquinas e laboratórios a até %d tiles" % [fabrica.energia(id) * 100, float(ci.get("efeito", 0.5)) * 100, int(ci.get("raio", 3))])
		_opcoes_modulos(id, e, -1.0, linhas, botoes)
	elif regra.get("grupo", "") == "para_raios":
		var cr: Dictionary = regra.capta_raio
		linhas.append("Pega os raios a até %d m da ponta: protege o que está em volta · raios pegos: %d" % [cr.raio, int(raios.descargas.get(id, 0))])
		linhas.append("%d MJ por raio para os acumuladores da rede (poste perto); sem acumulador, é só proteção" % cr.mj)
	elif regra.has("clima_local"):
		var cl: Dictionary = regra.clima_local
		var ativa := false
		for z in clima_local.zonas:
			ativa = ativa or z.id == id
		linhas.append(("Ativa num raio de %d m" % cl.raio) if ativa else "Parada (precisa de energia: poste perto)")
		match String(cl.tipo):
			"chuva":
				linhas.append("Chama chuva (%d%% pelo menos): apaga o fogo, nada pega fogo e os coletores de chuva enchem" % (float(cl.chuva) * 100))
			"vento":
				linhas.append("O vento sopra %s (para onde a peça aponta — gire para mudar), entre %d%% e %d%%: sem ventania de tufão; fogo e poluição vão junto"
						% [Clima.nome_rumo(Grade.girar(Vector2(0, 1), int(e.rot))), float(cl.vento_min) * 100, float(cl.vento_max) * 100])
			"cupula":
				linhas.append("Nenhum raio cai dentro: a cúpula pega e manda %d MJ para os acumuladores · raios pegos: %d" % [regra.capta_raio.mj, int(raios.descargas.get(id, 0))])
			"regulador":
				var modo_c := String(e.get("modo_clima", cl.get("modo", "firme")))
				linhas.append("Sem raio, sem tufão e vento manso no raio; agora: %s" % ("céu firme (sem chuva)" if modo_c != "chuva" else "chuva mansa"))
				for mc in [["firme", "Céu firme"], ["chuva", "Chuva mansa"]]:
					opcoes.append({"texto": mc[1], "ligado": modo_c == mc[0], "acao": func(): e["modo_clima"] = mc[0]; _detalhe()})
	elif Varredura.eh_sensor(e.nome):
		_detalhe_varredura(id, linhas)
	elif Genese.eh_receptor(e.nome):
		var rec := genese.recebido(id)
		linhas.append("Pacotes gênese: %d de %d (saem por braço; boca norte)" % [Genese._total(rec), genese.capacidade(id)])
		linhas.append("Colônias: %d · cápsulas a caminho daqui: %d" % [genese.colonias().size(), genese.a_caminho(id)])
		if genese.energia_de(id) <= 0.0:
			linhas.append("Parado: sem energia (as cápsulas vão para outro receptor ou esperam na colônia)")
		elif genese.colonias().is_empty():
			linhas.append("Nenhuma colônia ainda: lance um núcleo-semente depois da pesquisa Colônias")
	elif SiloLancamento.eh_silo(e.nome):
		_detalhe_silo(id, linhas, opcoes)
	elif Transportador.eh_transportador(e.nome):
		var ps := transportador.pares(id)
		linhas.append("Canal %s · %d outro%s transportador%s no canal%s" % [transportador.canal(id), ps.size(), "" if ps.size() == 1 else "s",
				"" if ps.size() == 1 else "es", "" if not ps.is_empty() else " — ponha outro (de outra colônia) no mesmo canal"])
		var rt := Transportador.regra(e.nome)
		linhas.append("Entrada (sul, braço): %d de %d · saída (norte, braço): %d de %d" % [Transportador.total(transportador.entrada(id)), int(rt.get("entrada", 20)),
				Transportador.total(transportador.saida(id)), int(rt.get("saida", 200))])
		linhas.append("Manda %d itens/s com energia (%d kW) · já mandou %d" % [int(rt.get("taxa", 5)), int(regra.get("energia_kw", 0)), int(transportador.enviados.get(id, 0))])
		if transportador.energia_de(id) <= 0.0:
			linhas.append("Parado: sem energia")
		for cn in rt.get("canais", ["A", "B", "C", "D"]):
			var cc: String = cn
			opcoes.append({"texto": "Canal %s" % cc, "ligado": transportador.canal(id) == cc, "acao": func(): transportador.mudar_canal(id, cc); _detalhe()})
	elif Lancador.eh_lancador(e.nome):
		_detalhe_lancador(id, linhas, opcoes, botoes)
	elif Farol.eh_farol(e.nome):
		var rf := Farol.regra(e.nome)
		linhas.append("Luz de %d m à noite (acende quando escurece, com energia: %d kW)" % [int(rf.get("raio", 10)), int(regra.get("energia_kw", 0))])
		if farol.energia_de(id) <= 0.0:
			linhas.append("Apagado: sem energia (poste perto)")
		elif not farol.noite(id):
			linhas.append("Apagado: ainda é dia (%s)" % clima.relogio())
		else:
			var na_luz := farol.aranhas_na_luz(id)
			linhas.append("ACESO — tira a névoa em volta e mostra as aranhas que chegam")
			linhas.append("Aranhas na luz agora: %d" % na_luz.size() if not na_luz.is_empty() else "Nenhuma aranha na luz")
	elif e.nome == "nucleo":
		var linhas_n: Array[String] = []
		var chaves := inventario.keys()
		chaves.sort()
		for k in chaves:
			if int(inventario[k]) > 0:
				linhas_n.append("%s: %d" % [_nome_item(k), inventario[k]])
		linhas.append("Estoque (o que entra pelas bocas vira material de construção):")
		linhas.append("\n".join(linhas_n) if not linhas_n.is_empty() else "vazio")
		_detalhe_construtores(linhas, opcoes)
	elif Registro.estruturas.get(e.nome, {}).get("grupo", "") == "logica":
		_opcoes_logica(id, e, linhas, botoes)
	elif not fabrica.rede_de(id).is_empty():
		var r: Dictionary = fabrica.rede_de(id)
		linhas.append("Rede de canos: %s %.0f de %.0f" % [Registro.nome_fluido(r.fluido) if r.fluido != "" else "vazia", r.qtd, r.cap])
		if e.nome == "cano_subterraneo_entrada":
			var par := fabrica.par_subterraneo(id)
			linhas.append("Passa por baixo até a saída a %d tile(s)" % (absi(mapa.estruturas[par].minimo.x - e.minimo.x) + absi(mapa.estruturas[par].minimo.y - e.minimo.y))
					if par >= 0 else "Sem saída: ponha a saída alinhada à frente, mesma direção, até 9 tiles livres no meio")
	elif fabrica.distribuidores.has(id):
		linhas.append("Passando: %s" % (", ".join(fabrica.distribuidores[id].buffer.map(_nome_item)) if not fabrica.distribuidores[id].buffer.is_empty() else "nada"))
		if e.nome == "divisor_filtro":
			_opcoes_divisor_filtro(e, linhas, botoes)
	elif fabrica.laboratorios.has(id):
		var lab: Dictionary = fabrica.laboratorios[id]
		var tipos: Array = pesquisa.tipos_ativa() if pesquisa.ativa != "" else ["pacote_pesquisa"]
		var partes: Array[String] = []
		for t in tipos:
			partes.append("%s %d/%d" % [Pesquisa.nome_tipo(t), int(lab.pacotes.get(t, 0)), Fabrica.LAB_MAX])
		for t in lab.pacotes:                                   # sobras de outra pesquisa
			if not t in tipos and int(lab.pacotes[t]) > 0:
				partes.append("%s %d (parado)" % [Pesquisa.nome_tipo(t), int(lab.pacotes[t])])
		linhas.append("Pacotes: %s\nEnergia: %d%%" % [", ".join(partes), lab.energia * 100])
		if regra.has("velocidade"):
			_opcoes_modulos(id, e, float(regra.velocidade) * float(fabrica.efeito_modulos(id).velocidade), linhas, botoes)
		if pesquisa.ativa != "":
			linhas.append("Cada unidade gasta: %s" % ", ".join(tipos.map(func(t): return "1 " + Pesquisa.nome_tipo(t))))
		opcoes.append({"texto": "⚗  Abrir a pesquisa", "acao": abrir_pesquisa})
	elif Fabrica.eh_posto(e.nome) and fabrica.baus.has(id):
		_detalhe_posto(id, e, regra, linhas, botoes, grade_filtro)
	elif fabrica.baus.has(id):
		var n := 0
		for k in fabrica.baus[id]:
			n += int(fabrica.baus[id][k])
		if not compacto:
			linhas.append("Armazenamento: %d de %d itens (máximo do baú: %d)" % [n, fabrica.capacidade_bau(id), regra.get("capacidade_itens", Fabrica.BAU_MAX)])
		_inventario_bau(id, e, botoes)
		if fabrica.um_tipo(id):
			var tg := Fabrica.tipo_guardado(fabrica.baus[id])
			linhas.append("Guarda um tipo só: %s" % ("vazio — aceita o primeiro item que chegar" if tg == "" else "%s (esvazie para trocar)" % _nome_item(tg)))
		for lim in [0.25, 0.5, 1.0]:
			botoes.append({"texto": "Limite: %d%% (%d itens)" % [lim * 100, int(regra.get("capacidade_itens", Fabrica.BAU_MAX) * lim)], "grupo": "Limite", "curto": "%d%%" % (lim * 100),
					"ligado": is_equal_approx(float(e.get("limite", 1.0)), lim), "acao": func(): e["limite"] = lim; _detalhe()})
		if drones.logistica_liberada() and not fabrica.um_tipo(id):
			_opcoes_logistica(e, linhas, opcoes, botoes)
		_opcoes_filtro_bau(id, e, linhas, grade_filtro)
	elif colonia.ninhos.has(id):
		var fu: float = colonia.ninhos[id].get("furia", 0.0)
		linhas.append("Aranhas: %d" % colonia.aranhas_do_ninho(id).size())
		linhas.append("Fúria: %d%% %s" % [fu * 100, "— o chão sujo em volta deixa as aranhas mais rápidas e fortes" if fu > 0.05 else "(chão limpo em volta)"])
	elif e.nome == "gerador":
		linhas.append("Combustível: %.1f MJ (carvão ou biomassa pela porta sul ou por braço)" % fabrica.combustivel.get(id, 0.0))
	elif Fabrica.eh_gerador_fluido(e.nome):
		linhas.append("Combustível: %.1f de %.0f MJ (combustível de seiva pelo cano da boca sul: 10 = 12 MJ)%s" % [fabrica.combustivel.get(id, 0.0),
				Fabrica.ESTOQUE_GERADOR_MJ, "" if fabrica.gerador_no_cano(id) else " — SEM CANO na boca"])
	elif Fabrica.eh_reator(e.nome):
		var nomes_comb: Array = regra.combustivel_item.keys().map(func(i): return "%s (%d MJ)" % [Registro.itens[i].nome, regra.combustivel_item[i]])
		linhas.append("Combustível: %.0f de %.0f MJ (%s, por braço na boca sul)" % [fabrica.combustivel.get(id, 0.0), regra.estoque_mj, " ou ".join(nomes_comb)])
		if regra.has("agua_por_mj"):
			linhas.append("Água: %.0f de %.0f (%.0f/s a plena carga, pelo cano da boca oeste)%s" % [fabrica.agua_reator.get(id, 0.0), regra.tanque_agua, -float(regra.energia_kw) / 1000.0 * float(regra.agua_por_mj),
					"" if fabrica.gerador_no_cano(id) else " — SEM CANO na boca"])
	elif e.nome == "torre_metralhadora":
		var t: Dictionary = colonia.torres.get(id, {})
		var cad := float(regra.get("cadencia", 10)) * (1.0 + pesquisa.bonus("cadencia_bala"))
		linhas.append("Munição: %d de %d tiros (cada munição que chega por braço = %d)" % [t.get("municao", regra.get("municao_inicial", 0)), regra.get("municao_max", 0), Fabrica.TIROS_POR_MUNICAO])
		linhas.append("Dano por bala: %.1f · %.1f tiros/s · alcance %d m" % [float(regra.get("dano", 3)) * (1.0 + pesquisa.bonus("dano_bala")), cad, regra.get("alcance", 18)])
		_linha_especiais(t, linhas)
	elif e.nome in ["torre_foguetes", "artilharia"]:
		var t: Dictionary = colonia.torres.get(id, {})
		var item := Colonia.item_municao(e.nome)
		var cad := float(regra.get("cadencia", 1)) * (1.0 + pesquisa.bonus(String(regra.get("bonus_cadencia", ""))))
		linhas.append("%s: %d de %d (chegam por esteira ou braço pela boca sul)" % [_nome_item(item), t.get("municao", 0), regra.get("municao_max", 0)])
		linhas.append("Dano %.0f em área (raio %.1f m) · %.2f disparos/s · alcance %d m%s" % [float(regra.get("dano", 0)) * (1.0 + pesquisa.bonus(String(regra.get("bonus_dano", "")))),
				float(regra.projetil.get("raio", 0)), cad, roundi(colonia.alcance_de(e.nome)),
				(" (mínimo %d m; só mira ninhos)" % int(regra.alcance_min)) if regra.has("alcance_min") else ""])
		_linha_especiais(t, linhas)
		if e.nome == "artilharia":
			if colonia.artilharia_espera_ordem(id):
				linhas.append("Sem a pesquisa Mira automática: só atira com a sua ordem")
				opcoes.append({"texto": "🎯 Disparar nos ninhos no alcance", "acao": func(): colonia.ordenar_disparo(id); _detalhe()})
			elif bool(colonia.torres.get(id, {}).get("ordem", false)):
				linhas.append("Ordem de disparo: atirando até não sobrar ninho no alcance")
	elif e.nome == "mina_pulso":
		var pu: Dictionary = regra.pulso
		var rec := float(colonia.minas.get(id, {}).get("recarga", 0.0))
		linhas.append("Armada — aranha a menos de %.1f m dispara" % float(pu.gatilho) if rec <= 0.0 else "Rearmando: %.0f s" % rec)
		linhas.append("Atordoa as aranhas em %.0f m por %.0f s; rearma em %.0f s" % [float(pu.raio), float(pu.atordoa), float(pu.rearme)])
	elif e.nome == "gerador_escudo":
		var cap := fabrica.carga_max(id)
		var c_e := float(fabrica.carga_torre.get(id, 0.0))
		var esc: Dictionary = regra.escudo
		linhas.append("Escudo: %d de %d de dano (%.1f de %.0f MJ) · recarrega da rede a %d kW" % [int(c_e / float(esc.mj_por_dano)), int(cap / float(esc.mj_por_dano)), c_e, cap, fabrica.kw_de(id)])
		linhas.append("Bolha de %d m: mordida ou raio em construção dentro dela gasta o escudo, não a vida" % roundi(colonia.raio_escudo(e.nome)))
	elif e.nome == "muro_escudo":
		linhas.append("Regenera %.0f ♥/s com energia (agora: %d%%)" % [float(regra.regenera), roundi(fabrica.energia(id) * 100)])
	elif e.nome == "torre_defesa":
		var t: Dictionary = colonia.torres.get(id, {})
		var cap_t := float(regra.get("carga_mj", 0.0))
		if cap_t > 0.0:
			var c_t := float(fabrica.carga_torre.get(id, 0.0))
			linhas.append("Energia guardada: %.1f de %.0f MJ (%d tiros) · recarrega da rede a %d kW" % [c_t, cap_t, int(c_t / float(regra.get("tiro_mj", 0.05))), regra.get("energia_kw", 0)])
		linhas.append("Munição de reserva: %d tiros (cada munição que chega por braço = %d)" % [t.get("municao", 0), Fabrica.TIROS_POR_MUNICAO])
	elif estoques.has(id):
		titulo = "Estação %d" % _numero_estacao(id)
		linhas.append("Para enviar: %s\nRecebido: %s" % [_lista_itens(estoques[id].enviar), _lista_itens(estoques[id].recebido)])
		_opcoes_estacao_fluido(id, linhas, botoes)
	elif fabrica.bracos.has(id):
		var b: Braco = fabrica.bracos[id]
		linhas.append("Segurando: %s\nEnergia: %d%%\nEntregues: %d" % [(_nome_item(b.segurando) + (" × %d" % b.qtd if b.qtd > 1 else "")) if b.segurando != "" else "nada", b.energia * 100, b.entregues])
		if b.pilha_max > 1:
			linhas.append("Empilha: até %d itens iguais por vez" % b.pilha_max)
		if regra.has("alcance_max"):                  # braço quântico: até onde a lança estica
			var alc_q := Fabrica.alcance_origem(e)
			linhas.append("Lança: pega a %d tile(s) atrás, solta no tile da frente" % alc_q)
			for n in range(1, int(regra.alcance_max) + 1):
				var nn: int = n
				botoes.append({"texto": "Alcance: %d tile(s)" % nn, "ligado": alc_q == nn, "acao": func():
					e["alcance"] = nn
					_fabrica_suja = true
					var ab := _animador(id)
					if ab != null:
						_posar_braco(ab, e)
					_detalhe()})
		if not regra.has("alcance_max"):              # o braço quântico estica a lança para trás e só tem Linear
			var modo_b := String(e.get("modo_braco", "linear"))
			for mb in [["linear", "Linear", "Linear: pega atrás, solta na frente"], ["radial", "Radial", "Radial: solta na frente; pega dos outros 3 lados, em rodízio"]]:
				var mbn: String = mb[0]
				opcoes.append({"texto": mb[2], "grupo": "Modo do braço", "curto": mb[1], "ligado": modo_b == mbn, "acao": func():
					if mbn == "linear":
						e.erase("modo_braco")
					else:
						e["modo_braco"] = mbn
					_fabrica_suja = true
					_detalhe()})
		_opcoes_filtro_braco(e, b, linhas, grade_filtro)
	match Fiacao.papel(e.nome):
		"consumo":
			var fontes := Fiacao.ligacoes(mapa, e)
			linhas.append("Energia: %d%% · ligada a %d poste(s)" % [fabrica.rede.satisfacao(id) * 100, fontes] if fontes > 0 else "Energia: SEM FIO — ponha um poste a até 5 m")
			for n in [1, 2, 3]:
				botoes.append({"texto": "Aceitar %d fonte(s) de energia" % n, "grupo": "Fontes de energia", "curto": str(n), "ligado": int(e.get("fontes", 1)) == n,
						"acao": func(): Fiacao.mudar_vagas(mapa, id, n); _fabrica_suja = true; _detalhe()})
		"poste":
			var r: Dictionary = Registro.estruturas[e.nome]
			linhas.append("Fios: %d · alcance %d m até outro poste, %d m até máquinas%s" % [e.get("fios", []).size(), r.raio_fio, r.raio_ligacao,
					" (sem fio)" if Fiacao.eh_sem_fio(e.nome) else ""])
			linhas.append("Na rede: %s" % ("gerador ligado" if fabrica.rede.tem_fonte(id) else "nenhum gerador"))
		"fonte":
			if regra.has("acumula_mj"):
				linhas.append("Guardado: %.1f de %.0f MJ · carrega/descarrega até %d kW" % [fabrica.acumulado.get(id, 0.0), regra.acumula_mj, regra.acumula_kw])
			elif regra.has("capta_raio"):
				linhas.append("Na rede: %s" % ("ligado (o raio vai para os acumuladores)" if fabrica.rede.nos.has(id) and Fiacao.ligacoes(mapa, e) > 0 else "sem poste — o raio só é aterrado"))
			else:
				var agora: float = -fabrica.kw_de(id)
				var sol_aqui: float = -fabrica.kw_de(id) / maxf(-float(regra.get("energia_kw", -1.0)), 1.0) if fabrica.ligada(id) else fabrica.sol
				var nota: String = {"sol": " (sol agora: %d%%%s)" % [sol_aqui * 100, ", nuvem tira só %d%%" % (float(regra.perda_nuvem) * 100) if regra.has("perda_nuvem") else ""], "rio": " (rio agora: %d%% da vazão — %s)" % [fabrica.rio * 100,
						clima.nome_estacao()]}.get(regra.get("renovavel", ""), "")
				linhas.append("Geração: até %d kW agora, máximo %d kW%s" % [agora, -float(regra.get("energia_kw", 0.0)), nota])
				if regra.get("renovavel", "") == "vento":
					var c := Grade.centro_da_area(e.minimo, e.area, e.rot)
					var f := vento_local.fator(Vector2i(c.floor()), clima.direcao_vento, float(regra.get("altura_vento", 0.0)))
					linhas.append("Vento aqui: %d%% %s · o lugar dá %+d%%%s" % [float(fabrica.vento_turbina.get(id, fabrica.vento)) * 100, Clima.nome_rumo(clima.direcao_vento), (f - 1.0) * 100,
							" (a torre alta conta +%d níveis)" % int(regra.altura_vento) if regra.has("altura_vento") else ""])
					var tc: Dictionary = Registro.ambiente.get("turbina", {})
					if fabrica.em_protecao(id):
						linhas.append("Ventania: pás em bandeira (rende %d%%, protege a turbina)" % (float(tc.get("so_protecao", 0.4)) * 100))
					elif Fabrica.curva_turbina(float(fabrica.vento_turbina.get(id, fabrica.vento))) <= 0.0:
						linhas.append("Vento fraco demais: parada (gira acima de %d%%)" % (float(tc.get("corte", 0.25)) * 100))
	# ficha da rede elétrica em que está ligada
	var est := fabrica.rede.estat_de(id)
	if not est.is_empty() and Fiacao.papel(e.nome) != "":
		var t := "Rede: gera %d kW (pode %d) · consome %d de %d kW" % [est.gera, est.gera_max, est.consumo, est.demanda]
		if est.acum_cap > 0.0:
			t += " · acumulado %.0f de %.0f MJ (%s)" % [est.acum, est.acum_cap, "carregando" if est.carga > 0.5 else ("descarregando" if est.carga < -0.5 else "parado")]
		linhas.append(t)
	if e.nome != "pilar" and e.get("nivel", 0) == 0:
		opcoes.append({"texto": "⟲  Girar", "acao": func(): girar_estrutura(id), "secao": "acoes", "icone_txt": "⟲ Girar", "tecla": "R"})
	# opções internas: ligar/desligar (tudo que usa ou gera energia, e máquinas) e modo de trabalho (máquinas elétricas)
	if fabrica.logica_off.has(id):
		linhas.append("Desligada pelo comparador encostado (a condição dele não vale agora)")
	if _tem_liga(id):
		var liga: bool = not e.get("desligada", false)
		opcoes.append({"texto": "Ligada" if liga else "Desligada (toque para ligar)", "ligado": liga,
				"acao": func(): alternar_ligada(id), "secao": "acoes", "icone_txt": "⏻ Ligada" if liga else "⏻ Desligada", "tecla": "O"})
	if fabrica.maquinas.has(id) and float(regra.get("energia_kw", 0.0)) > 0.0:
		var kw := float(regra.energia_kw)
		for mo in [["eco", "Econômico"], ["normal", "Normal"], ["turbo", "Turbo"]]:
			var k: Array = Fabrica.MODOS[mo[0]]
			opcoes.append({"texto": "%s: %d%% velocidade · %d kW · %d%% poluição" % [mo[1], k[0] * 100, kw * k[1], k[2] * 100], "grupo": "Modo", "curto": mo[1],
					"ligado": e.get("modo", "normal") == mo[0], "acao": func(): e["modo"] = mo[0]; _fabrica_suja = true; _detalhe()})
	if _confirmando_remocao_bau == id and eh_armazem_com_itens(id):
		var n_itens := total_itens_bau(id)
		linhas.insert(0, "⚠ Este baú tem %d itens. Remover e perder?" % n_itens)
		opcoes.append({"texto": "📦  Enviar à central antes e remover", "acao": func(): confirmar_remocao_bau(id, true), "secao": "acoes", "icone_txt": "📦 Enviar e remover"})
		opcoes.append({"texto": "✕  Remover e perder (%d itens)" % n_itens, "acao": func(): confirmar_remocao_bau(id, false), "secao": "acoes", "icone_txt": "✕ Remover e perder", "perigo": true})
		opcoes.append({"texto": "Cancelar remoção", "acao": func(): _confirmando_remocao_bau = -1; _detalhe(), "secao": "acoes", "icone_txt": "Cancelar"})
	elif e.nome != "nucleo" and not Colonia.eh_toca(e.nome):
		opcoes.append({"texto": "✕  Remover", "acao": func(): remover_estrutura(id), "secao": "acoes", "icone_txt": "✕ Remover", "tecla": "Del", "perigo": true})
	if fabrica.tem_config(id):
		opcoes.append({"texto": "⧉  Copiar configuração", "acao": func(): copiar_config_de(id), "secao": "acoes", "icone_txt": "⧉ Copiar", "tecla": "Ctrl+C"})
		if fabrica.pode_colar(id, _copia):
			opcoes.append({"texto": "⎘  Colar configuração", "acao": func(): colar_config_em(id), "secao": "acoes", "icone_txt": "⎘ Colar", "tecla": "Ctrl+V"})
	if linhas.is_empty():
		linhas.append(Registro.modelos.get(Construtor.modelo_de(e), {}).get("descricao", ""))
	var extra := {}
	if compacto:
		extra = _cabecalho_estrutura(id, e, regra)
	barra.detalhe(titulo, "\n".join(linhas), opcoes + botoes + grade_filtro, extra)
	barra.detalhe_maquina(_painel_maquina(id))


## Dados de uma receita para a escolha com ícones: entradas e saídas, itens com ícone e fluidos pelo nome.
func _dados_receita(rec: Dictionary) -> Dictionary:
	var lado := func(ch_i: String, ch_f: String) -> Array:
		var out := []
		for k in rec.get(ch_i, {}):
			out.append({"tex": TelaPesquisa._tex_item(k), "n": int(rec[ch_i][k]), "dica": _nome_item(k)})
		for k in rec.get(ch_f, {}):
			out.append({"tex": TelaPesquisa._tex_item(k), "n": int(rec[ch_f][k]), "dica": Registro.nome_fluido(k), "fluido": Registro.nome_fluido(k)})
		return out
	return {"entradas": lado.call("entradas", "entradas_fluido"), "saidas": lado.call("saidas", "saidas_fluido"), "tempo": float(rec.get("tempo", 1.0))}


func _texto_estatistica(m: Maquina) -> String:
	var p: Array[String] = []
	if m.receita.has("saidas") and not m.receita.saidas.is_empty():
		p.append("%s itens/min" % String.num(m.itens_por_minuto(), 1))
	if m.tempo_total > 0.0:
		p.append("trabalhou %d%% do tempo" % roundi(m.tempo_ativo / m.tempo_total * 100.0))
	p.append("%d ciclos" % m.produzidos)
	return " · ".join(p)


## Cabeçalho e barras do painel compacto: ícone, vida, estado com a causa em palavras e as barras do tipo.
func _cabecalho_estrutura(id: int, e: Dictionary, regra: Dictionary) -> Dictionary:
	var d := {"icone": TelaPesquisa._tex_peca(Construtor.modelo_de(e)), "estado": "", "cor": Tema.cor("info"), "vida": -1.0, "barras": [], "stats": ""}
	if d.icone == null:
		d.icone = TelaPesquisa._tex_peca(e.nome)
	var vmax := float(regra.get("vida", 0))
	if vmax > 0.0:
		d.vida = float(colonia.vida.get(id, vmax)) / vmax
		d["vida_dica"] = "Integridade: %d de %d" % [ceilf(float(colonia.vida.get(id, vmax))), vmax]
	if fabrica.maquinas.has(id):
		var m: Maquina = fabrica.maquinas[id]
		d.estado = Fabrica.causa_maquina(m, fabrica.logica_off.has(id))
		d.cor = _cor_estado(m.estado)
		d.barras.append({"rotulo": "Progresso", "valor": m.progresso, "cor": Tema.cor("sucesso")})
		if regra.has("energia_kw"):
			d.barras.append({"rotulo": "Energia", "valor": m.energia, "cor": Tema.cor("energia")})
		for fl in m.receita.get("entradas_fluido", {}):
			d.barras.append({"rotulo": Registro.nome_fluido(fl), "valor": float(m.fluidos.get(fl, 0.0)) / maxf(float(m.receita.entradas_fluido[fl]) * Maquina.LIMITE_ENTRADA, maxf(m.tanque_fluido, 1.0)), "cor": Tema.cor("agua")})
		for fl in m.receita.get("saidas_fluido", {}):
			d.barras.append({"rotulo": Registro.nome_fluido(fl), "valor": float(m.fluidos.get(fl, 0.0)) / maxf(m.limite_fluido(fl), 1.0), "cor": Tema.cor("agua")})
		if m.tempo_total >= 10.0:
			d.stats = _texto_estatistica(m)
	else:
		if e.get("desligada", false):
			d.estado = "desligada"
			d.cor = Tema.cor("travado")
		elif fabrica.logica_off.has(id):
			d.estado = "desligada pelo comparador"
			d.cor = Tema.cor("travado")
		elif Fiacao.papel(e.nome) == "consumo":
			var en := fabrica.rede.satisfacao(id) if Fiacao.ligacoes(mapa, e) > 0 else 0.0
			d.estado = "ligada" if en > 0.0 else "sem energia"
			d.cor = Tema.cor("sucesso") if en > 0.0 else Tema.cor("perigo")
			d.barras.append({"rotulo": "Energia", "valor": en, "cor": Tema.cor("energia")})
	if fabrica.baus.has(id) and not Fabrica.eh_posto(e.nome):
		var n := 0
		for k in fabrica.baus[id]:
			n += int(fabrica.baus[id][k])
		d.barras.append({"rotulo": "Estoque", "valor": float(n) / maxf(fabrica.capacidade_bau(id), 1.0), "cor": Tema.cor("destaque"), "dica": "%d de %d itens" % [n, fabrica.capacidade_bau(id)]})
	if regra.has("acumula_mj"):
		d.barras.append({"rotulo": "Carga", "valor": float(fabrica.acumulado.get(id, 0.0)) / maxf(float(regra.acumula_mj), 1.0), "cor": Tema.cor("energia")})
	if not fabrica.rede_de(id).is_empty():
		var rc: Dictionary = fabrica.rede_de(id)
		d.barras.append({"rotulo": "Rede", "valor": float(rc.qtd) / maxf(float(rc.cap), 1.0), "cor": Tema.cor("agua"), "dica": "%.0f de %.0f" % [rc.qtd, rc.cap]})
	return d


func _cor_estado(est: int) -> Color:
	match est:
		Maquina.Estado.TRABALHANDO, Maquina.Estado.PRONTIDAO: return Tema.cor("sucesso")
		Maquina.Estado.DESLIGADA: return Tema.cor("travado")
		Maquina.Estado.SEM_ENERGIA, Maquina.Estado.SEM_JAZIDA: return Tema.cor("perigo")
	return Tema.cor("destaque")


## Inventário do baú: grade de ícones com a quantidade (nome na dica) e a ordem de ver. Saída à mão: botão "Enviar para a central" (tudo ou por item), que manda os itens ao estoque do núcleo.
func _inventario_bau(id: int, e: Dictionary, botoes: Array) -> void:
	var ordem := String(e.get("ordem", "tipo"))
	for o in [["tipo", "Por tipo"], ["qtd", "Por quantidade"]]:
		var oo: String = o[0]
		botoes.append({"texto": "Organizar: %s" % o[1].to_lower(), "grupo": "Organizar", "curto": o[1], "ligado": ordem == oo, "acao": func():
			e["ordem"] = oo
			_detalhe()})
	var lista := fabrica.conteudo_ordenado(id, ordem)
	var tem_itens: bool = not lista.is_empty()
	if tem_itens:
		botoes.append({
			"texto": "📦  Enviar tudo para a central",
			"grupo": "Central",
			"curto": "📦 Tudo",
			"acao": func():
				enviar_bau_para_central(id)
				_detalhe()
		})
	botoes.append({"titulo": "Conteúdo" if tem_itens else "Conteúdo: vazio"})
	for it in lista:
		var q := int(fabrica.baus[id][it])
		var it_chave: String = it
		botoes.append({
			"texto": _nome_item(it_chave),
			"icone": TelaPesquisa._tex_item(it_chave),
			"chave": it_chave,
			"numero": PainelRecursos.numero_curto(q),
			"dica_num": "%s: %d (toque para enviar à central)" % [_nome_item(it_chave), q],
			"ligado": false,
			"sem_clique": false,
			"acao": func():
				enviar_bau_para_central(id, it_chave)
				_detalhe()
		})


## Filtro de tipos aceitos (nenhum = tudo) e limite por tipo: vale para braço, esteira por braço e drone. Grade no fim do painel, como a do braço.
func _opcoes_filtro_bau(_id: int, e: Dictionary, linhas: Array[String], grade: Array) -> void:
	var aceitos: Array = e.get("aceita", [])
	linhas.append("Aceita: %s" % ("tudo" if aceitos.is_empty() else ", ".join(aceitos.map(_nome_item))))
	var lim := int(e.get("aceita_limite", 0))
	for v in [0, 100, 500, 1000]:
		var vv: int = v
		grade.append({"texto": "Por tipo: %s" % ("sem limite" if vv == 0 else "até %d" % vv), "grupo": "Máximo de cada tipo", "curto": "—" if vv == 0 else str(vv), "ligado": lim == vv, "acao": func():
			if vv == 0:
				e.erase("aceita_limite")
			else:
				e["aceita_limite"] = vv
			_detalhe()})
	grade.append({"texto": "Aceita tudo (sem filtro)", "ligado": aceitos.is_empty(), "acao": func():
		e.erase("aceita")
		_detalhe()})
	var nomes_grupo := {"recurso": "Aceitar: recursos", "intermediario": "Aceitar: peças", "avancado": "Aceitar: avançados"}
	var por_grupo := {}
	for it in Registro.itens:
		var g: String = Registro.itens[it].get("grupo", "avancado")
		if not por_grupo.has(g):
			por_grupo[g] = []
		por_grupo[g].append(it)
	for g in nomes_grupo:
		var lista: Array = por_grupo.get(g, [])
		lista.sort_custom(func(x, y): return _nome_item(x) < _nome_item(y))
		grade.append({"titulo": nomes_grupo[g]})
		for it in lista:
			grade.append({"texto": _nome_item(it), "icone": TelaPesquisa._tex_item(it), "ligado": aceitos.has(it), "acao": func():
				var atual: Array = (e.get("aceita", []) as Array).duplicate()
				if atual.has(it):
					atual.erase(it)
				else:
					atual.append(it)
				if atual.is_empty():
					e.erase("aceita")
				else:
					e["aceita"] = atual
				_detalhe()})


## Escolha do que o braço pega: Auto ou um item (todo braço); o Braço com filtro escolhe até `filtro_max`. A grade de
## ícones vem por último no painel, porque é a parte longa (o resto continua à vista sem rolar).
func _opcoes_filtro_braco(e: Dictionary, b: Braco, linhas: Array[String], grade: Array) -> void:
	var filtros: Array = e.get("filtros", [])
	var mx := Fabrica.max_filtros(e.nome)
	var mudar := func(lista: Array) -> void:
		e["filtros"] = lista
		b.filtros = lista
		b.filtro = lista[0] if lista.size() == 1 else ""
		_detalhe()
	linhas.append("Pega: %s" % ("tudo o que o destino aceitar (Auto)" if filtros.is_empty() else ", ".join(filtros.map(_nome_item))))
	linhas.append("Toque em até %d itens abaixo; de novo para tirar." % mx if mx > 1 else "Toque num item abaixo para pegar só ele; de novo volta ao Auto.")
	grade.append({"texto": "Auto: pega o que vier", "ligado": filtros.is_empty(), "acao": func(): mudar.call([])})
	var nomes_grupo := {"recurso": "Recursos", "intermediario": "Peças", "avancado": "Avançados"}
	var por_grupo := {}
	for it in Registro.itens:
		var g: String = Registro.itens[it].get("grupo", "avancado")
		if not por_grupo.has(g):
			por_grupo[g] = []
		por_grupo[g].append(it)
	for g in nomes_grupo:
		var lista: Array = por_grupo.get(g, [])
		lista.sort_custom(func(x, y): return _nome_item(x) < _nome_item(y))
		grade.append({"titulo": nomes_grupo[g]})
		for it in lista:
			grade.append({"texto": _nome_item(it), "icone": TelaPesquisa._tex_item(it), "ligado": filtros.has(it), "acao": func():
				var atual: Array = e.get("filtros", [])
				var nova := Fabrica.escolher_filtro(atual, it, mx)
				if nova == atual and not atual.has(it):
					controle._avisar("O filtro escolhe até %d itens: tire um antes" % mx)
					return
				mudar.call(nova)})


## Estação de drones: frota, o que cada um faz e o tipo (opções internas).
func _detalhe_estacao_drones(id: int, e: Dictionary, linhas: Array[String], opcoes: Array) -> void:
	var tipo := drones.tipo_de(id)
	var lista := drones.da_estacao(id)
	var conta := {}
	for d in lista:
		var k: String = Drones.NOMES_ESTADO[int(d.e)]
		conta[k] = int(conta.get(k, 0)) + 1
	var partes: Array[String] = []
	for k in conta:
		partes.append("%d %s" % [conta[k], k])
	linhas.append("Frota: %d de %d drones%s · alcance %d m" % [lista.size(), drones.frota_max(), (" (" + ", ".join(partes) + ")") if not partes.is_empty() else "", roundi(drones.alcance(id))])
	linhas.append("Bateria: %d s de voo · %.1f m/s%s" % [roundi(drones.voo_max()), drones.velocidade(), "" if drones.pode_voar() else " — RAIOS: os drones ficam no hangar (pesquise Voo na tempestade)"])
	match tipo:
		"reparo":
			linhas.append("Reparo: escaneia e solda o que estiver danificado no alcance (%d ♥/s); gasta 1 placa de ferro do núcleo a cada 25 ♥" % int(Registro.estruturas[Drones.ESTACAO].drones.reparo_ps))
		"combate":
			linhas.append("Combate: caça as aranhas no alcance (%.0f de dano, %.1f tiros/s, %d m); aranha perto morde o drone" % [drones.dano(), float(Registro.estruturas[Drones.ESTACAO].drones.cadencia), int(Registro.estruturas[Drones.ESTACAO].drones.alcance_tiro)])
		"logistico":
			linhas.append("Logístico (porto): leva %d item(ns) por viagem de baú provedor para baú requisitante no alcance; toque nos baús para escolher o papel" % drones.carga_max())
	for t in Drones.TIPOS:
		if t == "logistico" and not drones.logistica_liberada():
			continue
		opcoes.append({"texto": "Drones: %s" % Drones.NOMES_TIPO[t], "ligado": tipo == t, "acao": func(): drones.definir_tipo(id, t); _detalhe()})


## Baú para os drones logísticos: provedor (oferece o que tem) ou requisitante (pede um item até uma quantidade).
func _opcoes_logistica(e: Dictionary, linhas: Array[String], opcoes: Array, botoes: Array) -> void:
	if e.nome == "bau_estoque":
		linhas.append("Drones logísticos: ESTOQUE — guarda o que sobra na garra e serve o requisitante quando nenhum provedor tem")
		return
	var papel := String(e.get("logistica", ""))
	linhas.append("Drones logísticos: %s" % {"": "fora da rede", "provedor": "PROVEDOR — os drones tiram daqui", "requisitante": "REQUISITANTE — os drones trazem o pedido"}[papel])
	for pp in [["", "Fora da rede"], ["provedor", "Provedor"], ["requisitante", "Requisitante"]]:
		opcoes.append({"texto": "Logística: %s" % pp[1], "ligado": papel == pp[0], "acao": func():
			if pp[0] == "": e.erase("logistica")
			else: e["logistica"] = pp[0]
			_detalhe()})
	if papel != "requisitante":
		return
	var item := String(e.get("pede_item", ""))
	var qtd := int(e.get("pede_qtd", 100))
	linhas.append("Pede: %s" % ("nada (escolha o item abaixo)" if item == "" else "%s até %d" % [_nome_item(item), qtd]))
	for q in [50, 100, 400, 1600]:
		botoes.append({"texto": "Quantidade: %d" % q, "ligado": qtd == q, "acao": func(): e["pede_qtd"] = q; _detalhe()})
	var itens_ord: Array = Registro.itens.keys()
	itens_ord.sort_custom(func(a, c): return _nome_item(a) < _nome_item(c))
	for it in itens_ord:
		botoes.append({"texto": "Pedir: %s" % _nome_item(it), "ligado": item == it, "acao": func(): e["pede_item"] = it; _detalhe()})


## Rede lógica (rede_logica): canal dos sensores; canal, condição e número do comparador; modo e nível da válvula.
func _opcoes_logica(id: int, e: Dictionary, linhas: Array[String], botoes: Array) -> void:
	var canal := Fabrica.canal_de(e)
	match e.nome:
		"sensor_esteira":
			var s: Dictionary = fabrica.sensores.get(id, {})
			var olha := fabrica._sens_esteira.any(func(x): return x.id == id)
			linhas.append(("Contou %d itens · agora %.0f itens/min" % [int(s.get("total", 0)), fabrica.valor_sensor(id)]) if olha
					else "Sem esteira na frente: vire a cabeça (⟲) para a esteira")
		"sensor_tanque":
			var r := fabrica.rede_de(id)
			linhas.append("Nível da rede: %.0f%% (%s %.0f de %.0f)" % [fabrica.valor_sensor(id), Registro.nome_fluido(r.fluido) if r.get("fluido", "") != "" else "vazia",
					float(r.get("qtd", 0.0)), float(r.get("cap", 0.0))])
		"comparador":
			var op := String(e.get("op", ">"))
			var n := int(e.get("numero", 50))
			var ok := fabrica.condicao_comparador(id)
			linhas.append("Canal %s = %.0f  %s  %d → vizinhos %s" % [canal, float(fabrica.canais.get(canal, 0.0)), op, n, "LIGADOS" if ok else "DESLIGADOS"])
			var nomes: Array = []
			for c in fabrica._comparadores:
				if c.id == id:
					nomes = c.vizinhos.map(func(v): return controle.barra.rotulo(mapa.estruturas[v].nome))
			linhas.append("Comanda: %s" % (", ".join(nomes) if not nomes.is_empty() else "ninguém — encoste máquinas, braços ou bombas nele"))
			for o in [[">", "Liga quando o canal passa do número"], ["<", "Liga quando o canal fica abaixo"]]:
				var op_o: String = o[0]
				botoes.append({"texto": o[1], "ligado": op == op_o, "acao": func(): e["op"] = op_o; _detalhe()})
			for d in [-10, -1, 1, 10]:
				var dd: int = d
				botoes.append({"texto": "Número %+d (agora %d)" % [dd, n], "acao": func(): e["numero"] = clampi(int(e.get("numero", 50)) + dd, 0, 9999); _detalhe()})
		"valvula":
			var modo := String(e.get("modo_valvula", "acima"))
			var nv := int(e.get("nivel_valvula", 50))
			linhas.append("Agora: %s" % ("passando" if fabrica.valvula_passou.has(id) else ("aberta" if fabrica.valvula_abre(id) else "fechada")))
			for o in [["acima", "Passa se a entrada estiver acima do nível"], ["abaixo", "Passa se a saída estiver abaixo do nível"], ["sempre", "Sempre aberta (só o comparador fecha)"]]:
				var mo: String = o[0]
				botoes.append({"texto": o[1], "ligado": modo == mo, "acao": func(): e["modo_valvula"] = mo; _detalhe()})
			for d in [-10, 10]:
				var dd: int = d
				botoes.append({"texto": "Nível %+d%% (agora %d%%)" % [dd, nv], "acao": func(): e["nivel_valvula"] = clampi(int(e.get("nivel_valvula", 50)) + dd, 0, 100); _detalhe()})
			return
	if e.nome != "valvula":
		for c in Fabrica.CANAIS:
			var cc: String = c
			botoes.append({"texto": "Canal %s" % cc, "ligado": canal == cc, "acao": func(): e["canal"] = cc; _detalhe()})


## Divisor com filtro: item filtrado → uma saída; o resto → saída de prioridade (ou rodízio). Lados relativos à peça
## (o item entra por trás): Frente (N do modelo), Direita (L), Esquerda (O).
func _opcoes_divisor_filtro(e: Dictionary, linhas: Array[String], botoes: Array) -> void:
	var filtro: String = e.get("filtro_item", "")
	var lado_f: String = e.get("saida_filtro", "L")
	var prio: String = e.get("prioridade", "")
	var ld: Dictionary = Fabrica.LADOS_DIVISOR
	linhas.append("Filtro: %s" % ("nenhum (reparte tudo)" if filtro == "" else "%s → sai pela %s" % [_nome_item(filtro), String(ld[lado_f]).to_lower()]))
	linhas.append("Prioridade do resto: %s" % ("rodízio" if prio == "" else String(ld[prio]).to_lower()))
	for l in ["N", "L", "O"]:
		botoes.append({"texto": "Saída do filtro: %s" % ld[l], "ligado": lado_f == l,
				"acao": func(): e["saida_filtro"] = l; _detalhe()})
	botoes.append({"texto": "Prioridade: rodízio", "ligado": prio == "", "acao": func(): e.erase("prioridade"); _detalhe()})
	for l in ["N", "L", "O"]:
		botoes.append({"texto": "Prioridade: %s" % ld[l], "ligado": prio == l, "acao": func(): e["prioridade"] = l; _detalhe()})
	botoes.append({"texto": "Filtro: nenhum", "ligado": filtro == "", "acao": func(): e.erase("filtro_item"); _detalhe()})
	var itens_ord: Array = Registro.itens.keys()
	itens_ord.sort_custom(func(a, c): return _nome_item(a) < _nome_item(c))
	for it in itens_ord:
		botoes.append({"texto": "Filtro: %s" % _nome_item(it), "ligado": filtro == it, "acao": func(): e["filtro_item"] = it; _detalhe()})


func _detalhe_pesquisa() -> void:
	var linhas: Array[String] = []
	var botoes := []
	if pesquisa.livre:
		linhas.append("Demonstração: tudo já está liberado.")
	else:
		if pesquisa.ativa != "":
			var at: Dictionary = pesquisa.pesquisas()[pesquisa.ativa]
			linhas.append("Pesquisando: %s%s — %d de %d (%s)" % [at.nome, " nível %d" % (pesquisa.nivel(pesquisa.ativa) + 1) if pesquisa.infinita(pesquisa.ativa) else "",
					pesquisa.feitos, pesquisa.unidades(pesquisa.ativa), pesquisa.custo_texto(pesquisa.ativa)])
		else:
			linhas.append("Escolha o que pesquisar.")
		linhas.append("Laboratório (com energia) gasta pacotes de pesquisa.\nPacote: montadora com 1 cristal lapidado + 1 engrenagem.")
		for id in pesquisa.pesquisas():
			var pq: Dictionary = pesquisa.pesquisas()[id]
			var libera: Array[String] = []
			for n in pq.get("libera", []):
				libera.append(controle.barra.rotulo(n))
			for r in pq.get("receitas", []):
				libera.append(_lista_itens(Registro.receitas[r].get("saidas", {})).trim_prefix("1 "))
			var resumo := ", ".join(libera)
			if pesquisa.concluidas.has(id):
				linhas.append("Feita: %s" % pq.nome)
			elif pesquisa.disponivel(id):
				botoes.append({"texto": "%s (%s) — %s" % [pq.nome, pesquisa.custo_texto(id), resumo], "ligado": pesquisa.ativa == id,
						"acao": func(): pesquisa.escolher(id); _detalhe()})
			else:
				var falta: Array[String] = []
				for rq in pq.get("requer", []):
					if not pesquisa.concluidas.has(rq):
						falta.append(pesquisa.pesquisas().get(rq, pesquisa.arvore().get(rq, {"nome": rq})).nome)   # pode ser "em breve"
				linhas.append("Depois de %s: %s" % [" e ".join(falta), pq.nome])
	controle.barra.detalhe("Pesquisa", "\n".join(linhas), botoes)


## Casas do painel da máquina: ícone da construção, receita (o que tem dentro × o que precisa), saída, barras.
func _painel_maquina(id: int) -> Dictionary:
	if not fabrica.maquinas.has(id) or not mapa.estruturas.has(id):
		return {}
	var m: Maquina = fabrica.maquinas[id]
	var nome: String = mapa.estruturas[id].nome
	var d := {"icone": TelaPesquisa._tex_peca(nome), "entradas": [], "saidas": [], "progresso": m.progresso,
			"energia": m.energia if Registro.estruturas.get(nome, {}).has("energia_kw") else -1.0}
	var precisa: Dictionary = m.receita.get("entradas", {})
	for k in precisa:
		var tem := int(m.entradas.get(k, 0))
		d.entradas.append({"tex": TelaPesquisa._tex_item(k), "n": tem, "dica": "%s: precisa %d" % [_nome_item(k), int(precisa[k])], "falta": tem < int(precisa[k])})
	for k in m.receita.get("saidas", {}):
		d.saidas.append({"tex": TelaPesquisa._tex_item(k), "n": int(m.saidas.get(k, 0)), "dica": _nome_item(k)})
	if precisa.is_empty() and m.receita.get("saidas", {}).is_empty():
		d.erase("saidas")
	return d


## Leitura ambiental (pesquisa monitor_ambiental): avisa uma vez quando um ninho fica furioso (chão sujo em volta).
var _furiosos: Dictionary = {}


func _avisar_furia() -> void:
	if modo == "demo" or not pesquisa.camada_liberada("poluicao"):
		return
	var agora := {}
	for id in colonia.ninhos_furiosos(VisaoRecursos.FURIA_AVISO):
		agora[id] = true
		if not _furiosos.has(id):
			controle._avisar("⚠ Ninho furioso (%d%%): chão sujo em volta. Veja em Recursos → Sujeira." % roundi(float(colonia.ninhos[id].furia) * 100))
	_furiosos = agora


# ------------------------------------------------------------------ patch RTS: drones construtores
var _obras_eventos: Array[Dictionary] = []
var _t_som_obra := 0.0
var _solda_t: Dictionary = {}           ## id do construtor → [falta para o próximo toque, qual solda tocou]


## Plano confirmado na construção: vira encomenda para os drones construtores (limpar/aplainar seguem na hora).
func encomendar(plano: Array[Dictionary]) -> Dictionary:
	var r := obras.encomendar(plano)
	if not (r.rel as Dictionary).is_empty():
		sincronizar(r.rel)
	return r


func _eventos_obras(delta: float) -> void:
	_t_som_obra -= delta
	for ev in _obras_eventos:
		match ev.tipo:
			"obra_pronta":
				pass                                     # o som da obra é a solda (abaixo), não um baque genérico
			"obra_removida":
				if _t_som_obra <= 0.0:
					_t_som_obra = 0.25
					Som.tocar("remover", Grade.ponto_mundo(ev.pos))
			"obra_falhou":
				if is_instance_valid(controle):
					controle._avisar("Não deu para construir %s ali — os itens voltam com o drone" % _nome_item(ev.nome))
			"carga_perdida":
				if is_instance_valid(controle):
					controle._avisar("Drone construtor derrubado: a carga se perdeu")
	_obras_eventos.clear()
	# solda dos construtores trabalhando: arco e MIG alternados, cada drone no seu ritmo, na posição dele
	for d in obras.construtores():
		if d.e != Drones.E.TRABALHANDO:
			_solda_t.erase(d.id)
			continue
		var st: Array = _solda_t.get(d.id, [0.0, randi() % 2])
		st[0] = float(st[0]) - delta
		if float(st[0]) <= 0.0:
			st[0] = 0.85
			st[1] = 1 - int(st[1])
			Som.tocar("solda_arco" if int(st[1]) == 0 else "solda_mig", Grade.ponto_mundo(d.pos, float(d.alt)))
		_solda_t[d.id] = st


func _detalhe_construtores(linhas: Array[String], opcoes: Array) -> void:
	var lista := obras.construtores()
	var fora := 0
	for d in lista:
		if d.e != Drones.E.HANGAR and d.e != Drones.E.NASCENDO:
			fora += 1
	linhas.append("Drones construtores: %d de %d (%d trabalhando)%s" % [lista.size(), obras.frota_max(), fora,
			"" if drones.pode_voar() else " — RAIOS: ficam no núcleo"])
	if obras.pendentes() > 0:
		var esp := obras.esperando()
		linhas.append("Obras na fila: %d%s" % [obras.pendentes(), (" (%d esperando recurso)" % esp) if esp > 0 else ""])
	var motivo := obras.pode_fabricar()
	var custo := _lista_itens(obras.custo_drone())
	opcoes.append({"texto": "Fabricar drone construtor (%s)%s" % [custo, "" if motivo == "" else " — " + motivo],
			"acao": func():
				if obras.fabricar() >= 0:
					Som.tocar("construir")
				_detalhe(),
			"secao": "acoes", "icone_txt": "✚ Drone"})


func _hud() -> void:
	_avisar_furia()
	if not _sel.is_empty():
		_detalhe()
	var atacando := 0
	var larvas_vindo := 0
	for a in colonia.aranhas.values():
		if a.estado == Colonia.E.ATACANDO:
			if a.get("especie", "aranha") == "larva":
				larvas_vindo += 1
			else:
				atacando += 1
	var municao := 0
	for t in colonia.torres.values():
		municao += t.municao
	var aqui := poluicao.em(Grade.tile_de_mundo(camera.alvo))
	var texto := "%s %s · %s · %s · Vento %d%% %s\nPoluição aqui: %.1f   ·   total: %.0f\nNinhos: %d   ·   aranhas: %d\nMunição nas torres: %d   ·   trens: %d" % [
			clima.periodo(), clima.relogio(), clima.nome_estacao(), clima.nome(), clima.vento_em(clima.foco) * 100, Clima.nome_rumo(clima.direcao_vento), aqui, poluicao.total(), colonia.ninhos.size(), colonia.aranhas.size(), municao, trens.size()]
	if modo != "demo":
		controle.barra.estoque(inventario)
		if pesquisa.ativa != "":
			texto += "\nPesquisa: %s %d/%d" % [pesquisa.pesquisas()[pesquisa.ativa].nome, pesquisa.feitos, pesquisa.unidades(pesquisa.ativa)]
	var vindo: PackedStringArray = []
	if atacando > 0:
		vindo.append("%d aranha(s)" % atacando)
	if larvas_vindo > 0:
		vindo.append("%d larva(s)" % larvas_vindo)
	controle.barra.situacao(texto, ("Ataque! %s vindo" % " e ".join(vindo)) if not vindo.is_empty() else "")
