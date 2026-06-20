#!/usr/bin/env python3
"""gen_payload.py: emit patch_payload.bin, the byte-diff the bootloader splices into the freshly-loaded
Zelda code so Link starts with the Magical Sword.

Format: a list of records [destLo, destHi, len, data...] terminated by destHi=0 (the bootloader's
ApplyPatches copies each run into RAM). Every record must land in side-A file f04 ($6000-$AF4F in RAM),
the region a Zelda load never re-reads.

THE PATCH (one record): overwrite the UPDATE-mode dispatch call at $644b ("20 d7 6f",
jsr tab_b1_6fd7) with "jsr ForceSword" ("20 59 af"). The ForceSword routine lives in the bootloader
at the FIXED gap address $AF59 (see boot.asm); it sets Items ($0657) = 3, then tail-jumps to the
displaced dispatch ($6fd7), whose rts returns to the NMI. So every active-play frame re-forces the
magical sword. $644b is AFTER the NMI's time-critical PPU section and runs only while IsUpdatingMode!=0
(play/menus, NOT the new-game disk transition GameMode $02), so the world boots cleanly, unlike hooking
the NMI entry $63A6, which delays the PPU writes and fires during the $02 disk op, hanging the boot.

The guard: when ./original.fds is present we VERIFY the bytes we're replacing actually are "20 d7 6f",
so the patch can never silently land on the wrong code (e.g. a different Zelda revision)."""
import os

REPO = os.path.dirname(os.path.abspath(__file__))
F04_OFF, F04_RAM, F04_SIZE = 0x356e, 0x6000, 20304   # side-A f04: .fds offset <-> RAM
FORCE_SWORD = 0xA235                                  # free $00 padding inside f04. MUST live in f04, not
                                                     # the $AF50 bootloader gap: the gap survives the disk
                                                     # load, but the running game reuses it as scratch RAM,
                                                     # so gap-resident code called per-frame gets clobbered
                                                     # mid-boot and hangs. f04 (resident game code) survives.

# ForceSword, planted into f04 padding: set Items ($0657)=3, then tail-jump to the UPDATE-mode dispatch
# ($6fd7) we displaced at the hook site, whose rts returns to the NMI. (lda #3 / sta $0657 / jmp $6fd7)
FORCESWORD_CODE = bytes([0xA9, 0x03, 0x8D, 0x57, 0x06, 0x4C, 0xD7, 0x6F])

# (RAM address, expected original bytes, replacement bytes)
PATCHES = [
    (FORCE_SWORD, bytes(len(FORCESWORD_CODE)), FORCESWORD_CODE),             # plant ForceSword in padding
    (0x644B, bytes([0x20, 0xD7, 0x6F]),
             bytes([0x20, FORCE_SWORD & 0xFF, (FORCE_SWORD >> 8) & 0xFF])),  # jsr tab_b1_6fd7 -> jsr ForceSword
]


def fds_off(ram):
    assert F04_RAM <= ram < F04_RAM + F04_SIZE, f"${ram:04X} is outside side-A f04"
    return F04_OFF + (ram - F04_RAM)


def main():
    orig_path = os.path.join(REPO, "original.fds")
    orig = open(orig_path, "rb").read() if os.path.exists(orig_path) else None

    out = bytearray()
    for ram, old, new in PATCHES:
        assert len(new) == len(old) <= 255
        if orig is not None:
            have = orig[fds_off(ram):fds_off(ram) + len(old)]
            if have != old:
                raise SystemExit(
                    f"GUARD FAILED at ${ram:04X}: expected {old.hex()} but original.fds has {have.hex()}.\n"
                    f"This Zelda image doesn't match the patch; refusing to build a bad disk.")
        out += bytes([ram & 0xFF, (ram >> 8) & 0xFF, len(new)]) + new
    out += bytes([0x00, 0x00])   # terminator (destHi = 0)

    open(os.path.join(REPO, "patch_payload.bin"), "wb").write(out)
    guarded = "verified vs original.fds" if orig is not None else "NOT verified (no original.fds)"
    print(f"patch_payload.bin: {len(out)} bytes, {len(PATCHES)} record(s); {guarded}")


if __name__ == "__main__":
    main()
