section .rodata
ar_versus_arg: db "--versus",0
ar_demo_arg: db "--arena-demo",0
ar_match_arg: db "--match",0
ar_json: db '{',10,'  "mode": "arena"',0
ar_jseed: db ',',10,'  "seed": ',0
ar_jtime: db ',',10,'  "simulated_ms": ',0
ar_jleft_result: db ',',10,'  "result": "left"',0
ar_jright_result: db ',',10,'  "result": "right"',0
ar_jdraw_result: db ',',10,'  "result": "draw"',0
ar_jleft: db ',',10,'  "left": {',0
ar_jright: db ',',10,'  "right": {',0
ar_jpieces: db '"pieces": ',0
ar_jlines: db ', "lines": ',0
ar_jsent: db ', "sent": ',0
ar_jcancelled: db ', "cancelled": ',0
ar_jreceived: db ', "received": ',0
ar_jpending: db ', "pending": ',0
ar_jscore: db ', "score": ',0
ar_jhash: db ', "board_hash": ',0
ar_jcells: db ', "cells": ',0
ar_jclose: db '}',0
ar_jwall: db ',',10,'  "wall_ms": ',0
ar_jend: db 10,'}',10,0

section .bss
alignb 8
arena_match_wall: resq 1

section .text
; Return 1 for an interactive arena command, 0 for an unrelated option.
; Headless commands and malformed arena options exit directly.
parse_arena_cli:
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    mov rdi, [r13+8]
    lea rsi, [ar_versus_arg]
    call cli_equal
    test eax, eax
    jnz .interactive
    mov rdi, [r13+8]
    lea rsi, [ar_demo_arg]
    call cli_equal
    test eax, eax
    jz .match_check
    mov byte [arena_spectator], 1
.interactive:
    cmp r12, 3
    ja parse_cli.invalid
    cmp r12, 3
    jb .ready
    mov rdi, [r13+16]
    call cli_uint
    test edx, edx
    jz parse_cli.invalid
    test rax, rax
    jz parse_cli.invalid
    mov [arena_seed], rax
.ready:
    mov byte [arena_mode], 1
    mov eax, 1
    jmp .done
.match_check:
    mov rdi, [r13+8]
    lea rsi, [ar_match_arg]
    call cli_equal
    test eax, eax
    jz .done
    cmp r12, 4
    ja parse_cli.invalid
    mov qword [arena_seed], 42
    cmp r12, 3
    jb .run
    mov rdi, [r13+16]
    call cli_uint
    test edx, edx
    jz parse_cli.invalid
    test rax, rax
    jz parse_cli.invalid
    cmp rax, 3600
    ja parse_cli.invalid
    imul rax, rax, 1000000000
    mov [arena_duration], rax
    cmp r12, 4
    jb .run
    mov rdi, [r13+24]
    call cli_uint
    test edx, edx
    jz parse_cli.invalid
    test rax, rax
    jz parse_cli.invalid
    mov [arena_seed], rax
.run:
    mov byte [arena_mode], 1
    mov byte [arena_spectator], 1
    mov byte [arena_simulating], 1
    call run_match
    xor edi, edi
    jmp cli_exit
.done:
    pop r13
    pop r12
    ret

run_match:
    push r15
    call get_wall_time_ns
    mov [arena_match_wall], rax
    call arena_init
    mov byte [arena_phase], ARENA_LIVE
    mov rax, [arena_now]
    mov [arena_live_start], rax
.tick:
    call arena_tick
    cmp byte [arena_phase], ARENA_FINISHED
    jne .tick
    call get_wall_time_ns
    sub rax, [arena_match_wall]
    xor edx, edx
    mov ecx, 1000000
    div rcx
    mov [arena_match_wall], rax
    lea r15, [output_buf]
    lea rsi, [ar_json]
    call append_z
    BENCH_FIELD ar_jseed, [arena_seed]
    mov rax, [arena_now]
    sub rax, [arena_live_start]
    xor edx, edx
    mov ecx, 1000000
    div rcx
    BENCH_FIELD ar_jtime, rax
    lea rsi, [ar_jleft_result]
    cmp byte [arena_winner], 1
    je .result
    lea rsi, [ar_jright_result]
    cmp byte [arena_winner], 2
    je .result
    lea rsi, [ar_jdraw_result]
.result:
    call append_z
    lea rsi, [ar_jleft]
    call append_z
    lea rdi, [arena_left]
    call arena_json_player
    lea rsi, [ar_jright]
    call append_z
    lea rdi, [arena_right]
    call arena_json_player
    BENCH_FIELD ar_jwall, [arena_match_wall]
    lea rsi, [ar_jend]
    call append_z
    lea rsi, [output_buf]
    mov rdx, r15
    sub rdx, rsi
    call write_all_stdout
    pop r15
    ret

arena_json_player:
    push r12
    mov r12, rdi
    BENCH_FIELD ar_jpieces, [r12+CTX(pieces_locked)]
    BENCH_FIELD ar_jlines, [r12+CTX(total_lines)]
    BENCH_FIELD ar_jsent, [r12+CTX(battle_sent)]
    BENCH_FIELD ar_jcancelled, [r12+CTX(battle_cancelled)]
    BENCH_FIELD ar_jreceived, [r12+CTX(battle_received)]
    mov eax, [r12+CTX(incoming_count)]
    BENCH_FIELD ar_jpending, rax
    BENCH_FIELD ar_jscore, [r12+CTX(score)]
    mov rdi, r12
    call arena_context_hash
    BENCH_FIELD ar_jhash, rax
    xor eax, eax
    xor ecx, ecx
.cells:
    cmp byte [r12+CTX(board)+rcx], 0
    je .next
    inc eax
.next:
    inc ecx
    cmp ecx, BOARD_SIZE
    jb .cells
    BENCH_FIELD ar_jcells, rax
    lea rsi, [ar_jclose]
    call append_z
    pop r12
    ret

arena_context_hash:
    mov rax, 0xcbf29ce484222325
    mov r8, 0x100000001b3
    xor ecx, ecx
.cell:
    movzx edx, byte [rdi+CTX(board)+rcx]
    xor rax, rdx
    imul rax, r8
    inc ecx
    cmp ecx, BOARD_SIZE
    jb .cell
    ret
