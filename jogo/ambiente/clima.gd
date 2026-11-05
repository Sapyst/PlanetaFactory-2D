class_name Clima
extends RefCounted
## Clima dinâmico (lógica pura): estados de dados/clima.json trocando sozinhos (pesos do "proximo"), com transição
## suave dos valores. `valores` = o que o desenho usa agora (nuvens, neblina, chuva, luz, vento); `molhado` sobe com
## chuva e seca devagar; `deslocamento` = quanto as nuvens já andaram com o vento (sombra no chão).
## Tempestade solta raios (eventos). Desligado (`ativo` = false) fica em céu limpo.
## Vento: cada estação tem um rumo predominante ("vento_de", de onde vem); a direção do momento oscila ±40° em volta
## dele e a força vem do estado do clima. Rajadas: frentes que atravessam o mapa a favor do vento (perto de `foco`,
## onde a câmera olha), somando força por onde passam. `vento_medio` = média móvel (10 min de jogo) de direção × força.
## Grade: +x = leste, +y = norte. `direcao_vento` aponta PARA onde o vento sopra.

var ativo := true
var atual := "limpo"
var valores: Dictionary = {}
var molhado := 0.0
var pocas := 0.0          ## 0..1: quanto as baixadas já encheram (enche devagar com chuva forte, seca mais devagar ainda)
## Viço do capim (patch fauna, fase 2), −1 seco … 0 normal … +1 viçoso: a chuva enche (uns minutos de chuva forte
## deixam o campo verde e alto); sem chuva volta devagar — uns 2 dias de jogo — ao normal da estação, que no verão
## seco puxa para amarelo e baixo (−secura da estação).
var vico := 0.0
var deslocamento := Vector2.ZERO
var direcao_vento := Vector2(1, 0.35).normalized()
var t_vento := 0.0                   ## segundos de jogo (oscilação da direção)
var rajada := {}                     ## {frente (m ao longo do vento), amp, largura, vel}; vazio = nenhuma
var prox_rajada := 20.0
var foco := Vector2.ZERO             ## onde a câmera olha (grade): rajadas nascem a barlavento daqui
var vento_medio := Vector2.ZERO      ## média móvel de direção × força
var restante := 120.0
var tempo_real := false             ## jogo: estação pelo relógio de verdade (7 dias reais cada); testes usam o tempo simulado
var estacao := 0                    ## índice em clima.json "estacoes"
var t_estacao := 0.0
var ciclo := true                    ## false = relógio parado (fotos)
var hora := 0.3                     ## 0..1 do dia (0 = meia-noite, 0,5 = meio-dia); ciclo de clima.json "dia_s"
var poluicao_total := 0.0            ## vem do mundo: ar sujo deixa tufão mais provável
var eventos: Array[String] = []     ## acumula ("raio"); quem desenha consome e limpa
var _rng := RandomNumberGenerator.new()
var _rng_vento := RandomNumberGenerator.new()   ## rajadas à parte: não mexem na sequência do clima
var _d: Dictionary


func _init(semente := 1) -> void:
	_rng.seed = semente
	_rng_vento.seed = semente * 7919 + 13
	_d = Registro.clima
	valores = _alvo().duplicate()


func nome() -> String:
	return _d.get("nomes", {}).get(atual, atual)


func _alvo() -> Dictionary:
	var e: Dictionary = _d.estados[atual if ativo else "limpo"]
	return {"nuvens": float(e.nuvens), "neblina": float(e.neblina), "chuva": float(e.chuva), "luz": float(e.luz), "vento": float(e.vento)}


## Força um estado (testes, roteiros de foto). `instantaneo` pula a transição.
func forcar(estado: String, instantaneo := false) -> void:
	atual = estado
	var dur: Array = _d.estados[estado].duracao_s
	restante = _rng.randf_range(dur[0], dur[1])
	if instantaneo:
		valores = _alvo().duplicate()
		molhado = 1.0 if valores.chuva > 0.0 else 0.0
		pocas = 0.85 if valores.chuva > 0.25 else 0.0


func nome_estacao() -> String:
	var es: Array = _d.get("estacoes", [])
	return es[estacao].nome if not es.is_empty() else ""


## 0..1: quão seco está (estação, menos o chão molhado): incêndio pega e espalha mais.
func secura() -> float:
	var es: Array = _d.get("estacoes", [])
	var s: float = es[estacao].secura if not es.is_empty() else 0.4
	return clampf(s * (1.0 - molhado) * (1.0 - valores.chuva), 0.0, 1.0)


## 0..1: quanto o rio corre agora (turbina de correnteza): vazao_rio da estação (cheia na primavera, seca no verão)
## mais um tanto com a chuva de agora.
func vazao_rio() -> float:
	var es: Array = _d.get("estacoes", [])
	var v: float = float(es[estacao].get("vazao_rio", 1.0)) if not es.is_empty() else 1.0
	return clampf(v + float(_d.get("chuva_vazao", 0.25)) * float(valores.get("chuva", 0.0)), 0.0, 1.0)


