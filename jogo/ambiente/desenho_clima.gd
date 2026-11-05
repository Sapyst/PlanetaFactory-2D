class_name DesenhoClima
extends Node3D
## Desenha o Clima (só lê a lógica):
##  - parâmetros globais de shader: sombra das nuvens (correndo com o vento) e chão molhado — ver clima.gdshaderinc;
##  - luz: sol e céu baixam com as nuvens; relâmpago acende tudo por um instante e o trovão vem depois;
##  - raio: cai onde a lógica (Raios) mandou — na ponta do para-raios, no topo da construção atingida, no chão; na
##    cúpula contra raios bate no campo e um segundo arco desce do alto dela até o cristal; o clarão e o trovão
##    enfraquecem e atrasam com a distância da câmera;
##  - dia e noite (Clima.hora): o sol anda de leste a oeste e baixa, fica alaranjado no fim da tarde, some; à noite a
##    mesma luz vira lua (azulada, fraca, vinda de outro lado — a troca acontece com as duas apagadas no horizonte),
##    céu e ambiente escurecem para azul-noite e os cristais das máquinas passam a se destacar;
##  - neblina: existe no mundo, não é filtro — pilha de fatias finas rente ao chão (ver neblina.gdshader), com corpo,
##    andando com o vento, abrindo onde há calor (`fontes_calor`); a névoa do ambiente só dá a distância;
##  - raios de sol: feixes descendo pelos buracos das nuvens (ver raios_sol.gdshader) — com céu parcialmente
##    nublado, mais fortes com ar úmido (depois da chuva, neblina);
##  - chuva: partículas na GPU só em volta do que a câmera vê (menos no celular), com som em loop. Cada gota é um
##    risco 3D alinhado à queda (nada de plano virado para a câmera). Respingos (coroa + anel, malhas 3D) nascem
##    em pontos sorteados na superfície de verdade em volta da câmera — chão com a ondulação, esteira, água —
##    renovados a cada fração de segundo (colisão de partícula na GPU não existe no renderizador do celular).

const GOTAS_PC := 1600
const GOTAS_CELULAR := 400
const RESPINGOS_PC := 1600
const RESPINGOS_CELULAR := 400
const FATIAS_PC := 10
const FATIAS_CELULAR := 3
const TOPO_NEBLINA := 3.2
const FATIAS_RAIOS_PC := 14
const FATIAS_RAIOS_CELULAR := 3
const TOPO_RAIOS := 18.0
const COR_NEBLINA := Color(0.72, 0.74, 0.76)
const COR_TEMPESTADE := Color(0.36, 0.39, 0.43)
const COR_POENTE := Color(1.0, 0.56, 0.32)
const COR_LUA := Color(0.58, 0.68, 1.0)
const LUA := 0.44                       ## força da lua em relação ao sol
const AMBIENTE_NOITE := 0.62            ## céu à noite (fração do de dia)
const PREENCHE_NOITE := 0.85            ## luz de preenchimento à noite (fração da de dia): é ela que dá forma ao lado oposto da lua
const AZUL_NOITE := Color(0.20, 0.25, 0.40)  ## luar difuso: o céu de noite é escuro demais para clarear as sombras sozinho
const MISTURA_AZUL := 0.35              ## parte do ambiente que vem dele à noite
const CEU_NOITE := [Color(0.025, 0.04, 0.10), Color(0.08, 0.10, 0.18)]   ## topo, horizonte
const CEU_POENTE := Color(0.85, 0.52, 0.36)

var clima: Clima
var camera: CameraJogo
var ambiente: WorldEnvironment
var sol: DirectionalLight3D
var fontes_calor: Callable           ## → Array de Vector3 (x, z do mundo, raio): onde a névoa abre
var raios: Raios                     ## (opcional) onde cada raio caiu; sem ele, o raio cai num ponto qualquer da vista

