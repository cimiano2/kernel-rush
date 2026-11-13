class_name CoreSlot
extends PanelContainer
## Um núcleo da CPU. Aceita cartões arrastados e cliques.

signal clicked(index: int)
signal dropped(pid: int, index: int)

var index := 0
var _title: Label
var _state: Label
var _name: Label
var _bar: ProgressBar
var _detail: Label
var _hover := false
var _blink := 0.0


func setup(i: int) -> void:
	index = i
	custom_minimum_size = Vector2(170, 150)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	_title = UIStyle.label("CPU %d" % (i + 1), 12, UIStyle.MUTED)
	v.add_child(_title)
	_name = UIStyle.label("", 16, UIStyle.TEXT)
	v.add_child(_name)
	_bar = UIStyle.bar(UIStyle.CYAN, 10)
	v.add_child(_bar)
	_state = UIStyle.label("", 12, UIStyle.MUTED)
	_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_state)
	_detail = UIStyle.label("", 11, UIStyle.MUTED)
	v.add_child(_detail)

	mouse_exited.connect(func(): _hover = false)


func refresh(core: Dictionary, unlocked: bool, now: float, delta_vis: float) -> void:
	var p: Sim.Proc = core.proc
	if not unlocked:
		modulate.a = 0.35
		_name.text = "BLOQUEADO"
		_name.add_theme_color_override("font_color", UIStyle.MUTED)
		_state.text = "Libera em nível mais alto"
		_bar.visible = false
		_detail.text = ""
		add_theme_stylebox_override("panel", UIStyle.box(Color("0d1229"), UIStyle.LINE, 2, -1, 10))
		return
	modulate.a = 1.0
	var border := UIStyle.YELLOW if _hover else UIStyle.LINE
	if p == null:
		_name.text = "ocioso"
		_name.add_theme_color_override("font_color", UIStyle.MUTED)
		_state.text = "Solte um processo aqui"
		_bar.visible = false
		_detail.text = ""
		add_theme_stylebox_override("panel", UIStyle.box(Color("0d1229"), border, 2, -1, 10))
		return

	_name.text = "%s #%d" % [p.name, p.pid]
	_name.add_theme_color_override("font_color", p.color)
	_bar.visible = true
	UIStyle.set_bar_color(_bar, p.color)
	_bar.value = 1.0 - clampf(p.remaining / p.burst, 0.0, 1.0)
	if core.switching > 0.0:
		_blink += delta_vis
		_state.text = "TROCA DE CONTEXTO..."
		_state.add_theme_color_override("font_color", UIStyle.YELLOW)
		_state.modulate.a = 0.4 + 0.6 * absf(sin(_blink * 10.0))
	else:
		_state.modulate.a = 1.0
		_state.text = "executando"
		_state.add_theme_color_override("font_color", UIStyle.GREEN)
	var d := "resta %.1fs · fatia %.1fs" % [maxf(p.remaining, 0.0), core.slice]
	if p.kind == "io":
		d += "\nE/S em %.1fs" % maxf(p.until_io, 0.0)
	if p.kind == "rt":
		d += "\nPRAZO %.1fs" % (p.deadline - now)
	_detail.text = d
	add_theme_stylebox_override("panel", UIStyle.box(Color("101634"), UIStyle.YELLOW if _hover else p.color, 3, -1, 10))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(index)
	elif event is InputEventScreenTouch and event.pressed:
		clicked.emit(index)


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	var ok: bool = data is Dictionary and data.has("pid")
	_hover = ok
	return ok


func _drop_data(_at: Vector2, data: Variant) -> void:
	_hover = false
	dropped.emit(int(data.pid), index)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_hover = false
