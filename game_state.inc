; Complete per-player state. Terminal I/O and search scratch space stay global.
; Arena snapshots copy this block, including RNG, timers, queues, and AI routes.
%define AI_STATES 2048
%define GARBAGE_CAP 64
%define CELL_GARBAGE 11
alignb 16
game_context_begin:
board:          resb BOARD_SIZE
rng_state:      resq 1
score:          resq 1
total_lines:    resq 1
level:          resq 1
start_level:    resq 1
combo:          resq 1
last_drop_ns:   resq 1
lock_deadline:  resq 1
flash_until_ns: resq 1
render_now_ns:  resq 1
piece_x:        resd 1
piece_y:        resd 1
piece_type:     resd 1
piece_rot:      resd 1
next_queue:     resd 5
hold_type:      resd 1
landing_cells:  resd 4
game_state:     resb 1
bag_index:      resb 1
bag:            resb 7
grounded:       resb 1
lock_resets:    resb 1
hold_used:      resb 1
last_action_rotate: resb 1
last_kick_index: resb 1
spin_kind:      resb 1              ; 0 normal, 1 T-spin mini, 2 full T-spin
hard_drop_lock: resb 1
flash_count:    resb 1
b2b_active:     resb 1
das_active:     resb 1
horizontal_dir: resd 1
horizontal_last_ns: resq 1
das_deadline_ns: resq 1
arr_deadline_ns: resq 1
arr_interval_ns: resq 1
piece_serial: resq 1
pieces_locked: resq 1
assisted_run: resb 1
ai_auto: resb 1
ai_single: resb 1
ai_valid: resb 1
ai_cached: resb 1
ai_deadline: resq 1
ai_snapshot: resq 3
ai_plan_us: resq 1
ai_nodes: resq 1
ai_evaluations: resq 1
ai_live_height: resd 1
ai_live_holes: resd 1
ai_goal_x: resd 1
ai_goal_y: resd 1
ai_goal_rot: resd 1
ai_goal_type: resd 1
ai_path_count: resd 1
ai_path_index: resd 1
ai_path: resb AI_STATES+1
ai_hint: resb 1
alignb 8
ai_interval: resq 1
battle_sent: resq 1
battle_cancelled: resq 1
battle_received: resq 1
battle_outbox: resd 1
battle_prior_b2b: resb 1
alignb 4
incoming_head: resd 1
incoming_count: resd 1
incoming_holes: resb GARBAGE_CAP
alignb 8
incoming_due: resq GARBAGE_CAP
alignb 16
game_context_end:
GAME_CONTEXT_SIZE equ game_context_end - game_context_begin