var _chuva: GPUParticles3D
var _proc: ParticleProcessMaterial
var mapa: MapaOcupacao                ## esteiras: o respingo bate na lona, não no chão debaixo dela
var _respingo: GPUParticles3D
var _pontos: Image
var _pontos_tex: ImageTexture
var _proc_respingo: ParticleProcessMaterial
var _t_pontos := 0.0
var _rng := RandomNumberGenerator.new()
var _neblina: MeshInstance3D
var _mat_neblina: ShaderMaterial
var _fatias := 0
var _raios_sol: MeshInstance3D
var _mat_raios: ShaderMaterial
var _fatias_raios := 0
var _claros: Dictionary = {}         ## Vector2i(ponto arredondado) → [Vector3 fonte, força 0..1] (abre e fecha devagar)
var _raio: MeshInstance3D
var _malha_raio: ImmediateMesh
var _mat_raio: ShaderMaterial
var _luz_raio: OmniLight3D           ## clarão no ponto do impacto (curto, sem sombra)
var _raio_linhas: Array = []         ## o golpe de agora ([de, até, largura, força] por traço), para o re-golpe
var _raio_t := 0.0                   ## segundos desde o golpe
var _raio_regolpe := false           ## o segundo pisco (outro traçado) já aconteceu
var _raio_perto := 1.0               ## 0,25..1: quão perto da câmera (clarão e luz)
var _som_chuva: AudioStreamPlayer
var _base := {}
var _flash := 0.0
var _vida_raio := 0.0
var _trovoes: Array[float] = []      ## segundos até cada trovão pendente
var _ceu: ProceduralSkyMaterial
var mexer_ceu := true                ## medição: false deixa o céu parado (o céu refaz o reflexo do ambiente ao mudar)
var _preenche: DirectionalLight3D


var _vento_tempo := 0.0              ## relógio do balanço da vegetação (somado aos poucos: mudar a força não dá salto)

func _ready() -> void:
	var env := ambiente.environment
	_base = {"sol": sol.light_energy, "ceu": env.ambient_light_energy, "neblina": env.fog_light_color,
			"saturacao": env.adjustment_saturation, "cor_sol": sol.light_color, "dir": sol.global_transform.basis.z.normalized()}
	if env.sky != null and env.sky.sky_material is ProceduralSkyMaterial:
		_ceu = env.sky.sky_material
		env.sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL      # reflexo do céu refeito aos poucos, não num quadro só
		_base.ceu_topo = _ceu.sky_top_color
		_base.ceu_horizonte = _ceu.sky_horizon_color
		_base.chao_horizonte = _ceu.ground_horizon_color
		_base.chao_fundo = _ceu.ground_bottom_color
	_preenche = sol.get_parent().get_node_or_null("Preenchimento") as DirectionalLight3D
	if _preenche != null:
		_base.preenche = _preenche.light_energy
	_criar_chuva()
	_criar_neblina()
	_criar_raios_sol()
	_criar_raio()
	_som_chuva = AudioStreamPlayer.new()
	_som_chuva.bus = "Ambiente"
	add_child(_som_chuva)


func _process(delta: float) -> void:
	if clima == null:
		return
	clima.ativo = bool(Sessao.config.get("clima", true))
	var v := clima.valores
	RenderingServer.global_shader_parameter_set("nuvem_cobertura", v.nuvens)
	RenderingServer.global_shader_parameter_set("nuvem_deslocamento", clima.deslocamento)
	RenderingServer.global_shader_parameter_set("molhado", clima.molhado)
	RenderingServer.global_shader_parameter_set("pocas", clima.pocas)
	RenderingServer.global_shader_parameter_set("vico_grama", clima.vico)
	RenderingServer.global_shader_parameter_set("chuva_agora", v.chuva)
	RenderingServer.global_shader_parameter_set("vento_dir", clima.direcao_vento * (0.4 + v.vento))
	_vento_tempo += delta * Clima.ritmo_vento(float(v.vento))
	RenderingServer.global_shader_parameter_set("vento_tempo", _vento_tempo)
	RenderingServer.global_shader_parameter_set("estacao_atual", float(clima.estacao) + clamp(clima.t_estacao / float(Registro.clima.get("estacao_s", 604800)), 0.0, 0.999))
	var rj: Dictionary = clima.rajada
	RenderingServer.global_shader_parameter_set("rajada", Vector3(float(rj.frente), float(rj.amp), float(rj.largura)) if not rj.is_empty() else Vector3(-1.0e6, 0.0, 12.0))
	_relampagos(delta)
	var dia := _dia_e_noite()
	RenderingServer.global_shader_parameter_set("sol_dir", sol.global_transform.basis.z.normalized())
	# luz e névoa do ambiente
	var env := ambiente.environment
	sol.light_energy = sol.light_energy * v.luz + _flash * 2.6
	sol.shadow_opacity = 1.0 - 0.55 * v.nuvens      # céu fechado: luz difusa, sombra fraca
	env.ambient_light_energy = _base.ceu * (0.7 + 0.3 * v.luz) * lerpf(AMBIENTE_NOITE, 1.0, dia) + _flash * 1.2
	env.ambient_light_color = AZUL_NOITE
	env.ambient_light_sky_contribution = lerpf(1.0 - MISTURA_AZUL, 1.0, dia)
	var cor: Color = (_base.neblina as Color).lerp(COR_NEBLINA, v.neblina * 0.7).lerp(COR_TEMPESTADE, v.chuva * 0.65)
	env.fog_light_color = cor.lerp(Color(0.10, 0.13, 0.22), 0.85 * (1.0 - dia))
	# névoa mais rala quanto mais longe a câmera (de longe o mapa não desbota); neblina engrossa em qualquer zoom
	env.fog_density = (0.055 + 0.05 * v.neblina + 0.06 * v.chuva) / camera.distancia
	env.adjustment_saturation = _base.saturacao - 0.18 * v.chuva - 0.10 * v.neblina
	_atualizar_neblina(delta, v.neblina, v.luz)
	_atualizar_raios_sol(v)
	_atualizar_chuva(v.chuva, v.vento)


