; Rendering consumes immutable contexts, including historical snapshots.
; It never context-switches the live game or calls a gameplay transformation.
section .rodata
ar_sync: db 27,"[?2026h",27,"[H",0
ar_sync_end: db 27,"[0m",27,"[J",27,"[?2026l",0
ar_center: db 27,"[28G",27,"[K",27,"[0;38;5;245m",0
ar_erase_tail: db 27,"[K",0
ar_right: db 27,"[55G",0
ar_human: db 27,"[1;38;5;117m  YOU / HUMAN",27,"[0m",0
ar_pilot: db 27,"[1;38;5;117m  YOU / AUTOPILOT",27,"[0m",0
ar_title: db 27,"[1;38;5;231mA S T R A  A R E N A",27,"[0m",0
ar_cpu: db 27,"[1;38;5;204m  CPU / LEVEL ",0
ar_round: db "ROUND ",0
ar_branch: db "  /  BRANCH ",0
ar_bottom: db 27,"[38;5;240m  └────────────────────┘",27,"[0m",0
ar_bottom_center: db 27,"[38;5;240mCPU ONLY. PURE ASSEMBLY.",0
ar_footer: db 27,"[38;5;245m  Arrows move  W/Z turn  Space drop  C hold  V replay  R rematch  Q quit",0
ar_small: db 27,"[H",27,"[0mASTRA ARENA",27,"[K",13,10
    db "Resize to 80 x 24.",27,"[K",13,10
    db "Both games suspended.",27,"[K",13,10,"Q quits.",0
ar_clock: db "TIME LEFT   ",27,"[1;38;5;231m",0
ar_labels: db 27,"[38;5;117m       YOU",27,"[38;5;245m  :  ",27,"[38;5;204mCPU",0
ar_score: db "SCORE  ",0
ar_lines: db "LINES  ",0
ar_sent: db "ATTACK ",0
ar_cancel: db "DENIED ",0
ar_next: db "NEXT   ",0
ar_hold: db "HOLD   ",0
ar_pair: db 27,"[38;5;245m : ",27,"[38;5;204m",0
ar_left_color: db 27,"[38;5;117m",0
ar_right_color: db 27,"[38;5;204m",0
ar_incoming: db "INCOMING / 1.5s WARNING",0
ar_you_bar: db 27,"[38;5;117mYOU [",0
ar_cpu_bar: db 27,"[38;5;204mCPU [",0
ar_bar_end: db 27,"[38;5;245m] ",0
ar_bar_empty: db 27,"[38;5;238m",0
ar_bar_urgent: db 27,"[1;38;5;221m",0
ar_attack_right: db 27,"[1;38;5;117m────── ",0
ar_attack_right_end: db " ROWS ─────▶",27,"[0m",0
ar_attack_left: db 27,"[1;38;5;204m◀───── ",0
ar_attack_left_end: db " ROWS ──────",27,"[0m",0
ar_ready: db 27,"[1;38;5;221mGET READY / ",0
ar_live: db 27,"[1;38;5;114mBATTLE / LIVE",27,"[0m",0
ar_pause: db 27,"[1;38;5;221mPAUSED / P TO RESUME",27,"[0m",0
ar_win: db 27,"[1;38;5;117mYOU WIN",27,"[0m",0
ar_loss: db 27,"[1;38;5;204mCPU WINS",27,"[0m",0
ar_draw: db 27,"[1;38;5;221mDRAW",27,"[0m",0
ar_replay: db 27,"[1;38;5;183mREPLAY / PLAYING",27,"[0m",0
ar_replay_frozen: db 27,"[1;38;5;183mREPLAY / FROZEN",27,"[0m",0
ar_rule: db "FIRST TOP-OUT LOSES",0
ar_result_help: db "V replay / R rematch",0
ar_frame: db "FRAME ",0
ar_slash: db " / ",0
ar_match: db "WINS   ",0
ar_controls: db "B auto   H hint   N assist",0
ar_replay_controls: db "← → seek   SPACE playback",0
ar_time_travel: db "M futures    V replay",0
ar_fork: db "ENTER resume from here",0
ar_difficulty: db "1 / 2 / 3  CPU difficulty",0
ar_return: db "V return to live match",0
ar_pause_help: db "P pause    R rematch",0
ar_center_rows: dq ar_render_center.clock, ar_render_center.labels
    dq ar_render_center.score, ar_render_center.lines, ar_render_center.sent
    dq ar_render_center.next, ar_render_center.hold, ar_render_center.incoming
    dq ar_render_center.you_bar, ar_render_center.cpu_bar, ar_render_center.cancelled
    dq ar_render_center.blank, ar_render_center.attack, ar_render_center.phase
    dq ar_render_center.explain, ar_render_center.wins, ar_render_center.controls
    dq ar_render_center.replay_key, ar_render_center.difficulty, ar_render_center.pause_key

