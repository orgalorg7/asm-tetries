; Regression tests for pure search, executable routes, and scoring isolation.
section .rodata
ai_test_pass: db "Copilot: evaluation, purity, four-line well, legal routes, top-out: PASS",10,0
ai_test_fail: db "Copilot regression: FAIL at stage ",0
ai_test_newline: db 10,0

section .bss
ai_test_board: resb BOARD_SIZE
alignb 8
ai_test_hash: resq 1
ai_test_rng: resq 1
ai_test_piece: resq 2
ai_test_queue: resd 5
ai_test_score: resq 1
ai_test_best: resq 1
ai_test_stage: resd 1

section .text
run_ai_tests:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov dword [ai_test_stage], 1
    lea rdi, [board]
    xor eax, eax
    mov ecx, BOARD_SIZE
    rep stosb
    lea rdi, [board]
    call ai_evaluate
    test eax, eax
    jnz .fail
    mov byte [board+180], 1
    lea rdi, [board]
    call ai_evaluate
    cmp dword [ai_eval_height], 2
    jne .fail
    cmp dword [ai_eval_holes], 1
    jne .fail
    mov ebx, eax
    mov byte [board+190], 1
    lea rdi, [board]
    call ai_evaluate
    cmp eax, ebx
    jge .fail
    cmp dword [ai_eval_holes], 0
    jne .fail

    mov dword [ai_test_stage], 2
    mov qword [rng_state], 42
    mov byte [benchmark_mode], 1
    call reset_game
    mov byte [board+199], 4
    call board_hash
    mov [ai_test_hash], rax
    mov rax, [rng_state]
    mov [ai_test_rng], rax
    mov rax, [score]
    mov [ai_test_score], rax
    mov rax, [high_score]
    mov [ai_test_best], rax
    mov rax, [piece_x]
    mov [ai_test_piece], rax
    mov rax, [piece_type]
    mov [ai_test_piece+8], rax
    lea rsi, [next_queue]
    lea rdi, [ai_test_queue]
    mov ecx, 5
    rep movsd
    call ai_plan
    cmp byte [ai_valid], 1
    jne .fail
    call board_hash
    cmp rax, [ai_test_hash]
    jne .fail
    mov rax, [rng_state]
    cmp rax, [ai_test_rng]
    jne .fail
    mov rax, [score]
    cmp rax, [ai_test_score]
    jne .fail
    mov rax, [piece_x]
    cmp rax, [ai_test_piece]
    jne .fail
    mov rax, [piece_type]
    cmp rax, [ai_test_piece+8]
    jne .fail
    lea rsi, [next_queue]
    lea rdi, [ai_test_queue]
    mov ecx, 5
    repe cmpsd
    jne .fail

    mov dword [ai_test_stage], 3
    ; A four-row well has an unambiguous I-piece solution.
    call reset_game
    lea rdi, [board+160]
    mov al, 2
    mov ecx, 40
    rep stosb
    mov byte [board+164], 0
    mov byte [board+174], 0
    mov byte [board+184], 0
    mov byte [board+194], 0
    mov dword [piece_type], 0
    call prepare_active_piece
    call ai_plan
    cmp byte [ai_valid], 1
    jne .fail
    call ai_test_execute
    test eax, eax
    jnz .fail
    cmp qword [total_lines], 4
    jne .fail
    call board_is_empty
    test eax, eax
    jz .fail
    ; Executed AI moves must never raise the persisted human high score.
    mov rax, [high_score]
    cmp rax, [ai_test_best]
    jne .fail

    mov dword [ai_test_stage], 4
    mov qword [rng_state], 2026
    call reset_game
    mov r13d, 120
.route:
    call ai_plan
    cmp byte [ai_valid], 1
    jne .fail
    call ai_test_execute
    test eax, eax
    jnz .fail
    cmp byte [game_state], STATE_PLAYING
    jne .fail
    dec r13d
    jnz .route

    mov dword [ai_test_stage], 5
    lea rdi, [board]
    mov al, 1
    mov ecx, BOARD_SIZE
    rep stosb
    mov dword [piece_type], 1
    mov dword [piece_x], 3
    mov dword [piece_y], -1
    mov dword [piece_rot], 0
    call ai_plan
    cmp byte [ai_valid], 0
    jne .fail
    cmp dword [ai_path_count], 0
    jne .fail
    lea rsi, [ai_test_pass]
    call write_z_stdout
    jmp .done
.fail:
    mov byte [test_failed], 1
    lea r15, [output_buf]
    lea rsi, [ai_test_fail]
    call append_z
    mov edi, [ai_test_stage]
    call append_u64
    lea rsi, [ai_test_newline]
    call append_z
    lea rsi, [output_buf]
    mov rdx, r15
    sub rdx, rsi
    call write_all_stdout
.done:
    mov byte [benchmark_mode], 0
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Verify every route using live physics. Before the final hard drop, check
; orientation/X and independently project its landing. Then compare the
; entire locked board with the scratch simulation, including line compaction.
; Return eax=0 success / 1 failure.
ai_test_execute:
    push rbx
    push r12
    push r14
    lea rdi, [board]
    lea rsi, [ai_test_board]
    mov edx, [ai_goal_rot]
    shl edx, 9
    mov eax, [ai_goal_y]
    add eax, 4
    shl eax, 4
    add edx, eax
    mov eax, [ai_goal_x]
    add eax, 3
    add edx, eax
    mov ecx, [piece_type]
    call ai_stamp_node
    test eax, eax
    js .fail
    xor r12d, r12d
.action:
    lea rbx, [ai_path]
    movzx edi, byte [rbx+r12]
    cmp edi, AI_DROP
    je .project
    mov r14, [piece_x]
    mov ebx, [piece_rot]
    call ai_execute_action
    mov rax, [piece_x]
    cmp rax, r14
    jne .changed
    cmp [piece_rot], ebx
    je .fail                     ; a route must never require a blocked move
.changed:
    inc r12d
    cmp r12d, [ai_path_count]
    jb .action
    jmp .fail
.project:
    mov eax, [piece_x]
    cmp eax, [ai_goal_x]
    jne .fail
    mov eax, [piece_rot]
    cmp eax, [ai_goal_rot]
    jne .fail
    mov r14d, [piece_y]
.fall:
    mov edi, [piece_x]
    lea esi, [r14d+1]
    mov edx, [piece_type]
    mov ecx, [piece_rot]
    call can_place
    test eax, eax
    jz .land
    inc r14d
    jmp .fall
.land:
    cmp r14d, [ai_goal_y]
    jne .fail
    mov edi, AI_DROP
    call ai_execute_action
    lea rdi, [board]
    lea rsi, [ai_test_board]
    mov ecx, BOARD_SIZE
    repe cmpsb
    jne .fail
    xor eax, eax
    jmp .done
.fail:
    mov eax, 1
.done:
    pop r14
    pop r12
    pop rbx
    ret