# ------------------------------------------------------------------ dia e noite
## Posição e cor do sol (ou da lua), céu e luz de preenchimento pela hora. Devolve a luz do dia 0..1.
func _dia_e_noite() -> float:
	var alt := clima.altura_sol()
	var dia := clima.luz_dia()
	var f_sol := smoothstep(-0.05, 0.3, alt)
	var f_lua := smoothstep(-0.02, -0.08, alt)   # a lua entra logo: antes, o entardecer ficava mais escuro que a meia-noite
	var d0: Vector3 = _base.dir
	var el0 := asin(clampf(d0.y, -1.0, 1.0))
	var az0 := atan2(d0.x, d0.z)
	var el: float
	var az: float
	if alt > -0.025:                     # sol: nasce a leste, meio-dia na pose original, se põe a oeste
		el = lerpf(0.10, el0, smoothstep(0.0, 1.0, alt))
		az = az0 + (clima.hora - 0.5) * PI * 1.2
		sol.light_color = COR_POENTE.lerp(_base.cor_sol, smoothstep(0.0, 0.7, alt))
		sol.light_energy = _base.sol * f_sol
	else:                                # lua: alta, de outro lado, azulada
		el = deg_to_rad(52.0)
		az = az0 + PI * 0.65
		sol.light_color = COR_LUA
		sol.light_energy = _base.sol * LUA * f_lua
	var dir := Vector3(cos(el) * sin(az), sin(el), cos(el) * cos(az))
	sol.global_basis = Basis.looking_at(-dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD)
	if _preenche != null:
		_preenche.light_energy = _base.preenche * lerpf(PREENCHE_NOITE, 1.0, dia)
	if _ceu != null and mexer_ceu:
		var poente := clampf(1.0 - absf(alt - 0.1) / 0.35, 0.0, 1.0)        # céu alaranjado perto do horizonte
		var hz: Color = (_base.ceu_horizonte as Color).lerp(CEU_POENTE, poente * 0.6)
		# o céu refaz o reflexo do ambiente toda vez que muda: só passa a cor nova quando a diferença se vê
		var topo := (CEU_NOITE[0] as Color).lerp(_base.ceu_topo, dia)
		var horiz := (CEU_NOITE[1] as Color).lerp(hz, dia)
		if _dif_cor(topo, _ceu.sky_top_color) > 0.006 or _dif_cor(horiz, _ceu.sky_horizon_color) > 0.006:
			_ceu.sky_top_color = topo
			_ceu.sky_horizon_color = horiz
			_ceu.ground_horizon_color = (CEU_NOITE[1] as Color).lerp(_base.chao_horizonte, dia)
			_ceu.ground_bottom_color = (CEU_NOITE[0] as Color).lerp(_base.chao_fundo, dia)   # fundo dos chunks ainda não desenhados
	return dia


