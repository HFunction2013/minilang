# minilang

一个极简的可自举编程语言，支持双编译后端：字节码 VM 和 LLVM 原生编译。

源文件后缀为 `.mil`，字节码文件后缀为 `.milc`（魔数 `!milc`）。

## 特性

- **C-like 语法**：函数、递归、if/else、while、var 声明、数组、字符串
- **双后端**：
  - 字节码 + 栈式 VM（快速开发、调试）
  - LLVM IR → 原生可执行文件（高性能）
- **完整自举**：所有 C 源文件均有对应的 minilang 实现，仅靠最小 boot VM 即可独立运行完整工具链
  - `compiler.mil`：词法分析 + 解析 + 字节码生成（对应 lexer.c/parser.c/bytecode.c）
  - `vm.mil`：纯 mil 栈式虚拟机（对应 vm.c/value.c/runtime.c）
  - `llvm_gen.mil`：LLVM IR 生成器（对应 llvm_gen.c）
  - `milc_io.mil`：字节码序列化（对应 milc_io.c，文本格式）
  - `main.mil`：统一 CLI 入口（对应 main.c）
- **自举编译器**：`compiler.mil` 能编译自身，输出与 C boot 编译器逐字节一致
- **无外部依赖**：不使用文件、网络等外部交互（除 console I/O）
- **内置函数**：`len`, `charAt`, `substr`, `toString`, `toInt`, `strcmp`, `readAll`, `array`, `argc`, `argv`, `readFile`, `fileExists`, `writeFile`, `system`, `readLine`
- **模块系统（require）**：从 syslib 或脚本目录加载模块，支持命名空间访问和选择性导入
- **REPL**：交互式命令行，支持多行输入、表达式求值、跨行保留函数/变量/模块
- **.milc 字节码文件**：可编译为二进制字节码文件，随时加载运行

## 构建

```bash
make
```

生成 `minilang` 可执行文件（C 实现的 boot 编译器 + VM）。

### LLVM 后端依赖

LLVM 后端使用 Python 的 `llvmlite` 包将 IR 编译为目标文件：

```bash
pip install -r requirements.txt
```

系统 `gcc` 用于最终链接。

## CLI 用法

```bash
# 1. 在 VM 上运行程序（支持 .mil 源码 或 .milc 字节码）
./minilang run tests/hello.mil
./minilang run tests/hello.milc

# 2. 输出人类可读的字节码反汇编
./minilang bytecode tests/hello.mil

# 3. 输出自举对比用的文本格式字节码
./minilang dump-text tests/hello.mil

# 4. 输出 LLVM IR (.ll 文件)
./minilang llvm tests/hello.mil

# 5. 编译为 .milc 字节码文件（魔数 "!milc"）
./minilang build -b tests/hello.mil
./minilang build --bytecode tests/hello.mil

# 6. 编译为原生可执行文件 (LLVM 后端, 默认)
./minilang build -e tests/hello.mil
./minilang build --executable tests/hello.mil
./minilang build tests/hello.mil    # 默认 -e
./tests/hello

# 7. 交互式 REPL（mil 版：echo 管道可批处理测试）
./minilang repl
printf 'println 42;\nquit\n' | ./minilang run main.mil repl

# 8. 自举验证（完整 A/B 双编译器验收，含 bytecode/self-test/repl）
./bootstrap_test.sh
./full_selfhost_test.sh
```

`main.mil`（mil 版统一入口）提供与 boot `minilang` 完全一致的全部命令：
`run` / `bytecode` / `dump-text` / `llvm` / `build -b|-e` / `repl` / `self-test`。
其中 `self-test` 用 mil 编译器编译 `compiler.mil` 并输出其字节码（与 boot 逐字节一致）。

```bash
# 用 mil 版统一入口运行同一批命令
./minilang run main.mil bytecode tests/hello.mil
./minilang run main.mil self-test
```


## 语言语法

```minilang
// 全局变量
var GLOBAL_CONST = 42;

// 函数定义（支持递归）
func fib(n) {
    if (n < 2) { return n; }
    return fib(n - 1) + fib(n - 2);
}

func main() {
    // 局部变量
    var i = 0;

    // while 循环 + break
    while (i < 10) {
        if (i == 5) { break; }
        println toString(fib(i));
        i = i + 1;
    }

    // 数组
    var arr = array(5, 0);
    arr[0] = 100;
    println toString(arr[0]);

    // 字符串
    var s = "Hello, " + "World!";
    println s;

    // 从 stdin 读取全部内容
    var input = readAll();
    println toString(len(input));

    return 0;
}
```

### 类型

- `int`：64 位整数
- `string`：字符串
- `array`：数组（通过 `array(size, init)` 创建）
- `nil`：空值

### 运算符

