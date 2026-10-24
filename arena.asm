; Two complete game contexts, one shared assembly engine.
; Both sides advance before attacks are delivered, avoiding same-tick
; cancellation advantages. The match clock is virtual: pause, resize, and
; replay stop it. The scheduler and search profiler still use the wall clock.
%define CTX(x) (x-game_context_begin)
%define ARENA_COUNTDOWN 1
%define ARENA_LIVE 2
%define ARENA_PAUSED 3
%define ARENA_REPLAY 4
%define ARENA_FINISHED 5
%define ARENA_MULTIVERSE 6
%define HISTORY_CAP 128
%define HISTORY_PERIOD 125000000
%define HISTORY_HEADER 64
%define HISTORY_BYTES (HISTORY_HEADER+GAME_CONTEXT_SIZE*2)
%define GARBAGE_WARNING 1500000000

section .rodata
arena_attack_table: dd 0, 1, 2, 4, 6
arena_paces: dq 175000000, 100000000, 50000000

section .data
arena_skill: dd 2
arena_duration: dq 180000000000

section .bss
alignb 8
arena_control_begin:
arena_mode: resb 1
arena_spectator: resb 1
arena_simulating: resb 1
arena_phase: resb 1
arena_return_phase: resb 1
arena_pause_phase: resb 1
arena_winner: resb 1            ; 1 left, 2 right, 3 draw
arena_accounted: resb 1
arena_replay_playing: resb 1
alignb 8
arena_seed: resq 1
arena_now: resq 1
arena_last_wall: resq 1
arena_live_start: resq 1
arena_render_deadline: resq 1
arena_attack_rng: resq 1
arena_event_time: resq 1
arena_event_side: resd 1
arena_event_lines: resd 1
arena_round: resq 1
arena_left_wins: resq 1
arena_right_wins: resq 1
arena_branches: resq 1
arena_history_deadline: resq 1
arena_replay_deadline: resq 1
arena_history_next: resd 1
arena_history_count: resd 1
arena_replay_index: resd 1
alignb 16
arena_control_end:
ARENA_CONTROL_SIZE equ arena_control_end-arena_control_begin
arena_left: resb GAME_CONTEXT_SIZE
arena_right: resb GAME_CONTEXT_SIZE
arena_history: resb HISTORY_CAP*HISTORY_BYTES

section .text
arena_save_left:
    lea rdi, [arena_left]
    jmp arena_save_context
arena_save_right:
    lea rdi, [arena_right]
arena_save_context:
    lea rsi, [game_context_begin]
    mov ecx, GAME_CONTEXT_SIZE/8
    rep movsq
    ret
arena_load_left:
    lea rsi, [arena_left]
    jmp arena_load_context
arena_load_right:
    lea rsi, [arena_right]
arena_load_context:
    lea rdi, [game_context_begin]
    mov ecx, GAME_CONTEXT_SIZE/8
    rep movsq
    ret

arena_init:
    push r12
    cmp qword [arena_seed], 0
    jne .seed
    mov rax, [rng_state]
    test rax, rax
    jnz .store_seed
    mov eax, 42
.store_seed:
    mov [arena_seed], rax
.seed:
    mov rax, [arena_seed]
    mov rdx, 0xd1b54a32d192ed03
    xor rax, rdx
    jnz .attack_seed
    mov eax, 1
.attack_seed:
    mov [arena_attack_rng], rax
    mov qword [arena_now], 1000000000
    mov rax, 4000000000
    mov [arena_live_start], rax
    mov byte [arena_phase], ARENA_COUNTDOWN
    mov byte [arena_winner], 0
    mov byte [arena_accounted], 0
    mov byte [escape_state], 0
    mov qword [arena_branches], 0
    inc qword [arena_round]
    mov dword [arena_history_next], 0
    mov dword [arena_history_count], 0
    mov qword [arena_history_deadline], 0
    mov qword [arena_render_deadline], 0
    mov qword [arena_event_time], 0
    mov dword [arena_event_lines], 0
    xor r12d, r12d
.player:
    lea rdi, [game_context_begin]
    xor eax, eax
    mov ecx, GAME_CONTEXT_SIZE/8
    rep stosq
    mov rax, [arena_seed]
    mov [rng_state], rax
    mov qword [start_level], 1
    mov qword [ai_interval], 75000000
    mov al, [arena_spectator]
    mov [ai_auto], al
    test r12d, r12d
    jz .reset
    mov byte [ai_auto], 1
    mov eax, [arena_skill]
    dec eax
    lea rdx, [arena_paces]
    mov rax, [rdx+rax*8]
    mov [ai_interval], rax
