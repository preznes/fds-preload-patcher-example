# fds-preload-patcher-example: a standalone example FDS bootloader that loads the stock Zelda disk
# and patches it in RAM at runtime so Link starts with the MAGICAL SWORD. The real disk is never touched.
#
#   make         build the boot disks into build/  (boot.fds ships; zelda-play.fds is local test)
#   make test    run the test suite (needs ./original.fds + FCEUX)
#   make clean   remove build artifacts
#   ./setup.sh   build the asm6f toolchain (run once)

.PHONY: all build test clean

all: build

build:
	python3 build_bootdisk.py

test: build
	tests/run.sh

clean:
	rm -f boot.bin splash.bin splash_font.bin patch_payload.bin
	rm -rf build
