class_name DesenhoObras
extends Node3D
## Fantasmas das obras encomendadas (patch RTS; lógica em Obras): o modelo da peça em holograma no lugar.
##  azul      na fila ou a caminho no drone;
##  âmbar     esperando recurso no núcleo;
##  vermelho  remoção encomendada (cópia do modelo por cima da estrutura, um pouco maior);
##  soldando  a faixa clara sobe pela peça conforme o drone trabalha; no fim a peça de verdade monta (Montagem).

const HOLO := preload("res://render/shaders/holograma.gdshader")
const AZUL := Color(0.16, 0.55, 1.0)
const AMBAR := Color(1.0, 0.52, 0.06)
const VERMELHO := Color(1.0, 0.06, 0.03)

var obras: Obras
var mapa: MapaOcupacao
var _nos: Dictionary = {}               ## id da obra → {no, mat, base, alto}
var _versao := -1
var _t := 0.0


func _process(delta: float) -> void:
	if obras == null:
		return
	_t += delta
	if obras.versao != _versao:
		_versao = obras.versao
		_sincronizar()
	for id in _nos:
		if not obras.obras.has(id):
			continue
		var o: Dictionary = obras.obras[id]
		var n: Dictionary = _nos[id]
		var m: ShaderMaterial = n.mat
		var cor := VERMELHO if o.acao == "remover" else (AMBAR if o.espera else AZUL)
		m.set_shader_parameter("cor", cor)
		var soldando: bool = float(o.prog) > 0.0
		m.set_shader_parameter("forca", (0.75 if soldando else 0.42) + 0.1 * sin(_t * 3.0 + float(id)))
		m.set_shader_parameter("faixa", lerpf(float(n.base), float(n.base) + float(n.alto), float(o.prog)) if soldando else -1000.0)


## Quantos fantasmas estão desenhados (testes).
func visiveis() -> int:
	return _nos.size()


func _sincronizar() -> void:
	for id in _nos.keys():
		if not obras.obras.has(id):
			(_nos[id].no as Node).queue_free()
			_nos.erase(id)
	for id in obras.obras:
		if not _nos.has(id):
			var n := _novo(obras.obras[id])
			if not n.is_empty():
				_nos[id] = n


func _novo(o: Dictionary) -> Dictionary:
	var it: Dictionary = o.item
	var e: Dictionary = it
	if o.acao == "remover":
		e = mapa.estruturas.get(int(it.get("id", -1)), {})
		if e.is_empty():
			return {}
	var nome := Construtor.modelo_de(e)
	if not Registro.modelos.has(nome):
		nome = String(e.nome)
	if not Registro.modelos.has(nome) or String(Registro.modelos[nome].get("modelo", "")) == "":
		return {}
	var cena: PackedScene = load(Registro.modelos[nome].modelo)
	if cena == null:
		return {}
	var raiz: Node3D = cena.instantiate()
	add_child(raiz)
	for ap in raiz.find_children("*", "AnimationPlayer", true, false):
		(ap as AnimationPlayer).stop()
	var mat := ShaderMaterial.new()
	mat.shader = HOLO
	for g in raiz.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).material_override = mat
		(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var area: Vector2i = mapa.registro.area(e.nome)
	var nivel := int(e.get("nivel", 0))
	var pos := Grade.ponto_mundo(Grade.centro_da_area(e.minimo, area, int(e.rot)), nivel * 0.5)
	raiz.position = pos
	raiz.rotation.y = Grade.angulo(int(e.rot)) + (PI if e.get("desce", false) else 0.0)
	if o.acao == "remover":
		raiz.scale = Vector3.ONE * 1.03
	var dims: Array = Registro.modelos[nome].get("dims", [1, 1, 1])
	return {"no": raiz, "mat": mat, "base": pos.y, "alto": float(dims[2])}
