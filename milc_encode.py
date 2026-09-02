#!/usr/bin/env python3
"""milc_encode.py - Convert full text bytecode (with globals) to binary .milc format.

Binary format matches boot's program_write_milc (magic "!milc"):
  "!milc" (5 bytes)
  int32 const_count
  for each const: int8 type; int: int64; string: int32 len + bytes; else: int64 0
  int32 func_count
  for each func: int32 namelen + name, int32 address, int32 param_count, int32 local_count
  int32 global_count
  for each: int32 namelen + name
  int32 bc_count
  int32 * bc_count (bytecode)

Usage: python3 milc_encode.py <input.txt> <output.milc>
"""
import sys

def decode_escaped(s):
    result = []
    i = 0
    while i < len(s):
        if s[i] == '\\' and i + 1 < len(s):
            nxt = s[i + 1]
            if nxt == 'n':
                result.append('\n'); i += 2
            elif nxt == 't':
                result.append('\t'); i += 2
            elif nxt == 'r':
                result.append('\r'); i += 2
            elif nxt == '\\':
                result.append('\\'); i += 2
            else:
                result.append(s[i]); i += 1
        else:
            result.append(s[i]); i += 1
    return ''.join(result)

def wr32(f, v):
    f.write(v.to_bytes(4, 'little', signed=True))

def wrstr(f, s):
    b = s.encode('utf-8')
    wr32(f, len(b))
    f.write(b)

def main():
    if len(sys.argv) != 3:
        print("Usage: milc_encode.py <input.txt> <output.milc>", file=sys.stderr)
        sys.exit(1)
    text_path = sys.argv[1]
    bin_path = sys.argv[2]
    with open(text_path, 'r') as tf:
        lines = tf.read().split('\n')
    idx = 0
    if lines[idx] != 'MINILANGBC':
        print(f"Error: expected MINILANGBC header, got '{lines[idx]}'", file=sys.stderr)
        sys.exit(1)
    idx += 1
    with open(bin_path, 'wb') as f:
        f.write(b'!milc')
        # Constants
        const_count = int(lines[idx]); idx += 1
        wr32(f, const_count)
        for _ in range(const_count):
            parts = lines[idx].split(' ', 1); idx += 1
            typ = int(parts[0])
            if typ == 0:  # text type 0 = int -> binary VAL_INT=1
                f.write(bytes([1]))
                val = int(parts[1])
                f.write(val.to_bytes(8, 'little', signed=True))
            elif typ == 1:  # text type 1 = string -> binary VAL_STRING=2
                f.write(bytes([2]))
                s = decode_escaped(parts[1])
                wrstr(f, s)
            else:
                f.write(bytes([0]))  # VAL_NIL
                f.write((0).to_bytes(8, 'little', signed=True))
        # Functions
        func_count = int(lines[idx]); idx += 1
        wr32(f, func_count)
        for _ in range(func_count):
            parts = lines[idx].split(); idx += 1
            name = parts[0]
            addr = int(parts[1])
            params = int(parts[2])
            locals_ = int(parts[3])
            wrstr(f, name)
            wr32(f, addr)
            wr32(f, params)
            wr32(f, locals_)
        # Globals
        global_count = int(lines[idx]); idx += 1
        wr32(f, global_count)
        for _ in range(global_count):
            name = lines[idx]; idx += 1
            wrstr(f, name)
        # Bytecode
        num_instr = int(lines[idx]); idx += 1
        bc_count = num_instr * 3
        wr32(f, bc_count)
        for _ in range(num_instr):
            parts = lines[idx].split(); idx += 1
            op = int(parts[0]); op1 = int(parts[1]); op2 = int(parts[2])
            wr32(f, op); wr32(f, op1); wr32(f, op2)
    print(f"Encoded {bin_path} ({const_count} consts, {func_count} funcs, {global_count} globals, {num_instr} instrs)", file=sys.stderr)

if __name__ == '__main__':
    main()