static func _dif_cor(a: Color, b: Color) -> float:
	return maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))


# ------------------------------------------------------------------ chuva
func _criar_chuva() -> void:
	var celular := OS.has_feature("mobile")
	_chuva = GPUParticles3D.new()
	_chuva.amount = GOTAS_CELULAR if celular else GOTAS_PC
	_chuva.lifetime = 1.1
	_chuva.local_coords = false
	_chuva.visibility_aabb = AABB(Vector3(-70, -30, -70), Vector3(140, 60, 140))
	_chuva.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_proc = ParticleProcessMaterial.new()
	_proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_proc.direction = Vector3.DOWN
	_proc.spread = 2.0
	_proc.initial_velocity_min = 17.0
	_proc.initial_velocity_max = 22.0
	_proc.gravity = Vector3(0, -9.8, 0)
	_proc.particle_flag_align_y = true                 # o risco segue a direção da queda (com vento, inclina)
	_chuva.process_material = _proc
	var gota := BoxMesh.new()                          # risco fino de verdade (3D), não um plano
	gota.size = Vector3(0.014, 0.5, 0.014)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.78, 0.82, 0.88, 0.32)
	gota.material = m
	_chuva.draw_pass_1 = gota
	_chuva.emitting = false
	add_child(_chuva)
	_criar_respingo(celular)


## Respingo: coroa d'água que abre e um anel rente ao chão que se espalha, os dois somem em ~0,3 s. Malhas 3D
## de verdade (coroa = tubo aberto, anel = toro achatado), nascidas onde cada gota bateu.
func _criar_respingo(celular: bool) -> void:
	_respingo = GPUParticles3D.new()
	_respingo.amount = RESPINGOS_CELULAR if celular else RESPINGOS_PC
	_respingo.lifetime = 0.26
	_respingo.local_coords = false
	_respingo.visibility_aabb = AABB(Vector3(-70, -40, -70), Vector3(140, 80, 140))
	_respingo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	var n := 128 if celular else 512
	_pontos = Image.create(n, 1, false, Image.FORMAT_RGBF)
	_pontos_tex = ImageTexture.create_from_image(_pontos)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	pm.emission_point_texture = _pontos_tex
	pm.emission_point_count = n
	_proc_respingo = pm
	pm.direction = Vector3.UP
	pm.spread = 0.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	pm.gravity = Vector3.ZERO
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	var cresce := Curve.new()
	cresce.add_point(Vector2(0.0, 0.35))
	cresce.add_point(Vector2(1.0, 1.6))
	var ct := CurveTexture.new()
	ct.curve = cresce
	pm.scale_curve = ct
	var some := Gradient.new()
	some.set_color(0, Color(1, 1, 1, 0.5))
	some.set_color(1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = some
	pm.color_ramp = gt
	_respingo.process_material = pm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.82, 0.87, 0.93)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var coroa := CylinderMesh.new()
	coroa.top_radius = 0.04
	coroa.bottom_radius = 0.012
	coroa.height = 0.045
	coroa.radial_segments = 10
	coroa.rings = 1
	coroa.cap_top = false
	coroa.cap_bottom = false
	coroa.material = mat
	var anel := TorusMesh.new()
	anel.inner_radius = 0.06
	anel.outer_radius = 0.07
	anel.rings = 16
	anel.ring_segments = 4
	anel.material = mat
	_respingo.draw_passes = 2
	_respingo.draw_pass_1 = coroa
	_respingo.draw_pass_2 = anel
	_respingo.emitting = false
	add_child(_respingo)


## Sorteia de novo os pontos onde as gotas batem, na caixa da chuva: altura do que está ali de verdade.
func _sortear_pontos(centro: Vector3, e: float) -> void:
	var g := Grade.gerador
	var n := _pontos.get_width()
	for i in n:
		var p := Vector2(centro.x + _rng.randf_range(-e, e), -centro.z + _rng.randf_range(-e * 0.8, e * 0.8))
		var y := _altura_superficie(g, p)
		if is_nan(y):
			y = -1000.0                                 # encosta/construção alta: sem respingo (fica longe da vista)
		_pontos.set_pixel(i, 0, Color(p.x, y + 0.01, -p.y))
	_pontos_tex.update(_pontos)


