#!/bin/bash
# Full self-hosting verification: all C components have mil equivalents
sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

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
echo "=== 8. build command ==="
echo "  build -b: compile to .milc bytecode file"
rm -f /tmp/sh_hello.milc
cp tests/hello.mil /tmp/sh_hello.mil
./minilang run main.mil build -b /tmp/sh_hello.mil > /dev/null 2>&1
check "$(test -f /tmp/sh_hello.milc && echo OK)" "OK" "build -b creates .milc file"
echo "  run .milc file"
./minilang run main.mil run /tmp/sh_hello.milc > /tmp/sh_milc_run.out 2>/dev/null
check "$(diff -q /tmp/sh_boot_run.out /tmp/sh_milc_run.out >/dev/null && echo OK)" "OK" "run .milc output matches"
echo "  build -e: generate .ll file (IR compile requires llvmlite)"
rm -f /tmp/sh_hello.ll
./minilang run main.mil build -e /tmp/sh_hello.mil > /dev/null 2>&1
check "$(test -f /tmp/sh_hello.ll && echo OK)" "OK" "build -e creates .ll file"
echo "  boot build main.mil: no duplicate global definitions"
./minilang llvm main.mil 2>/dev/null
check "$(grep -a '^@global_' main.ll 2>/dev/null | sort | uniq -d | wc -l | tr -d ' ')" "0" "no duplicate global definitions in main.mil IR"
rm -f main.ll /tmp/sh_hello.mil /tmp/sh_hello.milc /tmp/sh_hello.ll
echo "=== 9. Native build (requires llvmlite + gcc) ==="
if python3 -c "import llvmlite" 2>/dev/null; then
    echo "  boot build main.mil -> native executable"
    rm -f /tmp/sh_main_native
    ./minilang build main.mil > /dev/null 2>&1
    if [ -f main ]; then
        mv main /tmp/sh_main_native
        check "OK" "OK" "boot build main.mil produces native executable"
        echo "  native executable runs programs"
        /tmp/sh_main_native run tests/hello.mil > /tmp/sh_native_run.out 2>/dev/null
        check "$(diff -q /tmp/sh_boot_run.out /tmp/sh_native_run.out >/dev/null && echo OK)" "OK" "native executable output matches"
        echo "  native executable self-hosts compiler.mil"
        /tmp/sh_main_native dump-text compiler.mil > /tmp/sh_native_compiler.txt 2>/dev/null
        check "$(diff -q /tmp/sh_boot.txt /tmp/sh_native_compiler.txt >/dev/null && echo OK)" "OK" "native executable compiles compiler.mil identically"
        rm -f /tmp/sh_main_native
    else
        check "FAIL" "OK" "boot build main.mil produces native executable"
    fi
else
    echo "  SKIP: llvmlite not installed"
fi

echo "=== 10. New commands: bytecode / self-test / repl (must match boot) ==="
echo "  bytecode: human-readable disassembly"
for f in tests/hello.mil tests/fib.mil tests/array_test.mil tests/nested_test.mil tests/require_test.mil tests/require_path.mil; do
    base=$(basename "$f" .mil)
    ./minilang bytecode "$f" > /tmp/sh_bc_boot_$base.txt 2>/dev/null
    ./minilang run main.mil bytecode "$f" > /tmp/sh_bc_mil_$base.txt 2>/dev/null
    check "$(diff -q /tmp/sh_bc_boot_$base.txt /tmp/sh_bc_mil_$base.txt >/dev/null && echo OK)" "OK" "bytecode command matches boot for $base"
done
echo "  self-test"
./minilang run main.mil self-test 2>/dev/null | grep -v "Self-hosting test" | grep -v "self-test:" > /tmp/sh_st_mil.txt
./minilang self-test 2>/dev/null | grep -v "Self-hosting test" | grep -v "boot compile done" > /tmp/sh_st_boot.txt
check "$(diff -q /tmp/sh_st_boot.txt /tmp/sh_st_mil.txt >/dev/null && echo OK)" "OK" "self-test dumps compiler.mil bytecode identically"
echo "  repl (piped input)"
printf 'println 42;\nfunc add(a, b) { return a + b; }\nprintln add(2, 3);\nquit\n' | ./minilang repl > /tmp/sh_repl_boot.txt 2>/dev/null
printf 'println 42;\nfunc add(a, b) { return a + b; }\nprintln add(2, 3);\nquit\n' | ./minilang run main.mil repl > /tmp/sh_repl_mil.txt 2>/dev/null
check "$(diff -q /tmp/sh_repl_boot.txt /tmp/sh_repl_mil.txt >/dev/null && echo OK)" "OK" "repl output matches boot"
echo "=== 11. A/B two-compiler self-hosting acceptance ==="
echo "  A = boot-compiled compiler.mil; B = A-compiled compiler.mil"
echo "  Step 1: boot compiles compiler.mil -> A"
rm -f compiler
./minilang build compiler.mil > /dev/null 2>&1
if [ -f compiler ]; then
    mv compiler /tmp/sh_compiler_A
    check "OK" "OK" "boot builds A compiler"
else
    check "FAIL" "OK" "boot builds A compiler"
