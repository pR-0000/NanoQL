; SPDX-License-Identifier: GPL-3.0-or-later
; NanoQL direct-injection example for vasmm68k_mot.
;
; This is a raw, position-fixed 68000 program. It does not use QDOS and writes
; directly to the original QL MODE 4 framebuffer at $20000. It deliberately
; uses only basic 68000 instructions, so it is also a compact starting point
; for programs built with another assembler or compiler.

        ; The binary is loaded at this exact address by NanoQL Link. Because a
        ; raw file has no relocation table, ORG and --address/--pc must agree.
        org     $30000

; Useful addresses and dimensions from the original Sinclair QL hardware.
screen_base     equ     $20000
screen_bytes    equ     32768          ; 512 x 256 pixels, two bits per pixel
line_bytes      equ     128            ; bytes occupied by one MODE 4 scanline
green_block     equ     $ff00          ; eight green pixels in one 16-bit word

start:
        ; ZX8301 master-chip register $18063 selects MODE 4 and framebuffer
        ; base $20000. MOVE.B is important because this is an 8-bit register.
        move.b  #0,$18063              ; MODE 4, screen base $20000

        ; Clear the complete 32 KiB screen. A0 walks through VRAM in longwords.
        ; DBRA executes exactly 8192 iterations because D0 starts at 8191.
        movea.l #screen_base,a0
        move.w  #(screen_bytes/4)-1,d0
.clear:
        clr.l   (a0)+
        dbra    d0,.clear

        ; Draw the two lines. A0 points to their first screen byte, A1 to the
        ; tiny bitmap font, and D0 contains the number of characters. Each
        ; source pixel becomes one 16-bit QL word by four scanlines.
        movea.l #(screen_base+80*line_bytes+34),a0
        lea     hello_rows(pc),a1
        moveq   #5,d0
        bsr     draw_text

        movea.l #(screen_base+124*line_bytes+28),a0
        lea     nanoql_rows(pc),a1
        moveq   #6,d0
        bsr     draw_text

.forever:
        ; Bare-metal code has no operating system to return to. Keeping the PC
        ; here makes the resulting screen and RAM easy to inspect. The NanoQL
        ; Link `qdos` command resets the QL when development is finished.
        bra.s   .forever

; a0 = first framebuffer byte, a1 = row-major 5-bit glyph data
; d0 = character count
draw_text:
        ; Preserve every register used by this subroutine on the 68000 stack.
        movem.l d1-d7/a2-a3,-(sp)
        move.w  d0,d1
        subq.w  #1,d1                  ; DBRA character count
        moveq   #6,d7                  ; seven font rows
.row:
        moveq   #3,d5                  ; four scanlines per font row
.scanline:
        movea.l a1,a3
        movea.l a0,a2
        move.w  d1,d6
.character:
        ; One byte stores one 5-pixel font row. BTST examines bits 4 down to 0.
        moveq   #0,d2
        move.b  (a3)+,d2
        moveq   #4,d4
.pixel:
        moveq   #0,d3
        btst    d4,d2
        beq.s   .store
        move.w  #green_block,d3
.store:
        ; A set font bit stores eight green QL pixels; an unset bit stores
        ; black. Post-increment advances A2 to the following screen word.
        move.w  d3,(a2)+
        dbra    d4,.pixel
        clr.w   (a2)+                  ; one blank block between characters
        dbra    d6,.character
        adda.w  #line_bytes,a0
        dbra    d5,.scanline
        adda.w  d0,a1                  ; next row of glyph bytes
        dbra    d7,.row
        movem.l (sp)+,d1-d7/a2-a3
        rts

; Font data is row-major: the first five bytes are the top rows of H,E,L,L,O,
; followed by their second rows, and so on. Only bits 4..0 of each byte matter.
hello_rows:
        dc.b    $11,$1f,$10,$10,$0e
        dc.b    $11,$10,$10,$10,$11
        dc.b    $11,$10,$10,$10,$11
        dc.b    $1f,$1e,$10,$10,$11
        dc.b    $11,$10,$10,$10,$11
        dc.b    $11,$10,$10,$10,$11
        dc.b    $11,$1f,$1f,$1f,$0e

nanoql_rows:
        dc.b    $11,$0e,$11,$0e,$0e,$10
        dc.b    $19,$11,$19,$11,$11,$10
        dc.b    $15,$11,$15,$11,$11,$10
        dc.b    $13,$1f,$13,$11,$11,$10
        dc.b    $11,$11,$11,$11,$15,$10
        dc.b    $11,$11,$11,$11,$12,$10
        dc.b    $11,$11,$11,$0e,$0d,$1f

        even
