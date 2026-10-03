// ============================================================================
// level_tables.asm - Per-level tables: restart points, gravity, pointers, colours
// Included from thrust.asm. Runtime addresses $a873-$a999
// ============================================================================

// ----------------------------------------------------------------------------
// Restart points ("level reset data"): number of restart points per level,
// followed by each level's table. A table with n entries has 6 rows of n bytes:
// ship Y_EXT, ship Y, window X, window Y_EXT, window Y, ship X
// ----------------------------------------------------------------------------
level_reset_data_sizes:
    .byte $01,$01,$03,$03,$04,$05               // $a873  
level_0_reset_data:
    .byte $01                                   // $a879  
    .byte $91                                   // $a87a  
    .byte $56                                   // $a87b  
    .byte $01                                   // $a87c  
    .byte $2d                                   // $a87d  
    .byte $6c                                   // $a87e  
level_1_reset_data:
    .byte $01                                   // $a87f  
    .byte $91                                   // $a880  
    .byte $56                                   // $a881  
    .byte $01                                   // $a882  
    .byte $2d                                   // $a883  
    .byte $6c                                   // $a884  
level_2_reset_data:
    .byte $01,$02,$02                           // $a885  
    .byte $91,$2d,$96                           // $a888  
    .byte $56,$6f,$32                           // $a88b  
    .byte $01,$01,$02                           // $a88e  
    .byte $2d,$be,$23                           // $a891  
    .byte $6c,$86,$48                           // $a894  
level_3_reset_data:
    .byte $01,$01,$02                           // $a897  
    .byte $91,$e6,$4a                           // $a89a  
    .byte $56,$57,$76                           // $a89d  
    .byte $01,$01,$01                           // $a8a0  
    .byte $2d,$6a,$d8                           // $a8a3  
    .byte $6c,$7b,$a1                           // $a8a6  
level_4_reset_data:
    .byte $01,$02,$02,$03                       // $a8a9  
    .byte $91,$68,$dc,$15                       // $a8ad  
    .byte $56,$58,$43,$64                       // $a8b1  
    .byte $01,$01,$02,$02                       // $a8b5  
    .byte $2d,$ee,$66,$9f                       // $a8b9  
    .byte $6c,$7b,$6b,$81                       // $a8bd  
level_5_reset_data:
    .byte $01,$02,$02,$03,$03                   // $a8c1  
    .byte $91,$4b,$d4,$2a,$98                   // $a8c6  
    .byte $56,$8c,$82,$6e,$87                   // $a8cb  
    .byte $01,$01,$02,$02,$03                   // $a8d0  
    .byte $2d,$d8,$5a,$b4,$1b                   // $a8d5  
    .byte $6c,$a2,$9a,$87,$ae                   // $a8da  
level_reset_ptr_table_LO:
    .byte <(level_0_reset_data)                 // $a8df  
    .byte <(level_1_reset_data)                 // $a8e0  
    .byte <(level_2_reset_data)                 // $a8e1  
    .byte <(level_3_reset_data)                 // $a8e2  
    .byte <(level_4_reset_data)                 // $a8e3  
    .byte <(level_5_reset_data)                 // $a8e4  
level_reset_ptr_table_HI:
    .byte >(level_0_reset_data)                 // $a8e5  
    .byte >(level_1_reset_data)                 // $a8e6  
    .byte >(level_2_reset_data)                 // $a8e7  
    .byte >(level_3_reset_data)                 // $a8e8  
    .byte >(level_4_reset_data)                 // $a8e9  
    .byte >(level_5_reset_data)                 // $a8ea  
level_reset_ptr2_table_LO:
    .byte <(level_0_reset_data+1)               // $a8eb  
    .byte <(level_1_reset_data+1)               // $a8ec  
    .byte <(level_2_reset_data+3)               // $a8ed  
    .byte <(level_3_reset_data+3)               // $a8ee  
    .byte <(level_4_reset_data+4)               // $a8ef  
    .byte <(level_5_reset_data+5)               // $a8f0  
level_reset_ptr2_table_HI:
    .byte >(level_0_reset_data+1)               // $a8f1  
    .byte >(level_1_reset_data+1)               // $a8f2  
    .byte >(level_2_reset_data+3)               // $a8f3  
    .byte >(level_3_reset_data+3)               // $a8f4  
    .byte >(level_4_reset_data+4)               // $a8f5  
    .byte >(level_5_reset_data+5)               // $a8f6  
level_gravity_FRAC_table:
    .byte $05,$07,$09,$0b,$0c,$0d               // $a8f7  
terrain_left_wall_counter_ptrs_LO:
    .byte <(terrain_data_level_0_A)             // $a8fd  
    .byte <(terrain_data_level_1_A)             // $a8fe  
    .byte <(terrain_data_level_2_A)             // $a8ff  
    .byte <(terrain_data_level_3_A)             // $a900  
    .byte <(terrain_data_level_4_A)             // $a901  
    .byte <(terrain_data_level_5_A)             // $a902  
terrain_left_wall_counter_ptrs_HI:
    .byte >(terrain_data_level_0_A)             // $a903  
    .byte >(terrain_data_level_1_A)             // $a904  
    .byte >(terrain_data_level_2_A)             // $a905  
    .byte >(terrain_data_level_3_A)             // $a906  
    .byte >(terrain_data_level_4_A)             // $a907  
    .byte >(terrain_data_level_5_A)             // $a908  
