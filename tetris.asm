BITS 64
DEFAULT REL

; Assembly Tetris -- Linux x86-64, NASM, direct syscalls only.
;
; Internal ABI: System V AMD64. Functions preserve RBX, RBP, and R12-R15.
; RAX, RCX, RDX, RSI, RDI, and R8-R11 are caller-saved. Scalar arguments use
; the standard integer registers. No function relies on a red zone.

%define SYS_read            0
%define SYS_write           1
%define SYS_close           3
%define SYS_poll            7
%define SYS_rt_sigaction   13
%define SYS_rt_sigreturn   15
%define SYS_ioctl          16
%define SYS_exit           60
%define SYS_fcntl          72
%define SYS_fsync          74
%define SYS_clock_gettime 228
%define SYS_getrandom     318
%define SYS_openat        257
%define SYS_clock_nanosleep 230

%define STDIN               0
%define STDOUT              1
%define STDERR              2
%define TCGETS         0x5401
%define TCSETS         0x5402
%define TIOCGWINSZ     0x5413
%define F_GETFL             3
%define F_SETFL             4
%define O_NONBLOCK       0x800
%define CLOCK_MONOTONIC     1
%define TIMER_ABSTIME       1
%define SA_RESTORER   0x04000000
%define AT_FDCWD          -100
%define O_WRONLY            1
%define O_CREAT          0x40
%define O_TRUNC         0x200

%define SIG_HUP             1
%define SIG_INT             2
%define SIG_QUIT            3
%define SIG_TERM           15

%define BOARD_W            10
%define BOARD_H            20
%define BOARD_SIZE        200
%define FRAME_CAP       32768
%define LOCK_DELAY_NS   500000000
%define LOCK_RESET_MAX  15
%define LAND_FLASH_NS    90000000
%define FRAME_NS         25000000
%define DAS_NS          150000000
%define ARR_NS           30000000
%define KEY_RELEASE_NS  120000000
%define REPEAT_WINDOW_NS 700000000

%define STATE_PLAYING       0
%define STATE_PAUSED        1
%define STATE_GAME_OVER     2

section .rodata

enter_screen: db 27,"[?1049h",27,"[2J",27,"[H",27,"[?25l",0
leave_screen: db 27,"[?2026l",27,"[0m",27,"[?25h",27,"[?1049l",0
home_seq:     db 27,"[H",0
erase_tail:   db 27,"[J",0

title:         db 27,"[1;38;5;117m  T E T R I S",27,"[0;38;5;245m  /  ASSEMBLY LAB",27,"[0m",27,"[K",13,10,0
top_border:    db 27,"[38;5;240m  ┌────────────────────┐",27,"[0m",0
bottom_border: db 27,"[38;5;240m  └────────────────────┘",27,"[0m",27,"[K",13,10,0
left_edge:     db 27,"[38;5;240m  │",27,"[0m",0
right_edge:    db 27,"[38;5;240m│",27,"[0m",0
row_end_seq:   db 27,"[0m",27,"[K",13,10,0
empty_cell:    db 27,"[48;5;234;38;5;238m· ",27,"[0m",0
preview_empty: db "  ",0

cyan_cell:     db 27,"[48;5;80m  ",27,"[0m",0
yellow_cell:   db 27,"[48;5;221m  ",27,"[0m",0
magenta_cell:  db 27,"[48;5;183m  ",27,"[0m",0
green_cell:    db 27,"[48;5;114m  ",27,"[0m",0
red_cell:      db 27,"[48;5;204m  ",27,"[0m",0
blue_cell:     db 27,"[48;5;75m  ",27,"[0m",0
orange_cell:   db 27,"[48;5;215m  ",27,"[0m",0
ghost_cell:    db 27,"[48;5;234;38;5;242m::",27,"[0m",0
hint_cell:     db 27,"[48;5;235;38;5;117m++",27,"[0m",0
flash_cell:    db 27,"[107m  ",27,"[0m",0
garbage_cell:  db 27,"[48;5;240;38;5;246m░░",27,"[0m",0

cell_colors: dq cyan_cell, yellow_cell, magenta_cell, green_cell
             dq red_cell, blue_cell, orange_cell, ghost_cell, hint_cell, flash_cell, garbage_cell

score_text:    db 27,"[38;5;245m    SCORE   ",27,"[1;38;5;231m",0
high_text:     db 27,"[0;38;5;245m    BEST    ",27,"[38;5;252m",0
lines_text:    db 27,"[0;38;5;245m    LINES   ",27,"[38;5;252m",0
level_text:    db 27,"[0;38;5;245m    LEVEL   ",27,"[38;5;252m",0
start_text:    db "  START ",0
combo_text:    db "    COMBO   ",0
b2b_text:      db "    B2B     ",0
b2b_on_text:   db "ON",0
b2b_off_text:  db "--",0
next_text:     db 27,"[38;5;117m    N E X T",27,"[0m",0
hold_text:     db 27,"[38;5;117m    H O L D",27,"[0m",0
controls_text: db 27,"[38;5;245m    C hold / Z reverse",27,"[0m",0
move_text:     db 27,"[38;5;245m    Arrows move / turn",27,"[0m",0
soft_text:     db 27,"[38;5;245m    Space hard drop",27,"[0m",0
playing_text:  db 27,"[38;5;245m  B auto  H hint  N one piece  |  ARR ",0
arr_suffix:    db "ms [-/+]",27,"[0m",0
paused_text:   db 27,"[1;38;5;221m  PAUSED",27,"[0m  [P] Resume  [R] Restart  [Q] Quit",0
gameover_text: db 27,"[1;38;5;204m  GAME OVER",27,"[0m  [R] Restart  [Q] Quit",0

tty_error: db "tetris: stdin and stdout must be interactive terminals",10
tty_error_len equ $-tty_error
setup_error: db "tetris: failed to configure terminal",10
setup_error_len equ $-setup_error
time_error: db "tetris: CLOCK_MONOTONIC is unavailable",10
time_error_len equ $-time_error

test_pass: db "Assembly Tetris self-test: PASS",10
test_pass_len equ $-test_pass
test_fail: db "Assembly Tetris self-test: FAIL",10
test_fail_len equ $-test_fail
uint_expected: db "18446744073709551615",0

; Bit n denotes row n/4, column n%4 in a 4x4 bounding box.
; Four rotation masks are stored for each I, O, T, S, Z, J, and L.
shapes:
    dw 0x00f0, 0x4444, 0x0f00, 0x2222 ; I, fixed SRS rotation center
    dw 0x0066, 0x0066, 0x0066, 0x0066 ; O
    dw 0x0072, 0x0262, 0x0270, 0x0232 ; T
    dw 0x0036, 0x0462, 0x0360, 0x0231 ; S
    dw 0x0063, 0x0264, 0x0630, 0x0132 ; Z
    dw 0x0071, 0x0226, 0x0470, 0x0322 ; J
    dw 0x0074, 0x0622, 0x0170, 0x0223 ; L

line_points: dq 0, 100, 300, 500, 800
mini_points: dq 100, 200, 400, 0, 0
tspin_points: dq 400, 800, 1200, 1600, 0
perfect_points: dq 0, 800, 1200, 1800, 2000
piece_letters: db "IOTSZJL"
highscore_path: db ".tetris_highscore",0

; Official Super Rotation System kick tests. Y values are converted from the
; SRS upward-positive coordinate system to this board's downward-positive Y.
; Each transition contains five signed (dx,dy) byte pairs.
srs_jlstz_cw:
    db 0,0, -1,0, -1,-1, 0,2, -1,2      ; 0 -> R
    db 0,0,  1,0,  1, 1, 0,-2, 1,-2     ; R -> 2
    db 0,0,  1,0,  1,-1, 0,2,  1,2      ; 2 -> L
    db 0,0, -1,0, -1, 1, 0,-2,-1,-2     ; L -> 0
srs_jlstz_ccw:
    db 0,0,  1,0,  1,-1, 0,2,  1,2      ; 0 -> L
    db 0,0,  1,0,  1, 1, 0,-2, 1,-2     ; R -> 0
    db 0,0, -1,0, -1,-1, 0,2, -1,2      ; 2 -> R
    db 0,0, -1,0, -1, 1, 0,-2,-1,-2     ; L -> 2
srs_i_cw:
    db 0,0, -2,0,  1,0, -2, 1,  1,-2    ; 0 -> R
    db 0,0, -1,0,  2,0, -1,-2,  2, 1    ; R -> 2
    db 0,0,  2,0, -1,0,  2,-1, -1, 2    ; 2 -> L
    db 0,0,  1,0, -2,0,  1, 2, -2,-1    ; L -> 0
srs_i_ccw:
    db 0,0, -1,0,  2,0, -1,-2,  2, 1    ; 0 -> L
    db 0,0,  2,0, -1,0,  2,-1, -1, 2    ; R -> 0
    db 0,0,  1,0, -2,0,  1, 2, -2,-1    ; 2 -> R
    db 0,0, -2,0,  1,0, -2, 1,  1,-2    ; L -> 2
section .data

; Linux kernel sigaction layout on x86-64: handler, flags, restorer, mask.
signal_action: dq signal_handler, SA_RESTORER, signal_restorer, 0

