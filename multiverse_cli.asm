section .rodata
mv_arg: db "--multiverse",0
mv_forecast_arg: db "--forecast",0
mv_json: db '{',10,'  "mode": "multiverse"',0
mv_jcount: db ',',10,'  "futures": ',0
mv_jhorizon: db ',',10,'  "horizon_ms": 8000',0
mv_jwall: db ',',10,'  "build_ms": ',0
mv_jorigin: db ',',10,'  "origin": {"left": ',0
mv_jright: db ', "right": {',0
mv_jarray: db ',',10,'  "branches": [',0
mv_jitem: db 10,'    {"id": ',0
mv_jnode: db ', "first_landing": ',0
mv_jtime: db ', "simulated_ms": ',0
mv_jwinner: db ', "winner": ',0
mv_jleft: db ', "left": {',0
mv_jend: db 10,'  ]',10,'}',10,0

section .text
parse_multiverse_cli:
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    xor r14d, r14d
    mov rdi, [r13+8]
    lea rsi, [mv_arg]
    call cli_equal
    test eax, eax
    jnz .found
    mov rdi, [r13+8]
    lea rsi, [mv_forecast_arg]
    call cli_equal
    test eax, eax
    jz .done
    mov r14d, 1
.found:
    cmp r12, 3
    ja parse_cli.invalid
    mov qword [arena_seed], 2026
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
    mov byte [arena_spectator], 1
    test r14d, r14d
    jnz .forecast
    mov byte [mv_startup], 1
    mov eax, 1
    jmp .done
.forecast:
    mov byte [arena_simulating], 1
    call arena_init
    call multiverse_warmup
    call multiverse_build
    call multiverse_json
    xor edi, edi
    jmp cli_exit
.done:
    pop r14
    pop r13
    pop r12
    ret

multiverse_json:
    push r12
    push r13
    push r15
    lea r15, [output_buf]
    lea rsi, [mv_json]
    call append_z
    BENCH_FIELD ar_jseed, [arena_seed]
    mov eax, [mv_count]
    BENCH_FIELD mv_jcount, rax
    lea rsi, [mv_jhorizon]
    call append_z
    BENCH_FIELD mv_jwall, [mv_build_ms]
    lea rsi, [mv_jorigin]
    call append_z
    mov dil, '{'
    call append_char
    lea rdi, [arena_left]
    call arena_json_player
    lea rsi, [mv_jright]
    call append_z
    lea rdi, [arena_right]
    call arena_json_player
    mov dil, '}'
    call append_char
    lea rsi, [mv_jarray]
    call append_z
    xor r12d, r12d
.branch:
    cmp r12d, [mv_count]
    jae .end
    test r12d, r12d
    jz .item
    mov dil, ','
    call append_char
.item:
    lea rdi, [r12+1]
    BENCH_FIELD mv_jitem, rdi
    mov edi, r12d
    xor esi, esi
    call multiverse_pointer
    mov r13, rax
    mov eax, [r13+HISTORY_HEADER+CTX(ai_goal_rot)]
    shl eax, 9
    mov edx, [r13+HISTORY_HEADER+CTX(ai_goal_y)]
    add edx, 4
    shl edx, 4
    add eax, edx
    add eax, [r13+HISTORY_HEADER+CTX(ai_goal_x)]
    add eax, 3
    BENCH_FIELD mv_jnode, rax
    mov edi, r12d
    mov esi, MV_FRAMES-1
    call multiverse_pointer
    mov rdx, [rax]
    sub rdx, [r13]
    mov r13, rax
    mov rax, rdx
    xor edx, edx
    mov ecx, 1000000
    div rcx
    BENCH_FIELD mv_jtime, rax
    mov eax, [r13+44]
    BENCH_FIELD mv_jwinner, rax
    lea rsi, [mv_jleft]
    call append_z
    lea rdi, [r13+HISTORY_HEADER]
    call arena_json_player
    lea rsi, [mv_jright]
    call append_z
    lea rdi, [r13+HISTORY_HEADER+GAME_CONTEXT_SIZE]
    call arena_json_player
    mov dil, '}'
    call append_char
    inc r12d
    jmp .branch
.end:
    lea rsi, [mv_jend]
    call append_z
    lea rsi, [output_buf]
    mov rdx, r15
    sub rdx, rsi
    call write_all_stdout
    pop r15
    pop r13
    pop r12
    ret
