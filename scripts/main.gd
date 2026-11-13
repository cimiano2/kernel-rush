extends Control
## Cena principal (scenes/main.tscn). A árvore de nós vive na cena; este script
## só conecta a interface à simulação (Sim) e cuida do loop do jogo.

const ProcCardScene: PackedScene = preload("res://scenes/proc_card.tscn")
const SAVE_PATH := "user://kernel_rush.cfg"
const AUTO_MODES: Array[String] = ["off", "fcfs", "sjf", "rr", "prio", "edf"]

## Parâmetros de balanceamento (resources/sim_config.tres).
@export var config: SimConfig

var sim: Sim
var paused: bool = true
var selected_pid: int = -1
var best_score: int = 0

var _accum: float = 0.0
var _cards: Dictionary = {}          # pid -> ProcCard (fila de prontos)
var _blocked_cards: Dictionary = {}  # pid -> ProcCard (bloqueados)
var _core_slots: Array[CoreSlot] = []
var _glitch_boost: float = 0.0       # pico de glitch em eventos ruins

@onready var _time_value: Label = %TimeStatValue
@onready var _level_value: Label = %LevelStatValue
@onready var _score_value: Label = %ScoreStatValue
@onready var _done_value: Label = %DoneStatValue
@onready var _wait_value: Label = %WaitStatValue
@onready var _ctx_value: Label = %CtxStatValue
@onready var _satisfaction_bar: ProgressBar = %SatisfactionBar
@onready var _queue_count: Label = %QueueCount
@onready var _ready_list: VBoxContainer = %ReadyList
@onready var _blocked_list: VBoxContainer = %BlockedList
@onready var _core_grid: GridContainer = %CoreGrid
@onready var _kernel_log: RichTextLabel = %KernelLog
@onready var _pause_button: Button = %PauseButton
@onready var _autopilot_option: OptionButton = %AutopilotOption
@onready var _restart_button: Button = %RestartButton
@onready var _crt_toggle: CheckButton = %CrtToggle
@onready var _fx_layer: Control = %FxLayer
@onready var _overlay: CanvasLayer = %Overlay
@onready var _overlay_text: RichTextLabel = %OverlayText
@onready var _overlay_button: Button = %OverlayButton
@onready var _crt: ColorRect = %CRT


func _ready() -> void:
	for child in _core_grid.get_children():
		var slot := child as CoreSlot
		slot.clicked.connect(_on_core_clicked)
		slot.dropped.connect(_on_core_dropped)
		_core_slots.append(slot)
	_pause_button.pressed.connect(_toggle_pause)
	_restart_button.pressed.connect(_on_restart_pressed)
	_overlay_button.pressed.connect(_on_overlay_button)
	_autopilot_option.item_selected.connect(func(i: int) -> void: sim.autopilot = AUTO_MODES[i])
	_crt_toggle.toggled.connect(func(on: bool) -> void: _crt.visible = on)
	# CheckButton ligado não deve parecer "pressionado/focado"
	for style in ["pressed", "hover_pressed"]:
		_crt_toggle.add_theme_stylebox_override(style, _crt_toggle.get_theme_stylebox("normal"))
	_load_best()
	_new_game()
	_show_intro()


# ================================================================ loop

func _new_game() -> void:
	sim = Sim.new(-1, config)
	sim.logged.connect(_on_log)
	sim.popped.connect(_on_pop)
	sim.autopilot = AUTO_MODES[_autopilot_option.selected]
	for card in _cards.values() + _blocked_cards.values():
		card.queue_free()
	_cards.clear()
	_blocked_cards.clear()
	selected_pid = -1
	_accum = 0.0
	_kernel_log.clear()
	_on_log("Sistema iniciado. Escalone os processos!", "info")
	_refresh(0.0)


func _process(delta: float) -> void:
	if not paused and not sim.game_over:
		_accum += delta
		while _accum >= sim.cfg.tick:
			_accum -= sim.cfg.tick
			sim.tick()
			if sim.game_over:
				_show_game_over()
				break
	_refresh(delta)
	_update_crt(delta)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_SPACE, KEY_P:
			if _overlay.visible:
				_on_overlay_button()
			else:
				_toggle_pause()
		KEY_ENTER, KEY_KP_ENTER:
			if _overlay.visible:
				_on_overlay_button()
		KEY_1, KEY_2, KEY_3, KEY_4:
			_on_core_clicked(key.keycode - KEY_1)
		KEY_ESCAPE:
			_select(-1)
		KEY_C:
			_crt_toggle.button_pressed = not _crt_toggle.button_pressed
		_:
			return
	get_viewport().set_input_as_handled()