section .bss
alignb 8
arena_view_left: resq 1
arena_view_right: resq 1
arena_view_now: resq 1
arena_view_elapsed: resq 1
arena_view_event: resq 1
arena_view_side: resd 1
arena_view_lines: resd 1
arena_view_skill: resd 1
arena_display_left: resb BOARD_SIZE
arena_display_right: resb BOARD_SIZE

section .text
arena_maybe_render:
    call get_wall_time_ns
    cmp byte [dirty], 0
    jne .render
    cmp rax, [arena_render_deadline]
    jb .done
.render:
    add rax, 50000000
    mov [arena_render_deadline], rax
    jmp arena_render
.done:
    ret

arena_render:
    cmp byte [arena_phase], ARENA_MULTIVERSE
    jne .arena
    cmp byte [ui_too_small], 0
    je multiverse_render
.arena:
    push rbx
    push r12
    push r13
    push r14
    push r15
    lea r15, [output_buf]
    call ui_clear_if_needed
    lea rsi, [ar_sync]
    call append_z
    cmp byte [ui_too_small], 0
    jne .small
    lea rax, [arena_left]
    mov [arena_view_left], rax
    lea rax, [arena_right]
    mov [arena_view_right], rax
    mov rax, [arena_now]
    mov [arena_view_now], rax
    sub rax, [arena_live_start]
    jns .elapsed
    xor eax, eax
.elapsed:
    mov [arena_view_elapsed], rax
    mov rax, [arena_event_time]
    mov [arena_view_event], rax
    mov eax, [arena_event_side]
    mov [arena_view_side], eax
    mov eax, [arena_event_lines]
    mov [arena_view_lines], eax
    mov eax, [arena_skill]
    mov [arena_view_skill], eax
    cmp byte [arena_phase], ARENA_REPLAY
    jne .compose
    call arena_history_pointer
    lea rdx, [rax+HISTORY_HEADER]
    mov [arena_view_left], rdx
    add rdx, GAME_CONTEXT_SIZE
    mov [arena_view_right], rdx
    mov rdx, [rax]
    mov [arena_view_now], rdx
    mov rdx, [rax+8]
    mov [arena_view_elapsed], rdx
    mov rdx, [rax+24]
    mov [arena_view_event], rdx
    mov edx, [rax+32]
    mov [arena_view_side], edx
    mov edx, [rax+36]
    mov [arena_view_lines], edx
    mov edx, [rax+48]
    mov [arena_view_skill], edx
.compose:
    mov rdi, [arena_view_left]
    lea rsi, [arena_display_left]
    call arena_compose
    mov rdi, [arena_view_right]
    lea rsi, [arena_display_right]
    call arena_compose
    lea rsi, [ar_human]
    mov rax, [arena_view_left]
    cmp byte [rax+CTX(ai_auto)], 0
    je .title
    lea rsi, [ar_pilot]
.title:
    call append_z
    lea rsi, [ar_erase_tail]
    call append_z
    lea rsi, [ar_center]
    call append_z
    lea rsi, [ar_title]
    call append_z
    lea rsi, [ar_right]
    call append_z
    lea rsi, [ar_cpu]
    call append_z
    mov edi, [arena_view_skill]
    call append_u64
    lea rsi, [row_end_seq]
    call append_z
    lea rsi, [top_border]
    call append_z
    lea rsi, [ar_center]
    call append_z
    lea rsi, [ar_round]
    call append_z
    mov rdi, [arena_round]
    call append_u64
    lea rsi, [ar_branch]
    call append_z
    mov rdi, [arena_branches]
    call append_u64
    lea rsi, [ar_right]
    call append_z
    lea rsi, [top_border]
    call append_z
    lea rsi, [row_end_seq]
    call append_z
    xor r12d, r12d