func eh_tufao() -> bool:
	return bool(_d.estados[atual].get("tufao", false)) and ativo


## Altura do sol: −1 meia-noite … +1,2 meio-dia (o dia é um pouco mais longo que a noite); o verão alonga o dia,
## o inverno encurta (estação "dia_extra", passando suave da anterior no primeiro quarto da estação).
func altura_sol() -> float:
	return -cos(hora * TAU) + 0.2 + dia_extra()


func dia_extra() -> float:
	var es: Array = _d.get("estacoes", [])
	if es.is_empty():
		return 0.0
	var antes := float(es[(estacao + es.size() - 1) % es.size()].get("dia_extra", 0.0))
	var agora := float(es[estacao].get("dia_extra", 0.0))
	return lerpf(antes, agora, smoothstep(0.0, 0.25, t_estacao / float(_d.get("estacao_s", 604800))))


## 0 = noite, 1 = dia claro; amanhecer e entardecer no meio. Rende o painel solar e acende o mundo.
func luz_dia() -> float:
	return smoothstep(-0.15, 0.35, altura_sol())


## "06:40" no relógio do planeta.
func relogio() -> String:
	var m := int(hora * 1440.0)
	return "%02d:%02d" % [m / 60, m % 60]


func periodo() -> String:
	var a := altura_sol()
	if a > 0.35:
		return "Dia"
	if a < -0.15:
		return "Noite"
	return "Amanhecer" if hora < 0.5 else "Entardecer"


func tick(dt: float) -> void:
	if ciclo:
		hora = fposmod(hora + dt / float(_d.get("dia_s", 720)), 1.0)
	var dur_e: float = _d.get("estacao_s", 604800)
	if tempo_real and not _d.get("estacoes", []).is_empty():
		var agora := Time.get_unix_time_from_system()
		estacao = int(floor(agora / dur_e)) % _d.estacoes.size()
		t_estacao = fmod(agora, dur_e)
	else:
		t_estacao += dt
	if t_estacao >= dur_e and not _d.get("estacoes", []).is_empty():
		t_estacao -= dur_e
		estacao = (estacao + 1) % _d.estacoes.size()
	restante -= dt
	if restante <= 0.0 and ativo:
		forcar(_sortear(_d.estados[atual].proximo))
	# aproxima os valores do alvo (transição suave)
	var k := clampf(dt / float(_d.get("transicao_s", 25)), 0.0, 1.0)
	var alvo := _alvo()
	for chave in alvo:
		valores[chave] = lerpf(valores[chave], alvo[chave], k * 3.0)
	# chão molha com a chuva e seca devagar
	if valores.chuva > 0.15:
		molhado = minf(1.0, molhado + dt * 0.05 * valores.chuva)
	else:
		molhado = maxf(0.0, molhado - dt * 0.008)
	# viço do capim: chuva enche; sem ela volta devagar ao normal da estação (o verão seco puxa para baixo)
	if valores.chuva > 0.15:
		vico = minf(1.0, vico + dt * 0.004 * valores.chuva)
	else:
		var es: Array = _d.get("estacoes", [])
		var normal := -float(es[estacao].get("secura", 0.4)) * 0.8 + 0.15 if not es.is_empty() else 0.0
		vico = move_toward(vico, normal, dt / (2.0 * float(_d.get("dia_s", 720))))
	# poças: só chuva de verdade enche; secam do raso para o fundo (o mais fundo some por último)
	if valores.chuva > 0.25:
		pocas = minf(1.0, pocas + dt * 0.012 * valores.chuva)
	else:
		pocas = maxf(0.0, pocas - dt * 0.0035)
	_vento(dt)
	deslocamento += direcao_vento * (1.5 + 6.0 * valores.vento) * dt
	if _d.estados[atual].get("raios", false) and ativo and _rng.randf() < dt * float(_d.estados[atual].get("raios_por_s", 0.07)):
		if eventos.size() < 4:
			eventos.append("raio")


const RUMOS := {"leste": 0.0, "nordeste": 45.0, "norte": 90.0, "noroeste": 135.0, "oeste": 180.0, "sudoeste": 225.0, "sul": 270.0, "sudeste": 315.0}


## Para onde sopra o rumo predominante da estação (vetor unitário da grade).
func rumo_estacao(e := -1) -> Vector2:
	var es: Array = _d.get("estacoes", [])
	if es.is_empty():
		return Vector2.LEFT
	var de: String = es[estacao if e < 0 else e].get("vento_de", "leste")
	return Vector2.from_angle(deg_to_rad(float(RUMOS.get(de, 0.0)) + 180.0))


