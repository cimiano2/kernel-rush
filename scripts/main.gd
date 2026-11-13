extends Control
## Cena principal: monta a interface em código e conecta à simulação.

const SAVE_PATH := "user://kernel_rush.cfg"

var sim: Sim
var paused := true
var accum := 0.0
var selected_pid := -1
var best_score := 0

var cards := {}        # pid -> ProcCard (fila de prontos)
var blocked_cards := {} # pid -> ProcCard (bloqueados)
var core_slots: Array[CoreSlot] = []

# widgets
var lbl_time: Label
var lbl_level: Label
var lbl_score: Label
var lbl_done: Label
var lbl_wait: Label
var lbl_ctx: Label
var sat_bar: ProgressBar
var lbl_queue: Label
var ready_box: VBoxContainer
var blocked_box: VBoxContainer
var log_box: RichTextLabel
var btn_pause: Button
var opt_auto: OptionButton
var fx_layer: Control
var overlay: ColorRect
var overlay_text: RichTextLabel
var overlay_btn: Button

const AUTO_MODES := [
	["off", "Desligado (você joga)"],
	["fcfs", "FCFS — primeiro a chegar"],
	["sjf", "SJF — menor job primeiro"],
	["rr", "Round Robin (quantum 1,5s)"],
	["prio", "Prioridade"],
	["edf", "EDF — prazo mais cedo"],
]


func _ready() -> void:
	_load_best()
	_build_ui()
	_new_game()
	_show_intro()


# ================================================================ jogo

func _new_game() -> void:
	sim = Sim.new()
	sim.logged.connect(_on_log)
	sim.popped.connect(_on_pop)
	sim.autopilot = AUTO_MODES[opt_auto.selected][0]
	for c in cards.values():
		c.queue_free()
	for c in blocked_cards.values():
		c.queue_free()
	cards.clear()
	blocked_cards.clear()
	selected_pid = -1
	accum = 0.0
	log_box.clear()
	_on_log("Sistema iniciado. Escalone os processos!", "info")
	_refresh(0.0)


