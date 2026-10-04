// ============================================================================
// levels.asm - Level terrain and object data (6 levels)
// Included from thrust.asm at $1000-$1FFF (levels area; the address comments
// on the lines below are from the original layout at $a03c-$a351)
// ============================================================================

// ----------------------------------------------------------------------------
// ==========================================================================
// LEVEL DATA
// ==========================================================================
// The level data format is identical to the BBC Micro version.
//
// Terrain: each level has four tables. A/B describe the left cave wall, C/D the
// right wall. A[i] is a run length in rows, B[i] the X step added on each of
// those rows (signed). The terrain is decoded twice per wall (even/odd rows) by
// terrain_process as the screen scrolls. X is in 4-pixel units (80 columns
// across the screen, the world is 256 units wide and wraps).
// The first entries ($FF,$FF,...) are the open space above the planet.
//
// Level 0 terrain
// ----------------------------------------------------------------------------
terrain_data_level_0_A:
    .byte $ff,$ff,$af,$01,$0b,$3c,$17,$14,$17,$3c,$3c,$1f,$17,$14,$17,$1f,$01,$10,$14,$10,$01,$ff
terrain_data_level_0_B:
    .byte $00,$00,$00,$4b,$01,$00,$ff,$00,$01,$00,$01,$00,$ff,$00,$01,$00,$b4,$ff,$00,$01,$14,$00
terrain_data_level_0_C:
    .byte $ff,$ff,$af,$01,$17,$3c,$11,$15,$11,$23,$3c,$3f,$11,$15,$11,$43,$01,$03,$10,$ff  
terrain_data_level_0_D:
    .byte $00,$00,$00,$86,$ff,$00,$01,$00,$ff,$00,$01,$00,$01,$00,$ff,$00,$c0,$00,$ff,$00
terrain_data_level_1_A:
    .byte $ff,$ff,$af,$01,$0b,$01,$17,$36,$17,$14,$0f,$01,$ff  // $a05c  left wall: run lengths
terrain_data_level_1_B:
    .byte $00,$00,$00,$4a,$01,$19,$01,$00,$ff,$00,$01,$14,$00  // $a069  left wall: X step per row
terrain_data_level_1_C:
    .byte $ff,$ff,$af,$01,$1b,$3a,$11,$15,$18,$ff  // $a076  right wall: run lengths
terrain_data_level_1_D:
    .byte $00,$00,$00,$b4,$ff,$00,$01,$00,$ff,$00  // $a080  right wall: X step per row
terrain_data_level_2_A:
    .byte $ff,$ff,$b9,$01,$50,$0a,$32,$01,$0a,$1e,$01,$0a,$55,$0a,$01,$ff  // $a08a  left wall: run lengths
terrain_data_level_2_B:
    .byte $00,$00,$00,$87,$00,$ff,$00,$e2,$ff,$00,$f1,$ff,$00,$01,$15,$00  // $a09a  left wall: X step per row
terrain_data_level_2_C:
    .byte $ff,$ff,$b9,$01,$13,$01,$3c,$01,$14,$0a,$01,$3c,$01,$32,$01,$09,$ff  // $a0aa  right wall: run lengths
terrain_data_level_2_D:
    .byte $00,$00,$00,$b4,$00,$e9,$00,$18,$00,$ff,$ec,$00,$e2,$00,$ec,$ff,$00  // $a0bb  right wall: X step per row
terrain_data_level_3_A:
    .byte $ff,$ff,$a0,$01,$13,$01,$15,$26,$14,$0a,$06,$14,$22,$01,$14,$01,$26,$1c,$24,$0a,$ff,$ff  // $a0cc  left wall: run lengths
terrain_data_level_3_B:
    .byte $00,$00,$00,$5a,$01,$11,$00,$ff,$00,$01,$00,$ff,$00,$19,$01,$21,$00,$ff,$00,$01,$00,$00  // $a0e2  left wall: X step per row
terrain_data_level_3_C:
    .byte $ff,$ff,$a0,$01,$67,$01,$12,$18,$01,$84,$18,$14,$01,$ff,$ff  // $a0f8  right wall: run lengths
