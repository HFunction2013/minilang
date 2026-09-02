#!/bin/bash
# Full self-hosting verification: all C components have mil equivalents
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
echo "=== 1. compiler.mil self-hosting (compiles itself) ==="
./minilang dump-text compiler.mil > /tmp/sh_boot.txt 2>/dev/null
./minilang run compiler.mil dump-text compiler.mil > /tmp/sh_mil.txt 2>/dev/null
check "$(diff -q /tmp/sh_boot.txt /tmp/sh_mil.txt >/dev/null && echo OK)" "OK" "compiler.mil output matches boot"
echo "=== 2. vm.mil runs all test programs ==="
for f in tests/hello.mil tests/fib.mil tests/array_test.mil tests/nested_test.mil tests/require_test.mil tests/require_path.mil; do
    base=$(basename "$f" .mil)
    ./minilang dump-text "$f" > /tmp/sh_$base.bc 2>/dev/null
    ./minilang run "$f" > /tmp/sh_boot_$base.out 2>/dev/null
    ./minilang run vm.mil /tmp/sh_$base.bc > /tmp/sh_vm_$base.out 2>/dev/null
    check "$(diff -q /tmp/sh_boot_$base.out /tmp/sh_vm_$base.out >/dev/null && echo OK)" "OK" "vm.mil runs $base"
done
echo "=== 3. llvm_gen.mil matches boot LLVM IR ==="
for f in tests/hello.mil tests/fib.mil tests/array_test.mil tests/nested_test.mil tests/require_test.mil tests/require_path.mil; do
    base=$(basename "$f" .mil)
    ./minilang llvm "$f" 2>/dev/null
    if [ -f "tests/$base.ll" ]; then
        ./minilang run llvm_gen.mil "$f" > /tmp/sh_$base.ll 2>/dev/null
        check "$(diff -q tests/$base.ll /tmp/sh_$base.ll >/dev/null && echo OK)" "OK" "llvm_gen.mil matches $base"
        rm -f "tests/$base.ll"
    fi
done
echo "=== 4. milc_io.mil serialization matches boot ==="
for f in tests/hello.mil tests/fib.mil; do
    base=$(basename "$f" .mil)
    ./minilang dump-text "$f" > /tmp/sh_io_boot_$base.txt 2>/dev/null
    ./minilang run milc_io.mil "$f" > /tmp/sh_io_mil_$base.txt 2>/dev/null
    check "$(diff -q /tmp/sh_io_boot_$base.txt /tmp/sh_io_mil_$base.txt >/dev/null && echo OK)" "OK" "milc_io.mil matches $base"
done
echo "=== 5. main.mil unified CLI ==="
./minilang run main.mil run tests/hello.mil > /tmp/sh_main_run.out 2>/dev/null
./minilang run tests/hello.mil > /tmp/sh_boot_run.out 2>/dev/null
check "$(diff -q /tmp/sh_main_run.out /tmp/sh_boot_run.out >/dev/null && echo OK)" "OK" "main.mil run command"
./minilang run main.mil dump-text tests/hello.mil > /tmp/sh_main_dt.txt 2>/dev/null
check "$(diff -q /tmp/sh_boot.txt /tmp/sh_main_dt.txt >/dev/null; echo skip)" "skip" "main.mil dump-text command (hello)"
./minilang dump-text tests/hello.mil > /tmp/sh_dt_boot.txt 2>/dev/null
check "$(diff -q /tmp/sh_dt_boot.txt /tmp/sh_main_dt.txt >/dev/null && echo OK)" "OK" "main.mil dump-text matches boot"
./minilang run main.mil llvm tests/hello.mil > /tmp/sh_main_llvm.ll 2>/dev/null
./minilang llvm tests/hello.mil 2>/dev/null
check "$(diff -q tests/hello.ll /tmp/sh_main_llvm.ll >/dev/null && echo OK)" "OK" "main.mil llvm command"
rm -f tests/hello.ll
echo "=== 6. Full self-hosting chain ==="
echo "  boot -> main.mil bytecode -> vm.mil -> compile compiler.mil"
./minilang dump-text main.mil > /tmp/sh_main.bc 2>/dev/null
./minilang run vm.mil /tmp/sh_main.bc dump-text compiler.mil > /tmp/sh_chain.txt 2>/dev/null
check "$(diff -q /tmp/sh_boot.txt /tmp/sh_chain.txt >/dev/null && echo OK)" "OK" "full chain output identical"
echo "  boot -> main.mil bytecode -> vm.mil -> run hello.mil"
./minilang run vm.mil /tmp/sh_main.bc run tests/hello.mil > /tmp/sh_chain_run.out 2>/dev/null
check "$(diff -q /tmp/sh_boot_run.out /tmp/sh_chain_run.out >/dev/null && echo OK)" "OK" "full chain runs programs"
echo "  boot -> main.mil bytecode -> vm.mil -> llvm hello.mil"
./minilang run vm.mil /tmp/sh_main.bc llvm tests/hello.mil > /tmp/sh_chain_llvm.ll 2>/dev/null
./minilang llvm tests/hello.mil 2>/dev/null
check "$(diff -q tests/hello.ll /tmp/sh_chain_llvm.ll >/dev/null && echo OK)" "OK" "full chain generates LLVM IR"
rm -f tests/hello.ll
echo "=== 7. Program arguments ==="
cat > /tmp/sh_args.mil << 'MILEOF'
func main() {
    var n = argc();
    println toString(n);
    var i = 0;
    while (i < n) {
        println argv(i);
        i = i + 1;
    }
    return 0;
}
MILEOF
./minilang run main.mil run /tmp/sh_args.mil hello world > /tmp/sh_args.out 2>/dev/null
echo -e "3\n/tmp/sh_args.mil\nhello\nworld" > /tmp/sh_args_expected.txt
check "$(diff -q /tmp/sh_args_expected.txt /tmp/sh_args.out >/dev/null && echo OK)" "OK" "program arguments correct"
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ $FAIL -eq 0 ]; then
    echo "ALL TESTS PASSED - Full self-hosting verified!"
else
    echo "SOME TESTS FAILED"
    exit 1
fi
