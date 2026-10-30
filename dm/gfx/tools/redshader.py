"""REDengine Switch shader-cache compression, before GLSLC section parsing.

FZLC has {magic, chunk count}, a reserved table of {offset, packed, raw}
triples, then contiguous zstd frames. Other caches hold {u64 engine key,
u8 codec=1, u32 raw, u32 packed, zstd frame} records followed by lookup data.
Only section-validated GLSLC outputs become shaders in shader_split.
"""
import re
import struct

ZSTD = bytes.fromhex('28b52ffd')


def unpack_frame(data, size, zstd):
    decoder = zstd.ZstdDecompressor()
    result = decoder.decompress(data, max_length=size + 1)
    if len(result) != size or not decoder.eof or decoder.unused_data:
        raise ValueError('REDengine shader frame size or boundary mismatch')
    return result


def fzlc(data, zstd):
    if len(data) < 20 or data[:4] != b'FZLC':
        raise ValueError('Invalid FZLC header')
    count = struct.unpack_from('<I', data, 4)[0]
    if not 0 < count <= (len(data) - 8) // 12:
        raise ValueError('Invalid FZLC chunk count')
    rows = [struct.unpack_from('<III', data, 8 + i * 12) for i in range(count)]
    start = rows[0][0]
    if not 8 + count * 12 <= start <= len(data) or any(data[8 + count * 12:start]):
        raise ValueError('Invalid FZLC reserved table')
    end = start
    for offset, packed, raw in rows:
        if offset != end or not 0 < packed <= len(data) - offset or not 0 < raw <= 1 << 20:
            raise ValueError('Invalid FZLC chunk range')
        end = offset + packed
    if end != len(data):
        raise ValueError('FZLC trailing or missing data')
    return b''.join(unpack_frame(data[o:o + n], raw, zstd) for o, n, raw in rows)


def records(data, zstd):
    """Decode every bounded hash/codec/length record, ignoring its lookup table.

    Scan frame signatures because the lookup table is not a shader record.
    Validate both lengths, codec and exact frame consumption before returning
    anything; callers validate the decoded GLSLC container independently.
    """
    result, end = [], 0
    for match in re.finditer(re.escape(ZSTD), data):
        at = match.start()
        if at < end:  # a coincidental magic within a frame already consumed
            continue
        header = at - 17
        if header < 0:
            raise ValueError('Missing REDengine shader record header')
        _, codec, raw, packed = struct.unpack_from('<QBII', data, header)
        if codec != 1 or not 0 < raw <= 64 << 20 or not 0 < packed <= len(data) - at:
            raise ValueError('Invalid REDengine shader record range or codec')
        result.append((header, unpack_frame(data[at:at + packed], raw, zstd)))
        end = at + packed
    if not result:
        raise ValueError('No REDengine shader records')
    return result
