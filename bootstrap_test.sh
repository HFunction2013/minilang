#!/bin/bash
# Self-hosting verification script for minilang
# Boot compiler (C) compiles compiler.mil -> bytecode text A
# Self-hosted compiler (compiler.mil running on VM) compiles compiler.mil -> bytecode text B
# A and B must be byte-for-byte identical
set -e
cd "$(dirname "$0")"
echo "=== Building boot compiler (C) ==="
make 2>&1 | grep -E "error|Error" || true
echo ""
echo "=== Step 1: Boot compiler compiles compiler.mil ==="
./minilang dump-text compiler.mil > /tmp/minilang_boot_bc.txt 2>/tmp/minilang_boot_err.txt
echo "Exit code: $?"
if [ -s /tmp/minilang_boot_err.txt ]; then
    echo "Errors:"
    cat /tmp/minilang_boot_err.txt
    exit 1
fi
echo "Output: $(wc -l < /tmp/minilang_boot_bc.txt) lines"
echo ""
echo "=== Step 2: Self-hosted compiler compiles compiler.mil ==="
echo "(compiler.mil runs on VM, reads its own source from stdin)"
cat compiler.mil | ./minilang run compiler.mil > /tmp/minilang_self_bc.txt 2>/tmp/minilang_self_err.txt
echo "Exit code: $?"
if [ -s /tmp/minilang_self_err.txt ]; then
    echo "Errors:"
    cat /tmp/minilang_self_err.txt
    exit 1
fi
echo "Output: $(wc -l < /tmp/minilang_self_bc.txt) lines"
echo ""
echo "=== Step 3: Compare bytecode outputs ==="
if diff -q /tmp/minilang_boot_bc.txt /tmp/minilang_self_bc.txt > /dev/null 2>&1; then
    echo "SUCCESS: Boot and self-hosted bytecode are IDENTICAL!"
    echo ""
    echo "Self-hosting verified: the minilang compiler can compile itself"
    echo "and produce deterministic, reproducible bytecode."
    exit 0
else
    echo "FAILURE: Bytecode outputs differ!"
    echo "Diff (first 30 lines):"
    diff /tmp/minilang_boot_bc.txt /tmp/minilang_self_bc.txt | head -30
    exit 1
fi
