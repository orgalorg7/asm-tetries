; Three full-size, 20-row boards in the original 80 x 24 terminal.
; Absolute column placement and no final newline prevent terminal scrolling.
section .rodata
mv_columns: dq mv_col1, mv_col2, mv_col3
mv_col1: db 27,"[1G",0
mv_col2: db 27,"[28G",0
mv_col3: db 27,"[55G",0
mv_colors: dq mv_cyan, mv_gold, mv_pink
mv_cyan: db 27,"[1;38;5;117m",0
mv_gold: db 27,"[1;38;5;221m",0
mv_pink: db 27,"[1;38;5;204m",0
mv_select: db "  ▶ FUTURE ",0
mv_title: db "    FUTURE ",0
mv_running: db " / LIVE",0
mv_stopped: db " / ENDED",0
mv_empty: db 27,"[38;5;240m  NO OTHER LEGAL MOVE",0
mv_top: db "  ┌─ L+",0
mv_attack: db "  A+",0
mv_top_end: db " ───────┐",27,"[0m",0
mv_bottom: db "  └─ IN",0
mv_holes: db "  HOLES",0
mv_bottom_end: db " ────┘",27,"[0m",0
mv_footer: db 27,"[0;38;5;231m MULTIVERSE +",0
mv_time_end: db "s ",0
mv_bar_live: db 27,"[38;5;117m",0
mv_bar_past: db 27,"[38;5;239m",0
mv_bar: db "━",0
mv_keys: db 27,"[0;38;5;245m ←→ pick ↑↓ time SPACE play ENTER jump M back",0
mv_ended_keys: db 27,"[0;38;5;221m ENDED: ↑↓ seek earlier  ←→ pick  M back",0
mv_play_mark: db 27,"[38;5;114m▶",0
mv_pause_mark: db 27,"[38;5;221m||",0

section .bss
alignb 8
mv_view_ptrs: resq MV_BRANCHES
mv_view_displays: resb MV_BRANCHES*BOARD_SIZE

section .text
multiverse_render:
    push rbx
    push r12
    push r13
    push r14
    push r15
    lea r15, [output_buf]
    call ui_clear_if_needed
    lea rsi, [ar_sync]
    call append_z
    xor r12d, r12d
.compose:
    mov edi, r12d
    mov esi, [mv_cursor]
    call multiverse_pointer
    lea rdx, [mv_view_ptrs]
    mov [rdx+r12*8], rax
    mov rdx, [rax]
    mov [arena_view_now], rdx
    lea rdi, [rax+HISTORY_HEADER]
    imul eax, r12d, BOARD_SIZE
    lea rsi, [mv_view_displays]
    add rsi, rax
    call arena_compose
    inc r12d
    cmp r12d, [mv_count]
    jb .compose
    xor r12d, r12d
.titles:
    call mv_view_column
    cmp r12d, [mv_count]
    jae .missing
    call mv_view_color
    lea rsi, [mv_title]
    cmp r12d, [mv_selected]
    jne .title
    lea rsi, [mv_select]
.title:
    call append_z
    lea edi, [r12d+1]
    call ar_two_digits
    lea rdx, [mv_view_ptrs]
    mov rax, [rdx+r12*8]
    lea rsi, [mv_running]
    cmp dword [rax+40], ARENA_FINISHED
    jne .state
    lea rsi, [mv_stopped]
.state:
    call append_z
    jmp .next_title
.missing:
    lea rsi, [mv_empty]
    call append_z
.next_title:
    inc r12d
    cmp r12d, MV_BRANCHES
    jb .titles
    lea rsi, [row_end_seq]
    call append_z
    xor r12d, r12d
.tops:
    call mv_view_column
    call mv_view_color
    lea rdx, [mv_view_ptrs]
    mov rbx, [rdx+r12*8]
    add rbx, HISTORY_HEADER
    lea rsi, [mv_top]
    call append_z
    mov rdi, [rbx+CTX(total_lines)]
    sub rdi, [mv_origin_left+CTX(total_lines)]
    call mv_two_digits
    lea rsi, [mv_attack]
    call append_z
    mov rdi, [rbx+CTX(battle_sent)]
    sub rdi, [mv_origin_left+CTX(battle_sent)]
    call mv_two_digits
    lea rsi, [mv_top_end]
    call append_z
    inc r12d
    cmp r12d, [mv_count]
    jb .tops
    lea rsi, [row_end_seq]
    call append_z
    xor r13d, r13d
.row:
    xor r12d, r12d
.board:
    call mv_view_column
    imul eax, r12d, BOARD_SIZE
    lea rdi, [mv_view_displays]
    add rdi, rax
    mov esi, r13d
    call ar_render_board_row
    inc r12d
    cmp r12d, [mv_count]
    jb .board
    lea rsi, [row_end_seq]
    call append_z
    inc r13d
    cmp r13d, BOARD_H
    jb .row
    xor r12d, r12d
.bottoms:
    call mv_view_column
    call mv_view_color
    lea rdx, [mv_view_ptrs]
    mov rbx, [rdx+r12*8]
    add rbx, HISTORY_HEADER
    lea rsi, [mv_bottom]
    call append_z
    mov edi, [rbx+CTX(incoming_count)]
    call mv_two_digits
    lea rsi, [mv_holes]
    call append_z
    lea rdi, [rbx+CTX(board)]
    call ai_evaluate
    mov edi, [ai_eval_holes]
    call mv_two_digits
    lea rsi, [mv_bottom_end]
    call append_z
    inc r12d
    cmp r12d, [mv_count]
    jb .bottoms
    lea rsi, [row_end_seq]
    call append_z
    lea rsi, [mv_footer]
    call append_z
    mov eax, [mv_cursor]
    imul eax, eax, 125
    xor edx, edx
    mov ecx, 1000
    div ecx
    push rdx
    mov edi, eax
    call append_u64
    mov dil, '.'
    call append_char
    pop rax
    xor edx, edx
    mov ecx, 10
    div ecx
    mov edi, eax
    call ar_two_digits
    lea rsi, [mv_time_end]
    call append_z
    lea rsi, [mv_play_mark]
    cmp byte [mv_playing], 0
    jne .play_mark
    lea rsi, [mv_pause_mark]
.play_mark:
    call append_z
    xor r12d, r12d
.bar:
    lea rsi, [mv_bar_live]
    lea eax, [r12d+1]
    shl eax, 3
    cmp eax, [mv_cursor]
    jbe .bar_color
    lea rsi, [mv_bar_past]
.bar_color:
    call append_z
    lea rsi, [mv_bar]
    call append_z
    inc r12d
    cmp r12d, 8
    jb .bar
    lea rsi, [mv_keys]
    mov eax, [mv_selected]
    lea rdx, [mv_view_ptrs]
    mov rax, [rdx+rax*8]
    cmp dword [rax+40], ARENA_FINISHED
    jne .keys
    lea rsi, [mv_ended_keys]
.keys:
    call append_z
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

mv_view_column:
    lea rdx, [mv_columns]
    mov rsi, [rdx+r12*8]
    jmp append_z

mv_view_color:
    lea rdx, [mv_colors]
    mov rsi, [rdx+r12*8]
    jmp append_z

; Keep the fixed-width board borders intact, including pathological stacks.
mv_two_digits:
    cmp rdi, 99
    jbe ar_two_digits
    mov edi, 99
    jmp ar_two_digits