.row:
    lea rdi, [arena_display_left]
    mov esi, r12d
    call ar_render_board_row
    mov edi, r12d
    call ar_render_center
    lea rsi, [ar_right]
    call append_z
    lea rdi, [arena_display_right]
    mov esi, r12d
    call ar_render_board_row
    lea rsi, [row_end_seq]
    call append_z
    inc r12d
    cmp r12d, BOARD_H
    jb .row
    lea rsi, [ar_bottom]
    call append_z
    lea rsi, [ar_center]
    call append_z
    lea rsi, [ar_bottom_center]
    call append_z
    lea rsi, [ar_right]
    call append_z
    lea rsi, [ar_bottom]
    call append_z
    lea rsi, [row_end_seq]
    call append_z
    lea rsi, [ar_footer]
    call append_z
    jmp .emit
.small:
    lea rsi, [ar_small]
    call append_z
.emit:
    lea rsi, [ar_sync_end]
    call append_z
    lea rsi, [output_buf]
    mov rdx, r15
    sub rdx, rsi
    call write_all_stdout
    mov byte [dirty], 0
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

ar_render_board_row:
    push rbx
    push r12
    imul eax, esi, BOARD_W
    lea rbx, [rdi+rax]
    lea rsi, [left_edge]
    call append_z
    xor r12d, r12d
.cell:
    movzx eax, byte [rbx+r12]
    lea rsi, [empty_cell]
    test eax, eax
    jz .emit
    dec eax
    lea rdx, [cell_colors]
    mov rsi, [rdx+rax*8]
.emit:
    call append_z
    inc r12d
    cmp r12d, BOARD_W
    jb .cell
    lea rsi, [right_edge]
    call append_z
    pop r12
    pop rbx
    ret

ar_render_center:
    push r12
    mov r12d, edi
    lea rsi, [ar_center]
    call append_z
    lea rax, [ar_center_rows]
    call [rax+r12*8]
    pop r12
    ret
.clock:
    lea rsi, [ar_clock]
    call append_z
    mov rax, [arena_duration]
    sub rax, [arena_view_elapsed]
    jns .time
    xor eax, eax
.time:
    xor edx, edx
    mov ecx, 1000000000
    div rcx
    xor edx, edx
    mov ecx, 60
    div rcx
    push rdx
    mov rdi, rax
    call ar_two_digits
    mov dil, ':'
    call append_char
    pop rdi
    jmp ar_two_digits
.labels:
    lea rsi, [ar_labels]
    jmp append_z
.score:
    lea rsi, [ar_score]
    mov edx, CTX(score)
    jmp ar_stat_pair
.lines:
    lea rsi, [ar_lines]
    mov edx, CTX(total_lines)
    jmp ar_stat_pair
.sent:
    lea rsi, [ar_sent]
    mov edx, CTX(battle_sent)
    jmp ar_stat_pair
.cancelled:
    lea rsi, [ar_cancel]
    mov edx, CTX(battle_cancelled)
    jmp ar_stat_pair
.next:
    lea rsi, [ar_next]
    mov edx, CTX(next_queue)
    jmp ar_piece_pair
.hold:
    lea rsi, [ar_hold]
    mov edx, CTX(hold_type)
    jmp ar_piece_pair
.incoming:
    lea rsi, [ar_incoming]
    jmp append_z
.you_bar:
    lea rsi, [ar_you_bar]
    mov rdi, [arena_view_left]
    jmp ar_garbage_bar
.cpu_bar:
    lea rsi, [ar_cpu_bar]
    mov rdi, [arena_view_right]
    jmp ar_garbage_bar
.blank:
    ret
.attack:
    cmp dword [arena_view_lines], 0
    je .blank
    mov rax, [arena_view_now]
    sub rax, [arena_view_event]
    cmp rax, 1000000000
    ja .blank
    lea rsi, [ar_attack_right]
    cmp dword [arena_view_side], 0
    je .attack_prefix
    lea rsi, [ar_attack_left]