func _altura_superficie(g: GeradorMundo, p: Vector2) -> float:
	if g == null:
		return 0.0
	var t := Vector2i(floori(p.x), floori(p.y))
	var base := float(g.nivel(t)) * Grade.ALT_NIVEL
	if g.eh_agua(g.terreno(t)):
		return base - 0.12                              # lâmina d'água
	if g.em_encosta(t):
		return NAN
	if mapa != null and mapa.tiles.has(t):
		var nome: String = mapa.estruturas[mapa.tiles[t]].nome
		return base + 0.16 if nome.begins_with("esteira_") else NAN
	var plano := g.aplainado_em(t) != null
	if not plano and mapa != null:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if mapa.tiles.has(t + d):
				plano = true                            # o piso da fábrica em volta das construções é aplainado
				break
	if plano:
		var nv: Variant = g.aplainado_em(t)
		return float(nv) * Grade.ALT_NIVEL if nv != null else base
	return base + g.micro_em(p - Vector2(0.5, 0.5))


func _atualizar_chuva(chuva: float, vento: float) -> void:
	var ligar := chuva > 0.03
	if ligar != _chuva.emitting:
		_chuva.emitting = ligar
	var vol := linear_to_db(maxf(chuva * 0.9, 0.0001))
	if chuva > 0.03 and DisplayServer.get_name() != "headless":
		if not _som_chuva.playing and Som._sons.has("chuva"):
			var s: AudioStreamWAV = Som._sons["chuva"]
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
			s.loop_end = s.data.size() / 2
			_som_chuva.stream = s
			_som_chuva.play()
		_som_chuva.volume_db = vol
	elif _som_chuva.playing:
		_som_chuva.stop()
	if vento > 0.45 and DisplayServer.get_name() != "headless":
		Som.tocar_loop_ambiente("vento_forte", (vento - 0.45) / 0.55 * 0.7)
	else:
		Som.tocar_loop_ambiente("vento_forte", 0.0)
	_respingo.emitting = ligar
	if not ligar:
		return
	_chuva.amount_ratio = chuva
	_respingo.amount_ratio = chuva
	# caixa de onde as gotas caem: segue o ponto olhado, do tamanho da vista (com limite)
	var e := clampf(camera.distancia * 0.55, 12.0, 45.0)
	_proc.emission_box_extents = Vector3(e, 3.0, e * 0.8)
	_chuva.global_position = camera.alvo + Vector3(0, 15, 0)
	_t_pontos -= get_process_delta_time()
	if _t_pontos <= 0.0:
		_t_pontos = 0.2
		_sortear_pontos(camera.alvo, e)
	var w := clima.direcao_vento * 7.0 * vento
	_proc.gravity = Vector3(w.x, -9.8, w.y)


# ------------------------------------------------------------------ neblina de chão
func _criar_neblina() -> void:
	_fatias = FATIAS_CELULAR if OS.has_feature("mobile") else FATIAS_PC
	_mat_neblina = ShaderMaterial.new()
	_mat_neblina.shader = load("res://ambiente/neblina.gdshader")
	_mat_neblina.set_shader_parameter("topo", TOPO_NEBLINA)
	_neblina = MeshInstance3D.new()
	_neblina.mesh = _fatias_planas(_fatias, TOPO_NEBLINA, 1.4)      # mais fatias perto do chão, onde é densa
	_neblina.material_override = _mat_neblina
	_neblina.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_neblina.extra_cull_margin = 8.0
	_neblina.visible = false
	add_child(_neblina)


func _atualizar_neblina(delta: float, neblina: float, luz: float) -> void:
	# celular: cada fatia cobre a tela inteira (custo de preenchimento) — só liga com neblina de verdade
	_neblina.visible = neblina > (0.3 if OS.has_feature("mobile") else 0.03)
	if not _neblina.visible:
		return
	var lado := clampf(camera.distancia * 2.6, 40.0, 320.0)
	_neblina.position = Vector3(camera.alvo.x, 0, camera.alvo.z)
	_neblina.scale = Vector3(lado, 1, lado)
	# a pilha inteira chega a ~90% onde é densa: cada fatia leva a sua parte
	var alvo := 0.9 * clampf(neblina, 0.0, 1.0)
	_mat_neblina.set_shader_parameter("alfa_fatia", 1.0 - pow(1.0 - alvo, 1.0 / _fatias))
	var c := ambiente.environment.fog_light_color
	_mat_neblina.set_shader_parameter("cor_luz", c * (0.75 + 0.35 * luz))
	_mat_neblina.set_shader_parameter("cor_base", c * (0.55 + 0.2 * luz) * Color(0.95, 0.98, 1.05))
	_mat_neblina.set_shader_parameter("flash", _flash)
	_atualizar_claros(delta)


