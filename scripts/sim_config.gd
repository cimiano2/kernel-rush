class_name SimConfig
extends Resource
## Parâmetros de balanceamento do jogo.
## Edite [code]resources/sim_config.tres[/code] no inspetor do Godot para ajustar a dificuldade
## sem mexer em código.

@export_group("Tempo")
## Segundos simulados por passo da simulação.
@export_range(0.05, 0.5, 0.05) var tick: float = 0.1
## Custo de cada troca de contexto (atribuir um processo a um núcleo).
@export_range(0.0, 2.0, 0.05) var ctx_switch: float = 0.4
## Segundos até subir de nível.
@export_range(10.0, 180.0, 1.0) var level_time: float = 45.0
## Quantum usado pelo piloto automático Round Robin.
@export_range(0.2, 5.0, 0.1) var rr_quantum: float = 1.5

@export_group("Carga")
## Tamanho da fila de prontos antes de "transbordar".
@export_range(4, 30) var max_queue: int = 12
## Intervalo médio entre chegadas no nível 1.
@export_range(0.5, 6.0, 0.1) var spawn_base: float = 2.8
## Quanto o intervalo diminui a cada nível.
@export_range(0.0, 1.0, 0.05) var spawn_step: float = 0.3
## Intervalo mínimo entre chegadas.
@export_range(0.1, 3.0, 0.05) var spawn_min: float = 0.4
## Nível em que cada núcleo é liberado (índice = núcleo).
@export var core_unlock_levels: Array[int] = [1, 1, 3, 5]
## Nível em que surgem processos de E/S.
@export_range(1, 10) var io_from_level: int = 2
## Nível em que surgem processos de tempo real.
@export_range(1, 10) var rt_from_level: int = 3

@export_group("Satisfação")
## Perda por segundo para cada processo passando fome.
@export_range(0.0, 10.0, 0.1) var starvation_drain: float = 2.0
## Perda por segundo enquanto a fila está transbordando.
@export_range(0.0, 20.0, 0.5) var overflow_drain: float = 4.0
## Perda ao estourar o prazo de um processo de tempo real.
@export_range(0.0, 50.0, 1.0) var deadline_penalty: float = 15.0
## Ganho a cada processo concluído.
@export_range(0.0, 20.0, 0.5) var completion_bonus: float = 3.0
