# Change Log

本文件记录 minilang **编译器/语言本体**的变更。编辑器扩展的变更见 `minilang-vscode` 仓库的 CHANGELOG。

## v1.0.0

首个完整版本：boot（C 实现的编译器 + VM）与 mil 自举实现逐字节一致，LLVM 原生后端可用。

### 语言与工具链

- **`.milc` 二进制字节码**：可编译为二进制字节码文件（魔数 `!milc`）并直接加载运行；
  mil 侧用 `readFileBytes` / `writeFileBytes` / `chr` 直接读写二进制，不再依赖外部 Python 脚本
- **CLI**：`run`、`bytecode`、`dump-text`、`llvm`、`build -b` / `build -e`、`repl`、`self-test`；
  其中 `bytecode` 与 `dump-text` 现在同时接受 `.mil` 源码和 `.milc` 字节码文件
- **模块系统**：`require` 在解析阶段加载模块源码，函数以 `模块名.函数名` 命名并注册；
  别名（`require f from m`）建立 `f` → `m.f` 映射；字节码与 LLVM 后端统一解析
- **标准库 `syslib/`**：`math`、`string`、`list`、`sort`、`json`、`io`、`rand`、`word`

### 修复

- **标准库路径不再随工作目录漂移**：`syslib/` 按可执行文件所在目录定位
  （Linux 走 `/proc/self/exe`，macOS 走 `_NSGetExecutablePath`，最后回退到 argv[0] 并沿 PATH 查找），
  脚本目录取绝对路径。此前在 macOS 上会退化成相对 cwd 的 `syslib`，导致
  `cannot find module 'math' (searched syslib)`
- **`bytecode` 反汇编的助记符表补全**：新增的 `ARGC`/`ARGV`/`READFILE`/`READLINE`/
  `READFILEBYTES`/`WRITEFILEBYTES`/`CHR` 曾一律显示为 `???`，boot 与 mil 两侧都已补齐
- `llvm_gen.mil` 的 IR 分块缓冲由固定 512 槽改为按需倍增，编译 `main.mil` 不再越界
- `array(0, x)` 的长度在 boot 与 mil 两侧统一为 0
- `string.reverse` 修正：`r + charAt(s,i)` 把字符码当数字拼接，反转 "abc" 得到 "999897"
- `sort.insert` 修正：内层循环用 `j = -1` 退出导致插入位置丢失

### 已知限制

- 数字类型为 int64：JSON 中的小数会被截断，指数被忽略
- `json.mil` 用带标签的二元组表示值（无哈希类型）
- 尚无调试器