func _process(delta: float) -> void:
	if not paused and not sim.game_over:
		accum += delta
		while accum >= Sim.TICK:
			accum -= Sim.TICK
			sim.tick()
			if sim.game_over:
				_show_game_over()
				break
	_refresh(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_SPACE, KEY_P:
			if overlay.visible:
				_on_overlay_button()
			else:
				_toggle_pause()
		KEY_1, KEY_2, KEY_3, KEY_4:
			_on_core_clicked(event.keycode - KEY_1)
		KEY_ESCAPE:
			_select(-1)
		KEY_ENTER, KEY_KP_ENTER:
			if overlay.visible:
				_on_overlay_button()
		_:
			return
	get_viewport().set_input_as_handled()


func _select(pid: int) -> void:
	selected_pid = pid if pid != selected_pid else -1
	for k in cards:
		cards[k].set_selected(k == selected_pid)


func _on_card_clicked(pid: int) -> void:
	_select(pid)


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
	btn_pause.text = "▶ Continuar" if paused else "⏸ Pausar"


# ================================================================ render

func _refresh(delta: float) -> void:
	lbl_time.text = "%.1fs" % sim.time
	lbl_level.text = str(sim.level)
	lbl_score.text = str(sim.score)
	lbl_done.text = str(sim.completed)
	lbl_wait.text = "%.1fs" % sim.avg_wait()
	lbl_ctx.text = str(sim.ctx_switches)
	sat_bar.value = sim.satisfaction / 100.0
	UIStyle.set_bar_color(sat_bar,
		UIStyle.GREEN if sim.satisfaction > 60 else (UIStyle.YELLOW if sim.satisfaction > 30 else UIStyle.RED))
	lbl_queue.text = "%d/%d" % [sim.ready.size(), Sim.MAX_QUEUE]
	lbl_queue.add_theme_color_override("font_color",
		UIStyle.RED if sim.ready.size() > Sim.MAX_QUEUE else UIStyle.MUTED)

	_sync_cards(sim.ready, cards, ready_box, true)
	_sync_cards(sim.blocked, blocked_cards, blocked_box, false)
	if selected_pid >= 0 and not cards.has(selected_pid):
		selected_pid = -1

	var unlocked := sim.unlocked_cores()
	for i in core_slots.size():
		core_slots[i].refresh(sim.cores[i], i < unlocked, sim.time, delta)


## Mantém os nós de cartão em sincronia com a lista do simulador, sem
## recriar tudo a cada quadro (assim drag & drop e cliques não quebram).
func _sync_cards(list: Array, map: Dictionary, box: VBoxContainer, draggable: bool) -> void:
	var alive := {}
	for i in list.size():
		var p: Sim.Proc = list[i]
		alive[p.pid] = true
		var card: ProcCard = map.get(p.pid)
		if card == null:
			card = ProcCard.new()
			card.setup(p, draggable)
			if draggable:
				card.clicked.connect(_on_card_clicked)
			box.add_child(card)
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


func _on_log(text: String, kind: String) -> void:
	var col := {"ok": UIStyle.GREEN, "bad": UIStyle.RED, "info": UIStyle.CYAN}.get(kind, UIStyle.MUTED) as Color
	var t := "%5.1fs" % (sim.time if sim else 0.0)
	log_box.push_color(UIStyle.MUTED)
	log_box.add_text(t + "  ")
	log_box.pop()
	log_box.push_color(col)
	log_box.add_text(text + "\n")
	log_box.pop()
	# mantém o log curto
	while log_box.get_line_count() > 40:
		log_box.remove_paragraph(0)


func _on_pop(text: String, color: Color, where: String, index: int) -> void:
	var l := UIStyle.label(text, 22 if where == "center" else 16, color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	fx_layer.add_child(l)
	var origin: Vector2
	if where == "core" and index < core_slots.size():
		var r := core_slots[index].get_global_rect()
		origin = r.get_center() - Vector2(20, 10)
	else:
		origin = get_viewport_rect().size / 2.0 - Vector2(80, 0)
	l.global_position = origin
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "global_position:y", origin.y - 50, 1.1).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 1.1).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)


# ================================================================ overlays

func _show_intro() -> void:
	paused = true
	overlay_text.text = """[color=#34e7e4][font_size=26]KERNEL // RUSH[/font_size][/color]

Você é o [b]escalonador de CPU[/b] de um sistema operacional. Processos chegam à [b]fila de prontos[/b]: decida quem roda em cada núcleo.

[color=#ffd23f]Como jogar[/color]
• Clique num processo e depois num núcleo, ou [b]arraste[/b] (atalhos [b]1–4[/b]).
• Clique num núcleo ocupado para fazer [b]preempção[/b]: o processo volta ao fim da fila.
• Toda troca custa [b]0,4s de troca de contexto[/b], então não troque à toa!

[color=#ffd23f]Tipos de processo[/color]
• [color=#34e7e4]CPU[/color]: pesado, roda até terminar.
• [color=#a17bff]E/S[/color] (nível 2+): roda um pouco e bloqueia esperando o disco/rede, depois volta.
• [color=#ff4fa3]TEMPO REAL[/color] (nível 3+): tem [b]prazo[/b]; perder custa caro.

[color=#ff5a5a]Cuidado[/color]: processos esperando demais passam [b]fome[/b] (starvation) e a satisfação do usuário cai. Se chegar a zero: [b]KERNEL PANIC[/b].

[color=#8592c4]Dica: use o piloto automático para comparar FCFS, SJF, Round Robin, Prioridade e EDF com a sua estratégia.[/color]"""
	overlay_btn.text = "INICIAR  [Enter]"
	overlay.visible = true