.attack_prefix:
    call append_z
    mov edi, [arena_view_lines]
    call append_u64
    lea rsi, [ar_attack_right_end]
    cmp dword [arena_view_side], 0
    je append_z
    lea rsi, [ar_attack_left_end]
    jmp append_z
.phase:
    cmp byte [arena_phase], ARENA_COUNTDOWN
    je .countdown
    lea rsi, [ar_live]
    cmp byte [arena_phase], ARENA_LIVE
    je append_z
    lea rsi, [ar_pause]
    cmp byte [arena_phase], ARENA_PAUSED
    je append_z
    cmp byte [arena_phase], ARENA_REPLAY
    je .replay_mode
    lea rsi, [ar_win]
    cmp byte [arena_winner], 1
    je append_z
    lea rsi, [ar_loss]
    cmp byte [arena_winner], 2
    je append_z
    lea rsi, [ar_draw]
    jmp append_z
.replay_mode:
    lea rsi, [ar_replay]
    cmp byte [arena_replay_playing], 0
    jne append_z
    lea rsi, [ar_replay_frozen]
    jmp append_z
.countdown:
    lea rsi, [ar_ready]
    call append_z
    mov rax, [arena_live_start]
    sub rax, [arena_now]
    add rax, 999999999
    xor edx, edx
    mov ecx, 1000000000
    div rcx
    mov rdi, rax
    jmp append_u64
.explain:
    cmp byte [arena_phase], ARENA_REPLAY
    je .frame
    lea rsi, [ar_result_help]
    cmp byte [arena_phase], ARENA_FINISHED
    je append_z
    lea rsi, [ar_rule]
    jmp append_z
.frame:
    lea rsi, [ar_frame]
    call append_z
    mov edi, [arena_replay_index]
    inc edi
    call append_u64
    lea rsi, [ar_slash]
    call append_z
    mov edi, [arena_history_count]
    jmp append_u64
.wins:
    lea rsi, [ar_match]
    call append_z
    mov rdi, [arena_left_wins]
    call append_u64
    lea rsi, [ar_pair]
    call append_z
    mov rdi, [arena_right_wins]
    jmp append_u64
.controls:
    lea rsi, [ar_controls]
    cmp byte [arena_phase], ARENA_REPLAY
    jne append_z
    lea rsi, [ar_replay_controls]
    jmp append_z
.replay_key:
    lea rsi, [ar_time_travel]
    cmp byte [arena_phase], ARENA_REPLAY
    jne append_z
    lea rsi, [ar_fork]
    jmp append_z
.difficulty:
    lea rsi, [ar_difficulty]
    cmp byte [arena_phase], ARENA_REPLAY
    jne append_z
    lea rsi, [ar_return]
    jmp append_z
.pause_key:
    lea rsi, [ar_pause_help]
    jmp append_z

ar_two_digits:
    cmp rdi, 10
    jae append_u64
    push rdi
    mov dil, '0'
    call append_char
    pop rdi
    jmp append_u64

ar_stat_pair:
    push r12
    mov r12d, edx
    call append_z
    lea rsi, [ar_left_color]
    call append_z
    mov rax, [arena_view_left]
    mov rdi, [rax+r12]
    call append_u64
    lea rsi, [ar_pair]
    call append_z
    mov rax, [arena_view_right]
    mov rdi, [rax+r12]
    call append_u64
    pop r12
    ret

ar_piece_pair:
    push r12
    mov r12d, edx
    call append_z
    mov rax, [arena_view_left]
    mov edi, [rax+r12]
    call ar_piece_badge
    lea rsi, [ar_pair]
    call append_z
    mov rax, [arena_view_right]
    mov edi, [rax+r12]
    call ar_piece_badge
    pop r12
    ret

ar_piece_badge:
    test edi, edi
    js .empty
    push rdi
    lea rax, [cell_colors]
    mov rsi, [rax+rdi*8]
    call append_z
    pop rax
    lea rdx, [piece_letters]
    mov dil, [rdx+rax]
    jmp append_char
.empty:
    mov dil, '-'
    jmp append_char

