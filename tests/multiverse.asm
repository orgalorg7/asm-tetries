section .rodata
mv_test_ok: db "Multiverse: isolation, distinct roots, exact futures, jump, terminal branches: PASS",10,0
mv_test_bad: db "Multiverse regression: FAIL at stage ",0
section .bss
alignb 8
mv_test_stage: resq 1
mv_test_history: resb HISTORY_CAP*HISTORY_BYTES
section .text
run_multiverse_tests:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov byte [arena_mode], 1
    mov byte [arena_simulating], 1
    mov byte [arena_spectator], 1
    mov qword [arena_seed], 2026
    call arena_init
    call multiverse_warmup
    mov qword [mv_test_stage], 1
    lea rsi, [arena_history]
    lea rdi, [mv_test_history]
    mov ecx, HISTORY_CAP*HISTORY_BYTES/8
    rep movsq
    call multiverse_build
    cmp dword [mv_count], 3
    jne .fail
    ; Building must leave ALL session controls, both contexts, and history
    ; byte-identical, including profiler bytes, RNG, deadlines, and AI paths.
    lea rsi, [arena_control_begin]
    lea rdi, [mv_origin_controls]
    mov ecx, ARENA_CONTROL_SIZE
    repe cmpsb
    jne .fail
    lea rsi, [arena_left]
    lea rdi, [mv_origin_left]
    mov ecx, GAME_CONTEXT_SIZE*2
    repe cmpsb
    jne .fail
    lea rsi, [game_context_begin]
    lea rdi, [mv_origin_left]
    mov ecx, GAME_CONTEXT_SIZE
    repe cmpsb
    jne .fail
    lea rsi, [arena_history]
    lea rdi, [mv_test_history]
    mov ecx, HISTORY_CAP*HISTORY_BYTES
    repe cmpsb
    jne .fail

    mov qword [mv_test_stage], 2
    ; Each branch has a distinct, legal first landing (beam insertion already
    ; deduplicates equal occupied-cell sets across rotational symmetries).
    xor r12d, r12d
.root:
    mov edi, r12d
    xor esi, esi
    call multiverse_pointer
    lea rbx, [rax+HISTORY_HEADER]
    mov edi, [rbx+CTX(ai_goal_type)]
    mov esi, [rbx+CTX(ai_goal_x)]
    mov edx, [rbx+CTX(ai_goal_y)]
    mov ecx, [rbx+CTX(ai_goal_rot)]
    lea r11, [rbx+CTX(board)]
    ; can_place_on_board takes x, y, type, rotation.
    xchg edi, esi
    xchg esi, edx
    call can_place_on_board
    test eax, eax
    jz .fail
    mov eax, [rbx+CTX(ai_goal_x)]
    mov edx, [rbx+CTX(ai_goal_rot)]
    shl rdx, 32
    or rax, rdx
    test r12d, r12d
    jnz .other
    mov r13, rax
    jmp .next_root
.other:
    cmp rax, r13
    je .fail
    cmp r12d, 1
    jne .third
    mov r14, rax
    jmp .next_root
.third:
    cmp rax, r14
    je .fail
.next_root:
    inc r12d
    cmp r12d, MV_BRANCHES
    jb .root

    mov qword [mv_test_stage], 3
    ; Independently run every saved starting route for 8 seconds. The result
    ; must match BOTH predicted contexts, virtual time, and garbage RNG.
    xor r12d, r12d
.future:
    call multiverse_restore_origin
    mov edi, r12d
    xor esi, esi
    call multiverse_pointer
    mov rdi, rax
    call multiverse_load_frame
    mov byte [arena_simulating], 1
    mov byte [mv_building], 1
    mov r14d, (MV_FRAMES-1)*MV_TICKS_PER_FRAME
