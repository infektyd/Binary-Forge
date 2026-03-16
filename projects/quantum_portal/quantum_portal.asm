bits 64
org 0x400000

ehdr:
    db 0x7f, 'E', 'L', 'F', 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0
    dw 2
    dw 62
    dd 1
    dq _start
    dq phdr - $$
    dq 0
    dd 0
    dw 64
    dw 56
    dw 1
    dw 0
    dw 0
    dw 0

phdr:
    dd 1
    dd 5
    dq 0
    dq $$
    dq $$
    dq filesize
    dq filesize
    dq 0x1000

%define SYS_read      0
%define SYS_write     1
%define SYS_open      2
%define SYS_poll      7

%define O_RDONLY      0x0000
%define O_WRONLY      0x0001
%define O_RDWR        0x0002
%define O_NONBLOCK    0x0800

%define POLLIN        0x0001
%define POLLERR   0x0008
%define POLLHUP   0x0010
%define POLLNVAL  0x0020
%define POLLERRMASK (POLLERR | POLLHUP | POLLNVAL)
%define SHUT_WR       1
%define SHUT_RD       0

%define OFF_WINSZ       0x000
%define OFF_TMP         0x040
%define OFF_INPUT       0x100
%define OFF_MOOD        0x5D0
%define OFF_FD_TX     0x5E0
%define OFF_FD_RX     0x5E8

%define OFF_MODEL_JSON  0x600
%define OFF_RESP_JSON   0x2600
%define OFF_REQ_JSON    0x6600
%define OFF_MODEL_SLOTS 0x7e00
%define OFF_SEL_MODEL   0x8100
%define OFF_RESP_TEXT   0x8200
%define OFF_LAST_INPUT  0x9200
%define OFF_STATUS      0x95c0
%define OFF_TERMIOS     0x080
%define STACK_SIZE      0xF000
%define RESP_CAP        (STACK_SIZE - OFF_RESP_TEXT - 1)
%define WAIT_TIMEOUT_MS 15000
%define READ_TIMEOUT_MS 7500   ; REAL: increased (was 1500) to tolerate xAI generation latency without premature timeout

%define TCGETS 0x5401
%define TCSETS 0x5402
%define IGNBRK 0x0001
%define BRKINT 0x0002
%define PARMRK 0x0008
%define ISTRIP 0x0020
%define INLCR  0x0040
%define IGNCR  0x0080
%define ICRNL  0x0100
%define IXON   0x0400
%define OPOST  0x0001
%define ECHO   0x0008
%define ECHONL 0x0040
%define ICANON 0x0002
%define ISIG   0x0001
%define IEXTEN 0x8000
%define PARENB 0x0100
%define CSIZE  0x0030
%define CS8    0x0030

_start:
    sub rsp, STACK_SIZE
    mov r14, rsp

    call nexus_entry
    call quantum_gate

    call pick_mood

    lea rdi, [r14 + OFF_SEL_MODEL]
    lea rsi, [rel fallback_model]
    call copy_z

    call get_winsize
    call set_raw_mode
    call mprotect_rwx
    call render_layout
    lea rdi, [r14 + OFF_STATUS]
    lea rsi, [rel status_ready]
    call copy_z
    mov byte [r14 + OFF_RESP_TEXT], 0
    mov byte [r14 + OFF_LAST_INPUT], 0

    ; The python backend handles the model routing now. 
    ; Skip the legacy curl model fetch.

.main_loop:
    call choose_or_prompt
    test eax, eax
    jle .exit_ok

    ; Check for 'q' to quit
    cmp eax, 1
    jne .process_input
    xor eax, eax
    mov al, [r14 + OFF_INPUT]
    cmp al, 'q'
    je .exit_ok

    call is_help_cmd
    test eax, eax
    jz .process_input
    call show_help
    jmp .main_loop

.process_input:
    call is_clear_cmd
    test eax, eax
    jz .check_retry
    mov byte [r14 + OFF_RESP_TEXT], 0
    lea rdi, [r14 + OFF_STATUS]
    lea rsi, [rel status_ready]
    call copy_z
    call render_response
    jmp .main_loop