section .bss
%include "game_state.inc"
alignb 16
display_board:  resb BOARD_SIZE
old_termios:    resb 64
new_termios:    resb 64
stdout_termios: resb 64
input_buf:      resb 256
highscore_buf:  resb 32
output_buf:     resb FRAME_CAP
output_end:
time_now:       resq 2
sleep_deadline: resq 2

align 8
high_score:     resq 1
frame_deadline_ns: resq 1
old_flags:      resd 1
quit_flag:      resb 1
termios_active: resb 1
flags_active:   resb 1
escape_state:   resb 1
dirty:          resb 1
highscore_dirty: resb 1
test_failed:    resb 1

section .text
global _start

_start:
    xor ebp, ebp
    mov byte [ai_hint], 1
    mov rdi, [rsp]
    lea rsi, [rsp+8]
    call parse_cli

.interactive:
    call setup_terminal
    cmp eax, 1
    je fatal_tty
    test eax, eax
    jnz fatal_setup
    call install_signals
    test eax, eax
    jnz fatal_setup
    call init_random
    call load_high_score
    cmp byte [arena_mode], 0
    jne .arena_start
    call reset_game
    jmp .screen
.arena_start:
    call arena_init
    cmp byte [mv_startup], 0
    je .screen
    call multiverse_warmup
    call multiverse_enter
.screen:
    call get_wall_time_ns
    mov [frame_deadline_ns], rax
    lea rsi, [enter_screen]
    call write_z_stdout

.game_loop:
    call check_terminal_size
    call poll_input
    cmp byte [quit_flag], 0
    jne clean_exit
    cmp byte [arena_mode], 0
    jne .arena_loop
    call update_horizontal_repeat
    call update_game
    call ai_tick
    call maybe_render
    jmp .sleep
.arena_loop:
    call arena_tick
    call arena_maybe_render
.sleep:
    call sleep_frame_absolute
    jmp .game_loop

fatal_setup:
    mov eax, SYS_write
    mov edi, STDERR
    lea rsi, [setup_error]
    mov edx, setup_error_len
    syscall
    mov edi, 1
    jmp cleanup_exit

fatal_tty:
    mov eax, SYS_write
    mov edi, STDERR
    lea rsi, [tty_error]
    mov edx, tty_error_len
    syscall
    mov edi, 1
    mov eax, SYS_exit
    syscall

fatal_time:
    mov eax, SYS_write
    mov edi, STDERR
    lea rsi, [time_error]
    mov edx, time_error_len
    syscall
    mov edi, 1
    jmp cleanup_exit

clean_exit:
    xor edi, edi

; cleanup_exit(edi=status) restores fd flags, termios, colors, and cursor.
cleanup_exit:
    push rdi
    cmp byte [flags_active], 0
    je .termios
    mov eax, SYS_fcntl
    mov edi, STDIN
    mov esi, F_SETFL
    mov edx, [old_flags]
    syscall
    mov byte [flags_active], 0
.termios:
    cmp byte [termios_active], 0
    je .visual
    mov eax, SYS_ioctl
    mov edi, STDIN
    mov esi, TCSETS
    lea rdx, [old_termios]
    syscall
    mov byte [termios_active], 0
.visual:
    lea rsi, [leave_screen]
    call write_z_stdout
    call save_high_score
    pop rdi
    mov eax, SYS_exit
    syscall

; A caught signal cannot return into the game: clean up and exit 128+signal.
signal_handler:
    add edi, 128
    jmp cleanup_exit

signal_restorer:
    mov eax, SYS_rt_sigreturn
    syscall

; setup_terminal() -> eax=0 success, 1 not a tty, 2 setup failure.
setup_terminal:
    mov eax, SYS_ioctl
    mov edi, STDOUT
    mov esi, TCGETS
    lea rdx, [stdout_termios]
    syscall
    test rax, rax
    js .not_tty
    mov eax, SYS_ioctl
    mov edi, STDIN
    mov esi, TCGETS
    lea rdx, [old_termios]
    syscall
    test rax, rax
    js .not_tty

    lea rsi, [old_termios]
    lea rdi, [new_termios]
    mov ecx, 64
    rep movsb
    and dword [new_termios+0], 0xfffffa14 ; raw input flags
    and dword [new_termios+8], 0xfffffecf ; no CSIZE/PARENB
    or  dword [new_termios+8], 0x30       ; CS8
    and dword [new_termios+12], 0xffff7fb4 ; no echo/canonical/signals
    mov byte [new_termios+22], 0          ; VTIME
    mov byte [new_termios+23], 0          ; VMIN

    mov eax, SYS_ioctl
    mov edi, STDIN
    mov esi, TCSETS
    lea rdx, [new_termios]
    syscall
    test rax, rax
    js .failed
    mov byte [termios_active], 1

    mov eax, SYS_fcntl
    mov edi, STDIN
    mov esi, F_GETFL
    xor edx, edx
    syscall
    test rax, rax
    js .failed
    mov [old_flags], eax
    or eax, O_NONBLOCK
    mov edx, eax
    mov eax, SYS_fcntl
    mov edi, STDIN
    mov esi, F_SETFL
    syscall
    test rax, rax
    js .failed
    mov byte [flags_active], 1
    xor eax, eax
    ret
.not_tty:
    mov eax, 1
    ret
.failed:
    mov eax, 2
    ret

install_signals:
    mov edi, SIG_HUP
    call install_one_signal
    test eax, eax
    jnz .done
    mov edi, SIG_INT
    call install_one_signal
    test eax, eax
    jnz .done
    mov edi, SIG_QUIT
    call install_one_signal
    test eax, eax
    jnz .done
    mov edi, SIG_TERM
    call install_one_signal
.done:
    ret

install_one_signal:
    mov eax, SYS_rt_sigaction
    lea rsi, [signal_action]
    xor edx, edx
    mov r10d, 8
    syscall
    test rax, rax
    setnz al
    movzx eax, al
    ret

; get_time_ns() -> rax = monotonic nanoseconds, or exits on failure.
get_time_ns:
    cmp byte [arena_mode], 0
    je get_wall_time_ns
    mov rax, [arena_now]
    ret
get_wall_time_ns:
    mov eax, SYS_clock_gettime
    mov edi, CLOCK_MONOTONIC
    lea rsi, [time_now]
    syscall
    test rax, rax
    js fatal_time
    mov rax, [time_now]
    imul rax, rax, 1000000000
    add rax, [time_now+8]
    ret

; Best-effort persistent high score. Malformed or inaccessible files are
; ignored so gameplay never depends on writable storage.
load_high_score:
    push rbx
    push r12
    push r13
    mov qword [high_score], 0
    mov byte [highscore_dirty], 0
    mov eax, SYS_openat
    mov edi, AT_FDCWD
    lea rsi, [highscore_path]
    xor edx, edx
    xor r10d, r10d
    syscall
    test rax, rax
    js .done
    mov r12, rax
    mov eax, SYS_read
    mov rdi, r12
    lea rsi, [highscore_buf]
    mov edx, 31
    syscall
    mov r13, rax
    mov eax, SYS_close
    mov rdi, r12
    syscall
    test r13, r13
    jle .done
    lea rbx, [highscore_buf]
    xor eax, eax
    xor ecx, ecx
    xor r9d, r9d
.parse:
    cmp rcx, r13
    jae .accept
    movzx r8d, byte [rbx+rcx]
    cmp r8b, 10
    je .accept
    cmp r8b, '0'
    jb .done
    cmp r8b, '9'
    ja .done
    sub r8d, '0'
    mov r10d, 10
    mul r10
    test rdx, rdx
    jnz .done
    add rax, r8
    jc .done
    inc r9d
    inc ecx
    jmp .parse
.accept:
    test r9d, r9d
    jz .done
    mov [high_score], rax
.done:
    pop r13
    pop r12
    pop rbx
    ret

save_high_score:
    push rbx
    push r12
    push r13
    cmp byte [highscore_dirty], 0
    je .done
    mov eax, SYS_openat
    mov edi, AT_FDCWD
    lea rsi, [highscore_path]
    mov edx, O_WRONLY | O_CREAT | O_TRUNC
    mov r10d, 0644o
    syscall
    test rax, rax
    js .done
    mov r12, rax
    lea r13, [highscore_buf]
    mov rax, [high_score]
    test rax, rax
    jnz .digits
    mov byte [r13], '0'
    inc r13
    jmp .newline
.digits:
    xor ecx, ecx
    mov ebx, 10
.divide:
    xor edx, edx
    div rbx
    push rdx
    inc ecx
    test rax, rax
    jnz .divide
.emit:
    pop rdx
    add dl, '0'
    mov [r13], dl
    inc r13
    dec ecx
    jnz .emit
.newline:
    mov byte [r13], 10
    inc r13
    lea rsi, [highscore_buf]
    mov rdx, r13
    sub rdx, rsi
.write:
    mov eax, SYS_write
    mov rdi, r12
    syscall
    cmp rax, -4
    je .write
    test rax, rax
    jle .close
    add rsi, rax
    sub rdx, rax
    jnz .write
    mov eax, SYS_fsync
    mov rdi, r12
    syscall
    mov byte [highscore_dirty], 0
.close:
    mov eax, SYS_close
    mov rdi, r12
    syscall
