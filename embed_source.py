#!/usr/bin/env python3
"""Embed source code as SELF_SRC string into a minilang compiler file.
Usage: embed_source.py <compiler.ml> <source_to_embed> <output.ml>
"""
import sys

def escape_string(s):
    """Escape a string for minilang string literal."""
    result = []
    for ch in s:
        if ch == '\\':
            result.append('\\\\')
        elif ch == '"':
            result.append('\\"')
        elif ch == '\n':
            result.append('\\n')
        elif ch == '\t':
            result.append('\\t')
        elif ord(ch) < 32 or ord(ch) >= 127:
            result.append('\\%03d' % ord(ch))
        else:
            result.append(ch)
    return ''.join(result)

def main():
    if len(sys.argv) != 4:
        print("Usage: embed_source.py <compiler.ml> <source_to_embed> <output.ml>", file=sys.stderr)
        sys.exit(1)

    with open(sys.argv[1], 'r') as f:
        compiler_src = f.read()

    with open(sys.argv[2], 'r') as f:
        source_to_embed = f.read()

    escaped = escape_string(source_to_embed)

    # Replace the SELF_SRC line in the compiler
    lines = compiler_src.split('\n')
    output_lines = []
    for line in lines:
        if line.strip().startswith('var SELF_SRC'):
            output_lines.append('var SELF_SRC = "' + escaped + '";')
        else:
            output_lines.append(line)

    with open(sys.argv[3], 'w') as f:
        f.write('\n'.join(output_lines))

    print(f"Generated {sys.argv[3]} with embedded source ({len(source_to_embed)} bytes)")

if __name__ == '__main__':
    main()
