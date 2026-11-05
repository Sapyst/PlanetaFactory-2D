extends Node
## Autoload: gerencia e toca todos os efeitos sonoros sintetizados (assets/sons).
## Suporta áudio 2D e áudio 3D posicionado com atenuação por distância, limite de vozes simultâneas,
## controle de intervalos mínimos contra repetição de rajada e roteamento automático para os barramentos
## "Efeitos" e "Ambiente" (controlados no menu de Configurações).

const INTERVALO := {
	"rato_chiado": 0.4,
	"rato_guincho": 0.4,
	"rato_cavar": 0.8,
	"rato_roendo": 2.0,
	"filhotes": 1.5,
	"bando_migrando": 3.0,
	"herbivoro_alarme": 1.2,
	"predador_uivo": 6.0,
	"predador_rosnado": 1.0,
	"peixe_pulo": 0.3,
	"clique": 0.03,
	"construir": 0.05,
	"remover": 0.05,
	"alerta": 3.0,
	"pesquisa": 1.0,
	"derrota": 2.0,
	"tiro": 0.06,
	"tiro_metralhadora": 0.06,
	"tiro_energia": 0.08,
	"tiro_foguete": 0.12,
	"tiro_enxame": 0.07,
	"tiro_artilharia": 0.30,
	"tiro_perfurante": 0.07,
	"tiro_carregada": 0.09,
	"tiro_drone": 0.05,
	"impacto": 0.20,
	"impacto_aranha": 0.04,
	"impacto_chao": 0.05,
	"impacto_estrutura": 0.05,
	"explosao": 0.10,
	"explosao_grande": 0.25,
	"mina_pulso": 0.18,
	"maq_fornalha": 0.35,
	"maq_montadora": 0.30,
	"maq_broca": 0.25,
	"maq_esteira": 0.35,
	"apito_trem": 3.0,
	"trem_trilho": 0.40,
	"aranha_passo": 0.04,
	"aranha_morre": 0.08,
	"trovao": 1.5,
	"fogo": 2.0,
	"faisca": 0.15,
	"solda_arco": 0.1,
	"solda_mig": 0.1,
	"sapo": 1.0,
}

const MAX_VOZES := {
	"maq_fornalha": 2,
	"maq_montadora": 2,
	"maq_broca": 2,
	"maq_esteira": 2,
	"trem_trilho": 2,
	"apito_trem": 2,
	"aranha_passo": 2,
	"aranha_morre": 3,
	"tiro": 4,
	"tiro_metralhadora": 4,
	"tiro_energia": 3,
	"tiro_foguete": 3,
	"tiro_enxame": 3,
	"tiro_artilharia": 2,
	"tiro_perfurante": 3,
	"tiro_carregada": 3,
	"tiro_drone": 3,
	"impacto_aranha": 4,
	"impacto_chao": 3,
	"impacto_estrutura": 3,
	"explosao": 4,
	"explosao_grande": 2,
	"mina_pulso": 2,
}

const SONS_AMBIENTE := {
	"amb_grilos": true,
	"amb_insetos_dia": true,
	"amb_moscas": true,
	"rato_chiado": true,
	"rato_guincho": true,
	"rato_cavar": true,
	"rato_roendo": true,
	"filhotes": true,
	"bando_migrando": true,
	"herbivoro_alarme": true,
	"predador_uivo": true,
	"predador_rosnado": true,
	"peixe_pulo": true,
	"amb_enxame": true,
	"sapo": true,
	"chuva": true,
	"trovao": true,
	"vento_forte": true,
}

var _sons: Dictionary = {}
var _ultimo: Dictionary = {}
var _pool2d: Array[AudioStreamPlayer] = []
var _pool3d: Array[AudioStreamPlayer3D] = []
var _loops_ambiente: Dictionary = {}
var _loops_maq: Dictionary = {}       ## chave → {p: AudioStreamPlayer3D, visto: float, vol: float}: máquina trabalhando em laço
var _wav_laco: Dictionary = {}        ## nome → cópia do som com laço ligado
const MAQ_ENTRA := 0.25               ## s de fade quando a máquina começa
const MAQ_SAI := 0.6                  ## s de fade quando ela para (ou sai do alcance)
const MAQ_ESQUECE := 0.9              ## s sem ser renovado = parou


func _init() -> void:
	_carregar_sons()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _sons.is_empty():
		_carregar_sons()
	_criar_pools()


## Variações do mesmo som ("aranha_passo__2.wav", "__3"…): cada toque sorteia uma (o passo não vira metralhadora).
var _variantes: Dictionary = {}       ## nome → Array[AudioStream] (só os que têm mais de um arquivo)