.done:
    pop r13
    pop r12
    pop rbx
    ret

init_random:
    mov eax, SYS_getrandom
    lea rdi, [rng_state]
    mov esi, 8
    xor edx, edx
    syscall
    cmp rax, 8
    je .check
    call get_time_ns
    xor rax, rsp
    mov [rng_state], rax
.check:
    cmp qword [rng_state], 0
    jne .done
    mov rax, 0x9e3779b97f4a7c15
    mov [rng_state], rax
.done:
    ret

random_u64:
    mov rax, [rng_state]
    mov rdx, rax
    shl rdx, 13
    xor rax, rdx
    mov rdx, rax
    shr rdx, 7
    xor rax, rdx
    mov rdx, rax
    shl rdx, 17
    xor rax, rdx
    mov [rng_state], rax
    ret

; random_bounded(edi=n) -> eax in [0,n), with rejection against modulo bias.
random_bounded:
    push rbx
    push r12
    mov ebx, edi
    xor eax, eax
    sub rax, rbx
    xor edx, edx
    div rbx
    mov r12, rdx
.retry:
    call random_u64
    cmp rax, r12
    jb .retry
    xor edx, edx
    div rbx
    mov eax, edx
    pop r12
    pop rbx
    ret

; Refill with 0..6, then Fisher-Yates shuffle.
refill_bag:
    push rbx
    push r12
    lea rbx, [bag]
    xor eax, eax
.fill:
    mov [rbx+rax], al
    inc eax
    cmp eax, 7
    jb .fill
    mov r12d, 6
.shuffle:
    lea edi, [r12d+1]
    call random_bounded
    mov dl, [rbx+r12]
    mov cl, [rbx+rax]
    mov [rbx+r12], cl
    mov [rbx+rax], dl
    dec r12d
    jnz .shuffle
    mov byte [bag_index], 0
    pop r12
    pop rbx
    ret

next_from_bag:
    movzx ecx, byte [bag_index]
    cmp ecx, 7
    jb .have
    call refill_bag
    xor ecx, ecx
.have:
    lea rdx, [bag]
    movzx eax, byte [rdx+rcx]
    inc ecx
    mov [bag_index], cl
    ret

init_next_queue:
    push rbx
    push r12
    lea rbx, [next_queue]
    xor r12d, r12d
.fill:
    call next_from_bag
    mov [rbx+r12*4], eax
    inc r12d
    cmp r12d, 5
    jb .fill
    pop r12
    pop rbx
    ret

; Pop queue[0], shift the remaining four entries, and append one bag piece.
pop_next_piece:
    push r12
    mov r12d, [next_queue]
    mov eax, [next_queue+4]
    mov [next_queue], eax
    mov eax, [next_queue+8]
    mov [next_queue+4], eax
    mov eax, [next_queue+12]
    mov [next_queue+8], eax
    mov eax, [next_queue+16]
    mov [next_queue+12], eax
    call next_from_bag
    mov [next_queue+16], eax
    mov eax, r12d
    pop r12
    ret

reset_game:
    cmp qword [ai_interval], 0
    jne .pilot_ready
    mov qword [ai_interval], 75000000
.pilot_ready:
    mov byte [ai_cached], 0
    mov byte [ai_single], 0
    mov al, [ai_auto]
    or al, [benchmark_mode]
    mov [assisted_run], al
    mov qword [pieces_locked], 0
    lea rdi, [board]
    xor eax, eax
    mov ecx, BOARD_SIZE
    rep stosb
    mov qword [score], 0
    mov qword [total_lines], 0
    cmp qword [start_level], 1
    jae .have_start
    mov qword [start_level], 1
.have_start:
    cmp qword [arr_interval_ns], 0
    jne .have_arr
    mov qword [arr_interval_ns], ARR_NS
.have_arr:
    mov rax, [start_level]
    mov [level], rax
    mov qword [combo], -1
    mov byte [b2b_active], 0
    mov dword [hold_type], -1
    mov qword [flash_until_ns], 0
    mov byte [flash_count], 0
    mov byte [hard_drop_lock], 0
    mov byte [game_state], STATE_PLAYING
    mov byte [quit_flag], 0
    mov byte [escape_state], 0
    mov byte [bag_index], 7
    mov byte [das_active], 0
    mov dword [horizontal_dir], 0
    call init_next_queue
    call spawn_piece
    call get_time_ns
    mov [last_drop_ns], rax
    mov byte [dirty], 1
    ret

spawn_piece:
    call pop_next_piece
    mov [piece_type], eax
    mov byte [hold_used], 0
    call prepare_active_piece
    ret

; Reset position and per-piece timing for piece_type, then validate its spawn.
prepare_active_piece:
    inc qword [piece_serial]
    mov dword [piece_x], 3
    mov dword [piece_y], -1
    mov dword [piece_rot], 0
    mov byte [grounded], 0
    mov byte [lock_resets], 0
    mov byte [last_action_rotate], 0
    mov byte [last_kick_index], 0
    mov byte [dirty], 1
    mov edi, 3
    mov esi, -1
    mov edx, [piece_type]
    xor ecx, ecx
    call can_place
    test eax, eax
    jnz .done
    mov byte [game_state], STATE_GAME_OVER
.done:
    ret

; can_place(edi=x, esi=y, edx=type, ecx=rotation) -> eax=1 if valid.
; Negative visible rows are permitted but never dereferenced.
can_place:
    lea r11, [board]
; Same collision routine on an explicit board: r11=200-byte board pointer.
; R11 is preserved, so both the live game and the planner share these rules.
can_place_on_board:
    push rbx
    mov r8d, edi
    mov r9d, esi
    and ecx, 3
    mov eax, edx
    shl eax, 2
    add eax, ecx
    lea rbx, [shapes]
    movzx r10d, word [rbx+rax*2]
    xor ecx, ecx
.cell:
    cmp ecx, 16
    je .yes
    bt r10d, ecx
    jnc .next
    mov eax, ecx
    and eax, 3
    add eax, r8d
    cmp eax, 0
    jl .no
    cmp eax, BOARD_W
    jge .no
    mov edx, ecx
    shr edx, 2
    add edx, r9d
    cmp edx, BOARD_H
    jge .no
    test edx, edx
    js .next
    imul edx, edx, BOARD_W
    add edx, eax
    mov rbx, r11
    cmp byte [rbx+rdx], 0
    jne .no
.next:
    inc ecx
    jmp .cell
.yes:
    mov eax, 1
    pop rbx
    ret
.no:
    xor eax, eax
    pop rbx
    ret

try_left:
    mov edi, [piece_x]
    dec edi
    mov esi, [piece_y]
    mov edx, [piece_type]
    mov ecx, [piece_rot]
    call can_place
    test eax, eax
    jz .done
    dec dword [piece_x]
    mov byte [last_action_rotate], 0
    mov byte [dirty], 1
    call after_player_transform
.done:
    ret

try_right:
    mov edi, [piece_x]
    inc edi
    mov esi, [piece_y]
    mov edx, [piece_type]
    mov ecx, [piece_rot]
    call can_place
    test eax, eax
    jz .done
    inc dword [piece_x]
    mov byte [last_action_rotate], 0
    mov byte [dirty], 1
    call after_player_transform
.done:
    ret

; Official SRS rotation. rotate_piece(edi=1 clockwise, edi=-1 counter-clockwise)
; returns eax=1 when a rotation commits, zero when all five tests fail.
rotate_piece:
    mov r8d, edi
    mov edi, [piece_x]
    mov esi, [piece_y]
    mov edx, [piece_type]
    mov ecx, [piece_rot]
    lea r11, [board]
    call find_rotation
    test eax, eax
    jz .done
    mov [piece_x], edi
    mov [piece_y], esi
    mov [piece_rot], ecx
    mov [last_kick_index], dl
    mov byte [last_action_rotate], 1
    mov byte [dirty], 1
    call after_player_transform
    mov eax, 1
.done:
    ret

; Pure SRS query, shared by live controls and search. No game state is changed.
; In: edi=x, esi=y, edx=type, ecx=old rotation, r8d=+1/-1, r11=board.
; Out: eax=success; edi/esi=new x/y, ecx=new rotation, edx=kick index.
find_rotation:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 16
    mov [rsp], edi
    mov [rsp+4], esi
    mov ebp, edx
    mov r15d, r8d
    mov r12d, ecx
    mov r13d, ecx
    add r13d, r8d
    and r13d, 3
    cmp ebp, 1
    jne .choose_table
    mov ecx, r13d
    xor edx, edx
    mov eax, 1
    jmp .done
.choose_table:
    test ebp, ebp
    je .i_piece
    test r15d, r15d
    js .jlstz_ccw
    lea rbx, [srs_jlstz_cw]
    jmp .table_ready
.jlstz_ccw:
    lea rbx, [srs_jlstz_ccw]
    jmp .table_ready
.i_piece:
    test r15d, r15d
    js .i_ccw
    lea rbx, [srs_i_cw]
    jmp .table_ready
.i_ccw:
    lea rbx, [srs_i_ccw]
.table_ready:
    imul eax, r12d, 10
    add rbx, rax
    xor r14d, r14d
