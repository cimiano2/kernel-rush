class_name Sim
extends RefCounted
## Simulação pura do escalonador (sem UI). A UI só lê o estado e chama
## assign()/preempt(). Isso permite testar a lógica em modo headless.

signal logged(text: String, kind: String)        # kind: ok | bad | info
signal popped(text: String, color: Color, where: String, index: int)

const TICK := 0.1            # segundos simulados por passo
const CTX_SWITCH := 0.4      # custo de uma troca de contexto
const MAX_QUEUE := 12        # acima disso a fila "transborda"
const LEVEL_TIME := 45.0     # segundos por nível
const RR_QUANTUM := 1.5      # quantum do piloto automático Round Robin
const MAX_CORES := 4

const C_CYAN := Color("34e7e4")
const C_PINK := Color("ff4fa3")
const C_YELLOW := Color("ffd23f")
const C_GREEN := Color("5cff8a")
const C_RED := Color("ff5a5a")
const C_VIOLET := Color("a17bff")

const PALETTE := [
	Color("34e7e4"), Color("5cff8a"), Color("ffd23f"), Color("ff9f43"),
	Color("a17bff"), Color("4fa3ff"), Color("ff6bd5"), Color("c3ff4f"),
]
const NAMES_CPU := ["gcc", "python", "ffmpeg", "blender", "rustc", "mysqld", "make", "zip", "node", "javac"]
const NAMES_IO := ["bash", "vim", "sshd", "nginx", "browser", "chat", "git", "cups"]
const NAMES_RT := ["audio-rt", "mouse-rt", "video-rt", "teclado-rt"]


class Proc:
	var pid: int
	var name: String
	var kind: String            # "cpu" | "io" | "rt"
	var burst: float            # tempo total de CPU necessário
	var remaining: float
	var prio: int               # 1 (baixa) .. 5 (alta)
	var patience: float         # quanto tempo tolera na fila antes de "passar fome"
	var arrival: float
	var wait_start: float       # quando entrou na fila de prontos pela última vez
	var deadline: float = -1.0  # só para tempo real
	var io_every: float = 0.0   # roda isso de CPU e então bloqueia por E/S
	var until_io: float = 0.0
	var io_len: float = 0.0
	var io_left: float = 0.0
	var color: Color
	var starving := false
	var ever_starved := false


var rng := RandomNumberGenerator.new()
var time := 0.0
var level := 1
var score := 0
var satisfaction := 100.0
var completed := 0
var missed := 0
var wait_total := 0.0
var wait_count := 0
var turnaround_total := 0.0
var ctx_switches := 0
var next_pid := 100
var spawn_timer := 0.5
var game_over := false
var autopilot := "off"        # off | fcfs | sjf | rr | prio | edf
var used_autopilot := false

var ready: Array[Proc] = []
var blocked: Array[Proc] = []
var cores: Array[Dictionary] = []   # {proc: Proc|null, switching: float, slice: float}


func _init(seed_value: int = -1) -> void:
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	for i in MAX_CORES:
		cores.append({"proc": null, "switching": 0.0, "slice": 0.0})


func unlocked_cores() -> int:
	if level >= 5:
		return 4
	if level >= 3:
		return 3
	return 2


func avg_wait() -> float:
	return wait_total / wait_count if wait_count > 0 else 0.0


func find_ready(pid: int) -> Proc:
	for p in ready:
		if p.pid == pid:
			return p
	return null


# ------------------------------------------------------------------ passo

func tick() -> void:
	if game_over:
		return
	time += TICK
	_update_level()

	spawn_timer -= TICK
	if spawn_timer <= 0.0:
		_spawn()
		spawn_timer = _spawn_interval()

	if autopilot != "off":
		used_autopilot = true
		_auto_schedule()

	for i in unlocked_cores():
		var c: Dictionary = cores[i]
		var p: Proc = c.proc
		if p == null:
			continue
		if c.switching > 0.0:
			c.switching = maxf(0.0, c.switching - TICK)
			continue
		p.remaining -= TICK
		c.slice += TICK
		if p.kind == "io":
			p.until_io -= TICK
		if p.remaining <= 0.0001:
			_complete(i)
		elif p.kind == "io" and p.until_io <= 0.0001:
			_block(i)
		elif autopilot == "rr" and c.slice >= RR_QUANTUM and not ready.is_empty():
			preempt(i)

	for p in blocked.duplicate():
		p.io_left -= TICK
		if p.io_left <= 0.0:
			blocked.erase(p)
			p.until_io = p.io_every
			_enqueue(p)
			logged.emit("%s (%d) terminou E/S → pronto" % [p.name, p.pid], "info")

	# fome (starvation) e fila transbordando
	for p in ready:
		if time - p.wait_start > p.patience:
			if not p.starving:
				p.starving = true
				p.ever_starved = true
				logged.emit("%s (%d) está passando fome!" % [p.name, p.pid], "bad")
			satisfaction -= 2.0 * TICK
	if ready.size() > MAX_QUEUE:
		satisfaction -= 4.0 * TICK

	_check_deadlines()

	satisfaction = clampf(satisfaction, 0.0, 100.0)
	if satisfaction <= 0.0:
		game_over = true
		logged.emit("KERNEL PANIC — o usuário desistiu do sistema.", "bad")


# ------------------------------------------------------------------ ações do jogador

## Coloca um processo da fila de prontos num núcleo. Se o núcleo estiver
## ocupado, o processo atual sofre preempção e volta para o fim da fila.
func assign(pid: int, core_index: int) -> bool:
	if game_over or core_index < 0 or core_index >= unlocked_cores():
		return false
	var p := find_ready(pid)
	if p == null:
		return false
	if cores[core_index].proc != null:
		preempt(core_index)
	ready.erase(p)
	var waited := time - p.wait_start
	wait_total += waited
	wait_count += 1
	p.starving = false
	var c: Dictionary = cores[core_index]
	c.proc = p
	c.switching = CTX_SWITCH
	c.slice = 0.0
	ctx_switches += 1
	return true


