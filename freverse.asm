; =============================================================================
; Program: freverse.asm
; -----------------------------------------------------------------------------
; Cel: Odwraca zawartość pliku w miejscu (bez tworzenia pliku tymczasowego).
; 
; Użycie: ./freverse <nazwa_pliku>
;
; Działanie:
; - Mapuje plik do pamięci za pomocą mmap
; - Wykorzystuje optymalizację poprzez pracę na 16-bajtowych blokach
; - Odwraca kolejność bajtów używając instrukcji bswap dla bloków 8-bajtowych
; - Pozostałe bajty są odwracane pojedynczo
; =============================================================================

section .text
global _start

_start:
    ; Pobranie liczby argumentów (argc) ze stosu
    pop rax             ; RAX = argc (liczba argumentów)
    cmp al, 2           ; Sprawdzenie czy podano dokładnie 1 argument 
    jne exit_error      ; Jeśli nie, wyjście z błędem

    ; Pobranie nazwy pliku ze stosu
    pop rdi             ; Ignorujemy nazwę programu
    pop rdi             ; RDI = wskaźnik na nazwę pliku

    ; Otwarcie pliku
    mov eax, 2          ; sys_open (32-bitowy rejestr)
    mov esi, 2          ; O_RDWR - tryb odczytu i zapisu
    syscall             ; Wywołanie systemowe
    test eax, eax       ; Sprawdzenie czy deskryptor pliku jest poprawny
    js exit_error       ; Jeśli znacznik SF=1 (błąd), wyjście z błędem
    mov r13d, eax       ; Zapis deskryptora pliku w R13D (32-bit)

    ; Pobranie rozmiaru pliku przez fstat
    mov eax, 5          ; sys_fstat
    mov edi, r13d       ; Deskryptor pliku
    lea rsi, [rel stat_buf]   ; Wskaźnik na strukturę stat (adresowanie względne)
    syscall
    test eax, eax       ; Sprawdzenie błędów
    js close_exit       ; Jeśli błąd, zamknij plik i wyjdź

    mov r14, [rel stat_buf + 48] ; Pobranie rozmiaru pliku 
    cmp r14, 2          ; Sprawdzenie minimalnego rozmiaru pliku
    jl close_file       ; Jeśli plik < 2 bajtów, od razu zamykamy

    ; Mapowanie pliku do pamięci
    mov eax, 9          ; sys_mmap
    xor edi, edi        ; Automatyczne przydzielenie adresu
    mov rsi, r14        ; Rozmiar mapowania = rozmiar pliku
    mov edx, 3          ; PROT_READ|PROT_WRITE - dostęp do pamięci
    mov r10d, 1         ; MAP_SHARED - zmiany widoczne w pliku
    mov r8d, r13d       ; Deskryptor pliku
    xor r9d, r9d        ; Offset = 0
    syscall
    cmp rax, -4096      ; Sprawdzenie błędów (zwracane wartości > -4095)
    jae close_exit      ; Jeśli błąd, posprzątaj i wyjdź

    ; Inicjalizacja wskaźników do odwracania
    mov r15, rax        ; Zachowaj adres mapowania w R15
    mov rdi, rax        ; RDI = początek bufora
    lea rsi, [rax + r14 - 1] ; RSI = koniec bufora (adres ostatniego bajtu)

    ; Główna pętla odwracania - praca na 16-bajtowych blokach
    mov rcx, r14        ; RCX = rozmiar pliku
    shr rcx, 4          ; Liczba pełnych 16-bajtowych bloków
    jz .remainder       ; Jeśli brak pełnych bloków, przejdź do reszty

.block_loop:
    ; Odwracanie kolejności bajtów w 16-bajtowym bloku
    mov rax, [rdi]      ; Pierwsze 8 bajtów
    mov rbx, [rsi-7]    ; Ostatnie 8 bajtów (rsi-7 = rsi-8+1)
    bswap rax           ; Odwrócenie kolejności bajtów w RAX
    bswap rbx           ; Odwrócenie kolejności bajtów w RBX
    mov [rdi], rbx      ; Zamiana miejscami bloków 8-bajtowych
    mov [rsi-7], rax
    add rdi, 8          ; Przesunięcie wskaźnika początku w prawo
    sub rsi, 8          ; Przesunięcie wskaźnika końca w lewo
    dec rcx             ; Licznik bloków
    jnz .block_loop     ; Kontynuuj aż do przerobienia wszystkich bloków

.remainder:
    ; Obsługa pozostałych bajtów (dla rozmiarów niepodzielnych przez 16)
    cmp rdi, rsi        ; Sprawdzenie czy wskaźniki się minęły
    jge .cleanup        ; Jeśli tak, zakończ

.byte_loop:
    ; Odwracanie pojedynczych bajtów
    mov al, [rdi]       ; Bajt z początku
    mov bl, [rsi]       ; Bajt z końca
    mov [rdi], bl       ; Zamiana miejsc
    mov [rsi], al
    inc rdi             ; Przesuń wskaźnik początku w prawo
    dec rsi             ; Przesuń wskaźnik końca w lewo
    cmp rdi, rsi        ; Sprawdź czy trzeba kontynuować
    jl .byte_loop

.cleanup:
    ; Zwolnienie zasobów
    mov eax, 11         ; sys_munmap
    mov rdi, r15        ; Adres mapowania z R15
    mov rsi, r14        ; Rozmiar mapowania
    syscall

close_file:
    ; Zamknięcie pliku
    mov eax, 3          ; sys_close
    mov edi, r13d       ; Deskryptor pliku
    syscall

exit:
    ; Poprawne zakończenie programu
    mov eax, 60         ; sys_exit
    xor edi, edi        ; Kod wyjścia 0
    syscall

close_exit:
    ; Obsługa błędów z zamknięciem pliku
    mov eax, 3
    mov edi, r13d
    syscall

exit_error:
    ; Wyjście z błędem
    mov rax, 60             ; sys_exit
    mov rdi, 1              ; kod wyjścia = 1
    syscall


section .bss
    stat_buf resb 144  ; Bufor dla struktury stat