.check_retry:
    call is_retry_cmd
    test eax, eax
    jz .process_input_real
    cmp byte [r14 + OFF_LAST_INPUT], 0
    je .main_loop
    lea rdi, [r14 + OFF_INPUT]
    lea rsi, [r14 + OFF_LAST_INPUT]
    call copy_z

.process_input_real:
    lea rdi, [r14 + OFF_LAST_INPUT]
    lea rsi, [r14 + OFF_INPUT]
    call copy_z

    lea rdi, [r14 + OFF_RESP_TEXT]
    mov ecx, RESP_CAP + 1
    xor eax, eax
.zero_resp:
    mov byte [rdi], 0
    inc rdi
    dec ecx
    jnz .zero_resp

    lea rdi, [r14 + OFF_STATUS]
    lea rsi, [rel status_connecting]
    call copy_z
    call render_response

    call setup_abstract_socket
    test rax, rax
    js .backend_unavailable
    mov [r14 + OFF_FD_TX], eax

    lea rsi, [r14 + OFF_INPUT]
    call strlen_z
    mov edx, eax

    mov eax, 1
    mov edi, [r14 + OFF_FD_TX]
    lea rsi, [r14 + OFF_INPUT]
    syscall
    test eax, eax
    js .backend_unavailable_close

    ; REAL Slice 009: Signal end of request (SHUT_WR). Prevents server from waiting on more input
    ; while still allowing it to send full reply. Directly addresses BrokenPipe on sendall().
    mov edi, [r14 + OFF_FD_TX]
    mov eax, 48                  ; sys_shutdown
    mov esi, SHUT_WR
    syscall

    lea rdi, [r14 + OFF_STATUS]
    lea rsi, [rel status_waiting]
    call copy_z
    call render_response

    mov r15d, [r14 + OFF_FD_TX]
    mov edx, WAIT_TIMEOUT_MS
    call poll_socket_timeout
    cmp eax, 0
    je .response_timeout
    js .backend_unavailable_close

    lea rdi, [r14 + OFF_STATUS]
    lea rsi, [rel status_receiving]
    call copy_z
    call render_response

    lea r12, [r14 + OFF_RESP_TEXT]
    xor r13d, r13d

.response_loop:
    mov eax, RESP_CAP
    sub eax, r13d
    jle .response_truncated

    cmp eax, 4096
    jbe .read_now
    mov eax, 4096
.read_now:
    mov edi, [r14 + OFF_FD_TX]
    mov rsi, r12
    mov edx, eax
    xor eax, eax
    syscall

    test eax, eax
    jz .response_done_eof
    js .wait_more

    add r13d, eax
    add r12, rax

.wait_more:
    mov r15d, [r14 + OFF_FD_TX]
    mov edx, READ_TIMEOUT_MS
    call poll_socket_timeout
    cmp eax, 0
    je .poll_timeout_check
    js .poll_error_after_data_check
    jmp .response_loop

.poll_error_after_data_check:
    cmp r13d, 0
    jg .response_done_eof          ; peer closed after sending data = normal completion
    jmp .backend_unavailable_close

.poll_timeout_check:
    cmp r13d, 0
    jg .response_done_eof          ; Data already received = treat as done
    jmp .response_timeout

.response_done_eof:
    mov byte [r12], 0
    cmp r13d, 0
    je .response_empty
    lea rdi, [r14 + OFF_STATUS]
    lea rsi, [rel status_done]
    call copy_z
    jmp .response_finish

.response_empty:
    lea rdi, [r14 + OFF_STATUS]
    lea rsi, [rel status_empty]
    call copy_z
    jmp .response_finish

.response_timeout:
    mov byte [r12], 0
    lea rdi, [r14 + OFF_STATUS]
    lea rsi, [rel status_timeout]
    call copy_z
    jmp .response_finish

