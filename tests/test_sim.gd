extends SceneTree
## Testes headless da simulação:
##   godot --headless --path . -s tests/test_sim.gd

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		failures += 1
		printerr("  FAIL ", msg)


func _init() -> void:
	print("Kernel Rush — testes da simulação")

	# 1. processo atribuído passa pela troca de contexto e conclui
	var s := Sim.new(1)
	s.spawn_timer = 9999.0
	s._spawn()
	var p: Sim.Proc = s.ready[0]
	p.kind = "cpu"
	p.burst = 1.0
	p.remaining = 1.0
	check(s.assign(p.pid, 0), "assign aceita processo da fila")
	check(s.ready.is_empty(), "processo sai da fila de prontos")
	check(s.ctx_switches == 1, "troca de contexto contabilizada")
	for i in 13:   # 0.4s de troca + 1.0s de execução (+ folga de arredondamento)
		s.spawn_timer = 9999.0
		s.tick()
	check(s.cores[0].proc == p, "ainda rodando antes do fim do burst")
	for i in 3:
		s.spawn_timer = 9999.0
		s.tick()
	check(s.completed == 1, "processo concluído após troca + burst")
	check(s.score > 0, "pontuação aumentou")

	# 2. núcleo bloqueado não aceita processos
	s = Sim.new(2)
	s._spawn()
	check(not s.assign(s.ready[0].pid, 3), "núcleo 4 bloqueado no nível 1")

	# 3. preempção devolve à fila
	s = Sim.new(3)
	s._spawn()
	var pid: int = s.ready[0].pid
	s.assign(pid, 1)
	s.preempt(1)
	check(s.cores[1].proc == null and s.find_ready(pid) != null, "preempção devolve à fila")

	# 4. fome reduz satisfação
	s = Sim.new(4)
	s._spawn()
	s.ready[0].patience = 0.5
	for i in 20:
		s.spawn_timer = 9999.0
		s.tick()
	check(s.satisfaction < 100.0 and s.ready[0].starving, "starvation reduz satisfação")

	# 5. prazo de tempo real perdido
	s = Sim.new(5)
	s._spawn()
	s.ready[0].kind = "rt"
	s.ready[0].deadline = 0.3
	for i in 5:
		s.spawn_timer = 9999.0
		s.tick()
	check(s.missed == 1 and s.ready.is_empty(), "prazo perdido remove processo e penaliza")

	# 6. processo de E/S bloqueia e volta
	s = Sim.new(6)
	s._spawn()
	var io: Sim.Proc = s.ready[0]
	io.kind = "io"
	io.burst = 5.0
	io.remaining = 5.0
	io.io_every = 0.5
	io.until_io = 0.5
	io.io_len = 0.5
	s.assign(io.pid, 0)
	for i in 10:
		s.spawn_timer = 9999.0
		s.tick()
	check(s.blocked.has(io), "processo de E/S foi para bloqueados")
	for i in 6:
		s.spawn_timer = 9999.0
		s.tick()
	check(s.find_ready(io.pid) != null, "processo de E/S voltou para prontos")

	# 7. cada piloto automático roda uma partida longa sem erro
	for mode in ["fcfs", "sjf", "rr", "prio", "edf"]:
		s = Sim.new(42)
		s.autopilot = mode
		for i in 9000:   # até 900s simulados
			if s.game_over:
				break
			s.tick()
		print("       %-4s → tempo %.0fs, nível %d, concluídos %d, pontos %d, espera média %.2fs, game over: %s"
			% [mode, s.time, s.level, s.completed, s.score, s.avg_wait(), s.game_over])
		check(s.completed > 10, "piloto %s conclui processos" % mode)

	print("\n%s" % ("TODOS OS TESTES PASSARAM" if failures == 0 else "%d FALHA(S)" % failures))
	quit(1 if failures > 0 else 0)
