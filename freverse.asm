freverse-english
; =============================================================================
; Program: freverse.asm
; -----------------------------------------------------------------------------
; Goal: Reverses file contents in place (without creating a temporary file).
; 
; Usage: ./freverse <filename>
;
; Operation:
; - Maps file to memory using mmap
; - Uses optimization by working on 16-byte blocks
; - Reverses byte order using bswap instruction for 8-byte blocks
; - Remaining bytes are reversed individually
; =============================================================================


section .text
global _start


_start:
    ; Get number of arguments (argc) from stack
    pop rax             ; RAX = argc (number of arguments)
    cmp al, 2           ; Check if exactly 1 argument was provided 
    jne exit_error      ; If not, exit with error


    ; Get filename from stack
    pop rdi             ; Ignore program name
    pop rdi             ; RDI = pointer to filename


    ; Open file
    mov eax, 2          ; sys_open (32-bit register)
    mov esi, 2          ; O_RDWR - read and write mode
    syscall             ; System call
    test eax, eax       ; Check if file descriptor is valid
    js exit_error       ; If SF flag=1 (error), exit with error
    mov r13d, eax       ; Save file descriptor in R13D (32-bit)


    ; Get file size via fstat
    mov eax, 5          ; sys_fstat
    mov edi, r13d       ; File descriptor
    lea rsi, [rel stat_buf]   ; Pointer to stat structure (relative addressing)
    syscall
    test eax, eax       ; Check for errors
    js close_exit       ; If error, close file and exit


    mov r14, [rel stat_buf + 48] ; Get file size 
    cmp r14, 2          ; Check minimum file size
    jl close_file       ; If file < 2 bytes, close 


    ; Map file to memory
    mov eax, 9          ; sys_mmap
    xor edi, edi        ; Automatic address allocation
    mov rsi, r14        ; Mapping size = file size
    mov edx, 3          ; PROT_READ|PROT_WRITE - memory access
    mov r10d, 1         ; MAP_SHARED - changes visible in file
    mov r8d, r13d       ; File descriptor
    xor r9d, r9d        ; Offset = 0
    syscall
    cmp rax, -4096      ; Check for errors (returned values > -4095)
    jae close_exit      ; If error, clean up and exit


    ; Initialize pointers for reversal
    mov r15, rax        ; Save mapping address in R15
    mov rdi, rax        ; RDI = buffer start
    lea rsi, [rax + r14 - 1] ; RSI = buffer end (address of last byte)


    ; Main reversal loop - working on 16-byte blocks
    mov rcx, r14        ; RCX = file size
    shr rcx, 4          ; Number of full 16-byte blocks
    jz .remainder       ; If no full blocks, go to remainder


.block_loop:
    ; Reverse byte order in 16-byte block
    mov rax, [rdi]      ; First 8 bytes
    mov rbx, [rsi-7]    ; Last 8 bytes (rsi-7 = rsi-8+1)
    bswap rax           ; Reverse byte order in RAX
    bswap rbx           ; Reverse byte order in RBX
    mov [rdi], rbx      ; Swap 8-byte blocks
    mov [rsi-7], rax
    add rdi, 8          ; Move start pointer right
    sub rsi, 8          ; Move end pointer left
    dec rcx             ; Block counter
    jnz .block_loop     ; Continue until all blocks processed


.remainder:
    ; Handle remaining bytes (for sizes not divisible by 16)
    cmp rdi, rsi        ; Check if pointers crossed
    jge .cleanup        ; If so, finish


.byte_loop:
    ; Reverse individual bytes
    mov al, [rdi]       ; Byte from start
    mov bl, [rsi]       ; Byte from end
    mov [rdi], bl       ; Swap places
    mov [rsi], al
    inc rdi             ; Move start pointer right
    dec rsi             ; Move end pointer left
    cmp rdi, rsi        ; Check if need to continue
    jl .byte_loop


.cleanup:
    ; Free resources
    mov eax, 11         ; sys_munmap
    mov rdi, r15        ; Mapping address from R15
    mov rsi, r14        ; Mapping size
    syscall


close_file:
    ; Close file
    mov eax, 3          ; sys_close
    mov edi, r13d       ; File descriptor
    syscall


exit:
    ; Proper program termination
    mov eax, 60         ; sys_exit
    xor edi, edi        ; Exit code 0
    syscall


close_exit:
    ; Error handling with file close
    mov eax, 3
    mov edi, r13d
    syscall


exit_error:
    ; Exit with error
    mov rax, 60             ; sys_exit
    mov rdi, 1              ; exit code = 1
    syscall



section .bss
    stat_buf resb 144  ; Buffer for stat structure