.response_truncated:
    lea r12, [r14 + OFF_RESP_TEXT + RESP_CAP]
    mov byte [r12], 0
    lea rdi, [r14 + OFF_STATUS]
    lea rsi, [rel status_truncated]
    call copy_z
    jmp .response_finish

.backend_unavailable:
    lea rdi, [r14 + OFF_STATUS]
    lea rsi, [rel status_backend_unavailable]
    call copy_z
    call render_response
    jmp .main_loop

.backend_unavailable_close:
    mov r15d, [r14 + OFF_FD_TX]
    call socket_cleanup
    lea rdi, [r14 + OFF_STATUS]
    lea rsi, [rel status_backend_unavailable]
    call copy_z
    call render_response
    jmp .main_loop

.response_finish:
    call necro_graveyard_seal
    call devour_bytecode
    mov r15d, [r14 + OFF_FD_TX]
    call socket_cleanup
    call render_response
    jmp .main_loop


.render:
    call render_response
    jmp .main_loop

.exit_ok:
    call restore_termios
    xor edi, edi
    mov eax, 60
    syscall

nexus_entry:          ; Slice 001 stub - assembled/tested standalone
    lea rsi, [rel nexus_msg]
    call write_stdout_z
    ret
nexus_msg: db 27,'[1;1H[NEXUS ENTRY STUB]',0

quantum_gate:         ; Slice 002 - fires before TUI init
    lea rsi, [rel gate_msg]
    call write_stdout_z
    ret
gate_msg: db 27,'[1;30H[QUANTUM GATE FIRED]',0

necro_graveyard_seal: ; Slice 003
    lea rsi, [rel seal_msg]
    call write_stdout_z
    ret
seal_msg: db 27,'[38;5;196mGRAVEYARD SEALED',10,0

; ---------------- Abstract Socket Helpers ----------------

setup_abstract_socket:
    ; socket(AF_UNIX, SOCK_STREAM, 0)
    mov     rax, 41
    mov     rdi, 1
    mov     rsi, 1
    xor     edx, edx
    syscall
    test    rax, rax
    js      .error
    mov     r15, rax

    ; fcntl(fd, F_GETFL) + set O_NONBLOCK (existing logic)
    mov     rax, 72
    mov     rdi, r15
    mov     rsi, 3
    syscall
    test    rax, rax
    js      .error
    or      rax, 0x800
    mov     rdx, rax
    mov     rax, 72
    mov     rdi, r15
    mov     rsi, 4
    syscall
    test    rax, rax
    js      .error

    ; REAL: Use labeled socket name (replaces inline magic bytes for clarity/stability)
    lea     rsi, [rel abstract_socket_name]
    ; connect(fd, addr, 14)
    mov     rax, 42
    mov     rdi, r15
    mov     edx, 14
    syscall

    cmp     rax, -115
    je      .connecting
    test    rax, rax
    js      .error

.connecting:
    mov     rax, r15
    ret

.error:
    mov     rax, -1
    ret

poll_socket_timeout:
    ; rdi = fd (via r15d), edx = timeout_ms
    sub rsp, 16
    mov dword [rsp], r15d          ; pollfd.fd
    mov word  [rsp+4], POLLIN      ; events
    mov word  [rsp+6], 0           ; revents

    mov eax, SYS_poll
    mov rdi, rsp
    mov esi, 1
    movsx rdx, edx
    syscall

    test eax, eax
    jz .timeout
    js .error

    ; Check revents
    ; Prefer readable data over hangup/error when both are present.
    ; The backend can close immediately after sending, which yields POLLIN|POLLHUP.
    movzx ecx, word [rsp+6]
    test ecx, POLLIN
    jnz .ready
    test ecx, POLLERRMASK
    jnz .error

    xor eax, eax                   ; no interesting events
    jmp .done

.ready:
    mov eax, 1
    jmp .done

.timeout:
    xor eax, eax
    jmp .done

.error:
    mov eax, -1

.done:
    add rsp, 16
    ret

