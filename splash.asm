; splash.asm: boot-disk SPLASH SCREEN (loaded at $7000; free boot-time RAM, overwritten when the
; bootloader later loads Zelda, so it costs the $AF50 gap nothing). Called by BootReset in place of the
; old WaitForDiskSwap. It:
;   1. Resets the disk drive + finishes the BIOS reset-stub init MANUALLY (the false-reset boot skipped
;      it, and we must NOT JMP ($FFFC), which would hand control back to the BIOS, and that would boot Zelda
;      normally, show the license screen, and skip our patch). Without this the swap poll reads garbage
;      and Zelda's reset hangs on real hardware.
;   2. Draws "PLEASE LOAD NEXT DISK" and waits (frame-paced) for the boot disk OUT then the Zelda disk IN.
;   3. Wipes the screen and returns to BootReset, which loads + patches Zelda itself.

ptr = $10                  ; zp: font-copy source pointer

    .org $7000

SplashAndWait:
    ; --- (1) reset the disk drive + replicate the rest of the BIOS reset stub, by hand. Interrupts are
    ;     OFF here (BootReset doesn't cli until we return), so no stale disk IRQ fires during the wait. ---
    lda #$00
    sta $4023              ; disable disk + audio I/O
    lda #$83
    sta $4023              ; re-enable -> resets the disk transfer subsystem
    lda #$2E
    sta $4025              ; stop motor (rewinds head to disk start), read mode, horizontal mirroring
    sta $FA                ; BIOS read-back shadow of write-only $4025 (LoadFiles read-modify-writes it)
    lda #$FF
    sta $4026              ; expansion-port lines
    sta $F9                ; BIOS read-back shadow of write-only $4026
    lda #$00
    sta $FB
    sta $FC
    sta $FD               ; BIOS scratch ZP vars
    sta $4016             ; gamepad strobe off
    sta $4010             ; DPCM off
    lda #$C0
    sta $4017             ; APU frame counter: IRQ off
    lda #$0F
    sta $4015             ; APU: enable pulse/triangle/noise
    lda #$80
    sta $4080             ; FDS audio: reset volume envelope
    lda #$E8
    sta $408A             ; FDS audio: envelope speed
    lda #$C0
    sta $0100             ; FDS pseudo-reg: NMI vector select -> NMI #3 ($DFFA)
    lda #$80
    sta $0101             ; FDS pseudo-reg: IRQ vector select

    ; --- (2) draw the screen ---
    bit $2002              ; reset the PPU $2005/$2006 write latch

    ; copy the font into CHR-RAM at PPU $0000 (256 tiles * 16 = 4096 bytes)
    lda #$00
    sta $2006
    sta $2006              ; PPUADDR = $0000
    lda #<FontData
    sta ptr
    lda #>FontData
    sta ptr+1
    ldx #$10               ; 16 pages of 256 bytes = 4096
    ldy #$00
@font:
    lda (ptr),y
    sta $2007
    iny
    bne @font
    inc ptr+1
    dex
    bne @font

    ; palette: $3F00 backdrop = black, $3F01 = white
    lda #$3F
    sta $2006
    lda #$00
    sta $2006
    lda #$0F
    sta $2007
    lda #$30
    sta $2007

    ; clear nametable 0 to blank tile $00
    lda #$20
    sta $2006
    lda #$00
    sta $2006
    lda #$00
    ldx #$04
    ldy #$00
@clear:
    sta $2007
    iny
    bne @clear
    dex
    bne @clear

    ; message at row 14, col 5 ($21C5)
    lda #$21
    sta $2006
    lda #$C5
    sta $2006
    ldx #$00
@msg:
    lda Message,x
    beq @msgdone
    sta $2007
    inx
    bne @msg
@msgdone:

    ; reset scroll & enable background rendering
    bit $2002
    lda #$00
    sta $2006
    sta $2006
    sta $2005
    sta $2005
    sta $2000              ; NMI off, NT0, bg pattern $0000
    lda #$0A
    sta $2001              ; show background

    ; --- (3) wait for the boot disk OUT then the Zelda disk IN, polled once per frame ($4032 bit0:
    ;     1 = no disk). Frame-paced (not a tight loop), far less sensitive to FDS status transients. ---
@out:
    jsr WaitVBlank
    lda $4032
    and #$01
    beq @out               ; loop while a disk is present (boot disk not removed yet)
@in:
    jsr WaitVBlank
    lda $4032
    and #$01
    bne @in                ; loop while the drive is empty (Zelda disk not seated yet)

    ; settle, then wipe the message so the BIOS load animation / Zelda paints a clean screen
    ldx #$00
    ldy #$00
@settle:
    dey
    bne @settle
    dex
    bne @settle

    lda #$00
    sta $2001              ; rendering off (VRAM writes unrestricted)
    bit $2002
    lda #$20
    sta $2006
    lda #$00
    sta $2006
    lda #$00
    ldx #$04
    ldy #$00
@wipe:
    sta $2007
    iny
    bne @wipe
    dex
    bne @wipe
    lda #$00
    sta $2000
    rts

; wait for the start of vblank (also resets the $2005/$2006 write latch)
WaitVBlank:
@w:
    bit $2002
    bpl @w
    rts

Message:
    .db "PLEASE LOAD NEXT DISK", $00

FontData:
    .incbin "splash_font.bin"
