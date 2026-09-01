# minilang

一个极简的可自举编程语言，支持双编译后端：字节码 VM 和 LLVM 原生编译。

## 特性

- **C-like 语法**：函数、递归、if/else、while、var 声明、数组、字符串
- **双后端**：
  - 字节码 + 栈式 VM（快速开发、调试）
  - LLVM IR → 原生可执行文件（高性能）
- **可自举**：用 minilang 写的编译器 (`compiler.ml`) 能编译自身，且输出与 C  boot 编译器完全一致
- **无外部依赖**：不使用文件、网络等外部交互（除 console I/O）
- **内置函数**：`len`, `charAt`, `substr`, `toString`, `toInt`, `strcmp`, `array`, `readAll`

## 构建

```bash
make
```

生成 `minilang` 可执行文件（C 实现的 boot 编译器 + VM）。

### LLVM 后端依赖

LLVM 后端使用 Python 的 `llvmlite` 包将 IR 编译为目标文件：

```bash
pip install llvmlite
```

系统 `gcc` 用于最终链接。

## CLI 用法

```bash
# 1. 在 VM 上运行程序
./minilang run tests/hello.ml

# 2. 输出人类可读的字节码反汇编
./minilang bytecode tests/hello.ml

# 3. 输出自举对比用的文本格式字节码
./minilang dump-text tests/hello.ml

# 4. 输出 LLVM IR (.ll 文件)
./minilang llvm tests/hello.ml

# 5. 编译为原生可执行文件 (LLVM 后端)
./minilang build tests/hello.ml
./tests/hello
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

## 自举验证

自举编译器 `compiler.ml` 是用 minilang 语言实现的完整编译器（词法分析、递归下降解析、字节码生成、文本输出）。

验证流程：
1. **Boot 编译**：C 实现的 `minilang` 编译 `compiler.ml`，输出文本字节码 A
2. **自举编译**：将 `compiler.ml` 源码通过 stdin 喂给在 VM 上运行的 `compiler.ml`，输出文本字节码 B
3. **对比**：A 和 B 必须逐字节相同

运行验证：

```bash
./bootstrap_test.sh
```

预期输出：
```
SUCCESS: Boot and self-hosted bytecode are IDENTICAL!
```

## 项目结构

```
minilang/
├── minilang.h        # 公共头文件（值类型、AST、字节码、VM、函数声明）
├── value.c           # 值类型与运算
├── lexer.c           # 词法分析器
├── parser.c          # 递归下降解析器
├── bytecode.c        # AST → 字节码编译器
├── vm.c              # 栈式虚拟机
├── llvm_gen.c        # AST → LLVM IR 生成器
├── runtime.c         # LLVM 后端 C 运行时
├── main.c            # CLI 入口
├── compiler.ml       # 自举编译器（minilang 语言实现）
├── ir_compile.py     # LLVM IR → .o 编译脚本（llvmlite）
├── bootstrap_test.sh # 自举验证脚本
├── Makefile          # 构建文件
└── tests/            # 测试程序
    ├── hello.ml
    ├── fib.ml
    └── array_test.ml
```

## 字节码格式

每条指令 3 个整数（op, op1, op2），跳转目标为指令序号。

文本格式（`dump-text`）：
```
MINILANGBC
<常量数>
<type> <value>     # type: 0=int, 1=string
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
- **自举确定性**：boot 编译器和自举编译器使用相同的字节码编码规则，确保输出一致