func _carregar_sons() -> void:
	var dir := "res://assets/sons"
	var vistos := {}
	for f in DirAccess.get_files_at(dir):
		var arq := f.trim_suffix(".import")
		if not arq.ends_with(".wav") or vistos.has(arq):
			continue
		vistos[arq] = true
		var nome := arq.get_basename()
		var base := nome.get_slice("__", 0)
		var s: AudioStream = load(dir + "/" + arq)
		if base == nome:
			_sons[base] = s
		elif not _sons.has(base):
			_sons[base] = s
		if not _variantes.has(base):
			_variantes[base] = []
		(_variantes[base] as Array).append(s)
	for base in _variantes.keys():
		if (_variantes[base] as Array).size() < 2:
			_variantes.erase(base)


func _stream(nome: String) -> AudioStream:
	var vs: Array = _variantes.get(nome, [])
	return vs.pick_random() if not vs.is_empty() else _sons[nome]


func _criar_pools() -> void:
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.bus = "Efeitos"
		p.set_meta("som", "")
		p.set_meta("inicio", 0.0)
		add_child(p)
		_pool2d.append(p)
	for i in 16:
		var p := AudioStreamPlayer3D.new()
		p.bus = "Efeitos"
		p.unit_size = 18.0
		p.max_distance = 140.0
		p.set_meta("som", "")
		p.set_meta("inicio", 0.0)
		add_child(p)
		_pool3d.append(p)


func tem_som(nome: String) -> bool:
	return _sons.has(nome)


func barramento_do_som(nome: String) -> String:
	return "Ambiente" if SONS_AMBIENTE.has(nome) else "Efeitos"


## Toca som pontual em 2D (onde = INF) ou posicionado em 3D.
func tocar(nome: String, onde := Vector3.INF, volume_db := 0.0, bus_custom := "") -> Variant:
	if not _sons.has(nome) or DisplayServer.get_name() == "headless":
		return null
	var agora := Time.get_ticks_msec() / 1000.0
	var min_int: float = float(INTERVALO.get(nome, 0.0))
	if agora - float(_ultimo.get(nome, -99.0)) < min_int:
		return null
	var barramento: String = bus_custom if bus_custom != "" else barramento_do_som(nome)
	if onde == Vector3.INF:
		var p := _obter_player_2d(nome, agora)
		if p == null:
			return null
		_ultimo[nome] = agora
		p.stream = _stream(nome)
		p.bus = barramento
		p.volume_db = volume_db
		p.pitch_scale = randf_range(0.97, 1.03)
		p.set_meta("som", nome)
		p.set_meta("inicio", agora)
		p.play()
		return p
	else:
		var p := _obter_player_3d(nome, agora)
		if p == null:
			return null
		_ultimo[nome] = agora
		p.stream = _stream(nome)
		p.bus = barramento
		p.global_position = onde
		p.unit_size = 18.0
		p.max_distance = 140.0
		p.volume_db = volume_db
		p.pitch_scale = randf_range(0.94, 1.06)
		p.set_meta("som", nome)
		p.set_meta("inicio", agora)
		p.play()
		return p


## Toca som de máquina ativa (fornalha, montadora, broca, esteira, trem) com atenuação
## acentuada por distância e teto estrito de vozes simultâneas.
## Som contínuo de máquina, esteira ou trem: um laço por `chave` que segue a posição. Quem chama renova a cada
## atualização (0,35 s); sem renovação por MAQ_ESQUECE s, o laço some com fade. Começa num ponto ao acaso do
## laço, para duas máquinas iguais não soarem em uníssono.
func loop_maquina(chave: String, nome: String, onde: Vector3, volume_db := 0.0, distancia_max := 55.0) -> void:
	if not _sons.has(nome) or DisplayServer.get_name() == "headless":
		return
	var agora := Time.get_ticks_msec() / 1000.0
	var l: Dictionary = _loops_maq.get(chave, {})
	if l.is_empty():
		var p := AudioStreamPlayer3D.new()
		p.bus = "Efeitos"
		p.unit_size = 10.0
		p.max_distance = distancia_max
		p.stream = _laco(nome)
		p.volume_db = -60.0
		add_child(p)
		p.global_position = onde
		var wav := p.stream as AudioStreamWAV
		p.play(randf() * (wav.get_length() if wav != null else 0.0))
		l = {"p": p, "visto": agora, "vol": volume_db}
		_loops_maq[chave] = l
	l.visto = agora
	l.vol = volume_db
	(l.p as AudioStreamPlayer3D).global_position = onde


