#!/usr/bin/env python3
# bin2hex.py — Convert raw binary to 32-bit word hex file for $readmemh
#
# Usage: python3 bin2hex.py firmware.bin firmware.hex
#
# $readmemh expects one 32-bit word per line, no prefix.
# Words are little-endian (matches RISC-V memory layout).

import sys
import struct

def convert(src: str, dst: str) -> None:
    with open(src, 'rb') as f:
        data = f.read()

    # Pad to 4-byte boundary
    remainder = len(data) % 4
    if remainder:
        data += b'\x00' * (4 - remainder)

    with open(dst, 'w') as f:
        for i in range(0, len(data), 4):
            word = struct.unpack('<I', data[i:i+4])[0]
            f.write(f'{word:08x}\n')

    print(f'Converted {len(data)} bytes → {len(data)//4} words → {dst}')

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print(f'Usage: {sys.argv[0]} <input.bin> <output.hex>')
        sys.exit(1)
    convert(sys.argv[1], sys.argv[2])