# ================================================================ ações

func _select(pid: int) -> void:
	selected_pid = pid if pid != selected_pid else -1
	for k in _cards:
		_cards[k].set_selected(k == selected_pid)


func _on_core_clicked(index: int) -> void:
	if paused or sim.game_over or index >= sim.unlocked_cores():
		return
	if selected_pid >= 0:
		if sim.assign(selected_pid, index):
			selected_pid = -1
	elif sim.cores[index].proc != null:
		sim.preempt(index)


func _on_core_dropped(pid: int, index: int) -> void:
	if paused or sim.game_over:
		return
	if sim.assign(pid, index) and pid == selected_pid:
		selected_pid = -1


func _toggle_pause() -> void:
	if sim.game_over:
		return
	paused = not paused
	_pause_button.text = "▶ Continuar" if paused else "⏸ Pausar"


func _on_restart_pressed() -> void:
	_new_game()
	_overlay.visible = false
	paused = false
	_pause_button.text = "⏸ Pausar"


# ================================================================ render

func _refresh(delta: float) -> void:
	_time_value.text = "%.1fs" % sim.time
	_level_value.text = str(sim.level)
	_score_value.text = str(sim.score)
	_done_value.text = str(sim.completed)
	_wait_value.text = "%.1fs" % sim.avg_wait()
	_ctx_value.text = str(sim.ctx_switches)
	_satisfaction_bar.value = sim.satisfaction / 100.0
	UIStyle.set_bar_color(_satisfaction_bar,
		UIStyle.GREEN if sim.satisfaction > 60 else (UIStyle.YELLOW if sim.satisfaction > 30 else UIStyle.RED))
	var overflow := sim.ready.size() > sim.cfg.max_queue
	_queue_count.text = "%d/%d" % [sim.ready.size(), sim.cfg.max_queue]
	_queue_count.add_theme_color_override("font_color", UIStyle.RED if overflow else UIStyle.MUTED)

	_sync_cards(sim.ready, _cards, _ready_list, true)
	_sync_cards(sim.blocked, _blocked_cards, _blocked_list, false)
	if selected_pid >= 0 and not _cards.has(selected_pid):
		selected_pid = -1

	var unlocked := sim.unlocked_cores()
	for i in _core_slots.size():
		_core_slots[i].refresh(sim.cores[i], i < unlocked, sim.time, delta)


## Mantém os cartões em sincronia com a lista do simulador sem recriar tudo
## a cada quadro (assim drag & drop e cliques não quebram).
func _sync_cards(list: Array, map: Dictionary, box: VBoxContainer, draggable: bool) -> void:
	var alive := {}
	for i in list.size():
		var p: Sim.Proc = list[i]
		alive[p.pid] = true
		var card: ProcCard = map.get(p.pid)
		if card == null:
			card = ProcCardScene.instantiate() as ProcCard
			box.add_child(card)
			card.setup(p, draggable)
			if draggable:
				card.clicked.connect(_select)
			map[p.pid] = card
		if card.get_index() != i:
			box.move_child(card, i)
		card.refresh(p, sim.time)
		if draggable:
			card.set_selected(p.pid == selected_pid)
	for pid in map.keys():
		if not alive.has(pid):
			map[pid].queue_free()
			map.erase(pid)


## O glitch do shader CRT cresce conforme a satisfação cai e dá picos em eventos ruins.
func _update_crt(delta: float) -> void:
	_glitch_boost = maxf(0.0, _glitch_boost - delta * 2.0)
	var stress := clampf((40.0 - sim.satisfaction) / 40.0, 0.0, 1.0) * 0.5
	var target := maxf(0.15 if sim.game_over else stress, _glitch_boost)
	var mat := _crt.material as ShaderMaterial
	mat.set_shader_parameter("glitch", target)


func _on_log(text: String, kind: String) -> void:
	var color: Color = {"ok": UIStyle.GREEN, "bad": UIStyle.RED, "info": UIStyle.CYAN}.get(kind, UIStyle.MUTED)
	if kind == "bad":
		_glitch_boost = 0.6
	_kernel_log.push_color(UIStyle.MUTED)
	_kernel_log.add_text("%5.1fs  " % (sim.time if sim else 0.0))
	_kernel_log.pop()
	_kernel_log.push_color(color)
	_kernel_log.add_text(text + "\n")
	_kernel_log.pop()
	while _kernel_log.get_paragraph_count() > 40:
		_kernel_log.remove_paragraph(0)