.reset:
    call reset_game
    cmp byte [ai_auto], 0
    je .save
    call ai_plan
.save:
    test r12d, r12d
    jnz .right
    call arena_save_left
    inc r12d
    jmp .player
.right:
    call arena_save_right
    call arena_load_left
    call get_wall_time_ns
    mov [arena_last_wall], rax
    mov byte [dirty], 1
    mov byte [ui_clear], 1
    pop r12
    ret

arena_tick:
    call arena_save_left
    cmp byte [arena_simulating], 0
    jne .simulation
    call get_wall_time_ns
    mov rdx, rax
    sub rdx, [arena_last_wall]
    mov [arena_last_wall], rax
    jmp .clock
.simulation:
    mov edx, FRAME_NS
.clock:
    cmp byte [ui_too_small], 0
    jne .done
    cmp byte [arena_phase], ARENA_MULTIVERSE
    je multiverse_tick
    cmp byte [arena_phase], ARENA_REPLAY
    je arena_replay_tick
    cmp byte [arena_phase], ARENA_PAUSED
    je .done
    cmp byte [arena_phase], ARENA_FINISHED
    je .done
    add [arena_now], rdx
    cmp byte [arena_phase], ARENA_COUNTDOWN
    jne .live
    mov rax, [arena_now]
    cmp rax, [arena_live_start]
    jb .done
    mov [arena_live_start], rax
    mov [last_drop_ns], rax
    mov [ai_deadline], rax
    mov [arena_right+CTX(last_drop_ns)], rax
    mov [arena_right+CTX(ai_deadline)], rax
    mov byte [arena_phase], ARENA_LIVE
.live:
    mov rax, [arena_now]
    sub rax, [arena_live_start]
    cmp rax, [arena_duration]
    jae .time_limit
    call update_horizontal_repeat
    call update_game
    call ai_tick
    mov al, [ai_hint]
    or al, [ai_auto]
    or al, [ai_single]
    jz .save_player
    call ai_ensure_plan
.save_player:
    call arena_save_left
    call arena_load_right
    call update_game
    call ai_tick
    call ai_ensure_plan
    call arena_save_right
    call arena_dispatch
    call arena_load_left
    cmp byte [arena_left+CTX(game_state)], STATE_GAME_OVER
    je .left_out
    cmp byte [arena_right+CTX(game_state)], STATE_GAME_OVER
    jne .capture
    mov byte [arena_winner], 1
    jmp .finish
.left_out:
    mov byte [arena_winner], 2
    cmp byte [arena_right+CTX(game_state)], STATE_GAME_OVER
    jne .finish
    mov byte [arena_winner], 3
    jmp .finish
.time_limit:
    ; At the clock limit, outgoing attack wins; cleared lines break a tie.
    mov rax, [arena_left+CTX(battle_sent)]
    cmp rax, [arena_right+CTX(battle_sent)]
    ja .left_wins
    jb .right_wins
    mov rax, [arena_left+CTX(total_lines)]
    cmp rax, [arena_right+CTX(total_lines)]
    ja .left_wins
    jb .right_wins
    mov byte [arena_winner], 3
    jmp .finish
.left_wins:
    mov byte [arena_winner], 1
    jmp .finish
.right_wins:
    mov byte [arena_winner], 2
.finish:
    mov byte [arena_phase], ARENA_FINISHED
    mov byte [arena_accounted], 1
    cmp byte [arena_winner], 1
    jne .right_award
    inc qword [arena_left_wins]
.right_award:
    cmp byte [arena_winner], 2
    jne .final_frame
    inc qword [arena_right_wins]
.final_frame:
    mov byte [dirty], 1
    cmp byte [mv_building], 0
    jne .done
    call arena_history_capture
    ret
.capture:
    cmp byte [arena_simulating], 0
    jne .done
    mov rax, [arena_now]
    cmp rax, [arena_history_deadline]
    jb .done
    add rax, HISTORY_PERIOD
    mov [arena_history_deadline], rax
    call arena_history_capture
.done:
    ret

; Called after scoring and before spawning. Clear attacks cancel queued rows
; first. Non-clearing locks receive up to eight matured garbage rows.
arena_on_lock:
    cmp byte [arena_mode], 0
    je .done
    push r12
    mov r12d, edi
    xor eax, eax
    test edi, edi
    jz .receive
    lea rdx, [arena_attack_table]
    mov eax, [rdx+rdi*4]
    cmp byte [spin_kind], 2
    jne .mini
    lea eax, [rdi*2]
    jmp .difficult