.kick_loop:
    movsx eax, byte [rbx+r14*2]
    mov edi, [rsp]
    add edi, eax
    movsx eax, byte [rbx+r14*2+1]
    mov esi, [rsp+4]
    add esi, eax
    mov edx, ebp
    mov ecx, r13d
    call can_place_on_board
    test eax, eax
    jnz .commit
    inc r14d
    cmp r14d, 5
    jb .kick_loop
    xor eax, eax
    jmp .done
.commit:
    movsx eax, byte [rbx+r14*2]
    mov edi, [rsp]
    add edi, eax
    movsx eax, byte [rbx+r14*2+1]
    mov esi, [rsp+4]
    add esi, eax
    mov ecx, r13d
    mov edx, r14d
    mov eax, 1
.done:
    add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

try_rotate:
    mov edi, 1
    jmp rotate_piece

try_rotate_ccw:
    mov edi, -1
    jmp rotate_piece

can_active_fall:
    mov edi, [piece_x]
    mov esi, [piece_y]
    inc esi
    mov edx, [piece_type]
    mov ecx, [piece_rot]
    jmp can_place

; Start a lock deadline when newly grounded, without consuming a reset.
ensure_ground_state:
    call can_active_fall
    test eax, eax
    jz .blocked
    mov byte [grounded], 0
    ret
.blocked:
    cmp byte [grounded], 0
    jne .done
    call get_time_ns
    add rax, LOCK_DELAY_NS
    mov [lock_deadline], rax
    mov byte [grounded], 1
.done:
    ret

; A successful player move/rotation may reset lock delay at most 15 times.
after_player_transform:
    call can_active_fall
    test eax, eax
    jz .still_grounded
    mov byte [grounded], 0
    ret
.still_grounded:
    cmp byte [grounded], 0
    je .first_contact
    cmp byte [lock_resets], LOCK_RESET_MAX
    jae .done
    inc byte [lock_resets]
.first_contact:
    call get_time_ns
    add rax, LOCK_DELAY_NS
    mov [lock_deadline], rax
    mov byte [grounded], 1
.done:
    ret

; step_down() -> eax=0 moved, eax=1 blocked. Locking is deadline-driven.
step_down:
    call can_active_fall
    test eax, eax
    jz .blocked
    inc dword [piece_y]
    mov byte [last_action_rotate], 0
    mov byte [grounded], 0
    mov byte [dirty], 1
    call ensure_ground_state
    xor eax, eax
    ret
.blocked:
    call ensure_ground_state
    mov eax, 1
    ret

hard_drop:
    push r12
    xor r12d, r12d
.fall:
    mov edi, [piece_x]
    mov esi, [piece_y]
    inc esi
    mov edx, [piece_type]
    mov ecx, [piece_rot]
    call can_place
    test eax, eax
    jz .land
    inc dword [piece_y]
    inc r12d
    jmp .fall
.land:
    mov eax, r12d
    shl eax, 1
    add [score], rax
    call update_high_score
    mov byte [hard_drop_lock], 1
    call finish_lock
    pop r12
    ret

hold_piece:
    cmp byte [hold_used], 0
    jne .done
    mov eax, [piece_type]
    cmp dword [hold_type], -1
    jne .swap
    mov [hold_type], eax
    call pop_next_piece
    mov [piece_type], eax
    jmp .prepare
.swap:
    xchg eax, [hold_type]
    mov [piece_type], eax
.prepare:
    mov byte [hold_used], 1
    call prepare_active_piece
    call get_time_ns
    mov [last_drop_ns], rax
.done:
    ret

finish_lock:
    mov byte [dirty], 1
    call detect_tspin
    mov [spin_kind], al
    call lock_piece
    test eax, eax
    jnz .done
    inc qword [pieces_locked]
    mov byte [ai_single], 0       ; N stops even when gravity/lock delay locks it
    call clear_lines
    push rax
    mov dl, [b2b_active]
    mov [battle_prior_b2b], dl
    mov edi, eax
    call score_lock_event
    pop rax
    push rax
    mov edi, eax
    call arena_on_lock
    pop rax
    test eax, eax
    jnz .no_flash
    cmp byte [hard_drop_lock], 0
    je .no_flash
    call get_time_ns
    add rax, LAND_FLASH_NS
    mov [flash_until_ns], rax
    jmp .after_flash
.no_flash:
    mov byte [flash_count], 0
.after_flash:
    mov byte [hard_drop_lock], 0
    call spawn_piece
    call get_time_ns
    mov [last_drop_ns], rax
.done:
    ret

; Out-of-bounds corners count occupied for T-spin classification.
corner_occupied:
    cmp edi, 0
    jl .yes
    cmp edi, BOARD_W
    jge .yes
    cmp esi, 0
    jl .yes
    cmp esi, BOARD_H
    jge .yes
    imul eax, esi, BOARD_W
    add eax, edi
    lea rdx, [board]
    cmp byte [rdx+rax], 0
    setne al
    movzx eax, al
    ret
.yes:
    mov eax, 1
    ret

; Returns 0 normal, 1 T-spin mini, 2 full T-spin.
detect_tspin:
    push r12
    push r13
    push r14
    cmp dword [piece_type], 2
    jne .none
    cmp byte [last_action_rotate], 0
    je .none
    mov r12d, [piece_x]
    mov r13d, [piece_y]
    xor r14d, r14d
    mov edi, r12d
    mov esi, r13d
    call corner_occupied
    add r14d, eax
    lea edi, [r12d+2]
    mov esi, r13d
    call corner_occupied
    add r14d, eax
    mov edi, r12d
    lea esi, [r13d+2]
    call corner_occupied
    add r14d, eax
    lea edi, [r12d+2]
    lea esi, [r13d+2]
    call corner_occupied
    add r14d, eax
    cmp r14d, 3
    jb .none

    ; Count the two corners in front of the T's pointing direction.
    xor r14d, r14d
    mov eax, [piece_rot]
    cmp eax, 0
    je .front_up
    cmp eax, 1
    je .front_right
    cmp eax, 2
    je .front_down
    mov edi, r12d                 ; front left
    mov esi, r13d
    call corner_occupied
    add r14d, eax
    mov edi, r12d
    lea esi, [r13d+2]
    jmp .second_front
.front_up:
    mov edi, r12d
    mov esi, r13d
    call corner_occupied
    add r14d, eax
    lea edi, [r12d+2]
    mov esi, r13d
    jmp .second_front
.front_right:
    lea edi, [r12d+2]
    mov esi, r13d
    call corner_occupied
    add r14d, eax
    lea edi, [r12d+2]
    lea esi, [r13d+2]
    jmp .second_front
.front_down:
    mov edi, r12d
    lea esi, [r13d+2]
    call corner_occupied
    add r14d, eax
    lea edi, [r12d+2]
    lea esi, [r13d+2]
.second_front:
    call corner_occupied
    add r14d, eax
    cmp r14d, 2
    je .full
    cmp byte [last_kick_index], 4 ; fifth SRS kick promotes mini to full
    je .full
    mov eax, 1
    jmp .return
.full:
    mov eax, 2
    jmp .return
.none:
    xor eax, eax
.return:
    pop r14
    pop r13
    pop r12
    ret

; lock_piece() -> eax=1 on top-out; otherwise writes four cells and returns 0.
lock_piece:
    push rbx
    push r12
    push r13
    mov eax, [piece_type]
    shl eax, 2
    add eax, [piece_rot]
    lea rbx, [shapes]
    movzx r12d, word [rbx+rax*2]
    xor ecx, ecx
.top_check:
    cmp ecx, 16
    je .write_start
    bt r12d, ecx
    jnc .top_next
    mov eax, ecx
    shr eax, 2
    add eax, [piece_y]
    test eax, eax
    js .top_out
.top_next:
    inc ecx
    jmp .top_check
.write_start:
    xor ecx, ecx
    xor r13d, r13d
.write:
    cmp ecx, 16
    je .ok
    bt r12d, ecx
    jnc .write_next
    mov eax, ecx
    and eax, 3
    add eax, [piece_x]
    mov edx, ecx
    shr edx, 2
    add edx, [piece_y]
    imul edx, edx, BOARD_W
    add edx, eax
    lea rbx, [board]
    mov eax, [piece_type]
    inc eax
    mov [rbx+rdx], al
    cmp byte [hard_drop_lock], 0
    je .write_next
    mov [landing_cells+r13*4], edx
    inc r13d
.write_next:
    inc ecx
    jmp .write
.top_out:
    mov byte [game_state], STATE_GAME_OVER
    mov eax, 1
    pop r13
    pop r12
    pop rbx
    ret
.ok:
    mov [flash_count], r13b
    xor eax, eax
    pop r13
    pop r12
    pop rbx
    ret

; Compact every non-full row toward the bottom. Returns clear count in eax.
clear_lines:
    lea rdi, [board]
; clear_lines_on_board(rdi=board) is also used for isolated search positions.
clear_lines_on_board:
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12d, BOARD_H-1
    mov r13d, BOARD_H-1
    xor r14d, r14d
.scan:
    test r12d, r12d
    js .zero_remaining
    imul eax, r12d, BOARD_W
    xor ecx, ecx
.check_cell:
    mov edx, eax
    add edx, ecx
    cmp byte [rbx+rdx], 0
    je .not_full
    inc ecx
    cmp ecx, BOARD_W
    jb .check_cell
    inc r14d
    dec r12d
    jmp .scan