func preempt(core_index: int) -> void:
	var c: Dictionary = cores[core_index]
	var p: Proc = c.proc
	if p == null:
		return
	c.proc = null
	c.switching = 0.0
	c.slice = 0.0
	_enqueue(p)
	logged.emit("Preempção: %s (%d) voltou para a fila" % [p.name, p.pid], "info")


# ------------------------------------------------------------------ interno

func _update_level() -> void:
	var new_level := 1 + int(time / LEVEL_TIME)
	if new_level != level:
		var before := unlocked_cores()
		level = new_level
		logged.emit("NÍVEL %d — a carga aumentou!" % level, "ok")
		popped.emit("NÍVEL %d" % level, C_YELLOW, "center", 0)
		if unlocked_cores() > before:
			logged.emit("Novo núcleo de CPU liberado!", "ok")
		if level == 2:
			logged.emit("Novo: processos de E/S (bloqueiam e voltam).", "ok")
		elif level == 3:
			logged.emit("Novo: processos de TEMPO REAL com prazo!", "ok")


func _spawn_interval() -> float:
	var base := maxf(0.4, 2.8 - 0.3 * (level - 1))
	return base * rng.randf_range(0.6, 1.4)


func _spawn() -> void:
	var p := Proc.new()
	p.pid = next_pid
	next_pid += 1
	var r := rng.randf()
	if level >= 3 and r < 0.18:
		p.kind = "rt"
	elif level >= 2 and r < 0.48:
		p.kind = "io"
	else:
		p.kind = "cpu"
	match p.kind:
		"cpu":
			p.name = NAMES_CPU[rng.randi() % NAMES_CPU.size()]
			p.burst = snappedf(rng.randf_range(1.5, 4.0 + level * 0.6), 0.1)
			p.patience = 10.0
			p.prio = rng.randi_range(1, 3)
			p.color = PALETTE[rng.randi() % PALETTE.size()]
		"io":
			p.name = NAMES_IO[rng.randi() % NAMES_IO.size()]
			p.burst = snappedf(rng.randf_range(2.0, 4.0), 0.1)
			p.patience = 6.0
			p.prio = rng.randi_range(2, 4)
			p.io_every = snappedf(rng.randf_range(0.7, 1.4), 0.1)
			p.until_io = p.io_every
			p.io_len = snappedf(rng.randf_range(1.5, 3.0), 0.1)
			p.color = C_VIOLET
		"rt":
			p.name = NAMES_RT[rng.randi() % NAMES_RT.size()]
			p.burst = snappedf(rng.randf_range(1.0, 2.2), 0.1)
			p.patience = 99.0
			p.prio = 5
			p.color = C_PINK
	p.remaining = p.burst
	p.arrival = time
	if p.kind == "rt":
		p.deadline = time + p.burst + CTX_SWITCH + rng.randf_range(2.5, 4.5)
	_enqueue(p)


func _enqueue(p: Proc) -> void:
	p.wait_start = time
	p.starving = false
	ready.append(p)


func _complete(core_index: int) -> void:
	var p: Proc = cores[core_index].proc
	cores[core_index].proc = null
	completed += 1
	turnaround_total += time - p.arrival
	var pts := 100 + p.prio * 15
	if p.kind == "rt":
		pts += 150
	if not p.ever_starved:
		pts += 50
	score += pts
	satisfaction = minf(100.0, satisfaction + 3.0)
	logged.emit("%s (%d) concluído +%d" % [p.name, p.pid, pts], "ok")
	popped.emit("+%d" % pts, C_GREEN, "core", core_index)


func _block(core_index: int) -> void:
	var p: Proc = cores[core_index].proc
	cores[core_index].proc = null
	p.io_left = p.io_len
	blocked.append(p)
	popped.emit("E/S", C_VIOLET, "core", core_index)


func _check_deadlines() -> void:
	for p in ready.duplicate():
		if p.kind == "rt" and time > p.deadline:
			ready.erase(p)
			_miss(p, -1)
	for p in blocked.duplicate():
		if p.kind == "rt" and time > p.deadline:
			blocked.erase(p)
			_miss(p, -1)
	for i in MAX_CORES:
		var p: Proc = cores[i].proc
		if p != null and p.kind == "rt" and time > p.deadline:
			cores[i].proc = null
			_miss(p, i)


func _miss(p: Proc, core_index: int) -> void:
	missed += 1
	satisfaction -= 15.0
	score = maxi(0, score - 100)
	logged.emit("PRAZO PERDIDO: %s (%d)! −15 satisfação" % [p.name, p.pid], "bad")
	if core_index >= 0:
		popped.emit("PRAZO!", C_RED, "core", core_index)
	else:
		popped.emit("PRAZO PERDIDO!", C_RED, "center", 0)


func _auto_schedule() -> void:
	for i in unlocked_cores():
		if cores[i].proc != null or ready.is_empty():
			continue
		var pick: Proc = ready[0]   # FCFS / RR: cabeça da fila
		match autopilot:
			"sjf":
				for p in ready:
					if p.remaining < pick.remaining:
						pick = p
			"prio":
				for p in ready:
					if p.prio > pick.prio:
						pick = p
			"edf":
				var best: Proc = null
				for p in ready:
					if p.kind == "rt" and (best == null or p.deadline < best.deadline):
						best = p
				if best != null:
					pick = best
		assign(pick.pid, i)
