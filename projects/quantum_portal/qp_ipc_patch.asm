; =====================================================================
; QUANTUM PORTAL: IPC PIPES PATCH
; Instructions: Splice this into the main quantum_portal.asm
; =====================================================================

; --> 1. Add Definitions at the top (under %define OFF_WINSZ)
%define SYS_read      0
%define SYS_write     1
%define SYS_open      2
%define SYS_poll      7

%define O_RDONLY      0x0000
%define O_WRONLY      0x0001
%define O_RDWR        0x0002
%define O_NONBLOCK    0x0800

%define POLLIN        0x0001


; --> 2. Add pipe strings to the .data equivalent block
str_pipe_tx: db "/tmp/qp_tx", 0
str_pipe_rx: db "/tmp/qp_rx", 0


; --> 3. Allocate file descriptor storage in the .bss equivalent block
; (Assuming you are using r14 offset addressing, define new offsets)
%define OFF_FD_TX     0x110
%define OFF_FD_RX     0x118


; --> 4. Open the Pipes in _start (Place this before main_loop)
init_pipes:
    ; Open TX Pipe (We use RDWR to prevent blocking if python is offline)
    mov eax, SYS_open
    lea rdi, [rel str_pipe_tx]
    mov esi, O_RDWR
    xor edx, edx
    syscall
    mov [r14 + OFF_FD_TX], eax

    ; Open RX Pipe (Non-Blocking)
    mov eax, SYS_open
    lea rdi, [rel str_pipe_rx]
    mov esi, O_RDONLY | O_NONBLOCK  ; (0x0800)
    xor edx, edx
    syscall
    mov [r14 + OFF_FD_RX], eax


; --> 5. Update sys_poll in the main_loop to check both FDs
; The struct pollfd is 8 bytes. We need an array of 2 structures (16 bytes total).
; Structure 0 (STDIN)
mov dword [r14 + OFF_TMP], 0        ; fd = 0 (STDIN)
mov word  [r14 + OFF_TMP + 4], POLLIN ; events = POLLIN
mov word  [r14 + OFF_TMP + 6], 0    ; revents = 0

; Structure 1 (RX PIPE)
mov eax, [r14 + OFF_FD_RX]
mov dword [r14 + OFF_TMP + 8], eax  ; fd = fd_rx
mov word  [r14 + OFF_TMP + 12], POLLIN
mov word  [r14 + OFF_TMP + 14], 0

; Call sys_poll
mov eax, SYS_poll
lea rdi, [r14 + OFF_TMP]            ; pointer to pollfd array
mov esi, 2                          ; nfds = 2
mov edx, 10                         ; timeout = 10ms (so we don't burn cpu)
syscall


; --> 6. Read from RX Pipe if data is ready
; Check if poll returned > 0, then check the revents of fd_rx
cmp eax, 0
jle skip_rx

mov cx, [r14 + OFF_TMP + 14]        ; load revents for Structure 1 (fd_rx)
test cx, POLLIN
jz skip_rx

; Data is ready on RX Pipe! Read it.
mov eax, SYS_read
mov edi, [r14 + OFF_FD_RX]
lea rsi, [r14 + OFF_RENDER]         ; Render buffer
mov edx, 4096                       ; max read length
syscall

; Here we would route the buffer to the draw_text function.

skip_rx:
    ; Proceed to check STDIN (Structure 0 revents at offset 6)
