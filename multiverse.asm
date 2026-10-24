; Three counterfactual matches, all starting from one frozen live position.
; Only the first reachable placement differs; subsequent play uses the same
; copilot, physics, piece stream, and attack rules. Every frame stores BOTH
; complete players. Forecasting borrows the engine and restores its owner.
%define MV_BRANCHES 3
%define MV_FRAMES 65
%define MV_TICKS_PER_FRAME 5
%define MV_BRANCH_BYTES (MV_FRAMES*HISTORY_BYTES)
%define MV_PLAY_PERIOD 62500000

section .bss
mv_startup: resb 1
mv_building: resb 1
mv_playing: resb 1
alignb 8
mv_count: resd 1
mv_selected: resd 1
mv_cursor: resd 1
mv_origin_skill: resd 1
mv_deadline: resq 1
mv_build_ms: resq 1
mv_origin_controls: resb ARENA_CONTROL_SIZE
mv_origin_left: resb GAME_CONTEXT_SIZE
mv_origin_right: resb GAME_CONTEXT_SIZE
mv_frames: resb MV_BRANCHES*MV_BRANCH_BYTES

section .text
; A showcase begins in a real, deterministically played 30-second battle.
; It skips waiting for the countdown, then returns to the normal wall clock.
multiverse_warmup:
    push r12
    mov byte [mv_startup], 0
    movzx r12d, byte [arena_simulating]
    push r12
    mov byte [arena_simulating], 1
    mov byte [arena_phase], ARENA_LIVE
    mov rax, [arena_now]
    mov [arena_live_start], rax
    mov r12d, 1200
.tick:
    call multiverse_save_origin
    call arena_tick
    cmp byte [arena_phase], ARENA_FINISHED
    je .last_living
    dec r12d
    jnz .tick
    jmp .ready
.last_living:
    call multiverse_restore_origin
.ready:
    call arena_history_capture
    pop rax
    mov [arena_simulating], al
    call get_wall_time_ns
    mov [arena_last_wall], rax
    pop r12
    ret

multiverse_save_origin:
    call arena_save_left
    lea rsi, [arena_control_begin]
    lea rdi, [mv_origin_controls]
    mov ecx, ARENA_CONTROL_SIZE/8
    rep movsq
    lea rsi, [arena_left]
    lea rdi, [mv_origin_left]
    mov ecx, GAME_CONTEXT_SIZE*2/8
    rep movsq
    mov eax, [arena_skill]
    mov [mv_origin_skill], eax
    ret

multiverse_restore_origin:
    lea rsi, [mv_origin_controls]
    lea rdi, [arena_control_begin]
    mov ecx, ARENA_CONTROL_SIZE/8
    rep movsq
    lea rsi, [mv_origin_left]
    lea rdi, [arena_left]
    mov ecx, GAME_CONTEXT_SIZE*2/8
    rep movsq
    mov eax, [mv_origin_skill]
    mov [arena_skill], eax
    jmp arena_load_left

; edi=branch, esi=frame -> rax=immutable full-match snapshot.
multiverse_pointer:
    imul eax, edi, MV_BRANCH_BYTES
    imul edx, esi, HISTORY_BYTES
    add eax, edx
    lea rdx, [mv_frames]
    add rax, rdx
    ret

; Restore a forecast frame to run the shared engine. Session wins/history
; remain owned by the origin and are restored after every speculative run.
; rdi=snapshot, does not alter history or award a win.
multiverse_load_frame:
    mov rdx, rdi
    mov rax, [rdx]
    mov [arena_now], rax
    sub rax, [rdx+8]
    mov [arena_live_start], rax
    mov rax, [rdx+16]
    mov [arena_attack_rng], rax
    mov rax, [rdx+24]
    mov [arena_event_time], rax
    mov eax, [rdx+32]
    mov [arena_event_side], eax
    mov eax, [rdx+36]
    mov [arena_event_lines], eax
    mov eax, [rdx+40]
    mov [arena_phase], al
    mov eax, [rdx+44]
    mov [arena_winner], al
    mov eax, [rdx+48]
    mov [arena_skill], eax
    lea rsi, [rdx+HISTORY_HEADER]
    lea rdi, [arena_left]
    mov ecx, GAME_CONTEXT_SIZE*2/8
    rep movsq
    jmp arena_load_left

multiverse_build:
    push r12
    push r13
    push r14
    call get_wall_time_ns
    mov [mv_build_ms], rax
    call multiverse_save_origin
    mov byte [mv_building], 1
    mov dword [mv_count], MV_BRANCHES
    xor r12d, r12d
.roots:
    call multiverse_restore_origin
    mov byte [arena_phase], ARENA_LIVE
    mov byte [arena_simulating], 1
    mov byte [ai_auto], 1
    mov byte [ai_single], 0
    mov byte [assisted_run], 1
    mov byte [das_active], 0
    mov dword [horizontal_dir], 0
    mov [ai_variant], r12d
    call ai_plan
    cmp byte [ai_valid], 0
    je .unreachable
    mov eax, [ai_beam_count]
    cmp eax, [mv_count]
    jae .root_ready
    mov [mv_count], eax
.root_ready:
    call arena_save_left
    mov edi, r12d
    xor esi, esi
    call multiverse_pointer
    mov rdi, rax
    call arena_write_snapshot
    inc r12d
    cmp r12d, [mv_count]
    jb .roots
    xor r12d, r12d
.branch:
    call multiverse_restore_origin
    mov edi, r12d
    xor esi, esi
    call multiverse_pointer
    mov rdi, rax
    call multiverse_load_frame
    mov byte [arena_simulating], 1
    mov r13d, 1