.tick:
    call arena_tick
    dec r14d
    jnz .tick
    mov edi, r12d
    mov esi, MV_FRAMES-1
    call multiverse_pointer
    mov r13, rax
    mov rax, [arena_now]
    cmp rax, [r13]
    jne .fail
    mov rax, [arena_attack_rng]
    cmp rax, [r13+16]
    jne .fail
    lea rdi, [arena_left]
    call ar_test_context_digest
    mov rbx, rax
    lea rdi, [r13+HISTORY_HEADER]
    call ar_test_context_digest
    cmp rax, rbx
    jne .fail
    lea rdi, [arena_right]
    call ar_test_context_digest
    mov rbx, rax
    lea rdi, [r13+HISTORY_HEADER+GAME_CONTEXT_SIZE]
    call ar_test_context_digest
    cmp rax, rbx
    jne .fail
    inc r12d
    cmp r12d, MV_BRANCHES
    jb .future
    mov byte [mv_building], 0

    mov qword [mv_test_stage], 4
    call multiverse_restore_origin
    mov byte [arena_phase], ARENA_MULTIVERSE
    mov dword [mv_selected], 2
    mov dword [mv_cursor], 37
    call multiverse_jump
    cmp byte [arena_phase], ARENA_LIVE
    jne .fail
    cmp qword [arena_branches], 1
    jne .fail
    cmp dword [arena_history_count], 38
    jne .fail
    mov edi, 2
    mov esi, 37
    call multiverse_pointer
    mov r13, rax
    lea rsi, [r13+HISTORY_HEADER]
    lea rdi, [arena_left]
    mov ecx, GAME_CONTEXT_SIZE*2
    repe cmpsb
    jne .fail
    mov rax, [arena_attack_rng]
    cmp rax, [r13+16]
    jne .fail
    mov rax, [arena_now]
    cmp rax, [r13]
    jne .fail

    mov qword [mv_test_stage], 5
    ; A predicted match ending must not award a real win or write history.
    mov qword [arena_duration], 1000000
    call multiverse_build
    lea rsi, [arena_control_begin]
    lea rdi, [mv_origin_controls]
    mov ecx, ARENA_CONTROL_SIZE
    repe cmpsb
    jne .fail
    mov byte [arena_phase], ARENA_MULTIVERSE
    mov dword [mv_cursor], MV_FRAMES-1
    mov dword [mv_selected], 0
    call multiverse_jump
    cmp byte [arena_phase], ARENA_MULTIVERSE
    jne .fail
    call multiverse_leave
    cmp byte [arena_phase], ARENA_LIVE
    jne .fail

    mov qword [mv_test_stage], 6
    ; An O piece in a two-column shaft has exactly one distinct landing.
    ; Unused branch storage must remain untouched, and selection wraps to 0.
    mov rax, 180000000000
    mov [arena_duration], rax
    call arena_init
    mov byte [arena_phase], ARENA_LIVE
    mov rax, [arena_now]
    mov [arena_live_start], rax
    lea rdi, [board]
    mov al, CELL_GARBAGE
    mov ecx, BOARD_SIZE
    rep stosb
    lea rdi, [board+4]
    mov ecx, BOARD_H
.shaft:
    mov word [rdi], 0
    add rdi, BOARD_W
    loop .shaft
    mov dword [piece_type], 1
    mov dword [piece_rot], 0
    mov dword [piece_x], 3
    mov dword [piece_y], -1
    mov rax, 0x123456789abcdef0
    mov [mv_frames+MV_BRANCH_BYTES], rax
    call multiverse_build
    cmp dword [mv_count], 1
    jne .fail
    mov rax, 0x123456789abcdef0
    cmp [mv_frames+MV_BRANCH_BYTES], rax
    jne .fail
    mov dword [mv_selected], 0
    mov edi, 'C'
    call multiverse_arrow
    cmp dword [mv_selected], 0
    jne .fail

    mov qword [mv_test_stage], 7
    ; An unreachable active piece offers no forecasts and consumes no override.
    mov byte [board+4], CELL_GARBAGE
    mov dword [ai_variant], 2
    call multiverse_enter
    cmp dword [mv_count], 0
    jne .fail
    cmp dword [ai_variant], 0
    jne .fail
    cmp byte [arena_phase], ARENA_LIVE
    jne .fail
    lea rsi, [mv_test_ok]
    call write_z_stdout
    jmp .done
.fail:
    mov byte [test_failed], 1
    lea r15, [output_buf]
    lea rsi, [mv_test_bad]
    call append_z
    mov rdi, [mv_test_stage]
    call append_u64
    lea rsi, [ai_test_newline]
    call append_z
    lea rsi, [output_buf]
    mov rdx, r15
    sub rdx, rsi
    call write_all_stdout
.done:
    mov rax, 180000000000
    mov [arena_duration], rax
    mov byte [arena_mode], 0
    mov byte [arena_simulating], 0
    mov byte [arena_spectator], 0
    mov byte [mv_building], 0
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