.mini:
    cmp byte [spin_kind], 1
    jne .normal
    mov eax, edi
    jmp .difficult
.normal:
    cmp edi, 4
    jne .combo
.difficult:
    cmp byte [battle_prior_b2b], 0
    je .combo
    inc eax
.combo:
    mov rdx, [combo]
    test rdx, rdx
    js .perfect
    shr rdx, 1
    mov ecx, 5
    cmp rdx, rcx
    cmova rdx, rcx
    add eax, edx
.perfect:
    push rax
    call board_is_empty
    mov edx, eax
    pop rax
    test edx, edx
    jz .cancel
    add eax, 6
.cancel:
    test eax, eax
    jz .receive
    cmp dword [incoming_count], 0
    je .send
    dec dword [incoming_count]
    inc dword [incoming_head]
    and dword [incoming_head], GARBAGE_CAP-1
    inc qword [battle_cancelled]
    dec eax
    jmp .cancel
.send:
    add [battle_outbox], eax
    add [battle_sent], rax
.receive:
    test r12d, r12d
    jnz .return
    call arena_receive_garbage
.return:
    pop r12
.done:
    ret

arena_receive_garbage:
    push rbx
    push r12
    mov r12d, 8
.row:
    cmp dword [incoming_count], 0
    je .done
    mov ebx, [incoming_head]
    lea rdx, [incoming_due]
    mov rax, [arena_now]
    cmp rax, [rdx+rbx*8]
    jb .done
    lea rsi, [board]
    mov ecx, BOARD_W
.overflow:
    cmp byte [rsi], 0
    jne .topout
    inc rsi
    loop .overflow
    lea rdi, [board]
    lea rsi, [board+BOARD_W]
    mov ecx, BOARD_SIZE-BOARD_W
    rep movsb
    mov al, CELL_GARBAGE
    mov ecx, BOARD_W
    rep stosb
    lea rdx, [incoming_holes]
    movzx eax, byte [rdx+rbx]
    lea rdx, [board+BOARD_SIZE-BOARD_W]
    mov byte [rdx+rax], 0
    inc dword [incoming_head]
    and dword [incoming_head], GARBAGE_CAP-1
    dec dword [incoming_count]
    inc qword [battle_received]
    mov byte [flash_count], 0
    mov byte [ai_cached], 0
    dec r12d
    jnz .row
    jmp .done
.topout:
    mov byte [game_state], STATE_GAME_OVER
.done:
    pop r12
    pop rbx
    ret

; Queue bounded individual rows: rdi=context, esi=count, edx=hole,
; rcx=virtual arrival deadline. Extra rows beyond the 64-row cap are ignored.
arena_queue_garbage:
    mov r8d, [rdi+CTX(incoming_count)]
.row:
    test esi, esi
    jz .done
    cmp r8d, GARBAGE_CAP
    jae .done
    mov eax, [rdi+CTX(incoming_head)]
    add eax, r8d
    and eax, GARBAGE_CAP-1
    mov [rdi+CTX(incoming_holes)+rax], dl
    mov [rdi+CTX(incoming_due)+rax*8], rcx
    inc r8d
    dec esi
    jmp .row
.done:
    mov [rdi+CTX(incoming_count)], r8d
    ret

arena_dispatch:
    push r12
    push r13
    xor r12d, r12d
.side:
    lea r13, [arena_left]
    test r12d, r12d
    jz .outbox
    lea r13, [arena_right]
.outbox:
    cmp dword [r13+CTX(battle_outbox)], 0
    je .next
    call arena_random_hole
    mov edx, eax
    mov esi, [r13+CTX(battle_outbox)]
    mov dword [r13+CTX(battle_outbox)], 0
    mov [arena_event_lines], esi
    mov [arena_event_side], r12d
    mov rcx, [arena_now]
    mov [arena_event_time], rcx
    add rcx, GARBAGE_WARNING
    lea rdi, [arena_right]
    test r12d, r12d
    jz .deliver
    lea rdi, [arena_left]
.deliver:
    call arena_queue_garbage
    mov byte [dirty], 1
.next:
    inc r12d
    cmp r12d, 2
    jb .side
    pop r13
    pop r12
    ret

