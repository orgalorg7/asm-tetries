; Headless entry points use the same assembly engine and never configure a TTY
; or load/save the player's high score.

section .rodata
cli_help_arg: db "--help",0
cli_short_help: db "-h",0
cli_test_arg: db "--test",0
cli_demo_arg: db "--demo",0
cli_bench_arg: db "--benchmark",0
cli_usage: db "TETRIS / ASSEMBLY LAB",10
    db "CPU-only. Pure x86-64 assembly. No GPU or network required.",10,10
    db "Usage: ./tetris [--demo | --test | --help]",10
    db "       ./tetris --benchmark [pieces [seed]]",10,10
    db "       ./tetris --versus [seed]       Play against the CPU.",10
    db "       ./tetris --arena-demo [seed]   Watch two CPUs battle.",10
    db "       ./tetris --match [seconds [seed]]  Deterministic battle JSON.",10
    db "       ./tetris --multiverse [seed]  Explore three playable futures.",10
    db "       ./tetris --forecast [seed]    Three future outcomes as JSON.",10
    db "Multiverse: M from battle; arrows pick/seek; Enter jump; M return.",10
    db "Arena: V replay, arrows seek, Space playback, Enter branch, V return.",10
    db "       1/2/3 CPU skill, P pause both boards, R rematch.",10,10
    db "  --demo        Start with the copilot playing; B or a move takes over.",10
    db "  --benchmark   Deterministic JSON run (default: 1000 pieces, seed 12648430).",10
    db "                Pieces: 1..1000000. Seed: 1..18446744073709551615.",10
    db "  --test        Run assembly gameplay and copilot tests.",10,10
    db "Play: arrows / A D S W, Z reverse turn, C hold, Space hard drop.",10
    db "Copilot: B auto, H hint, N play one piece, [ / ] slower / faster.",10
    db "P pause, R restart, 1-9 starting level, -/+ ARR, Q quit.",10
    db "Use an 80x24 terminal for the full copilot dashboard.",10,0
cli_error: db "tetris: invalid arguments; run ./tetris --help",10,0
json_header: db '{',10,'  "search": "reachable-beam-8-depth-2"',0
j_seed: db ',',10,'  "seed": ',0
j_requested: db ',',10,'  "requested_pieces": ',0
j_pieces: db ',',10,'  "pieces": ',0
j_lines: db ',',10,'  "lines": ',0
j_score: db ',',10,'  "score": ',0
j_height: db ',',10,'  "height": ',0
j_holes: db ',',10,'  "holes": ',0
j_nodes: db ',',10,'  "nodes": ',0
j_placements: db ',',10,'  "placements": ',0
j_elapsed: db ',',10,'  "elapsed_ms": ',0
j_mean: db ',',10,'  "mean_plan_us": ',0
j_max: db ',',10,'  "max_plan_us": ',0
j_hash: db ',',10,'  "board_hash": ',0
j_limit: db ',',10,'  "status": "limit"',10,'}',10,0
j_topout: db ',',10,'  "status": "top_out"',10,'}',10,0
j_blocked: db ',',10,'  "status": "no_plan"',10,'}',10,0

section .data
align 8
benchmark_limit: dq 1000
benchmark_seed: dq 12648430

section .bss
benchmark_mode: resb 1
benchmark_blocked: resb 1
alignb 8
benchmark_start: resq 1
benchmark_elapsed: resq 1
benchmark_nodes: resq 1
benchmark_placements: resq 1
benchmark_plans: resq 1
benchmark_plan_sum: resq 1
benchmark_max: resq 1

section .text
parse_cli:
    cmp rdi, 1
    je .return
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    mov rdi, [r13+8]
    lea rsi, [cli_bench_arg]
    call cli_equal
    test eax, eax
    jnz .benchmark
    mov rdi, r12
    mov rsi, r13
    call parse_multiverse_cli
    test eax, eax
    jnz .interactive_return
    mov rdi, r12
    mov rsi, r13
    call parse_arena_cli
    test eax, eax
    jnz .interactive_return
    cmp r12, 2
    jne .invalid
    mov rdi, [r13+8]
    lea rsi, [cli_help_arg]
    call cli_equal
    test eax, eax
    jnz .help
    mov rdi, [r13+8]
    lea rsi, [cli_short_help]
    call cli_equal
    test eax, eax
    jnz .help
    mov rdi, [r13+8]
    lea rsi, [cli_test_arg]
    call cli_equal
    test eax, eax
    jnz .tests
    mov rdi, [r13+8]
    lea rsi, [cli_demo_arg]
    call cli_equal
    test eax, eax
    jz .invalid
    mov byte [ai_auto], 1
.interactive_return:
    pop r13
    pop r12
.return:
    ret
.tests:
    call run_tests
    mov edi, eax
    jmp cli_exit
.help:
    lea rsi, [cli_usage]
    call write_z_stdout
    xor edi, edi
    jmp cli_exit
