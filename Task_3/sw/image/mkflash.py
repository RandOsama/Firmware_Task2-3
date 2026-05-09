#!/usr/bin/env python3
import sys
import struct
import zlib

BOOT_MAGIC = 0xB007C0DE

bin_path = sys.argv[1]
hex_path = sys.argv[2]

with open(bin_path, 'rb') as f:
    app = f.read()

size = len(app)
crc  = zlib.crc32(app) & 0xFFFFFFFF

header = struct.pack('<III', BOOT_MAGIC, size, crc)
image  = header + app

with open(hex_path, 'w') as f:
    for byte in image:
        f.write(f'{byte:02X}\n')

print(f"Magic : 0x{BOOT_MAGIC:08X}")
print(f"Size  : {size} bytes")
print(f"CRC32 : 0x{crc:08X}")
print(f"Output: {hex_path}")
