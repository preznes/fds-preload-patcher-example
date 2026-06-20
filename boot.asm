; boot.asm: FDS PRELOAD PATCHER EXAMPLE. Lives at $AF50 (the 1200-byte gap side A never
; loads into, between the top of f04 at $AF4F and f06 at $B400). It loads the UNMODIFIED Zelda side A
; through the FDS BIOS, applies a small byte-diff into the freshly-loaded code (which lands in
; $6000-$AF4F, the never-reloaded region), then jumps into Zelda's own reset. After that the game
; overwrites this region with side-B data; fine, the bootloader's job is done.
;
; The byte-diff here just makes Link start with the MAGICAL SWORD, a minimal demonstration that the
; bootloader can patch the stock game in RAM at runtime, never touching the real disk.

LoadFiles = $E1F8          ; FDS BIOS: load files from the inserted disk (handles the swap prompt)
DiskIRQ   = $E149          ; FDS BIOS: service one disk byte-transfer interrupt
SplashAndWait = $7000      ; the splash file (splash.asm), loaded at $7000 by the boot disk: it shows
                           ; "PLEASE LOAD NEXT DISK", then waits for the disk swap, then blanks the
                           ; screen and returns. Lives outside the gap (free boot-time RAM), so the
                           ; font costs the gap nothing; overwritten when we load Zelda below.
VERIFY    = 0              ; 1 = after patching, flag $07FF and hold (so a test can dump RAM); 0 = run game

    .org $AF50

; --- fixed-address vector trampolines (the bootloader disk's $DFFA vectors point here) ---
RstVec: jmp BootReset      ; $AF50
NmiVec: jmp BootNMI        ; $AF53
IrqVec: jmp BootIRQ        ; $AF56

; NOTE: the magic-sword hook code (ForceSword) is NOT here in the gap; the running game uses the
; $AF50-$B3FF gap as scratch RAM (it survives the disk LOAD but not gameplay), so gap-resident code the
; game calls per-frame gets clobbered and the boot hangs. ForceSword is instead planted by the patch
; payload into free padding inside f04 (the resident game code), where it survives. See gen_payload.py.

; --- RESET: the BIOS jumps here after loading the bootloader disk's files ---
BootReset:
    sei
    cld
    ldx #$FF
    txs
    lda #$00
    sta $2000              ; NMI off
    sta $2001              ; rendering off
    sta $4022              ; disable the FDS timer IRQ (only the disk IRQ should fire during the load)
    jsr SplashAndWait      ; reset the disk head, show "PLEASE LOAD NEXT DISK", wait for the boot disk
                           ; out + Zelda disk in, blank the screen. Runs with interrupts OFF (no stale
                           ; disk IRQ during the wait); splash.asm @ $7000 (was WaitForDiskSwap)
    cli                    ; NOW enable interrupts; LoadFiles drives the Zelda transfer through IRQ
    jsr LoadZeldaSideA     ; load the real Zelda side A (now stable, no mid-read swap)
    jsr ApplyPatches       ; splice the magic-sword byte-diff into the loaded code
    jsr SetZeldaVectors    ; install Zelda's real NMI/RESET/IRQ vectors (we deliberately skip its f01)
    if VERIFY
    lda #$42
    sta $07FF              ; "patch done, RAM ready"; the verify test dumps $6000-$AF4F now
@hold:
    jmp @hold
    else
    jmp ($DFFC)            ; -> Zelda's RESET ($632A), as set by side-A f01
    endif

; The disk-swap wait now lives in splash.asm (SplashAndWait @ $7000), so the message stays on
; screen for the whole wait. The reason we boot FULLY first and only THEN invite the second disk
; is unchanged: if we called LoadFiles while the boot disk is still in, LoadFiles starts reading
; the boot disk, rejects its name, and is mid-stream when the disk gets swapped, derailing the
; block head so the next load (f04) reads a bogus filesize and truncates. SplashAndWait gates on
; $4032 bit0 (1 = no disk): boot disk leaves, a disk seats, settle, then it returns here.
LoadZeldaSideA:
    jsr LoadFiles
    .dw ZeldaDiskID        ; disk-ID the BIOS verifies against the inserted disk
    .dw SideAFileList      ; the side-A boot files to load (vectors $09 deliberately omitted)
    rts

ZeldaDiskID:
    .db $01,$5A,$45,$4C,$20,$00,$00,$00,$00,$00   ; side-A disk-ID (Zelda's $66CC ref but side byte=$00)
SideAFileList:
    ; f00..f06 file-IDs, $FF-terminated. We DELIBERATELY OMIT the vectors file ($09): the BIOS loads
    ; files in DISK order (not list order), and Zelda's $09 sits physically 2nd on disk, so loading it
    ; would slam $DFFE with Zelda's IRQ handler $645D BEFORE the code file ($0a) that contains $645D is
    ; resident, so every disk IRQ for the rest of the transfer jumps into uninitialized RAM and derails
    ; the load (it truncated f04 at 705 bytes). Skipping $09 keeps $DFFE pointing at OUR BootIRQ for the
    ; whole transfer; SetZeldaVectors installs Zelda's real vectors afterward.
    .db $00,$07,$0D,$0A,$0B,$0C,$FF

; --- install Zelda's real interrupt vectors (the f01 file we skipped above wrote these) ---
SetZeldaVectors:
    ; Copy Zelda's 6 interrupt-vector bytes ($DFFA-$DFFF) from a table, a loop instead of 6 unrolled
    ; lda/sta pairs, reclaiming ~13 B of the gap (this runs once at boot, so the
    ; loop's tiny cost is free). NMI -> $63A6, RESET -> $632A, IRQ -> $645D (same as f01 would set).
    ldx #$05
@v:
    lda ZeldaVectors,x
    sta $DFFA,x
    dex
    bpl @v
    rts
ZeldaVectors:
    .db $A6,$63,$2A,$63,$5D,$64   ; -> $DFFA,$DFFB(NMI) $DFFC,$DFFD(RESET) $DFFE,$DFFF(IRQ)

; --- the patcher: walk the diff records, copy each run into the loaded code ---
; record = [destLo, destHi, len, len*data]; a record with destHi=0 terminates.
src = $00                  ; zp pointer into PatchData
dst = $02                  ; zp pointer to the destination in $6000-$AF4F
len = $04
ApplyPatches:
    lda #<PatchData
    sta src
    lda #>PatchData
    sta src+1
@rec:
    ldy #1
    lda (src),y            ; destHi
    beq @done              ; 0 -> terminator (no patch lives in $00xx)
    sta dst+1
    dey
    lda (src),y            ; destLo
    sta dst
    ldy #2
    lda (src),y            ; len
    sta len
    lda src                ; advance past the 3-byte header
    clc
    adc #3
    sta src
    bcc @h1
    inc src+1
@h1:
    ldy #0
@copy:
    lda (src),y
    sta (dst),y
    iny
    cpy len
    bne @copy
    lda src                ; advance past the data
    clc
    adc len
    sta src
    bcc @h2
    inc src+1
@h2:
    jmp @rec
@done:
    rts

; --- IRQ: service the FDS disk transfer exactly as Zelda's $645D does ---
BootIRQ:
    pha
    txa
    pha
    tya
    pha
    lda $4030              ; disk status
    and #$02               ; byte ready?
    beq @ni
    jsr DiskIRQ
@ni:
    pla
    tay
    pla
    tax
    pla
    rti

BootNMI:
    rti

PatchData:
    .incbin "patch_payload.bin"
