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
    dq 0x400000
    dq 0x400000
    dq filesize
    dq filesize
    dq 0x1000

%define OFF_TOPIC     0x000
%define TOPIC_CAP     192
%define OFF_EXT       0x0c0
%define EXT_CAP       32
%define OFF_FILE      0x100
%define FILE_CAP      256
%define OFF_BODY      0x200
%define BODY_CAP      1024
%define OFF_CONTENT   0x600
%define CONTENT_CAP   2048
%define STACK_SIZE    0xe00

; Registers:
;   r8d  = 1 when body was read from stdin pipe
;   r9   = ext buffer pointer
;   r10d = 1 when ext is "md"
;   r12  = content length
;   r13  = topic buffer pointer
;   r14  = filename buffer pointer
;   r15  = content buffer pointer

_start:
    mov rbp, rsp
    sub rsp, STACK_SIZE

    xor r8d, r8d
    lea r13, [rsp + OFF_TOPIC]
    lea r9,  [rsp + OFF_EXT]
    lea r14, [rsp + OFF_FILE]
    lea r15, [rsp + OFF_CONTENT]

    mov byte [r13], 0

    ; ext = default "md"
    lea rdi, [rsp + OFF_EXT]
    lea rsi, [rel default_ext]
    mov ecx, EXT_CAP
    call copy_z_max

    mov rax, [rbp]              ; argc
    cmp rax, 1
    jg .argv_mode

.stdin_mode:
    xor eax, eax                ; read(0, topic, TOPIC_CAP-1)
    xor edi, edi
    lea rsi, [rsp + OFF_TOPIC]
    mov edx, TOPIC_CAP - 1
    syscall
    test rax, rax
    jle .post_topic_input

    lea rcx, [rsp + OFF_TOPIC]
    mov byte [rcx + rax], 0
    lea rdx, [rcx + rax - 1]
    cmp byte [rdx], 10
    jne .post_topic_input
    mov byte [rdx], 0
    jmp .post_topic_input

.argv_mode:
    ; Safe copy argv[1] into bounded topic buffer.
    mov rsi, [rbp + 16]
    lea rdi, [rsp + OFF_TOPIC]
    mov ecx, TOPIC_CAP
    call copy_z_max

    ; Optional argv[2] extension.
    cmp qword [rbp], 2
    jle .probe_body
    mov rsi, [rbp + 24]
    lea rdi, [rsp + OFF_EXT]
    mov ecx, EXT_CAP
    call copy_z_max

    ; Trim optional leading dot in extension.
    cmp byte [rsp + OFF_EXT], '.'
    jne .ext_norm
    lea rsi, [rsp + OFF_EXT + 1]
    lea rdi, [rsp + OFF_EXT]
    mov ecx, EXT_CAP
    call copy_z_max

.ext_norm:
    lea rdi, [rsp + OFF_EXT]
    call lowercase_z
    cmp byte [rsp + OFF_EXT], 0
    jne .probe_body
    lea rdi, [rsp + OFF_EXT]
    lea rsi, [rel default_ext]
    mov ecx, EXT_CAP
    call copy_z_max

.probe_body:
    ; If stdin is not a TTY, read body from pipe.
    mov eax, 16                 ; ioctl
    xor edi, edi
    mov esi, 0x5401             ; TCGETS
    lea rdx, [rsp + OFF_TOPIC + 64]
    syscall
    test eax, eax
    jns .post_topic_input

    xor eax, eax                ; read body
    xor edi, edi
    lea rsi, [rsp + OFF_BODY]
    mov edx, BODY_CAP - 1
    syscall
    test rax, rax
    jle .post_topic_input

    lea rcx, [rsp + OFF_BODY]
    mov byte [rcx + rax], 0
    lea rdx, [rcx + rax - 1]
    cmp byte [rdx], 10
    jne .body_done
    mov byte [rdx], 0
.body_done:
    mov r8d, 1

.post_topic_input:
    cmp byte [rsp + OFF_TOPIC], 0
    jne .build_filename
    lea rdi, [rsp + OFF_TOPIC]
    lea rsi, [rel untitled]
    mov ecx, TOPIC_CAP
    call copy_z_max

.build_filename:
    lea rdi, [rsp + OFF_FILE]
    lea rdx, [rsp + OFF_FILE + FILE_CAP - 1]
    lea rsi, [rel filename_prefix]
    call append_z_cap
    lea rsi, [rsp + OFF_TOPIC]
    call append_z_cap
    cmp rdi, rdx
    jae .append_ext
    mov byte [rdi], '.'
    inc rdi
    mov byte [rdi], 0
.append_ext:
    lea rsi, [rsp + OFF_EXT]
    call append_z_cap

    ; Detect markdown mode.
    xor r10d, r10d
    lea rsi, [rsp + OFF_EXT]
    cmp byte [rsi], 'm'
    jne .forge_start
    cmp byte [rsi + 1], 'd'
    jne .forge_start
    cmp byte [rsi + 2], 0
    jne .forge_start
    mov r10d, 1

.forge_start:
    lea rdi, [rsp + OFF_CONTENT]
    lea rdx, [rsp + OFF_CONTENT + CONTENT_CAP - 1]

    ; Markdown keeps the summary envelope for compatibility.
    test r10d, r10d
    jz .non_md
    lea rsi, [rel md_title]
    call append_z_cap
    lea rsi, [rsp + OFF_TOPIC]
    call append_z_cap
    test r8d, r8d
    jz .md_template
    lea rsi, [rel md_body_sep]
    call append_z_cap
    lea rsi, [rsp + OFF_BODY]
    call append_z_cap
    jmp .calc_len

