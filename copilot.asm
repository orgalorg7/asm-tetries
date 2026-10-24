; CPU-only Tetris copilot. No allocation, threads, model, or external service.
;
; A breadth-first search enumerates REACHABLE piece states using the game's
; collision and SRS functions. The eight best distinct landings are searched
; again with the next queued piece. All simulations use separate scratch boards.
; The winning parent chain becomes ordinary moves, rotations, and a hard drop.
;
; State ID: rotation * 512 + (y + 4) * 16 + (x + 3).
; Legal search domain: x=-3..9, y=-4..19, rotation=0..3 (2048 slots).
; The bounded hidden rows allow upward SRS kicks without an unbounded graph.

%define AI_BEAM 8
%define AI_INFINITY 100000000
%define AI_LEFT 1
%define AI_RIGHT 2
%define AI_CW 3
%define AI_CCW 4
%define AI_DOWN 5
%define AI_DROP 6

section .rodata
ai_line_reward: dd 0, 100, 300, 600, 1000

section .bss
alignb 8
alignb 8
ai_reverse: resb AI_STATES
alignb 8
ai_board_ptr: resq 1
ai_type: resd 1
ai_mode: resd 1
ai_head: resd 1
ai_tail: resd 1
ai_current: resd 1
ai_x: resd 1
ai_y: resd 1
ai_rot: resd 1
ai_leaf_best: resd 1
ai_beam_count: resd 1
ai_beam: resd AI_BEAM*4       ; cost, node ID, occupied-cell key, clear count
ai_future_costs: resd AI_BEAM
ai_variant: resd 1           ; one-shot rank of a distinct reachable landing
ai_parent: resw AI_STATES
ai_actions: resb AI_STATES
ai_queue: resw AI_STATES
ai_root_parent: resw AI_STATES
ai_root_actions: resb AI_STATES
ai_child_board: resb BOARD_SIZE
ai_eval_board: resb BOARD_SIZE
alignb 4
ai_stamp_key: resd 1
ai_eval_lines: resd 1
ai_eval_height: resd 1
ai_eval_holes: resd 1
ai_heights: resd BOARD_W

section .text

ai_manual_takeover:
    mov al, [ai_auto]
    or al, [ai_single]
    jz .manual
    mov byte [das_active], 0
    mov dword [horizontal_dir], 0
.manual:
    mov byte [ai_auto], 0
    mov byte [ai_single], 0
    mov byte [ai_cached], 0
    mov byte [dirty], 1
    ret

ai_remember_state:
    mov rax, [piece_x]
    mov [ai_snapshot], rax
    mov rax, [piece_type]
    mov [ai_snapshot+8], rax
    mov rax, [piece_serial]
    mov [ai_snapshot+16], rax
    ret

; A cached path remains valid after our own moves. Gravity, hold, spawn,
; restart, and human input all invalidate it through this state comparison.
ai_ensure_plan:
    cmp byte [game_state], STATE_PLAYING
    jne .done
    cmp byte [ai_cached], 0
    je ai_plan
    mov rax, [piece_x]
    cmp rax, [ai_snapshot]
    jne ai_plan
    mov rax, [piece_type]
    cmp rax, [ai_snapshot+8]
    jne ai_plan
    mov rax, [piece_serial]
    cmp rax, [ai_snapshot+16]
    jne ai_plan
.done:
    ret

ai_tick:
    cmp byte [game_state], STATE_PLAYING
    jne .done
    cmp byte [ui_too_small], 0
    jne .done
    mov al, [ai_auto]
    or al, [ai_single]
    jz .done
    call get_time_ns
    cmp rax, [ai_deadline]
    jb .done
    call ai_ensure_plan
    cmp byte [ai_valid], 0
    je .done
    mov eax, [ai_path_index]
    cmp eax, [ai_path_count]
    jae .done
    lea rdx, [ai_path]
    movzx edi, byte [rdx+rax]
    inc dword [ai_path_index]
    mov byte [assisted_run], 1
    call ai_execute_action
    test eax, eax
    jnz .locked
    call ai_remember_state
    jmp .deadline
.locked:
    mov byte [ai_cached], 0
    mov byte [ai_single], 0
.deadline:
    call get_time_ns
    add rax, [ai_interval]
    mov [ai_deadline], rax