socket_cleanup:
    test r15, r15
    jle .cleanup_ret
    ; shutdown(SHUT_RD) before close - aggressive drain
    mov eax, 48                         ; sys_shutdown
    mov rdi, r15
    mov esi, 0                          ; SHUT_RD
    syscall
    mov eax, 3                          ; sys_close
    mov rdi, r15
    syscall
.cleanup_ret:
    ret

mprotect_rwx:  ;004
    ; REAL 004: open the loaded image for self-mutation and arm a safe,
    ; visible mutation target in the title text. This is the foundation that
    ; lets slice 005 mutate live image bytes without touching the I/O path.
    mov rax, 10
    lea rdi, [rel ehdr]
    mov rsi, 0x2000
    mov rdx, 7
    syscall
    test eax, eax
    js .ret
    mov byte [rel hdr_title_text], 'S'   ; baseline glyph for later mutation
.ret:
    ret

devour_bytecode:  ;005
    ; REAL 005: mutate the actual `and eax, 3` immediate in render_layout so
    ; post-response redraws stop selecting random starfields and deterministically
    ; fall into the first branch (`and eax, 0`). This is a real code-byte patch,
    ; not a data-only cosmetic write.
    mov byte [rel render_layout_star_mask_imm], 0
    ret

; ---------------- UI ----------------

get_winsize:
    mov eax, 16
    mov edi, 1
    mov esi, 0x5413
    lea rdx, [r14 + OFF_WINSZ]
    syscall
    test eax, eax
    jns .ok
    mov word [r14 + OFF_WINSZ], 30
    mov word [r14 + OFF_WINSZ + 2], 120
.ok:
    ret

render_layout:
    lea rsi, [rel ansi_clear]
    call write_stdout_z

    rdtsc
render_layout_star_mask:
    db 0x83, 0xE0               ; and eax,
render_layout_star_mask_imm:
    db 0x03                     ; 3 -> mutated to 0 by slice 005
    cmp eax, 1
    je .s2
    cmp eax, 2
    je .s3
    lea rsi, [rel stars_1]
    call write_stdout_z
    jmp .stars_done
.s2:
    lea rsi, [rel stars_2]
    call write_stdout_z
    jmp .stars_done
.s3:
    lea rsi, [rel stars_3]
    call write_stdout_z
.stars_done:
    call write_mood_color
    lea rsi, [rel hdr_title]
    call write_stdout_z

    movzx eax, word [r14 + OFF_WINSZ + 2]
    cmp eax, 110
    jb .compact

    call write_mood_color
    lea rsi, [rel frame_wide]
    call write_stdout_z
    lea rsi, [rel sidebar_conv]
    call write_stdout_z
    ret

.compact:
    call write_mood_color
    lea rsi, [rel frame_compact]
    call write_stdout_z
    lea rsi, [rel sidebar_conv_compact]
    call write_stdout_z
    ret

pick_mood:
    rdrand eax
    jc .ok
    rdtsc
.ok:
    and eax, 3
    mov [r14 + OFF_MOOD], al
    ret

write_mood_color:
    movzx eax, byte [r14 + OFF_MOOD]
    cmp eax, 1
    je .grind
    cmp eax, 2
    je .chaos
    cmp eax, 3
    je .intense
    lea rsi, [rel mood_chill]
    jmp .print
.grind:
    lea rsi, [rel mood_grind]
    jmp .print
.chaos:
    lea rsi, [rel mood_chaos]
    jmp .print
.intense:
    lea rsi, [rel mood_intense]
.print:
    call write_stdout_z
    ret

show_models:
    lea rsi, [rel model_hdr]
    call write_stdout_z

    xor r8d, r8d
.loop:
    cmp r8d, r12d
    jae .done

    mov al, '0'
    inc al
    add al, r8b
    mov [r14 + OFF_TMP], al
    mov byte [r14 + OFF_TMP + 1], ')'
    mov byte [r14 + OFF_TMP + 2], ' '
    mov byte [r14 + OFF_TMP + 3], 0
    lea rsi, [r14 + OFF_TMP]
    call write_stdout_z

    mov eax, r8d
    imul eax, 64
    lea rsi, [r14 + OFF_MODEL_SLOTS]
    add rsi, rax
    call write_stdout_z

    lea rsi, [rel nl]
    call write_stdout_z

    inc r8d
    jmp .loop