func _on_pop(text: String, color: Color, where: String, index: int) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 22 if where == "center" else 16)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	_fx_layer.add_child(label)
	var origin: Vector2
	if where == "core" and index < _core_slots.size():
		origin = _core_slots[index].get_global_rect().get_center() - Vector2(20, 10)
	else:
		origin = get_viewport_rect().size / 2.0 - Vector2(80, 0)
	label.position = origin
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", origin.y - 50.0, 1.1).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tween.chain().tween_callback(label.queue_free)


# ================================================================ overlays

func _show_intro() -> void:
	paused = true
	_overlay_text.text = """[color=#34e7e4][font_size=26]KERNEL // RUSH[/font_size][/color]

Você é o [b]escalonador de CPU[/b] de um sistema operacional. Processos chegam à [b]fila de prontos[/b]: decida quem roda em cada núcleo.

[color=#ffd23f]Como jogar[/color]
• Clique num processo e depois num núcleo, ou [b]arraste[/b] (atalhos [b]1–4[/b]).
• Clique num núcleo ocupado para fazer [b]preempção[/b]: o processo volta ao fim da fila.
• Toda troca custa [b]%.1fs de troca de contexto[/b], então não troque à toa!

[color=#ffd23f]Tipos de processo[/color]
• [color=#34e7e4]CPU[/color]: pesado, roda até terminar.
• [color=#a17bff]E/S[/color] (nível %d+): roda um pouco e bloqueia esperando o disco/rede, depois volta.
• [color=#ff4fa3]TEMPO REAL[/color] (nível %d+): tem [b]prazo[/b]; perder custa caro.

[color=#ff5a5a]Cuidado[/color]: processos esperando demais passam [b]fome[/b] (starvation) e a satisfação do usuário cai. Se chegar a zero: [b]KERNEL PANIC[/b].

[color=#8592c4]Dica: use o piloto automático para comparar FCFS, SJF, Round Robin, Prioridade e EDF com a sua estratégia.[/color]""" % [sim.cfg.ctx_switch, sim.cfg.io_from_level, sim.cfg.rt_from_level]
	_overlay_button.text = "INICIAR  [Enter]"
	_overlay.visible = true


func _show_game_over() -> void:
	paused = true
	_glitch_boost = 1.2   # pico de glitch que se acalma em ~0,5s
	var assisted := sim.used_autopilot
	var record := ""
	if not assisted and sim.score > best_score:
		best_score = sim.score
		_save_best()
		record = "\n[color=#ffd23f]★ NOVO RECORDE! ★[/color]\n"
	var avg_turnaround := sim.turnaround_total / sim.completed if sim.completed > 0 else 0.0
	_overlay_text.text = """[color=#ff5a5a][font_size=26]KERNEL PANIC[/font_size][/color]
O usuário perdeu a paciência com o sistema.
%s
[table=2]
[cell]Pontuação[/cell][cell][color=#ffd23f]%d[/color][/cell]
[cell]Recorde (sem piloto automático)   [/cell][cell][color=#ffd23f]%d[/color][/cell]
[cell]Tempo sobrevivido[/cell][cell]%.1fs[/cell]
[cell]Nível alcançado[/cell][cell]%d[/cell]
[cell]Processos concluídos[/cell][cell]%d[/cell]
[cell]Prazos perdidos[/cell][cell]%d[/cell]
[cell]Tempo médio de espera[/cell][cell]%.2fs[/cell]
[cell]Turnaround médio[/cell][cell]%.2fs[/cell]
[cell]Trocas de contexto[/cell][cell]%d[/cell]
[/table]
%s""" % [record, sim.score, best_score, sim.time, sim.level, sim.completed, sim.missed,
		sim.avg_wait(), avg_turnaround, sim.ctx_switches,
		"[color=#8592c4](partida com piloto automático: não conta para recorde)[/color]" if assisted else ""]
	_overlay_button.text = "JOGAR DE NOVO  [Enter]"
	_overlay.visible = true


func _on_overlay_button() -> void:
	if sim.game_over:
		_new_game()
	_overlay.visible = false
	paused = false
	_pause_button.text = "⏸ Pausar"


func _load_best() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best_score = int(cfg.get_value("score", "best", 0))


func _save_best() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("score", "best", best_score)
	cfg.save(SAVE_PATH)
