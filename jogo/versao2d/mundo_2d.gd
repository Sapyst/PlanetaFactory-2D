extends Node
## Versão 2D: o MESMO jogo (simulação, interface, construção, clima, colônia) com o desenho 3D desligado e um
## espelho 2D por cima. A câmera do jogo vira ortográfica a 35° (a projeção dos sprites), então clique e construção
## continuam pelo raio da câmera e acertam o tile desenhado.

var mundo: Node3D
var desenho: Desenho2D


func _ready() -> void:
	mundo = (load("res://cenas/mundo_demo.tscn") as PackedScene).instantiate()
	var cam := mundo.get_node("Camera3D")
	cam.set_script(load("res://versao2d/camera_2d.gd"))
	desenho = Desenho2D.new()
	desenho.name = "Desenho2D"
	add_child(desenho)
	add_child(mundo)
	desenho.mundo = mundo
	desenho.camera = mundo.get_node("Camera3D")
	mundo.eventos_desenho.connect(desenho.efeitos_de)
	get_viewport().disable_3d = true
