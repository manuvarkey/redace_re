#!/usr/bin/env python3
"""Minimal InstallShield 5/6 cabinet extractor (data1.hdr + dataN.cab).

Usage: isextract.py <dir-with-data1.hdr> <output-dir>
"""
import os
import struct
import sys
import zlib

SIG = 0x28635349
FILE_SPLIT, FILE_OBFUSCATED, FILE_COMPRESSED, FILE_INVALID = 1, 2, 4, 8


def u16(b, o): return struct.unpack_from('<H', b, o)[0]
def u32(b, o): return struct.unpack_from('<I', b, o)[0]
def u64(b, o): return struct.unpack_from('<Q', b, o)[0]


def cstr(b, o):
    return b[o:b.index(b'\0', o)].decode('latin-1')


def major_version(v):
    if v >> 24 == 1:
        return (v >> 12) & 0xf
    if v >> 24 in (2, 4):
        m = (v & 0xffff) // 100
        return m or 0
    return 0


def deobfuscate(data, seed=0):
    out = bytearray(data)
    for i, c in enumerate(out):
        t = c ^ 0xd5
        t = ((t >> 2) | (t << 6)) & 0xff
        out[i] = (t - ((seed + i) % 0x47)) & 0xff
    return bytes(out)


class Cabinet:
    def __init__(self, path):
        self.dir = path
        self.hdr = open(os.path.join(path, 'data1.hdr'), 'rb').read()
        sig, ver, _, cdo, _ = struct.unpack_from('<5I', self.hdr, 0)
        assert sig == SIG, 'bad signature'
        self.major = major_version(ver)
        p = cdo
        self.cdo = cdo
        self.ft_off = u32(self.hdr, p + 0x0c)
        self.dir_count = u32(self.hdr, p + 0x1c)
        self.file_count = u32(self.hdr, p + 0x28)
        self.ft_off2 = u32(self.hdr, p + 0x2c)
        base = cdo + self.ft_off
        self.table = [u32(self.hdr, base + 4 * i)
                      for i in range(self.dir_count + self.file_count)]
        self.dirs = [cstr(self.hdr, base + self.table[i])
                     for i in range(self.dir_count)]
        self._vol_cache = {}

    def file(self, i):
        h = self.hdr
        base = self.cdo + self.ft_off
        if self.major <= 5:
            p = base + self.table[self.dir_count + i]
            fd = dict(name_offset=u32(h, p), directory_index=u32(h, p + 4),
                      flags=u16(h, p + 8), expanded_size=u32(h, p + 10),
                      compressed_size=u32(h, p + 14),
                      data_offset=u32(h, p + 0x26), volume=1)
        else:
            p = base + self.ft_off2 + i * 0x57
            fd = dict(flags=u16(h, p), expanded_size=u64(h, p + 2),
                      compressed_size=u64(h, p + 10), data_offset=u64(h, p + 18),
                      name_offset=u32(h, p + 58), directory_index=u16(h, p + 62),
                      volume=u16(h, p + 85))
        fd['name'] = cstr(h, base + fd['name_offset']) if fd['name_offset'] else ''
        fd['dir'] = self.dirs[fd['directory_index']] if fd['directory_index'] < self.dir_count else ''
        return fd

    def volume(self, n):
        if n not in self._vol_cache:
            data = open(os.path.join(self.dir, 'data%d.cab' % n), 'rb').read()
            vh = {}
            if self.major <= 5:
                f = struct.unpack_from('<10I', data, 20)
                vh = dict(first_file_index=f[2], last_file_index=f[3],
                          first_file_offset=f[4], first_file_size_compressed=f[6],
                          last_file_offset=f[7], last_file_size_compressed=f[9])
            else:
                f = struct.unpack_from('<16I', data, 20)
                vh = dict(first_file_index=f[2], last_file_index=f[3],
                          first_file_offset=f[4], first_file_size_compressed=f[8],
                          last_file_offset=f[10], last_file_size_compressed=f[14])
            self._vol_cache[n] = (data, vh)
        return self._vol_cache[n]

    def raw(self, i, fd):
        """Return the stored (compressed) bytes of file i, following volume splits."""
        vol = fd['volume']
        need = fd['compressed_size'] if fd['flags'] & FILE_COMPRESSED else fd['expanded_size']
        out = bytearray()
        data, vh = self.volume(vol)
        if i == vh['last_file_index'] and vh['last_file_offset'] and fd['flags'] & FILE_SPLIT:
            off, size = vh['last_file_offset'], vh['last_file_size_compressed']
        else:
            off, size = fd['data_offset'], need
        while True:
            out += data[off:off + size]
            if len(out) >= need:
                return bytes(out[:need])
            vol += 1
            data, vh = self.volume(vol)
            off, size = vh['first_file_offset'], vh['first_file_size_compressed']

    def extract(self, i, fd):
        raw = self.raw(i, fd)
        if fd['flags'] & FILE_OBFUSCATED:
            raw = deobfuscate(raw)
        if not fd['flags'] & FILE_COMPRESSED:
            return raw
        out = bytearray()
        p = 0
        while p < len(raw) and len(out) < fd['expanded_size']:
            n = u16(raw, p)
            p += 2
            d = zlib.decompressobj(-15)
            out += d.decompress(raw[p:p + n]) + d.flush()
            p += n
        return bytes(out)


def main():
    src, dst = sys.argv[1], sys.argv[2]
    cab = Cabinet(src)
    print('InstallShield major %d: %d dirs, %d files' % (cab.major, cab.dir_count, cab.file_count))
    ok = bad = 0
    for i in range(cab.file_count):
        fd = cab.file(i)
        if fd['flags'] & FILE_INVALID or not fd['name'] or fd['data_offset'] == 0:
            continue
        rel = os.path.normpath(os.path.join(fd['dir'].replace('\\', '/'), fd['name'])).lstrip('/')
        if rel.startswith('..'):
            continue
        out = os.path.join(dst, rel)
        os.makedirs(os.path.dirname(out) or dst, exist_ok=True)
        try:
            data = cab.extract(i, fd)
            assert len(data) == fd['expanded_size'], (len(data), fd['expanded_size'])
            open(out, 'wb').write(data)
            ok += 1
        except Exception as e:
            print('FAIL %s: %r' % (rel, e))
            bad += 1
    print('extracted %d, failed %d' % (ok, bad))


if __name__ == '__main__':
    main()
