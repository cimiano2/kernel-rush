extends SceneTree
## Gera capturas de tela (precisa de display, ex.: xvfb-run):
##   godot --path . -s tests/screenshot.gd -- <pasta_saida>

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://"
	var main: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 10: await process_frame
	await _shot(out + "/intro.png")

	main._on_overlay_button()
	main.sim = Sim.new(7, main.config)
	main.sim.logged.connect(main._on_log)
	main.sim.autopilot = "sjf"
	for i in 1500: main.sim.tick()    # ~150s de jogo (nível 4)
	main.sim.autopilot = "off"
	for i in 3: main.sim.tick()
	main.paused = true
	if main.sim.ready.size() > 0:
		main._select(main.sim.ready[0].pid)
	for i in 10: await process_frame
	await _shot(out + "/jogo.png")

	main.sim.satisfaction = 15.0       # sistema sob estresse → glitch
	for i in 30: await process_frame
	await _shot(out + "/estresse.png")

	main.sim.satisfaction = 0.0
	main.sim.game_over = true
	main._show_game_over()
	for i in 10: await process_frame
	await _shot(out + "/gameover.png")
	quit()

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("salvo ", path)
