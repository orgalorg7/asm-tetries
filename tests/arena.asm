section .rodata
ar_test_ok: db "Arena: attacks, garbage, bounds, replay, deterministic time travel: PASS",10,0
ar_test_bad: db "Arena regression: FAIL at stage ",0
section .bss
alignb 8
ar_test_stage: resq 1
ar_test_digest: resq 1
ar_test_right_digest: resq 1
ar_test_garbage_rng: resq 1
ar_test_now: resq 1
section .text
run_arena_tests:
    push rbx
    push r12
    push r15
    mov byte [arena_mode], 1
    mov byte [arena_simulating], 1
    mov qword [arena_seed], 42
    call arena_init
    mov byte [arena_phase], ARENA_LIVE
    mov rax, [arena_now]
    mov [arena_live_start], rax

    mov qword [ar_test_stage], 1
    ; Three pending rows, a single sends one: cancel oldest before delivery.
    lea rdi, [game_context_begin]
    mov esi, 3
    mov edx, 4
    mov rcx, [arena_now]
    add rcx, GARBAGE_WARNING
    call arena_queue_garbage
    mov byte [board+199], 1       ; avoid perfect-clear bonus
    mov qword [combo], 0
    mov byte [spin_kind], 0
    mov byte [battle_prior_b2b], 0
    mov edi, 1
    call arena_on_lock
    cmp dword [incoming_count], 2
    jne .fail
    cmp dword [incoming_head], 1
    jne .fail
    cmp qword [battle_cancelled], 1
    jne .fail
    cmp dword [battle_outbox], 0
    jne .fail

    mov qword [ar_test_stage], 2
    call arena_receive_garbage
    cmp qword [battle_received], 0
    jne .fail
    add qword [arena_now], GARBAGE_WARNING
    call arena_receive_garbage
    cmp dword [incoming_count], 0
    jne .fail
    cmp qword [battle_received], 2
    jne .fail
    cmp byte [board+179], 1
    jne .fail
    cmp byte [board+184], 0
    jne .fail
    cmp byte [board+194], 0
    jne .fail
    cmp byte [board+190], CELL_GARBAGE
    jne .fail

    mov qword [ar_test_stage], 3
    mov byte [board], 1
    lea rdi, [game_context_begin]
    mov esi, 1
    mov edx, 2
    mov rcx, [arena_now]
    call arena_queue_garbage
    call arena_receive_garbage
    cmp byte [game_state], STATE_GAME_OVER
    jne .fail

    mov qword [ar_test_stage], 4
    call arena_init
    mov byte [arena_phase], ARENA_LIVE
    mov rax, [arena_now]
    mov [arena_live_start], rax
    mov byte [board+195], 3
    mov qword [score], 1234
    mov qword [rng_state], 2026
    mov dword [incoming_count], 2
    mov byte [incoming_holes], 5
    call arena_save_left
    call arena_history_capture
    mov byte [board+195], 6
    mov qword [score], 9999
    mov qword [rng_state], 999
    call arena_save_left
    add qword [arena_now], HISTORY_PERIOD
    call arena_history_capture
    mov dword [arena_replay_index], 0
    mov byte [arena_phase], ARENA_REPLAY
    call arena_branch
    cmp byte [arena_phase], ARENA_LIVE
    jne .fail
    cmp byte [board+195], 3
    jne .fail
    cmp qword [score], 1234
    jne .fail
    cmp qword [rng_state], 2026
    jne .fail
    cmp dword [incoming_count], 2
    jne .fail
    cmp byte [incoming_holes], 5
    jne .fail
    cmp dword [arena_history_count], 1
    jne .fail
    cmp qword [arena_branches], 1
    jne .fail

    mov qword [ar_test_stage], 5
    ; Replay a whole future twice, including gravity, both pilots, and attacks.
    ; Every per-player byte must match, except the wall-clock search profiler.
    mov byte [arena_spectator], 1
    call arena_init
    mov byte [arena_phase], ARENA_LIVE
    mov rax, [arena_now]
    mov [arena_live_start], rax
    call arena_history_capture
    mov r12d, 1200
