[bits 64]

hdr:
db  0x7f, "ELF", 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0      ; e_ident
dw  2, 0x3e                                    ; e_type ET_EXEC, e_machine AMD64
dd  1                                          ; e_version
dq  0x400078                                  ; e_entry vaddr
dq  phdr - hdr                                 ; e_phoff
dq  0                                          ; e_shoff
dd  0                                          ; e_flags
dw  64, 56, 1, 0, 0, 0                        ; e_ehsize, e_phentsize, e_phnum, e_shentsize, e_shnum, e_shstrndx

phdr:
dd  1                                          ; p_type PT_LOAD
dd  5                                          ; p_flags PF_R|PF_X
dq  0                                          ; p_offset
dq  0x400000                                   ; p_vaddr
dq  0x400000                                   ; p_paddr
dq  0                                          ; p_filesz PATCH WITH ACTUAL FILE SIZE (LE 64bit)
dq  0                                          ; p_memsz same
dq  8                                          ; p_align

bufsize equ 4096
code_start:
_start:
        pop     rcx                             ; argc
        sub     rsp, bufsize
        cmp     rcx, 2
        jge     .use_arg

.read_stdin:
        mov     r12, rsp                        ; current buf pos
        xor     r13, r13                        ; msg_len = 0
.read_loop:
        lea     rdx, [rsp + bufsize]
        sub     rdx, r12                        ; remaining
        test    rdx, rdx
        jz      .got_msg
        mov     rax, 0                          ; sys_read
        mov     rdi, 0                          ; stdin
        syscall
        test    rax, rax
        jle     .got_msg
        add     r12, rax
        add     r13, rax
        jmp     .read_loop

.use_arg:
        mov     rdi, [rsp + bufsize + 8]        ; argv[1]
        xor     rax, rax
        mov     rcx, -1
        repne   scasb
        not     rcx
        lea     r13, [rcx - 1]                  ; len
        mov     r12, rdi                        ; ptr
        jmp     .got_msg

.got_msg:
        ; green header
        mov     rax, 1
        mov     rdi, 1
        mov     rsi, header
        mov     rdx, header_len
        syscall
        ; message
        mov     rax, 1
        mov     rdi, 1
        mov     rsi, r12
        mov     rdx, r13
        syscall
        ; newline
        mov     rax, 1
        mov     rdi, 1
        mov     rsi, nl
        mov     rdx, 1
        syscall
        ; blue footer
        mov     rax, 1
        mov     rdi, 1
        mov     rsi, footer
        mov     rdx, footer_len
        syscall
        ; exit(0)
        mov     rax, 60
        xor     rdi, rdi
        syscall

header db 0x1b,'[32m=== Your message to Grok 4.20 ===',0x1b,'[0m',10
header_len equ $ - header
nl db 10
footer db 0x1b,'[34mPaste this full response back to Grok 4.20 here for review/iteration. What next?',0x1b,'[0m',10
footer_len equ $ - footer
