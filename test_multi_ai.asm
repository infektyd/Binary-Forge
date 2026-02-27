; Test Multi-AI Fetch + Loader (Minimal Binary)
BITS 64
org 0x400000

ehdr:
    db 0x7F, "ELF", 2, 1, 1, 0  ; ELF header (simplified for tiny binary)
    times 8 db 0
    dw 2      ; e_type = ET_EXEC
    dw 62     ; e_machine = EM_X86_64
    dd 1      ; e_version
    dq _start ; e_entry
    dq phdr - $$ ; e_phoff
    dq 0      ; e_shoff
    dd 0      ; e_flags
    dw ehdrsize ; e_ehsize
    dw phdrsize ; e_phentsize
    dw 1      ; e_phnum
    dw 0, 0, 0
ehdrsize equ $ - ehdr

phdr:
    dd 1      ; p_type = PT_LOAD
    dd 5      ; p_flags = R+X
    dq 0      ; p_offset
    dq $$     ; p_vaddr
    dq $$     ; p_paddr
    dq filesize ; p_filesz
    dq filesize ; p_memsz
    dq 0x1000 ; p_align
phdrsize equ $ - phdr

_start:
    ; Test call: api_id=0 (xAI), prompt="Hello", buffers
    mov rdi, 0  ; api_id
    lea rsi, [rel prompt]
    mov rdx, prompt_len
    lea rcx, [rel resp_buf]
    mov r8, 1024
    call fetch_ai

    ; Load response
    mov rdi, rcx
    mov rsi, 1024  ; assume full
    lea rdx, [rel out_buf]
    mov rcx, 256
    call binary_ai_loader

    ; Output extracted text (sys_write to stdout)
    mov rax, 1
    mov rdi, 1
    lea rsi, [rel out_buf]
    mov rdx, 256  ; max
    syscall

    mov rax, 60  ; exit
    xor rdi, rdi
    syscall

section .data
    api_table:
        dq xai_endpoint, xai_auth, 0
        dq claude_endpoint, claude_auth, 1
        dq gemini_endpoint, gemini_auth, 2

    xai_endpoint db "https://api.x.ai/v1/chat/completions", 0
    xai_auth db "Authorization: Bearer DUMMY_KEY", 0xd, 0xa, 0
    claude_endpoint db "https://api.anthropic.com/v1/messages", 0
    claude_auth db "x-api-key: DUMMY_CLAUDE", 0xd, 0xa, 0
    gemini_endpoint db "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent?key=DUMMY_GEMINI", 0
    gemini_auth db "", 0

    prompt db "{\"model\": \"grok-4\", \"messages\": [{\"role\": \"user\", \"content\": \"Hello\"}]}", 0
    prompt_len equ $ - prompt

    resp_buf times 1024 db 0
    out_buf times 256 db 0

    sockaddr dw 2, 443 shl 8  ; AF_INET, port 443 (dummy IP next)
    dd 0x0100007f     ; 127.0.0.1
    times 8 db 0

section .text
fetch_ai:
    imul rax, rdi, 24
    lea rbx, [api_table + rax]
    mov r9, [rbx]
    mov r10, [rbx+8]
    call syscall_fetch
    ret

syscall_fetch:
    mov rax, 41
    mov rdi, 2
    mov rsi, 1
    mov rdx, 6
    syscall
    mov r12, rax

    mov rax, 42
    lea rsi, [rel sockaddr]
    mov rdx, 16
    syscall

    ; Dummy send (full request build omitted for test)
    mov rax, 44
    lea rsi, [rel prompt]  ; Using prompt as dummy request
    mov rdx, prompt_len
    syscall

    mov rax, 45
    lea rsi, [rel resp_buf]
    mov rdx, 1024
    syscall

    mov rax, 3
    mov rdi, r12
    syscall
    ret

binary_ai_loader:
    ; Dummy scan for test - assume response has "content\": \"Hi\""
    lea rbx, [rel key_content]
    mov r10, key_len
scan:
    cmp rsi, 0
    je end
    mov al, [rbx]
    cmp [rdi], al
    je match_start
    inc rdi
    dec rsi
    jmp scan
match_start:
    ; Skip to value, copy to out (simplified)
    add rdi, r10 + 1  ; Past key + ': "'
    xor rcx, rcx
copy:
    cmp byte [rdi], '"'
    je end
    mov al, [rdi]
    mov [rdx + rcx], al
    inc rdi
    inc rcx
    jmp copy
end:
    mov byte [rdx + rcx], 0  ; Null-term
    ret

key_content db "content\": \"", 0
key_len equ $ - key_content

filesize equ $ - $$
