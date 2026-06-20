#!/usr/bin/env python3
"""build_bootdisk.py: assemble the magic-sword bootloader and wrap it into FDS disk images.

Outputs (in build/):
  boot.fds         the standalone bootloader disk (SHIP this; it contains NO copyrighted content; the
                   user supplies their own Zelda disk). Boot it, then swap in your Zelda disk.
  zelda-play.fds   bootloader + your original Zelda A/B in ONE multi-side image, so a single emulator
                     process can auto-boot the bootloader and swap to Zelda. LOCAL test artifact only
                     (bundles Zelda); written only if ./original.fds is present, and never distributed.

Run from anywhere; paths resolve relative to this file's directory (the repo root).
"""
import os
import subprocess
import sys

REPO = os.path.dirname(os.path.abspath(__file__))
ASM6F = os.path.join(REPO, "asm6f", "asm6f")
SIDE = 65500


def build_side(disk_info_56, files, boot_count):
    """Assemble one FDS disk side from a 56-byte disk-info block + a list of files. `boot_count` is the
    block-2 'file amount' the BIOS reads at boot, passed explicitly (not len(files)) so the license-
    bypass disk can INFLATE it past the real total."""
    out = bytearray(disk_info_56)                 # block 1
    out += bytes([0x02, boot_count])              # block 2 (file-amount)
    for f in files:
        name = f["name"].encode().ljust(8, b"\xff")[:8]
        out += bytes([0x03, f["num"], f["id"]]) + name + bytes([
            f["load"] & 0xFF, (f["load"] >> 8) & 0xFF,
            len(f["data"]) & 0xFF, (len(f["data"]) >> 8) & 0xFF, f["kind"]])   # block 3 header
        out += bytes([0x04]) + f["data"]          # block 4 data
    assert len(out) <= SIDE, f"side overflow: {len(out)} > {SIDE}"
    return bytes(out) + bytes(SIDE - len(out))


def homebrew_disk_info(boot_count):
    """A HOMEBREW FDS disk-info block (56 B) carrying NO copyrighted game content, so the shippable boot
    disk reproduces none of Zelda's copyrighted data. We keep only the required FDS format magic
    (mandatory: the BIOS won't recognize a disk without it; every homebrew FDS title includes it) plus
    neutral header fields, modeled on bbbradsmith's NES-ca65-example FDS template. There is NO license
    ('KYODAKU') file and no game graphics: the bypass boot (below) seizes control via a false NMI before
    the BIOS reaches its copyright check, so none of that data is present. `boot_count` is the boot-read
    file count, set ONE past the real total so the BIOS keeps seeking a nonexistent extra file; that
    seek is the delay during which the armed NMI fires."""
    di = bytearray(56)
    di[0x00] = 0x01
    di[0x01:0x0F] = b"*NINTENDO-HVC*"          # FDS format magic (required to boot; not game content)
    di[0x0F] = 0x00                            # manufacturer: unlicensed / homebrew
    di[0x10:0x13] = b"MAG"                      # game name (3 chars): "MAGic sword"
    di[0x13] = 0x20                            # disk/game type: normal
    di[0x19] = boot_count                      # boot-read file count, INFLATED by 1 (the bypass seek)
    di[0x1A:0x1F] = b"\xff" * 5
    di[0x1F:0x22] = bytes((0x92, 0x04, 0x17))  # placeholder manufacture date (BCD), neutral
    di[0x22] = 0x49                            # country
    di[0x23:0x2C] = bytes((0x61, 0, 0, 0x02, 0, 0, 0, 0, 0))
    di[0x2C:0x2F] = bytes((0x92, 0x04, 0x17))  # placeholder rewrite date
    di[0x2F:0x31] = bytes((0x00, 0x80))
    di[0x33] = 0x07
    return bytes(di)


def asm(name, out_bin):
    r = subprocess.run([ASM6F, name, out_bin], cwd=REPO, capture_output=True, text=True)
    if r.returncode != 0:
        print(f"asm6f FAILED ({name}):\n", r.stdout, r.stderr)
        sys.exit(1)
    return open(out_bin, "rb").read()