## Calor abre a névoa aos poucos e ela volta a fechar quando a fonte para (16 mais perto da câmera).
func _atualizar_claros(delta: float) -> void:
	var vivas := {}
	if fontes_calor.is_valid():
		for f: Vector3 in fontes_calor.call():
			vivas[Vector2i(roundi(f.x), roundi(f.y))] = f
	for k in vivas:
		if not _claros.has(k):
			_claros[k] = [vivas[k], 0.0]
		_claros[k][0] = vivas[k]
	var lista: Array = []
	for k in _claros.keys():
		var cl: Array = _claros[k]
		cl[1] = clampf(cl[1] + (delta / 2.5 if vivas.has(k) else -delta / 6.0), 0.0, 1.0)
		if cl[1] <= 0.0 and not vivas.has(k):
			_claros.erase(k)
			continue
		lista.append(cl)
	var olho := Vector2(camera.alvo.x, camera.alvo.z)
	lista.sort_custom(func(a, b): return Vector2(a[0].x, a[0].y).distance_squared_to(olho) < Vector2(b[0].x, b[0].y).distance_squared_to(olho))
	var arr := PackedVector4Array()
	arr.resize(16)
	var n := mini(lista.size(), 16)
	for i in n:
		var f: Vector3 = lista[i][0]
		arr[i] = Vector4(f.x, f.y, f.z, smoothstep(0.0, 1.0, lista[i][1]))
	_mat_neblina.set_shader_parameter("claros", arr)
	_mat_neblina.set_shader_parameter("n_claros", n)