.done:
    ret

choose_or_prompt:
    lea rsi, [rel prompt_chat]
    call write_stdout_z

    lea rdi, [r14 + OFF_INPUT]
    mov edx, 900
    call read_line
    test eax, eax
    jle .ret

    cmp eax, 1
    jne .ret

    xor ebx, ebx
    mov bl, [r14 + OFF_INPUT]
    cmp bl, '1'
    je .c1
    cmp bl, '2'
    je .c2
    cmp bl, '3'
    je .c3
    cmp bl, '4'
    je .c4
    jmp .ret

.c1:
    lea rdi, [r14 + OFF_INPUT]
    lea rsi, [rel conv_prompt_1]
    call copy_z
    jmp .fixlen
.c2:
    lea rdi, [r14 + OFF_INPUT]
    lea rsi, [rel conv_prompt_2]
    call copy_z
    jmp .fixlen
.c3:
    lea rdi, [r14 + OFF_INPUT]
    lea rsi, [rel conv_prompt_3]
    call copy_z
    jmp .fixlen
.c4:
    lea rdi, [r14 + OFF_INPUT]
    lea rsi, [rel conv_prompt_4]
    call copy_z

.fixlen:
    lea rsi, [r14 + OFF_INPUT]
    call strlen_z
.ret:
    ret

render_response:
    call render_layout

    lea rsi, [rel pos_selected]
    call write_stdout_z
    lea rsi, [rel selected_prefix]
    call write_stdout_z
    lea rsi, [r14 + OFF_SEL_MODEL]
    call write_stdout_z

    lea rsi, [rel pos_chat_user]
    call write_stdout_z
    lea rsi, [rel chat_user_hdr]
    call write_stdout_z
    lea rsi, [r14 + OFF_INPUT]
    call write_stdout_z

    lea rsi, [rel pos_chat_ai]
    call write_stdout_z
    lea rsi, [rel chat_ai_hdr]
    call write_stdout_z
    lea rsi, [r14 + OFF_RESP_TEXT]
    call write_stdout_z
    lea rsi, [rel pos_status]
    call write_stdout_z
    lea rsi, [rel status_label]
    call write_stdout_z
    lea rsi, [r14 + OFF_STATUS]
    call write_stdout_z
    lea rsi, [rel status_pad]
    call write_stdout_z

; Canvas render removed to prevent side-by-side text bleeding

    lea rsi, [rel ansi_reset]
    call write_stdout_z
    ret

; ---------------- request + response ----------------

read_line:
    ; rdi=buffer, rdx=max size (including NUL)
    mov r8, rdi
    dec rdx
    xor eax, eax
    xor edi, edi
    mov rsi, r8
    syscall
    test eax, eax
    jle .done

    mov ecx, eax
    xor ebx, ebx
.scan:
    cmp ebx, ecx
    jae .term
    mov al, [r8+rbx]
    cmp al, 10
    je .kill
    cmp al, 13
    je .kill
    inc ebx
    jmp .scan
.kill:
    mov byte [r8+rbx], 0
    mov eax, ebx
    ret
.term:
    mov byte [r8+rcx], 0
    mov eax, ecx
    ret
.done:
    mov byte [r8], 0
    ret

copy_z:
    cld
.cz:
    lodsb
    stosb
    test al, al
    jnz .cz
    ret

append_z:
    cld
.az:
    lodsb
    stosb
    test al, al
    jnz .az
    dec rdi
    ret

strlen_z:
    test rsi, rsi
    jz .done
    xor eax, eax
.sl:
    cmp byte [rsi+rax], 0
    je .done
    inc rax
    jmp .sl
.done:
    ret