func _show_game_over() -> void:
	paused = true
	var assisted := sim.used_autopilot
	var record := ""
	if not assisted and sim.score > best_score:
		best_score = sim.score
		_save_best()
		record = "\n[color=#ffd23f]★ NOVO RECORDE! ★[/color]\n"
	var avg_turn := sim.turnaround_total / sim.completed if sim.completed > 0 else 0.0
	overlay_text.text = """[color=#ff5a5a][font_size=26]KERNEL PANIC[/font_size][/color]
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
		sim.avg_wait(), avg_turn, sim.ctx_switches,
		"[color=#8592c4](partida com piloto automático: não conta para recorde)[/color]" if assisted else ""]
	overlay_btn.text = "JOGAR DE NOVO  [Enter]"
	overlay.visible = true


func _on_overlay_button() -> void:
	if sim.game_over:
		_new_game()
	overlay.visible = false
	paused = false
	btn_pause.text = "⏸ Pausar"


func _load_best() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best_score = int(cfg.get_value("score", "best", 0))


func _save_best() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("score", "best", best_score)
	cfg.save(SAVE_PATH)


# ================================================================ construção da UI

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UIStyle.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	# ---------- cabeçalho
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 22)
	root.add_child(header)
	var logo := RichTextLabel.new()
	logo.bbcode_enabled = true
	logo.fit_content = true
	logo.scroll_active = false
	logo.autowrap_mode = TextServer.AUTOWRAP_OFF
	logo.add_theme_font_override("bold_font", UIStyle.mono())
	logo.add_theme_font_size_override("bold_font_size", 24)
	logo.text = "[b][color=#34e7e4]KERNEL[/color][color=#ff4fa3]//[/color][color=#34e7e4]RUSH[/color][/b]"
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	logo.custom_minimum_size = Vector2(210, 0)
	header.add_child(logo)

	lbl_time = _stat(header, "TEMPO")
	lbl_level = _stat(header, "NÍVEL")
	lbl_score = _stat(header, "PONTOS")
	lbl_done = _stat(header, "CONCLUÍDOS")
	lbl_wait = _stat(header, "ESPERA MÉDIA")
	lbl_ctx = _stat(header, "TROCAS CTX")

	var satv := VBoxContainer.new()
	satv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	satv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(satv)
	satv.add_child(UIStyle.label("SATISFAÇÃO DO USUÁRIO", 11, UIStyle.MUTED))
	sat_bar = UIStyle.bar(UIStyle.GREEN, 16)
	satv.add_child(sat_bar)

	# ---------- corpo (3 colunas)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	root.add_child(body)

	var ready_panel := _panel(body, "FILA DE PRONTOS", 1.0)
	lbl_queue = UIStyle.label("0/12", 12, UIStyle.MUTED)
	ready_panel.get_child(0).add_child(lbl_queue)
	ready_box = _scroll_list(ready_panel)

	var cpu_panel := _panel(body, "NÚCLEOS DA CPU", 1.4)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	cpu_panel.add_child(grid)
	for i in Sim.MAX_CORES:
		var slot := CoreSlot.new()
		slot.setup(i)
		slot.clicked.connect(_on_core_clicked)
		slot.dropped.connect(_on_core_dropped)
		grid.add_child(slot)
		core_slots.append(slot)
	var hint := UIStyle.label(
		"Clique num processo e depois num núcleo (ou arraste).\n" +
		"[1–4] núcleo · [Espaço] pausa · [Esc] desmarca\n" +
		"Clique num núcleo ocupado (sem seleção) = preempção.", 12, UIStyle.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cpu_panel.add_child(hint)

	var io_panel := _panel(body, "BLOQUEADOS (E/S)", 1.0)
	blocked_box = VBoxContainer.new()
	blocked_box.add_theme_constant_override("separation", 6)
	blocked_box.custom_minimum_size = Vector2(0, 120)
	io_panel.add_child(blocked_box)
	var log_title := UIStyle.label("LOG DO KERNEL", 13, UIStyle.CYAN)
	io_panel.add_child(log_title)
	log_box = RichTextLabel.new()
	log_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_box.scroll_following = true
	log_box.add_theme_font_override("normal_font", UIStyle.mono())
	log_box.add_theme_font_size_override("normal_font_size", 11)
	log_box.mouse_filter = Control.MOUSE_FILTER_PASS
	io_panel.add_child(log_box)

	# ---------- rodapé
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	root.add_child(footer)
	btn_pause = _button(footer, "⏸ Pausar", _toggle_pause)
	footer.add_child(UIStyle.label("Piloto automático:", 12, UIStyle.MUTED))
	opt_auto = OptionButton.new()
	opt_auto.add_theme_font_override("font", UIStyle.mono())
	for m in AUTO_MODES:
		opt_auto.add_item(m[1])
	opt_auto.item_selected.connect(func(i): sim.autopilot = AUTO_MODES[i][0])
	opt_auto.focus_mode = Control.FOCUS_NONE
	footer.add_child(opt_auto)
	_button(footer, "↻ Reiniciar", func():
		_new_game()
		overlay.visible = false
		paused = false
		btn_pause.text = "⏸ Pausar")

	# ---------- efeitos e overlay
	fx_layer = Control.new()
	fx_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fx_layer)

	overlay = ColorRect.new()
	overlay.color = Color(0.02, 0.03, 0.06, 0.85)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var modal := PanelContainer.new()
	modal.add_theme_stylebox_override("panel", UIStyle.box(UIStyle.PANEL, UIStyle.CYAN, 3, -1, 24))
	modal.custom_minimum_size = Vector2(640, 0)
	center.add_child(modal)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 14)
	modal.add_child(mv)
	overlay_text = RichTextLabel.new()
	overlay_text.bbcode_enabled = true
	overlay_text.fit_content = true
	overlay_text.scroll_active = false
	overlay_text.custom_minimum_size = Vector2(600, 0)
	overlay_text.add_theme_font_override("normal_font", UIStyle.mono())
	overlay_text.add_theme_font_override("bold_font", UIStyle.mono())
	overlay_text.add_theme_font_size_override("normal_font_size", 14)
	overlay_text.add_theme_font_size_override("bold_font_size", 14)
	mv.add_child(overlay_text)
	overlay_btn = _button(mv, "INICIAR", _on_overlay_button)
	overlay_btn.add_theme_stylebox_override("normal", UIStyle.box(UIStyle.CYAN, UIStyle.CYAN, 2, -1, 12))
	overlay_btn.add_theme_stylebox_override("hover", UIStyle.box(UIStyle.YELLOW, UIStyle.YELLOW, 2, -1, 12))
	overlay_btn.add_theme_color_override("font_color", Color("04131a"))
	overlay_btn.add_theme_color_override("font_hover_color", Color("1a1400"))


func _stat(parent: Control, title: String) -> Label:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(v)
	v.add_child(UIStyle.label(title, 10, UIStyle.MUTED))
	var l := UIStyle.label("0", 18, UIStyle.YELLOW)
	v.add_child(l)
	return l


func _panel(parent: Control, title: String, ratio: float) -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.size_flags_stretch_ratio = ratio
	pc.add_theme_stylebox_override("panel", UIStyle.box(UIStyle.PANEL, UIStyle.LINE, 2, -1, 12))
	parent.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pc.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := UIStyle.label(title, 13, UIStyle.CYAN)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	return v


func _scroll_list(panel: VBoxContainer) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	sc.add_child(v)
	return v


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", UIStyle.mono())
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_stylebox_override("normal", UIStyle.box(UIStyle.BG2, UIStyle.LINE, 2, -1, 10))
	b.add_theme_stylebox_override("hover", UIStyle.box(UIStyle.BG2, UIStyle.CYAN, 2, -1, 10))
	b.add_theme_stylebox_override("pressed", UIStyle.box(UIStyle.BG, UIStyle.YELLOW, 2, -1, 10))
	b.add_theme_color_override("font_hover_color", UIStyle.CYAN)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b