算术：`+ - * / %`
比较：`== != < > <= >=`
逻辑：`&& || !`（注意：不做短路求值，使用嵌套 if 避免类型错误）

## require 模块系统

minilang 支持模块加载。模块是位于 `syslib/` 目录（或脚本所在目录）的 `.mil` 文件。

**搜索顺序**：默认先在脚本所在目录查找，找不到再在 `syslib/` 目录查找。可用 `in cwd` 或 `in syslib` 强制指定。

```minilang
// 加载整个模块，通过命名空间访问
require math;
println toString(math.cos(60));   // 501 (cos 60° × 1000)
println toString(math.fib(10));   // 55

// 选择性导入单个函数，直接调用
require cos from math;
println toString(cos(0));         // 1000

// 选择性导入多个函数
require cos, sin from math;
println toString(sin(90));        // 1000

// 指定搜索位置（有冲突时）
require cos from math in syslib;  // 只从 syslib 加载
require double from local in cwd; // 只从当前目录加载

// require 也可以写在 REPL 里
```

### 内置模块

- `syslib/math.mil`：`abs, min, max, clamp, pow, gcd, lcm, isEven, isOdd, sqrt, factorial, fib, cos, sin, pi`（三角函数按角度制，返回值放大 1000 倍）
- `syslib/string.mil`：`isEmpty, startsWith, endsWith, contains, repeat, countChar, reverse, splitFirst`

## REPL

```bash
$ ./minilang repl
minilang REPL (type 'quit' to exit)
mil> 1 + 2
3
mil> var x = 10;
(defined)
mil> x * 3
30
mil> func sq(n) { return n * n; }
(defined)
mil> sq(7)
49
mil> require math;
(defined)
mil> math.fib(8)
21
mil> quit
```

- 输入表达式自动求值并打印
- `func`/`var`/`require` 声明会跨行保留
- 支持多行块输入（花括号未闭合时自动续行）

## 自举验证

自举编译器 `compiler.mil` 是用 minilang 语言实现的完整编译器（词法分析、递归下降解析、字节码生成、文本输出）。

验证流程：
1. **Boot 编译**：C 实现的 `minilang` 编译 `compiler.mil`，输出文本字节码 A
2. **自举编译**：将 `compiler.mil` 源码通过 stdin 喂给在 VM 上运行的 `compiler.mil`，输出文本字节码 B
3. **对比**：A 和 B 必须逐字节相同

运行验证：

```bash
./bootstrap_test.sh
```

预期输出：
```
SUCCESS: Boot and self-hosted bytecode are IDENTICAL!
```
## 纯 mil 实现的 VM
`vm.mil` 是用 minilang 语言实现的完整栈式虚拟机，支持加载文本格式字节码并执行，与 C 实现的 VM 行为完全一致。
```bash
# 编译程序为文本字节码
./minilang dump-text tests/hello.mil > /tmp/hello.bc
# 用 mil VM 运行字节码
./minilang run vm.mil /tmp/hello.bc
# 从 stdin 读取字节码
./minilang dump-text tests/hello.mil | ./minilang run vm.mil
# 完整自举链路：boot 编译 compiler.mil -> mil VM 运行 -> 编译 compiler.mil
./minilang dump-text compiler.mil > /tmp/compiler.bc
./minilang run vm.mil /tmp/compiler.bc dump-text compiler.mil
```

## 完整自举架构

所有 C 源文件均有对应的 minilang 实现，形成完整自举工具链：

| C 源文件 | mil 实现 | 功能 |
|----------|----------|------|
| lexer.c | compiler.mil | 词法分析 |
| parser.c | compiler.mil | 语法解析 + require 模块系统 |
| bytecode.c | compiler.mil | AST → 字节码编译 |
| vm.c | vm.mil | 栈式虚拟机 |
| value.c | vm.mil | 值类型与运算 |
| runtime.c | vm.mil | 内置函数运行时 |
| llvm_gen.c | llvm_gen.mil | AST → LLVM IR 生成 |
| milc_io.c | milc_io.mil | 字节码序列化（文本格式） |
| main.c | main.mil | 统一 CLI 入口 |

仅需 boot 编译器将 `main.mil` 编译为字节码，再由 `vm.mil` 执行，即可脱离所有 C 代码独立运行完整工具链。

### main.mil 统一入口

`main.mil` 整合了编译器、VM 和 LLVM 生成器，提供与 C `main.c` 一致的 CLI：

