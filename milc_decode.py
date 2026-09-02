#!/usr/bin/env python3
"""milc_decode.py - Convert binary .milc (magic "!milc") to text MINILANGBC format.

Output format matches boot's dump_bytecode_text (no globals section):
  MINILANGBC
  <const_count>
  <type: 0=int, 1=string> <value>
  ...
  <func_count>
  <name> <address> <param_count> <local_count>
  ...
  <num_instr>
  <op> <op1> <op2>
  ...

Usage: python3 milc_decode.py <input.milc> <output.txt>
"""
import sys

def escape_string(s):
    r = []
    for ch in s:
        o = ord(ch)
        if o == 92:
            r.append('\\\\')
        elif o == 10:
            r.append('\\n')
        elif o == 9:
            r.append('\\t')
        elif o == 13:
            r.append('\\r')
        elif 32 <= o < 127:
            r.append(ch)
        else:
            r.append('\\x%02x' % o)
    return ''.join(r)

def rd32(f):
    return int.from_bytes(f.read(4), 'little', signed=True)

def rdstr(f):
    n = rd32(f)
    return f.read(n).decode('utf-8')

def main():
    if len(sys.argv) != 3:
        print("Usage: milc_decode.py <input.milc> <output.txt>", file=sys.stderr)
        sys.exit(1)
    with open(sys.argv[1], 'rb') as f:
        magic = f.read(5)
        if magic != b'!milc':
            print(f"Error: not a .milc file (magic={magic})", file=sys.stderr)
            sys.exit(1)
        lines = ['MINILANGBC']
        const_count = rd32(f)
        lines.append(str(const_count))
        for _ in range(const_count):
            t = f.read(1)[0]
            if t == 1:  # VAL_INT
                val = int.from_bytes(f.read(8), 'little', signed=True)
                lines.append(f"0 {val}")
            elif t == 2:  # VAL_STRING
                s = rdstr(f)
                lines.append(f"1 {escape_string(s)}")
            else:
                f.read(8)  # skip
                lines.append("0 0")
        func_count = rd32(f)
        lines.append(str(func_count))
        for _ in range(func_count):
            name = rdstr(f)
            addr = rd32(f)
            params = rd32(f)
            locals_ = rd32(f)
            lines.append(f"{name} {addr} {params} {locals_}")
        global_count = rd32(f)
        for _ in range(global_count):
            rdstr(f)  # skip global names (text format has no globals)
        num_instr = rd32(f) // 3
        lines.append(str(num_instr))
        for _ in range(num_instr):
            op = rd32(f)
            op1 = rd32(f)
            op2 = rd32(f)
            lines.append(f"{op} {op1} {op2}")
    with open(sys.argv[2], 'w') as f:
        f.write('\n'.join(lines) + '\n')
    print(f"Decoded {sys.argv[1]} -> {sys.argv[2]} ({const_count} consts, {func_count} funcs, {num_instr} instrs)", file=sys.stderr)

if __name__ == '__main__':
    main()
