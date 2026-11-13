class_name UIStyle
extends RefCounted
## Paleta e helpers visuais (identidade própria: terminal neon retrô).

const BG := Color("0b0f1e")
const BG2 := Color("121833")
const PANEL := Color("151c3a")
const LINE := Color("2a3566")
const TEXT := Color("d8e1ff")
const MUTED := Color("8592c4")
const CYAN := Color("34e7e4")
const PINK := Color("ff4fa3")
const YELLOW := Color("ffd23f")
const GREEN := Color("5cff8a")
const RED := Color("ff5a5a")
const VIOLET := Color("a17bff")

static var _mono: SystemFont


static func mono() -> SystemFont:
	if _mono == null:
		_mono = SystemFont.new()
		_mono.font_names = PackedStringArray(["JetBrains Mono", "DejaVu Sans Mono", "Consolas", "Menlo", "monospace"])
		_mono.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return _mono


static func box(bg: Color, border: Color, width: int = 2, left: int = -1, pad: int = 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	if left >= 0:
		s.border_width_left = left
	s.set_content_margin_all(pad)
	return s


static func label(text: String, size: int = 14, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", mono())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func bar(fill: Color, height: int = 6) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(0, height)
	b.max_value = 1.0
	b.step = 0.0
	b.add_theme_stylebox_override("background", box(Color("0a0d1c"), Color("0a0d1c"), 0, -1, 0))
	b.add_theme_stylebox_override("fill", box(fill, fill, 0, -1, 0))
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


static func set_bar_color(b: ProgressBar, c: Color) -> void:
	var s: StyleBoxFlat = b.get_theme_stylebox("fill")
	if s.bg_color != c:
		b.add_theme_stylebox_override("fill", box(c, c, 0, -1, 0))
