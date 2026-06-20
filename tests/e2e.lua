-- e2e.lua: end-to-end test of the magic-sword bootloader in FCEUX.
-- Boots build/zelda-play.fds (bootloader + Zelda A/B), swaps in Zelda (the bootloader loads + patches
-- it), then registers + begins a NEW game and reaches the overworld, asserting the world actually boots
-- AND Link has the Magical Sword (Items $0657 == 3). Writes /tmp/fds_magic_e2e.log; exits 0 on PASS.
local function frames(n) for i = 1, n do emu.frameadvance() end end
local function rb(a) return memory.readbyte(a) end
local log = io.open("/tmp/fds_magic_e2e.log", "w")
local function w(s) log:write(s .. "\n"); log:flush() end
local function wait_until(fn, cap) for i = 1, cap do emu.frameadvance(); if fn() then return i end end; return cap end
local function wait_gm(v, cap) return wait_until(function() return rb(0x12) == v end, cap) end
local function press(b, h, g)
  h = h or 4; g = g or 8
  for i = 1, h do joypad.set(1, {[b] = true}); emu.frameadvance() end
  for i = 1, g do joypad.set(1, {}); emu.frameadvance() end
end
local GAP, S = 20, 25
local function swap() emu.fds_eject(); frames(GAP); emu.fds_select_side(); frames(GAP); emu.fds_insert(); frames(GAP) end

emu.speedmode("maximum")
if sound and sound.set then sound.set(0) end

-- Boot + swap in Zelda side A; wait for the bootloader to finish (SetZeldaVectors installs Zelda's reset
-- vector $DFFC=$632A => Zelda fully loaded + RAM-patched). The license-free boot has NO BIOS "GameMode
-- $24" phase, so $DFFC is the correct ready signal, NOT a GameMode change.
frames(480); swap()
local loaded = wait_until(function() return rb(0xDFFC) == 0x2A end, 1500)
w(string.format("bootloader done after %d f; hook $644b=%02X%02X%02X ForceSword $A235=%02X%02X%02X",
  loaded, rb(0x644B), rb(0x644C), rb(0x644D), rb(0xA235), rb(0xA236), rb(0xA237)))
frames(S)

-- Register a name and begin a new game -> overworld (the proven menu navigation).
swap()                                                                      -- Zelda side A -> side B
wait_gm(0x01, 800); frames(S)
press("start", 4, 8); wait_until(function() return rb(0x10) == 0x0A end, 400); frames(S)
press("A", 4, 8); wait_gm(0x0E, 300); frames(S); press("A", 4, 12)
press("select", 4, 12); press("select", 4, 12); press("select", 4, 12)
press("start", 4, 30); wait_gm(0x01, 1600); frames(S)
press("start", 4, 30); local r = wait_gm(0x05, 1600)
joypad.set(1, {}); frames(40)

local gm, room, sword = rb(0x12), rb(0xEB), rb(0x0657)
w(string.format("FINAL: GameMode=%02X RoomId=%02X Items($0657)=%d (reached play after %d f)", gm, room, sword, r))
gui.savescreenshotas("/tmp/fds_magic_e2e.png")

-- the hook must still be resident (f04 survives gameplay; the gap would NOT)
local hook_ok = (rb(0x644B) == 0x20 and rb(0x644C) == 0x35 and rb(0x644D) == 0xA2
                 and rb(0xA235) == 0xA9 and rb(0xA236) == 0x03)
if gm == 0x05 and room == 0x77 and sword == 3 and hook_ok then
  w("PASS: booted to the overworld with the Magical Sword, hook resident")
  frames(2); os.exit(0)
else
  w("FAIL: expected GameMode $05, RoomId $77, Items 3, hook resident")
  frames(2); os.exit(1)
end
