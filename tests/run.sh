#!/usr/bin/env bash
# run.sh: the magic-sword bootloader test suite.
#   1. payload_test.py: fast, emulator-free checks on the patch records + bootloader gap layout.
#   2. e2e.lua: boots build/zelda-play.fds in FCEUX, registers + begins a new game, and asserts
#                       Link reaches the overworld with the Magical Sword (Items $0657 == 3).
# Exits 0 only if every test passes. The e2e test needs ./original.fds and an FCEUX build.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
FCEUX="${FCEUX:-$REPO/fceux/build/src/fceux.app/Contents/MacOS/fceux}"
RC=0

echo "== build =="
python3 build_bootdisk.py || exit 1

echo; echo "== payload_test.py (emulator-free) =="
python3 tests/payload_test.py || RC=1

echo; echo "== e2e.lua (FCEUX) =="
if [ ! -f "$REPO/original.fds" ]; then
  echo "SKIP: no ./original.fds (drop your Zelda disk image there to run the end-to-end test)"
elif [ ! -x "$FCEUX" ]; then
  echo "SKIP: FCEUX not found at $FCEUX; run ./setup.sh to build the fork (or set FCEUX=/path/to/fceux)"
else
  ROM="/tmp/fds_magic_play.fds"
  rm -f "$ROM" "$HOME/.fceux/sav/fds_magic_play.fds" /tmp/fds_magic_e2e.log /tmp/fds_magic_e2e.png
  cp build/zelda-play.fds "$ROM"
  FCEUX_FDS_EXT_SOCK="" "$FCEUX" --loadlua "$REPO/tests/e2e.lua" "$ROM" >/tmp/fds_magic_fceux.log 2>&1 &
  FP=$!; ( sleep 90; kill -9 $FP 2>/dev/null ) & KP=$!
  wait $FP 2>/dev/null            # FCEUX self-exits via os.exit in the lua
  kill "$KP" 2>/dev/null; wait "$KP" 2>/dev/null   # reap the safety-timeout watchdog quietly
  cat /tmp/fds_magic_e2e.log 2>/dev/null
  grep -q "^PASS" /tmp/fds_magic_e2e.log 2>/dev/null || { echo "e2e FAILED"; RC=1; }
fi

echo
[ $RC -eq 0 ] && echo "ALL TESTS PASSED" || echo "TESTS FAILED"
exit $RC