arena_random_hole:
    mov rax, [arena_attack_rng]
    mov rdx, rax
    shl rdx, 13
    xor rax, rdx
    mov rdx, rax
    shr rdx, 7
    xor rax, rdx
    mov rdx, rax
    shl rdx, 17
    xor rax, rdx
    mov [arena_attack_rng], rax
    ; Reject the six values below 6 to remove modulo-ten bias.
    cmp rax, 6
    jb arena_random_hole
    xor edx, edx
    mov ecx, 10
    div rcx
    mov eax, edx
    ret

; Returns eax=1 if the arena consumed the key, zero for ordinary game input.
arena_key:
    cmp byte [arena_mode], 0
    je .pass
    mov eax, edi
    and al, 0xdf
    cmp al, 'Q'
    je .pass
    cmp dil, 3
    je .pass
    cmp al, 'R'
    je .restart
    cmp byte [arena_phase], ARENA_MULTIVERSE
    je multiverse_key
    cmp al, 'M'
    je .multiverse
    cmp al, 'V'
    je .replay
    cmp byte [arena_phase], ARENA_REPLAY
    je .replay_key
    cmp al, 'P'
    je .pause
    cmp dil, '1'
    jb .phase
    cmp dil, '9'
    ja .phase
    cmp dil, '3'
    ja .consumed
    movzx eax, dil
    sub eax, '0'
    mov [arena_skill], eax
    dec eax
    lea rdx, [arena_paces]
    mov rax, [rdx+rax*8]
    mov [arena_right+CTX(ai_interval)], rax
    mov byte [dirty], 1
    jmp .consumed
.phase:
    cmp byte [arena_phase], ARENA_LIVE
    jne .consumed
.pass:
    xor eax, eax
    ret
.restart:
    call arena_init
    jmp .consumed
.multiverse:
    call multiverse_enter
    jmp .consumed
.pause:
    cmp byte [arena_phase], ARENA_FINISHED
    je .consumed
    cmp byte [arena_phase], ARENA_PAUSED
    je .resume
    mov al, [arena_phase]
    mov [arena_pause_phase], al
    mov byte [arena_phase], ARENA_PAUSED
    jmp .redraw
.resume:
    mov al, [arena_pause_phase]
    mov [arena_phase], al
    call get_wall_time_ns
    mov [arena_last_wall], rax
    jmp .redraw
.replay:
    cmp byte [arena_phase], ARENA_REPLAY
    je .leave_replay
    cmp dword [arena_history_count], 0
    je .consumed
    call arena_save_left
    mov al, [arena_phase]
    mov [arena_return_phase], al
    mov byte [arena_phase], ARENA_REPLAY
    mov byte [arena_replay_playing], 1
    mov eax, [arena_history_count]
    sub eax, 80
    jns .index
    xor eax, eax
.index:
    mov [arena_replay_index], eax
    mov qword [arena_replay_deadline], 0
    jmp .redraw
.leave_replay:
    mov al, [arena_return_phase]
    mov [arena_phase], al
    call get_wall_time_ns
    mov [arena_last_wall], rax
    jmp .redraw
.replay_key:
    cmp dil, 13
    je .branch
    cmp dil, 10
    je .branch
    cmp dil, ' '
    je .play_pause
    cmp al, 'P'
    jne .consumed
.play_pause:
    xor byte [arena_replay_playing], 1
    jmp .redraw
.branch:
    call arena_branch
.redraw:
    mov byte [dirty], 1
.consumed:
    mov eax, 1
    ret

arena_arrow:
    cmp byte [arena_mode], 0
    je .pass
    cmp byte [arena_phase], ARENA_MULTIVERSE
    je multiverse_arrow
    cmp byte [arena_phase], ARENA_LIVE
    je .pass
    cmp byte [arena_phase], ARENA_REPLAY
    jne .consume
    mov byte [arena_replay_playing], 0
    cmp dil, 'D'
    je .back
    cmp dil, 'C'
    jne .consume
    mov eax, [arena_replay_index]
    inc eax
    cmp eax, [arena_history_count]
    jae .consume
    mov [arena_replay_index], eax
    jmp .consume
.back:
    cmp dword [arena_replay_index], 0
    je .consume
    dec dword [arena_replay_index]
.consume:
    mov byte [dirty], 1
    mov eax, 1
    ret
.pass:
    xor eax, eax
    ret

arena_history_capture:
    mov eax, [arena_history_next]
    imul eax, eax, HISTORY_BYTES
    lea rdi, [arena_history]
    add rdi, rax
    call arena_write_snapshot
    inc dword [arena_history_next]
    and dword [arena_history_next], HISTORY_CAP-1
    cmp dword [arena_history_count], HISTORY_CAP
    jae .done
    inc dword [arena_history_count]
