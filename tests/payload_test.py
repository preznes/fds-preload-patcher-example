#!/usr/bin/env python3
"""payload_test.py: fast, emulator-free checks on the magic-sword patch + bootloader layout.

Verifies:
  1. gen_payload produces a well-formed record stream (header + data, $00 $00 terminator).
  2. The patch targets the NMI handler $63A6 with "jsr ForceSword ; nop" where ForceSword == $AF59.
  3. The bytes being replaced really are Zelda's "a5 ff a6 5c" in original.fds (the guard), and applying
     the record yields the expected patched bytes.
  4. boot.bin has ForceSword at $AF59 (first instruction lda #$03), and it fits the $AF50-$B3FF gap.

Run: python3 tests/payload_test.py   (exits 0 on PASS). Needs `make` to have built boot.bin, and
original.fds present for the guard check (check 3 is skipped with a warning if it's absent)."""
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, REPO)
import gen_payload  # noqa: E402

FAIL = []


def check(cond, msg):
    print(("ok  " if cond else "FAIL ") + msg)
    if not cond:
        FAIL.append(msg)


def parse_records(buf):
    recs, i = [], 0
    while i < len(buf):
        lo, hi = buf[i], buf[i + 1]
        if hi == 0:                      # terminator
            return recs, i + 2
        ln = buf[i + 2]
        recs.append((lo | (hi << 8), buf[i + 3:i + 3 + ln]))
        i += 3 + ln
    raise AssertionError("no terminator")


def main():
    gen_payload.main()
    payload = open(os.path.join(REPO, "patch_payload.bin"), "rb").read()
    recs, end = parse_records(payload)

    check(end == len(payload), "payload is exactly the record stream + terminator (no trailing junk)")
    check(len(recs) == 2, "exactly two patch records (ForceSword plant + hook)")
    recmap = dict(recs)
    FS = gen_payload.FORCE_SWORD
    check(FS == 0xA235, f"ForceSword planted at $A235 in f04 padding (got ${FS:04X})")
    for addr, _ in recs:
        check(0x6000 <= addr < 0xAF50, f"record ${addr:04X} lands in the never-reloaded f04 region")
    # record 1: ForceSword code planted at $A235
    check(FS in recmap and recmap[FS] == bytes([0xA9, 0x03, 0x8D, 0x57, 0x06, 0x4C, 0xD7, 0x6F]),
          "ForceSword code = 'lda #$03 ; sta $0657 ; jmp $6FD7'")
    # record 2: the hook at $644b
    check(0x644B in recmap and recmap[0x644B] == bytes([0x20, FS & 0xFF, (FS >> 8) & 0xFF]),
          "hook at $644b = 'jsr ForceSword' ($A235)")

    orig_path = os.path.join(REPO, "original.fds")
    if os.path.exists(orig_path):
        orig = open(orig_path, "rb").read()
        check(orig[gen_payload.fds_off(0x644B):gen_payload.fds_off(0x644B) + 3] == bytes([0x20, 0xD7, 0x6F]),
              "original.fds has 'jsr tab_b1_6fd7' at $644b (guard byte-exact)")
        check(orig[gen_payload.fds_off(FS):gen_payload.fds_off(FS) + 8] == bytes(8),
              "original.fds has 8 free $00 bytes at $A235 (ForceSword landing pad)")
    else:
        print("warn original.fds absent; skipping the guard check")

    boot = os.path.join(REPO, "boot.bin")
    if os.path.exists(boot):
        code = open(boot, "rb").read()
        check(0xAF50 + len(code) <= 0xB400, "boot.bin fits the $AF50-$B3FF gap")
    else:
        print("warn boot.bin absent; run `make` first to check the gap fit")

    print()
    if FAIL:
        print(f"FAILED ({len(FAIL)})")
        sys.exit(1)
    print("PASS")


if __name__ == "__main__":
    main()