func _laco(nome: String) -> AudioStream:
	if not _wav_laco.has(nome):
		var s: AudioStream = _sons[nome]
		if s is AudioStreamWAV:
			var w := (s as AudioStreamWAV).duplicate() as AudioStreamWAV
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = w.data.size() / (2 * (2 if w.stereo else 1))
			s = w
		_wav_laco[nome] = s
	return _wav_laco[nome]


func _process(delta: float) -> void:
	if _loops_maq.is_empty():
		return
	var agora := Time.get_ticks_msec() / 1000.0
	for chave in _loops_maq.keys():
		var l: Dictionary = _loops_maq[chave]
		var p: AudioStreamPlayer3D = l.p
		var vivo := agora - float(l.visto) < MAQ_ESQUECE
		var alvo: float = float(l.vol) if vivo else -60.0
		var passo := delta * 60.0 / (MAQ_ENTRA if vivo else MAQ_SAI)       # dB por quadro até o alvo
		p.volume_db = move_toward(p.volume_db, alvo, passo)
		if not vivo and p.volume_db <= -59.0:
			p.queue_free()
			_loops_maq.erase(chave)


func tocar_maquina(nome: String, onde: Vector3, volume_db := 0.0, distancia_max := 55.0) -> Variant:
	if not _sons.has(nome) or DisplayServer.get_name() == "headless":
		return null
	var ouvido: Node3D = get_viewport().get_audio_listener_3d()      # versão 2D: o ouvido, não a câmera distante
	if ouvido == null:
		ouvido = get_viewport().get_camera_3d()
	if ouvido != null:
		if ouvido.global_position.distance_to(onde) > distancia_max:
			return null
	var agora := Time.get_ticks_msec() / 1000.0
	var min_int: float = float(INTERVALO.get(nome, 0.25))
	if agora - float(_ultimo.get(nome, -99.0)) < min_int:
		return null
	var p := _obter_player_3d(nome, agora)
	if p == null:
		return null
	_ultimo[nome] = agora
	p.stream = _stream(nome)
	p.bus = "Efeitos"
	p.global_position = onde
	p.unit_size = 10.0
	p.max_distance = distancia_max
	p.volume_db = volume_db
	p.pitch_scale = randf_range(0.96, 1.04)
	p.set_meta("som", nome)
	p.set_meta("inicio", agora)
	p.play()
	return p


## Atualiza ou inicia som contínuo em loop de ambiente (chuva, vento forte).
func tocar_loop_ambiente(nome: String, volume_linear: float) -> void:
	if DisplayServer.get_name() == "headless" or not _sons.has(nome):
		return
	var player: AudioStreamPlayer = _loops_ambiente.get(nome)
	if player == null:
		player = AudioStreamPlayer.new()
		player.bus = "Ambiente"
		var s = _sons[nome]
		if s is AudioStreamWAV:
			var wav: AudioStreamWAV = s
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_end = wav.data.size() / 2
			player.stream = wav
		else:
			player.stream = s
		add_child(player)
		_loops_ambiente[nome] = player
	if volume_linear > 0.02:
		player.volume_db = linear_to_db(clampf(volume_linear, 0.0001, 1.0))
		if not player.playing:
			player.play()
	elif player.playing:
		player.stop()


func _obter_player_2d(nome: String, agora: float) -> AudioStreamPlayer:
	var ativas := 0
	var player_mais_antigo: AudioStreamPlayer = null
	var tempo_mais_antigo := 1e9
	for p in _pool2d:
		if p.playing and p.get_meta("som", "") == nome:
			ativas += 1
			var ini: float = float(p.get_meta("inicio", 0.0))
			if ini < tempo_mais_antigo:
				tempo_mais_antigo = ini
				player_mais_antigo = p
	var max_v: int = int(MAX_VOZES.get(nome, 6))
	if ativas >= max_v:
		return player_mais_antigo
	for p in _pool2d:
		if not p.playing:
			return p
	return _pool2d[0]


func _obter_player_3d(nome: String, agora: float) -> AudioStreamPlayer3D:
	var ativas := 0
	var player_mais_antigo: AudioStreamPlayer3D = null
	var tempo_mais_antigo := 1e9
	for p in _pool3d:
		if p.playing and p.get_meta("som", "") == nome:
			ativas += 1
			var ini: float = float(p.get_meta("inicio", 0.0))
			if ini < tempo_mais_antigo:
				tempo_mais_antigo = ini
				player_mais_antigo = p
	var max_v: int = int(MAX_VOZES.get(nome, 6))
	if ativas >= max_v:
		return player_mais_antigo
	for p in _pool3d:
		if not p.playing:
			return p
	return _pool3d[0]
