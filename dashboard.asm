; Adaptive ANSI dashboard. The full view fits 80x24 without scrolling.
; At 60..79 columns the playfield/stats remain; smaller screens suspend time.
section .rodata
ui_clear_seq: db 27,"[2J",27,"[H",0
ui_small_text: db 27,"[H",27,"[0mTETRIS",27,"[K",13,10
    db "Resize to 60 x 24.",27,"[K",13,10
    db "Game suspended.",27,"[K",13,10
    db "Q quits.",27,"[J",0
ui_middle: db 27,"[28G",27,"[38;5;245m",0
ui_panel: db 27,"[52G",27,"[0;38;5;245m",0
ui_player: db "HUMAN / LIVE",27,"[0m",0
ui_assisted: db "ASSISTED RUN",27,"[0m",0
ui_banner: db 27,"[52G",27,"[38;5;240mCPU ONLY / NO GPU",27,"[0m",0
ui_pilot_title: db 27,"[1;38;5;117mC O P I L O T",27,"[0m",0
ui_auto_text: db 27,"[38;5;114mAUTOPILOT / ACTIVE",27,"[0m",0
ui_single_text: db 27,"[38;5;221mPLAYING ONE PIECE",27,"[0m",0
ui_hint_text: db "HINTS ON / YOU PLAY",0
ui_manual_text: db "MANUAL / HINTS OFF",0
ui_paused_text: db 27,"[38;5;221mPAUSED / P TO RESUME",27,"[0m",0
ui_stopped_text: db 27,"[38;5;204mSTOPPED / GAME OVER",27,"[0m",0
ui_rule: db "--------------------------",0
ui_depth_text: db "LOOKAHEAD   2 pieces",0
ui_states_text: db "STATES      ",27,"[38;5;252m",0
ui_time_text: db "PLAN        ",27,"[38;5;252m",0
ui_us: db " us",0
ui_target_text: db 27,"[38;5;117mBEST REACHABLE LANDING",27,"[0m",0
ui_col: db "COL ",27,"[38;5;252m",0
ui_rot: db 27,"[38;5;245m   ROT ",27,"[38;5;252m",0
ui_no_target: db "NO SAFE LANDING",0
ui_enable_hints: db "PRESS H TO SEE A PLAN",0
ui_idle: db "--",0
ui_next_move: db "NEXT MOVE   ",27,"[38;5;252m",0
ui_left: db "LEFT",0
ui_right: db "RIGHT",0
ui_cw: db "TURN CW",0
ui_ccw: db "TURN CCW",0
ui_down: db "DOWN",0
ui_drop: db "HARD DROP",0
ui_move_names: dq ui_idle, ui_left, ui_right, ui_cw, ui_ccw, ui_down, ui_drop
ui_height_text: db "STACK       ",27,"[38;5;252m",0
ui_twenty: db 27,"[38;5;240m / 20",0
ui_holes_text: db "HOLES       ",27,"[38;5;252m",0
ui_gauge_start: db 27,"[38;5;240m[",0
ui_gauge_low: db 27,"[38;5;80m",0
ui_gauge_mid: db 27,"[38;5;221m",0
ui_gauge_high: db 27,"[38;5;204m",0
ui_gauge_empty: db 27,"[38;5;238m",0
ui_gauge_end: db 27,"[38;5;240m]",0
ui_auto_key: db "B   Toggle autopilot",0
ui_hint_key: db "H   Toggle ++ hint",0
ui_one_key: db "N   Play one piece",0
ui_pace_key: db "[ ] Pace  ",27,"[38;5;252m",0
ui_ms: db 27,"[38;5;245m ms / move",0
ui_pause_key: db "P pause    R restart",0
ui_quit_key: db "Q quit     1-9 level",0
ui_rows: dq render_copilot.title, render_copilot.mode, render_copilot.rule
    dq render_copilot.depth, render_copilot.states, render_copilot.time
    dq render_copilot.blank, render_copilot.target, render_copilot.landing
    dq render_copilot.action, render_copilot.height, render_copilot.holes
    dq render_copilot.gauge, render_copilot.blank, render_copilot.auto_key
    dq render_copilot.hint_key, render_copilot.one_key, render_copilot.pace
    dq render_copilot.pause_key, render_copilot.quit_key

section .bss
alignb 4
ui_winsize: resw 4
ui_cols: resw 1
ui_height: resw 1
ui_too_small: resb 1
ui_clear: resb 1

section .text
check_terminal_size:
    mov eax, SYS_ioctl
    mov edi, STDOUT
    mov esi, TIOCGWINSZ
    lea rdx, [ui_winsize]
    syscall
    test rax, rax
    js .fallback
    movzx eax, word [ui_winsize+2]
    movzx edx, word [ui_winsize]
    test eax, eax
    jz .fallback
    test edx, edx
    jnz .compare
.fallback:
    mov eax, 80
    mov edx, 24
.compare:
    cmp ax, [ui_cols]
    jne .changed
    cmp dx, [ui_height]
    je .done
.changed:
    mov [ui_cols], ax
    mov [ui_height], dx
    mov byte [ui_clear], 1
    mov byte [dirty], 1
    mov ecx, 60
    cmp byte [arena_mode], 0
    je .minimum
    mov ecx, 80
.minimum:
    cmp eax, ecx
    jb .small
    cmp edx, 24
    jb .small
    cmp byte [ui_too_small], 0
    je .done
    mov byte [ui_too_small], 0
    cmp byte [arena_mode], 0
    jne .done
    ; A resize suspension must not accumulate gravity or expire lock delay.
    call get_time_ns
    mov [last_drop_ns], rax
    add rax, LOCK_DELAY_NS
    mov [lock_deadline], rax
    ret