.frame:
    mov r14d, MV_TICKS_PER_FRAME
.tick:
    call arena_tick
    dec r14d
    jnz .tick
    mov edi, r12d
    mov esi, r13d
    call multiverse_pointer
    mov rdi, rax
    call arena_write_snapshot
    inc r13d
    cmp r13d, MV_FRAMES
    jb .frame
    inc r12d
    cmp r12d, [mv_count]
    jb .branch
    jmp .restore
.unreachable:
    mov [mv_count], r12d
.restore:
    call multiverse_restore_origin
    mov byte [mv_building], 0
    call get_wall_time_ns
    sub rax, [mv_build_ms]
    xor edx, edx
    mov ecx, 1000000
    div rcx
    mov [mv_build_ms], rax
    pop r14
    pop r13
    pop r12
    ret

multiverse_enter:
    cmp byte [arena_phase], ARENA_LIVE
    je .build
    cmp byte [arena_phase], ARENA_PAUSED
    jne .done
    cmp byte [arena_pause_phase], ARENA_LIVE
    jne .done
.build:
    cmp byte [ui_too_small], 0
    jne .done
    call multiverse_build
    call get_wall_time_ns
    mov [arena_last_wall], rax
    cmp dword [mv_count], 0
    je .done
    mov byte [arena_phase], ARENA_MULTIVERSE
    mov dword [mv_selected], 0
    mov dword [mv_cursor], 0
    mov byte [mv_playing], 1
    mov qword [mv_deadline], 0
    mov byte [dirty], 1
    mov byte [ui_clear], 1
.done:
    ret

multiverse_leave:
    call multiverse_restore_origin
    call get_wall_time_ns
    mov [arena_last_wall], rax
    mov byte [dirty], 1
    mov byte [ui_clear], 1
    ret

; Only a living frame can become a new timeline. The ordinary replay branch
; operation restores everything, including the opponent and garbage RNG.
multiverse_jump:
    push r12
    mov edi, [mv_selected]
    mov esi, [mv_cursor]
    call multiverse_pointer
    cmp dword [rax+40], ARENA_LIVE
    jne .done
    cmp byte [rax+HISTORY_HEADER+CTX(game_state)], STATE_PLAYING
    jne .done
    cmp byte [rax+HISTORY_HEADER+GAME_CONTEXT_SIZE+CTX(game_state)], STATE_PLAYING
    jne .done
    call multiverse_restore_origin
    mov edi, [mv_selected]
    xor esi, esi
    call multiverse_pointer
    mov rsi, rax
    lea rdi, [arena_history]
    mov eax, [mv_cursor]
    inc eax
    mov [arena_history_next], eax
    mov [arena_history_count], eax
    imul ecx, eax, HISTORY_BYTES/8
    rep movsq
    mov eax, [mv_cursor]
    mov [arena_replay_index], eax
    call arena_branch
    mov byte [dirty], 1
    mov byte [ui_clear], 1
.done:
    pop r12
    ret

multiverse_tick:
    cmp byte [mv_playing], 0
    je .done
    call get_wall_time_ns
    cmp rax, [mv_deadline]
    jb .done
    add rax, MV_PLAY_PERIOD
    cmp dword [mv_cursor], MV_FRAMES-1
    jb .advance
    mov dword [mv_cursor], 0
    jmp .deadline
.advance:
    inc dword [mv_cursor]
    cmp dword [mv_cursor], MV_FRAMES-1
    jne .deadline
    add rax, 1500000000
.deadline:
    mov [mv_deadline], rax
    mov byte [dirty], 1
.done:
    ret

; Arena dispatch already handled Q, Ctrl+C, and R. Everything else is
; consumed here so preview controls cannot mutate the frozen human board.
multiverse_key:
    mov eax, edi
    and al, 0xdf
    cmp al, 'M'
    je .leave
    cmp dil, 13
    je .jump
    cmp dil, 10
    je .jump
    cmp dil, ' '
    je .toggle
    cmp al, 'P'
    je .toggle
    cmp dil, '['
    je .back
    cmp dil, ']'
    je .forward
    sub edi, '1'
    cmp edi, [mv_count]
    jae .done
    mov [mv_selected], edi
    jmp .done
.back:
    mov edi, 'B'
    jmp multiverse_arrow
.forward:
    mov edi, 'A'
    jmp multiverse_arrow
.toggle:
    xor byte [mv_playing], 1
    mov qword [mv_deadline], 0
    jmp .done
.leave:
    call multiverse_leave
    jmp .done
.jump:
    call multiverse_jump
.done:
    mov byte [dirty], 1
    mov eax, 1
    ret

multiverse_arrow:
    cmp dil, 'C'
    je .right
    cmp dil, 'D'
    je .left
    mov byte [mv_playing], 0
    cmp dil, 'A'
    je .forward
    cmp dil, 'B'
    jne .done
    cmp dword [mv_cursor], 0
    je .done
    dec dword [mv_cursor]
    jmp .done
.forward:
    cmp dword [mv_cursor], MV_FRAMES-1
    jae .done
    inc dword [mv_cursor]
    jmp .done
.right:
    mov eax, [mv_selected]
    inc eax
    cmp eax, [mv_count]
    jb .select
    xor eax, eax
    jmp .select
.left:
    mov eax, [mv_selected]
    dec eax
    jns .select
    mov eax, [mv_count]
    dec eax
.select:
    mov [mv_selected], eax
.done:
    mov byte [dirty], 1
    mov eax, 1
    ret