.done:
    ret

; Executes exactly the same transformations as human controls.
; Returns 1 for a hard drop, 0 for all other actions.
ai_execute_action:
    cmp edi, AI_LEFT
    je .left
    cmp edi, AI_RIGHT
    je .right
    cmp edi, AI_CW
    je .cw
    cmp edi, AI_CCW
    je .ccw
    cmp edi, AI_DOWN
    je .down
    cmp edi, AI_DROP
    jne .done
    call hard_drop
    mov eax, 1
    ret
.left:
    call try_left
    jmp .done
.right:
    call try_right
    jmp .done
.cw:
    call try_rotate
    jmp .done
.ccw:
    call try_rotate_ccw
    jmp .done
.down:
    call step_down
.done:
    xor eax, eax
    ret

ai_plan:
    push rbx
    push r12
    push r13
    push r14
    push r15
    call get_wall_time_ns
    mov r12, rax
    mov byte [ai_valid], 0
    mov dword [ai_path_count], 0
    mov dword [ai_path_index], 0
    mov dword [ai_beam_count], 0
    mov qword [ai_nodes], 0
    mov qword [ai_evaluations], 0
    lea rdi, [board]
    call ai_evaluate
    mov eax, [ai_eval_height]
    mov [ai_live_height], eax
    mov eax, [ai_eval_holes]
    mov [ai_live_holes], eax
    mov edi, [piece_type]
    mov esi, [piece_x]
    mov edx, [piece_y]
    mov ecx, [piece_rot]
    lea r8, [board]
    xor r9d, r9d
    call ai_enumerate
    cmp dword [ai_beam_count], 0
    je .done

    ; Save root parent chains before reusing the BFS workspace for lookahead.
    lea rsi, [ai_parent]
    lea rdi, [ai_root_parent]
    mov ecx, AI_STATES
    rep movsw
    lea rsi, [ai_actions]
    lea rdi, [ai_root_actions]
    mov ecx, AI_STATES
    rep movsb
    xor r13d, r13d
    mov r14d, AI_INFINITY*3
    xor ebx, ebx
.lookahead:
    mov eax, r13d
    shl eax, 4
    lea r15, [ai_beam]
    add r15, rax
    lea rdi, [board]
    lea rsi, [ai_child_board]
    mov edx, [r15+4]
    mov ecx, [piece_type]
    call ai_stamp_node
    mov edi, [next_queue]
    mov esi, 3
    mov edx, -1
    xor ecx, ecx
    lea r8, [ai_child_board]
    mov r9d, 1
    call ai_enumerate
    mov eax, [ai_leaf_best]
    add eax, [r15]
    lea rdx, [ai_future_costs]
    mov [rdx+r13*4], eax
    cmp eax, r14d
    jge .next
    mov r14d, eax
    mov ebx, r13d
.next:
    inc r13d
    cmp r13d, [ai_beam_count]
    jb .lookahead

    ; The multiverse may request the second/third best root. Ordinary plans
    ; still choose the original winner. Consume this override exactly once.
    mov ecx, [ai_variant]
    mov dword [ai_variant], 0
    mov eax, [ai_beam_count]
    dec eax
    cmp ecx, eax
    cmova ecx, eax
.variant:
    test ecx, ecx
    jz .chosen
    lea rdx, [ai_future_costs]
    mov dword [rdx+rbx*4], 0x7fffffff
    mov r14d, 0x7fffffff
    xor eax, eax
.rank:
    cmp [rdx+rax*4], r14d
    jge .rank_next
    mov r14d, [rdx+rax*4]
    mov ebx, eax
.rank_next:
    inc eax
    cmp eax, [ai_beam_count]
    jb .rank
    dec ecx
    jmp .variant
.chosen:
    shl ebx, 4
    lea rdx, [ai_beam]
    mov eax, [rdx+rbx+4]
    mov edx, eax
    and edx, 15
    sub edx, 3
    mov [ai_goal_x], edx
    mov edx, eax
    shr edx, 4
    and edx, 31
    sub edx, 4
    mov [ai_goal_y], edx
    mov edx, eax
    shr edx, 9
    mov [ai_goal_rot], edx
    mov edx, [piece_type]
    mov [ai_goal_type], edx
    xor ecx, ecx
    lea r8, [ai_root_parent]
    lea r9, [ai_root_actions]
    lea r10, [ai_reverse]