.not_full:
    cmp r13d, r12d
    je .kept
    imul esi, r12d, BOARD_W
    imul edi, r13d, BOARD_W
    mov ecx, BOARD_W
.copy_cell:
    mov al, [rbx+rsi]
    mov [rbx+rdi], al
    inc esi
    inc edi
    dec ecx
    jnz .copy_cell
.kept:
    dec r12d
    dec r13d
    jmp .scan
.zero_remaining:
    test r13d, r13d
    js .score
    mov rdi, rbx
    mov eax, r13d
    inc eax
    imul ecx, eax, BOARD_W
    xor eax, eax
    rep stosb
.score:
.return:
    mov eax, r14d
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

board_is_empty:
    lea rdi, [board]
    mov ecx, BOARD_SIZE
.scan:
    cmp byte [rdi], 0
    jne .no
    inc rdi
    dec ecx
    jnz .scan
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

; score_lock_event(edi=cleared lines) implements guideline-style line,
; T-spin, combo, back-to-back, and perfect-clear scoring.
score_lock_event:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12d, edi
    mov r13, [level]
    movzx eax, byte [b2b_active]
    mov r15d, eax                 ; B2B state before this event
    xor r14d, r14d
    cmp byte [spin_kind], 1
    je .mini
    cmp byte [spin_kind], 2
    je .full_spin
    mov eax, r12d
    cmp eax, 4
    jbe .normal_index
    mov eax, 4
.normal_index:
    lea rdx, [line_points]
    mov r14, [rdx+rax*8]
    jmp .difficulty
.mini:
    mov eax, r12d
    cmp eax, 4
    jbe .mini_index
    mov eax, 4
.mini_index:
    lea rdx, [mini_points]
    mov r14, [rdx+rax*8]
    cmp r12d, 2
    jbe .difficulty
    jmp .full_spin
.full_spin:
    mov eax, r12d
    cmp eax, 4
    jbe .spin_index
    mov eax, 4
.spin_index:
    lea rdx, [tspin_points]
    mov r14, [rdx+rax*8]

.difficulty:
    xor ebx, ebx
    test r12d, r12d
    jz .apply_base
    cmp byte [spin_kind], 0
    jne .difficult
    cmp r12d, 4
    jne .not_difficult
.difficult:
    mov ebx, 1
    test r15d, r15d
    jz .set_b2b
    mov rax, r14
    shr rax, 1
    add r14, rax
.set_b2b:
    mov byte [b2b_active], 1
    jmp .apply_base
.not_difficult:
    mov byte [b2b_active], 0

.apply_base:
    mov rax, r14
    imul rax, r13
    add [score], rax
    test r12d, r12d
    jz .break_combo
    inc qword [combo]
    mov rax, [combo]
    test rax, rax
    jle .perfect_check
    imul rax, rax, 50
    imul rax, r13
    add [score], rax
    jmp .perfect_check
.break_combo:
    mov qword [combo], -1

.perfect_check:
    test r12d, r12d
    jz .update_progress
    call board_is_empty
    test eax, eax
    jz .update_progress
    mov eax, r12d
    cmp eax, 4
    jbe .perfect_index
    mov eax, 4
.perfect_index:
    lea rdx, [perfect_points]
    mov rax, [rdx+rax*8]
    cmp r12d, 4
    jne .perfect_add
    test r15d, r15d
    jz .perfect_add
    mov eax, 3200
.perfect_add:
    imul rax, r13
    add [score], rax

.update_progress:
    mov eax, r12d
    add [total_lines], rax
    mov rax, [total_lines]
    xor edx, edx
    mov ecx, 10
    div rcx
    add rax, [start_level]
    mov [level], rax
    call update_high_score
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

update_high_score:
    cmp byte [arena_mode], 0
    jne .done
    cmp byte [assisted_run], 0
    jne .done
    mov rax, [score]
    cmp rax, [high_score]
    jbe .done
    mov [high_score], rax
    mov byte [highscore_dirty], 1
.done:
    ret

; Gravity is 700 ms at level 1, 60 ms faster per level, floor 80 ms.
gravity_interval_ns:
    mov rax, [level]
    dec rax
    imul rax, rax, 60000000
    mov rdx, 700000000
    cmp rax, 620000000
    jae .minimum
    sub rdx, rax
    mov rax, rdx
    ret
.minimum:
    mov eax, 80000000
    ret

update_game:
    push r12
    push r13
    cmp byte [game_state], STATE_PLAYING
    jne .done
    cmp byte [ui_too_small], 0
    jne .done
    call get_time_ns
    mov r12, rax
    cmp byte [grounded], 0
    je .gravity
    cmp r12, [lock_deadline]
    jb .gravity
    call finish_lock
    jmp .done
.gravity:
    xor r13d, r13d
.catch_up:
    call gravity_interval_ns
    mov rdx, rax
    mov rax, r12
    sub rax, [last_drop_ns]
    cmp rax, rdx
    jb .done
    add [last_drop_ns], rdx
    call step_down
    test eax, eax
    jnz .done
    inc r13d
    cmp r13d, 8
    jb .catch_up
    mov [last_drop_ns], r12          ; cap pathological scheduler catch-up
.done:
    pop r13
    pop r12
    ret

; Legacy terminals report repeats but not key releases. A second same-direction
; event confirms DAS; ARR then runs while repeat events refresh the timestamp.
handle_horizontal_input:
    push r12
    push r13
    mov r12d, edi
    call get_time_ns
    mov r13, rax
    cmp [horizontal_dir], r12d
    jne .new_press
    mov rax, r13
    sub rax, [horizontal_last_ns]
    cmp rax, REPEAT_WINDOW_NS
    ja .new_press
    mov [horizontal_last_ns], r13
    cmp byte [das_active], 0
    jne .done
    cmp r13, [das_deadline_ns]
    jb .move_now
    mov byte [das_active], 1
    mov rax, r13
    add rax, [arr_interval_ns]
    mov [arr_deadline_ns], rax
    jmp .move_now
.new_press:
    mov [horizontal_dir], r12d
    mov [horizontal_last_ns], r13
    mov rax, r13
    add rax, DAS_NS
    mov [das_deadline_ns], rax
    mov byte [das_active], 0
.move_now:
    test r12d, r12d
    js .left
    call try_right
    jmp .done
.left:
    call try_left
.done:
    pop r13
    pop r12
    ret

update_horizontal_repeat:
    push r12
    push r13
    cmp byte [das_active], 0
    je .done
    cmp byte [game_state], STATE_PLAYING
    jne .cancel
    cmp byte [ui_too_small], 0
    jne .cancel
    call get_time_ns
    mov r12, rax
    sub rax, [horizontal_last_ns]
    cmp rax, KEY_RELEASE_NS
    ja .cancel
    xor r13d, r13d
.repeat:
    cmp r12, [arr_deadline_ns]
    jb .done
    cmp dword [horizontal_dir], 0
    jl .left
    call try_right
    jmp .advanced
.left:
    call try_left
.advanced:
    mov rax, [arr_interval_ns]
    add [arr_deadline_ns], rax
    inc r13d
    cmp r13d, 4
    jb .repeat
    jmp .done
.cancel:
    mov byte [das_active], 0
.done:
    pop r13
    pop r12
    ret

maybe_render:
    cmp byte [dirty], 0
    jne render_frame
    cmp byte [flash_count], 0
    je .done
    call get_time_ns
    cmp rax, [flash_until_ns]
    jb .done
    mov byte [flash_count], 0
    mov byte [dirty], 1
    jmp render_frame
.done:
    ret

sleep_frame_absolute:
    push r12
    mov r12, [frame_deadline_ns]
    add r12, FRAME_NS
    call get_wall_time_ns
    cmp r12, rax
    ja .deadline_ready
    lea r12, [rax+FRAME_NS]
.deadline_ready:
    mov [frame_deadline_ns], r12
    mov rax, r12
    xor edx, edx
    mov ecx, 1000000000
    div rcx
    mov [sleep_deadline], rax
    mov [sleep_deadline+8], rdx
.sleep:
    mov eax, SYS_clock_nanosleep
    mov edi, CLOCK_MONOTONIC
    mov esi, TIMER_ABSTIME
    lea rdx, [sleep_deadline]
    xor r10d, r10d
    syscall
    cmp rax, -4
    je .sleep
    pop r12
    ret

poll_input:
    push rbx
    push r12
    push r13
.read_more:
    mov eax, SYS_read
    mov edi, STDIN
    lea rsi, [input_buf]
    mov edx, 256
    syscall
    test rax, rax
    jle .done
    mov r12, rax
    xor r13d, r13d
.byte_loop:
    cmp r13, r12
    jae .read_more
    lea rbx, [input_buf]
    movzx edi, byte [rbx+r13]
    inc r13
    call process_input_byte
    cmp byte [quit_flag], 0
    je .byte_loop
.done:
    pop r13
    pop r12
    pop rbx
    ret

