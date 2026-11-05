class_name Grama
extends MultiMeshInstance3D
## Campo de grama em massa: um tufo (5 folhas finas, ~20 triângulos) instanciado milhares de vezes numa MultiMesh
## — uma chamada de desenho para o campo todo; o balanço do vento é calculado no shader (render/shaders/grama.gdshader).
## Cada tufo pega a altura do relevo, um giro, um tamanho e um tom próprios.

@export var lado := 24.0           ## tamanho do bloco (m)
@export var densidade := 90.0      ## tufos por m²


static func tufo() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for f in 5:
		var a := f * TAU / 5.0 + rng.randf_range(-0.3, 0.3)
		var base := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, 0.05)
		var lado_v := Vector3(-sin(a), 0, cos(a)) * 0.022
		var incl := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.05, 0.14)
		var h := rng.randf_range(0.20, 0.34)
		var seg := 3
		var pts: Array = []
		for k in seg + 1:
			var t := float(k) / seg
			var c := base + incl * t * t + Vector3(0, h * t, 0)
			var w := lado_v * (1.0 - t * 0.92)
			pts.append([c - w, c + w, t])
		for k in seg:
			var p0: Array = pts[k]
			var p1: Array = pts[k + 1]
			var n: Vector3 = ((p0[1] - p0[0]) as Vector3).cross(p1[0] - p0[0]).normalized()
			# UV.x = lado da folha (−1/+1): o shader alarga a ponta dos tufos com flor (fase 2 do patch fauna)
			for v in [[p0[0], p0[2], -1.0], [p0[1], p0[2], 1.0], [p1[0], p1[2], -1.0], [p0[1], p0[2], 1.0], [p1[1], p1[2], 1.0], [p1[0], p1[2], -1.0]]:
				st.set_normal(n)
				st.set_uv(Vector2(v[2], v[1]))
				st.add_vertex(v[0])
	return st.commit()


func _ready() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = tufo()
	var n := int(lado * lado * densidade)
	mm.instance_count = n
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var origem := global_position
	for i in n:
		var p := Vector3(rng.randf_range(-lado / 2, lado / 2), 0, rng.randf_range(-lado / 2, lado / 2))
		var g := Vector2(origem.x + p.x, -(origem.z + p.z))
		p.y = Grade.altura_em(g) - origem.y
		var s := rng.randf_range(0.7, 1.35)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.85, 1.25), s))
		mm.set_instance_transform(i, Transform3D(b, p))
		var tom := rng.randf_range(0.82, 1.12)
		mm.set_instance_color(i, Color(tom * rng.randf_range(0.95, 1.05), tom, tom * rng.randf_range(0.9, 1.0)))
	multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://render/shaders/grama.gdshader")
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	print("GRAMA %d tufos (%d folhas, %d triângulos)" % [n, n * 5, n * 5 * 6])