.parents:
    movzx edx, word [r8+rax*2]
    cmp edx, 0xfffe
    je .reverse
    cmp edx, AI_STATES
    jae .done
    cmp ecx, AI_STATES
    jae .done
    mov bl, [r9+rax]
    mov [r10+rcx], bl
    inc ecx
    mov eax, edx
    jmp .parents
.reverse:
    lea rdi, [ai_path]
    xor edx, edx
.copy_path:
    test ecx, ecx
    jz .trim
    dec ecx
    mov al, [r10+rcx]
    mov [rdi+rdx], al
    inc edx
    jmp .copy_path
.trim:
    ; Replace a final vertical descent with hard drop. Earlier down moves
    ; remain in the path, so slides under overhangs are still executable.
    test edx, edx
    jz .drop
    cmp byte [rdi+rdx-1], AI_DOWN
    jne .drop
    dec edx
    jmp .trim
.drop:
    mov byte [rdi+rdx], AI_DROP
    inc edx
    mov [ai_path_count], edx
    mov byte [ai_valid], 1
.done:
    mov dword [ai_variant], 0
    mov byte [ai_cached], 1
    call ai_remember_state
    call get_wall_time_ns
    sub rax, r12
    xor edx, edx
    mov ecx, 1000
    div rcx
    mov [ai_plan_us], rax
    mov byte [dirty], 1
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ai_enumerate(edi=type, esi=x, edx=y, ecx=rotation, r8=board,
;              r9d=0 root beam / 1 best leaf). Nonrecursive BFS.
ai_enumerate:
    push rbx
    push r12
    push r13
    push r14
    mov [ai_type], edi
    mov [ai_board_ptr], r8
    mov [ai_mode], r9d
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx
    lea rdi, [ai_parent]
    mov eax, 0xffff
    mov ecx, AI_STATES
    rep stosw
    mov dword [ai_head], 0
    mov dword [ai_tail], 0
    mov dword [ai_leaf_best], AI_INFINITY
    mov dword [ai_current], 0xfffe
    mov edi, r12d
    mov esi, r13d
    mov ecx, r14d
    xor edx, edx
    call ai_visit
.queue:
    mov eax, [ai_head]
    cmp eax, [ai_tail]
    jae .done
    lea rbx, [ai_queue]
    movzx eax, word [rbx+rax*2]
    mov [ai_current], eax
    inc dword [ai_head]
    inc qword [ai_nodes]
    mov edx, eax
    and edx, 15
    sub edx, 3
    mov [ai_x], edx
    mov edx, eax
    shr edx, 4
    and edx, 31
    sub edx, 4
    mov [ai_y], edx
    shr eax, 9
    mov [ai_rot], eax
    mov edi, [ai_x]
    mov esi, [ai_y]
    inc esi
    mov edx, [ai_type]
    mov ecx, [ai_rot]
    mov r11, [ai_board_ptr]
    call can_place_on_board
    test eax, eax
    jnz .neighbors
    call ai_score_candidate
.neighbors:
    mov edi, [ai_x]
    dec edi
    mov esi, [ai_y]
    mov ecx, [ai_rot]
    mov edx, AI_LEFT
    call ai_visit
    mov edi, [ai_x]
    inc edi
    mov esi, [ai_y]
    mov ecx, [ai_rot]
    mov edx, AI_RIGHT
    call ai_visit
    mov edi, [ai_x]
    mov esi, [ai_y]
    mov edx, [ai_type]
    mov ecx, [ai_rot]
    mov r8d, 1
    mov r11, [ai_board_ptr]
    call find_rotation
    test eax, eax
    jz .ccw
    mov edx, AI_CW
    call ai_visit
.ccw:
    mov edi, [ai_x]
    mov esi, [ai_y]
    mov edx, [ai_type]
    mov ecx, [ai_rot]
    mov r8d, -1
    mov r11, [ai_board_ptr]
    call find_rotation
    test eax, eax
    jz .down
    mov edx, AI_CCW
    call ai_visit
