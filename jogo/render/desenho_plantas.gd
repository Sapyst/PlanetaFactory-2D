class_name DesenhoPlantas
extends Node3D
## Mudas e árvores plantadas pelo viveiro (AmbienteVivo.plantas): um MultiMesh por modelo de vegetação, cada
## planta no tamanho do seu crescimento (muda pequena → árvore inteira), giro e deslocamento próprios por tile.
## Refeito só quando `versao_plantas` muda (nasce, cai ou cresce um degrau). Muda com espécie (viveiro 2, semeador de
## bioma: AmbienteVivo.especies) usa um dos 6 modelos daquela espécie ("arv_salgueiro_3"…); as outras, a lista padrão.

var ambiente: AmbienteVivo
var _versao := -1
var _mm: Dictionary = {}          ## modelo → MultiMeshInstance3D


func _process(_d: float) -> void:
	if ambiente == null or ambiente.versao_plantas == _versao:
		return
	_versao = ambiente.versao_plantas
	_refazer()


## Modelo da planta do tile (o mesmo no 3D e no 2D): a espécie dela, senão um da lista padrão.
static func modelo_de(amb: AmbienteVivo, t: Vector2i) -> String:
	var modelos: Array = Registro.ambiente.get("plantas", {}).get("modelos", ["arvore_campina_a"])
	var modelo: String = modelos[int(Distribuicao.h(t.x, t.y, 901) * modelos.size()) % modelos.size()]
	if amb.especies.has(t):
		var esp := "%s_%d" % [amb.especies[t], 1 + int(Distribuicao.h(t.x, t.y, 906) * 6.0) % 6]
		if Registro.modelos.has(esp):
			modelo = esp
	return modelo


## Onde fica a planta do tile (grade): um pouco fora do centro, por tile.
static func pos_de(t: Vector2i) -> Vector2:
	return Vector2(t) + Vector2(0.5, 0.5) + Vector2(Distribuicao.h(t.x, t.y, 902) - 0.5, Distribuicao.h(t.x, t.y, 903) - 0.5) * 0.4


## Tamanho pelo crescimento: muda (15%) → árvore inteira, com uma variação por tile.
static func escala_de(t: Vector2i, cresc: float) -> float:
	return (0.15 + 0.85 * smoothstep(0.0, 1.0, cresc)) * (0.85 + 0.3 * Distribuicao.h(t.x, t.y, 904))


func _refazer() -> void:
	var modelos: Array = Registro.ambiente.get("plantas", {}).get("modelos", ["arvore_campina_a"])
	var lista := {}
	for m in modelos:
		lista[m] = []
	var g := ambiente.gerador
	for t: Vector2i in ambiente.plantas:
		var cresc: float = ambiente.plantas[t]
		var modelo := modelo_de(ambiente, t)
		if not lista.has(modelo):
			lista[modelo] = []
		var p := pos_de(t)
		var esc := escala_de(t, cresc)
		var b := Basis(Vector3.UP, Distribuicao.h(t.x, t.y, 905) * TAU).scaled(Vector3(esc, esc, esc))
		(lista[modelo] as Array).append(Transform3D(b, Grade.ponto_mundo(p, g.micro_em(p - Vector2(0.5, 0.5)))))
	for modelo in lista:
		var xs: Array = lista[modelo]
		var mmi: MultiMeshInstance3D = _mm.get(modelo)
		if mmi == null:
			if xs.is_empty():
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = DesenhoChunk.malha(modelo, 1.0)
			mmi = MultiMeshInstance3D.new()
			mmi.multimesh = mm
			add_child(mmi)
			_mm[modelo] = mmi
		mmi.multimesh.instance_count = xs.size()
		for i in xs.size():
			mmi.multimesh.set_instance_transform(i, xs[i])