; Persistent state prevents split ESC [ A/B/C/D reads from being misparsed.
process_input_byte:
    movzx eax, byte [escape_state]
    cmp eax, 1
    je .after_esc
    cmp eax, 2
    je .after_bracket
    cmp dil, 27
    je .start_esc
    jmp .normal
.after_esc:
    mov byte [escape_state], 0
    cmp dil, '['
    jne .normal
    mov byte [escape_state], 2
    ret
.after_bracket:
    mov byte [escape_state], 0
    push rdi
    call arena_arrow
    pop rdi
    test eax, eax
    jnz .done
    cmp dil, 'A'
    je .rotate
    cmp dil, 'B'
    je .down
    cmp dil, 'C'
    je .right
    cmp dil, 'D'
    je .left
    cmp dil, 27
    je .start_esc
    ret
.start_esc:
    mov byte [escape_state], 1
    ret
.normal:
    push rdi
    call arena_key
    pop rdi
    test eax, eax
    jnz .done
    cmp dil, 3
    je .quit
    cmp dil, '+'
    je .arr_faster
    cmp dil, '='
    je .arr_faster
    cmp dil, '-'
    je .arr_slower
    cmp dil, '1'
    jb .fold_letter
    cmp dil, '9'
    ja .fold_letter
    movzx eax, dil
    sub eax, '0'
    mov [start_level], rax
    call reset_game
    ret
.fold_letter:
    and dil, 0xdf
    cmp dil, 'Q'
    je .quit
    cmp dil, 'R'
    je .restart
    cmp dil, 'P'
    je .pause
    cmp dil, 'B'
    je .pilot
    cmp dil, 'H'
    je .hint
    cmp dil, 'N'
    je .one_piece
    cmp dil, '['
    je .pilot_slower
    cmp dil, ']'
    je .pilot_faster
    cmp byte [game_state], STATE_PLAYING
    jne .done
    cmp byte [ui_too_small], 0
    jne .done
    cmp dil, 'A'
    je .left
    cmp dil, 'D'
    je .right
    cmp dil, 'W'
    je .rotate
    cmp dil, 'S'
    je .down
    cmp dil, 'Z'
    je .ccw
    cmp dil, 'C'
    je .hold
    ; Space (0x20) folds to zero above.
    test dil, dil
    je .hard
    ret
.left:
    cmp byte [game_state], STATE_PLAYING
    jne .done
    cmp byte [ui_too_small], 0
    jne .done
    call ai_manual_takeover
    mov edi, -1
    call handle_horizontal_input
    ret
.right:
    cmp byte [game_state], STATE_PLAYING
    jne .done
    cmp byte [ui_too_small], 0
    jne .done
    call ai_manual_takeover
    mov edi, 1
    call handle_horizontal_input
    ret
.rotate:
    cmp byte [game_state], STATE_PLAYING
    jne .done
    cmp byte [ui_too_small], 0
    jne .done
    call ai_manual_takeover
    call try_rotate
    ret
.ccw:
    call ai_manual_takeover
    call try_rotate_ccw
    ret
.hold:
    call ai_manual_takeover
    call hold_piece
    ret
.down:
    cmp byte [game_state], STATE_PLAYING
    jne .done
    cmp byte [ui_too_small], 0
    jne .done
    call ai_manual_takeover
    call step_down
    test eax, eax
    jnz .done
    inc qword [score]
    call update_high_score
    ret
.hard:
    cmp byte [game_state], STATE_PLAYING
    jne .done
    cmp byte [ui_too_small], 0
    jne .done
    call ai_manual_takeover
    call hard_drop
    ret
.pause:
    cmp byte [game_state], STATE_GAME_OVER
    je .done
    cmp byte [game_state], STATE_PAUSED
    je .resume
    mov byte [game_state], STATE_PAUSED
    mov byte [dirty], 1
    ret
.resume:
    mov byte [game_state], STATE_PLAYING
    mov byte [dirty], 1
    call get_time_ns
    mov [last_drop_ns], rax
    cmp byte [grounded], 0
    je .done
    add rax, LOCK_DELAY_NS
    mov [lock_deadline], rax
    ret
.restart:
    call reset_game
    ret
.pilot:
    xor byte [ai_auto], 1
    mov byte [ai_single], 0
    mov byte [das_active], 0
    mov qword [ai_deadline], 0
    mov byte [dirty], 1
    ret
.hint:
    xor byte [ai_hint], 1
    mov byte [dirty], 1
    ret
.one_piece:
    cmp byte [game_state], STATE_PLAYING
    jne .done
    mov byte [ai_single], 1
    mov byte [ai_auto], 0
    mov byte [das_active], 0
    mov qword [ai_deadline], 0
    mov byte [dirty], 1
    ret
.pilot_slower:
    cmp qword [ai_interval], 250000000
    jae .done
    add qword [ai_interval], 25000000
    mov byte [dirty], 1
    ret
.pilot_faster:
    cmp qword [ai_interval], 25000000
    jbe .done
    sub qword [ai_interval], 25000000
    mov byte [dirty], 1
    ret
.arr_faster:
    cmp qword [arr_interval_ns], 15000000
    jbe .done
    sub qword [arr_interval_ns], 5000000
    mov byte [das_active], 0
    mov byte [dirty], 1
    ret
.arr_slower:
    cmp qword [arr_interval_ns], 90000000
    jae .done
    add qword [arr_interval_ns], 5000000
    mov byte [das_active], 0
    mov byte [dirty], 1
    ret
.quit:
    mov byte [quit_flag], 1
.done:
    ret

; Build the complete frame in output_buf and emit it with one write syscall.
render_frame:
    push rbx
    push r12
    push r13
    push r14
    push r15
    cmp byte [ui_too_small], 0
    jne .small
    mov al, [ai_hint]
    or al, [ai_auto]
    or al, [ai_single]
    jz .manual_stats
    cmp byte [game_state], STATE_GAME_OVER
    je .manual_stats
    call ai_ensure_plan
    jmp .no_plan
.manual_stats:
    mov byte [ai_valid], 0
    mov byte [ai_cached], 0
    lea rdi, [board]
    call ai_evaluate
    mov eax, [ai_eval_height]
    mov [ai_live_height], eax
    mov eax, [ai_eval_holes]
    mov [ai_live_holes], eax
.no_plan:
    call get_time_ns
    mov [render_now_ns], rax
    lea rsi, [board]
    lea rdi, [display_board]
    mov ecx, BOARD_SIZE
    rep movsb

    cmp byte [game_state], STATE_GAME_OVER
    je .overlay_done
    ; Find the ghost landing row without changing active-piece state.
    mov r13d, [piece_y]
.ghost_fall:
    mov edi, [piece_x]
    lea esi, [r13d+1]
    mov edx, [piece_type]
    mov ecx, [piece_rot]
    call can_place
    test eax, eax
    jz .ghost_ready
    inc r13d
    jmp .ghost_fall
.ghost_ready:
    mov eax, [piece_type]
    shl eax, 2
    add eax, [piece_rot]
    lea rbx, [shapes]
    movzx r14d, word [rbx+rax*2]
    xor ecx, ecx
.ghost_overlay:
    cmp ecx, 16
    je .active_start
    bt r14d, ecx
    jnc .ghost_next
    mov eax, ecx
    and eax, 3
    add eax, [piece_x]
    mov edx, ecx
    shr edx, 2
    add edx, r13d
    test edx, edx
    js .ghost_next
    cmp edx, BOARD_H
    jge .ghost_next
    imul edx, edx, BOARD_W
    add edx, eax
    lea rbx, [display_board]
    cmp byte [rbx+rdx], 0
    jne .ghost_next
    mov byte [rbx+rdx], 8
.ghost_next:
    inc ecx
    jmp .ghost_overlay
.active_start:
    call ai_overlay
    xor ecx, ecx
.overlay:
    cmp ecx, 16
    je .overlay_done
    bt r14d, ecx
    jnc .overlay_next
    mov eax, ecx
    and eax, 3
    add eax, [piece_x]
    mov edx, ecx
    shr edx, 2
    add edx, [piece_y]
    test edx, edx
    js .overlay_next
    cmp edx, BOARD_H
    jge .overlay_next
    cmp eax, 0
    jl .overlay_next
    cmp eax, BOARD_W
    jge .overlay_next
    imul edx, edx, BOARD_W
    add edx, eax
    lea rbx, [display_board]
    mov eax, [piece_type]
    inc eax
    mov [rbx+rdx], al
.overlay_next:
    inc ecx
    jmp .overlay

.overlay_done:
    lea r15, [output_buf]
    call ui_clear_if_needed
    lea rsi, [home_seq]
    call append_z
    lea rsi, [title]
    call append_z
    lea rsi, [top_border]
    call append_z
    call render_mode_banner
    lea rsi, [row_end_seq]
    call append_z
    xor r12d, r12d
.row:
    cmp r12d, BOARD_H
    je .bottom
    lea rsi, [left_edge]
    call append_z
    xor r13d, r13d
.column:
    cmp r13d, BOARD_W
    je .row_end
    imul eax, r12d, BOARD_W
    add eax, r13d
    cmp byte [flash_count], 0
    je .normal_cell
    mov rdx, [render_now_ns]
    cmp rdx, [flash_until_ns]
    jae .normal_cell
    movzx edx, byte [flash_count]
    xor ecx, ecx
.flash_scan:
    cmp eax, [landing_cells+rcx*4]
    je .flash
    inc ecx
    cmp ecx, edx
    jb .flash_scan
.normal_cell:
    lea rbx, [display_board]
    movzx eax, byte [rbx+rax]
    test eax, eax
    jz .empty
    dec eax
    lea rbx, [cell_colors]
    mov rsi, [rbx+rax*8]
    call append_z
    jmp .cell_done
.flash:
    lea rsi, [flash_cell]
    call append_z
    jmp .cell_done
.empty:
    lea rsi, [empty_cell]
    call append_z
.cell_done:
    inc r13d
    jmp .column
.row_end:
    lea rsi, [right_edge]
    call append_z
    mov edi, r12d
    call render_sidebar
    mov edi, r12d
    call render_copilot
    lea rsi, [row_end_seq]
    call append_z
    inc r12d
    jmp .row
.bottom:
    lea rsi, [bottom_border]
    call append_z
    cmp byte [game_state], STATE_GAME_OVER
    je .gameover
    cmp byte [game_state], STATE_PAUSED
    je .paused
    lea rsi, [playing_text]
    call append_z
    mov rax, [arr_interval_ns]
    xor edx, edx
    mov ecx, 1000000
    div rcx
    mov rdi, rax
    call append_u64
    lea rsi, [arr_suffix]
    jmp .status
.paused:
    lea rsi, [paused_text]
    jmp .status
.gameover:
    lea rsi, [gameover_text]
.status:
    call append_z
    lea rsi, [erase_tail]
    call append_z
.emit:
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
.small:
    lea r15, [output_buf]
    call ui_clear_if_needed
    lea rsi, [ui_small_text]
    call append_z
    jmp .emit

render_sidebar:
    cmp edi, 0
    je .score
    cmp edi, 1
    je .high
    cmp edi, 2
    je .lines
    cmp edi, 3
    je .level
    cmp edi, 4
    je .combo
    cmp edi, 5
    je .b2b
    cmp edi, 6
    je .next
    cmp edi, 7
    jl .done
    cmp edi, 11
    jle .queue_line
    cmp edi, 12
    je .hold
    cmp edi, 13
    jl .done
    cmp edi, 16
    jle .hold_preview
    cmp edi, 17
    je .controls
    cmp edi, 18
    je .move
    cmp edi, 19
    je .soft
.done:
    ret
.score:
    lea rsi, [score_text]
    call append_z
    mov rdi, [score]
    call append_u64
    ret
.high:
    lea rsi, [high_text]
    call append_z
    mov rdi, [high_score]
    call append_u64
    ret
.lines:
    lea rsi, [lines_text]
    call append_z
    mov rdi, [total_lines]
    call append_u64
    ret
.level:
    lea rsi, [level_text]
    call append_z
    mov rdi, [level]
    call append_u64
    lea rsi, [start_text]
    call append_z
    mov rdi, [start_level]
    call append_u64
    ret
.combo:
    lea rsi, [combo_text]
    call append_z
    mov rdi, [combo]
    test rdi, rdi
    jns .combo_value
    xor edi, edi
.combo_value:
    call append_u64
    ret
.b2b:
    lea rsi, [b2b_text]
    call append_z
    cmp byte [b2b_active], 0
    je .b2b_off
    lea rsi, [b2b_on_text]
    call append_z
    ret
.b2b_off:
    lea rsi, [b2b_off_text]
    call append_z
    ret
.next:
    lea rsi, [next_text]
    call append_z
    ret
.hold:
    lea rsi, [hold_text]
    call append_z
    ret
.controls:
    lea rsi, [controls_text]
    call append_z
    ret
.move:
    lea rsi, [move_text]
    call append_z
    ret
.soft:
    lea rsi, [soft_text]
    call append_z
    ret
.queue_line:
    sub edi, 7
    jmp render_queue_line
.hold_preview:
    sub edi, 13
    mov esi, [hold_type]
    jmp render_preview_piece

; render_queue_line(edi=index 0..4) shows all five queued pieces compactly.
render_queue_line:
    push rbx
    push r12
    mov r12d, edi
    mov dil, ' '
    call append_char
    call append_char
    call append_char
    call append_char
    mov edi, r12d
    add dil, '1'
    call append_char
    mov dil, ' '
    call append_char
    lea rbx, [next_queue]
    mov eax, [rbx+r12*4]
    push rax
    lea rbx, [cell_colors]
    mov rsi, [rbx+rax*8]
    call append_z
    mov dil, ' '
    call append_char
    pop rax
    lea rbx, [piece_letters]
    mov dil, [rbx+rax]
    call append_char
    pop r12
    pop rbx
    ret

; render_preview_piece(edi=mask row 0..3, esi=piece type or -1)
render_preview_piece:
    push rbx
    push r12
    push r13
    push r14
    mov r12d, edi
    mov r14d, esi
    mov dil, ' '
    call append_char
    call append_char
    call append_char
    call append_char
    test r14d, r14d
    js .empty_mask
    mov eax, r14d
    shl eax, 2
    lea rbx, [shapes]
    movzx r13d, word [rbx+rax*2]
    jmp .mask_ready
.empty_mask:
    xor r13d, r13d
.mask_ready:
    xor ecx, ecx
.preview_col:
    cmp ecx, 4
    je .preview_done
    mov eax, r12d
    shl eax, 2
    add eax, ecx
    bt r13d, eax
    jnc .preview_empty
    mov eax, r14d
    lea rbx, [cell_colors]
    mov rsi, [rbx+rax*8]
    call append_z
    jmp .preview_next
.preview_empty:
    lea rsi, [preview_empty]
    call append_z
.preview_next:
    inc ecx
    jmp .preview_col
.preview_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Buffer helpers use R15 as cursor and stop at output_end.
append_z:
    push rax
.loop:
    mov al, [rsi]
    test al, al
    jz .done
    cmp r15, output_end
    jae .done
    mov [r15], al
    inc r15
    inc rsi
    jmp .loop
.done:
    pop rax
    ret

append_char:
    cmp r15, output_end
    jae .done
    mov [r15], dil
    inc r15
.done:
    ret

; append_u64(rdi=value): complete unsigned 64-bit decimal conversion.
append_u64:
    push rbx
    mov rax, rdi
    test rax, rax
    jnz .digits
    mov dil, '0'
    call append_char
    pop rbx
    ret
.digits:
    xor ecx, ecx
    mov ebx, 10
.divide:
    xor edx, edx
    div rbx
    push rdx
    inc ecx
    test rax, rax
    jnz .divide
.emit:
    pop rdx
    add dl, '0'
    mov dil, dl
    call append_char
    dec ecx
    jnz .emit
    pop rbx
    ret

write_z_stdout:
    push rsi
    xor edx, edx
.length:
    cmp byte [rsi+rdx], 0
    je .write
    inc rdx
    jmp .length
.write:
    call write_all_stdout
    pop rsi
    ret

; write_all_stdout(rsi=buffer, rdx=length) retries EINTR and partial writes.
write_all_stdout:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rsi
    mov r12, rdx
.write:
    test r12, r12
    jz .done
    mov eax, SYS_write
    mov edi, STDOUT
    mov rsi, rbx
    mov rdx, r12
    syscall
    cmp rax, -4
    je .write
    cmp rax, -11
    je .writable
    test rax, rax
    jle .done
    add rbx, rax
    sub r12, rax
    jmp .write
.writable:
    ; STDIN and STDOUT can share the same open file description on a TTY.
    ; Enabling O_NONBLOCK for input can therefore affect output too. Wait for
    ; capacity instead of discarding a partial frame or spinning on EAGAIN.
    mov dword [rsp], STDOUT
    mov dword [rsp+4], 4           ; events=POLLOUT, revents=0
    mov eax, SYS_poll
    mov rdi, rsp
    mov esi, 1
    mov edx, 1000
    syscall
    cmp rax, -4
    je .writable
    test rax, rax
    js .done
    test word [rsp+6], 0x38       ; POLLERR | POLLHUP | POLLNVAL
    jnz .done
    jmp .write
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; Assembly-only tests for placement, clearing, bags, and integer formatting.
run_tests:
    push r15
    mov byte [test_failed], 0
    mov qword [arr_interval_ns], ARR_NS
    lea rdi, [board]
    xor eax, eax
    mov ecx, BOARD_SIZE
    rep stosb

    mov edi, 3
    xor esi, esi
    xor edx, edx
    xor ecx, ecx
    call can_place
    cmp eax, 1
    je .wall_test
    mov byte [test_failed], 1
.wall_test:
    mov edi, -2
    xor esi, esi
    xor edx, edx
    xor ecx, ecx
    call can_place
    test eax, eax
    jz .floor_test
    mov byte [test_failed], 1
.floor_test:
    mov edi, 3
    mov esi, 19
    xor edx, edx
    xor ecx, ecx
    call can_place
    test eax, eax
    jz .occupied_test
    mov byte [test_failed], 1
.occupied_test:
    mov byte [board+13], 4
    mov edi, 3
    xor esi, esi
    xor edx, edx
    xor ecx, ecx
    call can_place
    test eax, eax
    jz .srs_test
    mov byte [test_failed], 1

.srs_test:
    lea rdi, [board]
    xor eax, eax
    mov ecx, BOARD_SIZE
    rep stosb
    mov dword [piece_type], 0
    mov dword [piece_rot], 1
    mov dword [piece_x], -1
    mov dword [piece_y], 3
    mov byte [grounded], 0
    call try_rotate_ccw
    cmp eax, 1
    jne .srs_fail
    cmp dword [piece_rot], 0
    jne .srs_fail
    cmp dword [piece_x], 1
    jne .srs_fail
    cmp byte [last_kick_index], 1
    jne .srs_fail
    mov dword [piece_type], 2
    mov dword [piece_rot], 1
    mov dword [piece_x], -1
    mov dword [piece_y], 3
    mov byte [grounded], 0
    call try_rotate_ccw
    cmp eax, 1
    jne .srs_fail
    cmp dword [piece_rot], 0
    jne .srs_fail
    cmp dword [piece_x], 0
    je .das_test
.srs_fail:
    mov byte [test_failed], 1

.das_test:
    lea rdi, [board]
    xor eax, eax
    mov ecx, BOARD_SIZE
    rep stosb
    mov dword [piece_type], 1
    mov dword [piece_rot], 0
    mov dword [piece_x], 3
    mov dword [piece_y], 0
    mov byte [game_state], STATE_PLAYING
    mov byte [grounded], 0
    mov dword [horizontal_dir], 1
    call get_time_ns
    mov [horizontal_last_ns], rax
    mov qword [das_deadline_ns], 0
    mov byte [das_active], 0
    mov edi, 'd'
    call process_input_byte
    cmp byte [das_active], 1
    jne .das_fail
    cmp dword [piece_x], 4
    jne .das_fail
    mov qword [arr_deadline_ns], 0
    call update_horizontal_repeat
    cmp dword [piece_x], 7
    jne .das_fail
    mov edi, '+'
    call process_input_byte
    cmp qword [arr_interval_ns], 25000000
    jne .das_fail
    mov edi, '-'
    call process_input_byte
    cmp qword [arr_interval_ns], ARR_NS
    je .lock_delay_test
.das_fail:
    mov byte [test_failed], 1

.lock_delay_test:
    lea rdi, [board]
    xor eax, eax
    mov ecx, BOARD_SIZE
    rep stosb
    mov dword [piece_type], 0
    mov dword [piece_rot], 0
    mov dword [piece_x], 3
    mov dword [piece_y], 18
    mov byte [game_state], STATE_PLAYING
    mov byte [grounded], 0
    mov byte [hard_drop_lock], 0
    mov byte [last_action_rotate], 0
    mov qword [score], 0
    mov qword [total_lines], 0
    mov qword [start_level], 1
    mov qword [level], 1
    mov qword [combo], -1
    mov byte [b2b_active], 0
    mov dword [next_queue], 1
    mov dword [next_queue+4], 2
    mov dword [next_queue+8], 3
    mov dword [next_queue+12], 4
    mov dword [next_queue+16], 5
    mov byte [bag_index], 7
    mov rax, 0x123456789abcdef0
    mov [rng_state], rax
    call step_down
    cmp eax, 1
    jne .lock_delay_fail
    cmp byte [grounded], 1
    jne .lock_delay_fail
    cmp byte [board+193], 0
    jne .lock_delay_fail
    call update_game                  ; still before the 500 ms deadline
    cmp byte [board+193], 0
    jne .lock_delay_fail
    mov qword [lock_deadline], 0
    mov byte [ai_single], 1
    call update_game
    cmp byte [ai_single], 0
    jne .lock_delay_fail
    cmp byte [board+193], 1
    je .tspin_test
.lock_delay_fail:
    mov byte [test_failed], 1

.tspin_test:
    lea rdi, [board]
    xor eax, eax
    mov ecx, BOARD_SIZE
    rep stosb
    mov dword [piece_type], 2
    mov dword [piece_rot], 0
    mov dword [piece_x], 3
    mov dword [piece_y], 5
    mov byte [last_action_rotate], 1
    mov byte [last_kick_index], 0
    mov byte [board+53], 1          ; top-left corner
    mov byte [board+73], 1          ; bottom-left corner
    mov byte [board+75], 1          ; bottom-right corner
    call detect_tspin
    cmp eax, 1
    jne .tspin_fail
    mov byte [board+55], 1          ; top-right: both front corners now full
    call detect_tspin
    cmp eax, 2
    je .hold_test
.tspin_fail:
    mov byte [test_failed], 1

.hold_test:
    lea rdi, [board]
    xor eax, eax
    mov ecx, BOARD_SIZE
    rep stosb
    mov dword [piece_type], 0
    mov dword [next_queue], 1
    mov dword [next_queue+4], 2
    mov dword [next_queue+8], 3
    mov dword [next_queue+12], 4
    mov dword [next_queue+16], 5
    mov dword [hold_type], -1
    mov byte [hold_used], 0
    mov byte [bag_index], 0
    mov byte [bag], 2
    call hold_piece
    cmp dword [hold_type], 0
    jne .hold_fail
    cmp dword [piece_type], 1
    jne .hold_fail
    cmp dword [next_queue], 2
    jne .hold_fail
    call hold_piece                  ; second hold before lock must do nothing
    cmp dword [hold_type], 0
    jne .hold_fail
    cmp dword [piece_type], 1
    jne .hold_fail
    mov byte [hold_used], 0
    call hold_piece
    cmp dword [hold_type], 1
    jne .hold_fail
    cmp dword [piece_type], 0
    je .line_setup
.hold_fail:
    mov byte [test_failed], 1

.line_setup:
    lea rdi, [board]
    xor eax, eax
    mov ecx, BOARD_SIZE
    rep stosb
    mov byte [board], 3
    lea rdi, [board+180]
    mov al, 1
    mov ecx, 20
    rep stosb
    mov qword [score], 0
    mov qword [total_lines], 8
    mov qword [level], 1
    mov qword [start_level], 1
    mov qword [combo], -1
    mov byte [b2b_active], 0
    mov byte [spin_kind], 0
    call clear_lines
    push rax
    mov edi, eax
    call score_lock_event
    pop rax
    cmp eax, 2
    jne .line_fail
    cmp qword [score], 300
    jne .line_fail
    cmp qword [total_lines], 10
    jne .line_fail
    cmp qword [level], 2
    jne .line_fail
    cmp byte [board+20], 3
    je .modern_score_test
.line_fail:
    mov byte [test_failed], 1

.modern_score_test:
    lea rdi, [board]
    xor eax, eax
    mov ecx, BOARD_SIZE
    rep stosb
    mov qword [score], 0
    mov qword [total_lines], 0
    mov qword [level], 1
    mov qword [start_level], 1
    mov qword [combo], -1
    mov byte [b2b_active], 0
    mov byte [spin_kind], 0
    mov edi, 4
    call score_lock_event
    cmp qword [score], 2800       ; 800 Tetris + 2000 perfect clear
    jne .modern_score_fail
    cmp byte [b2b_active], 1
    jne .modern_score_fail
    mov edi, 4
    call score_lock_event
    cmp qword [score], 7250       ; +1200 B2B +50 combo +3200 PC
    jne .modern_score_fail
    cmp qword [combo], 1
    jne .modern_score_fail
    mov byte [spin_kind], 2
    xor edi, edi
    call score_lock_event
    cmp qword [score], 7650       ; +400 no-line T-spin
    jne .modern_score_fail
    cmp byte [b2b_active], 1
    je .bag_test
.modern_score_fail:
    mov byte [test_failed], 1

.bag_test:
    mov rax, 0x123456789abcdef0
    mov [rng_state], rax
    mov byte [bag_index], 7
    xor r8d, r8d
    xor r9d, r9d
.bag_loop:
    call next_from_bag
    cmp eax, 6
    ja .bag_fail
    bt r8d, eax
    jc .bag_fail
    bts r8d, eax
    inc r9d
    cmp r9d, 7
    jb .bag_loop
    cmp r8d, 0x7f
    je .uint_test
.bag_fail:
    mov byte [test_failed], 1

.uint_test:
    lea r15, [output_buf]
    mov rdi, -1
    call append_u64
    mov byte [r15], 0
    lea rsi, [output_buf]
    lea rdi, [uint_expected]
.compare:
    mov al, [rsi]
    cmp al, [rdi]
    jne .uint_fail
    test al, al
    jz .report
    inc rsi
    inc rdi
    jmp .compare
.uint_fail:
    mov byte [test_failed], 1
.report:
    call run_ai_tests
    call run_arena_tests
    call run_multiverse_tests
    cmp byte [test_failed], 0
    jne .failed
    mov eax, SYS_write
    mov edi, STDOUT
    lea rsi, [test_pass]
    mov edx, test_pass_len
    syscall
    xor eax, eax
    pop r15
    ret
.failed:
    mov eax, SYS_write
    mov edi, STDERR
    lea rsi, [test_fail]
    mov edx, test_fail_len
    syscall
    mov eax, 1
    pop r15
    ret

%include "copilot.asm"
%include "cli.asm"
%include "dashboard.asm"
%include "arena.asm"
%include "arena_view.asm"
%include "arena_cli.asm"
%include "multiverse.asm"
%include "multiverse_view.asm"
%include "multiverse_cli.asm"
%include "tests/copilot.asm"
%include "tests/arena.asm"
%include "tests/multiverse.asm"

section .note.GNU-stack noalloc noexec nowrite progbits