terrain_data_level_3_D:
    .byte $00,$00,$00,$8d,$00,$e2,$00,$01,$28,$00,$ff,$00,$f4,$00,$00  // $a107  right wall: X step per row
terrain_data_level_4_A:
    .byte $ff,$ff,$a5,$01,$15,$16,$01,$38,$01,$0c,$1c,$01,$28,$14,$01,$56,$14,$0e,$01,$1c,$0c,$01,$1e,$0c,$01,$52,$08,$01,$ff  // $a116  left wall: run lengths
terrain_data_level_4_B:
    .byte $00,$00,$00,$58,$01,$00,$17,$00,$f6,$ff,$00,$0a,$00,$ff,$ec,$00,$01,$00,$f6,$00,$01,$12,$00,$01,$14,$00,$01,$0a,$00  // $a133  left wall: X step per row
terrain_data_level_4_C:
    .byte $ff,$ff,$a5,$01,$64,$01,$0a,$1e,$01,$28,$01,$28,$0a,$01,$22,$20,$2c,$01,$0a,$16,$01,$3e,$10,$1e,$0c,$ff  // $a150  right wall: run lengths
terrain_data_level_4_D:
    .byte $00,$00,$00,$93,$00,$0e,$01,$00,$dc,$00,$08,$00,$ff,$de,$00,$01,$00,$0a,$01,$00,$10,$00,$01,$00,$ff,$00  // $a16a  right wall: X step per row
terrain_data_level_5_A:
    .byte $ff,$ff,$7f,$01,$3e,$01,$50,$28,$01,$0a,$a2,$01,$36,$0d,$14,$36,$0e,$0d,$1f,$0a,$39,$01,$ff  // $a184  left wall: run lengths
terrain_data_level_5_B:
    .byte $00,$00,$00,$4d,$00,$17,$01,$00,$ec,$ff,$00,$ef,$00,$ff,$00,$01,$00,$ff,$00,$ff,$00,$0b,$00  // $a19b  left wall: X step per row
terrain_data_level_5_C:
    .byte $ff,$ff,$7f,$01,$2b,$14,$37,$41,$14,$14,$01,$1c,$22,$12,$14,$0a,$32,$01,$27,$2c,$1e,$07,$07,$38,$1c,$23,$01,$16,$01,$ff  // $a1b2  right wall: run lengths
terrain_data_level_5_D:
    .byte $00,$00,$00,$b7,$ff,$00,$01,$00,$01,$00,$e7,$ff,$00,$01,$00,$ff,$00,$eb,$00,$01,$00,$01,$ff,$00,$ff,$00,$0d,$00,$f1,$00  // $a1d0  right wall: X step per row
level_0_obj_pos_X:
    .byte $4e,$a0,$34,$4b
level_0_obj_pos_Y:
    .byte $5b,$a4,$a7,$29
level_0_obj_pos_Y_EXT:
    .byte $03,$01,$01,$02
level_0_obj_type:
    .byte $05,$06,$04,$00,$ff                   // $a1fa  object types, $FF terminated
level_0_gun_param:
    .byte $00,$00,$00,$1e                       // $a1ff  gun parameters: bits 2-4 base angle, bits 0-1 spread
level_1_obj_pos_X:
    .byte $7f,$64,$8b,$74,$9e                   // $a203  object X positions (world X, 4-pixel units)
level_1_obj_pos_Y:
    .byte $38,$b1,$3b,$14,$0a                   // $a208  object Y positions (low byte)
level_1_obj_pos_Y_EXT:
    .byte $02,$01,$02,$02,$02                   // $a20d  object Y positions (high byte)
level_1_obj_type:
    .byte $05,$06,$04,$01,$03,$ff               // $a212  object types, $FF terminated
level_1_gun_param:
    .byte $00,$00,$00,$06,$0f                   // $a218  gun parameters: bits 2-4 base angle, bits 0-1 spread
level_2_obj_pos_X:
    .byte $4e,$a4,$78,$97,$9d,$a3,$7d,$67,$5d,$3e,$58,$ab,$81  // $a21d  object X positions (world X, 4-pixel units)
level_2_obj_pos_Y:
    .byte $ce,$c3,$b1,$21,$21,$21,$5e,$91,$97,$72,$48,$1e,$0a  // $a22a  object Y positions (low byte)