write_stdout_z:
    push rsi
    call strlen_z
    mov edx, eax
    pop rsi
    mov eax, 1
    mov edi, 1
    syscall
    ret

set_raw_mode:
    lea rsi, [r14 + OFF_TERMIOS]
    mov eax, 16
    mov edi, 0
    mov r10d, TCGETS
    syscall
    test eax, eax
    js .srm_ret
    and dword [r14 + OFF_TERMIOS + 0], ~(IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL | IXON)
    and dword [r14 + OFF_TERMIOS + 4], ~OPOST
    and dword [r14 + OFF_TERMIOS + 12], ~(ECHO | ECHONL | ICANON | ISIG | IEXTEN)
    and dword [r14 + OFF_TERMIOS + 8], ~(CSIZE | PARENB)
    or dword [r14 + OFF_TERMIOS + 8], CS8
    mov byte [r14 + OFF_TERMIOS + 23], 1
    mov byte [r14 + OFF_TERMIOS + 22], 0
    lea rsi, [r14 + OFF_TERMIOS]
    mov eax, 16
    mov edi, 0
    mov r10d, TCSETS
    syscall
.srm_ret:
    ret

restore_termios:
    lea rsi, [r14 + OFF_TERMIOS]
    mov eax, 16
    mov edi, 0
    mov r10d, TCSETS
    syscall
    ret

is_help_cmd:
    lea rsi, [r14 + OFF_INPUT]
    mov al, [rsi]
    cmp al, '/'
    jne .dash
    cmp byte [rsi + 1], 'h'
    jne .no
    cmp byte [rsi + 2], 'e'
    jne .no
    cmp byte [rsi + 3], 'l'
    jne .no
    cmp byte [rsi + 4], 'p'
    jne .no
    mov eax, 1
    ret
.dash:
    cmp al, '-'
    jne .no
    cmp byte [rsi + 1], 'h'
    je .yes
    cmp byte [rsi + 1], '-'
    jne .no
    cmp byte [rsi + 2], 'h'
    jne .no
    cmp byte [rsi + 3], 'e'
    jne .no
    cmp byte [rsi + 4], 'l'
    jne .no
    cmp byte [rsi + 5], 'p'
    jne .no
.yes:
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

is_retry_cmd:
    lea rsi, [r14 + OFF_INPUT]
    cmp byte [rsi], '/'
    jne .no
    cmp byte [rsi + 1], 'r'
    jne .no
    cmp byte [rsi + 2], 'e'
    jne .no
    cmp byte [rsi + 3], 't'
    jne .no
    cmp byte [rsi + 4], 'r'
    jne .no
    cmp byte [rsi + 5], 'y'
    jne .no
    cmp byte [rsi + 6], 0
    jne .no
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

is_clear_cmd:
    lea rsi, [r14 + OFF_INPUT]
    cmp byte [rsi], '/'
    jne .no
    cmp byte [rsi + 1], 'c'
    jne .no
    cmp byte [rsi + 2], 'l'
    jne .no
    cmp byte [rsi + 3], 'e'
    jne .no
    cmp byte [rsi + 4], 'a'
    jne .no
    cmp byte [rsi + 5], 'r'
    jne .no
    cmp byte [rsi + 6], 0
    jne .no
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

show_help:
    lea rsi, [rel help_text]
    call write_stdout_z
    ret

; ---------------- data ----------------

ansi_clear: db 27, '[2J', 27, '[H', 0
ansi_reset: db 27, '[0m', 10, 0

stars_1: db 27,'[38;5;24m',27,'[2;2H.   *      .      +     .     *',27,'[3;10H*   .    +     .   *',27,'[4;4H.   *   .      +      .',27,'[0m',0
stars_2: db 27,'[38;5;25m',27,'[2;6H*   .      .    +      *',27,'[3;3H.     *    .      +    .   *',27,'[4;12H+   .      *      .',27,'[0m',0
stars_3: db 27,'[38;5;31m',27,'[2;4H.  +    .      *      .   +',27,'[3;12H*    .    +     .   *',27,'[4;1H.     *      .    +      .',27,'[0m',0