.benchmark:
    cmp r12, 4
    ja .invalid
    cmp r12, 3
    jb .run
    mov rdi, [r13+16]
    call cli_uint
    test edx, edx
    jz .invalid
    test rax, rax
    jz .invalid
    cmp rax, 1000000
    ja .invalid
    mov [benchmark_limit], rax
    cmp r12, 4
    jb .run
    mov rdi, [r13+24]
    call cli_uint
    test edx, edx
    jz .invalid
    test rax, rax
    jz .invalid
    mov [benchmark_seed], rax
.run:
    mov byte [benchmark_mode], 1
    call run_benchmark
    xor edi, edi
    jmp cli_exit
.invalid:
    lea rsi, [cli_error]
    mov edx, 0
.length:
    cmp byte [rsi+rdx], 0
    je .write_error
    inc edx
    jmp .length
.write_error:
    mov eax, SYS_write
    mov edi, STDERR
    syscall
    mov edi, 2
    jmp cli_exit

cli_exit:
    mov eax, SYS_exit
    syscall

cli_equal:
    mov al, [rdi]
    cmp al, [rsi]
    jne .no
    test al, al
    jz .yes
    inc rdi
    inc rsi
    jmp cli_equal
.yes:
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

; Strict unsigned decimal parser, including overflow and empty-string checks.
; rdi=string -> rax=value, edx=1 success / 0 invalid.
cli_uint:
    xor eax, eax
    cmp byte [rdi], 0
    je .invalid
    mov r8d, 10
.digit:
    movzx r9d, byte [rdi]
    test r9d, r9d
    jz .done
    sub r9d, '0'
    cmp r9d, 9
    ja .invalid
    mul r8
    test rdx, rdx
    jnz .invalid
    add rax, r9
    jc .invalid
    inc rdi
    jmp .digit
.done:
    mov edx, 1
    ret
.invalid:
    xor edx, edx
    ret

run_benchmark:
    push r12
    push r15
    mov rax, [benchmark_seed]
    mov [rng_state], rax
    call reset_game
    call get_time_ns
    mov [benchmark_start], rax
.piece:
    mov rax, [pieces_locked]
    cmp rax, [benchmark_limit]
    jae .report
    cmp byte [game_state], STATE_PLAYING
    jne .report
    call ai_plan
    inc qword [benchmark_plans]
    mov rax, [ai_nodes]
    add [benchmark_nodes], rax
    mov rax, [ai_evaluations]
    add [benchmark_placements], rax
    mov rax, [ai_plan_us]
    add [benchmark_plan_sum], rax
    cmp rax, [benchmark_max]
    jbe .valid
    mov [benchmark_max], rax
.valid:
    cmp byte [ai_valid], 0
    je .blocked
    xor r12d, r12d
.action:
    lea rax, [ai_path]
    movzx edi, byte [rax+r12]
    call ai_execute_action
    inc r12d
    cmp r12d, [ai_path_count]
    jb .action
    jmp .piece
.blocked:
    mov byte [benchmark_blocked], 1
.report:
    call get_time_ns
    sub rax, [benchmark_start]
    xor edx, edx
    mov ecx, 1000000
    div rcx
    mov [benchmark_elapsed], rax
    lea rdi, [board]
    call ai_evaluate
    lea r15, [output_buf]
    lea rsi, [json_header]
    call append_z
%macro BENCH_FIELD 2
    lea rsi, [%1]
    call append_z
    mov rdi, %2
    call append_u64
%endmacro
    BENCH_FIELD j_seed, [benchmark_seed]
    BENCH_FIELD j_requested, [benchmark_limit]
    BENCH_FIELD j_pieces, [pieces_locked]
    BENCH_FIELD j_lines, [total_lines]
    BENCH_FIELD j_score, [score]
    mov eax, [ai_eval_height]
    BENCH_FIELD j_height, rax
    mov eax, [ai_eval_holes]
    BENCH_FIELD j_holes, rax
    BENCH_FIELD j_nodes, [benchmark_nodes]
    BENCH_FIELD j_placements, [benchmark_placements]
    BENCH_FIELD j_elapsed, [benchmark_elapsed]
    mov rax, [benchmark_plan_sum]
    xor edx, edx
    div qword [benchmark_plans]
    BENCH_FIELD j_mean, rax
    BENCH_FIELD j_max, [benchmark_max]
    call board_hash
    BENCH_FIELD j_hash, rax
    lea rsi, [j_limit]
    cmp byte [game_state], STATE_GAME_OVER
    jne .check_blocked
    lea rsi, [j_topout]
.check_blocked:
    cmp byte [benchmark_blocked], 0
    je .emit
    lea rsi, [j_blocked]
.emit:
    call append_z
    lea rsi, [output_buf]
    mov rdx, r15
    sub rdx, rsi
    call write_all_stdout
    pop r15
    pop r12
    ret

; Stable FNV-1a digest of the 200 locked cells, for reproducibility checks.
board_hash:
    mov rax, 0xcbf29ce484222325
    mov r8, 0x100000001b3
    lea rsi, [board]
    xor ecx, ecx
.cell:
    movzx edx, byte [rsi+rcx]
    xor rax, rdx
    imul rax, r8
    inc ecx
    cmp ecx, BOARD_SIZE
    jb .cell
    ret