terrain_left_wall_increment_ptrs_LO:
    .byte <(terrain_data_level_0_B)             // $a909  
    .byte <(terrain_data_level_1_B)             // $a90a  
    .byte <(terrain_data_level_2_B)             // $a90b  
    .byte <(terrain_data_level_3_B)             // $a90c  
    .byte <(terrain_data_level_4_B)             // $a90d  
    .byte <(terrain_data_level_5_B)             // $a90e  
terrain_left_wall_increment_ptrs_HI:
    .byte >(terrain_data_level_0_B)             // $a90f  
    .byte >(terrain_data_level_1_B)             // $a910  
    .byte >(terrain_data_level_2_B)             // $a911  
    .byte >(terrain_data_level_3_B)             // $a912  
    .byte >(terrain_data_level_4_B)             // $a913  
    .byte >(terrain_data_level_5_B)             // $a914  
terrain_right_wall_counter_ptrs_LO:
    .byte <(terrain_data_level_0_C)             // $a915  
    .byte <(terrain_data_level_1_C)             // $a916  
    .byte <(terrain_data_level_2_C)             // $a917  
    .byte <(terrain_data_level_3_C)             // $a918  
    .byte <(terrain_data_level_4_C)             // $a919  
    .byte <(terrain_data_level_5_C)             // $a91a  
terrain_right_wall_counter_ptrs_HI:
    .byte >(terrain_data_level_0_C)             // $a91b  
    .byte >(terrain_data_level_1_C)             // $a91c  
    .byte >(terrain_data_level_2_C)             // $a91d  
    .byte >(terrain_data_level_3_C)             // $a91e  
    .byte >(terrain_data_level_4_C)             // $a91f  
    .byte >(terrain_data_level_5_C)             // $a920  
terrain_right_wall_increment_ptrs_LO:
    .byte <(terrain_data_level_0_D)             // $a921  
    .byte <(terrain_data_level_1_D)             // $a922  
    .byte <(terrain_data_level_2_D)             // $a923  
    .byte <(terrain_data_level_3_D)             // $a924  
    .byte <(terrain_data_level_4_D)             // $a925  
    .byte <(terrain_data_level_5_D)             // $a926  
terrain_right_wall_increment_ptrs_HI:
    .byte >(terrain_data_level_0_D)             // $a927  
    .byte >(terrain_data_level_1_D)             // $a928  
    .byte >(terrain_data_level_2_D)             // $a929  
    .byte >(terrain_data_level_3_D)             // $a92a  
    .byte >(terrain_data_level_4_D)             // $a92b  
    .byte >(terrain_data_level_5_D)             // $a92c  
level_colour_terrain:
    .byte $02,$05,$03,$0e,$08,$04               // $a92d  
level_colour_mc1:
    .byte $07,$07,$07,$07,$07,$07               // $a933  
level_colour_mc3:
    .byte $05,$02,$0d,$05,$0a,$03               // $a939  
level_colour_status:
    .byte $05,$03,$05,$03,$02,$03               // $a93f  
level_colour_objects:
    .byte $05,$0e,$08,$02,$03,$0a               // $a945  
level_colour_shield:
    .byte $03,$08,$05,$0a,$0d,$02               // $a94b  
palette_set_colour_Y_to_A:
    rts                                         // $a951  
unused_a952:
    .byte $48,$a9,$13,$98,$68,$a9,$00,$60,$00,$20,$80,$a0  // $a952  
level_obj_pos_X_lookup:
    .word level_0_obj_pos_X                     // $a95e  
    .word level_1_obj_pos_X                     // $a960  
    .word level_2_obj_pos_X                     // $a962  
    .word level_3_obj_pos_X                     // $a964  
    .word level_4_obj_pos_X                     // $a966  
    .word level_5_obj_pos_X                     // $a968  
level_obj_pos_Y_lookup:
    .word level_0_obj_pos_Y                     // $a96a  
    .word level_1_obj_pos_Y                     // $a96c  
    .word level_2_obj_pos_Y                     // $a96e  
    .word level_3_obj_pos_Y                     // $a970  
    .word level_4_obj_pos_Y                     // $a972  
    .word level_5_obj_pos_Y                     // $a974  
level_obj_pos_Y_EXT_lookup:
    .word level_0_obj_pos_Y_EXT                 // $a976  
    .word level_1_obj_pos_Y_EXT                 // $a978  
    .word level_2_obj_pos_Y_EXT                 // $a97a  
    .word level_3_obj_pos_Y_EXT                 // $a97c  
    .word level_4_obj_pos_Y_EXT                 // $a97e  
    .word level_5_obj_pos_Y_EXT                 // $a980  
level_obj_type_lookup:
    .word level_0_obj_type                      // $a982  
    .word level_1_obj_type                      // $a984  
    .word level_2_obj_type                      // $a986  
    .word level_3_obj_type                      // $a988  
    .word level_4_obj_type                      // $a98a  
    .word level_5_obj_type                      // $a98c  
level_gun_param_lookup:
    .word level_0_gun_param                     // $a98e  
    .word level_1_gun_param                     // $a990  
    .word level_2_gun_param                     // $a992  
    .word level_3_gun_param                     // $a994  
    .word level_4_gun_param                     // $a996  
    .word level_5_gun_param                     // $a998  