# ------------------------------------------------------------------ raios de sol
func _fatias_planas(n: int, topo: float, curva: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in n:
		var y := topo * pow((f + 0.5) / n, curva)
		var c := [Vector3(-0.5, y, -0.5), Vector3(0.5, y, -0.5), Vector3(0.5, y, 0.5), Vector3(-0.5, y, 0.5)]
		var uv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_uv(uv[k])
			st.add_vertex(c[k])
	return st.commit()


func _criar_raios_sol() -> void:
	_fatias_raios = FATIAS_RAIOS_CELULAR if OS.has_feature("mobile") else FATIAS_RAIOS_PC
	_mat_raios = ShaderMaterial.new()
	_mat_raios.shader = load("res://ambiente/raios_sol.gdshader")
	_mat_raios.set_shader_parameter("topo", TOPO_RAIOS)
	_raios_sol = MeshInstance3D.new()
	_raios_sol.mesh = _fatias_planas(_fatias_raios, TOPO_RAIOS, 1.0)
	_raios_sol.material_override = _mat_raios
	_raios_sol.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_raios_sol.extra_cull_margin = 20.0
	_raios_sol.visible = false
	add_child(_raios_sol)


func _atualizar_raios_sol(v: Dictionary) -> void:
	# feixe só existe com céu QUASE fechado: poucos buracos pequenos, cada um uma coluna de luz com escuro em volta
	# (céu aberto = sol em tudo = nenhum feixe); ar úmido (depois da chuva, neblina) deixa o feixe mais visível
	var buracos: float = smoothstep(0.68, 0.8, v.nuvens) * (1.0 - smoothstep(0.93, 0.99, v.nuvens))
	var umidade: float = 0.45 + 0.35 * clima.molhado + 0.5 * v.neblina
	var f: float = buracos * smoothstep(0.45, 0.7, v.luz) * umidade * smoothstep(0.1, 0.5, clima.altura_sol())
	_raios_sol.visible = f > (0.08 if OS.has_feature("mobile") else 0.02)
	if not _raios_sol.visible:
		return
	var lado := clampf(camera.distancia * 2.8, 50.0, 340.0)
	_raios_sol.position = Vector3(camera.alvo.x, 0, camera.alvo.z)
	_raios_sol.scale = Vector3(lado, 1, lado)
	_mat_raios.set_shader_parameter("forca", f * 0.75 / _fatias_raios)
	_mat_raios.set_shader_parameter("cor", sol.light_color)


# ------------------------------------------------------------------ relâmpagos
func _criar_raio() -> void:
	_malha_raio = ImmediateMesh.new()
	_raio = MeshInstance3D.new()
	_raio.mesh = _malha_raio
	_raio.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_raio.extra_cull_margin = 60.0
	_mat_raio = ShaderMaterial.new()              # aditivo acima de 1: o bloom pega; halo em malha para o celular
	_mat_raio.shader = preload("res://render/shaders/relampago.gdshader")
	_raio.material_override = _mat_raio
	add_child(_raio)
	_luz_raio = OmniLight3D.new()
	_luz_raio.light_color = Color(0.78, 0.84, 1.0)
	_luz_raio.omni_range = 18.0
	_luz_raio.omni_attenuation = 1.4
	_luz_raio.shadow_enabled = false
	_luz_raio.visible = false
	add_child(_luz_raio)


## Canal principal do raio até `topo` (mundo): vem do céu inclinado para longe da câmera, para que a vista de cima
## o veja inteiro (reto para cima ele vira um ponto: o alto fica atrás/acima da câmera). Com ramos.
## Cada traço: [de, até, largura (m), força 0..1].
func _canal(topo: Vector3) -> Array:
	var olho := camera.global_position if camera.is_inside_tree() else camera.position
	var longe_h := Vector3(topo.x - olho.x, 0.0, topo.z - olho.z)
	longe_h = longe_h.normalized() if longe_h.length() > 0.01 else Vector3(0, 0, -1)
	var lado := longe_h.cross(Vector3.UP)
	var de := topo + longe_h * randf_range(16.0, 28.0) + Vector3(0.0, 44.0, 0.0) + lado * randf_range(-12.0, 12.0)
	var tracos: Array = [[de, topo, 2.4, 1.0]]
	for i in randi_range(2, 3):                   # ramos: saem do meio do canal e morrem no ar, mais finos
		var t := randf_range(0.25, 0.7)
		var p := de.lerp(topo, t)
		var dir := (topo - de).normalized().rotated(Vector3.UP, randf_range(-1.1, 1.1)) + Vector3(0.0, randf_range(-0.5, 0.1), 0.0) + lado * randf_range(-0.8, 0.8)
		var fim := p + dir.normalized() * de.distance_to(topo) * randf_range(0.18, 0.38)
		fim.y = maxf(fim.y, topo.y + 2.0)              # ramo morre no ar, nunca abaixo do ponto do impacto
		tracos.append([p, fim, 1.2, 0.6])
	return tracos


## Um golpe: desenha, acende o clarão (mais fraco longe da câmera) e agenda o trovão (343 m/s).
func _golpe(tracos: Array, chao: Vector3) -> void:
	var longe := Vector2(camera.alvo.x - chao.x, camera.alvo.z - chao.z).length()
	_raio_perto = clampf(1.0 - longe / maxf(30.0, camera.distancia * 3.0), 0.25, 1.0)
	_flash = maxf(_flash, 0.7 * _raio_perto)        # mais que isso a névoa vira uma parede branca
	_raio_linhas = tracos
	_raio_t = 0.0
	_raio_regolpe = false
	_vida_raio = 0.34
	_desenhar_raio(tracos)
	_mat_raio.set_shader_parameter("brilho", 1.0)
	_luz_raio.position = chao + Vector3(0.0, 2.0, 0.0)
	_luz_raio.light_energy = 9.0 * _raio_perto
	_luz_raio.visible = true
	_trovoes.append(randf_range(0.3, 0.8) + longe / 340.0)


func _relampagos(delta: float) -> void:
	if raios != null:
		for q in raios.quedas:
			var topo := Grade.ponto_mundo(q.pos, float(q.alt))
			var tracos := _canal(topo)
			if q.tipo == "cupula":                       # bate no campo, desce do alto da cúpula até o cristal
				var c: Vector2 = q.centro
				var pt: Vector3 = q.ponta
				tracos.append([Grade.ponto_mundo(c, float(q.raio_cupula)), Grade.ponto_mundo(Vector2(pt.x, pt.y), pt.z), 1.4, 0.8])
			_golpe(tracos, Grade.ponto_mundo(q.pos, 0.0))
		raios.quedas.clear()
	for ev in clima.eventos:                        # sem a lógica dos raios (cena só de desenho): cai num ponto da vista
		if ev == "raio":
			var r := camera.distancia * 0.5
			var p := camera.alvo + Vector3(randf_range(-r, r), 0, randf_range(-r * 0.7, r * 0.7))
			_golpe(_canal(p), p)
	clima.eventos.clear()
	_flash = maxf(0.0, _flash - delta * 5.0)
	if _vida_raio > 0.0:
		_vida_raio -= delta
		_raio_t += delta
		if _vida_raio <= 0.0:
			_malha_raio.clear_surfaces()
			_luz_raio.visible = false
			_raio_linhas = []
		else:
			# golpe: cheio por 40 ms e apaga em exponencial; re-golpe aos 110 ms com outro traçado e mais fraco
			var b := 1.0 if _raio_t < 0.04 else exp(-(_raio_t - 0.04) * 11.0)
			if _raio_t >= 0.11:
				if not _raio_regolpe:
					_raio_regolpe = true
					_flash = maxf(_flash, 0.45 * _raio_perto)
					_desenhar_raio(_raio_linhas)
				b = maxf(b, 0.75 * (1.0 if _raio_t < 0.14 else exp(-(_raio_t - 0.14) * 9.0)))
			_mat_raio.set_shader_parameter("brilho", b)
			_luz_raio.light_energy = 9.0 * b * _raio_perto
	for i in range(_trovoes.size() - 1, -1, -1):
		_trovoes[i] -= delta
		if _trovoes[i] <= 0.0:
			Som.tocar("trovao", Vector3.INF, -2.0)
			_trovoes.remove_at(i)


## Traços ([de, até, largura, força], mundo) em fita virada para a câmera, UV.x atravessando a fita (o shader faz o
## núcleo e o halo). O caminho serpenteia (passeio aleatório puxado de volta ao eixo), com as pontas no lugar; os lados
## de cada vértice seguem a direção média dos dois segmentos, para a fita não abrir nas dobras. Chamar de novo com os
## mesmos traços sorteia outro traçado (re-golpe).
func _desenhar_raio(tracos: Array) -> void:
	_malha_raio.clear_surfaces()
	_malha_raio.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var olho_em := camera.global_position if camera.is_inside_tree() else camera.position
	for tr in tracos:
		var de: Vector3 = tr[0]
		var ate: Vector3 = tr[1]
		var largura: float = tr[2]
		var comp := de.distance_to(ate)
		var n := clampi(int(comp / 3.0), 4, 18)
		var eixo := (ate - de).normalized()
		var u := eixo.cross(Vector3.UP if absf(eixo.y) < 0.9 else Vector3.RIGHT).normalized()
		var w := eixo.cross(u)
		var passo := minf(2.0, comp * 0.05)
		var pts: Array[Vector3] = []
		var d1 := 0.0
		var d2 := 0.0
		for i in n + 1:
			var p := de.lerp(ate, float(i) / n)
			if i > 0 and i < n:
				d1 = d1 * 0.6 + randf_range(-passo, passo)
				d2 = d2 * 0.6 + randf_range(-passo, passo)
				var fim := minf(1.0, float(n - i) / 2.0)          # chega reta na ponta
				p += (u * d1 + w * d2) * fim
			pts.append(p)
		_malha_raio.surface_set_color(Color(1, 1, 1, float(tr[3])))
		var lados: Array[Vector3] = []
		for i in n + 1:
			var dir := (pts[mini(i + 1, n)] - pts[maxi(i - 1, 0)]).normalized()
			var olho := (olho_em - pts[i]).normalized()
			var l := dir.cross(olho)
			if l.length() < 1e-3:
				l = u
			lados.append(l.normalized() * largura * 0.5)
		for i in n:
			var q := [pts[i] - lados[i], pts[i] + lados[i], pts[i + 1] + lados[i + 1], pts[i + 1] - lados[i + 1]]
			var uv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
			for k in [0, 1, 2, 0, 2, 3]:
				_malha_raio.surface_set_uv(uv[k])
				_malha_raio.surface_add_vertex(q[k])
	_malha_raio.surface_end()
