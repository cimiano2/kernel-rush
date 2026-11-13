class_name ProcCard
extends PanelContainer
## Cartão de um processo na fila de prontos ou na lista de bloqueados.
## Arrastável (drag & drop nativo do Godot) quando está na fila.

signal clicked(pid: int)

var pid := -1
var draggable := true
var selected := false

var _name: Label
var _tags: Label
var _burst: ProgressBar
var _wait: ProgressBar
var _info: Label
var _base_color := UIStyle.CYAN
var _starving := false
var _shake := 0.0


func setup(p: Sim.Proc, can_drag: bool) -> void:
	pid = p.pid
	draggable = can_drag
	_base_color = p.color
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_DRAG if can_drag else Control.CURSOR_ARROW
	custom_minimum_size = Vector2(0, 0)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	_name = UIStyle.label("", 14, UIStyle.TEXT)
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_name)
	_tags = UIStyle.label("", 11, UIStyle.MUTED)
	top.add_child(_tags)

	_burst = UIStyle.bar(p.color)
	v.add_child(_burst)
	if can_drag:
		_wait = UIStyle.bar(UIStyle.GREEN, 4)
		v.add_child(_wait)
	_info = UIStyle.label("", 11, UIStyle.MUTED)
	v.add_child(_info)
	_apply_style()


func refresh(p: Sim.Proc, now: float) -> void:
	_name.text = "%s  #%d" % [p.name, p.pid]
	var kind_txt := {"cpu": "CPU", "io": "E/S", "rt": "TEMPO REAL"}[p.kind] as String
	_tags.text = "%s  P%d" % [kind_txt, p.prio]
	_tags.add_theme_color_override("font_color",
		UIStyle.PINK if p.kind == "rt" else (UIStyle.VIOLET if p.kind == "io" else UIStyle.CYAN))
	_burst.value = 1.0 - clampf(p.remaining / p.burst, 0.0, 1.0)

	var parts: Array[String] = ["resta %.1fs" % maxf(p.remaining, 0.0)]
	if draggable:
		var w := now - p.wait_start
		parts.append("esperando %.1fs" % w)
		if p.kind != "rt":
			var ratio := clampf(w / p.patience, 0.0, 1.0)
			_wait.value = ratio
			UIStyle.set_bar_color(_wait, UIStyle.GREEN if ratio < 0.6 else (UIStyle.YELLOW if ratio < 1.0 else UIStyle.RED))
		else:
			_wait.value = 0.0
	else:
		parts.append("E/S %.1fs" % maxf(p.io_left, 0.0))
	if p.kind == "rt":
		parts.append("PRAZO %.1fs" % (p.deadline - now))
	_info.text = "  ·  ".join(parts)
	if p.kind == "rt" and p.deadline - now < 2.0:
		_info.add_theme_color_override("font_color", UIStyle.RED)

	if p.starving != _starving:
		_starving = p.starving
		_apply_style()


func set_selected(v: bool) -> void:
	if selected != v:
		selected = v
		_apply_style()


func _apply_style() -> void:
	var border := UIStyle.YELLOW if selected else (UIStyle.RED if _starving else UIStyle.LINE)
	add_theme_stylebox_override("panel", UIStyle.box(UIStyle.BG2, border, 2, 6, 6))
	queue_redraw()


func _draw() -> void:
	# pinta a faixa esquerda na cor do processo
	draw_rect(Rect2(Vector2.ZERO, Vector2(6, size.y)), _base_color)


func _process(delta: float) -> void:
	# processo com fome "treme" para chamar atenção
	if _starving:
		_shake += delta * 40.0
		position.x = sin(_shake) * 2.0
	elif position.x != 0.0:
		position.x = 0.0


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(pid)
	elif event is InputEventScreenTouch and event.pressed:
		clicked.emit(pid)


func _get_drag_data(_at: Vector2) -> Variant:
	if not draggable:
		return null
	var preview := PanelContainer.new()
	preview.add_theme_stylebox_override("panel", UIStyle.box(UIStyle.BG2, UIStyle.YELLOW, 2, 6, 8))
	preview.add_child(UIStyle.label(_name.text, 14, _base_color))
	preview.modulate.a = 0.9
	preview.rotation_degrees = -2.0
	set_drag_preview(preview)
	return {"pid": pid}