.md_template:
    lea rsi, [rel md_mid]
    call append_z_cap
    lea rsi, [rsp + OFF_TOPIC]
    call append_z_cap
    lea rsi, [rel md_end]
    call append_z_cap
    jmp .calc_len

.non_md:
    ; Non-md + body: emit raw body so files are true type payloads.
    test r8d, r8d
    jz .non_md_template
    lea rsi, [rsp + OFF_BODY]
    call append_z_cap
    jmp .calc_len

.non_md_template:
    ; Minimal no-body templates for common non-md types.
    lea rsi, [rsp + OFF_EXT]
    cmp byte [rsi], 'j'
    jne .check_sh
    cmp byte [rsi + 1], 's'
    jne .check_sh
    cmp byte [rsi + 2], 'o'
    jne .check_sh
    cmp byte [rsi + 3], 'n'
    jne .check_sh
    cmp byte [rsi + 4], 0
    jne .check_sh
    lea rsi, [rel json_a]
    call append_z_cap
    lea rsi, [rsp + OFF_TOPIC]
    call append_z_cap
    lea rsi, [rel json_b]
    call append_z_cap
    jmp .calc_len

.check_sh:
    lea rsi, [rsp + OFF_EXT]
    cmp byte [rsi], 's'
    jne .check_py
    cmp byte [rsi + 1], 'h'
    jne .check_py
    cmp byte [rsi + 2], 0
    jne .check_py
    lea rsi, [rel sh_a]
    call append_z_cap
    lea rsi, [rsp + OFF_TOPIC]
    call append_z_cap
    lea rsi, [rel sh_b]
    call append_z_cap
    jmp .calc_len

.check_py:
    lea rsi, [rsp + OFF_EXT]
    cmp byte [rsi], 'p'
    jne .plain_template
    cmp byte [rsi + 1], 'y'
    jne .plain_template
    cmp byte [rsi + 2], 0
    jne .plain_template
    lea rsi, [rel py_a]
    call append_z_cap
    lea rsi, [rsp + OFF_TOPIC]
    call append_z_cap
    lea rsi, [rel py_b]
    call append_z_cap
    jmp .calc_len

.plain_template:
    lea rsi, [rsp + OFF_TOPIC]
    call append_z_cap
    lea rsi, [rel nl]
    call append_z_cap

.calc_len:
    mov r12, rdi
    sub r12, r15

    mov eax, 257                ; openat(AT_FDCWD, file, O_CREAT|O_WRONLY|O_TRUNC, 0644)
    mov edi, -100
    mov rsi, r14
    mov edx, 0x241
    mov r10d, 0x1a4
    syscall
    test eax, eax
    js .exit_fail
    mov ebx, eax

    mov eax, 1                  ; write(file, content, len)
    mov edi, ebx
    mov rsi, r15
    mov rdx, r12
    syscall

    mov eax, 3                  ; close(file)
    mov edi, ebx
    syscall

    mov eax, 1                  ; stdout green preview
    mov edi, 1
    lea rsi, [rel ansi_green]
    mov edx, ansi_green_len
    syscall

    mov eax, 1
    mov edi, 1
    mov rsi, r15
    mov rdx, r12
    syscall

    mov eax, 1
    mov edi, 1
    lea rsi, [rel ansi_reset]
    mov edx, ansi_reset_len
    syscall

    xor edi, edi
    jmp .exit

.exit_fail:
    mov edi, 1

.exit:
    mov eax, 60
    syscall

; -------------------------------- helpers --------------------------------

append_z_cap:
    ; rdi=dst, rsi=src, rdx=last writable byte for NUL terminator
.az_loop:
    lodsb
    test al, al
    jz .az_done
    cmp rdi, rdx
    jae .az_loop
    stosb
    jmp .az_loop
.az_done:
    cmp rdi, rdx
    jbe .az_term
    mov rdi, rdx
.az_term:
    mov byte [rdi], 0
    ret

copy_z_max:
    ; rdi=dst, rsi=src, ecx=dst capacity in bytes
    test ecx, ecx
    jz .cz_ret
    dec ecx                     ; reserve room for trailing NUL
    js .cz_ret
.cz_loop:
    lodsb
    test al, al
    jz .cz_done
    test ecx, ecx
    jz .cz_drain
    stosb
    dec ecx
    jmp .cz_loop
.cz_drain:
    lodsb
    test al, al
    jnz .cz_drain
.cz_done:
    mov byte [rdi], 0
.cz_ret:
    ret

lowercase_z:
    ; rdi=string
.lc_loop:
    mov al, [rdi]
    test al, al
    jz .lc_ret
    cmp al, 'A'
    jb .lc_next
    cmp al, 'Z'
    ja .lc_next
    add byte [rdi], 32
.lc_next:
    inc rdi
    jmp .lc_loop
.lc_ret:
    ret

; -------------------------------- data --------------------------------

filename_prefix: db "grok-", 0
default_ext: db "md", 0
untitled: db "untitled", 0

md_title: db "# Grok on ", 0
md_mid: db 10, 10, "## Intro", 10, "About ", 0
md_end: db ".", 10, 0
md_body_sep: db 10, 10, 0

json_a: db '{"topic":"', 0
json_b: db '"}', 10, 0
sh_a: db '#!/bin/sh', 10, '# ', 0
sh_b: db 10, 0
py_a: db '# ', 0
py_b: db 10, 0
nl: db 10, 0

ansi_green: db 27, "[1;32m"
ansi_green_len equ $ - ansi_green
ansi_reset: db 27, "[0m", 10
ansi_reset_len equ $ - ansi_reset

filesize equ $ - ehdr
