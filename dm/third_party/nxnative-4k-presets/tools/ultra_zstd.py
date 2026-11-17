"""zstd as the games use it: plain frames (Mario Kart World's .sarc.zs) and frames compressed with a dictionary from the game's own Pack/ZsDic.pack.zs (Ocarina of Time,
as Tears of the Kingdom: zs.zsdic for most .zs files, pack.zsdic for .pack.zs, bcett.byml.zsdic for .bcett.byml.zs, bkprb.zsdic for .bkprb.zs).

compress() writes a frame with the original's frame parameters (content size present or not, checksum, dictionary ID, window size no larger than the original's), so a
game decoder that accepted the original accepts it the same way; frame_info() reports both to compare. The compressed bytes differ from Nintendo's (another encoder),
which no decoder checks.
"""
import struct
import zstandard


def frame_info(raw):
    """{content_size, window_size, dict_id, has_checksum, single_segment} of the first frame"""
    if raw[:4] != b'\x28\xb5\x2f\xfd': raise ValueError(f'not a zstd frame (magic {raw[:4].hex()})')
    p = zstandard.get_frame_parameters(raw)
    return {'content_size': p.content_size, 'window_size': p.window_size, 'dict_id': p.dict_id, 'has_checksum': bool(p.has_checksum), 'single_segment': bool(raw[4] >> 5 & 1)}


def dict_for(path, dicts):
    """The dictionary a RomFS path is compressed with in a game that has dicts ({zsdic name: bytes}), or None"""
    if not dicts: return None
    for suffix, name in (('.pack.zs', 'pack.zsdic'), ('.bcett.byml.zs', 'bcett.byml.zsdic'), ('.bkprb.zs', 'bkprb.zsdic')):
        if path.endswith(suffix) and name in dicts: return dicts[name]
    return dicts.get('zs.zsdic')


def decompress(raw, zdict=None):
    info = frame_info(raw)
    d = zstandard.ZstdDecompressor(dict_data=zstandard.ZstdCompressionDict(zdict, dict_type=zstandard.DICT_TYPE_AUTO) if zdict else None)
    out = d.decompress(raw, max_output_size=max(info['content_size'] if info['content_size'] > 0 else 0, 1 << 28))
    if info['dict_id'] and not zdict: raise ValueError(f'frame needs dictionary {info["dict_id"]}')
    return out


def compress(data, like, zdict=None, level=19):
    """data compressed with the frame parameters of the original frame like"""
    info = frame_info(like)
    wlog = max(10, min(31, info['window_size'].bit_length() - 1)) if info['window_size'] else None
    cdict = zstandard.ZstdCompressionDict(zdict, dict_type=zstandard.DICT_TYPE_AUTO) if zdict else None
    if cdict is not None: cdict.precompute_compress(level=level)
    params = zstandard.ZstdCompressionParameters.from_level(level, source_size=len(data), dict_size=len(zdict) if zdict else 0,
                                                            window_log=wlog if (wlog and not info['single_segment']) else 0,
                                                            write_checksum=info['has_checksum'], write_content_size=info['content_size'] > 0,
                                                            write_dict_id=bool(info['dict_id']))
    out = zstandard.ZstdCompressor(compression_params=params, dict_data=cdict).compress(data)
    got = frame_info(out)
    if got['dict_id'] != info['dict_id'] or got['has_checksum'] != info['has_checksum'] or (got['content_size'] > 0) != (info['content_size'] > 0):
        raise ValueError(f'frame parameters differ from the original: {got} vs {info}')
    if not info['single_segment'] and info['window_size'] and got['window_size'] > info['window_size']:
        raise ValueError(f'window {got["window_size"]} larger than the original {info["window_size"]}')
    return out
