class_name UIStyle
extends RefCounted
## Paleta do jogo e helpers para recolorir estilos do tema em tempo de execução.
## O visual base fica em resources/theme.tres (editável no editor do Godot).

const TEXT := Color("d8e1ff")
const MUTED := Color("8592c4")
const LINE := Color("2a3566")
const CYAN := Color("34e7e4")
const PINK := Color("ff4fa3")
const YELLOW := Color("ffd23f")
const GREEN := Color("5cff8a")
const RED := Color("ff5a5a")
const VIOLET := Color("a17bff")

const KIND_COLORS := {"cpu": CYAN, "io": VIOLET, "rt": PINK}
const KIND_NAMES := {"cpu": "CPU", "io": "E/S", "rt": "TEMPO REAL"}


## Duplica o StyleBoxFlat vindo do tema e troca a cor da borda (e opcionalmente a largura).
static func set_border(ctrl: Control, style_name: String, color: Color, width: int = -1) -> void:
	var base := ctrl.get_theme_stylebox(style_name) as StyleBoxFlat
	if base == null or (base.border_color == color and (width < 0 or base.border_width_top == width)):
		return
	var s := base.duplicate() as StyleBoxFlat
	s.border_color = color
	if width >= 0:
		var left := s.border_width_left
		s.set_border_width_all(width)
		s.border_width_left = maxi(left, width)
	ctrl.add_theme_stylebox_override(style_name, s)


## Troca a cor de preenchimento de uma ProgressBar.
static func set_bar_color(bar: ProgressBar, color: Color) -> void:
	var base := bar.get_theme_stylebox("fill") as StyleBoxFlat
	if base == null or base.bg_color == color:
		return
	var s := base.duplicate() as StyleBoxFlat
	s.bg_color = color
	bar.add_theme_stylebox_override("fill", s)