```bash
# 编译并运行程序
./minilang run main.mil run tests/hello.mil

# 输出文本字节码
./minilang run main.mil dump-text tests/hello.mil

# 输出 LLVM IR
./minilang run main.mil llvm tests/hello.mil

# 人类可读字节码反汇编（与 boot bytecode 输出逐字节一致）
./minilang run main.mil bytecode tests/hello.mil

# 编译为 .milc 字节码文件（文本格式）
./minilang run main.mil build -b tests/hello.mil

# 编译为原生可执行文件（LLVM IR + ir_compile.py + gcc）
./minilang run main.mil build -e tests/hello.mil

# 交互式 REPL 与自举自检
./minilang run main.mil repl
./minilang run main.mil self-test
```

### 完整自举链路验证

```bash
# 1. boot 编译 main.mil（含 compiler/vm/llvm_gen 全部模块）为文本字节码
./minilang dump-text main.mil > /tmp/main.bc

# 2. mil VM 运行 main.bc，编译 compiler.mil
./minilang run vm.mil /tmp/main.bc dump-text compiler.mil > /tmp/selfhost.txt

# 3. 与 boot 直接编译对比
./minilang dump-text compiler.mil > /tmp/boot.txt
diff /tmp/boot.txt /tmp/selfhost.txt  # 完全一致
```

## .milc 字节码文件格式

- **boot（C 实现）**：`build -b` 生成二进制字节码文件，以魔数 `!milc`（5 字节）开头。
- **mil 版（main.mil）**：由于 mil 语言本身无二进制写能力，`build -b` 输出文本字节码
  （`MINILANGBC` 格式，与 `dump-text` 相同），仍可被 `vm.mil` 加载运行，功能等价。

```bash
./minilang build -b tests/hello.mil    # boot：生成二进制 tests/hello.milc（魔数 !milc）
./minilang run main.mil build -b tests/hello.mil  # mil 版：生成文本 .milc
./minilang run tests/hello.milc        # 直接运行字节码
```

## 项目结构

```
minilang/
├── minilang.h        # 公共头文件（值类型、AST、字节码、VM、函数声明）
├── value.c           # 值类型与运算
├── lexer.c           # 词法分析器
├── parser.c          # 递归下降解析器（含 require 模块系统）
├── bytecode.c        # AST → 字节码编译器
├── vm.c              # 栈式虚拟机
├── llvm_gen.c        # AST → LLVM IR 生成器
├── milc_io.c         # .milc 字节码序列化/反序列化
├── runtime.c         # LLVM 后端 C 运行时
├── main.c            # CLI 入口（run/bytecode/llvm/build/repl/self-test）
├── compiler.mil      # 自举编译器（minilang 语言实现，对应 lexer/parser/bytecode.c）
├── vm.mil            # 纯 mil 实现的虚拟机（对应 vm.c/value.c/runtime.c）
├── llvm_gen.mil      # 纯 mil 实现的 LLVM IR 生成器（对应 llvm_gen.c）
├── milc_io.mil       # 纯 mil 实现的字节码序列化（对应 milc_io.c，文本格式）
├── main.mil          # 纯 mil 实现的统一 CLI 入口（对应 main.c）
├── syslib/           # 内置模块库
│   ├── math.mil      # 整数数学库
│   └── string.mil    # 字符串工具库
├── minilang.lsh      # LSH 语法高亮定义（microsoft/edit 格式）
├── requirements.txt  # Python 依赖（llvmlite）
├── ir_compile.py     # LLVM IR → .o 编译脚本（llvmlite）
├── bootstrap_test.sh # 自举验证脚本
├── Makefile          # 构建文件
└── tests/            # 测试程序
    ├── hello.mil
    ├── fib.mil
    ├── array_test.mil
    ├── require_test.mil
    └── require_path.mil
```

## 字节码格式

每条指令 3 个整数（op, op1, op2），跳转目标为指令序号。

文本格式（`dump-text`）中字符串常量的换行、制表符、回车、反斜杠会被转义（`\n` `\t` `\r` `\\`），确保每行一条记录：
```
MINILANGBC
<常量数>
<type> <value>     # type: 0=int, 1=string（已转义）
...
<函数数>
<name> <address> <params> <locals>
...
<指令数>
<op> <op1> <op2>
...
```

## 设计说明

- **VM 栈管理**：OP_STORE/OP_STORE_GLOBAL/OP_PRINT/OP_PRINTLN 均弹出栈顶值，确保语句级栈平衡
- **break 实现**：循环进入时记录 break 位置栈起点，退出时回填所有 break 跳转地址，嵌套循环通过 loop_stack 隔离
- **全局变量**：顶层 var 声明收集为全局变量，在 init 段初始化（地址 0 为 JMP 到 init 段）
- **模块系统**：require 在解析阶段加载模块源码，函数以 `模块名.函数名` 命名并注册，模块内部互调也加上前缀；别名（`require f from m`）建立 `f` → `m.f` 映射，字节码和 LLVM 后端统一解析
- **自举确定性**：boot 编译器和自举编译器使用相同的字节码编码规则，确保输出一致