.future:
    call arena_tick
    dec r12d
    jnz .future
    lea rdi, [arena_left]
    call ar_test_context_digest
    mov [ar_test_digest], rax
    lea rdi, [arena_right]
    call ar_test_context_digest
    mov [ar_test_right_digest], rax
    mov rax, [arena_attack_rng]
    mov [ar_test_garbage_rng], rax
    mov rax, [arena_now]
    mov [ar_test_now], rax
    mov dword [arena_replay_index], 0
    mov byte [arena_phase], ARENA_REPLAY
    call arena_branch
    mov r12d, 1200
.repeat_future:
    call arena_tick
    dec r12d
    jnz .repeat_future
    lea rdi, [arena_left]
    call ar_test_context_digest
    cmp rax, [ar_test_digest]
    jne .fail
    lea rdi, [arena_right]
    call ar_test_context_digest
    cmp rax, [ar_test_right_digest]
    jne .fail
    mov rax, [arena_attack_rng]
    cmp rax, [ar_test_garbage_rng]
    jne .fail
    mov rax, [arena_now]
    cmp rax, [ar_test_now]
    jne .fail

    mov qword [ar_test_stage], 6
    ; Fill the ring across its wrap, with a canary immediately after it.
    call arena_init
    mov dword [incoming_head], 60
    mov qword [game_context_end], 0x12345678
    lea rdi, [game_context_begin]
    mov esi, 100
    mov edx, 7
    mov rcx, [arena_now]
    call arena_queue_garbage
    cmp dword [incoming_count], GARBAGE_CAP
    jne .fail
    cmp qword [game_context_end], 0x12345678
    jne .fail
    mov qword [game_context_end], 0

    mov qword [ar_test_stage], 7
    ; The oldest snapshot remains addressable after the history ring wraps.
    call arena_init
    mov byte [arena_phase], ARENA_LIVE
    mov rax, [arena_now]
    mov [arena_live_start], rax
    xor r12d, r12d
.wrap_history:
    mov [score], r12
    call arena_save_left
    call arena_history_capture
    add qword [arena_now], HISTORY_PERIOD
    inc r12d
    cmp r12d, HISTORY_CAP+2
    jb .wrap_history
    cmp dword [arena_history_count], HISTORY_CAP
    jne .fail
    mov dword [arena_replay_index], 0
    mov byte [arena_phase], ARENA_REPLAY
    call arena_branch
    cmp qword [score], 2
    jne .fail
    cmp dword [arena_history_count], 1
    jne .fail
    lea rsi, [ar_test_ok]
    call write_z_stdout
    jmp .done
.fail:
    mov byte [test_failed], 1
    lea r15, [output_buf]
    lea rsi, [ar_test_bad]
    call append_z
    mov rdi, [ar_test_stage]
    call append_u64
    lea rsi, [ai_test_newline]
    call append_z
    lea rsi, [output_buf]
    mov rdx, r15
    sub rdx, rsi
    call write_all_stdout
.done:
    mov byte [arena_mode], 0
    mov byte [arena_simulating], 0
    mov byte [arena_spectator], 0
    pop r15
    pop r12
    pop rbx
    ret

ar_test_context_digest:
    mov rax, 0xcbf29ce484222325
    mov r8, 0x100000001b3
    xor ecx, ecx
.byte:
    cmp ecx, CTX(ai_plan_us)
    jb .hash
    cmp ecx, CTX(ai_plan_us)+8
    jb .next
.hash:
    movzx edx, byte [rdi+rcx]
    xor rax, rdx
    imul rax, r8
.next:
    inc ecx
    cmp ecx, GAME_CONTEXT_SIZE
    jb .byte
    ret
