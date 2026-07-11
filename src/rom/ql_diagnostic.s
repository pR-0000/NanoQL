; NanoQL autonomous 68000/SDRAM/video contention diagnostic.
;
; This ROM requires no keyboard. It continuously writes and verifies 48 KiB
; of main RAM while the ZX8301-compatible scanout reads screen 1 from the
; same SDRAM. A55A reports a completed pass; DEAD reports a mismatch.

                org     $000000

                dc.l    $00040000      ; Initial supervisor stack pointer
                dc.l    start           ; Initial program counter

                dcb.b   $68-*, $ff
                dc.l    vblank_handler  ; Level-2 autovector (vector 26)

                dcb.b   $100-*, $ff

start:
                move.w  #$2700,sr       ; Keep IRQs masked during setup
                move.w  $00018020,d1    ; Exercise ZX8302 status read
                move.b  #$88,$00018063  ; Screen 1 ($28000), QL mode 8
                move.w  #$2000,sr       ; Enable level-2 VBlank IRQ
                move.w  #$1357,d3       ; Known first-pass pattern seed

stress_pass:
                lea     $00030000,a0    ; 48 KiB test area, outside VRAM
                move.w  d3,d0
                move.w  #$5fff,d1       ; 24,576 16-bit words
write_loop:
                move.w  d0,(a0)+
                addq.w  #1,d0
                dbra    d1,write_loop

                lea     $00030000,a0
                move.w  d3,d0
                move.w  #$5fff,d1
read_loop:
                move.w  (a0)+,d2
                cmp.w   d0,d2
                bne.w   failed
                addq.w  #1,d0
                dbra    d1,read_loop

                move.w  #$a55a,$0002fffc
                addi.w  #$1f3d,d3       ; Change the pattern each pass
                bra.w   stress_pass

failed:
                move.w  #$dead,$0002fffc
                bra.s   failed

                dcb.b   $200-*, $ff

vblank_handler:
                move.b  #$08,$00018021  ; Acknowledge ZX8302 VBlank
                rte
