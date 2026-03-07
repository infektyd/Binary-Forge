; Minimal x86_64 NASM serial console for Creality CR-10S Pro (Marlin)
; /dev/ttyUSB0 @ 115200 8N1 raw mode
; Build: nasm -f elf64 -o serial.o serial.asm && ld -nostdlib -pie -o serial serial.o

section .data
dev_ttyusb0: db '/dev/ttyUSB0', 0
prompt: db '> ', 0

section .bss
serial_fd: resq 1
term_buf: resb 60
resp_buf: resb 512
resp_len: resq 1
cmd_buf: resb 256
cmd_len: resq 1

section .text
global _start

struc termios
 .c_iflag: resd 1
 .c_oflag: resd 1
 .c_cflag: resd 1
 .c_lflag: resd 1
 .c_line: resb 1
 .c_cc: resb 32
endstruc

; Syscall numbers
SYS_read  equ 0
SYS_write equ 1
SYS_open  equ 2
SYS_ioctl equ 16
SYS_exit  equ 60

; open() flags
O_RDWR   equ 2
O_NOCTTY equ 0x100

; ioctl commands
TCGETS equ 0x5401
TCSETS equ 0x5402

; Serial settings
B115200 equ 0x1002
CS8     equ 0x30
CREAD   equ 0x80
CLOCAL  equ 0x800

VTIME equ 5
VMIN  equ 6

; =============================================================
; Helper: strlen (rdi = string) -> rax = length
; =============================================================
strlen:
 xor rax, rax
.loop:
 cmp byte [rdi + rax], 0
 je .done
 inc rax
 jmp .loop
.done:
 ret

; =============================================================
; int open_serial(void) -> rax = fd or negative errno
; =============================================================
open_serial:
 mov rax, SYS_open
 lea rdi, [rel dev_ttyusb0]
 mov esi, O_RDWR | O_NOCTTY
 xor edx, edx
 syscall
 cmp rax, 0
 jle .err
 mov [rel serial_fd], rax
.err:
 ret

; =============================================================
; void config_serial_raw(void) - 115200 8N1 raw, no echo/flow
; =============================================================
config_serial_raw:
 mov rdi, [rel serial_fd]
 mov rax, SYS_ioctl
 mov rsi, TCGETS
 lea rdx, [rel term_buf]
 syscall

 mov dword [rel term_buf + termios.c_iflag], 0
 mov dword [rel term_buf + termios.c_oflag], 0
 mov eax, B115200 | CS8 | CREAD | CLOCAL
 mov dword [rel term_buf + termios.c_cflag], eax
 mov dword [rel term_buf + termios.c_lflag], 0

 mov byte [rel term_buf + 17 + VTIME], 0
 mov byte [rel term_buf + 17 + VMIN], 1

 mov rdi, [rel serial_fd]
 mov rax, SYS_ioctl
 mov rsi, TCSETS
 lea rdx, [rel term_buf]
 syscall
 ret

; =============================================================
; void send_gcode(rdi = null-terminated command)
; =============================================================
send_gcode:
 push rdi
 call strlen
 mov rdx, rax
 pop rsi
 mov rdi, [rel serial_fd]
 mov rax, SYS_write
 syscall
 ret

; =============================================================
; ssize_t read_response(void) -> rax = bytes read (callee-safe)
; =============================================================
read_response:
 push r12
 xor r12, r12
.loop:
 mov rdi, [rel serial_fd]
 lea rsi, [rel resp_buf + r12]
 mov rdx, 1
 mov rax, SYS_read
 syscall

 cmp rax, 1
 jne .done

 inc r12
 cmp byte [rel resp_buf + r12 - 1], 0xa
 je .done

 cmp r12, 510
 jb .loop
.done:
 mov [rel resp_len], r12
 mov rax, r12
 pop r12
 ret

; =============================================================
; bool has_ok(void) -> rax = 1 if "ok" present in resp_buf
; =============================================================
has_ok:
 mov rdx, [rel resp_len]
 cmp rdx, 2
 jb .no
 lea rdi, [rel resp_buf]
.loop:
 cmp byte [rdi], 'o'
 jne .next
 cmp byte [rdi + 1], 'k'
 je .yes
.next:
 inc rdi
 dec rdx
 cmp rdx, 1
 ja .loop
.no:
 xor rax, rax
 ret
.yes:
 mov rax, 1
 ret

; =============================================================
; void read_until_ok(void) - read lines until "ok"
; =============================================================
read_until_ok:
 push rbx
.loop:
 call read_response
 call has_ok
 test rax, rax
 jnz .print_final
 call print_response
 jmp .loop
.print_final:
 call print_response
 pop rbx
 ret

; =============================================================
; void print_str(rdi = null-terminated string)
; =============================================================
print_str:
 push rdi
 call strlen
 mov rdx, rax
 pop rsi
 mov rdi, 1
 mov rax, SYS_write
 syscall
 ret

; =============================================================
; void print_response(void) - echo resp_buf to stdout
; =============================================================
print_response:
 mov rdi, 1
 lea rsi, [rel resp_buf]
 mov rdx, [rel resp_len]
 mov rax, SYS_write
 syscall
 ret

; =============================================================
; ssize_t read_stdin_line(void) -> rax = bytes read
; =============================================================
read_stdin_line:
 push r12
 xor r12, r12
.loop:
 mov rdi, 0
 lea rsi, [rel cmd_buf + r12]
 mov rdx, 1
 mov rax, SYS_read
 syscall
 cmp rax, 1
 jne .done
 inc r12
 cmp byte [rel cmd_buf + r12 - 1], 0xa
 je .done
 cmp r12, 254
 jb .loop
.done:
 mov byte [rel cmd_buf + r12], 0
 mov [rel cmd_len], r12
 mov rax, r12
 pop r12
 ret

; =============================================================
; Entry point
; =============================================================
_start:
 call open_serial
 test rax, rax
 js exit_error

 call config_serial_raw

main_loop:
 lea rdi, [rel prompt]
 call print_str

 call read_stdin_line
 test rax, rax
 jz .exit

 lea rdi, [rel cmd_buf]
 call send_gcode

 call read_until_ok
 jmp main_loop

.exit:
 xor rdi, rdi
 jmp do_exit

exit_error:
 mov rdi, 1
do_exit:
 mov rax, SYS_exit
 syscall