ar_garbage_bar:
    push r12
    push r13
    mov r12, rdi
    call append_z
    cmp dword [r12+CTX(incoming_count)], 0
    je .bars
    mov eax, [r12+CTX(incoming_head)]
    mov rdx, [arena_view_now]
    cmp rdx, [r12+CTX(incoming_due)+rax*8]
    jb .bars
    lea rsi, [ar_bar_urgent]
    call append_z
.bars:
    xor r13d, r13d
.bar:
    cmp r13d, [r12+CTX(incoming_count)]
    jne .char
    lea rsi, [ar_bar_empty]
    call append_z
.char:
    mov dil, '|'
    call append_char
    inc r13d
    cmp r13d, 14
    jb .bar
    lea rsi, [ar_bar_end]
    call append_z
    mov edi, [r12+CTX(incoming_count)]
    call append_u64
    pop r13
    pop r12
    ret

; compose(rdi=context, rsi=200-byte display): ghost, hint, active, flash.
arena_compose:
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    lea rsi, [rbx+CTX(board)]
    mov rdi, r12
    mov ecx, BOARD_SIZE
    rep movsb
    cmp byte [rbx+CTX(game_state)], STATE_GAME_OVER
    je .flash
    mov r13d, [rbx+CTX(piece_y)]
.ghost:
    mov edi, [rbx+CTX(piece_x)]
    lea esi, [r13d+1]
    mov edx, [rbx+CTX(piece_type)]
    mov ecx, [rbx+CTX(piece_rot)]
    lea r11, [rbx+CTX(board)]
    call can_place_on_board
    test eax, eax
    jz .ghost_ready
    inc r13d
    jmp .ghost
.ghost_ready:
    mov eax, [rbx+CTX(piece_type)]
    shl eax, 2
    add eax, [rbx+CTX(piece_rot)]
    lea rdx, [shapes]
    movzx r14d, word [rdx+rax*2]
    mov rdi, r12
    mov esi, [rbx+CTX(piece_x)]
    mov edx, r13d
    mov ecx, r14d
    mov r8d, 8
    call ar_stamp_display
    cmp byte [rbx+CTX(ai_valid)], 0
    je .active
    mov al, [rbx+CTX(ai_auto)]
    or al, [rbx+CTX(ai_hint)]
    or al, [rbx+CTX(ai_single)]
    jz .active
    mov eax, [rbx+CTX(ai_goal_type)]
    shl eax, 2
    add eax, [rbx+CTX(ai_goal_rot)]
    lea rdx, [shapes]
    movzx ecx, word [rdx+rax*2]
    mov rdi, r12
    mov esi, [rbx+CTX(ai_goal_x)]
    mov edx, [rbx+CTX(ai_goal_y)]
    mov r8d, 9
    call ar_stamp_display
.active:
    mov rdi, r12
    mov esi, [rbx+CTX(piece_x)]
    mov edx, [rbx+CTX(piece_y)]
    mov ecx, r14d
    mov r8d, [rbx+CTX(piece_type)]
    inc r8d
    call ar_stamp_display
.flash:
    mov rax, [arena_view_now]
    cmp rax, [rbx+CTX(flash_until_ns)]
    jae .done
    movzx edx, byte [rbx+CTX(flash_count)]
    xor ecx, ecx
.flash_cell:
    cmp ecx, edx
    jae .done
    mov eax, [rbx+CTX(landing_cells)+rcx*4]
    cmp eax, BOARD_SIZE
    jae .next
    mov byte [r12+rax], 10
.next:
    inc ecx
    jmp .flash_cell
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

ar_stamp_display:
    xor r9d, r9d
.cell:
    bt ecx, r9d
    jnc .next
    mov r10d, r9d
    and r10d, 3
    add r10d, esi
    cmp r10d, BOARD_W
    jae .next
    mov r11d, r9d
    shr r11d, 2
    add r11d, edx
    cmp r11d, BOARD_H
    jae .next
    imul eax, r11d, BOARD_W
    add eax, r10d
    cmp r8d, 8
    jb .write
    cmp byte [rdi+rax], 0
    je .write
    cmp byte [rdi+rax], 8
    jne .next
.write:
    mov [rdi+rax], r8b
.next:
    inc r9d
    cmp r9d, 16
    jb .cell
    ret
