# Famicom Disk System Preload Patcher Example

A standalone **example Famicom Disk System bootloader**. It boots from its own tiny,
license-free disk, waits for you to insert an **unmodified** *The Legend of Zelda* disk, loads the
original game into RAM, **patches it in memory at runtime**, and launches the game, so Link **starts with the
Magical Sword**. The original game disk is never written to or modified.

The patch is deliberately trivial (one tiny byte-diff). The point of this repo is the **bootloader
mechanism**: seize control of the FDS before its copyright check, load a *different* disk yourself,
splice changes into the loaded code, and hand off to the game, all from a distributable disk that
contains **no copyrighted content**.

## How it works

The boot disk has no game, no graphics, and **no copyright/license ("KYODAKU") file**. The boot sequence:

1. **Seize control before the copyright check.** It boots with the standard homebrew **"false reset"**,
   as demonstrated in [Brad Smith's FDS license-bypass example](https://github.com/bbbradsmith/NES-ca65-example/tree/fds).
2. **Prompt + wait for the disk swap.** The bootloader shows **"PLEASE LOAD NEXT DISK"**, then resets the
   disk drive and finishes the BIOS init by hand (the false reset skipped it), then waits, polling the
   drive status (`$4032`), for you to remove the boot disk and insert your Zelda disk.
3. **Load Zelda ourselves.** We call the BIOS `LoadFiles` *subroutine* (it loads named files and returns
   to us) to read Zelda side A into RAM (`$6000–$AF4F`).
4. **Patch in RAM.** We copy a small byte-diff over the freshly-loaded code (this is the magic-sword
   change), then install Zelda's real interrupt vectors and `JMP` into Zelda's own reset. The game runs as
   if it had always had the patch, but the disk was never altered.

The bootloader itself lives in the 1200-byte gap at `$AF50–$B3FF` that a Zelda side-A load never touches;
the splash screen + font live at `$7000` (free during the boot-disk load, harmlessly overwritten when
Zelda loads).

## Build

```sh
./setup.sh                 # one-time: build the asm6f assembler
make                       # -> build/boot.fds
```

`setup.sh` is macOS-only and self-contained: it builds the [asm6f](https://github.com/freem/asm6f)
assembler locally.

- **`build/boot.fds`**: the shippable bootloader disk. Contains no copyrighted content. Write it to a
  disk via FDSStick, boot it, and swap in your own Zelda disk when prompted.

## Testing

```sh
./setup.sh                 # one-time: build asm6f + the custom FCEUX fork
make test                  # run the test suite
```

The end-to-end test runs in a custom [FCEUX fork](https://github.com/preznes/fceux/tree/lua-disk-switching)
whose Lua disk-switching support drives the disk swap. On macOS, `./setup.sh` installs the build
dependencies via Homebrew (see `Brewfile`), clones the fork into `./fceux`, and builds it; the test
suite picks it up automatically (override with `FCEUX=/path/to/fceux` if you built it elsewhere).

You must also provide your own **`original.fds`** (an unmodified *The Legend of Zelda* disk image) in
the repo root. Without it the end-to-end test cannot run.