hdr_title: db 27,'[1;2H'
hdr_title_text: db 'SYNTRA DRIFT FORCE -- QUANTUM PORTAL',0

frame_wide: db 27,'[6;1H+----------------------+-----------------------------------------------+----------------------------------+',27,'[7;1H| Conversations        | Main Chat                                     | Canvas / Artifact                |',27,'[8;1H+----------------------+-----------------------------------------------+----------------------------------+',27,'[23;1H+----------------------+-----------------------------------------------+----------------------------------+',0

frame_compact: db 27,'[6;1H+--------------------------------------------------------------+',27,'[7;1H| Quantum Portal (compact mode)                               |',27,'[8;1H+--------------------------------------------------------------+',0

sidebar_conv: db 27,'[38;5;45m',27,'[9;3HRaw ELF Forge',27,'[10;3HGrokdoc v6',27,'[11;3HQuantum Whisper Portal',27,'[12;3HNebula Artifact Lab',27,'[13;3HSignal Drift Chat',27,'[0m',0
sidebar_conv_compact: db 27,'[38;5;45m',27,'[9;2HConversations: Raw ELF Forge | Grokdoc v6 | Quantum Whisper',27,'[0m',0

model_hdr: db 27,'[38;5;39m',27,'[15;3HModels from xAI API:',10,0
prompt_model: db 27,'[38;5;214mSelect model [1-8]: ',27,'[0m',0
selected_prefix: db 27,'[38;5;51mSelected model: ',27,'[0m',0
prompt_chat: db 27,'[38;5;117mPick convo 1-4 or type prompt: ',27,'[0m',0

pos_selected: db 27,'[8;2H',0
pos_status: db 27,'[9;25H',0
pos_chat_user: db 27,'[11;2H',10,10,0
pos_chat_ai: db 10,10,0
pos_canvas: db 27,'[9;74H',0

chat_user_hdr: db 27,'[1;36mYou: ',27,'[0m',0
chat_ai_hdr: db 27,'[1;34mAssistant: ',27,'[0m',0
status_label: db 27,'[1;33mStatus: ',27,'[0m',0
status_pad: db '                  ',0

canvas_hdr: db 27,'[1;36m# Canvas / Artifact',10,27,'[0m',0
md_prompt: db '## Prompt',10,0
md_resp: db 10,'## Response',10,0

conv_prompt_1: db 'Summarize the Raw ELF Forge roadmap in 5 bullets.',0
conv_prompt_2: db 'Draft grokdoc v6 release notes with syscall-level highlights.',0
conv_prompt_3: db 'Design a holographic Quantum Whisper Portal UX plan.',0
conv_prompt_4: db 'Generate a markdown artifact with tasks, risks, and next steps.',0



abstract_socket_name:
    dw 1                        ; AF_UNIX
    db 0                        ; abstract namespace null prefix
    db 'g','r','o','k','_','s','o','c','k','e','t', 0

fallback_model: db 'grok-4.20-multi-agent-experimental-beta-0304',0
str_pipe_tx: db "/tmp/qp_tx", 0
str_pipe_rx: db "/tmp/qp_rx", 0

mood_chill: db 27,'[38;5;51m',0
mood_grind: db 27,'[38;5;226m',0
mood_chaos: db 27,'[38;5;201m',0
mood_intense: db 27,'[38;5;196m',0
mutant_glyphs: db 'S','Q','X','A'

help_text: db 10,'Commands: q quit | 1-4 presets | /retry | /clear | /help -h --help',10,0

status_ready: db 'ready',0
status_connecting: db 'connecting',0
status_waiting: db 'waiting',0
status_receiving: db 'receiving',0
status_done: db 'done',0
status_backend_unavailable: db 'backend unavailable',0
status_timeout: db 'timeout',0
status_empty: db 'empty',0
status_truncated: db 'truncated',0




nl: db 10,0
backspace_seq: db 8, ' ', 8, 0

filesize equ $ - ehdr
