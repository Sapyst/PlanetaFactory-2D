extends SceneTree
## Exporta um retângulo do mundo gerado (mesmo gerador do jogo) para JSON: terreno, bioma, jazida e obstáculos.
## godot --headless --path <jogo> -s <este arquivo> -- <semente> <x0> <y0> <largura> <altura> <saida.json>

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var sem := int(a[0]); var x0 := int(a[1]); var y0 := int(a[2]); var w := int(a[3]); var h := int(a[4])
	var g := GeradorMundo.new(sem)
	var cx := Distribuicao.contexto()
	var ter := []; var bio := []; var jaz := {}; var obs := []
	for j in h:
		for i in w:
			var t := Vector2i(x0 + i, y0 + j)
			ter.append(g.distribuicao._ter(t, cx))
			bio.append(g.distribuicao._bio(t, cx))
			var jz: Dictionary = g.distribuicao.jazida(t, cx)
			if not jz.is_empty():
				jaz["%d,%d" % [t.x, t.y]] = jz.get("recurso", jz.get("nome", "?"))
			var ob: Dictionary = g.distribuicao.obstaculo(t, cx)
			if not ob.is_empty() and ob.ancora == t:
				obs.append({"nome": ob.nome, "x": t.x, "y": t.y, "rot": int(ob.get("rot", 0)), "area": ob.get("area", [1, 1])})
	var f := FileAccess.open(a[5], FileAccess.WRITE)
	f.store_string(JSON.stringify({"x0": x0, "y0": y0, "w": w, "h": h, "terreno": ter, "bioma": bio, "jazidas": jaz,
		"obstaculos": obs, "terrenos": GeradorMundo.Terreno.keys()}))
	f.close()
	print("DESPEJO ok ", obs.size(), " obstáculos ", jaz.size(), " jazidas")
	quit()