.done:
    ret

; rdi = a HISTORY_BYTES buffer. Also used by isolated future simulations.
arena_write_snapshot:
    mov qword [rdi+52], 0
    mov dword [rdi+60], 0
    mov rax, [arena_now]
    mov [rdi], rax
    sub rax, [arena_live_start]
    mov [rdi+8], rax
    mov rax, [arena_attack_rng]
    mov [rdi+16], rax
    mov rax, [arena_event_time]
    mov [rdi+24], rax
    mov eax, [arena_event_side]
    mov [rdi+32], eax
    mov eax, [arena_event_lines]
    mov [rdi+36], eax
    movzx eax, byte [arena_phase]
    mov [rdi+40], eax
    movzx eax, byte [arena_winner]
    mov [rdi+44], eax
    mov eax, [arena_skill]
    mov [rdi+48], eax
    add rdi, HISTORY_HEADER
    lea rsi, [arena_left]
    mov ecx, GAME_CONTEXT_SIZE/8
    rep movsq
    lea rsi, [arena_right]
    mov ecx, GAME_CONTEXT_SIZE/8
    rep movsq
    ret

; Logical replay index -> rax = immutable snapshot pointer.
arena_history_pointer:
    mov eax, [arena_history_next]
    sub eax, [arena_history_count]
    add eax, [arena_replay_index]
    and eax, HISTORY_CAP-1
    imul eax, eax, HISTORY_BYTES
    lea rdx, [arena_history]
    add rax, rdx
    ret

arena_replay_tick:
    cmp byte [arena_replay_playing], 0
    je .done
    call get_wall_time_ns
    cmp rax, [arena_replay_deadline]
    jb .done
    add rax, HISTORY_PERIOD
    mov [arena_replay_deadline], rax
    mov eax, [arena_replay_index]
    inc eax
    cmp eax, [arena_history_count]
    jae .end
    mov [arena_replay_index], eax
    mov byte [dirty], 1
    ret
.end:
    mov byte [arena_replay_playing], 0
.done:
    ret

; Fork the match from an earlier live snapshot. Both random streams, paths,
; lock timers, and garbage queues are restored. Future history is discarded.
arena_branch:
    push r12
    call arena_history_pointer
    mov r12, rax
    cmp byte [r12+HISTORY_HEADER+CTX(game_state)], STATE_PLAYING
    jne .done
    cmp byte [r12+HISTORY_HEADER+GAME_CONTEXT_SIZE+CTX(game_state)], STATE_PLAYING
    jne .done
    cmp dword [r12+40], ARENA_LIVE
    jne .done
    cmp byte [arena_accounted], 0
    je .restore
    cmp byte [arena_winner], 1
    jne .undo_right
    dec qword [arena_left_wins]
.undo_right:
    cmp byte [arena_winner], 2
    jne .restore
    dec qword [arena_right_wins]
.restore:
    mov rax, [r12]
    mov [arena_now], rax
    sub rax, [r12+8]
    mov [arena_live_start], rax
    mov rax, [r12+16]
    mov [arena_attack_rng], rax
    mov rax, [r12+24]
    mov [arena_event_time], rax
    mov eax, [r12+32]
    mov [arena_event_side], eax
    mov eax, [r12+36]
    mov [arena_event_lines], eax
    mov eax, [r12+48]
    mov [arena_skill], eax
    lea rsi, [r12+HISTORY_HEADER]
    lea rdi, [arena_left]
    mov ecx, GAME_CONTEXT_SIZE/8
    rep movsq
    lea rdi, [arena_right]
    mov ecx, GAME_CONTEXT_SIZE/8
    rep movsq
    mov eax, [arena_history_next]
    sub eax, [arena_history_count]
    mov edx, [arena_replay_index]
    inc edx
    add eax, edx
    and eax, HISTORY_CAP-1
    mov [arena_history_next], eax
    mov [arena_history_count], edx
    mov byte [arena_phase], ARENA_LIVE
    mov byte [arena_winner], 0
    mov byte [arena_accounted], 0
    inc qword [arena_branches]
    mov rax, [arena_now]
    add rax, HISTORY_PERIOD
    mov [arena_history_deadline], rax
    call arena_load_left
    call get_wall_time_ns
    mov [arena_last_wall], rax
.done:
    pop r12
    ret