.small:
    mov byte [ui_too_small], 1
.done:
    ret

ui_clear_if_needed:
    cmp byte [ui_clear], 0
    je .done
    mov byte [ui_clear], 0
    lea rsi, [ui_clear_seq]
    call append_z
.done:
    ret

render_mode_banner:
    lea rsi, [ui_middle]
    call append_z
    lea rsi, [ui_player]
    cmp byte [assisted_run], 0
    je .mode
    lea rsi, [ui_assisted]
.mode:
    call append_z
    cmp word [ui_cols], 80
    jb .done
    lea rsi, [ui_banner]
    call append_z
.done:
    ret

render_copilot:
    cmp word [ui_cols], 80
    jb .done
    push r12
    mov r12d, edi
    lea rsi, [ui_panel]
    call append_z
    lea rax, [ui_rows]
    call [rax+r12*8]
    pop r12
.done:
    ret
.title:
    lea rsi, [ui_pilot_title]
    jmp append_z
.mode:
    lea rsi, [ui_paused_text]
    cmp byte [game_state], STATE_PAUSED
    je append_z
    lea rsi, [ui_stopped_text]
    cmp byte [game_state], STATE_GAME_OVER
    je append_z
    lea rsi, [ui_auto_text]
    cmp byte [ai_auto], 0
    jne append_z
    lea rsi, [ui_single_text]
    cmp byte [ai_single], 0
    jne append_z
    lea rsi, [ui_hint_text]
    cmp byte [ai_hint], 0
    jne append_z
    lea rsi, [ui_manual_text]
    jmp append_z
.rule:
    lea rsi, [ui_rule]
    jmp append_z
.depth:
    lea rsi, [ui_depth_text]
    jmp append_z
.states:
    lea rsi, [ui_states_text]
    call append_z
    lea rsi, [ui_idle]
    cmp byte [ai_valid], 0
    je append_z
    mov rdi, [ai_nodes]
    jmp append_u64
.time:
    lea rsi, [ui_time_text]
    call append_z
    lea rsi, [ui_idle]
    cmp byte [ai_valid], 0
    je append_z
    mov rdi, [ai_plan_us]
    call append_u64
    lea rsi, [ui_us]
    jmp append_z
.blank:
    ret
.target:
    lea rsi, [ui_target_text]
    jmp append_z
.landing:
    cmp byte [ai_valid], 0
    je .no_target
    lea rsi, [ui_col]
    call append_z
    mov eax, [ai_goal_type]
    shl eax, 2
    add eax, [ai_goal_rot]
    lea rdx, [shapes]
    movzx eax, word [rdx+rax*2]
    mov edx, eax
    shr edx, 8
    or eax, edx
    mov edx, eax
    shr edx, 4
    or eax, edx
    and eax, 15
    bsf edi, eax
    add edi, [ai_goal_x]
    inc edi
    call append_u64
    lea rsi, [ui_rot]
    call append_z
    imul edi, [ai_goal_rot], 90
    jmp append_u64
.no_target:
    lea rsi, [ui_no_target]
    mov al, [ai_hint]
    or al, [ai_auto]
    or al, [ai_single]
    jnz append_z
    lea rsi, [ui_enable_hints]
    jmp append_z
.action:
    lea rsi, [ui_next_move]
    call append_z
    lea rsi, [ui_idle]
    cmp byte [ai_valid], 0
    je append_z
    mov eax, [ai_path_index]
    cmp eax, [ai_path_count]
    jae append_z
    lea rdx, [ai_path]
    movzx eax, byte [rdx+rax]
    lea rdx, [ui_move_names]
    mov rsi, [rdx+rax*8]
    jmp append_z
.height:
    lea rsi, [ui_height_text]
    call append_z
    mov edi, [ai_live_height]
    call append_u64
    lea rsi, [ui_twenty]
    jmp append_z
.holes:
    lea rsi, [ui_holes_text]
    call append_z
    mov edi, [ai_live_holes]
    jmp append_u64
.gauge:
    lea rsi, [ui_gauge_start]
    call append_z
    lea rsi, [ui_gauge_low]
    cmp dword [ai_live_height], 8
    jb .gauge_color
    lea rsi, [ui_gauge_mid]
    cmp dword [ai_live_height], 14
    jb .gauge_color
    lea rsi, [ui_gauge_high]
.gauge_color:
    call append_z
    xor ecx, ecx
.gauge_cell:
    cmp ecx, [ai_live_height]
    jne .gauge_emit
    lea rsi, [ui_gauge_empty]
    call append_z
.gauge_emit:
    mov dil, '|'
    call append_char
    inc ecx
    cmp ecx, BOARD_H
    jb .gauge_cell
    lea rsi, [ui_gauge_end]
    jmp append_z
.auto_key:
    lea rsi, [ui_auto_key]
    jmp append_z
.hint_key:
    lea rsi, [ui_hint_key]
    jmp append_z
.one_key:
    lea rsi, [ui_one_key]
    jmp append_z
.pace:
    lea rsi, [ui_pace_key]
    call append_z
    mov rax, [ai_interval]
    xor edx, edx
    mov ecx, 1000000
    div rcx
    mov rdi, rax
    call append_u64
    lea rsi, [ui_ms]
    jmp append_z
.pause_key:
    lea rsi, [ui_pause_key]
    jmp append_z
.quit_key:
    lea rsi, [ui_quit_key]
    jmp append_z