def main():
    if not os.path.exists(ASM6F):
        sys.exit("asm6f not found; run ./setup.sh first")

    # 1. patch payload (the magic-sword byte-diff records)
    sys.path.insert(0, REPO)
    import gen_payload
    gen_payload.main()

    # 2. assemble the bootloader -> boot.bin (raw bytes from .org $AF50)
    code = asm("boot.asm", os.path.join(REPO, "boot.bin"))
    print(f"boot.bin: {len(code)} bytes  (loads $AF50-${0xAF50 + len(code) - 1:04X}; gap ends $B3FF, "
          f"{0xB400 - (0xAF50 + len(code))} bytes free)")
    assert 0xAF50 + len(code) <= 0xB400, "bootloader overflows the $AF50-$B3FF gap!"

    # 2b. splash screen: its own boot-disk file at $7000 (free boot-time RAM, overwritten when the
    #     bootloader later loads Zelda, so it costs the $AF50 gap nothing). Generate its ASCII-indexed
    #     CHR font first (splash.asm .incbin's it), then assemble.
    import make_splash_font
    make_splash_font.main()
    splash = asm("splash.asm", os.path.join(REPO, "splash.bin"))
    print(f"splash.bin: {len(splash)} bytes  (loads $7000-${0x7000 + len(splash) - 1:04X})")
    assert 0x7000 + len(splash) <= 0xAF50, "splash file overlaps the bootloader at $AF50!"

    # 3. bootloader disk, LICENSE-FREE (reproduces no copyrighted content). We boot via the standard
    #    homebrew "false reset" (Loopy/bbbradsmith): the LAST file "loads" $90 into PPUCTRL ($2000) to
    #    arm NMI, and the boot file count is inflated by one so the BIOS keeps seeking a nonexistent extra
    #    file; the armed NMI fires during that seek and lands at NMI #3 ($DFFA), which we point at a tiny
    #    "bypass" routine BEFORE the BIOS reaches its copyright check. The bypass redirects NMI #3 to our
    #    real handler, then JMPs DIRECTLY to BootReset.
    #
    #    *** DO NOT JMP ($FFFC) here. *** bbbradsmith's single-disk template uses it to run the BIOS reset
    #    stub for a clean init, but it is WRONG for a TWO-disk loader like ours: the stub RE-ARMS the BIOS's
    #    own disk-boot, so inserting the Zelda disk makes the BIOS boot it NORMALLY (license screen) and our
    #    patch never runs. We KEEP control: jump straight to BootReset, which waits for the swap and then
    #    loads Zelda itself via the BIOS LoadFiles *subroutine* (it returns to us, unlike the reset stub).
    #    The clean drive/BIOS init the stub would have done is replicated MANUALLY in splash.asm instead.
    #
    #    The bypass lives in its OWN file at $6000 (free during the boot-disk load; overwritten when we
    #    later load Zelda), so it costs the $AF50 bootloader gap nothing.
    bypass = bytes([
        0xA9, 0x00, 0x8D, 0x00, 0x20,                          # lda #$00 / sta $2000   -> NMI off
        0xA9, 0x53, 0x8D, 0xFA, 0xDF, 0xA9, 0xAF, 0x8D, 0xFB, 0xDF,  # $DFFA := $AF53 (real NMI = NmiVec)
        0x4C, 0x50, 0xAF,                                      # jmp $AF50 -> BootReset (KEEP control)
    ])
    boot_files = [
        # $DFFA = $6000 (bypass / false-reset entry), $DFFC = $AF50 (BootReset), $DFFE = $AF56 (BootIRQ)
        {"num": 0, "id": 0x00, "name": "BOOTVEC", "load": 0xDFFA,
         "data": bytes([0x00, 0x60, 0x50, 0xAF, 0x56, 0xAF]), "kind": 0},
        {"num": 1, "id": 0x01, "name": "BOOTRST", "load": 0x6000, "data": bypass, "kind": 0},
        {"num": 2, "id": 0x02, "name": "BOOTLDR", "load": 0xAF50, "data": code, "kind": 0},
        {"num": 3, "id": 0x03, "name": "SPLASH", "load": 0x7000, "data": splash, "kind": 0},
        # LAST file: "loading" $90 into PPUCTRL ($2000) arms NMI -> the false reset fires during the seek.
        # It MUST stay last so every other file (incl. the splash) is resident before NMI arms.
        {"num": 4, "id": 0x04, "name": "BOOTNMI", "load": 0x2000, "data": bytes([0x90]), "kind": 0},
    ]
    boot_count = len(boot_files) + 1     # inflate by 1: the BIOS seeks a nonexistent 6th file (the delay)
    boot_side = build_side(homebrew_disk_info(boot_count), boot_files, boot_count)

    os.makedirs(os.path.join(REPO, "build"), exist_ok=True)
    open(os.path.join(REPO, "build", "boot.fds"), "wb").write(boot_side)
    msg = "wrote build/boot.fds (1 side, ship, license-free)"

    # combined play image: our license-free bootloader side + your stock Zelda A/B untouched. LOCAL test
    # only (one emulator can swap between bundled sides); bundles Zelda, so it's never distributed.
    orig = os.path.join(REPO, "original.fds")
    if os.path.exists(orig):
        zelda = open(orig, "rb").read()
        open(os.path.join(REPO, "build", "zelda-play.fds"), "wb").write(boot_side + zelda)
        msg += " and build/zelda-play.fds (boot + your Zelda A/B, local test only)"
    else:
        msg += " (no ./original.fds -> skipped zelda-play.fds; drop your Zelda disk image there to test)"
    print(msg)


if __name__ == "__main__":
    main()
