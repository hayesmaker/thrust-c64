// ============================================================================
// title_qr.asm - thrusty-levels: QR code (link to the GitHub repo) on the
// title screen, left of the high score table. Lives in the free tail of the
// music area ($2CAD-$2FFF; runs in place, not moved by the relocator).
// Data: title_qr_data.asm, made by packages/thrusty-levels/tools/qr2asm.py.
//
// 8x8 bitmap cells. The title screen is in hires bitmap mode, like its
// text: a QR module is 2 pixels x 2 lines (square on screen), %11 = light
// (screen colour high nibble = white), %00 = dark (low nibble = black).
// Called after the high score table is
// drawn, because each table entry is 40 characters wide and wraps into
// columns 0-8 of the next row.
// ============================================================================

.const QR_ROW   = 6                             // text row of the top cell
.const QR_COL   = 0
.const QR_CELLS = 8                             // 8x8 cells = 32x32 modules
.const QR_LIGHT = $10                           // screen byte: 1 pixels white, 0 pixels black
.label qr_bitmap = $6000 + QR_ROW * 320 + QR_COL * 8

plot_qr_code:
    lda #<qr_bitmap
    sta colour_ptr_A
    lda #>qr_bitmap
    sta colour_ptr_A+1
    ldx #$00                                    // index into qr_data
qr_cell_row:
    ldy #$00                                    // offset in this cell row
qr_byte:
    lda qr_data,x                               // 4 lines of half a cell
    pha
    lsr
    lsr
    lsr
    lsr
    jsr qr_put_line_pair
    pla
    and #$0f
    jsr qr_put_line_pair
    inx
    cpy #QR_CELLS * 8
    bne qr_byte
    clc                                         // next cell row: +320
    lda colour_ptr_A
    adc #<320
    sta colour_ptr_A
    lda colour_ptr_A+1
    adc #>320
    sta colour_ptr_A+1
    cpx #QR_CELLS * 16
    bne qr_cell_row
    // colours: the same in both screen matrices (the title shows either)
    lda #QR_LIGHT
    ldy #QR_CELLS - 1
qr_colour:
    .for (var r = 0; r < QR_CELLS; r++) {
        sta $5c00 + (QR_ROW + r) * 40 + QR_COL,y
        sta $5400 + (QR_ROW + r) * 40 + QR_COL,y
    }
    dey
    bpl qr_colour
    rts

// A = 4 modules (bit 3 = leftmost, 1 = light): write two bitmap lines at
// (colour_ptr_A),y and advance y by 2.
qr_put_line_pair:
    stx qr_save_x
    tax
    lda qr_expand,x
    sta (colour_ptr_A),y
    iny
    sta (colour_ptr_A),y
    iny
    ldx qr_save_x
    rts

qr_save_x:
    .byte $00
qr_expand:                                      // nibble -> 4 modules of 2 pixels, light = %11
    .fill 16, ((i & 8) << 3 | (i & 4) << 2 | (i & 2) << 1 | (i & 1)) * 3

    #import "title_qr_data.asm"