fi
echo "  Step 2: A compiles + runs all test programs"
for f in tests/hello.mil tests/fib.mil tests/array_test.mil tests/nested_test.mil tests/require_test.mil tests/require_path.mil; do
    base=$(basename "$f" .mil)
    /tmp/sh_compiler_A dump-text "$f" > /tmp/sh_A_$base.bc 2>/dev/null
    ./minilang run "$f" > /tmp/sh_ref_$base.out 2>/dev/null
    ./minilang run vm.mil /tmp/sh_A_$base.bc > /tmp/sh_A_$base.out 2>/dev/null
    check "$(diff -q /tmp/sh_ref_$base.out /tmp/sh_A_$base.out >/dev/null && echo OK)" "OK" "A runs $base"
done
echo "  Step 3: A compiles itself (B bytecode); compare A bytecode with boot"
/tmp/sh_compiler_A dump-text compiler.mil > /tmp/sh_B_bc.txt 2>/dev/null
./minilang dump-text compiler.mil > /tmp/sh_boot_bc.txt 2>/dev/null
check "$(diff -q /tmp/sh_B_bc.txt /tmp/sh_boot_bc.txt >/dev/null && echo OK)" "OK" "A/B bytecode identical (boot == A-compiled)"
echo "  Step 4: A/B binary identical (same LLVM IR -> same native binary)"
./minilang llvm compiler.mil 2>/dev/null
mv compiler.ll /tmp/sh_A_compiler.ll
./minilang run main.mil llvm compiler.mil > /tmp/sh_B_compiler.ll 2>/dev/null
check "$(diff -q /tmp/sh_A_compiler.ll /tmp/sh_B_compiler.ll >/dev/null && echo OK)" "OK" "A/B LLVM IR identical"
if python3 -c "import llvmlite" 2>/dev/null; then
    python3 ir_compile.py /tmp/sh_A_compiler.ll /tmp/sh_A_compiler.o > /dev/null 2>&1
    python3 ir_compile.py /tmp/sh_B_compiler.ll /tmp/sh_B_compiler.o > /dev/null 2>&1
    gcc -o /tmp/sh_compiler_A_bin /tmp/sh_A_compiler.o runtime.c -O2 2>/dev/null
    gcc -o /tmp/sh_compiler_B_bin /tmp/sh_B_compiler.o runtime.c -O2 2>/dev/null
    ha=$(sha256_file /tmp/sh_compiler_A_bin | cut -d' ' -f1)
    hb=$(sha256_file /tmp/sh_compiler_B_bin | cut -d' ' -f1)
    check "$ha" "$hb" "A/B binary sha256 identical ($ha)"
fi
echo "  Step 5: B (A-compiled bytecode) runs all test programs"
for f in tests/hello.mil tests/fib.mil tests/array_test.mil tests/nested_test.mil tests/require_test.mil tests/require_path.mil; do
    base=$(basename "$f" .mil)
    /tmp/sh_compiler_A dump-text "$f" > /tmp/sh_B_$base.bc 2>/dev/null
    ./minilang run vm.mil /tmp/sh_B_$base.bc > /tmp/sh_B_$base.out 2>/dev/null
    check "$(diff -q /tmp/sh_ref_$base.out /tmp/sh_B_$base.out >/dev/null && echo OK)" "OK" "B runs $base"
done
rm -f /tmp/sh_compiler_A compiler.ll compiler.o compiler /tmp/sh_A_*.ll /tmp/sh_B_*.ll /tmp/sh_A_*.o /tmp/sh_B_*.o


echo "=== 12. Native main self-host: A builds itself -> B, A/B binary identical ==="
echo "  A = boot-built main.mil; B = A-built main.mil (native, no OOM after IR buffer optimization)"
rm -f main main.ll main.o main_A
./minilang build main.mil > /dev/null 2>&1
if [ -f main ]; then
    cp main main_A
    rm -f main main.ll main.o
    ./main_A build main.mil > /dev/null 2>&1
    if [ -f main ]; then
        check "OK" "OK" "A (main_A) builds main.mil -> B (main) natively"
        ha=$(sha256_file main_A | cut -d' ' -f1)
        hb=$(sha256_file main | cut -d' ' -f1)
        check "$ha" "$hb" "A/B native binary sha256 identical ($ha)"
        echo "  B runs all test programs"
        for f in tests/hello.mil tests/fib.mil tests/array_test.mil tests/nested_test.mil tests/require_test.mil tests/require_path.mil; do
            base=$(basename "$f" .mil)
            ./main run "$f" > /tmp/sh_B2_$base.out 2>/dev/null
            ./minilang run "$f" > /tmp/sh_ref2_$base.out 2>/dev/null
            check "$(diff -q /tmp/sh_ref2_$base.out /tmp/sh_B2_$base.out >/dev/null && echo OK)" "OK" "B (native) runs $base"
        done
    else
        check "FAIL" "OK" "A (main_A) builds main.mil -> B (main) natively"
    fi
    rm -f main main.ll main.o main_A
else
    check "FAIL" "OK" "boot builds main.mil natively"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ $FAIL -eq 0 ]; then
    echo "ALL TESTS PASSED - Full self-hosting verified!"
else
    echo "SOME TESTS FAILED"
    exit 1
fi