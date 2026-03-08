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
%define OFF_TERMIOS     0x080
%define STACK_SIZE      0x9800

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

    call pick_mood

    call get_winsize
    call set_raw_mode
    call render_layout

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

.process_input:
    call setup_abstract_socket
    test rax, rax
    js .exit_ok                        ; connection failed (or close, but js catches neg err)
    mov [r14 + OFF_FD_TX], eax         ; use OFF_FD_TX to hold the single socket fd

    ; Write user input buffer to socket
    lea rdi, [r14 + OFF_INPUT]
    call string_len
    mov edx, eax                       ; string length to rdx

    mov eax, 1                         ; SYS_write
    mov edi, [r14 + OFF_FD_TX]         ; socket fd
    lea rsi, [r14 + OFF_INPUT]         ; buffer ptr
    syscall

    ; Wait for AI response stream to become available
    mov r15d, [r14 + OFF_FD_TX]
    call poll_connect_completion

    ; Start reading exactly at OFF_RESP_TEXT
    lea r12, [r14 + OFF_RESP_TEXT]
    
.response_loop:
    mov edi, [r14 + OFF_FD_TX]
    mov rsi, r12
    mov edx, 4096
    xor eax, eax                       ; SYS_read
    syscall

    cmp eax, 0
    jle .response_done                 ; 0 = EOF/close, <0 = error

    add r12, rax                       ; advance buffer pointer
    jmp .response_loop                 ; keep reading until EOF

.response_done:
    ; Null terminate
    mov byte [r12], 0

    ; Clean up socket
    mov r15d, [r14 + OFF_FD_TX]
    call socket_cleanup

    ; Render the text to the screen!
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

    ; fcntl(fd, F_GETFL)
    mov     rax, 72
    mov     rdi, r15
    mov     rsi, 3
    syscall
    test    rax, rax
    js      .error

    ; fcntl(fd, F_SETFL, flags | O_NONBLOCK)
    or      rax, 0x800
    mov     rdx, rax
    mov     rax, 72
    mov     rdi, r15
    mov     rsi, 4
    syscall
    test    rax, rax
    js      .error

    sub     rsp, 32
    xor     eax, eax
    mov     qword [rsp],    rax
    mov     qword [rsp+8],  rax
    mov     qword [rsp+16], rax
    mov     qword [rsp+24], rax

    mov     word  [rsp], 1
    mov rax, 0x636f735f6b6f7267
    mov qword [rsp+3], rax
    mov     word  [rsp+11], 0x656b
    mov     byte  [rsp+13], 0x74

    ; connect(fd, addr, 14)
    mov     rax, 42
    mov     rdi, r15
    mov     rsi, rsp
    mov     edx, 14
    syscall

    add     rsp, 32

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

poll_connect_completion:
    sub rsp, 16
    mov dword [rsp], r15d
    mov word  [rsp+4], 0x0001       ; POLLIN -- waiting for Python to WRITE to us!
    mov word  [rsp+6], 0

    mov eax, 7
    mov rdi, rsp
    mov esi, 1
    mov rdx, -1
    syscall

    test eax, eax
    jle .poll_done

    movzx eax, word [rsp+6]

.poll_done:
    add rsp, 16
    ret

socket_cleanup:
    mov eax, 48
    mov rdi, r15
    mov esi, 2
    syscall

    mov eax, 3
    mov rdi, r15
    syscall
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
    and eax, 3
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

; ---------------- data ----------------

ansi_clear: db 27, '[2J', 27, '[H', 0
ansi_reset: db 27, '[0m', 10, 0

stars_1: db 27,'[38;5;24m',27,'[2;2H.   *      .      +     .     *',27,'[3;10H*   .    +     .   *',27,'[4;4H.   *   .      +      .',27,'[0m',0
stars_2: db 27,'[38;5;25m',27,'[2;6H*   .      .    +      *',27,'[3;3H.     *    .      +    .   *',27,'[4;12H+   .      *      .',27,'[0m',0
stars_3: db 27,'[38;5;31m',27,'[2;4H.  +    .      *      .   +',27,'[3;12H*    .    +     .   *',27,'[4;1H.     *      .    +      .',27,'[0m',0

hdr_title: db 27,'[1;2H', 'SYNTRA DRIFT FORCE -- QUANTUM PORTAL',0

frame_wide: db 27,'[6;1H+----------------------+-----------------------------------------------+----------------------------------+',27,'[7;1H| Conversations        | Main Chat                                     | Canvas / Artifact                |',27,'[8;1H+----------------------+-----------------------------------------------+----------------------------------+',27,'[23;1H+----------------------+-----------------------------------------------+----------------------------------+',0

frame_compact: db 27,'[6;1H+--------------------------------------------------------------+',27,'[7;1H| Quantum Portal (compact mode)                               |',27,'[8;1H+--------------------------------------------------------------+',0

sidebar_conv: db 27,'[38;5;45m',27,'[9;3HRaw ELF Forge',27,'[10;3HGrokdoc v6',27,'[11;3HQuantum Whisper Portal',27,'[12;3HNebula Artifact Lab',27,'[13;3HSignal Drift Chat',27,'[0m',0
sidebar_conv_compact: db 27,'[38;5;45m',27,'[9;2HConversations: Raw ELF Forge | Grokdoc v6 | Quantum Whisper',27,'[0m',0

model_hdr: db 27,'[38;5;39m',27,'[15;3HModels from xAI API:',10,0
prompt_model: db 27,'[38;5;214mSelect model [1-8]: ',27,'[0m',0
selected_prefix: db 27,'[38;5;51mSelected model: ',27,'[0m',0
prompt_chat: db 27,'[38;5;117mPick convo 1-4 or type prompt: ',27,'[0m',0

pos_selected: db 27,'[8;2H',0
pos_chat_user: db 27,'[11;2H',10,10,0
pos_chat_ai: db 10,10,0
pos_canvas: db 27,'[9;74H',0

chat_user_hdr: db 27,'[1;36mYou: ',27,'[0m',0
chat_ai_hdr: db 27,'[1;34mAssistant: ',27,'[0m',0

canvas_hdr: db 27,'[1;36m# Canvas / Artifact',10,27,'[0m',0
md_prompt: db '## Prompt',10,0
md_resp: db 10,'## Response',10,0

conv_prompt_1: db 'Summarize the Raw ELF Forge roadmap in 5 bullets.',0
conv_prompt_2: db 'Draft grokdoc v6 release notes with syscall-level highlights.',0
conv_prompt_3: db 'Design a holographic Quantum Whisper Portal UX plan.',0
conv_prompt_4: db 'Generate a markdown artifact with tasks, risks, and next steps.',0



fallback_model: db 'minimax/minimax-m2.5',0
str_pipe_tx: db "/tmp/qp_tx", 0
str_pipe_rx: db "/tmp/qp_rx", 0

mood_chill: db 27,'[38;5;51m',0
mood_grind: db 27,'[38;5;226m',0
mood_chaos: db 27,'[38;5;201m',0
mood_intense: db 27,'[38;5;196m',0




nl: db 10,0
backspace_seq: db 8, ' ', 8, 0

filesize equ $ - ehdr


string_len:
    xor eax, eax
.loop:
    cmp byte [rdi+rax], 0
    je .done
    inc eax
    jmp .loop
.done:
    ret
