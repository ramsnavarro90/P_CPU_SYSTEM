#!/usr/bin/env python3
# bin2hex.py — Convert raw binary to a hex file for $readmemh / flash model
#
# Usage:
#   python3 bin2hex.py firmware.bin firmware.hex          # 32-bit words (ROM)
#   python3 bin2hex.py app.bin flash.hex --flash          # bytes + boot header
#
# Flash image layout (all little-endian):
#   0x00  magic     0xB007F1A5
#   0x04  length    payload length in bytes (padded to a multiple of 4)
#   0x08  checksum  sum of all payload bytes, modulo 2^32
#   0x0C  payload   application image (linked at 0x8000_0000)

import sys
import struct

MAGIC = 0xB007F1A5

def read_bin(path: str) -> bytes:
    with open(path, 'rb') as f:
        data = f.read()
    remainder = len(data) % 4
    if remainder:
        data += b'\x00' * (4 - remainder)
    return data

def write_words(data: bytes, dst: str) -> None:
    with open(dst, 'w') as f:
        for i in range(0, len(data), 4):
            word = struct.unpack('<I', data[i:i+4])[0]
            f.write(f'{word:08x}\n')
    print(f'Converted {len(data)} bytes -> {len(data)//4} words -> {dst}')

def write_flash(data: bytes, dst: str) -> None:
    header = struct.pack('<III', MAGIC, len(data), sum(data) & 0xFFFFFFFF)
    image = header + data
    with open(dst, 'w') as f:
        for b in image:
            f.write(f'{b:02x}\n')
    print(f'Flash image: {len(data)} payload bytes (+12 header) -> {dst}')

if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    flash_mode = '--flash' in sys.argv[1:]
    if len(args) != 2:
        print(f'Usage: {sys.argv[0]} <input.bin> <output.hex> [--flash]')
        sys.exit(1)
    payload = read_bin(args[0])
    if flash_mode:
        write_flash(payload, args[1])
    else:
        write_words(payload, args[1])