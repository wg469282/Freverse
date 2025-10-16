#!/bin/bash

# Wymagane: sudo apt install strace

nasm -f elf64 -w+all -w+error -w-unknown-warning -w-reloc-rel -o freverse.o freverse.asm
ld --fatal-warnings -o freverse freverse.o

set -e  # Zatrzymaj na błędzie

generate_random_file() {
    local filename="$1"
    local size_bytes="$2"
    dd if=/dev/urandom of="$filename" bs=1 count="$size_bytes" 2>/dev/null
}

reverse_file_python() {
    local input_path="$1"
    local output_path="$2"
    python3 -c "
import sys
with open('$input_path', 'rb') as f:
    data = f.read()
with open('$output_path', 'wb') as f:
    f.write(data[::-1])
"
}

run_freverse_inplace_strace() {
    local file_path="$1"
    local strace_log="$2"
    
    if ! strace -e munmap,close -o "$strace_log" ./freverse "$file_path" 2>/dev/null; then
        echo "freverse failed"
        exit 1
    fi
}

check_strace_log() {
    local log_path="$1"
    
    local munmap_count=$(grep -c "munmap" "$log_path" 2>/dev/null || echo 0)
    local close_count=$(grep -c "close" "$log_path" 2>/dev/null || echo 0)
    
    if [ "$munmap_count" -ne 1 ]; then
        echo "❌ ERROR: No munmap call detected."
        return 1
    fi
    
    if [ "$close_count" -ne 1 ]; then
        echo "❌ ERROR: No close call detected."
        return 1
    fi
    
    return 0
}

cleanup_files() {
    local files=("$@")
    for file in "${files[@]}"; do
        [ -f "$file" ] && rm -f "$file"
    done
}

main() {
    local max_size=$((32 * 1024))  # 32KB
    
    for i in $(seq 1 99); do
        # Generuj losowy rozmiar
        local size=$((RANDOM % max_size + 1))
        echo "Generating random file of size: $size bytes"
        
        local input_file="test_input.bin"
        local input_for_freverse="input_for_freverse.bin"
        local output_py="output_python.bin"
        local strace_log="freverse_strace.log"
        
        # Generuj plik testowy
        generate_random_file "$input_file" "$size"
        
        # Skopiuj plik dla freverse
        cp "$input_file" "$input_for_freverse"
        
        # Odwróć plik w Pythonie (referencja)
        reverse_file_python "$input_file" "$output_py"
        
        # Uruchom freverse ze strace
        run_freverse_inplace_strace "$input_for_freverse" "$strace_log"
        
        # Porównaj wyniki
        if ! diff "$output_py" "$input_for_freverse" >/dev/null 2>&1; then
            echo "❌ Byte output differs from Python."
            cleanup_files "$input_file" "$input_for_freverse" "$output_py" "$strace_log"
            exit 1
        fi
        
        # Sprawdź logi strace
        if ! check_strace_log "$strace_log"; then
            echo "❌ freverse failed to unmap or close properly."
            cleanup_files "$input_file" "$input_for_freverse" "$output_py" "$strace_log"
            exit 1
        fi
        
        # Posprzątaj pliki
        cleanup_files "$input_file" "$input_for_freverse" "$output_py" "$strace_log"
    done
    
    echo "!!!All tests passed!!!"
}

# Sprawdź czy freverse istnieje
if [ ! -f "./freverse" ]; then
    echo "❌ ERROR: ./freverse not found"
    exit 1
fi

# Sprawdź czy strace jest dostępne
if ! command -v strace >/dev/null 2>&1; then
    echo "❌ ERROR: strace not installed. Run: sudo apt install strace"
    exit 1
fi

main "$@"
