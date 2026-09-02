#!/bin/bash
# Test script for the pure-mil VM (vm.mil) and self-hosting compiler
set -e
cd "$(dirname "$0")"
echo "=== Building boot compiler ==="
make 2>&1 | grep -E "error|Error" || true
echo ""
PASS=0
FAIL=0
check() {
    if [ "$1" = "$2" ]; then
        echo "  PASS: $3"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $3"
        FAIL=$((FAIL + 1))
    fi
}
echo "=== 1. Self-hosting: compiler.mil compiles itself ==="
./minilang dump-text compiler.mil > /tmp/minilang_boot_self.txt 2>/dev/null
./minilang run compiler.mil dump-text compiler.mil > /tmp/minilang_mil_self.txt 2>/dev/null
if diff -q /tmp/minilang_boot_self.txt /tmp/minilang_mil_self.txt > /dev/null 2>&1; then
    echo "  PASS: boot == self-hosted ($(wc -l < /tmp/minilang_boot_self.txt) lines)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: boot != self-hosted"
    FAIL=$((FAIL + 1))
fi
echo ""
echo "=== 2. Compiler output identity (all tests) ==="
for f in tests/*.mil; do
    ./minilang dump-text "$f" > /tmp/minilang_a.txt 2>/dev/null
    ./minilang run compiler.mil dump-text "$f" > /tmp/minilang_b.txt 2>/dev/null
    if diff -q /tmp/minilang_a.txt /tmp/minilang_b.txt > /dev/null 2>&1; then
        echo "  PASS: $f"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $f"
        FAIL=$((FAIL + 1))
    fi
done
echo ""
echo "=== 3. mil VM runtime matches boot VM ==="
for f in tests/*.mil; do
    ./minilang dump-text "$f" > /tmp/minilang_test.bc 2>/dev/null
    boot_out=$(./minilang run "$f" 2>&1)
    mil_out=$(./minilang run vm.mil /tmp/minilang_test.bc 2>&1)
    check "$boot_out" "$mil_out" "$f"
done
echo ""
echo "=== 4. Full chain: boot -> bytecode -> mil VM -> compiler ==="
./minilang dump-text compiler.mil > /tmp/minilang_compiler.bc 2>/dev/null
./minilang run vm.mil /tmp/minilang_compiler.bc dump-text compiler.mil > /tmp/minilang_chain.txt 2>/dev/null
if diff -q /tmp/minilang_boot_self.txt /tmp/minilang_chain.txt > /dev/null 2>&1; then
    echo "  PASS: full chain identical"
    PASS=$((PASS + 1))
else
    echo "  FAIL: full chain differs"
    FAIL=$((FAIL + 1))
fi
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ $FAIL -eq 0 ]; then
    echo "ALL TESTS PASSED"
    exit 0
else
    echo "SOME TESTS FAILED"
    exit 1
fi
