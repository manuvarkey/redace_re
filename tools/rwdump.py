#!/usr/bin/env python3
"""Dump the RenderWare chunk tree of a .dff/.bsp/.txd file."""
import struct
import sys

CONTAINERS = {0x03, 0x06, 0x07, 0x08, 0x0B, 0x0E, 0x0F, 0x10, 0x14, 0x1A, 0x09, 0x0A, 0x16}
NAMES = {0x01: 'Struct', 0x02: 'String', 0x03: 'Extension', 0x06: 'Texture', 0x07: 'Material',
         0x08: 'MaterialList', 0x09: 'AtomicSector', 0x0A: 'PlaneSector', 0x0B: 'World',
         0x0E: 'FrameList', 0x0F: 'Geometry', 0x10: 'Clump', 0x14: 'Atomic', 0x1A: 'GeometryList',
         0x16: 'TextureDictionary', 0x15: 'TextureNative', 0x50E: 'BinMeshPLG'}


def walk(d, o, end, depth):
    while o + 12 <= end:
        t, size, lib = struct.unpack_from('<3I', d, o)
        body = o + 12
        extra = ''
        if t == 0x02:
            extra = repr(d[body:body + size].split(b'\0')[0])
        elif t == 0x01:
            extra = d[body:body + min(size, 48)].hex(' ', 4)
        print('%s%s 0x%x size=%d lib=0x%x %s' % ('  ' * depth, NAMES.get(t, '?'), t, size, lib, extra))
        if t in CONTAINERS:
            walk(d, body, body + size, depth + 1)
        o = body + size


d = open(sys.argv[1], 'rb').read()
walk(d, 0, len(d), 0)
