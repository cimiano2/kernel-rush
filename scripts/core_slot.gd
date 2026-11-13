class_name CoreSlot
extends PanelContainer
## Um núcleo da CPU (cena: scenes/core_slot.tscn). Aceita cartões arrastados e cliques.

signal clicked(index: int)
signal dropped(pid: int, index: int)

## Índice do núcleo (0..3). Definido no inspetor de cada instância em main.tscn.
@export var index: int = 0

var _hover: bool = false
var _blink: float = 0.0

@onready var _title_label: Label = %TitleLabel
@onready var _proc_label: Label = %ProcLabel
@onready var _bar: ProgressBar = %ProgressBar
@onready var _state_label: Label = %StateLabel
@onready var _detail_label: Label = %DetailLabel


func _ready() -> void:
	_title_label.text = "CPU %d" % (index + 1)
	mouse_exited.connect(func() -> void: _hover = false)


func refresh(core: Dictionary, unlocked: bool, now: float, delta: float) -> void:
	var p: Sim.Proc = core.proc
	_state_label.modulate.a = 1.0
	if not unlocked:
		modulate.a = 0.35
		_show_empty("BLOQUEADO", "Libera em nível mais alto", UIStyle.LINE, 2)
		return
	modulate.a = 1.0
	if p == null:
		_show_empty("ocioso", "Solte um processo aqui", UIStyle.YELLOW if _hover else UIStyle.LINE, 2)
		return

	_proc_label.text = "%s #%d" % [p.name, p.pid]
	_proc_label.add_theme_color_override("font_color", p.color)
	_bar.visible = true
	UIStyle.set_bar_color(_bar, p.color)
	_bar.value = 1.0 - clampf(p.remaining / p.burst, 0.0, 1.0)
	if core.switching > 0.0:
		_blink += delta
		_state_label.text = "TROCA DE CONTEXTO..."
		_state_label.add_theme_color_override("font_color", UIStyle.YELLOW)
		_state_label.modulate.a = 0.4 + 0.6 * absf(sin(_blink * 10.0))
	else:
		_state_label.text = "executando"
		_state_label.add_theme_color_override("font_color", UIStyle.GREEN)
	var detail := "resta %.1fs · fatia %.1fs" % [maxf(p.remaining, 0.0), core.slice]
	if p.kind == "io":
		detail += "\nE/S em %.1fs" % maxf(p.until_io, 0.0)
	elif p.kind == "rt":
		detail += "\nPRAZO %.1fs" % (p.deadline - now)
	_detail_label.text = detail
	UIStyle.set_border(self, "panel", UIStyle.YELLOW if _hover else p.color, 3)


func _show_empty(title: String, state: String, border: Color, width: int) -> void:
	_proc_label.text = title
	_proc_label.add_theme_color_override("font_color", UIStyle.MUTED)
	_state_label.text = state
	_state_label.add_theme_color_override("font_color", UIStyle.MUTED)
	_bar.visible = false
	_detail_label.text = ""
	UIStyle.set_border(self, "panel", border, width)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(index)
	elif event is InputEventScreenTouch and event.pressed:
		clicked.emit(index)


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var ok: bool = data is Dictionary and data.has("pid")
	_hover = ok
	return ok


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	_hover = false
	dropped.emit(int(data.pid), index)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_hover = false