.down:
    mov edi, [ai_x]
    mov esi, [ai_y]
    inc esi
    mov ecx, [ai_rot]
    mov edx, AI_DOWN
    call ai_visit
    jmp .queue
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ai_visit(edi=x, esi=y, ecx=rotation, edx=action): bounds, deduplicate,
; check collision, then enqueue once. No queue can exceed AI_STATES entries.
ai_visit:
    cmp edi, -3
    jl .done
    cmp edi, 9
    jg .done
    cmp esi, -4
    jl .done
    cmp esi, 19
    jg .done
    push rbx
    push r12
    mov r12d, edx
    mov ebx, ecx
    shl ebx, 9
    lea eax, [rsi+4]
    shl eax, 4
    add ebx, eax
    lea eax, [rdi+3]
    add ebx, eax
    lea rax, [ai_parent]
    cmp word [rax+rbx*2], 0xffff
    jne .return
    mov edx, [ai_type]
    mov r11, [ai_board_ptr]
    call can_place_on_board
    test eax, eax
    jz .return
    lea rax, [ai_parent]
    mov edx, [ai_current]
    mov [rax+rbx*2], dx
    lea rax, [ai_actions]
    mov [rax+rbx], r12b
    lea rax, [ai_queue]
    mov edx, [ai_tail]
    mov [rax+rdx*2], bx
    inc dword [ai_tail]
.return:
    pop r12
    pop rbx
.done:
    ret

; Copy source to scratch, lock node, compact lines. Does not touch live state.
; In: rdi=source, rsi=destination, edx=node ID, ecx=piece type.
; Out: eax=cleared lines, or -1 if the piece would lock above the ceiling.
ai_stamp_node:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rsi
    mov r13d, edx
    and r13d, 15
    sub r13d, 3
    mov r14d, edx
    shr r14d, 4
    and r14d, 31
    sub r14d, 4
    shr edx, 9
    lea eax, [rdx+rcx*4]
    lea rbx, [shapes]
    movzx ebx, word [rbx+rax*2]
    lea r9d, [rcx+1]
    mov rsi, rdi
    mov rdi, r12
    mov ecx, BOARD_SIZE
    rep movsb
    xor ecx, ecx
    xor r10d, r10d
.cell:
    bt ebx, ecx
    jnc .next
    mov edx, ecx
    shr edx, 2
    add edx, r14d
    cmp edx, BOARD_H
    jae .invalid                 ; unsigned also excludes negative rows
    mov eax, ecx
    and eax, 3
    add eax, r13d
    cmp eax, BOARD_W
    jae .invalid
    imul edx, edx, BOARD_W
    add edx, eax
    mov [r12+rdx], r9b
    shl r10d, 8
    or r10d, edx                 ; canonical key: four sorted cell indices
.next:
    inc ecx
    cmp ecx, 16
    jb .cell
    mov [ai_stamp_key], r10d
    mov rdi, r12
    call clear_lines_on_board
    jmp .done
.invalid:
    mov eax, -1
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

ai_score_candidate:
    push rbx
    push r12
    mov rdi, [ai_board_ptr]
    lea rsi, [ai_eval_board]
    mov edx, [ai_current]
    mov ecx, [ai_type]
    call ai_stamp_node
    test eax, eax
    js .done
    mov [ai_eval_lines], eax
    inc qword [ai_evaluations]
    lea rdi, [ai_eval_board]
    call ai_evaluate
    mov edx, [ai_eval_lines]
    lea rcx, [ai_line_reward]
    sub eax, [rcx+rdx*4]
    cmp dword [ai_mode], 0
    je .beam
    cmp eax, [ai_leaf_best]
    jge .done
    mov [ai_leaf_best], eax
    jmp .done
.beam:
    mov r12d, eax
    lea rbx, [ai_beam]
    xor ecx, ecx
    mov edx, [ai_stamp_key]
.deduplicate:
    cmp ecx, [ai_beam_count]
    jae .insert
    mov eax, ecx
    shl eax, 4
    cmp [rbx+rax+8], edx
    je .done
    inc ecx
    jmp .deduplicate
.insert:
    cmp ecx, AI_BEAM
    jb .grow
    xor ecx, ecx
    mov edx, [rbx]
    xor r8d, r8d
.worst:
    mov eax, ecx
    shl eax, 4
    cmp [rbx+rax], edx
    jle .keep_worst
    mov edx, [rbx+rax]
    mov r8d, ecx