## "de leste", "de sudoeste"... de onde vem o vento `v` (que sopra para v).
static func nome_rumo(v: Vector2) -> String:
	if v.length() < 1e-4:
		return "sem direção"
	var de := fposmod(rad_to_deg((-v).angle()), 360.0)
	var melhor := ""
	var dist := 999.0
	for n in RUMOS:
		var d := absf(angle_difference(deg_to_rad(de), deg_to_rad(RUMOS[n])))
		if d < dist:
			dist = d
			melhor = n
	return "de " + melhor


## Ritmo do balanço da vegetação para a força do vento: sobe pouco (30% da calmaria à ventania). Vento forte é mais
## amplitude e mais inclinação (shaders); subir a velocidade junto com a força parecia o jogo acelerado.
static func ritmo_vento(forca: float) -> float:
	return 1.0 + 0.3 * clampf(forca, 0.0, 1.0)


## Força do vento no ponto (grade), 0..~1,6: estado do clima + rajada passando (sem o fator do lugar: VentoLocal).
func vento_em(p: Vector2) -> float:
	var v: float = valores.vento
	if not rajada.is_empty():
		var x := p.dot(direcao_vento) - float(rajada.frente)
		v += float(rajada.amp) * exp(-x * x / pow(float(rajada.largura), 2.0))
	return v


## Rumo predominante de agora: o da estação, virando devagar a partir do da anterior no primeiro quarto dela.
func rumo_atual() -> Vector2:
	var es: Array = _d.get("estacoes", [])
	var rumo := rumo_estacao()
	if not es.is_empty():
		var antes := rumo_estacao((estacao + es.size() - 1) % es.size())
		var k := smoothstep(0.0, 0.25, t_estacao / float(_d.get("estacao_s", 604800)))
		rumo = Vector2.from_angle(lerp_angle(antes.angle(), rumo.angle(), k))
	return rumo


func _vento(dt: float) -> void:
	t_vento += dt
	var rumo := rumo_atual()
	var osc := deg_to_rad(40.0) * (0.6 * sin(t_vento / 97.0) + 0.4 * sin(t_vento / 41.0 + 1.3))
	direcao_vento = rumo.rotated(osc)
	# rajadas: uma frente por vez; nascem a barlavento do foco e passam por ele
	if rajada.is_empty():
		prox_rajada -= dt * (0.5 + valores.vento)
		if prox_rajada <= 0.0 and ativo:
			prox_rajada = _rng_vento.randf_range(12.0, 35.0)
			rajada = {"frente": foco.dot(direcao_vento) - 70.0, "amp": _rng_vento.randf_range(0.25, 0.6) * (0.4 + valores.vento) / 1.4,
					"largura": _rng_vento.randf_range(10.0, 18.0), "vel": 6.0 + 10.0 * valores.vento}
	else:
		rajada.frente = float(rajada.frente) + float(rajada.vel) * dt
		if float(rajada.frente) > foco.dot(direcao_vento) + 90.0:
			rajada = {}
	var k_m := clampf(dt / 600.0, 0.0, 1.0)
	vento_medio = vento_medio.lerp(direcao_vento * valores.vento, k_m)


## Próximo estado: pesos do estado × pesos da estação; tufão cresce com a poluição do ar (causa e efeito).
func _sortear(pesos: Dictionary) -> String:
	var es: Array = _d.get("estacoes", [])
	var mult: Dictionary = es[estacao].pesos if not es.is_empty() else {}
	var p := {}
	var total := 0.0
	for k in pesos:
		var w := float(pesos[k]) * float(mult.get(k, 1.0))
		if k == "tufao":
			w *= 1.0 + poluicao_total * float(_d.get("tufao_poluicao", 0.0))
		p[k] = w
		total += w
	var r := _rng.randf() * total
	for k in p:
		r -= float(p[k])
		if r <= 0.0:
			return k
	return pesos.keys()[0]


func estado() -> Dictionary:
	return {"atual": atual, "valores": valores, "molhado": molhado, "pocas": pocas, "deslocamento": deslocamento, "restante": restante,
			"vento": direcao_vento, "rng": _rng.state, "estacao": estacao, "t_estacao": t_estacao, "hora": hora,
			"t_vento": t_vento, "vento_medio": vento_medio, "vico": vico}


func restaurar(d: Dictionary) -> void:
	atual = d.atual
	valores = d.valores
	molhado = d.molhado
	pocas = d.get("pocas", 0.0)
	deslocamento = d.deslocamento
	restante = d.restante
	direcao_vento = d.vento
	_rng.state = d.rng
	estacao = d.get("estacao", 0)
	t_estacao = d.get("t_estacao", 0.0)
	hora = d.get("hora", 0.3)
	t_vento = d.get("t_vento", 0.0)
	vento_medio = d.get("vento_medio", Vector2.ZERO)
	vico = float(d.get("vico", 0.0))
