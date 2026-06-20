#!/usr/bin/env bash
# Build the toolchain this repo needs, all cloned/built locally and gitignored:
#   - asm6f          : the 6502 assembler (github.com/freem/asm6f)
#   - fceux/ (fork)  : the custom FCEUX with Lua disk-switching that `make test` drives,
#                      built from github.com/preznes/fceux (branch lua-disk-switching)
# Idempotent: safe to re-run; already-built pieces are skipped.
set -euo pipefail
cd "$(dirname "$0")"

# --- asm6f (6502 assembler) ---
if [ ! -d asm6f ]; then
    git clone --depth 1 https://github.com/freem/asm6f.git
else
    echo "asm6f/ already present, skipping clone"
fi
if [ ! -x asm6f/asm6f ] || [ asm6f/asm6f.c -nt asm6f/asm6f ]; then
    echo "building asm6f..."
    make -C asm6f
else
    echo "asm6f/asm6f is up to date, skipping build"
fi

# --- FCEUX (custom fork; only needed for `make test`) ---
FCEUX_REPO="https://github.com/preznes/fceux.git"
FCEUX_BRANCH="lua-disk-switching"
FCEUX_BIN="fceux/build/src/fceux.app/Contents/MacOS/fceux"

if [ "$(uname)" != "Darwin" ]; then
    echo "NOTE: skipping FCEUX; the test harness and this build recipe are macOS-only."
elif [ -x "$FCEUX_BIN" ]; then
    echo "fceux already built ($FCEUX_BIN), skipping"
else
    if ! command -v brew >/dev/null 2>&1; then
        echo "ERROR: Homebrew is required to build FCEUX." >&2
        echo "       Install it from https://brew.sh and re-run ./setup.sh" >&2
        exit 1
    fi

    echo "installing FCEUX build dependencies (brew bundle)..."
    brew bundle --file=Brewfile

    if [ ! -d fceux ]; then
        echo "cloning the custom FCEUX fork ($FCEUX_BRANCH)..."
        git clone --depth 1 --branch "$FCEUX_BRANCH" "$FCEUX_REPO" fceux
    else
        echo "fceux/ already present, skipping clone"
    fi

    echo "building FCEUX (Qt6; this takes a few minutes)..."
    export PKG_CONFIG_PATH="$(brew --prefix minizip)/lib/pkgconfig:$(brew --prefix sdl2)/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
    cmake -S fceux -B fceux/build \
        -DCMAKE_BUILD_TYPE=Release \
        -DQT6=1 \
        -DCMAKE_PREFIX_PATH="$(brew --prefix qt);$(brew --prefix)"
    cmake --build fceux/build -j "$(sysctl -n hw.ncpu)"
    echo "built $FCEUX_BIN"
fi

echo
echo "ready. Put your own Zelda disk image at ./original.fds, then: make  (and: make test)"
