bits 64

_start:
	pop	rdi
	cmp	rdi, byte 2
	je	arg

	call	header
	call	msgcolor
loop:
	sub	rsp, 64
	mov	rdi, 0
	mov	rsi, rsp
	mov	rdx, 64
	xor	rax, rax
	syscall
	test	rax, rax
	jle	endloop
	mov	rdx, rax
	mov	rdi, 1
	mov	rax, 1
	syscall
	add	rsp, 64
	jmp	loop
endloop:
	add	rsp, 64
	call	reset
	call	footer
	jmp	exit_

arg:
	mov	rsi, [rsp+8]
	call	strlen
	mov	rdx, rax
	push	rsi
	push	rdx
	call	header
	call	msgcolor
	pop	rdx
	pop	rsi
	mov	rdi, 1
	mov	rax, 1
	syscall
	call	reset
	call	footer

exit_:
	xor	rdi, rdi
	mov	rax, 60
	syscall

strlen:
	mov	rcx, rsi
	xor	rax, rax
sloop:
	cmp	byte [rcx], 0
	je	sret
	inc	rcx
	inc	rax
	jmp	sloop
sret:
	ret

printstr:
	mov	rdi, 1
	mov	rax, 1
	syscall
	ret

header:
	lea	rsi, [rel hstr]
	mov	rdx, hstr_len
	jmp	printstr

footer:
	lea	rsi, [rel fstr]
	mov	rdx, fstr_len
	jmp	printstr

msgcolor:
	lea	rsi, [rel cstr]
	mov	rdx, cstr_len
	jmp	printstr

reset:
	lea	rsi, [rel rstr]
	mov	rdx, rstr_len
	jmp	printstr

hstr:
	db 0x1b,'[32;1m'
	db '+---------------+', 0xa
	db '|QUANTUM v4     |', 0xa
	db '|Linus raw ELF! |', 0xa
	db '+---------------+', 0xa
	db 0x1b,'[0m'
hstr_len equ $ - hstr

cstr:
	db 0x1b,'[33;5m'
cstr_len equ $ - cstr

fstr:
	db 0x1b,'[36;1m'
	db '+---------------+', 0xa
	db '|Whisper sent!  |', 0xa
	db '+---------------+', 0xa
	db 0x1b,'[0m'
fstr_len equ $ - fstr

rstr:
	db 0x1b,'[0m'
rstr_len equ $ - rstr