level_2_obj_pos_Y_EXT:
    .byte $02,$01,$01,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02  // $a237  object Y positions (high byte)
level_2_obj_type:
    .byte $05,$06,$04,$04,$04,$04,$04,$04,$02,$01,$01,$02,$01,$ff  // $a244  object types, $FF terminated
level_2_gun_param:
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$1b,$06,$0a,$16,$04  // $a252  gun parameters: bits 2-4 base angle, bits 0-1 spread
level_3_obj_pos_X:
    .byte $8e,$5b,$ac,$ac,$92,$72,$5a,$5a,$78,$6d,$8a,$a2  // $a25f  object X positions (world X, 4-pixel units)
level_3_obj_pos_Y:
    .byte $d9,$40,$51,$87,$57,$d0,$01,$16,$24,$4c,$92,$ba  // $a26b  object Y positions (low byte)
level_3_obj_pos_Y_EXT:
    .byte $02,$02,$02,$02,$02,$01,$02,$02,$02,$02,$02,$02  // $a277  object Y positions (high byte)
level_3_obj_type:
    .byte $05,$06,$08,$08,$04,$01,$00,$01,$03,$00,$01,$02,$ff  // $a283  object types, $FF terminated
level_3_gun_param:
    .byte $00,$00,$00,$00,$00,$06,$06,$06,$12,$1f,$06,$1e  // $a290  gun parameters: bits 2-4 base angle, bits 0-1 spread
level_4_obj_pos_X:
    .byte $a2,$8f,$a4,$98,$7c,$9a,$a0,$68,$69,$6f,$89,$8f,$72,$a2,$86,$5d  // $a29c  object X positions (world X, 4-pixel units)
    .byte $8e,$7b,$ac                           // $a2ac  
level_4_obj_pos_Y:
    .byte $8d,$29,$25,$75,$c9,$2b,$2b,$87,$0a,$0a,$35,$35,$0d,$0c,$83,$04  // $a2af  object Y positions (low byte)
    .byte $00,$2f,$63                           // $a2bf  
level_4_obj_pos_Y_EXT:
    .byte $03,$02,$03,$03,$01,$02,$02,$02,$03,$03,$03,$03,$02,$02,$02,$03  // $a2c2  object Y positions (high byte)
    .byte $03,$03,$03                           // $a2d2  
level_4_obj_type:
    .byte $05,$06,$08,$07,$04,$04,$04,$04,$04,$04,$04,$04,$01,$03,$02,$00  // $a2d5  object types, $FF terminated
    .byte $03,$00,$03,$ff                       // $a2e5  
level_4_gun_param:
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$05,$14,$1a,$02  // $a2e9  gun parameters: bits 2-4 base angle, bits 0-1 spread
    .byte $12,$1e,$19                           // $a2f9  
level_5_obj_pos_X:
    .byte $9a,$a9,$a1,$be,$9a,$c1,$af,$9b,$a2,$9b,$7b,$ac,$ac,$ac,$ca,$99  // $a2fc  object X positions (world X, 4-pixel units)
    .byte $99                                   // $a30c  
level_5_obj_pos_Y:
    .byte $e4,$04,$98,$5d,$f8,$57,$bf,$ac,$86,$2e,$1f,$c1,$a8,$67,$3e,$39  // $a30d  object Y positions (low byte)
    .byte $cc                                   // $a31d  
level_5_obj_pos_Y_EXT:
    .byte $03,$04,$03,$03,$02,$02,$03,$03,$03,$03,$03,$02,$02,$02,$02,$02  // $a31e  object Y positions (high byte)
    .byte $01                                   // $a32e  
level_5_obj_type:
    .byte $05,$06,$07,$08,$04,$04,$02,$01,$01,$03,$01,$02,$03,$02,$03,$01  // $a32f  object types, $FF terminated
    .byte $03,$ff                               // $a33f  
level_5_gun_param:
    .byte $00,$00,$00,$00,$00,$00,$1a,$06,$09,$12,$06,$16,$12,$1b,$12,$05  // $a341  gun parameters: bits 2-4 base angle, bits 0-1 spread
    .byte $0e                                   // $a351  
