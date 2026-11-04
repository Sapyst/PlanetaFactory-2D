class_name Catalogo2D
## Sprites da versão 2D (assets2d/, gerados de cada modelo do jogo): metadados, folhas e o retângulo de cada quadro.

const RAIZ := "res://assets2d/"
static var _indice: Dictionary = {}
static var _meta: Dictionary = {}
static var _tex: Dictionary = {}


static func tem(nome: String) -> bool:
	_carregar_indice()
	return _indice.has(nome)


static func _carregar_indice() -> void:
	if _indice.is_empty():
		_indice = JSON.parse_string(FileAccess.get_file_as_string(RAIZ + "indice.json"))


static func meta(nome: String) -> Dictionary:
	if not _meta.has(nome):
		_carregar_indice()
		if not _indice.has(nome):
			return {}
		var p: String = RAIZ + _indice[nome].pasta + "/" + nome + ".json"
		_meta[nome] = JSON.parse_string(FileAccess.get_file_as_string(p))
	return _meta[nome]


## Folha da variante ("" = base; braço: "atras", "esquerda", "direita"); sombra = a folha da sombra.
static func folha(nome: String, variante := "", sombra := false) -> Texture2D:
	var chave := "%s|%s|%s" % [nome, variante, sombra]
	if not _tex.has(chave):
		_carregar_indice()
		var suf := ("_" + variante if variante != "" else "") + ("_sombra" if sombra else "")
		var p: String = RAIZ + _indice[nome].pasta + "/" + nome + suf + ".png"
		_tex[chave] = load(p) if ResourceLoader.exists(p) else null
	return _tex[chave]


## Quadro q da linha (rotação ou direção) na folha: as folhas largas demais vêm em 2 fileiras por linha.
static func regiao(m: Dictionary, linha: int, q: int) -> Rect2:
	var w: float = m.quadro[0]
	var h: float = m.quadro[1]
	var col: int = int(m.get("colunas", m.quadros))
	var fil: int = int(m.get("fileiras_por_linha", 1))
	linha = posmod(linha, int(m.linhas))
	q = posmod(q, int(m.quadros))
	return Rect2((q % col) * w, (linha * fil + q / col) * h, w, h)


## Linha mais próxima de um ângulo (rad, giro em volta do eixo vertical, anti-horário visto de cima).
static func linha_do_angulo(m: Dictionary, ang: float) -> int:
	var n := int(m.linhas)
	return posmod(int(round(ang / (TAU / n))), n)
