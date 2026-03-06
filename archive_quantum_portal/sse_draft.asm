; --- SSE STREAMING ARCHITECTURE PIPELINE ---
; We inject this into the main chat loop instead of `run_shell`

section .bss
    pipe_fd resd 2         ; int pipe_fd[2] (8 bytes total)
    poll_fds resb 16       ; struct pollfd (2 elements, 8 bytes each)
                           ; [fd(4)|events(2)|revents(2)]
    sse_buf resb 256       ; read chunk buffer
    print_buf resb 128     ; output line buffer
    print_len resq 1       ; current len of print_buf
    fsm_state resb 1       ; 0=seek, 1=in_content

section .text

do_streaming_chat:
    ; 1. Create Pipe with O_NONBLOCK
    mov rax, 293           ; sys_pipe2
    lea rdi, [rel pipe_fd]
    mov rsi, 0x800         ; O_NONBLOCK
    syscall
    test rax, rax
    js .pipe_err

    ; 2. Fork
    mov rax, 57            ; sys_fork
    syscall
    test rax, rax
    js .fork_err
    jz .child_process      ; rax == 0 means child

.parent_process:
    ; Parent: Close write end of pipe
    mov rax, 3             ; sys_close
    mov edi, dword [rel pipe_fd + 4]
    syscall

    ; Setup pollfd struct for the read pipe
    ; poll_fds[0].fd = pipe_fd[0]
    mov eax, dword [rel pipe_fd]
    mov dword [rel poll_fds], eax
    ; poll_fds[0].events = POLLIN (0x0001)
    mov word [rel poll_fds + 4], 1
    ; poll_fds[0].revents = 0
    mov word [rel poll_fds + 6], 0

    ; Reset FSM
    mov byte [rel fsm_state], 0
    mov qword [rel print_len], 0

.poll_loop:
    ; 3. sys_poll loop
    mov rax, 7             ; sys_poll
    lea rdi, [rel poll_fds]
    mov rsi, 1             ; 1 fd to watch (could add stdin later)
    mov rdx, 100           ; timeout 100ms
    syscall

    ; Check if pipe has data (revents & POLLIN)
    mov ax, word [rel poll_fds + 6]
    test ax, 1
    jz .poll_loop          ; No data, wait again
    
    ; Check if pipe hung up (revents & POLLHUP)
    test ax, 0x10          ; POLLHUP = 0x0010
    jnz .stream_done

    ; 4. Read from pipe
    mov rax, 0             ; sys_read
    mov edi, dword [rel pipe_fd]
    lea rsi, [rel sse_buf]
    mov rdx, 256
    syscall
    
    test rax, rax
    jle .stream_done       ; EOF or error

    ; ... Process rax bytes using JSON FSM ...
    ; call process_sse_chunk

    jmp .poll_loop

.stream_done:
    ; Close read end
    mov rax, 3
    mov edi, dword [rel pipe_fd]
    syscall
    
    ; Wait for child
    mov rax, 61            ; sys_wait4
    mov rdi, -1
    xor rsi, rsi
    mov rdx, 0
    xor r10, r10
    syscall
    ret

.child_process:
    ; Child: Close read end of pipe
    mov rax, 3             ; sys_close
    mov edi, dword [rel pipe_fd]
    syscall

    ; Redirect stdout (fd 1) to write end of pipe (pipe_fd[1])
    mov rax, 33            ; sys_dup2
    mov edi, dword [rel pipe_fd + 4]
    mov rsi, 1             ; stdout
    syscall

    ; Execute curl
    lea rdi, [rel cmd_chat] ; Assume cmd_chat contains the curl command
    call run_shell         ; Existing routine that sets up execve
    
    ; If execve fails
    mov rax, 60            ; sys_exit
    mov rdi, 1
    syscall

.pipe_err:
.fork_err:
    ret
