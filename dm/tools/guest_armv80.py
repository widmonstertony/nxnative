"""Lower guest instructions unavailable on the original ARMv8-A iPads."""

import re
import struct

from nso_asm import ADDI, B, BEQ, CBNZW, LDP_POST, STP_PRE

AUT_EPILOGUE = {
    0xD65F0BFF: 0xD50323BF,  # RETAA -> AUTIASP; RET
    0xD65F0FFF: 0xD50323FF,  # RETAB -> AUTIBSP; RET
}
RET = 0xD65F03C0
CLREX = 0xD5033F5F
RETURN_PATTERN = re.compile(rb"(?=\xff[\x0b\x0f]\x5f\xd6)")
# Byte patterns narrow the scan. Validate fixed bits before decoding an opcode.
ATOMIC_PATTERN = re.compile(rb"(?=(?s:..)[\x20-\xff][\x08\x38\x48\x78\x88\xb8\xc8\xf8])")


def words(image, ranges, pattern):
    for start, end in ranges:
        for candidate in pattern.finditer(image, start, end):
            offset = candidate.start()
            if offset % 4 == 0:
                yield offset, struct.unpack_from("<I", image, offset)[0]


def returns(image, ranges):
    """Find aligned combined returns in the rewriter's executable ranges."""
    for offset, word in words(image, ranges, RETURN_PATTERN):
        yield offset, AUT_EPILOGUE[word]


def atomic_kind(word):
    if word & 0x3FA07C00 == 0x08A07C00:
        return "cas"
    if word & 0xBFA07C00 == 0x08207C00:
        return "pair"
    if word & 0x3FFFFC00 == 0x38BFC000:
        return "rcpc"
    if word & 0x3F200C00 == 0x38200000 and (word >> 12 & 15) <= 8:
        return "rmw"
    return None


def atomics(image, ranges):
    """Find the scalar LSE and RCpc instructions emitted by the guest SDK."""
    for offset, word in words(image, ranges, ATOMIC_PATTERN):
        kind = atomic_kind(word)
        if kind:
            yield offset, word, kind


def ldar(word):
    """Strengthen an RCpc acquire load to an acquire load present on ARMv8-A."""
    return (word & 0xC00003FF) | 0x08DFFC00


def move(dst, src, wide):
    return (0xAA0003E0 if wide else 0x2A0003E0) | src << 16 | dst


def eor(dst, left, right, wide):
    return (0xCA000000 if wide else 0x4A000000) | right << 16 | left << 5 | dst


def narrow(reg, size, signed=False):
    return (0x13000000 if signed else 0x53000000) | ((8 << size) - 1) << 10 | reg << 5 | reg


def cbnz(reg, pc, target, wide):
    return CBNZW(reg, pc, target) | (0x80000000 if wide else 0)


def atomic_thunk(word, kind, origin, target, jump=B):
    """Emit an exclusive-load/store loop. Preserve NZCV, LR and non-output registers.

    `jump` can route a long continuation through the rewriter's existing islands.
    """
    size, src, base, dst = word >> 30, word >> 16 & 31, word >> 5 & 31, word & 31
    pair = kind == "pair"
    compare = kind in ("cas", "pair")
    wide = bool(size & 1) if pair else size == 3
    acquire = bool(word & (1 << (22 if compare else 23)))
    release = bool(word & (1 << (15 if compare else 22)))
    op = word >> 12 & 15
    is_minmax = not compare and 4 <= op <= 7

    used = {src, base, dst}
    if pair:
        if src % 2 or dst % 2:
            raise ValueError(f"invalid CASP alignment at {origin:#x}")
        used.update((src + 1, dst + 1))
    scratch = iter(r for r in range(9, 18) if r not in used)
    old, value = next(scratch), next(scratch)
    status, address = next(scratch), next(scratch)
    code = [STP_PRE(old, value, 31, -32), STP_PRE(status, address, 31, -16)]
    # The original SP is also a valid atomic address. The spill area stays
    # below it, outside the guest stack frame.
    if base == 31:
        code.append(ADDI(address, 31, 48))
        base = address
    flags = next(scratch) if is_minmax else None
    if is_minmax:
        code.extend((STP_PRE(flags, 31, 31, -16), 0xD53B4200 | flags))

    pc = lambda: target + 4 * len(code)
    repeat = pc()
    if pair:
        # A store-exclusive validates even the mismatch path, so CASP can
        # never return a pair assembled from two different observations.
        code.append((0xC87F0000 if wide else 0x887F0000) | (int(acquire) << 15) | value << 10 | base << 5 | old)
        code.append(eor(status, old, src, wide))
        code.append(cbnz(status, pc(), pc() + 20, wide))
        code.append(eor(status, value, src + 1, wide))
        code.append(cbnz(status, pc(), pc() + 12, wide))
        store = (0xC8200000 if wide else 0x88200000) | int(release) << 15 | status << 16 | base << 5
        code.append(store | (dst + 1) << 10 | dst)
        code.append(B(pc(), pc() + 8))
        code.append(store | value << 10 | old)
    else:
        code.append(0x085F7C00 | size << 30 | int(acquire) << 15 | base << 5 | old)
        if compare:
            code.append(eor(value, old, src, wide))
            if size < 2:
                code.append(narrow(value, size))
            code.append(cbnz(value, pc(), pc() + 16, wide))
            data = dst
        elif op == 8:  # SWP
            data = src
        else:
            sf = 0x80000000 if wide else 0
            if is_minmax:
                signed = op < 6
                if size < 2:
                    code.extend((move(value, src, False), narrow(value, size, signed)))
                    extend = (4 if signed else 0) + size
                    code.append(0x6B20001F | old << 16 | extend << 13 | value << 5)
                    left, right = value, old
                else:
                    code.append(0x6B00001F | sf | src << 16 | old << 5)
                    left, right = old, src
                # On a tie either operand yields identical low bits.
                lt = 11 if signed else 3
                ge = lt ^ 1
                cond = lt if op & 1 else ge
                code.append(0x1A800000 | sf | right << 16 | cond << 12 | left << 5 | value)
            else:
                # LDADD, LDCLR, LDEOR, LDSET and their ST aliases.
                code.append((0x0B000000, 0x0A200000, 0x4A000000, 0x2A000000)[op]
                            | sf | src << 16 | old << 5 | value)
            data = value
        code.append(0x08007C00 | size << 30 | int(release) << 15 | status << 16 | base << 5 | data)
    code.append(CBNZW(status, pc(), repeat))
    if kind == "cas":
        code.append(B(pc(), pc() + 8))
        code.append(CLREX)

    if pair:
        code.extend((move(src, old, wide), move(src + 1, value, wide)))
    else:
        code.append(move(src if compare else dst, old, wide))
    if is_minmax:
        code.extend((0xD51B4200 | flags, LDP_POST(flags, 31, 31, 16)))
    code.extend((LDP_POST(status, address, 31, 16), LDP_POST(old, value, 31, 32)))
    code.append(jump(pc(), origin + 4))
    return code