.keep_worst:
    inc ecx
    cmp ecx, AI_BEAM
    jb .worst
    cmp r12d, edx
    jge .done
    mov ecx, r8d
    jmp .store
.grow:
    inc dword [ai_beam_count]
.store:
    shl ecx, 4
    mov [rbx+rcx], r12d
    mov eax, [ai_current]
    mov [rbx+rcx+4], eax
    mov eax, [ai_stamp_key]
    mov [rbx+rcx+8], eax
    mov eax, [ai_eval_lines]
    mov [rbx+rcx+12], eax
.done:
    pop r12
    pop rbx
    ret

; Handwritten integer heuristic: smaller is better.
; 45*aggregate height + 140*holes + 30*bumpiness + 4*max height squared.
; Extra-deep wells (>3 rows) receive a quadratic penalty. Clear rewards are
; applied by the caller. This favors accessible, low stacks over short-term
; score. A "hole" is an empty cell with at least one occupied cell above it.
ai_evaluate:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, rdi
    xor r12d, r12d
    xor r13d, r13d
    xor r14d, r14d
    xor r15d, r15d
    xor ecx, ecx
    lea r11, [ai_heights]
.column:
    xor edx, edx
    xor r8d, r8d
.row:
    imul eax, edx, BOARD_W
    add eax, ecx
    cmp byte [rbx+rax], 0
    je .empty
    test r8d, r8d
    jnz .next_row
    mov r8d, BOARD_H
    sub r8d, edx
    jmp .next_row
.empty:
    test r8d, r8d
    jz .next_row
    inc r13d
.next_row:
    inc edx
    cmp edx, BOARD_H
    jb .row
    mov [r11+rcx*4], r8d
    add r12d, r8d
    cmp r8d, r15d
    cmovg r15d, r8d
    test ecx, ecx
    jz .next_column
    mov eax, [r11+rcx*4-4]
    sub eax, r8d
    mov edx, eax
    neg edx
    cmovs edx, eax
    add r14d, edx
.next_column:
    inc ecx
    cmp ecx, BOARD_W
    jb .column
    mov [ai_eval_height], r15d
    mov [ai_eval_holes], r13d
    imul eax, r12d, 45
    imul edx, r13d, 140
    add eax, edx
    imul edx, r14d, 30
    add eax, edx
    imul r15d, r15d
    lea eax, [rax+r15*4]
    xor ecx, ecx
.wells:
    mov edx, BOARD_H
    test ecx, ecx
    jz .right_wall
    mov edx, [r11+rcx*4-4]
.right_wall:
    mov r8d, BOARD_H
    cmp ecx, BOARD_W-1
    je .well_depth
    mov r8d, [r11+rcx*4+4]
.well_depth:
    cmp edx, r8d
    cmovg edx, r8d
    sub edx, [r11+rcx*4]
    sub edx, 3
    jle .next_well
    imul edx, edx
    imul edx, edx, 20
    add eax, edx
.next_well:
    inc ecx
    cmp ecx, BOARD_W
    jb .wells
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Place the recommendation in the display copy. Live board remains untouched.
ai_overlay:
    cmp byte [ai_valid], 0
    je .done
    mov al, [ai_hint]
    or al, [ai_auto]
    or al, [ai_single]
    jz .done
    push rbx
    mov eax, [ai_goal_type]
    shl eax, 2
    add eax, [ai_goal_rot]
    lea rbx, [shapes]
    movzx r8d, word [rbx+rax*2]
    lea rbx, [display_board]
    xor ecx, ecx
.cell:
    bt r8d, ecx
    jnc .next
    mov eax, ecx
    and eax, 3
    add eax, [ai_goal_x]
    mov edx, ecx
    shr edx, 2
    add edx, [ai_goal_y]
    cmp eax, BOARD_W
    jae .next
    cmp edx, BOARD_H
    jae .next
    imul edx, edx, BOARD_W
    add edx, eax
    cmp byte [rbx+rdx], 0
    je .draw
    cmp byte [rbx+rdx], 8
    jne .next
.draw:
    mov byte [rbx+rdx], 9
.next:
    inc ecx
    cmp ecx, 16
    jb .cell
    pop rbx
.done:
    ret
