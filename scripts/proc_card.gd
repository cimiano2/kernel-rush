class_name ProcCard
extends PanelContainer
## Cartão de um processo (cena: scenes/proc_card.tscn).
## Na fila de prontos é arrastável via drag & drop nativo do Godot.

signal clicked(pid: int)

var pid: int = -1
var draggable: bool = true
var selected: bool = false

var _base_color: Color = UIStyle.CYAN
var _starving: bool = false
var _shake: float = 0.0

@onready var _name_label: Label = %NameLabel
@onready var _tag_label: Label = %TagLabel
@onready var _burst_bar: ProgressBar = %BurstBar
@onready var _wait_bar: ProgressBar = %WaitBar
@onready var _info_label: Label = %InfoLabel


## Chamar depois de add_child (precisa dos nós @onready).
func setup(p: Sim.Proc, can_drag: bool) -> void:
	pid = p.pid
	draggable = can_drag
	_base_color = p.color
	mouse_default_cursor_shape = Control.CURSOR_DRAG if can_drag else Control.CURSOR_ARROW
	_wait_bar.visible = can_drag
	UIStyle.set_bar_color(_burst_bar, p.color)
	_tag_label.add_theme_color_override("font_color", UIStyle.KIND_COLORS[p.kind])
	_update_border()


func refresh(p: Sim.Proc, now: float) -> void:
	_name_label.text = "%s  #%d" % [p.name, p.pid]
	_tag_label.text = "%s  P%d" % [UIStyle.KIND_NAMES[p.kind], p.prio]
	_burst_bar.value = 1.0 - clampf(p.remaining / p.burst, 0.0, 1.0)

	var parts: Array[String] = ["resta %.1fs" % maxf(p.remaining, 0.0)]
	if draggable:
		var waited := now - p.wait_start
		parts.append("esperando %.1fs" % waited)
		if p.kind == "rt":
			_wait_bar.value = 0.0
		else:
			var ratio := clampf(waited / p.patience, 0.0, 1.0)
			_wait_bar.value = ratio
			UIStyle.set_bar_color(_wait_bar,
				UIStyle.GREEN if ratio < 0.6 else (UIStyle.YELLOW if ratio < 1.0 else UIStyle.RED))
	else:
		parts.append("E/S %.1fs" % maxf(p.io_left, 0.0))
	if p.kind == "rt":
		parts.append("PRAZO %.1fs" % (p.deadline - now))
		if p.deadline - now < 2.0:
			_info_label.add_theme_color_override("font_color", UIStyle.RED)
	_info_label.text = "  ·  ".join(parts)

	if p.starving != _starving:
		_starving = p.starving
		_update_border()


func set_selected(value: bool) -> void:
	if selected != value:
		selected = value
		_update_border()


func _update_border() -> void:
	var color := UIStyle.YELLOW if selected else (UIStyle.RED if _starving else UIStyle.LINE)
	UIStyle.set_border(self, "panel", color)
	queue_redraw()


func _draw() -> void:
	# faixa esquerda na cor do processo
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


func _get_drag_data(_at_position: Vector2) -> Variant:
	if not draggable:
		return null
	var preview := duplicate(0) as Control   # cópia visual, sem script nem sinais
	preview.size = size
	preview.modulate.a = 0.85
	preview.rotation_degrees = -2.0
	set_drag_preview(preview)
	return {"pid": pid}
