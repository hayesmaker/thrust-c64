// ============================================================================
// THRUST (Commodore 64) - Firebird, 1986
// Game by Jeremy C. Smith, music by Rob Hubbard.
// Commented disassembly for KickAssembler 5.x
//
// Build:   ./build.sh   (java -jar KickAss.jar src/thrust.asm -odir ../build)
// Result:  byte-identical to the unpacked original (orig/thrust_unpacked.prg)
//
// Files:   thrust.asm        this file: layout, code, tables
//          levels.asm        terrain + object data       (see docs/level_format.md)
//          level_tables.asm  restart points, gravity, pointers, colours
//          music.asm         Rob Hubbard music driver + theme
//          sprites.asm       sprite graphics
//
// The PRG loads at $0801 and is started with SYS 27684 ($6C24). Most of the
// program is then relocated: each section below is assembled at its LOAD address
// but labelled with its RUNTIME address via .pseudopc.
//
//    load $1000-$1FFF  -> $1000  terrain + object tables, levels.asm (runs in place;
//                                thrusty-levels: moved out of the main block)
//    load $2000-$2FFF  -> $2000  music driver (runs in place)
//    load $3000-$3002  -> $3000  JMP music_driver (runs in place)
//    load $3003-$6C23  -> $8283  main game code + data (relocator copies $3000-$6CFF to $8280)
//    load $6C24-$6C54  -> $6C24  entry point / relocator (runs in place)
//    load $6C55-$7954  -> $4000  sprite graphics (VIC bank 1)
//    init copies sub-blocks of the main code to $0100, $0400, $0880-$09BF, $0E00.
//
// Every address in the comments ($xxxx) is the RUNTIME address - use it with the
// VICE monitor (build/thrust.vs has all labels). Names and many comments of the
// game logic come from the BBC Micro disassembly by Kieran HJ Connell; the C64
// specific parts (VIC, sprites, raster interrupts, SID, keyboard) are new.
// ============================================================================

// The relocator copies everything from music_stub_load ($3000) upwards to $8280
.label RELOC_OFFSET = $8280 - $3000

// ----------------------------------------------------------------------------
// Constants
// ----------------------------------------------------------------------------
.const KEY_RETURN                     = $01     // fire
.const KEY_F7                         = $03     // resume
.const INITIAL_LIVES                  = $04     // starting number of lives
.const KEY_F1                         = $04     // sound off
.const PLAYER_CENTRE_X_OFFSET         = $04     // X offset to centre of player sprite
.const KEY_F3                         = $05     // sound on
.const PLAYER_CENTRE_Y_OFFSET         = $05     // Y offset to centre of player sprite
.const KEY_F5                         = $06     // pause
.const KEY_A                          = $0a     // rotate left
.const PLANET_COUNTDOWN_SECONDS       = $0a     // planet countdown timer in seconds
.const KEY_S                          = $0d     // rotate right
.const KEY_LSHIFT                     = $0f     // thrust
.const ANGLE_DOWN                     = $10     // ship angle pointing straight down
.const INITIAL_FUEL                   = $10     // starting fuel value (BCD 1000)
.const ANGLE_MASK                     = $1f     // bitmask for angle wrapping (0-31)
.const LEVEL_MAX_OBJECTS              = $1f     // max object index per level (32 objects)
.const ASCII_0                        = $30     // digit 0
.const KEY_RSHIFT                     = $34     // thrust
.const SCREEN_ADDR_HI_OFFSET          = $38     // high byte offset for screen address calculation
.const KEY_SPACE                      = $3c     // shield / tractor beam, start game
.const POD_DESTROY_TIMER_INIT         = $3c     // pod destroying player timer initial value (60 ticks)
.const KEY_RUN_STOP                   = $3f     // abort game
.const TRACTOR_BEAM_ACTIVATE_DIST     = $75     // distance threshold to activate tractor beam
.const TRACTOR_BEAM_ATTACH_DIST       = $84     // distance threshold to attach pod

// ----------------------------------------------------------------------------
// Zero page
// ----------------------------------------------------------------------------
.label planet_explode_anim            = $02     // initialised to $F and decrements to 0
.label window_ypos_INT                = $03     // y position of window into world coordinates that is drawn on screen
.label window_ypos_EXT                = $04     // "
.label window_scroll_x                = $05     // *think* this is the scroll offset in x for the window
.label window_scroll_y                = $06     // *think* this is the scroll offset in y for the window
.label midpoint_xpos_FRAC_LO          = $07     // fractional part - additional lower 8 bits
.label midpoint_xpos_FRAC             = $08     // calculated as player_pos + nearest_obj_pos / 2
.label midpoint_xpos_INT              = $09     // all physics calculations are performed on the mid-point
.label midpoint_ypos_FRAC             = $0a     // once the ship and pod are attached
.label midpoint_ypos_INT              = $0b     // integer part
.label midpoint_ypos_INT_HI           = $0c     // integer part - additional upper 8 bits
.label ship_angle                     = $0d     // $00 = up, $10 = down, $1F = max angle
.label old_plot_ship_sprite_number    = $11     // remembers plot_ship_sprite_number
.label velocity_vectorx_FRAC_LO       = $12     // X velocity vector, extra low precision byte
.label velocity_vectorx_FRAC          = $13     // X velocity vector, fractional part
.label velocity_vectorx_INT           = $14     // X velocity vector, integer part
.label velocity_vectory_FRAC          = $15     // set to gravity_FRAC in ship_input_thrust_calculate_force
.label velocity_vectory_INT           = $16     // set to gravity_INT in ship_input_thrust_calculate_force
.label pod_sprite_plotted_flag        = $17     // set to 1 as plot_pod_sprite is called
.label ship_sprite_plotted_flag       = $18     // set to 1 when ship sprite has been plotted
.label level_tick_counter             = $19     // increments every tick loop
.label vsync_count                    = $1a     // incremented by the top-of-frame raster interrupt
.label tether_angle_LO                = $1b     // tether angle, extra precision low byte
.label tether_angle_FRAC              = $1c     // tether angle, fractional part (sub-angle for interpolation)
.label angle_ship_to_pod              = $1d     // tether angle, integer part (0-31 index into trig tables)
.label tether_angular_vel_LO          = $1e     // tether angular velocity, extra precision low byte
.label tether_angular_vel_FRAC        = $1f     // tether angular velocity, fractional part
.label tether_angular_vel_INT         = $20     // tether angular velocity, integer/sign part
.label pod_attached_flag_1            = $22     // set to non-zero at top of attach_pod_to_ship function
.label midpoint_deltax_FRAC           = $23     // add midpoint_delta to midpoint to get ship_position
.label midpoint_deltax_INT            = $24     // subtract midpoint_delta from midpoint to get pod_position
.label midpoint_deltay_FRAC           = $25     // " (fractional part)
.label midpoint_deltay_INT            = $26     // " (integer part)
.label shield_tractor_pressed         = $27     // non-zero when space is pressed
.label sheild_tractor_flag            = $28     // may still be zero when space is pressed!
.label plot_ship_collision_detected   = $2a     // set in plot_ship function
.label plot_pod_collision_detected    = $2b     // set in plot_pod_sprite function
.label player_pressed_fire            = $2c     // non-zero when fire key is pressed
.label bullet_index                   = $2d     // can only have 4 bullets active at one time
.label player_ypos_FRAC               = $2e     // calculated by adding midpoint_delta to midpoint_position
.label player_ypos_INT                = $2f     // "
.label player_ypos_INT_HI             = $30     // "
.label old_midpoint_xpos_FRAC_LO      = $31     // remembers temp_midpoint_xpos_FRAC_LO
.label player_xpos_FRAC               = $32     // (as above)
.label player_xpos_INT                = $33     // (as above)
.label player_velocityy_FRAC          = $34     // calculated in calculate_player_position_from_midpoint
.label player_velocityy_INT           = $35     // used to add player velocity to bullets when firing
.label player_velocityy_INT_HI        = $36     // "
.label diff_midpoint_xpos_FRAC_LO     = $37     // **UNUSED** ?
.label player_velocityx_FRAC          = $38     // (as above)
.label player_velocityx_INT           = $39     // (as above)
.label rnd_A                          = $3a     // used by rnd function
.label rnd_B                          = $3b     // used by rnd function
.label collecting_fuel_flag           = $3c     // set to 1 if using tractor beam near fuel object
.label generator_recharge_counter     = $3d     // number of ticks to recharge generator.  Guns do not fire while generator is temporarily damaged
.label generator_total_damage         = $3e     // permanent accumulated reactor damage.
.label player_ship_destroyed_flag     = $42     // set to $FF during init, 0 or 1 at other times
.label level_ended_flag               = $43     // set to 0 each tick, set to $FF in one place - suspect collision / death?
.label pod_destroying_player_timer    = $44     // set to $FF during init, otherwise counts down during explode?
.label pod_line_exists_flag           = $45     // related to tractor_beam_started_flag
.label line_drawn_flag                = $4a     // 0 or $FF set in draw_new_line, unset in erase_old_line
.label midpoint_window_xpos_INT       = $4b     // calculated in update_window_and_terrain_tables
.label midpoint_window_ypos_INT       = $4c     // "
.label midpoint_deltax_FRAC_LO        = $4d     // "
.label ship_window_xpos_FRAC          = $4e     // calculated in update_shield_tractor_draw_ship_and_pod
.label ship_window_xpos_INT           = $4f     // *think* these are relative to the window position
.label ship_window_ypos_INT           = $50     // i.e. screen coordinates not world
.label pod_window_xpos_FRAC           = $51     // *think* these are relative to the window position
.label pod_window_xpos_INT            = $52     // i.e. screen coordinates not world
.label pod_window_ypos_INT            = $53     // "
.label tether_length                  = $54     // initialised to $E (14) and decremented by 2 when the ship+pod dies; used to index lookup_top_nibble
.label fuel_beam_position_flag        = $55     // set & unset in tick_fuel_pickup_draw_beams
.label fuel_value_updated_flag        = $56     // when zero indicates fuel value needs to be updated on screen
.label fuel_just_ran_out_flag         = $57     // set moment player runs out of fuel
.label old_player_xpos_FRAC           = $58     // remembers player_xpos_FRAC
.label old_player_xpos_INT            = $59     // remembers player_xpos_INT
.label old_player_ypos_INT            = $5a     // remembers player_ypos_INT
.label old_player_ypos_INT_HI         = $5b     // remembers player_ypos_INT_HI
.label pod_xpos_FRAC                  = $5c     // calculated in calculate_pod_pos
.label pod_xpos_INT                   = $5d     // "
.label pod_ypos_FRAC                  = $5e     // "
.label pod_ypos_INT_HI                = $5f     // "
.label level_tick_state               = $61     // set to 1 when paused, 0 when running, $FF when initialising
.label window_xpos_INT                = $62     // x position of window into world coordinates that is drawn on screen
.label demo_mode_flag                 = $63     // 0 = real game, non-zero = demo mode
.label nearest_obj_xpos_FRAC          = $64     // calculated in calculate_object_plot_addr
.label nearest_obj_xpos_INT           = $65     // "
.label nearest_obj_ypos_INT           = $66     // "
.label nearest_obj_ypos_INT_HI        = $67     // "
.label tractor_beam_started_flag      = $68     // related to pod_line_exists_flag
.label countdown_timer_ticks          = $69     // used to time between countdown timer seconds
.label planet_countdown_timer         = $6a     // set to $FF or $A on countdown
.label door_switch_counter_A          = $6b     // used in level door logic
.label door_switch_counter_B          = $6c     // "
.label band_next_raster               = $70
.label boot_read_ptr                  = $70
.label calc_velocity_vectory_FRAC     = $70
.label draw_line_delta_x              = $70
.label pixel_colour_mask              = $70
.label plot_pod_xpos_FRAC             = $70
.label ship_spr_x_calc                = $70
.label temp_midpoint_xpos_FRAC_LO     = $70
.label terrain_pixel_byte             = $70
.label terrain_y_count_inner          = $70
.label value_LO                       = $70
.label band_sprite_count              = $71
.label best_distance                  = $71
.label calc_velocity_vectory_INT      = $71
.label draw_line_delta_y_unused       = $71
.label new_ship_xpos_FRAC             = $71
.label particle_screen_x              = $71
.label plot_pod_xpos_INT              = $71
.label terrain_y_count_outer          = $71
.label value_HI                       = $71
.label boot_write_ptr                 = $72
.label build_list_pos                 = $72
.label calc_velocity_vectorx_FRAC     = $72
.label delta_x_scaled                 = $72
.label gfx_copy_dst_ptr               = $72
.label new_ship_xpos_INT              = $72
.label particle_screen_y              = $72
.label plot_pixels_ptr                = $72
.label terrain_draw_ptr               = $72
.label terrain_draw_start_x           = $72
.label attach_pod_delta_y_scaled      = $73
.label calc_velocity_vectorx_INT      = $73
.label new_ship_ypos_FRAC             = $73
.label obj_screen_x                   = $73
.label raster_build_pos               = $73
.label attach_pod_delta_x_frac        = $74
.label new_ship_ypos_INT              = $74
.label obj_screen_y                   = $74
.label particle_write_ptr             = $74
.label pixel_column_index             = $74
.label terrain_draw_wall_index        = $74
.label delta_x_shifted                = $75
.label draw_line_delta_major          = $75
.label new_ship_ypos_INT_HI           = $75
.label obj_screen_y_hi                = $75
.label delta_y_frac                   = $76
.label draw_line_delta_minor          = $76
.label explosion_dx_FRAC              = $76
.label particle_pixel_byte            = $76
.label plot_ship_sprite_number        = $76
.label rnd_AND_3                      = $76
.label score_value                    = $76
.label terrain_draw_addr_LO           = $76
.label calc_ship_window_xpos_INT      = $77
.label delta_y_shifted                = $77
.label explosion_dx_INT               = $77
.label particle_temp_clear_77         = $77
.label terrain_draw_addr_HI           = $77
.label bresenham_error                = $78
.label explosion_dy_FRAC              = $78
.label search_inner_count             = $78
.label ship_spr_y_calc                = $78
.label ship_thrust_x_INT              = $78
.label terrain_xpos_1_clipped         = $78
.label explosion_dy_INT               = $79
.label particle_temp_clear_79         = $79
.label screen_addr_hi_temp            = $79
.label ship_window_ypos_FRAC          = $79
.label terrain_xpos_2_clipped         = $79
.label thrust_sign_extend             = $79
.label angle_step_frac                = $7a
.label current_object                 = $7a
.label pod_angle_sub_frac             = $7a
.label ship_thrust_x_FRAC             = $7a
.label angle_step_int                 = $7b
.label calc_ship_delta_FRAC           = $7b
.label particle_collision_flag        = $7b
.label pod_temp                       = $7b
.label prev_tether_vel_FRAC           = $7b
.label teleport_row_count             = $7b
.label terrain_draw_table_index       = $7b
.label calc_ship_delta_INT            = $7c
.label prev_tether_vel_INT            = $7c
.label search_iterations              = $7c
.label current_obj_xpos_INT           = $7d
.label prev_tether_vel_LO             = $7d
.label current_obj_ypos_INT           = $7e
.label player_to_particle_deltay_INT  = $7e
.label temp_angle_ship_to_pod         = $7e
.label thrust_angle_sub_frac          = $7e
.label calc_velocity_vectorx_FRAC_LO  = $7f
.label current_obj_ypos_EXT           = $7f
.label explosion_particle_count       = $7f
.label add_score_thousands            = $80
.label clear_screen_ptr               = $80
.label colour_ptr_A                   = $80
.label copy_src_ptr                   = $80
.label high_score_ptr_A               = $80
.label level_reset_ptr                = $80
.label old_plot_pixels_ptr            = $80
.label plot_string_ptr                = $80
.label relocate_src_ptr               = $80
.label window_deltax_INT              = $80
.label current_object_width           = $81
.label door_screen_ypos               = $81
.label colour_ptr_B                   = $82
.label copy_dst_ptr                   = $82
.label current_object_height          = $82
.label high_score_ptr_B               = $82
.label level_reset_ptr2               = $82
.label plot_high_score_number         = $82
.label relocate_dest_ptr              = $82
.label teleport_screen_addr_LO        = $82
.label object_type                    = $83
.label teleport_screen_addr_HI        = $83
.label colour_pages                   = $84
.label copy_dst2_ptr                  = $84
.label gun_base_angle                 = $84
.label high_score_counter             = $84
.label level_reset_size               = $84
.label old_pixel_column_index         = $84
.label current_obj_visible_flag       = $85
.label high_score_ptr_C               = $85
.label gun_angle_spread_mask          = $86
.label high_score_ptr_C_HI            = $86
.label teleport_ring_count            = $86
.label score_accumulation             = $87
.label teleport_appear_or_disappear   = $87
.label draw_line_start_x              = $88
.label explosion_xpos_FRAC            = $88
.label multiply_operand_a             = $88
.label draw_line_start_y              = $89
.label explosion_xpos_INT             = $89
.label multiply_result_lo             = $89
.label draw_line_end_x                = $8a
.label explosion_ypos_INT             = $8a
.label multiply_result_hi             = $8a
.label draw_line_end_y                = $8b
.label explosion_ypos_INT_HI          = $8b
.label multiply_operand_b             = $8b
.label explosion_angle                = $8c
.label multiply_sign_ext              = $8c
.label explosion_particle_type        = $8d
.label cross_product_term_lo          = $8e
.label cross_product_term_hi          = $8f
.label wait_frames                    = $8f
.label terrain_data_x_increment_ptr   = $9d     // pointer to terrain x increment data for level
.label terrain_data_count_ptr         = $9f     // pointer to terrain count data for level
.label irq1_timer1_signal             = $a1     // BBC timer flag, only cleared on the C64
.label mute_sound_flag                = $a2     // set to non-zero to mute sound
.label hostile_gun_shoot_probability  = $a3     // probability that a gun will shoot
.label total_levels_played            = $a4     // total number of levels played in one game
.label invisible_landscape_flag       = $a5     // game var init 0 - inverted start of each level
.label gravity_INT                    = $a6     // gravity vector for level (integer part)
.label gravity_FRAC                   = $a7     // " (fractional part)
.label spr_frame                      = $a8     // sprite to add: frame (sprite pointer)
.label spr_colour                     = $a9     // sprite to add: colour
.label spr_x_lo                       = $aa     // sprite to add: X (low 8 bits)
.label spr_x_hi                       = $ab     // sprite to add: X bit 8 / $FF = do not draw
.label spr_y                          = $ac     // sprite to add: Y
.label irq_table_index                = $ad     // offset of current entry in raster_table ($0E00)
.label irq_sprite_index               = $ae
.label sprite_list_len                = $af
.label raster_table_len               = $b0
.label irq_band_skip                  = $b1
.label irq_hw_sprite                  = $b2
.label irq_band_rotate                = $b3
.label sprite_band_count_pos          = $b4
.label text_ptr                       = $b5
.label text_ptr_HI                    = $b6
.label music_track_ptr                = $e0
.label music_track_ptr_HI             = $e1
.label music_pattern_ptr              = $e2
.label music_pattern_ptr_HI           = $e3
.label music_vib_counter              = $e4
.label music_vib_direction            = $e7
.label music_vib_range                = $ea
.label music_vib_freq_lo              = $ed
.label music_vib_freq_hi              = $ee
.label music_vib_step_lo              = $ef
.label music_vib_step_hi              = $f0
.label music_note_nr                  = $f1
.label music_pulse_dir                = $f4
.label music_pulse_delay              = $f7
.label music_voice_reg                = $fa
.label char_write_ptr_LO              = $fb     // address fonts are plotted to the screen
.label char_write_ptr_HI              = $fc     // "
.label key_bits                       = $fd

// ----------------------------------------------------------------------------
// RAM work areas, hardware registers and KERNAL (outside the program image)
// ----------------------------------------------------------------------------
.label score_A                        = $0180   // score, 3 bytes BCD
.label score_B                        = $0181
.label score_C                        = $0182
.label CINV                           = $0314
.label CINV_HI                        = $0315
.label CBINV                          = $0316
.label CBINV_HI                       = $0317
.label terrain_left_wall              = $0400   // left wall X per world row (256 entries, circular)
.label terrain_right_wall             = $0500   // right wall X per world row
.label particles_xpos_FRAC            = $0600   // particle tables: 32 entries each
.label particles_xpos_INT             = $0620
.label particles_ypos_FRAC            = $0640
.label particles_ypos_INT             = $0660
.label particles_ypos_INT_HI          = $0680
.label particles_dx_FRAC              = $06a0
.label particles_dx_INT               = $06c0
.label particles_dy_FRAC              = $06e0
.label particles_dy_INT               = $0700
.label particles_lifetime             = $0720
.label particles_scraddr_LO           = $0740
.label particles_scraddr_HI           = $0760
.label particles_pixels_byte          = $0780
.label particles_type                 = $07a0
.label sprite_sort_order              = $07c0   // sprite multiplexer: sorted entry offsets
.label obj_tractor_counter            = $07e0   // per-object tractor beam counters
.label old_irq_vector                 = $08c0   // saved KERNAL IRQ vector
.label terrain_draw_table_1           = $09f7   // terrain drawing state (previous frame X per row)
.label terrain_draw_table_2           = $0a00
.label terrain_draw_table_3           = $0a77
.label terrain_draw_table_4           = $0a80
.label column_bitmap_offset_LO        = $0b00   // terrain column -> bitmap byte offset (80 columns)
.label column_bitmap_offset_HI        = $0b50
.label column_pixel_byte              = $0ba0   // terrain column -> pixel pattern ($A0 left / $0A right half)
.label sprite_display_list            = $0c00   // sprite bands being displayed (5 bytes per sprite)
.label sprite_build_list              = $0d00   // sprite bands being built
.label raster_build_table             = $0e80   // raster table being built
.label sprite_entries                 = $0f00   // sprite list: frame, colour, x lo, x hi, y
.label line_sprite_data               = $5300   // tether line sprites (frames $4C-$4F)
.label screen_B                       = $5400   // screen matrix B: playfield colours with invisible terrain
.label sprite_pointers_screen_B       = $57f8
.label screen_A                       = $5c00   // screen matrix A: status bar + playfield colours
.label sprite_pointers_screen_A       = $5ff8
.label VIC_SPR0_X                     = $d000
.label VIC_SPR0_Y                     = $d001
.label VIC_SPR6_X                     = $d00c
.label VIC_SPR6_Y                     = $d00d
.label VIC_SPR7_X                     = $d00e
.label VIC_SPR7_Y                     = $d00f
.label VIC_SPR_X_MSB                  = $d010
.label VIC_CTRL1                      = $d011
.label VIC_RASTER                     = $d012
.label VIC_SPR_ENABLE                 = $d015
.label VIC_CTRL2                      = $d016
.label VIC_SPR_EXPAND_Y               = $d017
.label VIC_MEMSETUP                   = $d018
.label VIC_IRQ_STATUS                 = $d019
.label VIC_IRQ_ENABLE                 = $d01a
.label VIC_SPR_EXPAND_X               = $d01d
.label VIC_SPR_SPR_COLL               = $d01e
.label VIC_SPR_BG_COLL                = $d01f
.label VIC_BORDER                     = $d020
.label VIC_BG0                        = $d021
.label VIC_BG1                        = $d022
.label VIC_BG2                        = $d023
.label VIC_SPR0_COL                   = $d027
.label VIC_SPR6_COL                   = $d02d
.label VIC_SPR7_COL                   = $d02e
.label SID_V1_FREQ_LO                 = $d400
.label SID_V1_FREQ_HI                 = $d401
.label SID_V1_PW_LO                   = $d402
.label SID_V1_PW_HI                   = $d403
.label SID_V1_CTRL                    = $d404
.label SID_V1_AD                      = $d405
.label SID_V1_SR                      = $d406
.label SID_V2_FREQ_LO                 = $d407
.label SID_V2_FREQ_HI                 = $d408
.label SID_V2_PW_LO                   = $d409
.label SID_V2_PW_HI                   = $d40a
.label SID_V2_CTRL                    = $d40b
.label SID_V2_AD                      = $d40c
.label SID_V2_SR                      = $d40d
.label SID_V3_FREQ_LO                 = $d40e
.label SID_V3_FREQ_HI                 = $d40f
.label SID_V3_CTRL                    = $d412
.label SID_V3_AD                      = $d413
.label SID_V3_SR                      = $d414
.label SID_FC_LO                      = $d415
.label SID_FC_HI                      = $d416
.label SID_RES_FILT                   = $d417
.label SID_MODE_VOL                   = $d418
.label COLOR_RAM                      = $d800
.label CIA1_PRA                       = $dc00
.label CIA1_PRB                       = $dc01
.label CIA1_DDRA                      = $dc02
.label CIA1_DDRB                      = $dc03
.label CIA1_TA_LO                     = $dc04
.label CIA1_TA_HI                     = $dc05
.label CIA1_ICR                       = $dc0d
.label CIA1_CRA                       = $dc0e
.label CIA2_PRA                       = $dd00
.label CIA2_DDRA                      = $dd02
.label CIA2_ICR                       = $dd0d
.label CHROUT                         = $ffd2
.label STOP                           = $ffe1

* = $0801 "Thrust"

// ============================================================================
// basic_stub  (load $0801-$0816, runtime $0801-$0816)
// BASIC line: 1987 SYS(27684) KASPER
// "KASPER" is probably a cracker's tag - there is no crack intro in this version
// ============================================================================
basic_stub_load:
    .word basic_end                             // link to next BASIC line
    .word 1987                                  // line number
    .byte $9e, '('                              // SYS(
    .byte '0' + floor(entry / 10000)            // entry address as 5 decimal digits
    .byte '0' + mod(floor(entry / 1000), 10)
    .byte '0' + mod(floor(entry / 100), 10)
    .byte '0' + mod(floor(entry / 10), 10)
    .byte '0' + mod(entry, 10)
    .encoding "petscii_upper"
    .text ") KASPER"
    .byte $00                                   // end of line
basic_end:
    .word $0000                                 // end of program

// ============================================================================
// filler1  (load $0817-$0fff) + level data area (load/runtime $1000-$1fff)
// The cruncher left $0817-$1FFF as filler ($FA). $1000-$1FFF is free at run
// time and is not moved by the relocator, so thrusty-levels keeps the terrain
// and object tables (levels.asm) there: 4 KB for level data instead of the few
// hundred bytes left in the main block. The tables are only reached through
// the pointer tables in level_tables.asm, so they can live anywhere.
// ============================================================================
.const LEVELS_AREA_START = $1000
.const LEVELS_AREA_END   = $2000
filler1_load:
    .fill LEVELS_AREA_START - *, $fa
levels_area:
    #import "levels.asm"
levels_area_end:
    .errorif levels_area_end > LEVELS_AREA_END, "levels.asm is " + (levels_area_end - LEVELS_AREA_END) + " bytes too big for the levels area $" + toHexString(LEVELS_AREA_START) + "-$" + toHexString(LEVELS_AREA_END - 1)
    .fill LEVELS_AREA_END - levels_area_end, $fa

// ============================================================================
// music  (load $2000-$2fff, runtime $2000-$2fff)
// Music / sound effects driver and data. Runs in place.
// ============================================================================
music_load:

    #import "music.asm"

// ============================================================================
// music_stub  (load $3000-$3002, runtime $3000-$3002)
// JMP to the music driver, called each frame via JSR $3000.
// These three bytes are also the first bytes copied by the relocator
// (their copy at $8280 is never used).
// ============================================================================
music_stub_load:
music_play:
    jmp music_driver                            // $3000  

// ============================================================================
// main1  (load $3003-$6492, runtime $8283-$b712)
// Main game code (relocated to $8283-$B712)
// ============================================================================
main1_load:
.pseudopc main1_load + RELOC_OFFSET {
unused_bit_table:
    .byte $00,$40,$20,$10,$08,$04,$02,$01       // $8283  
landscape_draw:
    lda #$00                                    // $828b  
    sta terrain_draw_table_index                // $828d  
    lda #$41                                    // $828f  
    clc                                         // $8291  
    adc terrain_window_y_index                  // $8292  
    sta terrain_draw_wall_index                 // $8295  
    lda #$82                                    // $8297  
    sta terrain_draw_addr_LO                    // $8299  
    lda #$62                                    // $829b  
    sta terrain_draw_addr_HI                    // $829d  
    ldx window_xpos_INT                         // $829f  
    dex                                         // $82a1  
    stx window_xpos_2                           // $82a2  MODIFIES CODE
    stx window_xpos_1                           // $82a5  MODIFIES CODE
    clc                                         // $82a8  
landscape_draw_loop:
    ldy terrain_draw_wall_index                 // $82a9  starts at terrain_window_y_index + $49
    lda terrain_left_wall,y                     // $82ab  
sbc_window_xpos_1:
    .label window_xpos_1 = *+1
    sbc #$00                                    // $82ae  SELF-MODIFIED CODE
    bcs terrain_xpos_1_greater_than_zero        // $82b0  
    lda #$00                                    // $82b2  clamp to 0
    jmp terrain_xpos_1_less_than_screen_width   // $82b4  
terrain_xpos_1_greater_than_zero:
    cmp #$50                                    // $82b7  
    bcc terrain_xpos_1_less_than_screen_width   // $82b9  
    lda #$50                                    // $82bb  
terrain_xpos_1_less_than_screen_width:
    sta terrain_xpos_1_clipped                  // $82bd  
    ldy terrain_draw_table_index                // $82bf  
    sec                                         // $82c1  
    sbc terrain_draw_table_2,y                  // $82c2  number of columns to draw = xpos1 - table2
    bcs terrain_width_1_greater_than_zero       // $82c5  
    eor #$ff                                    // $82c7  negate width to make positive
    tax                                         // $82c9  number of columns to draw
    inx                                         // $82ca  +1
    lda terrain_xpos_1_clipped                  // $82cb  
    sta terrain_draw_table_2,y                  // $82cd  update table_2 for next time?
    tay                                         // $82d0  start X column
    jmp draw_terrain_xpos_1                     // $82d1  draw a line of terrain
terrain_width_1_greater_than_zero:
    clc                                         // $82d4  
    beq landscape_draw_part_2                   // $82d5  nothing to draw
    tax                                         // $82d7  number of columns to draw
    lda terrain_draw_table_2,y                  // $82d8  
    sta terrain_draw_start_x                    // $82db  start X column
    lda terrain_xpos_1_clipped                  // $82dd  
    sta terrain_draw_table_2,y                  // $82df  update table_2 for next time?
    ldy terrain_draw_start_x                    // $82e2  start X column
draw_terrain_xpos_1:
    lda column_bitmap_offset_LO,y               // $82e4  
    sta terrain_draw_start_x                    // $82e7  
    lda column_bitmap_offset_HI,y               // $82e9  
    adc terrain_draw_addr_HI                    // $82ec  
    sta terrain_draw_start_x+1                  // $82ee  
    lda column_pixel_byte,y                     // $82f0  
    sta terrain_pixel_byte                      // $82f3  
    ldy terrain_draw_addr_LO                    // $82f5  
    eor (terrain_draw_start_x),y                // $82f7  
    sta (terrain_draw_start_x),y                // $82f9  
    dex                                         // $82fb  
    beq landscape_draw_part_2                   // $82fc  
    lda terrain_pixel_byte                      // $82fe  
    bmi L8314                                   // $8300  
L8302:
    tya                                         // $8302  
    adc #$08                                    // $8303  
    tay                                         // $8305  
    bcc L830b                                   // $8306  
    clc                                         // $8308  
    inc terrain_draw_ptr+1                      // $8309  
L830b:
    lda #$a0                                    // $830b  
    eor (terrain_draw_start_x),y                // $830d  
    sta (terrain_draw_start_x),y                // $830f  
    dex                                         // $8311  
    beq landscape_draw_part_2                   // $8312  
L8314:
    lda #$0a                                    // $8314  
    eor (terrain_draw_ptr),y                    // $8316  
    sta (terrain_draw_ptr),y                    // $8318  
    dex                                         // $831a  
    bne L8302                                   // $831b  
landscape_draw_part_2:
    ldy terrain_draw_wall_index                 // $831d  
    lda terrain_right_wall,y                    // $831f  
sbc_window_xpos_2:
    .label window_xpos_2 = *+1
    sbc #$00                                    // $8322  SELF-MODIFIED CODE
    bcs terrain_xpos_2_greater_than_zero        // $8324  
    lda #$00                                    // $8326  clamp to 0
    jmp terrain_xpos_2_less_than_screen_width   // $8328  
terrain_xpos_2_greater_than_zero:
    cmp #$50                                    // $832b  
    bcc terrain_xpos_2_less_than_screen_width   // $832d  
    lda #$50                                    // $832f  
terrain_xpos_2_less_than_screen_width:
    sta terrain_xpos_2_clipped                  // $8331  
    ldy terrain_draw_table_index                // $8333  
    sec                                         // $8335  
    sbc terrain_draw_table_4,y                  // $8336  
    bcs terrain_width_2_greater_than_zero       // $8339  
    eor #$ff                                    // $833b  negate width to make positive
    tax                                         // $833d  number columns to draw
    inx                                         // $833e  +1
    lda terrain_xpos_2_clipped                  // $833f  
    sta terrain_draw_table_4,y                  // $8341  
    tay                                         // $8344  start X column
    jmp draw_terrain_xpos_2                     // $8345  
terrain_width_2_greater_than_zero:
    clc                                         // $8348  
    beq landscape_increment_index               // $8349  nothing to draw
    tax                                         // $834b  number columns to draw
    lda terrain_draw_table_4,y                  // $834c  
    sta terrain_draw_start_x                    // $834f  start X column
    lda terrain_xpos_2_clipped                  // $8351  
    sta terrain_draw_table_4,y                  // $8353  update table 4?
    ldy terrain_draw_start_x                    // $8356  start X column
draw_terrain_xpos_2:
    lda column_bitmap_offset_LO,y               // $8358  
    sta terrain_draw_start_x                    // $835b  
    lda column_bitmap_offset_HI,y               // $835d  
    adc terrain_draw_addr_HI                    // $8360  
    sta terrain_draw_start_x+1                  // $8362  
    lda column_pixel_byte,y                     // $8364  
    sta terrain_pixel_byte                      // $8367  
    ldy terrain_draw_addr_LO                    // $8369  
    eor (terrain_draw_start_x),y                // $836b  
    sta (terrain_draw_start_x),y                // $836d  
    dex                                         // $836f  
    beq landscape_increment_index               // $8370  
    lda terrain_pixel_byte                      // $8372  
    bmi L8388                                   // $8374  
L8376:
    tya                                         // $8376  
    adc #$08                                    // $8377  
    tay                                         // $8379  
    bcc L837f                                   // $837a  
    clc                                         // $837c  
    inc terrain_draw_ptr+1                      // $837d  
L837f:
    lda #$a0                                    // $837f  
    eor (terrain_draw_start_x),y                // $8381  
    sta (terrain_draw_start_x),y                // $8383  
    dex                                         // $8385  
    beq landscape_increment_index               // $8386  
L8388:
    lda #$0a                                    // $8388  
    eor (terrain_draw_ptr),y                    // $838a  
    sta (terrain_draw_ptr),y                    // $838c  
    dex                                         // $838e  
    bne L8376                                   // $838f  
landscape_increment_index:
    inc terrain_draw_wall_index                 // $8391  
    inc terrain_draw_table_index                // $8393  
landscape_increment_draw_addr:
    lda terrain_draw_addr_LO                    // $8395  
    adc #$02                                    // $8397  only draw every other line
    sta terrain_draw_addr_LO                    // $8399  
    and #$07                                    // $839b  
    beq landscape_draw_next_character_row       // $839d  
    jmp landscape_draw_loop                     // $839f  
landscape_draw_next_character_row:
    lda terrain_draw_addr_LO                    // $83a2  
    adc #$38                                    // $83a4  
    sta terrain_draw_addr_LO                    // $83a6  
    lda terrain_draw_addr_HI                    // $83a8  
    adc #$01                                    // $83aa  
    sta terrain_draw_addr_HI                    // $83ac  
    bmi landscape_draw_return                   // $83ae  
    jmp landscape_draw_loop                     // $83b0  
landscape_draw_return:
    rts                                         // $83b3  
initialise_landscape:
    ldx #$01                                    // $83b4  
    stx terrain_left_wall_2_index               // $83b6  
    stx terrain_right_wall_2_index              // $83b9  
    dex                                         // $83bc  
    stx terrain_window_y_index                  // $83bd  
    stx terrain_left_wall_1_xpos                // $83c0  
    stx terrain_left_wall_2_xpos                // $83c3  
    stx terrain_left_wall_1_index               // $83c6  
    stx terrain_right_wall_1_index              // $83c9  
    dex                                         // $83cc  
    stx terrain_left_wall_1_counter             // $83cd  
    stx terrain_right_wall_1_counter            // $83d0  
    stx terrain_right_wall_1_xpos               // $83d3  
    stx terrain_right_wall_2_xpos               // $83d6  
    stx terrain_left_wall_2_counter             // $83d9  
    stx terrain_right_wall_2_counter            // $83dc  
    lda window_ypos_INT                         // $83df  
    sta terrain_y_count_inner                   // $83e1  
    lda window_ypos_EXT                         // $83e3  
    sta terrain_y_count_outer                   // $83e5  
    inc terrain_y_count_inner                   // $83e7  
    inc terrain_y_count_outer                   // $83e9  
    inc terrain_y_count_outer                   // $83eb  
    bne terrain_y_count_outer_not_zero          // $83ed  
initialise_landscape_loop:
    jsr terrain_process_accumulate_xpos         // $83ef  
terrain_y_count_outer_not_zero:
    dec terrain_y_count_inner                   // $83f2  
    bne initialise_landscape_loop               // $83f4  
    dec terrain_y_count_outer                   // $83f6  
    bne initialise_landscape_loop               // $83f8  
    rts                                         // $83fa  
terrain_call_process_fn:
    .label terrain_call_process_fn_JMP_LO = *+1
    .label terrain_call_process_fn_JMP_HI = *+2
    jmp terrain_call_process_fn_JMP_LO          // $83fb  SELF-MODIFIED CODE
terrain_process_subtract_xpos:
    lda #<terrain_subtract_xpos_fn              // $83fe  
    sta terrain_call_process_fn_JMP_LO          // $8400  MODIFIES CODE
    lda #>terrain_subtract_xpos_fn              // $8403  
    sta terrain_call_process_fn_JMP_HI          // $8405  MODIFIES CODE
    dec terrain_window_y_index                  // $8408  
    jsr terrain_process                         // $840b  
    rts                                         // $840e  
terrain_process_accumulate_xpos:
    lda #<terrain_accumulate_xpos_fn            // $840f  
    sta terrain_call_process_fn_JMP_LO          // $8411  MODIFIES CODE
    lda #>terrain_accumulate_xpos_fn            // $8414  
    sta terrain_call_process_fn_JMP_HI          // $8416  MODIFIES CODE
    inc terrain_window_y_index                  // $8419  
terrain_process:
    lda terrain_left_wall_counter_LO            // $841c  
    sta terrain_data_count_ptr                  // $841f  
    lda terrain_left_wall_counter_HI            // $8421  
    sta terrain_data_count_ptr+1                // $8424  
    lda terrain_left_wall_increment_LO          // $8426  
    sta terrain_data_x_increment_ptr            // $8429  
    lda terrain_left_wall_increment_HI          // $842b  
    sta terrain_data_x_increment_ptr+1          // $842e  
    lda terrain_left_wall_1_xpos                // $8430  
    ldx terrain_left_wall_1_counter             // $8433  
    ldy terrain_left_wall_1_index               // $8436  
    jsr terrain_call_process_fn                 // $8439  
    sty terrain_left_wall_1_index               // $843c  
    stx terrain_left_wall_1_counter             // $843f  
    ldy terrain_window_y_index                  // $8442  
    sta terrain_left_wall,y                     // $8445  
    sta terrain_left_wall_1_xpos                // $8448  
    lda terrain_left_wall_2_xpos                // $844b  
    ldx terrain_left_wall_2_counter             // $844e  
    ldy terrain_left_wall_2_index               // $8451  
    jsr terrain_call_process_fn                 // $8454  
    sty terrain_left_wall_2_index               // $8457  
    stx terrain_left_wall_2_counter             // $845a  
    ldy terrain_window_y_index                  // $845d  
    dey                                         // $8460  
    sta terrain_left_wall,y                     // $8461  
    sta terrain_left_wall_2_xpos                // $8464  
    lda terrain_right_wall_counter_LO           // $8467  
    sta terrain_data_count_ptr                  // $846a  
    lda terrain_right_wall_counter_HI           // $846c  
    sta terrain_data_count_ptr+1                // $846f  
    lda terrain_right_wall_increment_LO         // $8471  
    sta terrain_data_x_increment_ptr            // $8474  
    lda terrain_right_wall_increment_HI         // $8476  
    sta terrain_data_x_increment_ptr+1          // $8479  
    lda terrain_right_wall_1_xpos               // $847b  
    ldx terrain_right_wall_1_counter            // $847e  
    ldy terrain_right_wall_1_index              // $8481  
    jsr terrain_call_process_fn                 // $8484  
    sty terrain_right_wall_1_index              // $8487  
    stx terrain_right_wall_1_counter            // $848a  
    ldy terrain_window_y_index                  // $848d  
    sta terrain_right_wall,y                    // $8490  
    sta terrain_right_wall_1_xpos               // $8493  
    lda terrain_right_wall_2_xpos               // $8496  
    ldx terrain_right_wall_2_counter            // $8499  
    ldy terrain_right_wall_2_index              // $849c  
    jsr terrain_call_process_fn                 // $849f  
    sty terrain_right_wall_2_index              // $84a2  
    stx terrain_right_wall_2_counter            // $84a5  
    ldy terrain_window_y_index                  // $84a8  
    dey                                         // $84ab  
    sta terrain_right_wall,y                    // $84ac  
    sta terrain_right_wall_2_xpos               // $84af  
    rts                                         // $84b2  
terrain_window_y_index:
    .byte $00                                   // $84b3  
terrain_left_wall_1_xpos:
    .byte $00                                   // $84b4  
terrain_left_wall_1_counter:
    .byte $00                                   // $84b5  
terrain_left_wall_1_index:
    .byte $00                                   // $84b6  
terrain_left_wall_2_xpos:
    .byte $00                                   // $84b7  
terrain_left_wall_2_counter:
    .byte $00                                   // $84b8  
terrain_left_wall_2_index:
    .byte $00                                   // $84b9  
terrain_right_wall_1_xpos:
    .byte $00                                   // $84ba  
terrain_right_wall_1_counter:
    .byte $00                                   // $84bb  
terrain_right_wall_1_index:
    .byte $00                                   // $84bc  
terrain_right_wall_2_xpos:
    .byte $00                                   // $84bd  
terrain_right_wall_2_counter:
    .byte $00                                   // $84be  
terrain_right_wall_2_index:
    .byte $00                                   // $84bf  
terrain_left_wall_counter_LO:
    .byte $00                                   // $84c0  
terrain_left_wall_counter_HI:
    .byte $00                                   // $84c1  
terrain_left_wall_increment_LO:
    .byte $00                                   // $84c2  
terrain_left_wall_increment_HI:
    .byte $00                                   // $84c3  
terrain_right_wall_counter_LO:
    .byte $00                                   // $84c4  
terrain_right_wall_counter_HI:
    .byte $00                                   // $84c5  
terrain_right_wall_increment_LO:
    .byte $00                                   // $84c6  
terrain_right_wall_increment_HI:
    .byte $00                                   // $84c7  
terrain_accumulate_xpos_fn:
    cpx #$00                                    // $84c8  
    bne terrain_accumulate_xpos_fn_counter_not_zero  // $84ca  
    iny                                         // $84cc  increment index into table
    pha                                         // $84cd  keep accumulator
    lda (terrain_data_count_ptr),y              // $84ce  read new count value from table
    tax                                         // $84d0  store new counter
    pla                                         // $84d1  restore accumulated x
terrain_accumulate_xpos_fn_counter_not_zero:
    clc                                         // $84d2  
    adc (terrain_data_x_increment_ptr),y        // $84d3  add x increment to accumulated x from table
    dex                                         // $84d5  decrement counter
    rts                                         // $84d6  
terrain_subtract_xpos_fn:
    inx                                         // $84d7  
    sec                                         // $84d8  
    sbc (terrain_data_x_increment_ptr),y        // $84d9  
    pha                                         // $84db  
    lda (terrain_data_count_ptr),y              // $84dc  
    sta terrain_y_count_inner                   // $84de  
    cpx terrain_y_count_inner                   // $84e0  
    bne terrain_subtract_xpos_fn_counter_not_zero  // $84e2  
    dey                                         // $84e4  
    ldx #$00                                    // $84e5  
terrain_subtract_xpos_fn_counter_not_zero:
    pla                                         // $84e7  
    rts                                         // $84e8  
obj_colour_gun:
    .byte $07                                   // $84e9  
obj_colour_fuel:
    .byte $07                                   // $84ea  
obj_colour_fuel_2:
    .byte $07                                   // $84eb  
obj_colour_pod_stand:
    .byte $07                                   // $84ec  
obj_colour_generator:
    .byte $07                                   // $84ed  
obj_colour_generator_2:
    .byte $07                                   // $84ee  
obj_colour_door_switch:
    .byte $07                                   // $84ef  
objects_processed:
    .byte $00                                   // $84f0  
obj_type_width:
    .byte $05,$05,$05,$05,$04,$05,$05,$02,$02   // $84f1  
obj_type_height:
    .byte $08,$08,$08,$08,$0a,$08,$0a,$08,$08   // $84fa  
obj_type_explosion_particle:
    .byte $02,$02,$02,$02,$01                   // $8503  
obj_type_score_value:
    .byte $75,$75,$75,$75,$15                   // $8508  
end_of_objects_function:
    lda score_accumulation                      // $850d  
    beq L8514                                   // $850f  
skip_add_score:
    jsr add_A_to_score                          // $8511  
L8514:
    lda level_tick_counter                      // $8514  
    and #$01                                    // $8516  
    bne skip_dec_generator                      // $8518  
    lda generator_recharge_counter              // $851a  
    beq skip_dec_generator                      // $851c  
    dec generator_recharge_counter              // $851e  temporary gun-disabling timer recharges.
skip_dec_generator:
    dec countdown_timer_ticks                   // $8520  
    bpl skip_countdown_sound_return             // $8522  
    lda #$20                                    // $8524  
    sta countdown_timer_ticks                   // $8526  
    lda planet_countdown_timer                  // $8528  
    bmi skip_countdown_sound_return             // $852a  
    beq skip_countdown_sound                    // $852c  
    dec planet_countdown_timer                  // $852e  
    jsr make_sound                              // $8530  
skip_countdown_sound:
    lda #$ff                                    // $8533  
    sta font_byte_mask                          // $8535  
    lda planet_countdown_timer                  // $8538  
    clc                                         // $853a  
    adc #ASCII_0                                // $853b  ASCII '0'
    jsr write_countdown_timer                   // $853d  
    lda #$0f                                    // $8540  
    sta font_byte_mask                          // $8542  
    lda planet_countdown_timer                  // $8545  
    bne skip_countdown_sound_return             // $8547  
    lda #$01                                    // $8549  
    sta plot_ship_collision_detected            // $854b  
    lda #$ff                                    // $854d  
    sta pod_attached_flag_2                     // $854f  
skip_countdown_sound_return:
    rts                                         // $8552  
end_of_obj_type_table:
    jmp end_of_objects_function                 // $8553  
write_countdown_timer:
    ldx #$a9                                    // $8556  
    ldy #$59                                    // $8558  
    jsr plot_char_set_scr_addr_XY               // $855a  
    jsr plot_char_A                             // $855d  
    ldx #$09                                    // $8560  
    ldy #$5a                                    // $8562  
    jsr plot_char_set_scr_addr_XY               // $8564  
    jsr plot_char_A                             // $8567  
    rts                                         // $856a  
accumulate_score_A:
    clc                                         // $856b  
    adc score_accumulation                      // $856c  
    sta score_accumulation                      // $856e  
    rts                                         // $8570  
update_and_draw_all_objects:
    lda #$00                                    // $8571  reset sprite frame/colour
    sta spr_frame                               // $8573  
    sta objects_processed                       // $8575  count objects processed this frame
    ldx #$00                                    // $8578  
    stx collecting_fuel_flag                    // $857a  
    stx score_accumulation                      // $857c  
update_objects_loop:
    stx current_object                          // $857e  
    inc objects_processed                       // $8580  
load_object_type:
    .label level_obj_type_addr_LO = *+1
    .label level_obj_type_addr_HI = *+2
    lda level_0_obj_type,x                      // $8583  SELF-MODIFIED CODE
    cmp #$ff                                    // $8586  
    beq end_of_obj_type_table                   // $8588  
    sta object_type                             // $858a  
load_gun_param:
    .label level_gun_param_addr_LO = *+1
    .label level_gun_param_addr_HI = *+2
    lda level_0_gun_param,x                     // $858c  SELF-MODIFIED CODE
    pha                                         // $858f  
    and #$1c                                    // $8590  
    sta gun_base_angle                          // $8592  
    pla                                         // $8594  
    and #$03                                    // $8595  
    tay                                         // $8597  
    lda gun_param_table,y                       // $8598  
    sta gun_angle_spread_mask                   // $859b  
    ldy object_type                             // $859d  
    cpy #$05                                    // $859f  
    bne not_pod_stand                           // $85a1  
    lda level_obj_flags,x                       // $85a3  
    ora #$02                                    // $85a6  
    sta level_obj_flags,x                       // $85a8  
    lda pod_attached_flag_2                     // $85ab  
    beq not_pod_stand                           // $85ae  
    lda level_obj_flags,x                       // $85b0  
    and #$fd                                    // $85b3  
    sta level_obj_flags,x                       // $85b5  
not_pod_stand:
    cpy #$06                                    // $85b8  
    bne not_generator                           // $85ba  
    lda planet_countdown_timer                  // $85bc  
    bmi not_generator                           // $85be  
    beq not_generator                           // $85c0  
    lda countdown_timer_ticks                   // $85c2  
    and #$04                                    // $85c4  
    bne L85d3                                   // $85c6  
    lda level_obj_flags,x                       // $85c8  
    ora #$02                                    // $85cb  
    sta level_obj_flags,x                       // $85cd  
    jmp not_generator                           // $85d0  
L85d3:
    lda level_obj_flags,x                       // $85d3  
    and #$fd                                    // $85d6  
    sta level_obj_flags,x                       // $85d8  
not_generator:
    lda #$ff                                    // $85db  
    sta spr_x_hi                                // $85dd  assume not drawn
    ldx current_object                          // $85df  
    lda level_obj_flags,x                       // $85e1  
    and #$fe                                    // $85e4  
    sta level_obj_flags,x                       // $85e6  
    lda level_obj_flags,x                       // $85e9  
    and #$02                                    // $85ec  
    bne object_is_active                        // $85ee  
    jmp next_object                             // $85f0  
object_is_active:
    jsr object_visibility_test                  // $85f3  
    lda object_type                             // $85f6  
    cmp #$05                                    // $85f8  
    beq bullet_test_object                      // $85fa  
    lda planet_countdown_timer                  // $85fc  
    bne bullet_test_object                      // $85fe  
    lda planet_explode_anim                     // $8600  
    bne destroy_generator                       // $8602  
    lda #$0f                                    // $8604  
    sta planet_explode_anim                     // $8606  
destroy_generator:
    lda #POD_DESTROY_TIMER_INIT                 // $8608  
    sta pod_destroying_player_timer             // $860a  
    lda #$01                                    // $860c  
    sta explosion_particle_type                 // $860e  
    lda #$00                                    // $8610  
    sta score_value                             // $8612  
    jmp destroy_object                          // $8614  
bullet_test_object:
    ldx object_type                             // $8617  
    lda obj_type_width,x                        // $8619  
    sta current_object_width                    // $861c  
    lda obj_type_height,x                       // $861e  
    sta current_object_height                   // $8621  
    lda obj_type_explosion_particle,x           // $8623  
    sta explosion_particle_type                 // $8626  
    lda obj_type_score_value,x                  // $8628  
    sta score_value                             // $862b  
    ldx #$03                                    // $862d  
bullet_test_loop:
    lda particles_lifetime,x                    // $862f  
    beq bullet_test_next_jmp                    // $8632  
    lda particles_type,x                        // $8634  
    bne bullet_test_next_jmp                    // $8637  
    sec                                         // $8639  
    lda particles_xpos_INT,x                    // $863a  
    sbc current_obj_xpos_INT                    // $863d  
    bcc bullet_test_next_jmp                    // $863f  
    cmp current_object_width                    // $8641  
    bcs bullet_test_next_jmp                    // $8643  
    sec                                         // $8645  
    lda particles_ypos_INT,x                    // $8646  
    sbc current_obj_ypos_INT                    // $8649  
    tay                                         // $864b  
    lda particles_ypos_INT_HI,x                 // $864c  
    sbc current_obj_ypos_EXT                    // $864f  
    bne bullet_test_next_jmp                    // $8651  
    cpy current_object_height                   // $8653  
    bcs bullet_test_next_jmp                    // $8655  
    lda particles_lifetime,x                    // $8657  
    and #$80                                    // $865a  
    sta particles_lifetime,x                    // $865c  
    lda object_type                             // $865f  
    cmp #$07                                    // $8661  
    beq handle_door_switch                      // $8663  
    cmp #$08                                    // $8665  
    beq handle_door_switch                      // $8667  
    jmp handle_generator                        // $8669  
handle_door_switch:
    lda #$ff                                    // $866c  
    sta door_switch_counter_A                   // $866e  
    jsr explosion_at_bullet                     // $8670  
handle_generator:
    lda object_type                             // $8673  
    cmp #$06                                    // $8675  
    bne bullet_hit_not_generator                // $8677  
    jsr explosion_at_bullet                     // $8679  
    jsr rnd                                     // $867c  
    and #$1f                                    // $867f  
    adc generator_total_damage                  // $8681  
    sta generator_recharge_counter              // $8683  
    sta generator_total_damage                  // $8685  
    bcc delete_object                           // $8687  
    lda planet_countdown_timer                  // $8689  
    bpl delete_object                           // $868b  
    lda #$ff                                    // $868d  
    sta generator_recharge_counter              // $868f  
    lda #PLANET_COUNTDOWN_SECONDS               // $8691  
    sta planet_countdown_timer                  // $8693  
    lda #$01                                    // $8695  
    sta countdown_timer_ticks                   // $8697  
    jmp delete_object                           // $8699  
bullet_test_next_jmp:
    jmp bullet_test_next                        // $869c  
explosion_at_bullet:
    lda particles_xpos_INT,x                    // $869f  
    sta explosion_xpos_INT                      // $86a2  
    lda particles_ypos_INT_HI,x                 // $86a4  
    sta explosion_ypos_INT_HI                   // $86a7  
    lda particles_ypos_INT,x                    // $86a9  
    sta explosion_ypos_INT                      // $86ac  
    lda #$04                                    // $86ae  random debris
    sta explosion_particle_type                 // $86b0  
    jmp create_explosion                        // $86b2  
delete_object:
    jmp object_fuel_and_guns                    // $86b5  
bullet_hit_not_generator:
    lda object_type                             // $86b8  
    cmp #$05                                    // $86ba  
    bcs bullet_test_next                        // $86bc  
destroy_object:
    ldx current_object                          // $86be  
    lda level_obj_flags,x                       // $86c0  
    and #$fd                                    // $86c3  
    sta level_obj_flags,x                       // $86c5  
    lda current_obj_xpos_INT                    // $86c8  
    adc #$02                                    // $86ca  
    sta explosion_xpos_INT                      // $86cc  
    lda current_obj_ypos_INT                    // $86ce  
    adc #$04                                    // $86d0  
    sta explosion_ypos_INT                      // $86d2  
    lda current_obj_ypos_EXT                    // $86d4  
    adc #$00                                    // $86d6  
    sta explosion_ypos_INT_HI                   // $86d8  
    lda score_value                             // $86da  
    jsr accumulate_score_A                      // $86dc  
    jsr create_explosion                        // $86df  
    jmp object_fuel_and_guns                    // $86e2  
bullet_test_next:
    dex                                         // $86e5  
    bmi object_fuel_and_guns                    // $86e6  
    jmp bullet_test_loop                        // $86e8  
object_fuel_and_guns:
    lda pod_destroying_player_timer             // $86eb  
    bmi test_fuel_collect                       // $86ed  
object_guns_jmp:
    jmp object_gun_fire                         // $86ef  
test_fuel_collect:
    lda pod_attached_flag_1                     // $86f2  
    bne object_guns_jmp                         // $86f4  
    lda object_type                             // $86f6  
    cmp #$04                                    // $86f8  
    bne object_guns_jmp                         // $86fa  
    cmp #$06                                    // $86fc  
    beq object_guns_jmp                         // $86fe  
    lda shield_tractor_pressed                  // $8700  
    beq object_guns_jmp                         // $8702  
    lda current_obj_xpos_INT                    // $8704  
    sec                                         // $8706  
    sbc player_xpos_INT                         // $8707  
    beq object_guns_jmp                         // $8709  
    cmp #$06                                    // $870b  
    bcs object_guns_jmp                         // $870d  
    lda current_obj_ypos_INT                    // $870f  
    sbc player_ypos_INT                         // $8711  
    tax                                         // $8713  
    lda current_obj_ypos_EXT                    // $8714  
    sbc player_ypos_INT_HI                      // $8716  
    bne object_guns_jmp                         // $8718  
    cpx #$1c                                    // $871a  
    bcs object_guns_jmp                         // $871c  
    lda #$01                                    // $871e  
    sta collecting_fuel_flag                    // $8720  
    ldx current_object                          // $8722  
    ldy obj_tractor_counter,x                   // $8724  
    iny                                         // $8727  
    tya                                         // $8728  
    sta obj_tractor_counter,x                   // $8729  
    cmp #$1a                                    // $872c  
    bcc object_gun_fire                         // $872e  
    lda level_obj_flags,x                       // $8730  
    and #$fd                                    // $8733  
    sta level_obj_flags,x                       // $8735  
    lda #$30                                    // $8738  
    jsr accumulate_score_A                      // $873a  
    jsr collect_pod_fuel_sound                  // $873d  
object_gun_fire:
    lda object_type                             // $8740  
    cmp #$04                                    // $8742  
    bcs object_generator_smoke                  // $8744  
    lda generator_recharge_counter              // $8746  
    bne object_generator_smoke                  // $8748  
    lda planet_countdown_timer                  // $874a  
    bpl object_generator_smoke                  // $874c  
    lda current_obj_visible_flag                // $874e  
    beq object_generator_smoke                  // $8750  
    jsr rnd                                     // $8752  
    cmp hostile_gun_shoot_probability           // $8755  
    bcs object_generator_smoke                  // $8757  
    jsr hostile_gun_sound                       // $8759  
    jsr particle_return_free_slot_in_Y          // $875c  
    tya                                         // $875f  
    tax                                         // $8760  
    jsr rnd                                     // $8761  
    and #$03                                    // $8764  
    sta rnd_AND_3                               // $8766  
    lda rnd_B                                   // $8768  
    and gun_angle_spread_mask                   // $876a  
    adc gun_base_angle                          // $876c  
    adc rnd_AND_3                               // $876e  
    and #ANGLE_MASK                             // $8770  
    tay                                         // $8772  
    jsr angle_to_bullet_dx_dy                   // $8773  
    lda #$03                                    // $8776  
    sta particles_type,x                        // $8778  
    sta particles_xpos_FRAC,x                   // $877b  
    lda particles_lifetime,x                    // $877e  
    and #$80                                    // $8781  
    ora #$28                                    // $8783  
    sta particles_lifetime,x                    // $8785  
    ldy object_type                             // $8788  
    lda current_obj_xpos_INT                    // $878a  
    clc                                         // $878c  
    adc gun_bullet_x_offset,y                   // $878d  
    sta particles_xpos_INT,x                    // $8790  
    lda current_obj_ypos_INT                    // $8793  
    adc gun_bullet_y_offset,y                   // $8795  
    sta particles_ypos_INT,x                    // $8798  
    lda current_obj_ypos_EXT                    // $879b  
    adc #$00                                    // $879d  
    sta particles_ypos_INT_HI,x                 // $879f  
object_generator_smoke:
    lda level_tick_counter                      // $87a2  
    and #$07                                    // $87a4  
    bne object_draw                             // $87a6  
    lda object_type                             // $87a8  
    cmp #$06                                    // $87aa  
    bne object_draw                             // $87ac  
    lda generator_recharge_counter              // $87ae  
    bne object_draw                             // $87b0  
    lda planet_countdown_timer                  // $87b2  
    bpl object_draw                             // $87b4  
    jsr particle_return_free_slot_in_Y          // $87b6  
    lda current_obj_xpos_INT                    // $87b9  
    clc                                         // $87bb  
    adc #$04                                    // $87bc  
    sta particles_xpos_INT,y                    // $87be  
    lda #$00                                    // $87c1  
    sta particles_xpos_FRAC,y                   // $87c3  
    sta particles_dx_FRAC,y                     // $87c6  
    sta particles_dx_INT,y                      // $87c9  
    lda current_obj_ypos_INT                    // $87cc  
    sta particles_ypos_INT,y                    // $87ce  
    lda current_obj_ypos_EXT                    // $87d1  
    sta particles_ypos_INT_HI,y                 // $87d3  
    lda #$8e                                    // $87d6  
    sta particles_dy_FRAC,y                     // $87d8  
    lda #$ff                                    // $87db  
    sta particles_dy_INT,y                      // $87dd  
    lda #$01                                    // $87e0  
    sta particles_type,y                        // $87e2  
    lda particles_lifetime,y                    // $87e5  
    and #$80                                    // $87e8  
    ora #$0a                                    // $87ea  
    sta particles_lifetime,y                    // $87ec  
object_draw:
    ldx current_object                          // $87ef  
    lda spr_x_hi                                // $87f1  object on screen?
    bmi next_object                             // $87f3  
    jsr plot_object_sprite                      // $87f5  
next_object:
    ldx current_object                          // $87f8  
    inx                                         // $87fa  
    jmp update_objects_loop                     // $87fb  
gun_bullet_x_offset:
    .byte $04,$04,$01,$01                       // $87fe  
gun_bullet_y_offset:
    .byte $00,$08,$00,$08                       // $8802  
gun_param_table:
    .byte $01,$03,$07,$0f                       // $8806  
object_visibility_test:
    ldx current_object                          // $880a  
    .label level_obj_pos_X_addr_LO = *+1
    .label level_obj_pos_X_addr_HI = *+2
    lda level_0_obj_pos_X,x                     // $880c  SELF-MODIFIED CODE
    sta current_obj_xpos_INT                    // $880f  
    .label level_obj_pos_Y_addr_LO = *+1
    .label level_obj_pos_Y_addr_HI = *+2
    lda level_0_obj_pos_Y,x                     // $8811  SELF-MODIFIED CODE
    sta current_obj_ypos_INT                    // $8814  
    .label level_obj_pos_Y_EXT_addr_LO = *+1
    .label level_obj_pos_Y_EXT_addr_HI = *+2
    lda level_0_obj_pos_Y_EXT,x                 // $8816  SELF-MODIFIED CODE
    sta current_obj_ypos_EXT                    // $8819  
    lda #$00                                    // $881b  
    sta current_obj_visible_flag                // $881d  assume not visible
    sec                                         // $881f  
    lda current_obj_ypos_INT                    // $8820  
    sbc window_ypos_INT                         // $8822  
    sta obj_screen_y                            // $8824  
    lda current_obj_ypos_EXT                    // $8826  
    sbc window_ypos_EXT                         // $8828  
    sta obj_screen_y_hi                         // $882a  
    bne object_offscreen                        // $882c  
    lda #$01                                    // $882e  
    sta current_obj_visible_flag                // $8830  
    sec                                         // $8832  
    lda obj_screen_y                            // $8833  
    sbc #SCREEN_ADDR_HI_OFFSET                  // $8835  
    sta obj_screen_y                            // $8837  
    cmp #$09                                    // $8839  
    bcc object_offscreen                        // $883b  
    cmp #$61                                    // $883d  
    bcs object_offscreen                        // $883f  
    ldy object_type                             // $8841  
    sec                                         // $8843  
    lda current_obj_xpos_INT                    // $8844  
    sbc window_xpos_INT                         // $8846  
    adc #$05                                    // $8848  
    sta obj_screen_x                            // $884a  
    cmp #$64                                    // $884c  
    bcc object_onscreen                         // $884e  
object_offscreen:
    rts                                         // $8850  
object_onscreen:
    lda current_object                          // $8851  
    bne object_sprite_coords                    // $8853  
    lda #$00                                    // $8855  
    sta nearest_obj_xpos_FRAC                   // $8857  
    lda current_obj_xpos_INT                    // $8859  
    sec                                         // $885b  
    sbc #$02                                    // $885c  
    sta nearest_obj_xpos_INT                    // $885e  
    lda current_obj_ypos_EXT                    // $8860  
    sta nearest_obj_ypos_INT_HI                 // $8862  
    lda current_obj_ypos_INT                    // $8864  
    sta nearest_obj_ypos_INT                    // $8866  
object_sprite_coords:
    lda #$00                                    // $8868  convert to sprite coordinates:
    sta spr_x_hi                                // $886a  
    lda obj_screen_y                            // $886c  Y * 2 + 50 (top border)
    clc                                         // $886e  
    rol                                         // $886f  
    adc #$32                                    // $8870  
    sta spr_y                                   // $8872  
    lda obj_screen_x                            // $8874  X * 4 (9 bits)
    clc                                         // $8876  
    rol                                         // $8877  
    rol                                         // $8878  
    rol spr_x_hi                                // $8879  
    adc #$00                                    // $887b  
    sta spr_x_lo                                // $887d  
    bcc object_not_first                        // $887f  
    inc spr_x_hi                                // $8881  
object_not_first:
    lda current_object                          // $8883  
    bne L889a                                   // $8885  
    lda spr_y                                   // $8887  
    sec                                         // $8889  
    sbc #$04                                    // $888a  
    sta pod_window_ypos_INT                     // $888c  
    lda spr_x_lo                                // $888e  
    sbc #$01                                    // $8890  
    sta pod_window_xpos_FRAC                    // $8892  
    lda spr_x_hi                                // $8894  
    sbc #$00                                    // $8896  
    sta pod_window_xpos_INT                     // $8898  
L889a:
    rts                                         // $889a  
plot_object_sprite:
    ldx current_object                          // $889b  
    lda level_obj_flags,x                       // $889d  
    ora #$01                                    // $88a0  
    sta level_obj_flags,x                       // $88a2  
    lda object_type                             // $88a5  
    cmp #$04                                    // $88a7  
    bcc plot_object_gun                         // $88a9  
    beq plot_object_fuel                        // $88ab  
    cmp #$06                                    // $88ad  
    bcc plot_object_pod_stand                   // $88af  
    beq plot_object_generator                   // $88b1  
    clc                                         // $88b3  
    adc #$25                                    // $88b4  door switch: frames $2C/$2D
    sta spr_frame                               // $88b6  
    lda obj_colour_door_switch                  // $88b8  
    sta spr_colour                              // $88bb  
    jsr sprite_list_add                         // $88bd  
    ldx current_object                          // $88c0  
    rts                                         // $88c2  
plot_object_gun:
    adc #$22                                    // $88c3  gun: frames $22-$25 by direction
    sta spr_frame                               // $88c5  
    lda obj_colour_gun                          // $88c7  
    sta spr_colour                              // $88ca  
    jsr sprite_list_add                         // $88cc  
    ldx current_object                          // $88cf  
    rts                                         // $88d1  
plot_object_fuel:
    lda objects_processed                       // $88d2  fuel: alternate drawing every other object
    and #$01                                    // $88d5  
    beq plot_object_fuel_single                 // $88d7  
    lda #$26                                    // $88d9  
    sta spr_frame                               // $88db  
    lda obj_colour_fuel                         // $88dd  
    sta spr_colour                              // $88e0  
    jsr sprite_list_add                         // $88e2  
    inc spr_frame                               // $88e5  
    lda obj_colour_fuel_2                       // $88e7  
    sta spr_colour                              // $88ea  
    jsr sprite_list_add                         // $88ec  
    ldx current_object                          // $88ef  
    rts                                         // $88f1  
plot_object_fuel_single:
    lda #$2e                                    // $88f2  
    sta spr_frame                               // $88f4  
    lda obj_colour_fuel                         // $88f6  
    sta spr_colour                              // $88f9  
    jsr sprite_list_add                         // $88fb  
    ldx current_object                          // $88fe  
    rts                                         // $8900  
plot_object_pod_stand:
    lda #$28                                    // $8901  pod stand: two sprites
    sta spr_frame                               // $8903  
    lda pod_colour                              // $8905  
    sta spr_colour                              // $8908  
    jsr sprite_list_add                         // $890a  
    inc spr_frame                               // $890d  
    lda obj_colour_pod_stand                    // $890f  
    sta spr_colour                              // $8912  
    jsr sprite_list_add                         // $8914  
    ldx current_object                          // $8917  
    rts                                         // $8919  
plot_object_generator:
    lda #$2a                                    // $891a  generator: two sprites
    sta spr_frame                               // $891c  
    lda obj_colour_generator                    // $891e  
    sta spr_colour                              // $8921  
    jsr sprite_list_add                         // $8923  
    inc spr_frame                               // $8926  
    lda obj_colour_generator_2                  // $8928  
    sta spr_colour                              // $892b  
    jsr sprite_list_add                         // $892d  
    ldx current_object                          // $8930  
    rts                                         // $8932  
sprite_list_offset:
    .byte $00                                   // $8933  
sprite_list_count:
    .byte $00,$00                               // $8934  
sprite_bands_ready:
    .byte $00                                   // $8936  
sprite_bands_busy:
    .byte $00                                   // $8937  
sprite_band_rotate:
    .byte $00                                   // $8938  
hires_status_flag:
    .byte $00                                   // $8939  
multicolour_flag:
    .byte $00                                   // $893a  
playfield_bg_colour:
    .byte $00                                   // $893b  
playfield_mc2_colour:
    .byte $00                                   // $893c  
irq_exit:
    pla                                         // $893d  
    tay                                         // $893e  
    pla                                         // $893f  
    tax                                         // $8940  
    pla                                         // $8941  
    rti                                         // $8942  
irq_handler:
    cld                                         // $8943  
    lda #$01                                    // $8944  
    bit VIC_IRQ_STATUS                          // $8946  raster interrupt?
    bne irq_raster                              // $8949  
    lda CIA1_ICR                                // $894b  CIA timer interrupt?
    and #$01                                    // $894e  
    beq irq_other                               // $8950  
    dec game_tick_timer                         // $8952  CIA timer: game timing tick
    jmp irq_exit                                // $8955  
irq_other:
    lda VIC_IRQ_STATUS                          // $8958  
    sta VIC_IRQ_STATUS                          // $895b  
    lda CIA2_ICR                                // $895e  
    jmp irq_exit                                // $8961  
irq_raster:
    lda #$01                                    // $8964  
    sta VIC_IRQ_STATUS                          // $8966  
    ldy irq_table_index                         // $8969  current raster table entry
    lda raster_table+2,y                        // $896b  next entry raster line ($FF = last)
    tax                                         // $896e  
    cmp #$ff                                    // $896f  
    beq irq_raster_wrap                         // $8971  
    lda raster_table+3,y                        // $8973  schedule next interrupt
    sta VIC_RASTER                              // $8976  
    lda raster_table+1,y                        // $8979  handler number for this entry
    tay                                         // $897c  
    lda irq_jump_table_LO,y                     // $897d  
    sta irq_jump_vector                         // $8980  
    lda irq_jump_table_HI,y                     // $8983  
    sta sprite_data_B_ptr_HI                    // $8986  
    clc                                         // $8989  
    lda irq_table_index                         // $898a  
    adc #$03                                    // $898c  
    sta irq_table_index                         // $898e  
    jmp (irq_jump_vector)                       // $8990  
irq_raster_wrap:
    lda raster_table+1,y                        // $8993  last entry: restart table at top of frame
    tay                                         // $8996  
    lda irq_jump_table_LO,y                     // $8997  
    sta irq_jump_vector                         // $899a  MODIFIES CODE
    lda irq_jump_table_HI,y                     // $899d  
    sta sprite_data_B_ptr_HI                    // $89a0  MODIFIES CODE
    lda #$00                                    // $89a3  
    sta irq_table_index                         // $89a5  
    lda raster_table                            // $89a7  first raster line
    sta VIC_RASTER                              // $89aa  
    lda VIC_CTRL1                               // $89ad  
    and #$7f                                    // $89b0  
    sta VIC_CTRL1                               // $89b2  
    jmp (irq_jump_vector)                       // $89b5  
irq_jump_vector:
    .byte $00                                   // $89b8  
sprite_data_B_ptr_HI:
    .byte $00                                   // $89b9  
irq_jump_table_LO:
    .byte <(irq_top_of_frame)                   // $89ba  
    .byte <(irq_sprite_band)                    // $89bb  
    .byte <(irq_status_bar_line)                // $89bc  
    .byte <(irq_playfield_start)                // $89bd  
    .byte <(irq_multicolour_on)                 // $89be  
irq_jump_table_HI:
    .byte >(irq_top_of_frame)                   // $89bf  
    .byte >(irq_sprite_band)                    // $89c0  
    .byte >(irq_status_bar_line)                // $89c1  
    .byte >(irq_playfield_start)                // $89c2  
    .byte >(irq_multicolour_on)                 // $89c3  
irq_top_of_frame:
    lda #$00                                    // $89c4  black background in the border area
    sta VIC_BG0                                 // $89c6  
    lda sprite_bands_ready                      // $89c9  new sprite bands ready?
    beq irq_frame_no_commit                     // $89cc  
    jsr sprite_bands_commit                     // $89ce  
irq_frame_no_commit:
    lda #$00                                    // $89d1  
    sta irq_sprite_index                        // $89d3  
    sta irq1_timer1_signal                      // $89d5  BBC leftover, not used on the C64
    lda VIC_SPR_ENABLE                          // $89d7  disable multiplexed sprites (keep 6 and 7)
    and #$c0                                    // $89da  
    sta VIC_SPR_ENABLE                          // $89dc  
    inc vsync_count                             // $89df  rotate starting sprite each frame (0-5)
    lda vsync_count                             // $89e1  
    and #$07                                    // $89e3  
    sec                                         // $89e5  
    sbc #$06                                    // $89e6  
    bcs irq_band_rotate_ok                      // $89e8  
    adc #$06                                    // $89ea  
irq_band_rotate_ok:
    sta sprite_band_rotate                      // $89ec  
    inc sprite_band_rotate                      // $89ef  
    jsr scan_keyboard                           // $89f2  scan keyboard
    ldx planet_explode_anim                     // $89f5  planet explosion: flash the background
    beq irq_no_planet_flash                     // $89f7  
    lda planet_flash_colours,x                  // $89f9  
    ldy #$00                                    // $89fc  
    sta playfield_bg_colour                     // $89fe  
    lda #$00                                    // $8a01  
    sta landscape_visible_flag                  // $8a03  
    lda vsync_count                             // $8a06  
    and #$01                                    // $8a08  
    beq irq_no_planet_flash                     // $8a0a  
    dec planet_explode_anim                     // $8a0c  
irq_no_planet_flash:
    lda #$76                                    // $8a0e  status bar: text mode, double buffered screen
    ldx landscape_visible_flag                  // $8a10  
    bne irq_set_status_screen                   // $8a13  
    lda #$56                                    // $8a15  
irq_set_status_screen:
    sta VIC_MEMSETUP                            // $8a17  
    lda VIC_CTRL1                               // $8a1a  text mode, display on
    and #$5f                                    // $8a1d  
    sta VIC_CTRL1                               // $8a1f  
    lda #$07                                    // $8a22  status bar colours
    sta VIC_BG0                                 // $8a24  
    lda #$00                                    // $8a27  
    sta VIC_BG1                                 // $8a29  
    lda playfield_mc2_colour                    // $8a2c  
    sta VIC_BG2                                 // $8a2f  
    jsr sound_update                            // $8a32  sound effects
    jsr test_sound_keys                         // $8a35  read joystick / keys
    jsr music_play                              // $8a38  music
    jmp irq_sprite_band                         // $8a3b  
irq_status_bar_line:
    lda VIC_RASTER                              // $8a3e  wait for end of status bar line
    cmp #$34                                    // $8a41  
    bcc irq_status_bar_line                     // $8a43  
    lda #$00                                    // $8a45  
    sta VIC_BG0                                 // $8a47  
    jmp irq_exit                                // $8a4a  
irq_playfield_start:
    lda VIC_CTRL1                               // $8a4d  switch to bitmap mode
    ora #$20                                    // $8a50  
    tax                                         // $8a52  
irq_wait_playfield:
    lda VIC_RASTER                              // $8a53  wait for start of playfield
    cmp #$41                                    // $8a56  
    bcc irq_wait_playfield                      // $8a58  
    lda VIC_MEMSETUP                            // $8a5a  bitmap at $6000
    and #$f0                                    // $8a5d  
    ora #$08                                    // $8a5f  
    sta VIC_MEMSETUP                            // $8a61  
    stx VIC_CTRL1                               // $8a64  
    lda VIC_CTRL2                               // $8a67  
    ora #$10                                    // $8a6a  multicolour unless hires flag
    ldx multicolour_flag                        // $8a6c  
    beq irq_set_ctrl2                           // $8a6f  
    eor #$10                                    // $8a71  
irq_set_ctrl2:
    tax                                         // $8a73  
irq_wait_playfield_2:
    lda VIC_RASTER                              // $8a74  
    cmp #$43                                    // $8a77  
    bcc irq_wait_playfield_2                    // $8a79  
    stx VIC_CTRL2                               // $8a7b  
    lda playfield_bg_colour                     // $8a7e  
    sta VIC_BG0                                 // $8a81  
    lda #$04                                    // $8a84  
    sta VIC_BG1                                 // $8a86  
    jmp irq_exit                                // $8a89  
irq_multicolour_on:
    lda VIC_CTRL2                               // $8a8c  multicolour on (bottom of screen)
    ora #$10                                    // $8a8f  
    sta VIC_CTRL2                               // $8a91  
    lda #$ff                                    // $8a94  
    sta multicolour_flag                        // $8a96  
    jmp irq_exit                                // $8a99  
irq_sprite_band_end:
    inc irq_sprite_index                        // $8a9c  
    jmp irq_exit                                // $8a9e  
irq_sprite_band:
    lda sprite_band_rotate                      // $8aa1  sprite band: position up to 6 hardware sprites
    sta irq_band_skip                           // $8aa4  
    ldx irq_sprite_index                        // $8aa6  
    lda sprite_display_list,x                   // $8aa8  
    sta irq_band_rotate                         // $8aab  
    inc irq_sprite_index                        // $8aad  
irq_sprite_band_loop:
    ldx irq_sprite_index                        // $8aaf  
    lda sprite_display_list,x                   // $8ab1  
    cmp #$ff                                    // $8ab4  
    beq irq_sprite_band_end                     // $8ab6  
    tay                                         // $8ab8  
    lda irq_band_rotate                         // $8ab9  
    beq irq_sprite_set                          // $8abb  
    dec irq_band_skip                           // $8abd  
    bne irq_sprite_set                          // $8abf  
    lda irq_sprite_index                        // $8ac1  
irq_skip_sprites:
    clc                                         // $8ac3  
    adc #$05                                    // $8ac4  
    dec irq_band_rotate                         // $8ac6  
    bne irq_skip_sprites                        // $8ac8  
    sta irq_sprite_index                        // $8aca  
    jmp irq_sprite_band_loop                    // $8acc  
irq_sprite_set:
    ldx irq_hw_sprite                           // $8acf  
    inx                                         // $8ad1  
    cpx #$06                                    // $8ad2  
    bne irq_sprite_index_ok                     // $8ad4  
    ldx #$00                                    // $8ad6  
irq_sprite_index_ok:
    stx irq_hw_sprite                           // $8ad8  
    tya                                         // $8ada  
    sta sprite_pointers_screen_A,x              // $8adb  sprite pointer in both screens
    sta sprite_pointers_screen_B,x              // $8ade  
    ldy irq_sprite_index                        // $8ae1  
    lda sprite_display_list+$01,y               // $8ae3  colour
    sta VIC_SPR0_COL,x                          // $8ae6  
    lda bit_table_2,x                           // $8ae9  
    pha                                         // $8aec  
    lda sprite_display_list+$03,y               // $8aed  X bit 8
    beq irq_sprite_x_msb_clear                  // $8af0  
    pla                                         // $8af2  
    pha                                         // $8af3  
    ora VIC_SPR_X_MSB                           // $8af4  
    sta VIC_SPR_X_MSB                           // $8af7  
    jmp irq_sprite_xy                           // $8afa  
irq_sprite_x_msb_clear:
    pla                                         // $8afd  
    pha                                         // $8afe  
    and VIC_SPR_X_MSB                           // $8aff  
    eor VIC_SPR_X_MSB                           // $8b02  
    sta VIC_SPR_X_MSB                           // $8b05  
irq_sprite_xy:
    txa                                         // $8b08  
    clc                                         // $8b09  
    rol                                         // $8b0a  
    tax                                         // $8b0b  
    lda sprite_display_list+$02,y               // $8b0c  X
    sta VIC_SPR0_X,x                            // $8b0f  
    lda sprite_display_list+$04,y               // $8b12  Y
    sta VIC_SPR0_Y,x                            // $8b15  
    pla                                         // $8b18  
    ora VIC_SPR_ENABLE                          // $8b19  enable sprite
    sta VIC_SPR_ENABLE                          // $8b1c  
    clc                                         // $8b1f  
    lda irq_sprite_index                        // $8b20  
    adc #$05                                    // $8b22  
    sta irq_sprite_index                        // $8b24  
    jmp irq_sprite_band_loop                    // $8b26  
bit_table:
    .byte $01,$02,$04,$08,$10,$20,$40,$80       // $8b29  
planet_flash_colours:
    .byte $00,$00,$06,$02,$04,$05,$03,$07,$01,$01,$07,$03,$05,$04,$02,$06  // $8b31  
sprite_list_clear:
    lda #$00                                    // $8b41  
    sta sprite_list_offset                      // $8b43  
    sta sprite_list_count                       // $8b46  
    lda #$ff                                    // $8b49  
    sta sprite_entries                          // $8b4b  
    sta sprite_sort_order                       // $8b4e  
    rts                                         // $8b51  
sprite_list_add:
    lda sprite_list_count                       // $8b52  
    cmp #$1f                                    // $8b55  list full (31 sprites)?
    bcc sprite_list_add_ok                      // $8b57  
    rts                                         // $8b59  
sprite_list_add_ok:
    ldx sprite_list_offset                      // $8b5a  
    ldy #$00                                    // $8b5d  
sprite_list_copy:
    lda.a spr_frame,y                           // $8b5f  copy frame, colour, x lo, x hi, y
    sta sprite_entries,x                        // $8b62  
    inx                                         // $8b65  
    iny                                         // $8b66  
    cpy #$05                                    // $8b67  
    bne sprite_list_copy                        // $8b69  
    lda #$ff                                    // $8b6b  
    sta sprite_entries,x                        // $8b6d  
    ldx #$00                                    // $8b70  
sprite_list_find_pos:
    lda sprite_sort_order,x                     // $8b72  insertion sort on Y
    cmp #$ff                                    // $8b75  
    beq sprite_list_insert                      // $8b77  
    tay                                         // $8b79  
    lda sprite_entries+$04,y                    // $8b7a  
    cmp spr_y                                   // $8b7d  
    bcs sprite_list_insert                      // $8b7f  
    inx                                         // $8b81  
    jmp sprite_list_find_pos                    // $8b82  
sprite_list_insert:
    stx sprite_list_insert_pos+1                // $8b85  
    ldx sprite_list_count                       // $8b88  
    inx                                         // $8b8b  
    stx sprite_list_count                       // $8b8c  
sprite_list_shift:
    dex                                         // $8b8f  
    lda sprite_sort_order,x                     // $8b90  
    sta sprite_sort_order+1,x                   // $8b93  
sprite_list_insert_pos:
    cpx #$00                                    // $8b96  
    bne sprite_list_shift                       // $8b98  
    lda sprite_list_offset                      // $8b9a  
    sta sprite_sort_order,x                     // $8b9d  
    clc                                         // $8ba0  
    adc #$05                                    // $8ba1  
    sta sprite_list_offset                      // $8ba3  
    rts                                         // $8ba6  
sprite_bands_finish:
    ldy #$00                                    // $8ba7  
    lda band_sprite_count                       // $8ba9  
    cmp #$07                                    // $8bab  
    bcc sprite_bands_finish_2                   // $8bad  
    sbc #$06                                    // $8baf  
    tay                                         // $8bb1  
sprite_bands_finish_2:
    tya                                         // $8bb2  
    ldy sprite_band_count_pos                   // $8bb3  
    sta sprite_build_list,y                     // $8bb5  
    ldy build_list_pos                          // $8bb8  
    lda #$ff                                    // $8bba  
    sta sprite_build_list,y                     // $8bbc  
    ldy raster_build_pos                        // $8bbf  
    lda #$ff                                    // $8bc1  
    sta raster_build_table,y                    // $8bc3  
    iny                                         // $8bc6  
    lda #$00                                    // $8bc7  
    sta raster_build_table,y                    // $8bc9  
    iny                                         // $8bcc  
    lda #$ff                                    // $8bcd  
    sta raster_build_table,y                    // $8bcf  
    sei                                         // $8bd2  
    sty raster_table_len                        // $8bd3  
    lda build_list_pos                          // $8bd5  
    sta sprite_list_len                         // $8bd7  
    cli                                         // $8bd9  
    lda #$ff                                    // $8bda  
    sta sprite_bands_ready                      // $8bdc  
    lda #$00                                    // $8bdf  
    sta sprite_bands_busy                       // $8be1  
    rts                                         // $8be4  
sprite_bands_finish_jmp:
    jmp sprite_bands_finish                     // $8be5  
sprite_bands_build:
    lda #$ff                                    // $8be8  
    sta sprite_bands_busy                       // $8bea  
    lda #$00                                    // $8bed  
    sta band_next_raster                        // $8bef  
    sta sprite_list_count                       // $8bf1  
    sta build_list_pos                          // $8bf4  
    sta raster_build_pos                        // $8bf6  
    sta band_sprite_count                       // $8bf8  
    sta sprite_band_count_pos                   // $8bfa  
    dec sprite_list_count                       // $8bfc  
    inc build_list_pos                          // $8bff  
sprite_bands_next:
    inc sprite_list_count                       // $8c01  
    ldx sprite_list_count                       // $8c04  
    lda sprite_sort_order,x                     // $8c07  
    cmp #$ff                                    // $8c0a  
    beq sprite_bands_finish_jmp                 // $8c0c  
    tax                                         // $8c0e  
    lda sprite_entries+$04,x                    // $8c0f  
    cmp band_next_raster                        // $8c12  
    bcs sprite_bands_new_band                   // $8c14  
sprite_bands_copy:
    ldy build_list_pos                          // $8c16  
    lda sprite_entries,x                        // $8c18  
    sta sprite_build_list,y                     // $8c1b  
    inx                                         // $8c1e  
    iny                                         // $8c1f  
    lda sprite_entries,x                        // $8c20  
    sta sprite_build_list,y                     // $8c23  
    inx                                         // $8c26  
    iny                                         // $8c27  
    lda sprite_entries,x                        // $8c28  
    sta sprite_build_list,y                     // $8c2b  
    inx                                         // $8c2e  
    iny                                         // $8c2f  
    lda sprite_entries,x                        // $8c30  
    sta sprite_build_list,y                     // $8c33  
    inx                                         // $8c36  
    iny                                         // $8c37  
    lda sprite_entries,x                        // $8c38  
    sta sprite_build_list,y                     // $8c3b  
    inx                                         // $8c3e  
    iny                                         // $8c3f  
    inc band_sprite_count                       // $8c40  
    sty build_list_pos                          // $8c42  
    jmp sprite_bands_next                       // $8c44  
sprite_bands_new_band:
    pha                                         // $8c47  
    lda band_next_raster                        // $8c48  
    bne sprite_bands_close_band                 // $8c4a  
    pla                                         // $8c4c  
    adc #$0c                                    // $8c4d  
    sta band_next_raster                        // $8c4f  
    jmp sprite_bands_copy                       // $8c51  
sprite_bands_close_band:
    ldy build_list_pos                          // $8c54  
    lda #$ff                                    // $8c56  
    sta sprite_build_list,y                     // $8c58  
    inc build_list_pos                          // $8c5b  
    ldy #$00                                    // $8c5d  
    lda band_sprite_count                       // $8c5f  
    cmp #$07                                    // $8c61  
    bcc sprite_bands_count_ok                   // $8c63  
    sbc #$06                                    // $8c65  
    tay                                         // $8c67  
sprite_bands_count_ok:
    tya                                         // $8c68  
    ldy sprite_band_count_pos                   // $8c69  
    sta sprite_build_list,y                     // $8c6b  
    lda build_list_pos                          // $8c6e  
    sta sprite_band_count_pos                   // $8c70  
    inc build_list_pos                          // $8c72  
    lda #$00                                    // $8c74  
    sta band_sprite_count                       // $8c76  
    pla                                         // $8c78  
    adc #$0c                                    // $8c79  
    bcc sprite_bands_raster                     // $8c7b  
    lda #$ff                                    // $8c7d  
sprite_bands_raster:
    sta band_next_raster                        // $8c7f  
    sbc #$19                                    // $8c81  
    ldy raster_build_pos                        // $8c83  
    sta raster_build_table,y                    // $8c85  
    iny                                         // $8c88  
    lda #$01                                    // $8c89  
    sta raster_build_table,y                    // $8c8b  
    iny                                         // $8c8e  
    lda #$00                                    // $8c8f  
    sta raster_build_table,y                    // $8c91  
    iny                                         // $8c94  
    sty raster_build_pos                        // $8c95  
    jmp sprite_bands_copy                       // $8c97  
sprite_bands_commit_rts:
    rts                                         // $8c9a  
sprite_bands_commit:
    lda sprite_bands_busy                       // $8c9b  busy building?
    bmi sprite_bands_commit_rts                 // $8c9e  
    ldx sprite_list_len                         // $8ca0  
    inx                                         // $8ca2  
sprite_bands_copy_list:
    lda sprite_build_list-1,x                   // $8ca3  copy build list to display list
    sta sprite_display_list-1,x                 // $8ca6  
    dex                                         // $8ca9  
    bne sprite_bands_copy_list                  // $8caa  
    ldx raster_table_len                        // $8cac  
    inx                                         // $8cae  
    lda hires_status_flag                       // $8caf  
    beq sprite_bands_commit_mc                  // $8cb2  
    jmp sprite_bands_commit_hires               // $8cb4  
sprite_bands_commit_mc:
    lda #$00                                    // $8cb7  
    sta multicolour_flag                        // $8cb9  
sprite_bands_copy_irq:
    lda raster_build_table-1,x                  // $8cbc  
    sta raster_table+5,x                        // $8cbf  
    dex                                         // $8cc2  
    bne sprite_bands_copy_irq                   // $8cc3  
    stx sprite_bands_ready                      // $8cc5  
check_collisions:
    lda collision_ignore_timer                  // $8cc8  
    beq check_collisions_2                      // $8ccb  
    dec collision_ignore_timer                  // $8ccd  
    lda VIC_SPR_BG_COLL                         // $8cd0  clear collision latches
    lda VIC_SPR_SPR_COLL                        // $8cd3  
check_collisions_2:
    lda line_drawn_flag                         // $8cd6  
    beq check_ship_hits_sprite                  // $8cd8  
    dec line_drawn_flag                         // $8cda  
    jmp check_sprite_bg                         // $8cdc  
check_ship_hits_sprite:
    lda VIC_SPR_SPR_COLL                        // $8cdf  sprite-sprite collision
    bpl check_sprite_bg                         // $8ce2  
    lda #$ff                                    // $8ce4  
    sta plot_ship_collision_detected            // $8ce6  
check_sprite_bg:
    lda VIC_SPR_SPR_COLL                        // $8ce8  
    lda VIC_SPR_BG_COLL                         // $8ceb  sprite-background collision
    rol                                         // $8cee  bit 7: ship (sprite 7) hit background
    bcc check_pod_bg                            // $8cef  
    pha                                         // $8cf1  
    lda #$ff                                    // $8cf2  
    sta plot_ship_collision_detected            // $8cf4  
    pla                                         // $8cf6  
check_pod_bg:
    rol                                         // $8cf7  bit 6: pod (sprite 6) hit background
    bcc set_ship_and_pod_sprites                // $8cf8  
    lda midpoint_ypos_INT_HI                    // $8cfa  
    cmp #$01                                    // $8cfc  
    bne pod_collided                            // $8cfe  
    lda midpoint_ypos_INT                       // $8d00  
    cmp #$78                                    // $8d02  
    bcc set_ship_and_pod_sprites                // $8d04  
pod_collided:
    lda #$ff                                    // $8d06  
    sta plot_pod_collision_detected             // $8d08  
set_ship_and_pod_sprites:
    lda ship_spr_y                              // $8d0a  ship = sprite 7
    sta VIC_SPR7_Y                              // $8d0d  
    lda ship_spr_x                              // $8d10  
    sta VIC_SPR7_X                              // $8d13  
    lda ship_spr_frame                          // $8d16  
    sta sprite_pointers_screen_A+$07            // $8d19  
    sta sprite_pointers_screen_B+$07            // $8d1c  
    lda pod_spr_y                               // $8d1f  pod = sprite 6
    sta VIC_SPR6_Y                              // $8d22  
    lda pod_spr_x                               // $8d25  
    sta VIC_SPR6_X                              // $8d28  
    lda VIC_SPR_X_MSB                           // $8d2b  
    and #$3f                                    // $8d2e  
    ora ship_spr_x_msb                          // $8d30  
    ora pod_spr_x_msb                           // $8d33  
    sta VIC_SPR_X_MSB                           // $8d36  
    lda VIC_SPR_ENABLE                          // $8d39  
    and #$3f                                    // $8d3c  
    ora ship_spr_enable                         // $8d3e  
    ora pod_spr_enable                          // $8d41  
    sta VIC_SPR_ENABLE                          // $8d44  
    lda ship_colour                             // $8d47  
    sta VIC_SPR7_COL                            // $8d4a  
    rts                                         // $8d4d  
sprite_bands_commit_hires:
    lda #$ff                                    // $8d4e  
    sta multicolour_flag                        // $8d50  
sprite_bands_copy_irq_2:
    lda raster_build_table-1,x                  // $8d53  
    sta raster_table+8,x                        // $8d56  
    dex                                         // $8d59  
    bne sprite_bands_copy_irq_2                 // $8d5a  
    lda #$b8                                    // $8d5c  
    sta raster_table+6                          // $8d5e  
    lda #$04                                    // $8d61  
    sta raster_table+7                          // $8d63  
    lda #$00                                    // $8d66  
    sta raster_table+8                          // $8d68  
    sta sprite_bands_ready                      // $8d6b  
    rts                                         // $8d6e  
key_matrix_to_ascii:
    .byte $14,$0d,$00,$00,$00,$00,$00,$00,$33,$57,$41,$34,$5a,$53,$45,$00  // $8d6f  "........3WA4ZSE."
    .byte $35,$52,$44,$36,$43,$46,$54,$58,$37,$59,$47,$38,$42,$48,$55,$56  // $8d7f  "5RD6CFTX7YG8BHUV"
    .byte $39,$49,$4a,$30,$4d,$4b,$4f,$4e,$2b,$50,$4c,$2d,$2e,$3a,$40,$2c  // $8d8f  "9IJ0MKON+PL-.:@,"
    .byte $5c,$2a,$3b,$00,$00,$3d,$5e,$2f,$31,$00,$00,$32,$20,$00,$51,$00  // $8d9f  "\*;..=^/1..2 .Q."
key_last_1:
    .byte $00                                   // $8daf  
key_last_2:
    .byte $00                                   // $8db0  
key_ascii:
    .byte $00                                   // $8db1  
key_matrix_checksum:
    .byte $00                                   // $8db2  
read_key_ascii:
    txa                                         // $8db3  wait for a new key and return its ASCII code
    pha                                         // $8db4  
    tya                                         // $8db5  
    pha                                         // $8db6  
read_key_wait:
    jsr key_matrix_checksum_calc                // $8db7  
    cmp key_matrix_checksum                     // $8dba  
    beq read_key_wait                           // $8dbd  
    sta key_matrix_checksum                     // $8dbf  
    ldx key_last_1                              // $8dc2  
    bmi read_key_check_2                        // $8dc5  
    jsr test_inkey                              // $8dc7  
    beq read_key_check_2                        // $8dca  
    lda #$80                                    // $8dcc  
    sta key_last_1                              // $8dce  
read_key_check_2:
    ldx key_last_2                              // $8dd1  
    bmi read_key_released                       // $8dd4  
    jsr test_inkey                              // $8dd6  
    beq read_key_released                       // $8dd9  
    lda #$80                                    // $8ddb  
    sta key_last_2                              // $8ddd  
read_key_released:
    lda key_last_1                              // $8de0  
    bmi read_key_shift                          // $8de3  
    lda key_last_2                              // $8de5  
    bmi read_key_scan                           // $8de8  
    jmp read_key_wait                           // $8dea  
read_key_shift:
    lda key_last_2                              // $8ded  
    sta key_last_1                              // $8df0  
    lda #$80                                    // $8df3  
    sta key_last_2                              // $8df5  
read_key_scan:
    ldx #$00                                    // $8df8  
    ldy #$00                                    // $8dfa  
read_key_scan_row:
    lda key_matrix,y                            // $8dfc  scan the 8 keyboard matrix rows read in the IRQ
    sta key_bits                                // $8dff  
read_key_scan_bit:
    clc                                         // $8e01  
    ror key_bits                                // $8e02  
    bcs read_key_found                          // $8e04  
read_key_next_bit:
    inx                                         // $8e06  
    txa                                         // $8e07  
    and #$07                                    // $8e08  
    bne read_key_scan_bit                       // $8e0a  
    iny                                         // $8e0c  
    cpy #$08                                    // $8e0d  
    bne read_key_scan_row                       // $8e0f  
    jmp read_key_wait                           // $8e11  
read_key_found:
    cpx key_last_1                              // $8e14  
    beq read_key_next_bit                       // $8e17  
    stx key_last_2                              // $8e19  
    lda key_matrix_checksum                     // $8e1c  
    eor #$ff                                    // $8e1f  
    sta key_matrix_checksum                     // $8e21  
    ldx key_last_2                              // $8e24  
    lda key_matrix_to_ascii,x                   // $8e27  convert to ASCII
    sta key_ascii                               // $8e2a  
    pla                                         // $8e2d  
    tay                                         // $8e2e  
    pla                                         // $8e2f  
    tax                                         // $8e30  
    lda key_ascii                               // $8e31  
    rts                                         // $8e34  
key_matrix_checksum_calc:
    php                                         // $8e35  XOR of all matrix rows (changes when a key changes)
    lda #$00                                    // $8e36  
    ldx #$07                                    // $8e38  
key_matrix_checksum_loop:
    eor key_matrix,x                            // $8e3a  
    dex                                         // $8e3d  
    bpl key_matrix_checksum_loop                // $8e3e  
    plp                                         // $8e40  
    rts                                         // $8e41  
read_key_reset:
    lda #$80                                    // $8e42  
    sta key_last_1                              // $8e44  
    sta key_last_2                              // $8e47  
    jsr key_matrix_checksum_calc                // $8e4a  
    sta key_matrix_checksum                     // $8e4d  
    rts                                         // $8e50  
font_byte_mask:
    .byte $00                                   // $8e51  
font_data_line_0:
    .byte $00,$1e,$fc,$fe,$fe,$fe,$fe,$f8,$c6,$7e,$7e,$cc,$c0,$fe,$f6,$fe  // $8e52  
    .byte $fe,$fe,$fe,$fe,$fe,$c6,$c6,$c6,$c6,$c6,$fe,$fe,$78,$7e,$78,$c0  // $8e62  
    .byte $f8,$f0,$fe,$7c,$fe                   // $8e72  
font_data_line_1:
    .byte $00,$36,$cc,$c6,$c6,$c0,$c0,$c0,$c6,$18,$18,$d8,$c0,$d6,$d6,$c6  // $8e77  
    .byte $c6,$c6,$c6,$c0,$30,$c6,$c6,$c6,$6c,$c6,$06,$c6,$18,$06,$18,$ce  // $8e87  
    .byte $c0,$c0,$06,$6c,$c6                   // $8e97  
font_data_line_2:
    .byte $00,$66,$fe,$c0,$c6,$f8,$f8,$de,$fe,$18,$18,$fe,$c0,$d6,$d6,$c6  // $8e9c  
    .byte $c6,$c6,$fe,$fe,$30,$c6,$cc,$d6,$38,$fe,$fe,$c6,$18,$fe,$7e,$fe  // $8eac  
    .byte $fe,$fe,$7e,$fe,$fe                   // $8ebc  
font_data_line_3:
    .byte $30,$fe,$c6,$c0,$cc,$c0,$c0,$c6,$c6,$18,$d8,$c6,$c0,$d6,$d6,$c6  // $8ec1  
    .byte $fe,$cc,$cc,$06,$30,$c6,$d8,$d6,$6c,$06,$c0,$de,$7e,$e0,$1e,$0e  // $8ed1  
    .byte $0e,$ce,$70,$ee,$1e                   // $8ee1  
font_data_line_4:
    .byte $30,$c6,$fe,$fe,$f8,$fe,$c0,$fe,$c6,$7e,$f8,$c6,$fe,$c6,$de,$fe  // $8ee6  
    .byte $c0,$fe,$c6,$fe,$30,$fe,$f0,$fe,$c6,$7e,$fe,$fe,$7e,$fe,$fe,$0e  // $8ef6  
    .byte $fe,$fe,$70,$fe,$1e                   // $8f06  
char_write_ptr_next_column:
    clc                                         // $8f0b  
    lda char_write_ptr_LO                       // $8f0c  
    adc #$08                                    // $8f0e  
    sta char_write_ptr_LO                       // $8f10  
    bcc L8f16                                   // $8f12  
    inc char_write_ptr_HI                       // $8f14  
L8f16:
    rts                                         // $8f16  
char_clear_cursor_backspace:
    lda #$00                                    // $8f17  
    ldy #$04                                    // $8f19  
    sta (char_write_ptr_LO),y                   // $8f1b  
    sec                                         // $8f1d  
    lda char_write_ptr_LO                       // $8f1e  
    sbc #$08                                    // $8f20  
    sta char_write_ptr_LO                       // $8f22  
    bcs char_clear_cursor_backspace_return      // $8f24  
    dec char_write_ptr_HI                       // $8f26  
char_clear_cursor_backspace_return:
    rts                                         // $8f28  
char_plot_cursor:
    lda char_flag_cursor                        // $8f29  
    beq skip_cursor                             // $8f2c  
    lda #$ff                                    // $8f2e  
    ldy #$04                                    // $8f30  
    sta (char_write_ptr_LO),y                   // $8f32  
skip_cursor:
    pla                                         // $8f34  
    tay                                         // $8f35  
    pla                                         // $8f36  
    tax                                         // $8f37  
    pla                                         // $8f38  
    clc                                         // $8f39  
    rts                                         // $8f3a  
plot_font_mask_byte:
    pha                                         // $8f3b  
    tya                                         // $8f3c  
    pha                                         // $8f3d  
    ldy #$00                                    // $8f3e  
    lda font_byte_mask                          // $8f40  
    sta (text_ptr),y                            // $8f43  
    inc text_ptr                                // $8f45  
    bne L8f4b                                   // $8f47  
    inc text_ptr_HI                             // $8f49  
L8f4b:
    pla                                         // $8f4b  
    tay                                         // $8f4c  
    pla                                         // $8f4d  
plot_char_A:
    sta char_to_plot                            // $8f4e  
    pha                                         // $8f51  
    txa                                         // $8f52  
    pha                                         // $8f53  
    tya                                         // $8f54  
    pha                                         // $8f55  
    lda char_to_plot                            // $8f56  
    cmp #$07                                    // $8f59  
    beq plot_char_beep                          // $8f5b  
    cmp #$20                                    // $8f5d  
    bcc char_plot_cursor                        // $8f5f  
    beq plot_char_space                         // $8f61  
    cmp #$7f                                    // $8f63  
    beq plot_char_delete                        // $8f65  
    cmp #ASCII_0                                // $8f67  
    bcc not_a_number                            // $8f69  
    cmp #$3a                                    // $8f6b  
    bcc plot_ascii_number                       // $8f6d  
not_a_number:
    ora #$20                                    // $8f6f  
    cmp #$61                                    // $8f71  
    bcc not_a_letter                            // $8f73  
    cmp #$7b                                    // $8f75  
    bcc plot_ascii_lower_case_letter            // $8f77  
not_a_letter:
    lda #$00                                    // $8f79  
    jmp plot_font_A                             // $8f7b  
plot_char_space:
    jsr char_erase                              // $8f7e  
    jmp char_plot_cursor                        // $8f81  
plot_char_beep:
    jmp char_plot_cursor                        // $8f84  
char_erase:
    ldy #$04                                    // $8f87  
    lda #$00                                    // $8f89  
char_erase_loop:
    sta (char_write_ptr_LO),y                   // $8f8b  
    dey                                         // $8f8d  
    bpl char_erase_loop                         // $8f8e  
    jsr char_write_ptr_next_column              // $8f90  
    rts                                         // $8f93  
plot_char_delete:
    jsr char_clear_cursor_backspace             // $8f94  
    jsr char_erase                              // $8f97  
    jsr char_clear_cursor_backspace             // $8f9a  
    jmp char_plot_cursor                        // $8f9d  
plot_ascii_lower_case_letter:
    sec                                         // $8fa0  
    sbc #$60                                    // $8fa1  
    jmp plot_font_A                             // $8fa3  
plot_ascii_number:
    sec                                         // $8fa6  
    sbc #$15                                    // $8fa7  
    jmp plot_font_A                             // $8fa9  
plot_font_A:
    tax                                         // $8fac  
    ldy #$00                                    // $8fad  
    lda font_data_line_0,x                      // $8faf  
    sta (char_write_ptr_LO),y                   // $8fb2  
    iny                                         // $8fb4  
    lda font_data_line_1,x                      // $8fb5  
    sta (char_write_ptr_LO),y                   // $8fb8  
    iny                                         // $8fba  
    lda font_data_line_2,x                      // $8fbb  
    sta (char_write_ptr_LO),y                   // $8fbe  
    iny                                         // $8fc0  
    lda font_data_line_3,x                      // $8fc1  
    sta (char_write_ptr_LO),y                   // $8fc4  
    iny                                         // $8fc6  
    lda font_data_line_4,x                      // $8fc7  
    sta (char_write_ptr_LO),y                   // $8fca  
    jsr char_write_ptr_next_column              // $8fcc  
    jmp char_plot_cursor                        // $8fcf  
char_to_plot:
    .byte $00                                   // $8fd2  
char_flag_cursor:
    .byte $00                                   // $8fd3  
attach_pod_calculate_signed_multiply:
    sta multiply_operand_b                      // $8fd4  save multiplicand (operand B)
    lda #$00                                    // $8fd6  
    sta multiply_result_lo                      // $8fd8  clear result low byte
    sta multiply_result_hi                      // $8fda  clear result high byte
    sta multiply_sign_ext                       // $8fdc  clear sign-extension byte
    lda multiply_operand_a                      // $8fde  
    bpl L8ff0                                   // $8fe0  skip if operand A >= 0
    eor #$ff                                    // $8fe2  
    sta multiply_operand_a                      // $8fe4  
    inc multiply_operand_a                      // $8fe6  two's complement: -operand A
    lda multiply_operand_b                      // $8fe8  
    eor #$ff                                    // $8fea  
    sta multiply_operand_b                      // $8fec  
    inc multiply_operand_b                      // $8fee  two's complement: -operand B
L8ff0:
    lda multiply_operand_b                      // $8ff0  
    bpl L8ff8                                   // $8ff2  
    lda #$ff                                    // $8ff4  
    sta multiply_sign_ext                       // $8ff6  mark result as negative
L8ff8:
    ldx #$08                                    // $8ff8  process 8 bits
L8ffa:
    ror multiply_operand_a                      // $8ffa  shift multiplier right
    bcc L900b                                   // $8ffc  if bit = 0, skip addition
    lda multiply_operand_b                      // $8ffe  
    clc                                         // $9000  
    adc multiply_result_lo                      // $9001  
    sta multiply_result_lo                      // $9003  add multiplicand to result (low)
    lda multiply_sign_ext                       // $9005  
    adc multiply_result_hi                      // $9007  
    sta multiply_result_hi                      // $9009  propagate carry to high byte
L900b:
    clc                                         // $900b  
    rol multiply_operand_b                      // $900c  multiplicand <<= 1
    rol multiply_sign_ext                       // $900e  shift sign extension with it
    dex                                         // $9010  
    bne L8ffa                                   // $9011  repeat for remaining bits
    rts                                         // $9013  
update_window_and_terrain_tables:
    clc                                         // $9014  
    lda window_scroll_x                         // $9015  
    adc window_xpos_INT                         // $9017  
    sta window_xpos_INT                         // $9019  
    clc                                         // $901b  
    lda window_scroll_y                         // $901c  
    bmi L9039                                   // $901e  negative scroll -> scroll up
    beq L904d                                   // $9020  zero scroll -> skip Y update
    adc window_ypos_INT                         // $9022  
    sta window_ypos_INT                         // $9024  
    bcc L902a                                   // $9026  
    inc window_ypos_EXT                         // $9028  handle carry across 256-pixel boundary
L902a:
    lda window_scroll_y                         // $902a  
L902c:
    pha                                         // $902c  
    jsr terrain_process_accumulate_xpos         // $902d  advance terrain one row
    pla                                         // $9030  
    sec                                         // $9031  
    sbc #$01                                    // $9032  
    bne L902c                                   // $9034  repeat once per pixel of scroll
    jmp L904d                                   // $9036  
L9039:
    adc window_ypos_INT                         // $9039  
    sta window_ypos_INT                         // $903b  
    bcs L9041                                   // $903d  
    dec window_ypos_EXT                         // $903f  handle borrow
L9041:
    lda window_scroll_y                         // $9041  
L9043:
    pha                                         // $9043  
    jsr terrain_process_subtract_xpos           // $9044  rewind terrain one row
    pla                                         // $9047  
    clc                                         // $9048  
    adc #$01                                    // $9049  
    bne L9043                                   // $904b  repeat once per pixel of scroll
L904d:
    jsr tick_door_logic                         // $904d  unrelated game logic, ticked here
    sec                                         // $9050  
    lda midpoint_ypos_INT                       // $9051  
    sbc window_ypos_INT                         // $9053  
    sec                                         // $9055  
    sbc #SCREEN_ADDR_HI_OFFSET                  // $9056  
    sta midpoint_window_ypos_INT                // $9058  
    sec                                         // $905a  
    lda velocity_vectory_INT                    // $905b  
    bmi L9083                                   // $905d  ship moving upward
    lda midpoint_window_ypos_INT                // $905f  
    cmp #$46                                    // $9061  
    bcs L907b                                   // $9063  past threshold -> force scroll
    lda window_scroll_y                         // $9065  
    bmi L9078                                   // $9067  do not fight opposite scroll
    beq L9078                                   // $9069  
    ldx velocity_vectory_INT                    // $906b  
    inx                                         // $906d  max scroll = ship velocity + 1
    cpx window_scroll_y                         // $906e  
    bcs L9078                                   // $9070  
    dec window_scroll_y                         // $9072  gently reduce scroll speed
    bne L9078                                   // $9074  
    inc window_scroll_y                         // $9076  stabilise at +/-1
L9078:
    jmp L90a1                                   // $9078  
L907b:
    ldx velocity_vectory_INT                    // $907b  
    inx                                         // $907d  
    stx window_scroll_y                         // $907e  lock scroll to ship speed + 1
    jmp L90a1                                   // $9080  
L9083:
    lda midpoint_window_ypos_INT                // $9083  
    cmp #$20                                    // $9085  
    bcc L909c                                   // $9087  
    lda window_scroll_y                         // $9089  
    bpl L9099                                   // $908b  
    lda window_scroll_y                         // $908d  
    cmp velocity_vectory_INT                    // $908f  
    bcs L9099                                   // $9091  
    inc window_scroll_y                         // $9093  gently reduce magnitude
    bne L9099                                   // $9095  
    dec window_scroll_y                         // $9097  
L9099:
    jmp L90a1                                   // $9099  
L909c:
    ldx velocity_vectory_INT                    // $909c  
    dex                                         // $909e  
    stx window_scroll_y                         // $909f  lock scroll to ship speed - 1
L90a1:
    lda window_scroll_y                         // $90a1  
    beq L90be                                   // $90a3  
    bmi L90b4                                   // $90a5  
    lda midpoint_window_ypos_INT                // $90a7  
    cmp #$2d                                    // $90a9  
    bcs L90be                                   // $90ab  
    lda #$00                                    // $90ad  
    sta window_scroll_y                         // $90af  
    jmp L90be                                   // $90b1  
L90b4:
    lda midpoint_window_ypos_INT                // $90b4  
    cmp #$39                                    // $90b6  
    bcc L90be                                   // $90b8  
    lda #$00                                    // $90ba  
    sta window_scroll_y                         // $90bc  
L90be:
    sec                                         // $90be  
    lda midpoint_xpos_INT                       // $90bf  
    sbc window_xpos_INT                         // $90c1  
    sta midpoint_window_xpos_INT                // $90c3  
    sec                                         // $90c5  
    sbc #$14                                    // $90c6  
    bcs L90cf                                   // $90c8  
    sta window_scroll_x                         // $90ca  
    jmp L90da                                   // $90cc  
L90cf:
    lda midpoint_window_xpos_INT                // $90cf  
    sec                                         // $90d1  
    sbc #$32                                    // $90d2  
    beq L90da                                   // $90d4  
    bcc L90da                                   // $90d6  
    sta window_scroll_x                         // $90d8  
L90da:
    lda window_scroll_x                         // $90da  
    beq L9111                                   // $90dc  no scroll -> done
    bmi L90fa                                   // $90de  negative = scrolling left
    lda midpoint_window_xpos_INT                // $90e0  
    cmp #$1d                                    // $90e2  
    bcs L90ed                                   // $90e4  
    lda #$00                                    // $90e6  
    sta window_scroll_x                         // $90e8  
    jmp L9111                                   // $90ea  
L90ed:
    cmp #$32                                    // $90ed  
    bcs L9111                                   // $90ef  
    dec window_scroll_x                         // $90f1  
    bne L9111                                   // $90f3  
    inc window_scroll_x                         // $90f5  
    jmp L9111                                   // $90f7  
L90fa:
    lda midpoint_window_xpos_INT                // $90fa  
    cmp #$29                                    // $90fc  
    bcc L9107                                   // $90fe  
    lda #$00                                    // $9100  
    sta window_scroll_x                         // $9102  
    jmp L9111                                   // $9104  
L9107:
    cmp #$14                                    // $9107  
    bcc L9111                                   // $9109  
    inc window_scroll_x                         // $910b  
    bne L9111                                   // $910d  
    dec window_scroll_x                         // $910f  
L9111:
    lda window_xpos_INT                         // $9111  
    beq L9119                                   // $9113  near left edge -> wrap backward
    cmp #$d8                                    // $9115  
    bcc L911d                                   // $9117  not near right edge -> continue
L9119:
    lda #$af                                    // $9119  
    bne L9123                                   // $911b  
L911d:
    cmp #$b0                                    // $911d  
    bcc L917c                                   // $911f  no wrap needed
    lda #$51                                    // $9121  
L9123:
    sta window_deltax_INT                       // $9123  
    lda window_xpos_INT                         // $9125  
    clc                                         // $9127  
    adc window_deltax_INT                       // $9128  
    sta window_xpos_INT                         // $912a  
    lda midpoint_xpos_INT                       // $912c  
    clc                                         // $912e  
    adc window_deltax_INT                       // $912f  
    sta midpoint_xpos_INT                       // $9131  
    lda player_xpos_INT                         // $9133  
    clc                                         // $9135  
    adc window_deltax_INT                       // $9136  
    sta player_xpos_INT                         // $9138  
    lda old_player_xpos_INT                     // $913a  
    clc                                         // $913c  
    adc window_deltax_INT                       // $913d  
    sta old_player_xpos_INT                     // $913f  
    ldx #$1f                                    // $9141  
L9143:
    lda particles_xpos_INT,x                    // $9143  
    clc                                         // $9146  
    adc window_deltax_INT                       // $9147  
    sta particles_xpos_INT,x                    // $9149  
    dex                                         // $914c  
    bpl L9143                                   // $914d  
    ldx #$09                                    // $914f  
L9151:
    lda terrain_draw_table_3,x                  // $9151  
    bne L9166                                   // $9154  
    lda terrain_draw_table_1,x                  // $9156  
    bne L9179                                   // $9159  
    lda #$50                                    // $915b  
    sta terrain_draw_table_1,x                  // $915d  
    sta terrain_draw_table_3,x                  // $9160  
    jmp L9179                                   // $9163  
L9166:
    cmp #$50                                    // $9166  
    bne L9179                                   // $9168  
    lda terrain_draw_table_1,x                  // $916a  
    cmp #$50                                    // $916d  
    bne L9179                                   // $916f  
    lda #$00                                    // $9171  
    sta terrain_draw_table_3,x                  // $9173  
    sta terrain_draw_table_1,x                  // $9176  
L9179:
    inx                                         // $9179  
    bpl L9151                                   // $917a  
L917c:
    rts                                         // $917c  
tick_door_logic:
    lda door_switch_counter_A                   // $917d  door switch shot: counter set to $FF, counts down
    beq door_switch_zero                        // $917f  
    dec door_switch_counter_A                   // $9181  
door_switch_zero:
    lda level_number                            // $9183  only levels 3, 4 and 5 have doors
    cmp #$03                                    // $9186  
    beq level_3_door_logic                      // $9188  
    cmp #$05                                    // $918a  
    beq level_5_door_logic                      // $918c  
    cmp #$04                                    // $918e  
    beq level_4_door_logic                      // $9190  
    rts                                         // $9192  
level_5_door_logic:
    jmp do_level_5_door_logic                   // $9193  
level_4_door_logic:
    jmp do_level_4_door_logic                   // $9196  
level_3_door_logic:
    sec                                         // $9199  
    lda #$69                                    // $919a  door top: world Y $0269
    sbc window_ypos_INT                         // $919c  
    sta door_screen_ypos                        // $919e  
    lda #$02                                    // $91a0  
    sbc window_ypos_EXT                         // $91a2  
    bne level_3_door_logic_return               // $91a4  
    lda door_screen_ypos                        // $91a6  
    cmp #$f1                                    // $91a8  on screen?
    bcc level_3_door_visible                    // $91aa  
level_3_door_logic_return:
    rts                                         // $91ac  
level_3_door_visible:
    lda door_switch_counter_A                   // $91ad  door open amount follows the switch counter,
    cmp #$10                                    // $91af  
    bcs level_3_door_closing                    // $91b1  
    sta door_switch_counter_B                   // $91b3  
    jmp level_3_door_draw                       // $91b5  
level_3_door_closing:
    lda door_switch_counter_B                   // $91b8  then closes slowly
    cmp #$10                                    // $91ba  
    bcs level_3_door_draw                       // $91bc  
    inc door_switch_counter_B                   // $91be  
level_3_door_draw:
    sec                                         // $91c0  
    lda #$ae                                    // $91c1  door: left wall X = $AE - opening
    sbc door_switch_counter_B                   // $91c3  
    pha                                         // $91c5  
    lda door_screen_ypos                        // $91c6  wall array row of the door top
    clc                                         // $91c8  
    adc terrain_window_y_index                  // $91c9  
    tay                                         // $91cc  
    pla                                         // $91cd  
    ldx #$0d                                    // $91ce  13 rows
level_3_door_draw_loop:
    sta terrain_left_wall,y                     // $91d0  
    iny                                         // $91d3  
    dex                                         // $91d4  
    bne level_3_door_draw_loop                  // $91d5  
    rts                                         // $91d7  
do_level_4_door_logic:
    sec                                         // $91d8  
    lda #$43                                    // $91d9  door top: world Y $0343
    sbc window_ypos_INT                         // $91db  
    sta door_screen_ypos                        // $91dd  
    lda #$03                                    // $91df  
    sbc window_ypos_EXT                         // $91e1  
    bne do_level_4_door_logic_return            // $91e3  
    lda door_screen_ypos                        // $91e5  
    cmp #$e9                                    // $91e7  
    bcc level_4_door_visible                    // $91e9  
do_level_4_door_logic_return:
    rts                                         // $91eb  
level_4_door_visible:
    lda door_switch_counter_A                   // $91ec  
    cmp #$15                                    // $91ee  max opening 21 rows
    bcs level_4_door_closing                    // $91f0  
    sta door_switch_counter_B                   // $91f2  
    jmp level_4_door_draw                       // $91f4  
level_4_door_closing:
    lda door_switch_counter_B                   // $91f7  
    cmp #$15                                    // $91f9  
    bcs level_4_door_draw                       // $91fb  
    inc door_switch_counter_B                   // $91fd  
level_4_door_draw:
    lda door_screen_ypos                        // $91ff  
    clc                                         // $9201  
    adc terrain_window_y_index                  // $9202  
    clc                                         // $9205  
    adc #$15                                    // $9206  bottom row of the door
    tax                                         // $9208  
    lda #$a6                                    // $9209  closed door wall X
    ldy #$15                                    // $920b  
level_4_door_draw_loop:
    cpy door_switch_counter_B                   // $920d  
    bne level_4_door_store                      // $920f  
    lda #$98                                    // $9211  open part: wall X $98
level_4_door_store:
    sta terrain_left_wall,x                     // $9213  
    dex                                         // $9216  
    dey                                         // $9217  
    bne level_4_door_draw_loop                  // $9218  
    rts                                         // $921a  
do_level_5_door_logic:
    sec                                         // $921b  
    lda #$70                                    // $921c  door top: world Y $0370
    sbc window_ypos_INT                         // $921e  
    sta door_screen_ypos                        // $9220  
    lda #$03                                    // $9222  
    sbc window_ypos_EXT                         // $9224  
    bne do_level_5_door_logic_return            // $9226  
    lda door_screen_ypos                        // $9228  
    cmp #$ef                                    // $922a  
    bcc level_5_door_visible                    // $922c  
do_level_5_door_logic_return:
    rts                                         // $922e  
level_5_door_visible:
    lda door_switch_counter_A                   // $922f  
    cmp #$12                                    // $9231  max opening $12
    bcs level_5_door_closing                    // $9233  
    sta door_switch_counter_B                   // $9235  
    jmp level_5_door_draw                       // $9237  
level_5_door_closing:
    lda door_switch_counter_B                   // $923a  
    cmp #$12                                    // $923c  
    bcs level_5_door_draw                       // $923e  
    inc door_switch_counter_B                   // $9240  
level_5_door_draw:
    sec                                         // $9242  
    lda #$c0                                    // $9243  diamond door: wall X = $C0 - opening
    sbc door_switch_counter_B                   // $9245  
    pha                                         // $9247  
    lda door_screen_ypos                        // $9248  
    clc                                         // $924a  
    adc terrain_window_y_index                  // $924b  
    tay                                         // $924e  
    pla                                         // $924f  
    clc                                         // $9250  
    ldx #$07                                    // $9251  7 rows sloping right
level_5_door_draw_top:
    sta terrain_left_wall,y                     // $9253  
    adc #$01                                    // $9256  
    iny                                         // $9258  
    dex                                         // $9259  
    bne level_5_door_draw_top                   // $925a  
    sec                                         // $925c  
    ldx #$08                                    // $925d  8 rows sloping back
level_5_door_draw_bottom:
    sta terrain_left_wall,y                     // $925f  
    sbc #$01                                    // $9262  
    iny                                         // $9264  
    dex                                         // $9265  
    bne level_5_door_draw_bottom                // $9266  
    rts                                         // $9268  
lose_a_life:
    lda lives                                   // $9269  
    sec                                         // $926c  
    sed                                         // $926d  
    sbc #$01                                    // $926e  
    sta lives                                   // $9270  
    cld                                         // $9273  
    bpl write_num_lives                         // $9274  
    ldx #$ff                                    // $9276  
    rts                                         // $9278  
extra_life:
    lda lives                                   // $9279  
    clc                                         // $927c  
    sed                                         // $927d  
    adc #$01                                    // $927e  
    sta lives                                   // $9280  
    cld                                         // $9283  
write_num_lives:
    pha                                         // $9284  
    ldx #$d1                                    // $9285  
    ldy #$59                                    // $9287  
    jsr plot_char_set_scr_addr_XY               // $9289  
    pla                                         // $928c  
    beq zero_lives                              // $928d  
    dey                                         // $928f  
    ldx #$00                                    // $9290  
    ldy #$00                                    // $9292  
    jmp plot_score_ext                          // $9294  
zero_lives:
    lda #$20                                    // $9297  
    jsr plot_char_A                             // $9299  
    lda #$30                                    // $929c  ASCII '0'
    jmp plot_char_A                             // $929e  
add_score_return:
    rts                                         // $92a1  
add_A_to_score:
    ldx demo_mode_flag                          // $92a2  
    bne add_score_return                        // $92a4  
    pha                                         // $92a6  
    lda score_B                                 // $92a7  
    and #$f0                                    // $92aa  
    sta add_score_thousands                     // $92ac  number of thousands
    pla                                         // $92ae  
    sed                                         // $92af  
    clc                                         // $92b0  
    adc score_A                                 // $92b1  
    sta score_A                                 // $92b4  
    lda #$00                                    // $92b7  
    adc score_B                                 // $92b9  
    sta score_B                                 // $92bc  
    lda #$00                                    // $92bf  
    adc score_C                                 // $92c1  
    sta score_C                                 // $92c4  
    cld                                         // $92c7  
    lda score_B                                 // $92c8  
    and #$f0                                    // $92cb  
    cmp add_score_thousands                     // $92cd  
    beq write_score                             // $92cf  
    jsr extra_life                              // $92d1  
    jsr countdown_sound                         // $92d4  
write_score:
    lda #<score_A                               // $92d7  
    sta plot_string_ptr                         // $92d9  
    lda #>score_A                               // $92db  
    sta add_score_thousands+1                   // $92dd  
    ldx #$21                                    // $92df  
    ldy #$5a                                    // $92e1  
plot_three_byte_BCD_number:
    jsr plot_char_set_scr_addr_XY               // $92e3  
plot_three_byte_BCD_number_ext:
    ldx #$00                                    // $92e6  
    ldy #$02                                    // $92e8  
plot_BCD_loop:
    lda (plot_string_ptr),y                     // $92ea  
plot_score_ext:
    pha                                         // $92ec  
    ror                                         // $92ed  
    ror                                         // $92ee  
    ror                                         // $92ef  
    ror                                         // $92f0  
    and #$0f                                    // $92f1  
    jsr plot_number_zero_space                  // $92f3  
    pla                                         // $92f6  
    and #$0f                                    // $92f7  
    jsr plot_number_zero_space                  // $92f9  
    dey                                         // $92fc  
    bpl plot_BCD_loop                           // $92fd  
    rts                                         // $92ff  
plot_char_set_scr_addr_XY:
    stx char_write_ptr_LO                       // $9300  
    sty char_write_ptr_HI                       // $9302  
    rts                                         // $9304  
calc_text_colour_ptr:
    lda char_write_ptr_LO                       // $9305  
    sta text_ptr                                // $9307  
    lda char_write_ptr_HI                       // $9309  
    ror                                         // $930b  
    ror text_ptr                                // $930c  
    ror                                         // $930e  
    ror text_ptr                                // $930f  
    ror                                         // $9311  
    ror text_ptr                                // $9312  
    and #$1f                                    // $9314  
    clc                                         // $9316  
    adc #$50                                    // $9317  
    sta text_ptr_HI                             // $9319  
    rts                                         // $931b  
plot_number_zero_space:
    bne plot_a_number                           // $931c  
    cpx #$00                                    // $931e  
    bne plot_a_number                           // $9320  
    lda #$20                                    // $9322  
    jmp plot_char_A                             // $9324  
plot_a_number:
    clc                                         // $9327  
    adc #ASCII_0                                // $9328  
    tax                                         // $932a  
    jmp plot_char_A                             // $932b  
add_fuel:
    lda demo_mode_flag                          // $932e  
    bne fuel_return                             // $9330  
    lda #$11                                    // $9332  
    ldx #$00                                    // $9334  
    jmp add_A_X_to_fuel                         // $9336  
use_fuel:
    lda demo_mode_flag                          // $9339  
    bne fuel_return                             // $933b  
    lda #$00                                    // $933d  
    sta fuel_just_ran_out_flag                  // $933f  
    lda fuel_A                                  // $9341  
    ora fuel_B                                  // $9344  
    ora fuel_C                                  // $9347  
    bne subtract_from_fuel                      // $934a  
fuel_is_empty:
    ldx #$81                                    // $934c  
    ldy #$59                                    // $934e  
    jsr plot_char_set_scr_addr_XY               // $9350  
    lda #ASCII_0                                // $9353  
    jsr plot_char_A                             // $9355  
    lda #$ff                                    // $9358  
    sta fuel_empty_flag                         // $935a  
    sta fuel_just_ran_out_flag                  // $935d  
    rts                                         // $935f  
subtract_from_fuel:
    lda #$99                                    // $9360  
    ldx #$99                                    // $9362  
add_A_X_to_fuel:
    sed                                         // $9364  
    clc                                         // $9365  
    adc fuel_A                                  // $9366  
    sta fuel_A                                  // $9369  
    txa                                         // $936c  
    adc fuel_B                                  // $936d  
    sta fuel_B                                  // $9370  
    txa                                         // $9373  
    adc fuel_C                                  // $9374  
    sta fuel_C                                  // $9377  
    cld                                         // $937a  
    ora fuel_B                                  // $937b  
    ora fuel_A                                  // $937e  
    beq fuel_is_empty                           // $9381  
    lda #$00                                    // $9383  
    sta fuel_value_updated_flag                 // $9385  
fuel_return:
    rts                                         // $9387  
plot_fuel_value:
    lda fuel_value_updated_flag                 // $9388  
    bne fuel_return                             // $938a  
    lda fuel_empty_flag                         // $938c  
    bmi fuel_return                             // $938f  
    lda #<fuel_A                                // $9391  
    sta plot_string_ptr                         // $9393  
    lda #>fuel_A                                // $9395  
    sta plot_string_ptr+1                       // $9397  
    sta fuel_value_updated_flag                 // $9399  
    ldx #$59                                    // $939b  
    ldy #$59                                    // $939d  
    jmp plot_three_byte_BCD_number              // $939f  
plot_high_score_table:
    ldx #$c8                                    // $93a2  
    ldy #$67                                    // $93a4  
    jsr plot_char_set_scr_addr_XY               // $93a6  
    lda #$70                                    // $93a9  
    sta font_byte_mask                          // $93ab  
    ldy #$01                                    // $93ae  
    sty high_score_ptr_A+1                      // $93b0  
    dey                                         // $93b2  
    sty high_score_ptr_A                        // $93b3  high_score_table at $100
    lda #$31                                    // $93b5  
    sta plot_high_score_number                  // $93b7  
L93b9:
    jsr calc_text_colour_ptr                    // $93b9  
    ldy #$0a                                    // $93bc  
    lda font_byte_mask                          // $93be  
L93c1:
    sta (text_ptr),y                            // $93c1  
    dey                                         // $93c3  
    bpl L93c1                                   // $93c4  
    lda plot_high_score_number                  // $93c6  
    jsr plot_char_A                             // $93c8  
    lda #$2e                                    // $93cb  
    jsr plot_char_A                             // $93cd  
    inc plot_high_score_number                  // $93d0  
    jsr plot_three_byte_BCD_number_ext          // $93d2  
    lda #$30                                    // $93d5  
    jsr plot_char_A                             // $93d7  
    jsr calc_text_colour_ptr                    // $93da  
    ldy #$03                                    // $93dd  
L93df:
    lda (high_score_ptr_A),y                    // $93df  
    jsr plot_font_mask_byte                     // $93e1  
    iny                                         // $93e4  
    cpy #$10                                    // $93e5  
    bne L93df                                   // $93e7  
L93e9:
    lda #$20                                    // $93e9  
    jsr plot_char_A                             // $93eb  
    iny                                         // $93ee  
    cpy #$22                                    // $93ef  
    bne L93e9                                   // $93f1  
    ldy #$00                                    // $93f3  
    lda high_score_ptr_A                        // $93f5  
    clc                                         // $93f7  
    adc #$10                                    // $93f8  
    sta high_score_ptr_A                        // $93fa  
    bpl L93b9                                   // $93fc  
    rts                                         // $93fe  
fuel_A:
    .byte $00                                   // $93ff  
fuel_B:
    .byte $00                                   // $9400  
fuel_C:
    .byte $00                                   // $9401  
fuel_empty_flag:
    .byte $00                                   // $9402  
lives:
    .byte $00                                   // $9403  
write_game_over:
    lda #$07                                    // $9404  
    sta font_byte_mask                          // $9406  
    ldx #<msg_game_over                         // $9409  
    jmp write_message_page_09                   // $940b  
write_top_8_thrusters:
    lda obj_colour_gun                          // $940e  
    sta font_byte_mask                          // $9411  
    ldx #<msg_top_eight_thrusters               // $9414  
    jmp write_message_page_09                   // $9416  
write_congratulations:
    lda obj_colour_gun                          // $9419  
    sta font_byte_mask                          // $941c  
    ldx #<msg_congratulations                   // $941f  
    jmp write_message_page_09                   // $9421  
write_enter_name:
    lda text_colour                             // $9424  
    sta font_byte_mask                          // $9427  
    ldx #<msg_enter_name                        // $942a  
    jmp write_message_page_09                   // $942c  
write_press_spacebar:
    lda text_colour                             // $942f  
    sta font_byte_mask                          // $9432  
    ldx #<msg_press_space                       // $9435  
    jmp write_message_page_09                   // $9437  
write_out_of_fuel:
    lda obj_colour_gun                          // $943a  
    sta font_byte_mask                          // $943d  
    ldx #<msg_out_of_fuel                       // $9440  
write_message_page_09:
    lda #>msg_game_over                         // $9442  messages at $09xx
    sta plot_string_ptr+1                       // $9444  
write_message:
    stx plot_string_ptr                         // $9446  
    ldy #$00                                    // $9448  
    lda (plot_string_ptr),y                     // $944a  
    tax                                         // $944c  
    iny                                         // $944d  
    lda (plot_string_ptr),y                     // $944e  
    tay                                         // $9450  
    jsr plot_char_set_scr_addr_XY               // $9451  
write_message_continue:
    lda font_byte_mask                          // $9454  
    rol                                         // $9457  
    rol                                         // $9458  
    rol                                         // $9459  
    rol                                         // $945a  
    and #$f0                                    // $945b  
    sta font_byte_mask                          // $945d  
    jsr calc_text_colour_ptr                    // $9460  
    ldy #$01                                    // $9463  
write_message_loop:
    iny                                         // $9465  
    lda (plot_string_ptr),y                     // $9466  
    bmi write_message_return                    // $9468  
    jsr plot_font_mask_byte                     // $946a  
    jmp write_message_loop                      // $946d  
write_message_return:
    rts                                         // $9470  
write_mission:
    lda text_colour                             // $9471  
    sta font_byte_mask                          // $9474  
    lda #>msg_mission                           // $9477  
    sta plot_string_ptr+1                       // $9479  
    ldx #<msg_mission                           // $947b  
    jsr write_message                           // $947d  
    ldy #$0a                                    // $9480  
    lda text_colour                             // $9482  
    rol                                         // $9485  
    rol                                         // $9486  
    rol                                         // $9487  
    rol                                         // $9488  
    and #$f0                                    // $9489  
write_mission_colour:
    sta (text_ptr),y                            // $948b  
    dey                                         // $948d  
    bpl write_mission_colour                    // $948e  
    rts                                         // $9490  
write_in:
    lda text_colour                             // $9491  
    sta font_byte_mask                          // $9494  
    lda #>msg_in                                // $9497  
    sta plot_string_ptr+1                       // $9499  
    ldx #<msg_in                                // $949b  
    stx plot_string_ptr                         // $949d  
    jmp write_message_continue                  // $949f  
write_complete:
    lda text_colour                             // $94a2  
    sta font_byte_mask                          // $94a5  
    lda #>msg_complete                          // $94a8  
    sta plot_string_ptr+1                       // $94aa  
    ldx #<msg_complete                          // $94ac  
    stx plot_string_ptr                         // $94ae  
    jmp write_message_continue                  // $94b0  
write_bonus:
    lda #$07                                    // $94b3  
    sta font_byte_mask                          // $94b5  
    lda #>msg_bonus                             // $94b8  
    sta plot_string_ptr+1                       // $94ba  
    ldx #<msg_bonus                             // $94bc  
    jsr write_message                           // $94be  
    ldy #$0a                                    // $94c1  
    lda #$70                                    // $94c3  
write_bonus_colour:
    sta (text_ptr),y                            // $94c5  
    dey                                         // $94c7  
    bpl write_bonus_colour                      // $94c8  
    rts                                         // $94ca  
write_failed:
    lda text_colour                             // $94cb  
    sta font_byte_mask                          // $94ce  
    lda #>msg_failed                            // $94d1  
    sta plot_string_ptr+1                       // $94d3  
    ldx #<msg_failed                            // $94d5  
    stx plot_string_ptr                         // $94d7  
    jmp write_message_continue                  // $94d9  
write_no_bonus:
    lda #$07                                    // $94dc  
    sta font_byte_mask                          // $94de  
    lda #>msg_no_bonus                          // $94e1  
    sta plot_string_ptr+1                       // $94e3  
    ldx #<msg_no_bonus                          // $94e5  
    jmp write_message                           // $94e7  
write_planet_destroyed:
    lda obj_colour_gun                          // $94ea  
    sta font_byte_mask                          // $94ed  
    lda #>msg_planet_destroyed                  // $94f0  
    sta plot_string_ptr+1                       // $94f2  
    ldx #<msg_planet_destroyed                  // $94f4  
    jmp write_message                           // $94f6  
write_reverse_gravity:
    lda #$07                                    // $94f9  
    sta font_byte_mask                          // $94fb  
    lda #>msg_reverse_gravity                   // $94fe  
    sta plot_string_ptr+1                       // $9500  
    ldx #<msg_reverse_gravity                   // $9502  
    jmp write_message                           // $9504  
write_invisible_landscape:
    lda #$07                                    // $9507  
    sta font_byte_mask                          // $9509  
    lda #>msg_invisible_landscape               // $950c  
    sta plot_string_ptr+1                       // $950e  
    ldx #<msg_invisible_landscape               // $9510  
    jmp write_message                           // $9512  
msg_mission:
    .byte $d8,$6c,$4d,$69,$73,$73,$69,$6f,$6e,$20,$ff  // $9515  ".lMission ."
msg_in:
    .byte $00,$00,$49,$6e,$ff                   // $9520  "..In."
msg_complete:
    .byte $00,$00,$43,$6f,$6d,$70,$6c,$65,$74,$65,$ff  // $9525  "..Complete."
msg_bonus:
    .byte $b8,$70,$42,$6f,$6e,$75,$73,$20,$ff   // $9530  ".pBonus ."
msg_failed:
    .byte $00,$00,$46,$61,$69,$6c,$65,$64,$ff   // $9539  "..Failed."
msg_no_bonus:
    .byte $c0,$70,$4e,$6f,$20,$42,$6f,$6e,$75,$73,$ff  // $9542  ".pNo Bonus."
msg_planet_destroyed:
    .byte $20,$69,$50,$6c,$61,$6e,$65,$74,$20,$44,$65,$73,$74,$72,$6f,$79  // $954d  " iPlanet Destroy"
    .byte $65,$64,$ff                           // $955d  "ed."
msg_reverse_gravity:
    .byte $e0,$6c,$52,$65,$76,$65,$72,$73,$65,$20,$47,$72,$61,$76,$69,$74  // $9560  ".lReverse Gravit"
    .byte $79,$ff                               // $9570  "y."
msg_invisible_landscape:
    .byte $d0,$6c,$49,$6e,$76,$69,$73,$69,$62,$6c,$65,$20,$4c,$61,$6e,$64  // $9572  ".lInvisible Land"
    .byte $73,$63,$61,$70,$65,$ff               // $9582  "scape."
ship_input_thrust_calculate_force:
    lda pod_destroying_player_timer             // $9588  
    bmi L959f                                   // $958a  if ship is being destroyed, continue
    lda pod_attached_flag_1                     // $958c  
    bne L959f                                   // $958e  if pod attached, continue
    lda player_ship_destroyed_flag              // $9590  
    bne L959f                                   // $9592  if ship destroyed, continue
    lda #$00                                    // $9594  
    sta velocity_vectory_INT                    // $9596  clear vertical velocity (INT)
    sta velocity_vectory_FRAC                   // $9598  clear vertical velocity (FRAC)
    sta velocity_vectorx_INT                    // $959a  clear horizontal velocity (INT)
    sta velocity_vectorx_FRAC                   // $959c  clear horizontal velocity (FRAC)
    rts                                         // $959e  no physics this tick
L959f:
    lda level_tick_counter                      // $959f  
    and #$0f                                    // $95a1  
    beq add_gravity_to_velocity_vector          // $95a3  
    cmp #$03                                    // $95a5  
    beq add_gravity_to_velocity_vector          // $95a7  
    cmp #$05                                    // $95a9  
    beq add_gravity_to_velocity_vector          // $95ab  
    cmp #$08                                    // $95ad  
    beq add_gravity_to_velocity_vector          // $95af  
    cmp #$0b                                    // $95b1  
    beq add_gravity_to_velocity_vector          // $95b3  
    cmp #$0d                                    // $95b5  
    beq add_gravity_to_velocity_vector          // $95b7  
    rts                                         // $95b9  inactive tick -> exit
add_gravity_to_velocity_vector:
    clc                                         // $95ba  
    lda velocity_vectory_FRAC                   // $95bb  
    adc gravity_FRAC                            // $95bd  
    sta velocity_vectory_FRAC                   // $95bf  
    lda velocity_vectory_INT                    // $95c1  
    adc gravity_INT                             // $95c3  
    sta velocity_vectory_INT                    // $95c5  
    lda pod_destroying_player_timer             // $95c7  
    bpl no_thrust                               // $95c9  disable thrust while dying
    lda fuel_just_ran_out_flag                  // $95cb  
    bne no_thrust                               // $95cd  no fuel -> no thrust
    ldx #KEY_RSHIFT                             // $95cf  
    jsr test_inkey                              // $95d1  
    beq thrust_was_pressed                      // $95d4  
    ldx #KEY_LSHIFT                             // $95d6  
    jsr test_inkey                              // $95d8  test thrust key
    beq thrust_was_pressed                      // $95db  
no_thrust:
    jmp end_of_thrust_force_calculation         // $95dd  
thrust_was_pressed:
    jsr use_fuel                                // $95e0  
    jsr run_engine                              // $95e3  
    ldy #$04                                    // $95e6  
    lda pod_attached_flag_1                     // $95e8  
    beq L95ed                                   // $95ea  
    iny                                         // $95ec  
L95ed:
    ldx ship_angle                              // $95ed  
    lda angle_to_y_FRAC,x                       // $95ef  
    sta calc_velocity_vectory_FRAC              // $95f2  
    lda angle_to_y_INT,x                        // $95f4  
L95f7:
    ror                                         // $95f7  divide by 2 per iteration
    ror calc_velocity_vectory_FRAC              // $95f8  
    dey                                         // $95fa  
    bne L95f7                                   // $95fb  
    and #$01                                    // $95fd  recover sign bit
    eor #$ff                                    // $95ff  
    clc                                         // $9601  
    adc #$01                                    // $9602  
    sta calc_velocity_vectory_INT               // $9604  signed vertical thrust component
    ldy #$04                                    // $9606  
    lda pod_attached_flag_1                     // $9608  
    beq L960d                                   // $960a  
    iny                                         // $960c  
L960d:
    lda angle_to_x_FRAC,x                       // $960d  
    sta calc_velocity_vectorx_FRAC              // $9610  X thrust fractional part
    lda angle_to_x_INT,x                        // $9612  X thrust integer part
L9615:
    ror                                         // $9615  scale thrust (>> 1)
    ror calc_velocity_vectorx_FRAC              // $9616  
    ror calc_velocity_vectorx_FRAC_LO           // $9618  extra precision for X
    dey                                         // $961a  
    bne L9615                                   // $961b  repeat for mass scaling
    and #$01                                    // $961d  extract sign bit
    eor #$ff                                    // $961f  
    clc                                         // $9621  
    adc #$01                                    // $9622  
    sta calc_velocity_vectorx_INT               // $9624  signed X thrust component
    clc                                         // $9626  
    lda velocity_vectorx_FRAC_LO                // $9627  
    adc calc_velocity_vectorx_FRAC_LO           // $9629  
    sta velocity_vectorx_FRAC_LO                // $962b  
    lda velocity_vectorx_FRAC                   // $962d  
    adc calc_velocity_vectorx_FRAC              // $962f  
    sta velocity_vectorx_FRAC                   // $9631  
    lda velocity_vectorx_INT                    // $9633  
    adc calc_velocity_vectorx_INT               // $9635  
    sta velocity_vectorx_INT                    // $9637  
    clc                                         // $9639  
    lda velocity_vectory_FRAC                   // $963a  
    adc calc_velocity_vectory_FRAC              // $963c  
    sta velocity_vectory_FRAC                   // $963e  
    lda velocity_vectory_INT                    // $9640  
    adc calc_velocity_vectory_INT               // $9642  
    sta velocity_vectory_INT                    // $9644  
    lda level_tick_counter                      // $9646  
    and #$0f                                    // $9648  
    cmp #$03                                    // $964a  
    bne L9651                                   // $964c  
    jmp end_of_thrust_force_calculation         // $964e  
L9651:
    cmp #$0b                                    // $9651  
    bne L9658                                   // $9653  
    jmp end_of_thrust_force_calculation         // $9655  
L9658:
    lda #$00                                    // $9658  
    sta thrust_sign_extend                      // $965a  clear sign extension
    sec                                         // $965c  
    sbc tether_angle_FRAC                       // $965d  
    sta thrust_angle_sub_frac                   // $965f  -tether angle fraction
    lda ship_angle                              // $9661  
    sbc angle_ship_to_pod                       // $9663  
    tay                                         // $9665  angular difference (integer)
    lda thrust_angle_sub_frac                   // $9666  
    clc                                         // $9668  
    adc #$08                                    // $9669  center fractional range
    sta thrust_angle_sub_frac                   // $966b  
    tya                                         // $966d  
    adc #$00                                    // $966e  propagate carry into angle
    and #ANGLE_MASK                             // $9670  
    tay                                         // $9672  
    lda angle_to_x_FRAC,y                       // $9673  
    sta ship_thrust_x_FRAC                      // $9676  
    lda angle_to_x_INT,y                        // $9678  
    sta ship_thrust_x_INT                       // $967b  
    ldx #$0e                                    // $967d  interpolation count
L967f:
    lda thrust_angle_sub_frac                   // $967f  fractional angular difference
    and #$f0                                    // $9681  extract high nibble
    cmp lookup_top_nibble,x                     // $9683  compare against interpolation table
    bne L968d                                   // $9686  
    iny                                         // $9688  advance angle index when matched
    tya                                         // $9689  
    and #ANGLE_MASK                             // $968a  
    tay                                         // $968c  
L968d:
    clc                                         // $968d  
    lda angle_to_x_FRAC,y                       // $968e  
    adc ship_thrust_x_FRAC                      // $9691  accumulate tangential thrust (frac)
    sta ship_thrust_x_FRAC                      // $9693  
    lda angle_to_x_INT,y                        // $9695  
    adc ship_thrust_x_INT                       // $9698  accumulate tangential thrust (int)
    sta ship_thrust_x_INT                       // $969a  
    dex                                         // $969c  
    bpl L967f                                   // $969d  repeat interpolation steps
    lda ship_thrust_x_INT                       // $969f  
    rol                                         // $96a1  
    ror ship_thrust_x_INT                       // $96a2  
    ror ship_thrust_x_FRAC                      // $96a4  arithmetic right shift (/2)
    lda ship_thrust_x_INT                       // $96a6  
    bpl L96ae                                   // $96a8  
    lda #$ff                                    // $96aa  
    sta thrust_sign_extend                      // $96ac  sign extension for negative values
L96ae:
    clc                                         // $96ae  
    lda tether_angular_vel_LO                   // $96af  
    sta prev_tether_vel_LO                      // $96b1  
    adc ship_thrust_x_FRAC                      // $96b3  
    sta tether_angular_vel_LO                   // $96b5  
    lda tether_angular_vel_FRAC                 // $96b7  
    sta prev_tether_vel_FRAC                    // $96b9  
    adc ship_thrust_x_INT                       // $96bb  
    sta tether_angular_vel_FRAC                 // $96bd  
    lda tether_angular_vel_INT                  // $96bf  
    sta prev_tether_vel_INT                     // $96c1  
    adc thrust_sign_extend                      // $96c3  
    sta tether_angular_vel_INT                  // $96c5  
    lda prev_tether_vel_INT                     // $96c7  
    ldx #$06                                    // $96c9  divide by 64
L96cb:
    pha                                         // $96cb  
    rol                                         // $96cc  
    pla                                         // $96cd  
    ror                                         // $96ce  
    ror prev_tether_vel_FRAC                    // $96cf  
    ror prev_tether_vel_LO                      // $96d1  
    dex                                         // $96d3  
    bne L96cb                                   // $96d4  
    sta prev_tether_vel_INT                     // $96d6  damped angular velocity
    clc                                         // $96d8  
    lda tether_angular_vel_LO                   // $96d9  
    sbc prev_tether_vel_LO                      // $96db  
    sta tether_angular_vel_LO                   // $96dd  
    lda tether_angular_vel_FRAC                 // $96df  
    sbc prev_tether_vel_FRAC                    // $96e1  
    sta tether_angular_vel_FRAC                 // $96e3  
    lda tether_angular_vel_INT                  // $96e5  
    sbc prev_tether_vel_INT                     // $96e7  
    sta tether_angular_vel_INT                  // $96e9  
end_of_thrust_force_calculation:
    lda velocity_vectorx_FRAC_LO                // $96eb  
    sta calc_velocity_vectory_FRAC              // $96ed  
    lda velocity_vectorx_FRAC                   // $96ef  
    sta calc_velocity_vectory_INT               // $96f1  
    lda velocity_vectorx_INT                    // $96f3  
    ldx #$06                                    // $96f5  X drag divisor
L96f7:
    pha                                         // $96f7  
    rol                                         // $96f8  
    pla                                         // $96f9  
    ror                                         // $96fa  
    ror calc_velocity_vectory_INT               // $96fb  
    ror calc_velocity_vectory_FRAC              // $96fd  
    dex                                         // $96ff  
    bne L96f7                                   // $9700  
    sta calc_velocity_vectorx_FRAC              // $9702  
    sec                                         // $9704  
    lda velocity_vectorx_FRAC_LO                // $9705  
    sbc calc_velocity_vectory_FRAC              // $9707  
    sta velocity_vectorx_FRAC_LO                // $9709  
    lda velocity_vectorx_FRAC                   // $970b  
    sbc calc_velocity_vectory_INT               // $970d  
    sta velocity_vectorx_FRAC                   // $970f  
    lda velocity_vectorx_INT                    // $9711  
    sbc calc_velocity_vectorx_FRAC              // $9713  
    sta velocity_vectorx_INT                    // $9715  
    lda #$00                                    // $9717  
    sta calc_velocity_vectorx_INT               // $9719  
    lda velocity_vectory_INT                    // $971b  
    bpl L9723                                   // $971d  
    lda #$ff                                    // $971f  
    sta calc_velocity_vectorx_INT               // $9721  
L9723:
    lda velocity_vectory_FRAC                   // $9723  
    sta calc_velocity_vectory_FRAC              // $9725  
    lda velocity_vectory_INT                    // $9727  
    sta calc_velocity_vectory_INT               // $9729  
    lda calc_velocity_vectorx_INT               // $972b  
    ldx #$08                                    // $972d  Y drag divisor
L972f:
    pha                                         // $972f  
    rol                                         // $9730  
    pla                                         // $9731  
    ror                                         // $9732  
    ror calc_velocity_vectory_INT               // $9733  
    ror calc_velocity_vectory_FRAC              // $9735  
    dex                                         // $9737  
    bne L972f                                   // $9738  
    sta calc_velocity_vectorx_FRAC              // $973a  
    sec                                         // $973c  
    lda velocity_vectory_FRAC                   // $973d  
    sbc calc_velocity_vectory_FRAC              // $973f  
    sta velocity_vectory_FRAC                   // $9741  
    lda velocity_vectory_INT                    // $9743  
    sbc calc_velocity_vectory_INT               // $9745  
    sta velocity_vectory_INT                    // $9747  
    lda calc_velocity_vectorx_INT               // $9749  
    sbc calc_velocity_vectorx_FRAC              // $974b  final sign correction
    sta calc_velocity_vectorx_INT               // $974d  
    rts                                         // $974f  
lookup_top_nibble:
    .byte $10,$20,$30,$40,$50,$60,$70,$80,$90,$a0,$b0,$c0,$d0,$e0,$f0  // $9750  
test_for_pause:
    ldx #KEY_F5                                 // $975f  
    jsr test_inkey                              // $9761  
    bne not_paused                              // $9764  
    lda shield_tractor_pressed                  // $9766  
    bne not_paused                              // $9768  
pause_loop:
    lda #$01                                    // $976a  paused: wait for F7
    sta level_tick_state                        // $976c  
    ldx #KEY_F7                                 // $976e  
    jsr test_inkey                              // $9770  
    bne pause_loop                              // $9773  
    jsr reset_game_tick                         // $9775  resync game timer
    lda #$00                                    // $9778  
    sta level_tick_state                        // $977a  
not_paused:
    rts                                         // $977c  
test_sound_keys:
    ldx #KEY_F1                                 // $977d  
    jsr test_key                                // $977f  
    bne test_sound_on_key                       // $9782  
    stx mute_sound_flag                         // $9784  F1: X = $FF -> mute
test_sound_on_key:
    ldx #KEY_F3                                 // $9786  
    jsr test_key                                // $9788  
    bne test_sound_keys_return                  // $978b  
    lda #$00                                    // $978d  F3: sound on
    sta mute_sound_flag                         // $978f  
test_sound_keys_return:
    rts                                         // $9791  
ship_spr_y:
    .byte $00                                   // $9792  
ship_spr_x:
    .byte $00                                   // $9793  
ship_spr_x_msb:
    .byte $00                                   // $9794  
ship_spr_enable:
    .byte $00                                   // $9795  
ship_spr_frame:
    .byte $00                                   // $9796  
shield_colour:
    .byte $00                                   // $9797  
ship_colour:
    .byte $00                                   // $9798  
plot_ship_and_pod:
    jsr calculate_attached_pod_vector           // $9799  calculate pod position from the tether
    lda ship_sprite_plotted_flag                // $979c  
    bne plot_ship_visible                       // $979e  
    lda #$00                                    // $97a0  
    sta ship_spr_enable                         // $97a2  
    jmp plot_ship_sprite                        // $97a5  
plot_ship_visible:
    lda #$07                                    // $97a8  ship colour: yellow
    sta ship_colour                             // $97aa  
ship_input_shield_tractor:
    lda #$00                                    // $97ad  
    sta shield_tractor_pressed                  // $97af  
    sta sheild_tractor_flag                     // $97b1  
    lda pod_destroying_player_timer             // $97b3  
    bpl no_sheild_tractor                       // $97b5  
    lda fuel_just_ran_out_flag                  // $97b7  
    bne no_sheild_tractor                       // $97b9  
    ldx #KEY_SPACE                              // $97bb  
    jsr test_inkey                              // $97bd  
    stx shield_tractor_pressed                  // $97c0  
    cpx #$00                                    // $97c2  
    beq no_sheild_tractor                       // $97c4  
    lda vsync_count                             // $97c6  
    and #$02                                    // $97c8  
    beq no_sheild_tractor                       // $97ca  
    lda #$01                                    // $97cc  
    sta sheild_tractor_flag                     // $97ce  
    lda shield_colour                           // $97d0  shield on: shield colour
    sta ship_colour                             // $97d3  
    jsr use_fuel                                // $97d6  
    jsr shield_sound                            // $97d9  shield hum
no_sheild_tractor:
    lda #$00                                    // $97dc  
    sta ship_sprite_plotted_flag                // $97de  
plot_ship_sprite:
    lda ship_angle                              // $97e0  sprite frame = ship angle (frames 0-31)
    sta plot_ship_sprite_number                 // $97e2  
    sta old_plot_ship_sprite_number             // $97e4  
    lda sheild_tractor_flag                     // $97e6  
    beq plot_ship_calc_y                        // $97e8  
    lda #$ff                                    // $97ea  $FF = shield
    sta plot_ship_sprite_number                 // $97ec  
    sta old_plot_ship_sprite_number             // $97ee  
plot_ship_calc_y:
    clc                                         // $97f0  
    lda midpoint_ypos_FRAC                      // $97f1  
    adc midpoint_deltay_FRAC                    // $97f3  
    sta ship_window_ypos_FRAC                   // $97f5  
    lda midpoint_window_ypos_INT                // $97f7  
    adc midpoint_deltay_INT                     // $97f9  
    sta ship_spr_y_calc                         // $97fb  
    ldx ship_angle                              // $97fd  
    lda plot_ship_sprite_number                 // $97ff  
    bpl plot_ship_calc_x                        // $9801  
    lda angle_to_y_FRAC,x                       // $9803  
    sta calc_ship_delta_FRAC                    // $9806  
    lda angle_to_y_INT,x                        // $9808  
    sta calc_ship_delta_INT                     // $980b  
    rol                                         // $980d  
    ror calc_ship_delta_INT                     // $980e  
    lda calc_ship_delta_FRAC                    // $9810  
    ror                                         // $9812  
    adc ship_window_ypos_FRAC                   // $9813  
    sta ship_window_ypos_FRAC                   // $9815  
    lda calc_ship_delta_INT                     // $9817  
    adc ship_spr_y_calc                         // $9819  
    sta ship_spr_y_calc                         // $981b  
plot_ship_calc_x:
    rol ship_window_ypos_FRAC                   // $981d  Y * 2 (half vertical resolution)
    rol ship_spr_y_calc                         // $981f  
    clc                                         // $9821  
    lda midpoint_xpos_FRAC_LO                   // $9822  
    adc midpoint_deltax_FRAC_LO                 // $9824  
    lda midpoint_xpos_FRAC                      // $9826  
    adc midpoint_deltax_FRAC                    // $9828  
    pha                                         // $982a  
    lda midpoint_window_xpos_INT                // $982b  
    adc midpoint_deltax_INT                     // $982d  
    sta calc_ship_window_xpos_INT               // $982f  
    lda plot_ship_sprite_number                 // $9831  
    bpl plot_ship_sprite_x                      // $9833  
    lda angle_to_x_FRAC,x                       // $9835  
    sta calc_ship_delta_FRAC                    // $9838  
    lda angle_to_x_INT,x                        // $983a  
    sta calc_ship_delta_INT                     // $983d  
    rol                                         // $983f  
    ror calc_ship_delta_INT                     // $9840  
    ror calc_ship_delta_FRAC                    // $9842  
    pla                                         // $9844  
    adc calc_ship_delta_FRAC                    // $9845  
    pha                                         // $9847  
    lda calc_ship_window_xpos_INT               // $9848  
    adc calc_ship_delta_INT                     // $984a  
    sta calc_ship_window_xpos_INT               // $984c  
plot_ship_sprite_x:
    lda calc_ship_window_xpos_INT               // $984e  
    sta ship_spr_x_calc                         // $9850  X * 4: world X is in 4-pixel units
    pla                                         // $9852  
    rol                                         // $9853  
    rol ship_spr_x_calc                         // $9854  
    rol                                         // $9856  
    rol ship_spr_x_calc                         // $9857  
    lda ship_spr_x_calc                         // $9859  
    clc                                         // $985b  
    adc #$1e                                    // $985c  + left border
    bcc plot_ship_x_lt_256                      // $985e  
    sta ship_spr_x                              // $9860  
    sta ship_window_xpos_FRAC                   // $9863  
    lda #$80                                    // $9865  X > 255: set bit 7 of $D010 (sprite 7)
    sta ship_spr_x_msb                          // $9867  
    lda #$01                                    // $986a  
    sta ship_window_xpos_INT                    // $986c  
    jmp plot_ship_sprite_y                      // $986e  
plot_ship_x_lt_256:
    sta ship_spr_x                              // $9871  
    sta ship_window_xpos_FRAC                   // $9874  
    lda #$00                                    // $9876  
    sta ship_spr_x_msb                          // $9878  
    lda #$00                                    // $987b  
    sta ship_window_xpos_INT                    // $987d  
plot_ship_sprite_y:
    lda ship_spr_y_calc                         // $987f  
    clc                                         // $9881  
    adc #$32                                    // $9882  + top border
    sta ship_spr_y                              // $9884  
    sta ship_window_ypos_INT                    // $9887  
    lda plot_ship_sprite_number                 // $9889  
    bpl plot_ship_set_frame                     // $988b  
    lda #$20                                    // $988d  frame $20 = shield
plot_ship_set_frame:
    sta ship_spr_frame                          // $988f  
    lda player_ship_destroyed_flag              // $9892  
    bmi plot_ship_test_hit                      // $9894  
    lda #$00                                    // $9896  
    sta player_ship_destroyed_flag              // $9898  
    sta ship_spr_enable                         // $989a  
    jmp plot_pod_sprite                         // $989d  and the pod
plot_ship_test_hit:
    lda plot_ship_collision_detected            // $98a0  
    bne L98ae                                   // $98a2  
    lda #$80                                    // $98a4  enable sprite 7
    sta ship_spr_enable                         // $98a6  
    lda #$01                                    // $98a9  
    sta ship_sprite_plotted_flag                // $98ab  
    cli                                         // $98ad  
L98ae:
    jsr plot_pod_sprite                         // $98ae  
plot_ship_return:
    rts                                         // $98b1  
calculate_attached_pod_vector:
    lda tether_angle_FRAC                       // $98b2  fractional angle (0-255)
    clc                                         // $98b4  
    adc #$08                                    // $98b5  bias by +8
    sta pod_angle_sub_frac                      // $98b7  store (fraction + 8)
    lda angle_ship_to_pod                       // $98b9  integer angle (0-31)
    adc #$00                                    // $98bb  add carry from frac+8
    and #ANGLE_MASK                             // $98bd  wrap into 32-entry table
    tay                                         // $98bf  Y = starting angle index
    lda angle_to_x_FRAC,y                       // $98c0  
    sta midpoint_deltax_FRAC                    // $98c3  
    lda angle_to_x_INT,y                        // $98c5  
    sta midpoint_deltax_INT                     // $98c8  
    lda angle_to_y_FRAC,y                       // $98ca  
    sta midpoint_deltay_FRAC                    // $98cd  
    lda angle_to_y_INT,y                        // $98cf  
    sta midpoint_deltay_INT                     // $98d2  
    ldx tether_length                           // $98d4  typically initialised to $0E (14)
L98d6:
    lda pod_angle_sub_frac                      // $98d6  (fraction + 8)
    and #$f0                                    // $98d8  extract top nibble
    cmp lookup_top_nibble,x                     // $98da  does angle advance here?
    bne L98e4                                   // $98dd  
    iny                                         // $98df  switch to angle + 1
    tya                                         // $98e0  
    and #ANGLE_MASK                             // $98e1  
    tay                                         // $98e3  
L98e4:
    clc                                         // $98e4  
    lda angle_to_x_FRAC,y                       // $98e5  
    adc midpoint_deltax_FRAC                    // $98e8  
    sta midpoint_deltax_FRAC                    // $98ea  
    lda angle_to_x_INT,y                        // $98ec  
    adc midpoint_deltax_INT                     // $98ef  
    sta midpoint_deltax_INT                     // $98f1  
    clc                                         // $98f3  
    lda angle_to_y_FRAC,y                       // $98f4  
    adc midpoint_deltay_FRAC                    // $98f7  
    sta midpoint_deltay_FRAC                    // $98f9  
    lda angle_to_y_INT,y                        // $98fb  
    adc midpoint_deltay_INT                     // $98fe  
    sta midpoint_deltay_INT                     // $9900  
    dex                                         // $9902  
    bpl L98d6                                   // $9903  loop while X >= 0
    lda midpoint_deltax_INT                     // $9905  
    rol                                         // $9907  
    ror midpoint_deltax_INT                     // $9908  
    ror midpoint_deltax_FRAC                    // $990a  
    ror midpoint_deltax_FRAC_LO                 // $990c  >> 1
    lda midpoint_deltax_INT                     // $990e  
    rol                                         // $9910  
    ror midpoint_deltax_INT                     // $9911  
    ror midpoint_deltax_FRAC                    // $9913  
    ror midpoint_deltax_FRAC_LO                 // $9915  >> 1 again (/4 total)
    lda midpoint_deltay_INT                     // $9917  
    rol                                         // $9919  
    ror midpoint_deltay_INT                     // $991a  
    ror midpoint_deltay_FRAC                    // $991c  >> 1
    lda midpoint_deltay_INT                     // $991e  
    rol                                         // $9920  
    ror midpoint_deltay_INT                     // $9921  
    ror midpoint_deltay_FRAC                    // $9923  >> 1 again (/4 total)
    rts                                         // $9925  
update_pod_tractor_beam:
    lda pod_sprite_plotted_flag                 // $9926  
    bne L9934                                   // $9928  
    lda level_obj_flags                         // $992a  what's special about first entry in table?
    and #$03                                    // $992d  
    cmp #$03                                    // $992f  
    beq L9934                                   // $9931  
    rts                                         // $9933  
L9934:
    lda pod_attached_flag_2                     // $9934  
    bmi tractor_beam_return                     // $9937  
    lda shield_tractor_pressed                  // $9939  
    bne do_pod_tractor_beam                     // $993b  
    sta tractor_beam_started_flag               // $993d  
    rts                                         // $993f  
do_pod_tractor_beam:
    lda pod_destroying_player_timer             // $9940  
    bpl tractor_beam_return                     // $9942  
    lda tractor_beam_started_flag               // $9944  
    sta pod_line_exists_flag                    // $9946  
    jsr get_distance_ship_to_pod_tractor        // $9948  must return distance?
    cmp #TRACTOR_BEAM_ACTIVATE_DIST             // $994b  
    bcc set_flag                                // $994d  
    cmp #TRACTOR_BEAM_ATTACH_DIST               // $994f  must be distance of ship from pod stand
    bcs attach_pod_to_ship                      // $9951  
    rts                                         // $9953  
set_flag:
    lda #$01                                    // $9954  
    sta tractor_beam_started_flag               // $9956  
    sta pod_line_exists_flag                    // $9958  
tractor_beam_return:
    rts                                         // $995a  
attach_pod_to_ship:
    lda tractor_beam_started_flag               // $995b  exit if tractor beam inactive
    beq tractor_beam_return                     // $995d  
    lda #$0a                                    // $995f  
    sta collision_ignore_timer                  // $9961  
    lda #$ff                                    // $9964  mark pod as attached
    sta pod_attached_flag_1                     // $9966  
    sta pod_attached_flag_2                     // $9968  
    sta level_reset_with_pod_flag               // $996b  
    clc                                         // $996e  
    lda player_xpos_FRAC                        // $996f  
    adc nearest_obj_xpos_FRAC                   // $9971  
    sta midpoint_xpos_FRAC                      // $9973  
    lda player_xpos_INT                         // $9975  
    adc nearest_obj_xpos_INT                    // $9977  
    ror                                         // $9979  
    sta midpoint_xpos_INT                       // $997a  
    ror midpoint_xpos_FRAC                      // $997c  
    clc                                         // $997e  
    lda player_ypos_FRAC                        // $997f  
    adc #$80                                    // $9981  +0.5 for divide-by-2 rounding
    sta midpoint_ypos_FRAC                      // $9983  
    lda player_ypos_INT                         // $9985  
    adc nearest_obj_ypos_INT                    // $9987  
    sta midpoint_ypos_INT                       // $9989  
    lda player_ypos_INT_HI                      // $998b  
    adc nearest_obj_ypos_INT_HI                 // $998d  
    ror                                         // $998f  
    sta midpoint_ypos_INT_HI                    // $9990  
    ror midpoint_ypos_INT                       // $9992  
    ror midpoint_ypos_FRAC                      // $9994  
    lda velocity_vectory_INT                    // $9996  
    rol                                         // $9998  
    ror velocity_vectory_INT                    // $9999  
    ror velocity_vectory_FRAC                   // $999b  
    lda velocity_vectorx_INT                    // $999d  
    rol                                         // $999f  
    ror velocity_vectorx_INT                    // $99a0  
    ror velocity_vectorx_FRAC                   // $99a2  
    ror velocity_vectorx_FRAC_LO                // $99a4  X uses extra precision (Q7.16)
    lda player_xpos_FRAC                        // $99a6  
    sbc midpoint_xpos_FRAC                      // $99a8  
    sta attach_pod_delta_x_frac                 // $99aa  target dX frac
    lda player_xpos_INT                         // $99ac  
    sbc midpoint_xpos_INT                       // $99ae  target dX int
    sta delta_x_shifted                         // $99b0  
    rol attach_pod_delta_x_frac                 // $99b2  
    rol delta_x_shifted                         // $99b4  
    rol attach_pod_delta_x_frac                 // $99b6  
    rol delta_x_shifted                         // $99b8  X scaled x4
    lda delta_x_shifted                         // $99ba  
    sta delta_x_scaled                          // $99bc  store target dX int
    lda player_ypos_FRAC                        // $99be  
    sbc midpoint_ypos_FRAC                      // $99c0  
    sta delta_y_frac                            // $99c2  target dY frac
    lda player_ypos_INT                         // $99c4  
    sbc midpoint_ypos_INT                       // $99c6  
    sta delta_y_shifted                         // $99c8  target dY int
    rol delta_y_frac                            // $99ca  
    rol delta_y_shifted                         // $99cc  Y scaled x2
    lda delta_y_shifted                         // $99ce  
    sta attach_pod_delta_y_scaled               // $99d0  store target dY int
    lda #$0a                                    // $99d2  
    sta angle_step_int                          // $99d4  stepHi
    lda #$ab                                    // $99d6  
    sta angle_step_frac                         // $99d8  stepLo
    lda #$07                                    // $99da  
    sta search_iterations                       // $99dc  number of passes
    lda #$00                                    // $99de  
    sta tether_angle_FRAC                       // $99e0  starting angleFrac
    sta angle_ship_to_pod                       // $99e2  starting integer angle
L99e4:
    lda #$ff                                    // $99e4  
    sta best_distance                           // $99e6  best distance this pass
    ldx #$03                                    // $99e8  
    stx search_inner_count                      // $99ea  3 candidate angles
L99ec:
    jsr calculate_attached_pod_vector           // $99ec  compute candidate tether vector
    rol midpoint_deltax_FRAC                    // $99ef  
    rol midpoint_deltax_INT                     // $99f1  
    rol midpoint_deltax_FRAC                    // $99f3  
    rol midpoint_deltax_INT                     // $99f5  X scaled x4
    rol midpoint_deltay_FRAC                    // $99f7  
    rol midpoint_deltay_INT                     // $99f9  Y scaled x2
    sec                                         // $99fb  
    lda midpoint_deltax_INT                     // $99fc  
    sbc delta_x_shifted                         // $99fe  
    bpl L9a06                                   // $9a00  
    eor #$ff                                    // $9a02  
    adc #$01                                    // $9a04  
L9a06:
    sta multiply_operand_a                      // $9a06  |deltaX|
    sec                                         // $9a08  
    lda midpoint_deltay_INT                     // $9a09  
    sbc delta_y_shifted                         // $9a0b  
    bpl L9a13                                   // $9a0d  
    eor #$ff                                    // $9a0f  
    adc #$01                                    // $9a11  
L9a13:
    sta multiply_result_lo                      // $9a13  |deltaY|
    jsr get_distance_ship_to_pod_tractor_ext    // $9a15  
    cmp best_distance                           // $9a18  
    bcs L9a26                                   // $9a1a  
    sta best_distance                           // $9a1c  new best distance
    lda tether_angle_FRAC                       // $9a1e  
    sta prev_tether_vel_LO                      // $9a20  save best frac
    lda angle_ship_to_pod                       // $9a22  
    sta temp_angle_ship_to_pod                  // $9a24  save best int
L9a26:
    clc                                         // $9a26  
    lda tether_angle_FRAC                       // $9a27  
    adc angle_step_frac                         // $9a29  
    sta tether_angle_FRAC                       // $9a2b  
    lda angle_ship_to_pod                       // $9a2d  
    adc angle_step_int                          // $9a2f  
    and #ANGLE_MASK                             // $9a31  
    sta angle_ship_to_pod                       // $9a33  
    dec search_inner_count                      // $9a35  
    bne L99ec                                   // $9a37  test next candidate
    lda prev_tether_vel_LO                      // $9a39  
    sta tether_angle_FRAC                       // $9a3b  
    lda temp_angle_ship_to_pod                  // $9a3d  
    sta angle_ship_to_pod                       // $9a3f  
    clc                                         // $9a41  
    ror angle_step_int                          // $9a42  step >> 1 (Q8.8)
    ror angle_step_frac                         // $9a44  
    dec search_iterations                       // $9a46  
    beq L9a5c                                   // $9a48  after 7 passes, done
    sec                                         // $9a4a  
    lda tether_angle_FRAC                       // $9a4b  
    sbc angle_step_frac                         // $9a4d  
    sta tether_angle_FRAC                       // $9a4f  
    lda angle_ship_to_pod                       // $9a51  
    sbc angle_step_int                          // $9a53  
    and #ANGLE_MASK                             // $9a55  
    sta angle_ship_to_pod                       // $9a57  
    jmp L99e4                                   // $9a59  
L9a5c:
    lda velocity_vectorx_INT                    // $9a5c  
    sta multiply_operand_a                      // $9a5e  
    lda velocity_vectorx_FRAC                   // $9a60  
    rol                                         // $9a62  
    rol multiply_operand_a                      // $9a63  
    rol                                         // $9a65  
    rol multiply_operand_a                      // $9a66  
    rol                                         // $9a68  
    rol multiply_operand_a                      // $9a69  
    rol                                         // $9a6b  
    rol multiply_operand_a                      // $9a6c  velX x 16 (scale-alignment)
    lda attach_pod_delta_y_scaled               // $9a6e  dy (midpoint -> ship, pre-scaled)
    jsr attach_pod_calculate_signed_multiply    // $9a70  signed multiply: velX * dy
    lda multiply_result_lo                      // $9a73  
    sta cross_product_term_lo                   // $9a75  
    lda multiply_result_hi                      // $9a77  
    sta cross_product_term_hi                   // $9a79  
    lda velocity_vectory_INT                    // $9a7b  
    sta multiply_operand_a                      // $9a7d  
    lda velocity_vectory_FRAC                   // $9a7f  
    rol                                         // $9a81  
    rol multiply_operand_a                      // $9a82  
    rol                                         // $9a84  
    rol multiply_operand_a                      // $9a85  
    rol                                         // $9a87  
    rol multiply_operand_a                      // $9a88  
    rol                                         // $9a8a  
    rol multiply_operand_a                      // $9a8b  velY x 16 (scale-alignment)
    lda delta_x_scaled                          // $9a8d  dx (midpoint -> ship, pre-scaled)
    jsr attach_pod_calculate_signed_multiply    // $9a8f  signed multiply: velY * dx
    sec                                         // $9a92  
    lda multiply_result_lo                      // $9a93  
    sbc cross_product_term_lo                   // $9a95  
    sta tether_angular_vel_FRAC                 // $9a97  
    lda multiply_result_hi                      // $9a99  
    sbc cross_product_term_hi                   // $9a9b  
    pha                                         // $9a9d  
    rol                                         // $9a9e  
    pla                                         // $9a9f  
    ror                                         // $9aa0  
    ror tether_angular_vel_FRAC                 // $9aa1  
    pha                                         // $9aa3  
    rol                                         // $9aa4  
    pla                                         // $9aa5  
    ror                                         // $9aa6  
    ror tether_angular_vel_FRAC                 // $9aa7  
    sta tether_angular_vel_INT                  // $9aa9  final initial angular velocity
    jsr collect_pod_fuel_sound                  // $9aab  
    rts                                         // $9aae  
pod_colour:
    .byte $05                                   // $9aaf  
pod_spr_y:
    .byte $00                                   // $9ab0  
pod_spr_x:
    .byte $00                                   // $9ab1  
pod_spr_x_msb:
    .byte $00                                   // $9ab2  
pod_spr_enable:
    .byte $00                                   // $9ab3  
plot_pod_sprite:
    lda #$00                                    // $9ab4  
    sta plot_pod_collision_detected             // $9ab6  
    lda #$21                                    // $9ab8  sprite 6 frame $21 = pod
    sta sprite_pointers_screen_A+$06            // $9aba  
    sta sprite_pointers_screen_B+$06            // $9abd  
    lda pod_sprite_plotted_flag                 // $9ac0  
    beq plot_pod_test_attached                  // $9ac2  
    lda #$00                                    // $9ac4  
    sta pod_sprite_plotted_flag                 // $9ac6  
    sta pod_spr_enable                          // $9ac8  
plot_pod_test_attached:
    lda pod_attached_flag_2                     // $9acb  
    bne plot_pod_calc                           // $9ace  
    jmp plot_pod_return                         // $9ad0  
plot_pod_calc:
    sec                                         // $9ad3  
    lda midpoint_ypos_FRAC                      // $9ad4  
    sbc midpoint_deltay_FRAC                    // $9ad6  
    sta pod_temp                                // $9ad8  
    lda midpoint_window_ypos_INT                // $9ada  
    sbc midpoint_deltay_INT                     // $9adc  
    rol pod_temp                                // $9ade  
    rol                                         // $9ae0  
    clc                                         // $9ae1  
    adc #$32                                    // $9ae2  + top border
    sta pod_spr_y                               // $9ae4  
    sta pod_window_ypos_INT                     // $9ae7  
    sec                                         // $9ae9  
    lda midpoint_xpos_FRAC_LO                   // $9aea  
    sbc midpoint_deltax_FRAC_LO                 // $9aec  
    lda midpoint_xpos_FRAC                      // $9aee  
    sbc midpoint_deltax_FRAC                    // $9af0  
    sta plot_pod_xpos_FRAC                      // $9af2  
    lda midpoint_window_xpos_INT                // $9af4  
    sbc midpoint_deltax_INT                     // $9af6  
    sta plot_pod_xpos_FRAC+1                    // $9af8  
    ldx pod_colour                              // $9afa  
    lda pod_attached_flag_1                     // $9afd  
    bne plot_pod_visible                        // $9aff  
    lda #$00                                    // $9b01  
    sta plot_pod_collision_detected             // $9b03  
    rts                                         // $9b05  
plot_pod_visible:
    lda #$01                                    // $9b06  
    sta pod_sprite_plotted_flag                 // $9b08  
    lda plot_pod_xpos_INT                       // $9b0a  
    sta pod_temp                                // $9b0c  
    lda plot_pod_xpos_FRAC                      // $9b0e  
    rol                                         // $9b10  
    rol pod_temp                                // $9b11  
    rol                                         // $9b13  
    rol pod_temp                                // $9b14  
    lda pod_temp                                // $9b16  
    clc                                         // $9b18  
    adc #$1e                                    // $9b19  + left border
    sta pod_spr_x                               // $9b1b  
    sta pod_window_xpos_FRAC                    // $9b1e  
    bcs plot_pod_x_ge_256                       // $9b20  
    lda #$00                                    // $9b22  
    sta pod_spr_x_msb                           // $9b24  
    lda #$00                                    // $9b27  
    sta pod_window_xpos_INT                     // $9b29  
    jmp plot_pod_enable                         // $9b2b  
plot_pod_x_ge_256:
    lda #$40                                    // $9b2e  X > 255: set bit 6 of $D010 (sprite 6)
    sta pod_spr_x_msb                           // $9b30  
    lda #$01                                    // $9b33  
    sta pod_window_xpos_INT                     // $9b35  
plot_pod_enable:
    lda pod_colour                              // $9b37  
    sta VIC_SPR6_COL                            // $9b3a  
    lda #$40                                    // $9b3d  enable sprite 6
    sta pod_spr_enable                          // $9b3f  
plot_pod_return:
    rts                                         // $9b42  
unused_rts:
    .byte $60                                   // $9b43  
sfx_volume:
    .byte $0f                                   // $9b44  
sfx_explosion_timer:
    .byte $00                                   // $9b45  
sfx_engine_timer:
    .byte $00                                   // $9b46  
sfx_shield_timer:
    .byte $00                                   // $9b47  
sfx_own_gun_timer:
    .byte $00                                   // $9b48  
sfx_hostile_gun_timer:
    .byte $00                                   // $9b49  
sfx_ping_timer:
    .byte $00                                   // $9b4a  
sfx_unused:
    .byte $00,$00                               // $9b4b  
sfx_v1_sweep:
    .byte $00                                   // $9b4d  
sfx_v1_freq:
    .byte $00                                   // $9b4e  
sfx_v2_pulse:
    .byte $96                                   // $9b4f  
sfx_v2_pulse_sweep:
    .byte $05                                   // $9b50  
sfx_v2_freq_hi:
    .byte $00                                   // $9b51  
sfx_filter_lo:
    .byte $00                                   // $9b52  
sfx_filter_hi:
    .byte $50                                   // $9b53  
sfx_filter_route:
    .byte $00                                   // $9b54  
sfx_v1_ctrl:
    .byte $00                                   // $9b55  
sfx_v2_ctrl:
    .byte $00                                   // $9b56  
sound_update_return:
    rts                                         // $9b57  
sound_update:
    lda demo_mode_flag                          // $9b58  called every frame from the raster IRQ
    bne sound_update_return                     // $9b5a  no sound effects in demo mode
    lda mute_sound_flag                         // $9b5c  
    beq sound_volume_on                         // $9b5e  
    lda #$00                                    // $9b60  muted: volume 0
    sta SID_MODE_VOL                            // $9b62  
    jmp sound_update_regs                       // $9b65  
sound_volume_on:
    lda sfx_volume                              // $9b68  
    ora #$40                                    // $9b6b  volume + voice 3 off
    sta SID_MODE_VOL                            // $9b6d  
sound_update_regs:
    lda sfx_filter_lo                           // $9b70  write the shadow registers to the SID
    sta SID_FC_LO                               // $9b73  
    lda sfx_filter_hi                           // $9b76  
    sta SID_FC_HI                               // $9b79  
    lda sfx_filter_route                        // $9b7c  
    sta SID_RES_FILT                            // $9b7f  
    lda sfx_v1_ctrl                             // $9b82  
    sta SID_V1_CTRL                             // $9b85  
    lda sfx_v2_ctrl                             // $9b88  
    sta SID_V2_CTRL                             // $9b8b  
    lda sfx_explosion_timer                     // $9b8e  explosion: voice 1 noise, released after 30 frames
    beq sound_v1_sweep                          // $9b91  
    dec sfx_explosion_timer                     // $9b93  
    lda sfx_explosion_timer                     // $9b96  
    cmp #$14                                    // $9b99  
    bne sound_v1_sweep                          // $9b9b  
    lda #$80                                    // $9b9d  
    sta SID_V1_CTRL                             // $9b9f  
    sta sfx_v1_ctrl                             // $9ba2  
sound_v1_sweep:
    lda sfx_v1_sweep                            // $9ba5  voice 1 frequency sweep (bounces between $64 and $C8)
    beq L9bba                                   // $9ba8  
    bmi sound_v1_sweep_down                     // $9baa  
    clc                                         // $9bac  
    adc sfx_v1_freq                             // $9bad  
    sta sfx_v1_freq                             // $9bb0  
    sta SID_V1_FREQ_LO                          // $9bb3  
    cmp #$c8                                    // $9bb6  
    bcs sound_v1_sweep_reverse                  // $9bb8  
L9bba:
    jmp sound_engine_timer                      // $9bba  
sound_v1_sweep_down:
    clc                                         // $9bbd  
    adc sfx_v1_freq                             // $9bbe  
    sta sfx_v1_freq                             // $9bc1  
    sta SID_V1_FREQ_LO                          // $9bc4  
    cmp #$64                                    // $9bc7  
    bcc sound_v1_sweep_reverse                  // $9bc9  
    jmp sound_engine_timer                      // $9bcb  
sound_v1_sweep_reverse:
    lda sfx_v1_sweep                            // $9bce  
    eor #$ff                                    // $9bd1  
    clc                                         // $9bd3  
    adc #$01                                    // $9bd4  
    sta sfx_v1_sweep                            // $9bd6  
sound_engine_timer:
    lda sfx_engine_timer                        // $9bd9  engine: release voice 1 when timer ends
    beq sound_shield_timer                      // $9bdc  
    dec sfx_engine_timer                        // $9bde  
    bne sound_shield_timer                      // $9be1  
    lda #$80                                    // $9be3  
    sta SID_V1_CTRL                             // $9be5  
    sta sfx_v1_ctrl                             // $9be8  
sound_shield_timer:
    lda sfx_v2_pulse                            // $9beb  shield: voice 2 pulse
    sta SID_V2_PW_LO                            // $9bee  
    lda sfx_shield_timer                        // $9bf1  
    beq sound_own_gun                           // $9bf4  
    dec sfx_shield_timer                        // $9bf6  
    bne sound_own_gun                           // $9bf9  
    lda #$40                                    // $9bfb  
    sta SID_V2_CTRL                             // $9bfd  
    sta sfx_v2_ctrl                             // $9c00  
sound_own_gun:
    lda sfx_own_gun_timer                       // $9c03  own gun: falling pitch on voice 2
    beq sound_hostile_gun                       // $9c06  
    dec sfx_own_gun_timer                       // $9c08  
    bne sound_own_gun_fall                      // $9c0b  
    lda #$40                                    // $9c0d  
    sta SID_V2_CTRL                             // $9c0f  
    sta sfx_v2_ctrl                             // $9c12  
sound_own_gun_fall:
    dec sfx_v2_freq_hi                          // $9c15  
    dec sfx_v2_pulse                            // $9c18  
    dec sfx_v2_pulse                            // $9c1b  
    dec sfx_v2_pulse                            // $9c1e  
    lda sfx_v2_freq_hi                          // $9c21  
    sta SID_V2_FREQ_HI                          // $9c24  
sound_hostile_gun:
    lda sfx_hostile_gun_timer                   // $9c27  hostile gun: short voice 2 pulse
    beq sound_pulse_sweep                       // $9c2a  
    dec sfx_hostile_gun_timer                   // $9c2c  
    bne sound_pulse_sweep                       // $9c2f  
    lda #$40                                    // $9c31  
    sta SID_V2_CTRL                             // $9c33  
    sta sfx_v2_ctrl                             // $9c36  
sound_pulse_sweep:
    lda sfx_v2_pulse_sweep                      // $9c39  voice 2 pulse width sweep
    clc                                         // $9c3c  
    adc sfx_v2_pulse                            // $9c3d  
    sta sfx_v2_pulse                            // $9c40  
    lda sfx_v2_pulse_sweep                      // $9c43  
    bmi sound_pulse_sweep_down                  // $9c46  
    lda sfx_v2_pulse                            // $9c48  
    cmp #$dc                                    // $9c4b  
    bcs sound_pulse_reverse                     // $9c4d  
    jmp sound_ping_timer                        // $9c4f  
sound_pulse_sweep_down:
    lda sfx_v2_pulse                            // $9c52  
    cmp #$1e                                    // $9c55  
    bcc sound_pulse_reverse                     // $9c57  
    jmp sound_ping_timer                        // $9c59  
sound_pulse_reverse:
    lda sfx_v2_pulse_sweep                      // $9c5c  
    eor #$ff                                    // $9c5f  
    clc                                         // $9c61  
    adc #$01                                    // $9c62  
    sta sfx_v2_pulse_sweep                      // $9c64  
sound_ping_timer:
    lda sfx_ping_timer                          // $9c67  ping: release voice 3 when timer ends
    beq sound_update_done                       // $9c6a  
    dec sfx_ping_timer                          // $9c6c  
    bne sound_update_done                       // $9c6f  
    jsr sound_ping                              // $9c71  
sound_update_done:
    rts                                         // $9c74  
sound_ping:
    lda #$20                                    // $9c75  voice 3 triangle "ping" (fuel / pod collected, countdown)
    sta SID_V3_CTRL                             // $9c77  triangle, gate off
    lda #$22                                    // $9c7a  
    sta SID_V3_AD                               // $9c7c  
    lda #$02                                    // $9c7f  
    sta SID_V3_SR                               // $9c81  
    lda #$00                                    // $9c84  frequency $AA00
    sta SID_V3_FREQ_LO                          // $9c86  
    lda #$aa                                    // $9c89  
    sta SID_V3_FREQ_HI                          // $9c8b  
    lda #$21                                    // $9c8e  triangle, gate on
    sta SID_V3_CTRL                             // $9c90  
    rts                                         // $9c93  
explosion_sound:
    lda demo_mode_flag                          // $9c94  
    bne explosion_sound_return                  // $9c96  
    lda #$80                                    // $9c98  noise, gate off
    sta SID_V1_CTRL                             // $9c9a  
    sta sfx_v1_ctrl                             // $9c9d  
    lda #$32                                    // $9ca0  
    sta sfx_explosion_timer                     // $9ca2  
    lda #$2a                                    // $9ca5  attack/decay
    sta SID_V1_AD                               // $9ca7  
    lda #$8c                                    // $9caa  sustain/release
    sta SID_V1_SR                               // $9cac  
    lda #$ff                                    // $9caf  
    sta SID_V1_FREQ_LO                          // $9cb1  
    sta sfx_v1_freq                             // $9cb4  
    lda #$05                                    // $9cb7  
    sta SID_V1_FREQ_HI                          // $9cb9  
    lda #$fb                                    // $9cbc  
    sta sfx_v1_sweep                            // $9cbe  
    lda #$81                                    // $9cc1  noise, gate on
    sta sfx_v1_ctrl                             // $9cc3  
    lda sfx_filter_route                        // $9cc6  
    and #$fe                                    // $9cc9  
    sta sfx_filter_route                        // $9ccb  
explosion_sound_return:
    rts                                         // $9cce  
run_engine:
    lda demo_mode_flag                          // $9ccf  
    bne run_engine_return                       // $9cd1  
    lda sfx_explosion_timer                     // $9cd3  
    bne run_engine_return                       // $9cd6  
    lda #$08                                    // $9cd8  
    sta sfx_engine_timer                        // $9cda  
    lda #$00                                    // $9cdd  
    sta SID_V1_FREQ_LO                          // $9cdf  
    lda #$14                                    // $9ce2  
    sta SID_V1_FREQ_HI                          // $9ce4  
    lda #$00                                    // $9ce7  
    sta sfx_v1_freq                             // $9ce9  
    sta sfx_v1_sweep                            // $9cec  
    lda #$00                                    // $9cef  attack/decay
    sta SID_V1_AD                               // $9cf1  
    lda #$b6                                    // $9cf4  sustain/release
    sta SID_V1_SR                               // $9cf6  
    lda #$81                                    // $9cf9  noise, gate on
    sta sfx_v1_ctrl                             // $9cfb  
    lda sfx_filter_route                        // $9cfe  
    ora #$01                                    // $9d01  
    sta sfx_filter_route                        // $9d03  
run_engine_return:
    rts                                         // $9d06  
shield_sound:
    lda demo_mode_flag                          // $9d07  
    bne run_engine_return                       // $9d09  
    lda #$0a                                    // $9d0b  
    sta sfx_shield_timer                        // $9d0d  
    lda #$00                                    // $9d10  
    sta SID_V2_FREQ_LO                          // $9d12  
    lda #$08                                    // $9d15  
    sta SID_V2_FREQ_HI                          // $9d17  
    lda #$01                                    // $9d1a  
    sta SID_V2_PW_HI                            // $9d1c  
    lda sfx_v2_pulse                            // $9d1f  
    sta SID_V2_PW_LO                            // $9d22  
    lda #$00                                    // $9d25  
    sta SID_V2_AD                               // $9d27  
    lda #$67                                    // $9d2a  
    sta SID_V2_SR                               // $9d2c  
    lda sfx_filter_route                        // $9d2f  
    ora #$02                                    // $9d32  
    sta sfx_filter_route                        // $9d34  
    lda #$41                                    // $9d37  pulse, gate on
    sta sfx_v2_ctrl                             // $9d39  
    rts                                         // $9d3c  
own_gun_sound:
    lda demo_mode_flag                          // $9d3d  
    bne own_gun_sound_return                    // $9d3f  
    lda sfx_shield_timer                        // $9d41  
    bne own_gun_sound_return                    // $9d44  
    lda #$40                                    // $9d46  pulse, gate off
    sta SID_V2_CTRL                             // $9d48  
    sta sfx_v2_ctrl                             // $9d4b  
    lda #$19                                    // $9d4e  
    sta sfx_own_gun_timer                       // $9d50  
    lda #$00                                    // $9d53  
    sta SID_V2_FREQ_LO                          // $9d55  
    lda #$1e                                    // $9d58  
    sta SID_V2_FREQ_HI                          // $9d5a  
    sta sfx_v2_freq_hi                          // $9d5d  
    lda #$13                                    // $9d60  
    sta SID_V2_AD                               // $9d62  
    lda #$23                                    // $9d65  
    sta SID_V2_SR                               // $9d67  
    lda #$05                                    // $9d6a  
    sta SID_V2_PW_HI                            // $9d6c  
    lda #$00                                    // $9d6f  
    sta SID_V2_PW_LO                            // $9d71  
    sta sfx_v2_pulse                            // $9d74  
    lda #$41                                    // $9d77  pulse, gate on
    sta sfx_v2_ctrl                             // $9d79  
    lda sfx_filter_route                        // $9d7c  
    and #$fd                                    // $9d7f  
    sta sfx_filter_route                        // $9d81  
own_gun_sound_return:
    rts                                         // $9d84  
hostile_gun_sound:
    lda demo_mode_flag                          // $9d85  
    bne sound_return                            // $9d87  
    lda sfx_shield_timer                        // $9d89  
    bne sound_return                            // $9d8c  
    lda sfx_own_gun_timer                       // $9d8e  
    bne sound_return                            // $9d91  
    lda #$05                                    // $9d93  
    sta sfx_hostile_gun_timer                   // $9d95  
    lda #$00                                    // $9d98  frequency $0F00
    sta SID_V2_FREQ_LO                          // $9d9a  
    lda #$0f                                    // $9d9d  
    sta SID_V2_FREQ_HI                          // $9d9f  
    lda #$23                                    // $9da2  
    sta SID_V2_AD                               // $9da4  
    lda #$03                                    // $9da7  
    sta SID_V2_SR                               // $9da9  
    lda #$00                                    // $9dac  
    sta SID_V2_PW_LO                            // $9dae  
    lda #$01                                    // $9db1  
    sta SID_V2_PW_HI                            // $9db3  
    lda #$41                                    // $9db6  
    sta sfx_v2_ctrl                             // $9db8  
    lda sfx_filter_route                        // $9dbb  
    ora #$02                                    // $9dbe  
    sta sfx_filter_route                        // $9dc0  
sound_return:
    rts                                         // $9dc3  
collect_pod_fuel_sound:
    lda demo_mode_flag                          // $9dc4  
    bne sound_return                            // $9dc6  
    jsr sound_ping                              // $9dc8  
    lda #$09                                    // $9dcb  
    sta sfx_ping_timer                          // $9dcd  
    rts                                         // $9dd0  
make_sound:
    lda demo_mode_flag                          // $9dd1  
    bne sound_return                            // $9dd3  
    jsr sound_ping                              // $9dd5  
    rts                                         // $9dd8  
countdown_sound:
    rts                                         // $9dd9  
key_matrix:
    .byte $00,$00,$00,$00,$00,$00,$00,$00       // $9dda  
scan_keyboard:
    php                                         // $9de2  read the 8 keyboard matrix rows into key_matrix (1 = pressed)
    lda #$fe                                    // $9de3  
    sta key_bits                                // $9de5  
    sei                                         // $9de7  disable interrupts
    lda #$ff                                    // $9de8  
    sta CIA1_DDRA                               // $9dea  
    lda #$00                                    // $9ded  
    sta CIA1_DDRB                               // $9def  
    ldx #$00                                    // $9df2  
scan_keyboard_row:
    lda key_bits                                // $9df4  
    sta CIA1_PRA                                // $9df6  
    lda CIA1_PRB                                // $9df9  
    eor #$ff                                    // $9dfc  
    sta key_matrix,x                            // $9dfe  
    inx                                         // $9e01  
    sec                                         // $9e02  
    rol key_bits                                // $9e03  
    bcs scan_keyboard_row                       // $9e05  
    plp                                         // $9e07  
    rts                                         // $9e08  
ship_input_rotate:
    lda level_tick_counter                      // $9e09  
    and #$03                                    // $9e0b  
    beq rotate_right_not_pressed_return         // $9e0d  
    ldx #KEY_A                                  // $9e0f  
    jsr test_inkey                              // $9e11  
    bne rotate_left_not_pressed                 // $9e14  
    dec ship_angle                              // $9e16  
rotate_left_not_pressed:
    ldx #KEY_S                                  // $9e18  
    jsr test_inkey                              // $9e1a  
    bne rotate_right_not_pressed                // $9e1d  
    inc ship_angle                              // $9e1f  
rotate_right_not_pressed:
    lda ship_angle                              // $9e21  
    and #ANGLE_MASK                             // $9e23  
    sta ship_angle                              // $9e25  
rotate_right_not_pressed_return:
    rts                                         // $9e27  
midpoint_add_velocity_vector:
    clc                                         // $9e28  
    lda midpoint_xpos_FRAC_LO                   // $9e29  
    adc velocity_vectorx_FRAC_LO                // $9e2b  
    sta midpoint_xpos_FRAC_LO                   // $9e2d  
    lda midpoint_xpos_FRAC                      // $9e2f  
    adc velocity_vectorx_FRAC                   // $9e31  
    sta midpoint_xpos_FRAC                      // $9e33  
    lda midpoint_xpos_INT                       // $9e35  
    adc velocity_vectorx_INT                    // $9e37  
    sta midpoint_xpos_INT                       // $9e39  
    clc                                         // $9e3b  
    lda midpoint_ypos_FRAC                      // $9e3c  
    adc velocity_vectory_FRAC                   // $9e3e  
    sta midpoint_ypos_FRAC                      // $9e40  
    lda velocity_vectory_INT                    // $9e42  
    bmi ship_velocity_negative                  // $9e44  
    adc midpoint_ypos_INT                       // $9e46  
    sta midpoint_ypos_INT                       // $9e48  
    bcc ship_ypos_no_ext                        // $9e4a  
    inc midpoint_ypos_INT_HI                    // $9e4c  
    jmp ship_ypos_no_ext                        // $9e4e  
ship_velocity_negative:
    adc midpoint_ypos_INT                       // $9e51  
    sta midpoint_ypos_INT                       // $9e53  
    bcs ship_ypos_no_ext                        // $9e55  
    dec midpoint_ypos_INT_HI                    // $9e57  
ship_ypos_no_ext:
    lda pod_destroying_player_timer             // $9e59  
    bpl L9e61                                   // $9e5b  
    lda pod_attached_flag_1                     // $9e5d  
    beq ship_ypos_no_ext_return                 // $9e5f  
L9e61:
    clc                                         // $9e61  
    lda tether_angular_vel_LO                   // $9e62  
    adc tether_angle_LO                         // $9e64  
    sta tether_angle_LO                         // $9e66  
    lda tether_angular_vel_FRAC                 // $9e68  
    adc tether_angle_FRAC                       // $9e6a  
    sta tether_angle_FRAC                       // $9e6c  
    lda tether_angular_vel_INT                  // $9e6e  
    adc angle_ship_to_pod                       // $9e70  
    and #ANGLE_MASK                             // $9e72  
    sta angle_ship_to_pod                       // $9e74  
ship_ypos_no_ext_return:
    rts                                         // $9e76  
calculate_player_position_from_midpoint:
    clc                                         // $9e77  
    lda midpoint_xpos_FRAC_LO                   // $9e78  
    sta temp_midpoint_xpos_FRAC_LO              // $9e7a  
    lda midpoint_xpos_FRAC                      // $9e7c  
    adc midpoint_deltax_FRAC                    // $9e7e  
    sta new_ship_xpos_FRAC                      // $9e80  
    lda midpoint_xpos_INT                       // $9e82  
    adc midpoint_deltax_INT                     // $9e84  
    sta new_ship_xpos_INT                       // $9e86  
    clc                                         // $9e88  
    lda midpoint_ypos_FRAC                      // $9e89  
    adc midpoint_deltay_FRAC                    // $9e8b  
    sta new_ship_ypos_FRAC                      // $9e8d  
    lda midpoint_ypos_INT                       // $9e8f  
    adc midpoint_deltay_INT                     // $9e91  
    sta new_ship_ypos_INT                       // $9e93  
    php                                         // $9e95  
    lda midpoint_deltay_INT                     // $9e96  
    bmi L9e9f                                   // $9e98  
    lda #$00                                    // $9e9a  
    jmp L9ea1                                   // $9e9c  
L9e9f:
    lda #$ff                                    // $9e9f  
L9ea1:
    plp                                         // $9ea1  
    adc midpoint_ypos_INT_HI                    // $9ea2  
    sta new_ship_ypos_INT_HI                    // $9ea4  
    sec                                         // $9ea6  
    lda temp_midpoint_xpos_FRAC_LO              // $9ea7  
    sbc old_midpoint_xpos_FRAC_LO               // $9ea9  
    sta diff_midpoint_xpos_FRAC_LO              // $9eab  
    lda new_ship_xpos_FRAC                      // $9ead  
    sbc player_xpos_FRAC                        // $9eaf  
    sta player_velocityx_FRAC                   // $9eb1  
    lda new_ship_xpos_INT                       // $9eb3  
    sbc player_xpos_INT                         // $9eb5  
    sta player_velocityx_INT                    // $9eb7  
    sec                                         // $9eb9  
    lda new_ship_ypos_FRAC                      // $9eba  
    sbc player_ypos_FRAC                        // $9ebc  
    sta player_velocityy_FRAC                   // $9ebe  
    lda new_ship_ypos_INT                       // $9ec0  
    sbc player_ypos_INT                         // $9ec2  
    sta player_velocityy_INT                    // $9ec4  
    lda new_ship_ypos_INT_HI                    // $9ec6  
    sbc player_ypos_INT_HI                      // $9ec8  
    sta player_velocityy_INT_HI                 // $9eca  
    lda player_xpos_FRAC                        // $9ecc  
    sta old_player_xpos_FRAC                    // $9ece  
    lda player_xpos_INT                         // $9ed0  
    sta old_player_xpos_INT                     // $9ed2  
    lda player_ypos_INT                         // $9ed4  
    sta old_player_ypos_INT                     // $9ed6  
    lda player_ypos_INT_HI                      // $9ed8  
    sta old_player_ypos_INT_HI                  // $9eda  
    lda temp_midpoint_xpos_FRAC_LO              // $9edc  
    sta old_midpoint_xpos_FRAC_LO               // $9ede  
    lda new_ship_xpos_FRAC                      // $9ee0  
    sta player_xpos_FRAC                        // $9ee2  
    lda new_ship_xpos_INT                       // $9ee4  
    sta player_xpos_INT                         // $9ee6  
    lda new_ship_ypos_FRAC                      // $9ee8  
    sta player_ypos_FRAC                        // $9eea  
    lda new_ship_ypos_INT                       // $9eec  
    sta player_ypos_INT                         // $9eee  
    lda new_ship_ypos_INT_HI                    // $9ef0  
    sta player_ypos_INT_HI                      // $9ef2  
    rts                                         // $9ef4  
create_explosion:
    jsr explosion_sound                         // $9ef5  
    ldx #$08                                    // $9ef8  
    lda explosion_particle_type                 // $9efa  
    cmp #$04                                    // $9efc  random debris
    bne create_explosion_loop                   // $9efe  
    ldx #$03                                    // $9f00  
    lda level_tick_counter                      // $9f02  
    lda #$02                                    // $9f04  
    sta explosion_particle_type                 // $9f06  
    jsr rnd                                     // $9f08  
    and #ANGLE_MASK                             // $9f0b  
    sta explosion_angle                         // $9f0d  
create_explosion_loop:
    stx explosion_particle_count                // $9f0f  
    jsr particle_return_free_slot_in_Y          // $9f11  
    lda explosion_xpos_FRAC                     // $9f14  
    sta particles_xpos_FRAC,y                   // $9f16  
    lda explosion_xpos_INT                      // $9f19  
    sta particles_xpos_INT,y                    // $9f1b  
    lda explosion_ypos_INT                      // $9f1e  
    sta particles_ypos_INT,y                    // $9f20  
    lda explosion_ypos_INT_HI                   // $9f23  
    sta particles_ypos_INT_HI,y                 // $9f25  
    ldx explosion_particle_count                // $9f28  
    jsr rnd                                     // $9f2a  
    and #$03                                    // $9f2d  
    clc                                         // $9f2f  
    adc explosion_angle                         // $9f30  
    and #ANGLE_MASK                             // $9f32  
    tax                                         // $9f34  
    lda angle_to_x_FRAC,x                       // $9f35  
    sta explosion_dx_FRAC                       // $9f38  
    lda angle_to_x_INT,x                        // $9f3a  
    sta explosion_dx_INT                        // $9f3d  
    lda angle_to_y_FRAC,x                       // $9f3f  
    sta explosion_dy_FRAC                       // $9f42  
    lda angle_to_y_INT,x                        // $9f44  
    sta explosion_dy_INT                        // $9f47  
    lda explosion_dx_INT                        // $9f49  
    rol                                         // $9f4b  
    php                                         // $9f4c  
    php                                         // $9f4d  
    php                                         // $9f4e  
    php                                         // $9f4f  
    ldx #$04                                    // $9f50  
L9f52:
    plp                                         // $9f52  
    ror explosion_dx_INT                        // $9f53  
    ror explosion_dx_FRAC                       // $9f55  
    dex                                         // $9f57  
    bne L9f52                                   // $9f58  
    lda explosion_dy_INT                        // $9f5a  
    rol                                         // $9f5c  
    php                                         // $9f5d  
    php                                         // $9f5e  
    php                                         // $9f5f  
    php                                         // $9f60  
    ldx #$04                                    // $9f61  
L9f63:
    plp                                         // $9f63  
    ror explosion_dy_INT                        // $9f64  
    ror explosion_dy_FRAC                       // $9f66  
    dex                                         // $9f68  
    bne L9f63                                   // $9f69  
    lda #$00                                    // $9f6b  
    sta particles_dx_FRAC,y                     // $9f6d  
    sta particles_dx_INT,y                      // $9f70  
    sta particles_dy_FRAC,y                     // $9f73  
    sta particles_dy_INT,y                      // $9f76  
    lda rnd_B                                   // $9f79  
    and #$03                                    // $9f7b  
    tax                                         // $9f7d  
    inx                                         // $9f7e  
    inx                                         // $9f7f  
    pha                                         // $9f80  
L9f81:
    clc                                         // $9f81  
    lda explosion_dx_FRAC                       // $9f82  
    adc particles_dx_FRAC,y                     // $9f84  
    sta particles_dx_FRAC,y                     // $9f87  
    lda explosion_dx_INT                        // $9f8a  
    adc particles_dx_INT,y                      // $9f8c  
    sta particles_dx_INT,y                      // $9f8f  
    clc                                         // $9f92  
    lda explosion_dy_FRAC                       // $9f93  
    adc particles_dy_FRAC,y                     // $9f95  
    sta particles_dy_FRAC,y                     // $9f98  
    lda explosion_dy_INT                        // $9f9b  
    adc particles_dy_INT,y                      // $9f9d  
    sta particles_dy_INT,y                      // $9fa0  
    dex                                         // $9fa3  
    bne L9f81                                   // $9fa4  
    pla                                         // $9fa6  
    rol                                         // $9fa7  
    rol                                         // $9fa8  
    rol                                         // $9fa9  
    eor #ANGLE_MASK                             // $9faa  
    sta explosion_dx_FRAC                       // $9fac  
    lda particles_lifetime,y                    // $9fae  
    rol                                         // $9fb1  
    lda rnd_A                                   // $9fb2  
    and #$0f                                    // $9fb4  
    ror                                         // $9fb6  
    adc explosion_dx_FRAC                       // $9fb7  
    adc #$08                                    // $9fb9  
    sta particles_lifetime,y                    // $9fbb  
    lda explosion_particle_type                 // $9fbe  
    sta particles_type,y                        // $9fc0  
    clc                                         // $9fc3  
    lda explosion_angle                         // $9fc4  
    adc #$04                                    // $9fc6  
    and #ANGLE_MASK                             // $9fc8  
    sta explosion_angle                         // $9fca  
    tya                                         // $9fcc  
    tax                                         // $9fcd  
    jsr particle_move_index_X                   // $9fce  
    jsr particle_move_index_X                   // $9fd1  
    ldx explosion_particle_count                // $9fd4  
    dex                                         // $9fd6  
    beq create_explosion_return                 // $9fd7  
    jmp create_explosion_loop                   // $9fd9  
create_explosion_return:
    rts                                         // $9fdc  
particle_return_free_slot_in_Y:
    ldy #$1f                                    // $9fdd  
L9fdf:
    lda particles_lifetime,y                    // $9fdf  
    and #$7f                                    // $9fe2  
    beq particle_return_free_slot_in_Y_return   // $9fe4  
    dey                                         // $9fe6  
    bne L9fdf                                   // $9fe7  
    ldy #$1f                                    // $9fe9  
L9feb:
    lda particles_lifetime,y                    // $9feb  
    and #$7f                                    // $9fee  
    cmp #$0a                                    // $9ff0  
    bcc particle_return_free_slot_in_Y_return   // $9ff2  
    dey                                         // $9ff4  
    bne L9feb                                   // $9ff5  
L9ff7:
    beq particle_return_free_slot_in_Y_return   // $9ff7  
    bne L9ff7                                   // $9ff9  
    jsr rnd                                     // $9ffb  
    and #$0f                                    // $9ffe  
    adc #$04                                    // $a000  
    tay                                         // $a002  
particle_return_free_slot_in_Y_return:
    rts                                         // $a003  
debug_print_hex_A:
    sta debug_hex_value                         // $a004  
    php                                         // $a007  
    txa                                         // $a008  
    pha                                         // $a009  
    tya                                         // $a00a  
    pha                                         // $a00b  
    lda debug_hex_value                         // $a00c  
    ror                                         // $a00f  
    ror                                         // $a010  
    ror                                         // $a011  
    ror                                         // $a012  
    and #$0f                                    // $a013  
    jsr debug_print_hex_digit                   // $a015  
    lda debug_hex_value                         // $a018  
    and #$0f                                    // $a01b  
    jsr debug_print_hex_digit                   // $a01d  
    pla                                         // $a020  
    tay                                         // $a021  
    pla                                         // $a022  
    tax                                         // $a023  
    plp                                         // $a024  
    lda debug_hex_value                         // $a025  
    rts                                         // $a028  
debug_hex_value:
    .byte $00                                   // $a029  
debug_print_hex_digit:
    pha                                         // $a02a  
    cmp #$0a                                    // $a02b  
    bcc La035                                   // $a02d  
    clc                                         // $a02f  
    adc #$37                                    // $a030  
    jmp debug_print_hex_digit_2                 // $a032  
La035:
    adc #$30                                    // $a035  
debug_print_hex_digit_2:
    jsr plot_char_A                             // $a037  
    pla                                         // $a03a  
    rts                                         // $a03b  

    // (thrusty-levels: levels.asm was imported here; it now lives at $1000)
level_obj_flags:
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00  // $a352  
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00  // $a362  
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00  // $a372  
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00  // $a382  
particles_update_and_draw:
    jsr particles_generate_stars                // $a38e  
    lda #$00                                    // $a391  
    sta particle_temp_clear_77                  // $a393  
    lda #$00                                    // $a395  
    sta particle_temp_clear_79                  // $a397  
    ldx #$1f                                    // $a399  
particle_update_loop_X:
    lda #$00                                    // $a39b  
    sta particle_collision_flag                 // $a39d  
    lda particles_lifetime,x                    // $a39f  
    bpl La3c3                                   // $a3a2  
    and #$7f                                    // $a3a4  
    sta particles_lifetime,x                    // $a3a6  
    lda particles_scraddr_LO,x                  // $a3a9  
    sta particle_write_ptr                      // $a3ac  
    lda particles_scraddr_HI,x                  // $a3ae  
    sta particle_write_ptr+1                    // $a3b1  
    ldy #$00                                    // $a3b3  
    lda particles_pixels_byte,x                 // $a3b5  
    pha                                         // $a3b8  
    eor (particle_write_ptr),y                  // $a3b9  
    sta (particle_write_ptr),y                  // $a3bb  
    pla                                         // $a3bd  
    iny                                         // $a3be  
    eor (particle_write_ptr),y                  // $a3bf  
    sta (particle_write_ptr),y                  // $a3c1  
La3c3:
    ldy particles_lifetime,x                    // $a3c3  
    beq particle_update_next_X                  // $a3c6  
    dey                                         // $a3c8  
    tya                                         // $a3c9  
    sta particles_lifetime,x                    // $a3ca  
    jsr particle_move_index_X                   // $a3cd  
    ldy particles_type,x                        // $a3d0  
    lda particle_type_pixels,y                  // $a3d3  
    sta particle_pixel_byte                     // $a3d6  
    jsr particle_test_hit_ship                  // $a3d8  
    jmp La3e5                                   // $a3db  
particle_update_next_X:
    dex                                         // $a3de  
    bmi particle_update_next_X_return           // $a3df  
    jmp particle_update_loop_X                  // $a3e1  
particle_update_next_X_return:
    rts                                         // $a3e4  
La3e5:
    sec                                         // $a3e5  
    lda particles_ypos_INT,x                    // $a3e6  
    sbc window_ypos_INT                         // $a3e9  
    sta particle_screen_y                       // $a3eb  
    lda particles_ypos_INT_HI,x                 // $a3ed  
    sbc window_ypos_EXT                         // $a3f0  
    bne La428                                   // $a3f2  
    lda particle_screen_y                       // $a3f4  
    clc                                         // $a3f6  
    adc terrain_window_y_index                  // $a3f7  
    tay                                         // $a3fa  
    lda particles_xpos_INT,x                    // $a3fb  
    cmp terrain_left_wall,y                     // $a3fe  bullet vs terrain collision detection?
    bcc La428                                   // $a401  
    cmp terrain_right_wall,y                    // $a403  bullet vs terrain collision detection?
    bcs La428                                   // $a406  
    lda particles_xpos_INT,x                    // $a408  
    sec                                         // $a40b  
    sbc window_xpos_INT                         // $a40c  
    bcc next_X1                                 // $a40e  
    cmp #$50                                    // $a410  
    bcs next_X1                                 // $a412  
    sta particle_screen_x                       // $a414  
    sec                                         // $a416  
    lda particle_screen_y                       // $a417  
    sbc #SCREEN_ADDR_HI_OFFSET                  // $a419  
    sta particle_screen_y                       // $a41b  
    cmp #$09                                    // $a41d  
    bcc next_X1                                 // $a41f  
    cmp #$63                                    // $a421  
    bcc La430                                   // $a423  
next_X1:
    jmp particle_update_next_X                  // $a425  
La428:
    lda #$00                                    // $a428  
    sta particles_lifetime,x                    // $a42a  
    jmp particle_update_next_X                  // $a42d  
La430:
    lda particles_lifetime,x                    // $a430  
    ora #$80                                    // $a433  
    sta particles_lifetime,x                    // $a435  
    lda particle_screen_y                       // $a438  
    rol                                         // $a43a  
    sta particle_screen_y                       // $a43b  
    ldy #$00                                    // $a43d  
    sty particle_write_ptr                      // $a43f  
    and #$f8                                    // $a441  
    ror                                         // $a443  
    ror                                         // $a444  
    ror                                         // $a445  
    sta particle_write_ptr+1                    // $a446  
    ror                                         // $a448  
    ror particle_write_ptr                      // $a449  
    ror                                         // $a44b  
    ror particle_write_ptr                      // $a44c  
    adc #$60                                    // $a44e  
    adc particle_write_ptr+1                    // $a450  
    sta particle_write_ptr+1                    // $a452  
    ldy particle_screen_x                       // $a454  
    lda column_bitmap_offset_LO,y               // $a456  
    adc particle_write_ptr                      // $a459  
    sta particle_write_ptr                      // $a45b  
    lda column_bitmap_offset_HI,y               // $a45d  
    adc particle_write_ptr+1                    // $a460  
    sta particle_write_ptr+1                    // $a462  
    sta particles_scraddr_HI,x                  // $a464  
    lda particle_screen_y                       // $a467  
    and #$07                                    // $a469  
    cmp #$07                                    // $a46b  
    bne La471                                   // $a46d  
    lda #$06                                    // $a46f  
La471:
    clc                                         // $a471  
    adc particle_write_ptr                      // $a472  
    sta particle_write_ptr                      // $a474  
    sta particles_scraddr_LO,x                  // $a476  
    lda particle_screen_x                       // $a479  
    ror                                         // $a47b  
    lda particles_xpos_FRAC,x                   // $a47c  
    rol                                         // $a47f  
    rol                                         // $a480  
    rol                                         // $a481  
    and #$07                                    // $a482  
    tay                                         // $a484  
    lda particles_xpos_byte_mask,y              // $a485  
    and particle_pixel_byte                     // $a488  
    pha                                         // $a48a  
    sta particles_pixels_byte,x                 // $a48b  
    ldy #$00                                    // $a48e  
    sty particle_collision_flag                 // $a490  
    eor (particle_write_ptr),y                  // $a492  
    sta (particle_write_ptr),y                  // $a494  
    iny                                         // $a496  
    pla                                         // $a497  
    eor (particle_write_ptr),y                  // $a498  
    sta (particle_write_ptr),y                  // $a49a  
    jmp particle_update_next_X                  // $a49c  
particle_test_hit_ship:
    lda ship_sprite_plotted_flag                // $a49f  
    beq La4e9                                   // $a4a1  
    lda particles_type,x                        // $a4a3  
    beq La4e9                                   // $a4a6  
    cmp #$02                                    // $a4a8  
    beq La4e9                                   // $a4aa  
    cmp #$01                                    // $a4ac  
    beq La4b4                                   // $a4ae  
    lda shield_tractor_pressed                  // $a4b0  
    beq next_X2                                 // $a4b2  
La4b4:
    sec                                         // $a4b4  
    lda particles_xpos_INT,x                    // $a4b5  
    sbc player_xpos_INT                         // $a4b8  
    beq next_X2_return                          // $a4ba  
    cmp #$08                                    // $a4bc  
    bcs next_X2_return                          // $a4be  
    sec                                         // $a4c0  
    lda particles_ypos_INT,x                    // $a4c1  
    sbc player_ypos_INT                         // $a4c4  
    sta player_to_particle_deltay_INT           // $a4c6  
    lda particles_ypos_INT_HI,x                 // $a4c8  
    sbc player_ypos_INT_HI                      // $a4cb  
    tay                                         // $a4cd  
    clc                                         // $a4ce  
    lda player_to_particle_deltay_INT           // $a4cf  
    adc #$02                                    // $a4d1  
    bcc La4d6                                   // $a4d3  
    iny                                         // $a4d5  
La4d6:
    cpy #$00                                    // $a4d6  
    bne next_X2_return                          // $a4d8  
    cmp #$0d                                    // $a4da  
    bcs next_X2_return                          // $a4dc  
    lda #$55                                    // $a4de  
    sta particle_pixel_byte                     // $a4e0  
    lda particles_type,x                        // $a4e2  
    cmp #$03                                    // $a4e5  
    beq next_X2                                 // $a4e7  
La4e9:
    rts                                         // $a4e9  
next_X2:
    sec                                         // $a4ea  
    lda particles_xpos_INT,x                    // $a4eb  
    sbc player_xpos_INT                         // $a4ee  
    cmp #$03                                    // $a4f0  
    bcc next_X2_return                          // $a4f2  
    cmp #$06                                    // $a4f4  
    bcs next_X2_return                          // $a4f6  
    sec                                         // $a4f8  
    lda particles_ypos_INT,x                    // $a4f9  
    sbc player_ypos_INT                         // $a4fc  
    sta player_to_particle_deltay_INT           // $a4fe  
    lda particles_ypos_INT_HI,x                 // $a500  
    sbc player_ypos_INT_HI                      // $a503  
    bne next_X2_return                          // $a505  
    lda player_to_particle_deltay_INT           // $a507  
    cmp #$02                                    // $a509  
    bcc next_X2_return                          // $a50b  
    cmp #$07                                    // $a50d  
    bcs next_X2_return                          // $a50f  
    lda ship_sprite_plotted_flag                // $a511  
    beq next_X2_return                          // $a513  
    lda particles_lifetime,x                    // $a515  
    and #$80                                    // $a518  
    sta particles_lifetime,x                    // $a51a  
    lda shield_tractor_pressed                  // $a51d  
    bne next_X2_return                          // $a51f  
    lda #$ff                                    // $a521  
    sta plot_ship_collision_detected            // $a523  
next_X2_return:
    rts                                         // $a525  
particles_xpos_byte_mask:
    .byte $c0,$c0,$30,$30,$0c,$0c,$03,$03       // $a526  
particle_type_pixels:
    .byte $aa,$ff,$55,$ff                       // $a52e  
particle_move_index_X:
    clc                                         // $a532  
    lda particles_xpos_FRAC,x                   // $a533  
    adc particles_dx_FRAC,x                     // $a536  
    sta particles_xpos_FRAC,x                   // $a539  
    lda particles_xpos_INT,x                    // $a53c  
    adc particles_dx_INT,x                      // $a53f  
    sta particles_xpos_INT,x                    // $a542  
    clc                                         // $a545  
    lda particles_ypos_FRAC,x                   // $a546  
    adc particles_dy_FRAC,x                     // $a549  
    sta particles_ypos_FRAC,x                   // $a54c  
    lda particles_ypos_INT,x                    // $a54f  
    adc particles_dy_INT,x                      // $a552  
    sta particles_ypos_INT,x                    // $a555  
    php                                         // $a558  
    lda particles_dy_INT,x                      // $a559  
    bmi La563                                   // $a55c  
    lda #$00                                    // $a55e  
    jmp La565                                   // $a560  
La563:
    lda #$ff                                    // $a563  
La565:
    plp                                         // $a565  
    adc particles_ypos_INT_HI,x                 // $a566  
    sta particles_ypos_INT_HI,x                 // $a569  
particles_return:
    rts                                         // $a56c  
particles_generate_stars:
    lda window_ypos_EXT                         // $a56d  
    cmp #$02                                    // $a56f  
    bcs particles_return                        // $a571  
    lda level_tick_counter                      // $a573  
    and #$01                                    // $a575  
    bne particles_return                        // $a577  
    jsr particle_return_free_slot_in_Y          // $a579  
    jsr rnd                                     // $a57c  
    adc #$64                                    // $a57f  
    sta particles_ypos_INT,y                    // $a581  
    lda #$00                                    // $a584  
    adc #$00                                    // $a586  
    sta particles_ypos_INT_HI,y                 // $a588  
    lda #$00                                    // $a58b  
    sta particles_dx_FRAC,y                     // $a58d  
    sta particles_dx_INT,y                      // $a590  
    sta particles_dy_FRAC,y                     // $a593  
    sta particles_dy_INT,y                      // $a596  
    lda rnd_B                                   // $a599  
    and #$3f                                    // $a59b  
    adc window_xpos_INT                         // $a59d  
    adc #$05                                    // $a59f  
    sta particles_xpos_INT,y                    // $a5a1  
    lda particles_lifetime,y                    // $a5a4  
    and #$80                                    // $a5a7  
    ora #$1e                                    // $a5a9  
    sta particles_lifetime,y                    // $a5ab  
    lda rnd_B                                   // $a5ae  
    and #$01                                    // $a5b0  
    clc                                         // $a5b2  
    adc #$01                                    // $a5b3  
    sta particles_type,y                        // $a5b5  stars / debris
    rts                                         // $a5b8  
level_reset:
    jsr clear_screen_and_sprites                // $a5b9  
    jsr set_level_colours                       // $a5bc  redraw the level colours
    ldy #$0a                                    // $a5bf  
    jsr wait_time_out_Y                         // $a5c1  
    lda midpoint_ypos_INT_HI                    // $a5c4  
    pha                                         // $a5c6  
    lda midpoint_ypos_INT                       // $a5c7  
    pha                                         // $a5c9  
    lda rnd_B                                   // $a5ca  
    pha                                         // $a5cc  
    lda rnd_A                                   // $a5cd  
    pha                                         // $a5cf  
    ldy demo_mode_flag                          // $a5d0  
    ldx #$9e                                    // $a5d2  clear game variables $02-$9F (keeps demo flag, random seed, ship Y)
clear_zp_game_vars:
    lda #$00                                    // $a5d4  
    sta $01,x                                   // $a5d6  
    dex                                         // $a5d8  
    bne clear_zp_game_vars                      // $a5d9  
    sty demo_mode_flag                          // $a5db  
    pla                                         // $a5dd  
    sta rnd_A                                   // $a5de  
    pla                                         // $a5e0  
    sta rnd_B                                   // $a5e1  
    pla                                         // $a5e3  
    sta midpoint_ypos_INT                       // $a5e4  
    pla                                         // $a5e6  
    sta midpoint_ypos_INT_HI                    // $a5e7  
    lda #$ff                                    // $a5e9  
    sta level_tick_state                        // $a5eb  
    ldx #$ff                                    // $a5ed  
    stx player_ship_destroyed_flag              // $a5ef  
    stx pod_destroying_player_timer             // $a5f1  
    stx player_pressed_fire                     // $a5f3  
    stx planet_countdown_timer                  // $a5f5  
    inx                                         // $a5f7  
    stx pod_attached_flag_2                     // $a5f8  
    ldx #$0f                                    // $a5fb  
    stx generator_recharge_counter              // $a5fd  
    ldx level_number                            // $a5ff  find the restart point for the current height:
    lda level_reset_ptr_table_LO,x              // $a602  
    sta level_reset_ptr                         // $a605  
    lda level_reset_ptr_table_HI,x              // $a607  
    sta level_reset_ptr+1                       // $a60a  
    lda level_reset_ptr2_table_LO,x             // $a60c  
    sta level_reset_ptr2                        // $a60f  
    lda level_reset_ptr2_table_HI,x             // $a611  
    sta level_reset_ptr2+1                      // $a614  
    lda level_reset_data_sizes,x                // $a616  
    sta level_reset_size                        // $a619  
    ldy #$00                                    // $a61b  
level_reset_loop:
    lda (level_reset_ptr2),y                    // $a61d  first entry whose trigger height is below the ship
    sbc midpoint_ypos_INT                       // $a61f  
    lda (level_reset_ptr),y                     // $a621  
    sbc midpoint_ypos_INT_HI                    // $a623  
    bcs level_reset_found                       // $a625  
    iny                                         // $a627  
    cpy level_reset_size                        // $a628  
    bne level_reset_loop                        // $a62a  
    lda #$00                                    // $a62c  
    sta level_reset_with_pod_flag               // $a62e  
level_reset_found:
    cpy #$00                                    // $a631  
    beq level_reset_use_entry                   // $a633  
    lda level_reset_with_pod_flag               // $a635  
    bne level_reset_use_entry                   // $a638  
    dey                                         // $a63a  move back one check point.
level_reset_use_entry:
    iny                                         // $a63b  
    cpy level_reset_size                        // $a63c  
    bne level_reset_set_position                // $a63e  
    lda #$00                                    // $a640  
    sta level_reset_with_pod_flag               // $a642  
level_reset_set_position:
    dey                                         // $a645  restart data rows: Y_EXT, Y, window X, window Y_EXT, window Y, X
    clc                                         // $a646  
    lda (level_reset_ptr),y                     // $a647  
    sta midpoint_ypos_INT_HI                    // $a649  
    tya                                         // $a64b  
    adc level_reset_size                        // $a64c  
    tay                                         // $a64e  
    lda (level_reset_ptr),y                     // $a64f  
    sta midpoint_ypos_INT                       // $a651  
    tya                                         // $a653  
    adc level_reset_size                        // $a654  
    tay                                         // $a656  
    lda (level_reset_ptr),y                     // $a657  
    sta window_xpos_INT                         // $a659  
    tya                                         // $a65b  
    adc level_reset_size                        // $a65c  
    tay                                         // $a65e  
    lda (level_reset_ptr),y                     // $a65f  
    sta window_ypos_EXT                         // $a661  
    tya                                         // $a663  
    adc level_reset_size                        // $a664  
    tay                                         // $a666  
    lda (level_reset_ptr),y                     // $a667  
    sta window_ypos_INT                         // $a669  
    tya                                         // $a66b  
    adc level_reset_size                        // $a66c  
    tay                                         // $a66e  
    lda (level_reset_ptr),y                     // $a66f  
    sta midpoint_xpos_INT                       // $a671  
    lda #$0e                                    // $a673  
    sta tether_length                           // $a675  
    lda level_reset_with_pod_flag               // $a677  
    beq dont_set_angle_to_pod                   // $a67a  
    ldx #$ff                                    // $a67c  
    stx pod_attached_flag_2                     // $a67e  
    stx pod_attached_flag_1                     // $a681  
    ldx #$01                                    // $a683  angle $01 - straight up (+1)
    lda gravity_INT                             // $a685  
    bpl level_reset_set_pod_angle               // $a687  normal gravity
    ldx #$11                                    // $a689  angle $11 - straight down (+1)
level_reset_set_pod_angle:
    stx angle_ship_to_pod                       // $a68b  
dont_set_angle_to_pod:
    lda gravity_INT                             // $a68d  
    bpl level_reset_done                        // $a68f  
    lda #ANGLE_DOWN                             // $a691  angle $10 - straight down for reverse gravity
    sta ship_angle                              // $a693  
level_reset_done:
    lda #$07                                    // $a695  
    ldy #$01                                    // $a697  
    jsr palette_set_colour_Y_to_A               // $a699  BBC palette calls - empty on the C64
    lda #$00                                    // $a69c  
    ldy #$00                                    // $a69e  
    jsr palette_set_colour_Y_to_A               // $a6a0  
    rts                                         // $a6a3  
level_number:
    .byte $00                                   // $a6a4  
reverse_gravity_flag:
    .byte $00                                   // $a6a5  
level_reset_with_pod_flag:
    .byte $00                                   // $a6a6  
initialise_level_pointers:
    jsr clear_screen_and_sprites                // $a6a7  
    lda #$00                                    // $a6aa  
    sta level_reset_with_pod_flag               // $a6ac  
    lda #$ff                                    // $a6af  landscape visible
    sta landscape_visible_flag                  // $a6b1  
    lda #$32                                    // $a6b4  generator damage starts at 50
    sta generator_total_damage                  // $a6b6  
    ldx level_number                            // $a6b8  
    lda level_gravity_FRAC_table,x              // $a6bb  
    sta gravity_FRAC                            // $a6be  
    lda terrain_left_wall_counter_ptrs_LO,x     // $a6c0  
    sta terrain_left_wall_counter_LO            // $a6c3  
    lda terrain_left_wall_increment_ptrs_LO,x   // $a6c6  
    sta terrain_left_wall_increment_LO          // $a6c9  
    lda terrain_left_wall_counter_ptrs_HI,x     // $a6cc  
    sta terrain_left_wall_counter_HI            // $a6cf  
    lda terrain_left_wall_increment_ptrs_HI,x   // $a6d2  
    sta terrain_left_wall_increment_HI          // $a6d5  
    lda terrain_right_wall_counter_ptrs_LO,x    // $a6d8  
    sta terrain_right_wall_counter_LO           // $a6db  
    lda terrain_right_wall_increment_ptrs_LO,x  // $a6de  
    sta terrain_right_wall_increment_LO         // $a6e1  
    lda terrain_right_wall_counter_ptrs_HI,x    // $a6e4  
    sta terrain_right_wall_counter_HI           // $a6e7  
    lda terrain_right_wall_increment_ptrs_HI,x  // $a6ea  
    sta terrain_right_wall_increment_HI         // $a6ed  
    ldy #$00                                    // $a6f0  
    lda reverse_gravity_flag                    // $a6f2  reverse gravity: negate gravity
    beq normal_gravity                          // $a6f5  
    lda gravity_FRAC                            // $a6f7  
    eor #$ff                                    // $a6f9  
    sta gravity_FRAC                            // $a6fb  
    ldy #$ff                                    // $a6fd  
normal_gravity:
    sty gravity_INT                             // $a6ff  
    lda #$aa                                    // $a701  bullet pixels ($AA visible / $FF)
    ora invisible_landscape_flag                // $a703  
    sta particle_type_pixels                    // $a705  player bullet pixels: $AA, or $FF when the landscape is invisible
    clc                                         // $a708  
    txa                                         // $a709  
    rol                                         // $a70a  
    tax                                         // $a70b  level_number *= 2
    lda level_obj_pos_X_lookup,x                // $a70c  
    sta level_obj_pos_X_addr_LO                 // $a70f  MODIFIES CODE
    lda level_obj_pos_X_lookup+1,x              // $a712  
    sta level_obj_pos_X_addr_HI                 // $a715  MODIFIES CODE
    lda level_obj_pos_Y_lookup,x                // $a718  
    sta level_obj_pos_Y_addr_LO                 // $a71b  MODIFIES CODE
    lda level_obj_pos_Y_lookup+1,x              // $a71e  
    sta level_obj_pos_Y_addr_HI                 // $a721  MODIFIES CODE
    lda level_obj_pos_Y_EXT_lookup,x            // $a724  
    sta level_obj_pos_Y_EXT_addr_LO             // $a727  MODIFIES CODE
    lda level_obj_pos_Y_EXT_lookup+1,x          // $a72a  
    sta level_obj_pos_Y_EXT_addr_HI             // $a72d  MODIFIES CODE
    lda level_obj_type_lookup,x                 // $a730  
    sta level_obj_type_addr_LO                  // $a733  MODIFIES CODE
    lda level_obj_type_lookup+1,x               // $a736  
    sta level_obj_type_addr_HI                  // $a739  MODIFIES CODE
    lda level_gun_param_lookup,x                // $a73c  
    sta level_gun_param_addr_LO                 // $a73f  MODIFIES CODE
    lda level_gun_param_lookup+1,x              // $a742  
    sta level_gun_param_addr_HI                 // $a745  MODIFIES CODE
    txa                                         // $a748  
    ror                                         // $a749  level_number /= 2
    tax                                         // $a74a  
    ldx #LEVEL_MAX_OBJECTS                      // $a74b  max objects per level
initialise_sprite_table_A:
    lda #$02                                    // $a74d  
    sta level_obj_flags,x                       // $a74f  
    dex                                         // $a752  
    bpl initialise_sprite_table_A               // $a753  
    ldx #$0b                                    // $a755  
initialise_obj_tractor_counter:
    lda #$00                                    // $a757  
    sta obj_tractor_counter,x                   // $a759  
    dex                                         // $a75c  
    bpl initialise_obj_tractor_counter          // $a75d  
set_level_colours:
    jsr clear_screen_and_sprites                // $a75f  set up the playfield colours for this level
    lda #$00                                    // $a762  
    sta hires_status_flag                       // $a764  
    jsr sprite_bands_build                      // $a767  
set_level_colours_wait:
    lda multicolour_flag                        // $a76a  
    bne set_level_colours_wait                  // $a76d  
    ldx level_number                            // $a76f  
    lda level_colour_terrain,x                  // $a772  terrain colour ("10" pixels, screen RAM low nibble)
    sta playfield_mc2_colour                    // $a775  
    sta text_colour                             // $a778  
    lda level_colour_mc1,x                      // $a77b  colour of "01" pixels (screen RAM high nibble)
    rol                                         // $a77e  
    rol                                         // $a77f  
    rol                                         // $a780  
    rol                                         // $a781  
    and #$f0                                    // $a782  
    pha                                         // $a784  
    ora level_colour_terrain,x                  // $a785  
    ldy #$00                                    // $a788  
set_level_colours_screen_A:
    sta screen_A+$50,y                          // $a78a  screen A ($5C00): terrain visible
    sta screen_A+$100,y                         // $a78d  
    sta screen_A+$200,y                         // $a790  
    sta screen_A+$2f8,y                         // $a793  
    dey                                         // $a796  
    bne set_level_colours_screen_A              // $a797  
    pla                                         // $a799  
    ldy #$00                                    // $a79a  
set_level_colours_screen_B:
    sta screen_B+$50,y                          // $a79c  screen B ($5400): terrain colour 0 = invisible landscape
    sta screen_B+$100,y                         // $a79f  
    sta screen_B+$200,y                         // $a7a2  
    sta screen_B+$2f8,y                         // $a7a5  
    dey                                         // $a7a8  
    bne set_level_colours_screen_B              // $a7a9  
    ldx level_number                            // $a7ab  
    lda level_colour_mc3,x                      // $a7ae  colour of "11" pixels (colour RAM)
    ldy #$00                                    // $a7b1  
set_level_colours_colour_ram:
    sta COLOR_RAM+$50,y                         // $a7b3  
    sta COLOR_RAM+$100,y                        // $a7b6  
    sta COLOR_RAM+$200,y                        // $a7b9  
    sta COLOR_RAM+$300,y                        // $a7bc  
    dey                                         // $a7bf  
    bne set_level_colours_colour_ram            // $a7c0  
    sta pod_colour                              // $a7c2  
    lda level_colour_objects,x                  // $a7c5  object sprite colours
    sta obj_colour_gun                          // $a7c8  
    sta obj_colour_pod_stand                    // $a7cb  
    sta obj_colour_generator_2                  // $a7ce  
    lda level_colour_shield,x                   // $a7d1  
    sta shield_colour                           // $a7d4  
    sta obj_colour_fuel_2                       // $a7d7  
set_level_colours_wait_raster:
    lda VIC_RASTER                              // $a7da  wait for raster line $50
    cmp #$50                                    // $a7dd  
    bne set_level_colours_wait_raster           // $a7df  
    lda VIC_CTRL1                               // $a7e1  
    bmi set_level_colours_wait_raster           // $a7e4  
    ldy #$4f                                    // $a7e6  
set_status_bar_chars:
    tya                                         // $a7e8  status bar: characters 0-79 in rows 0-1 of both screens
    sta screen_B,y                              // $a7e9  
    sta screen_A,y                              // $a7ec  
    lda #$07                                    // $a7ef  
    sta COLOR_RAM,y                             // $a7f1  
    dey                                         // $a7f4  
    bpl set_status_bar_chars                    // $a7f5  
    ldy #$27                                    // $a7f7  
set_status_bar_colours:
    lda #$0f                                    // $a7f9  
    sta COLOR_RAM,y                             // $a7fb  
    dey                                         // $a7fe  
    bpl set_status_bar_colours                  // $a7ff  
    ldx level_number                            // $a801  
    lda level_colour_status,x                   // $a804  status bar label colours
    sta COLOR_RAM+$05                           // $a807  
    sta COLOR_RAM+$06                           // $a80a  
    sta COLOR_RAM+$07                           // $a80d  
    sta COLOR_RAM+$08                           // $a810  
    sta COLOR_RAM+$11                           // $a813  
    sta COLOR_RAM+$12                           // $a816  
    sta COLOR_RAM+$13                           // $a819  
    sta COLOR_RAM+$14                           // $a81c  
    sta COLOR_RAM+$15                           // $a81f  
    sta COLOR_RAM+$1e                           // $a822  
    sta COLOR_RAM+$1f                           // $a825  
    sta COLOR_RAM+$20                           // $a828  
    sta COLOR_RAM+$21                           // $a82b  
    sta COLOR_RAM+$22                           // $a82e  
    rts                                         // $a831  
set_text_screen_colours:
    lda #$50                                    // $a832  fill both screens with the text colour (title / high score screens)
    sta colour_ptr_A                            // $a834  
    lda #$5c                                    // $a836  
    sta colour_ptr_A+1                          // $a838  
    lda #$50                                    // $a83a  
    sta colour_ptr_B                            // $a83c  
    lda #$54                                    // $a83e  
    sta colour_ptr_B+1                          // $a840  
    lda #$02                                    // $a842  
    sta colour_pages                            // $a844  
    ldx #$58                                    // $a846  
    lda COLOR_RAM+$a0                           // $a848  
    rol                                         // $a84b  
    rol                                         // $a84c  
    rol                                         // $a84d  
    rol                                         // $a84e  
    and #$f0                                    // $a84f  
    ldy #$00                                    // $a851  
set_text_screen_colours_loop:
    sta (colour_ptr_A),y                        // $a853  
    sta (colour_ptr_B),y                        // $a855  
    iny                                         // $a857  
    bne set_text_screen_colours_next            // $a858  
    inc colour_ptr_A+1                          // $a85a  
    inc colour_ptr_B+1                          // $a85c  
set_text_screen_colours_next:
    dex                                         // $a85e  
    bne set_text_screen_colours_loop            // $a85f  
    dec colour_pages                            // $a861  
    bpl set_text_screen_colours_loop            // $a863  
    lda #$ff                                    // $a865  
    sta hires_status_flag                       // $a867  
    jsr sprite_bands_build                      // $a86a  
set_text_screen_colours_wait:
    lda multicolour_flag                        // $a86d  
    beq set_text_screen_colours_wait            // $a870  
    rts                                         // $a872  

    #import "level_tables.asm"
ship_input_fire:
    lda pod_destroying_player_timer             // $a99a  
    bpl ship_input_fire_return                  // $a99c  
    lda shield_tractor_pressed                  // $a99e  
    beq test_fire_key                           // $a9a0  
    lda #$ff                                    // $a9a2  
    sta player_pressed_fire                     // $a9a4  
ship_input_fire_return:
    rts                                         // $a9a6  
test_fire_key:
    ldx #KEY_RETURN                             // $a9a7  
    jsr test_inkey                              // $a9a9  
    cpx #$ff                                    // $a9ac  
    beq fire_pressed                            // $a9ae  
    lda #$00                                    // $a9b0  
    sta player_pressed_fire                     // $a9b2  
    rts                                         // $a9b4  
fire_pressed:
    lda player_pressed_fire                     // $a9b5  
    beq player_shoot_bullet                     // $a9b7  
    rts                                         // $a9b9  
player_shoot_bullet:
    ldx bullet_index                            // $a9ba  
    lda particles_type,x                        // $a9bc  
    cmp #$00                                    // $a9bf  
    bne create_new_player_bullet                // $a9c1  
    lda particles_lifetime,x                    // $a9c3  
    beq create_new_player_bullet                // $a9c6  
    rts                                         // $a9c8  
angle_to_bullet_dx_dy:
    lda angle_to_x_FRAC,y                       // $a9c9  
    sta particles_dx_FRAC,x                     // $a9cc  
    lda angle_to_x_INT,y                        // $a9cf  
    sta particles_dx_INT,x                      // $a9d2  
    lda angle_to_y_FRAC,y                       // $a9d5  
    sta particles_dy_FRAC,x                     // $a9d8  
    lda angle_to_y_INT,y                        // $a9db  
    sta particles_dy_INT,x                      // $a9de  
    rts                                         // $a9e1  
create_new_player_bullet:
    lda #$04                                    // $a9e2  
    sta collision_ignore_timer                  // $a9e4  
    lda #$ff                                    // $a9e7  
    sta player_pressed_fire                     // $a9e9  
    lda player_xpos_FRAC                        // $a9eb  
    sta particles_xpos_FRAC,x                   // $a9ed  
    lda player_xpos_INT                         // $a9f0  
    clc                                         // $a9f2  
    adc #PLAYER_CENTRE_X_OFFSET                 // $a9f3  player x position offset by $4 - start bullet in centre?
    sta particles_xpos_INT,x                    // $a9f5  
    lda player_ypos_FRAC                        // $a9f8  
    sta particles_ypos_FRAC,x                   // $a9fa  
    clc                                         // $a9fd  
    lda player_ypos_INT                         // $a9fe  
    adc #PLAYER_CENTRE_Y_OFFSET                 // $aa00  player y position offset by $5 - start bullet in centre?
    sta particles_ypos_INT,x                    // $aa02  
    lda player_ypos_INT_HI                      // $aa05  
    adc #$00                                    // $aa07  
    sta particles_ypos_INT_HI,x                 // $aa09  
    ldy ship_angle                              // $aa0c  
    jsr angle_to_bullet_dx_dy                   // $aa0e  
    ldy #$02                                    // $aa11  
move_bullet_initial:
    clc                                         // $aa13  
    lda particles_xpos_FRAC,x                   // $aa14  
    adc particles_dx_FRAC,x                     // $aa17  
    sta particles_xpos_FRAC,x                   // $aa1a  
    lda particles_xpos_INT,x                    // $aa1d  
    adc particles_dx_INT,x                      // $aa20  
    sta particles_xpos_INT,x                    // $aa23  
    clc                                         // $aa26  
    lda particles_ypos_FRAC,x                   // $aa27  
    adc particles_dy_FRAC,x                     // $aa2a  
    sta particles_ypos_FRAC,x                   // $aa2d  
    lda particles_ypos_INT,x                    // $aa30  
    adc particles_dy_INT,x                      // $aa33  
    sta particles_ypos_INT,x                    // $aa36  
    php                                         // $aa39  
    lda particles_dy_INT,x                      // $aa3a  
    bmi bullet_dy_negative                      // $aa3d  
    lda #$00                                    // $aa3f  
    jmp bullet_dy_positive                      // $aa41  
bullet_dy_negative:
    lda #$ff                                    // $aa44  
bullet_dy_positive:
    plp                                         // $aa46  
    adc particles_ypos_INT_HI,x                 // $aa47  
    sta particles_ypos_INT_HI,x                 // $aa4a  
    dey                                         // $aa4d  
    bne move_bullet_initial                     // $aa4e  
    clc                                         // $aa50  
    lda particles_dx_FRAC,x                     // $aa51  
    adc player_velocityx_FRAC                   // $aa54  
    sta particles_dx_FRAC,x                     // $aa56  
    lda particles_dx_INT,x                      // $aa59  
    adc player_velocityx_INT                    // $aa5c  
    sta particles_dx_INT,x                      // $aa5e  
    clc                                         // $aa61  
    lda particles_dy_FRAC,x                     // $aa62  
    adc player_velocityy_FRAC                   // $aa65  
    sta particles_dy_FRAC,x                     // $aa67  
    lda particles_dy_INT,x                      // $aa6a  
    adc player_velocityy_INT                    // $aa6d  
    sta particles_dy_INT,x                      // $aa6f  
    lda particles_lifetime,x                    // $aa72  
    and #$80                                    // $aa75  
    ora #$28                                    // $aa77  
    sta particles_lifetime,x                    // $aa79  
    lda #$00                                    // $aa7c  
    sta particles_type,x                        // $aa7e  
    inx                                         // $aa81  
    txa                                         // $aa82  
    and #$03                                    // $aa83  can only have 4 active bullets
    tax                                         // $aa85  
    stx bullet_index                            // $aa86  
    jsr own_gun_sound                           // $aa88  
    rts                                         // $aa8b  
unused_init_particle:
    lda #$28                                    // $aa8c  
    sta particles_xpos_FRAC,x                   // $aa8e  
    sta particles_xpos_INT,x                    // $aa91  
    lda #$02                                    // $aa94  
    sta particles_ypos_FRAC,x                   // $aa96  
    sta particles_ypos_INT,x                    // $aa99  
    sta particles_ypos_INT_HI,x                 // $aa9c  
    lda #$01                                    // $aa9f  
    sta particles_dx_FRAC,x                     // $aaa1  
    sta particles_dx_INT,x                      // $aaa4  
    sta particles_dy_FRAC,x                     // $aaa7  
    sta particles_dy_INT,x                      // $aaaa  
    lda #$28                                    // $aaad  
    sta particles_lifetime,x                    // $aaaf  
    lda #$00                                    // $aab2  
    sta particles_type,x                        // $aab4  
    rts                                         // $aab7  
rnd:
    php                                         // $aab8  
    lda rnd_A                                   // $aab9  
    pha                                         // $aabb  
    lda rnd_B                                   // $aabc  
    pha                                         // $aabe  
    lda rnd_A                                   // $aabf  
    pha                                         // $aac1  
    clc                                         // $aac2  
    rol                                         // $aac3  
    rol rnd_B                                   // $aac4  
    rol                                         // $aac6  
    rol rnd_B                                   // $aac7  
    ora #$01                                    // $aac9  
    sta rnd_A                                   // $aacb  
    clc                                         // $aacd  
    pla                                         // $aace  
    adc rnd_A                                   // $aacf  
    sta rnd_A                                   // $aad1  
    pla                                         // $aad3  
    adc rnd_B                                   // $aad4  
    sta rnd_B                                   // $aad6  
    pla                                         // $aad8  
    clc                                         // $aad9  
    adc rnd_B                                   // $aada  
    sta rnd_B                                   // $aadc  
    eor rnd_A                                   // $aade  
    plp                                         // $aae0  
    rts                                         // $aae1  
get_distance_ship_to_pod_tractor:
    sec                                         // $aae2  
    lda ship_window_ypos_INT                    // $aae3  
    sbc pod_window_ypos_INT                     // $aae5  
    bcs Laaee                                   // $aae7  
    eor #$ff                                    // $aae9  
    clc                                         // $aaeb  
    adc #$01                                    // $aaec  
Laaee:
    sta multiply_result_lo                      // $aaee  
    sec                                         // $aaf0  
    lda ship_window_xpos_FRAC                   // $aaf1  
    sbc pod_window_xpos_FRAC                    // $aaf3  
    bcs Laafc                                   // $aaf5  
    eor #$ff                                    // $aaf7  
    clc                                         // $aaf9  
    adc #$01                                    // $aafa  
Laafc:
    sta multiply_operand_a                      // $aafc  
get_distance_ship_to_pod_tractor_ext:
    lda multiply_operand_a                      // $aafe  
    cmp multiply_result_lo                      // $ab00  
    bcs Lab0a                                   // $ab02  
    ldy multiply_result_lo                      // $ab04  
    sta multiply_result_lo                      // $ab06  
    sty multiply_operand_a                      // $ab08  
Lab0a:
    lda multiply_result_lo                      // $ab0a  
    clc                                         // $ab0c  
    adc multiply_operand_a                      // $ab0d  
    bcs return_max_distance                     // $ab0f  
    adc multiply_operand_a                      // $ab11  
    bcs return_max_distance                     // $ab13  
    adc multiply_operand_a                      // $ab15  
    bcs return_max_distance                     // $ab17  
    bcc return_distance                         // $ab19  
return_max_distance:
    lda #$ff                                    // $ab1b  
return_distance:
    rts                                         // $ab1d  
line_step_fn_LO:
    .byte $00                                   // $ab1e  
line_step_fn_HI:
    .byte $00                                   // $ab1f  
line_pixel_mask:
    .byte $00                                   // $ab20  
line_sprite_offset:
    .byte $00                                   // $ab21  
line_sprite_offset_start:
    .byte $00                                   // $ab22  
line_bytes_left:
    .byte $00                                   // $ab23  
line_rows_left:
    .byte $00                                   // $ab24  
line_sprite_buffer:
    .byte $00                                   // $ab25  
draw_line_sprite:
    inc line_sprite_buffer                      // $ab26  alternate between two sprite buffers
    lda text_colour                             // $ab29  
    sta spr_colour                              // $ab2c  
    lda #$4c                                    // $ab2e  sprite frame $4C/$4D ($5300) or $4E/$4F ($5380)
    sta spr_frame                               // $ab30  
    lda #$03                                    // $ab32  
    sta line_bytes_left                         // $ab34  
    lda #$15                                    // $ab37  21 rows
    sta line_rows_left                          // $ab39  
    lda #$80                                    // $ab3c  
    sta line_pixel_mask                         // $ab3e  
    ldy #$7f                                    // $ab41  
    lda line_sprite_buffer                      // $ab43  
    ror                                         // $ab46  
    bcs draw_line_clear_buffer_1                // $ab47  
    lda #$00                                    // $ab49  
draw_line_clear_buffer_0:
    sta line_sprite_data,y                      // $ab4b  
    dey                                         // $ab4e  
    bpl draw_line_clear_buffer_0                // $ab4f  
    jmp draw_line                               // $ab51  
draw_line_clear_buffer_1:
    lda #$00                                    // $ab54  
draw_line_clear_buffer_1_loop:
    sta line_sprite_data+$80,y                  // $ab56  
    dey                                         // $ab59  
    bpl draw_line_clear_buffer_1_loop           // $ab5a  
draw_line:
    sec                                         // $ab5c  
    lda draw_line_end_x                         // $ab5d  
    sbc draw_line_start_x                       // $ab5f  
    bcs Lab7d                                   // $ab61  
    eor #$ff                                    // $ab63  
    adc #$01                                    // $ab65  
    pha                                         // $ab67  
    lda draw_line_start_x                       // $ab68  
    pha                                         // $ab6a  
    lda draw_line_end_x                         // $ab6b  
    sta draw_line_start_x                       // $ab6d  
    pla                                         // $ab6f  
    sta draw_line_end_x                         // $ab70  
    lda draw_line_start_y                       // $ab72  
    pha                                         // $ab74  
    lda draw_line_end_y                         // $ab75  
    sta draw_line_start_y                       // $ab77  
    pla                                         // $ab79  
    sta draw_line_end_y                         // $ab7a  
    pla                                         // $ab7c  
Lab7d:
    cmp #$30                                    // $ab7d  
    bcc Lab83                                   // $ab7f  
    lda #$2f                                    // $ab81  
Lab83:
    sta draw_line_delta_x                       // $ab83  
    sta draw_line_delta_major                   // $ab85  
    clc                                         // $ab87  
    lda draw_line_start_x                       // $ab88  
    adc #$0a                                    // $ab8a  
    sta spr_x_lo                                // $ab8c  
    lda #$00                                    // $ab8e  
    adc #$00                                    // $ab90  
    sta spr_x_hi                                // $ab92  
    lda draw_line_end_y                         // $ab94  
    cmp draw_line_start_y                       // $ab96  
    bcs Labb6                                   // $ab98  
    lda #<line_step_up                          // $ab9a  
    sta line_step_fn_LO                         // $ab9c  MODIFIES CODE
    lda #>line_step_up                          // $ab9f  
    sta line_step_fn_HI                         // $aba1  MODIFIES CODE
    lda #$3c                                    // $aba4  
    sta line_sprite_offset                      // $aba6  
    sta line_sprite_offset_start                // $aba9  
    lda draw_line_start_y                       // $abac  
    sec                                         // $abae  
    sbc #$14                                    // $abaf  
    sta spr_y                                   // $abb1  
    jmp Labcc                                   // $abb3  
Labb6:
    lda #<line_step_down                        // $abb6  
    sta line_step_fn_LO                         // $abb8  
    lda #>line_step_down                        // $abbb  
    sta line_step_fn_HI                         // $abbd  
    lda #$00                                    // $abc0  
    sta line_sprite_offset                      // $abc2  
    sta line_sprite_offset_start                // $abc5  
    lda draw_line_start_y                       // $abc8  
    sta spr_y                                   // $abca  
Labcc:
    lda line_sprite_buffer                      // $abcc  
    ror                                         // $abcf  
    bcc Labe1                                   // $abd0  
    lda line_sprite_offset                      // $abd2  
    ora #$80                                    // $abd5  
    sta line_sprite_offset                      // $abd7  
    sta line_sprite_offset_start                // $abda  
    inc spr_frame                               // $abdd  
    inc spr_frame                               // $abdf  
Labe1:
    lda #<line_step_right                       // $abe1  
    sta plot_line_bresenham_1_addr_LO           // $abe3  MODIFIES CODE
    sta plot_line_bresenham_2_addr_LO           // $abe6  MODIFIES CODE
    lda #>line_step_right                       // $abe9  
    sta plot_line_bresenham_1_addr_HI           // $abeb  MODIFIES CODE
    sta plot_line_bresenham_2_addr_HI           // $abee  MODIFIES CODE
    sec                                         // $abf1  
    lda draw_line_end_y                         // $abf2  
    sbc draw_line_start_y                       // $abf4  
    bcs Labfc                                   // $abf6  
    eor #$ff                                    // $abf8  
    adc #$01                                    // $abfa  
Labfc:
    cmp #$2a                                    // $abfc  
    bcc Lac02                                   // $abfe  
    lda #$29                                    // $ac00  
Lac02:
    sta draw_line_delta_y_unused                // $ac02  
    sta draw_line_delta_minor                   // $ac04  
    cmp draw_line_delta_major                   // $ac06  
    bcc Lac21                                   // $ac08  
    pha                                         // $ac0a  
    lda draw_line_delta_major                   // $ac0b  
    sta draw_line_delta_minor                   // $ac0d  
    pla                                         // $ac0f  
    sta draw_line_delta_major                   // $ac10  
    lda line_step_fn_LO                         // $ac12  
    sta plot_line_bresenham_1_addr_LO           // $ac15  MODIFIES CODE
    lda line_step_fn_HI                         // $ac18  
    sta plot_line_bresenham_1_addr_HI           // $ac1b  MODIFIES CODE
    jmp Lac2d                                   // $ac1e  
Lac21:
    lda line_step_fn_LO                         // $ac21  
    sta plot_line_bresenham_2_addr_LO           // $ac24  MODIFIES CODE
    lda line_step_fn_HI                         // $ac27  
    sta plot_line_bresenham_2_addr_HI           // $ac2a  MODIFIES CODE
Lac2d:
    lda draw_line_delta_major                   // $ac2d  
    clc                                         // $ac2f  
    ror                                         // $ac30  
    sta bresenham_error                         // $ac31  
    jsr sprite_list_add                         // $ac33  
    ldx draw_line_delta_major                   // $ac36  
    inx                                         // $ac38  
    jmp plot_line_pixels                        // $ac39  
plot_line_bresenham_1:
    .label plot_line_bresenham_1_addr_LO = *+1
    .label plot_line_bresenham_1_addr_HI = *+2
    jsr line_step_right                         // $ac3c  SELF-MODIFIED CODE
    lda bresenham_error                         // $ac3f  
    clc                                         // $ac41  
    adc draw_line_delta_minor                   // $ac42  
    bcs plot_line_bresenham_2                   // $ac44  
    cmp draw_line_delta_major                   // $ac46  
    bcs plot_line_bresenham_2                   // $ac48  
    sta bresenham_error                         // $ac4a  
plot_line_pixels:
    lda line_pixel_mask                         // $ac4c  
    ldy line_sprite_offset                      // $ac4f  
    eor line_sprite_data,y                      // $ac52  plot into the sprite data
    sta line_sprite_data,y                      // $ac55  
    dex                                         // $ac58  
    bne plot_line_bresenham_1                   // $ac59  
    rts                                         // $ac5b  
plot_line_bresenham_2:
    sbc draw_line_delta_major                   // $ac5c  
    sta bresenham_error                         // $ac5e  
plot_line_bresenham_2_JSR_label:
    .label plot_line_bresenham_2_addr_LO = *+1
    .label plot_line_bresenham_2_addr_HI = *+2
    jsr line_step_down                          // $ac60  SELF-MODIFIED CODE
    jmp plot_line_pixels                        // $ac63  
line_step_right:
    inc spr_x_lo                                // $ac66  
    clc                                         // $ac68  
    ror line_pixel_mask                         // $ac69  
    bcc line_step_return                        // $ac6c  
    ror line_pixel_mask                         // $ac6e  
    inc line_sprite_offset                      // $ac71  
    dec line_bytes_left                         // $ac74  
    beq line_next_sprite                        // $ac77  
line_step_return:
    rts                                         // $ac79  
line_step_down:
    inc spr_y                                   // $ac7a  
    clc                                         // $ac7c  
    lda line_sprite_offset                      // $ac7d  
    adc #$03                                    // $ac80  
    sta line_sprite_offset                      // $ac82  
    dec line_rows_left                          // $ac85  
    beq line_next_sprite                        // $ac88  
    rts                                         // $ac8a  
line_step_up:
    dec spr_y                                   // $ac8b  
    sec                                         // $ac8d  
    lda line_sprite_offset                      // $ac8e  
    sbc #$03                                    // $ac91  
    sta line_sprite_offset                      // $ac93  
    dec line_rows_left                          // $ac96  
    beq line_next_sprite                        // $ac99  
    rts                                         // $ac9b  
line_next_sprite:
    inc spr_frame                               // $ac9c  
    lda line_sprite_offset_start                // $ac9e  
    clc                                         // $aca1  
    adc #$40                                    // $aca2  
    sta line_sprite_offset                      // $aca4  
    lda #$03                                    // $aca7  
    sta line_bytes_left                         // $aca9  
    lda #$15                                    // $acac  
    sta line_rows_left                          // $acae  
    lda #$80                                    // $acb1  
    sta line_pixel_mask                         // $acb3  
    txa                                         // $acb6  
    pha                                         // $acb7  
    jsr sprite_list_add                         // $acb8  
    pla                                         // $acbb  
    tax                                         // $acbc  
    rts                                         // $acbd  
calculate_pixels_ptr:
    lda #$00                                    // $acbe  
    sta plot_pixels_ptr                         // $acc0  
    sta screen_addr_hi_temp                     // $acc2  
    lda draw_line_start_y                       // $acc4  
    clc                                         // $acc6  
    and #$f8                                    // $acc7  
    ror                                         // $acc9  
    ror                                         // $acca  
    ror                                         // $accb  
    sta plot_pixels_ptr+1                       // $accc  
    ror                                         // $acce  
    ror plot_pixels_ptr                         // $accf  
    ror                                         // $acd1  
    ror plot_pixels_ptr                         // $acd2  
    adc #$60                                    // $acd4  
    adc plot_pixels_ptr+1                       // $acd6  
    sta plot_pixels_ptr+1                       // $acd8  
    lda draw_line_start_x                       // $acda  
    and #$f8                                    // $acdc  
    adc plot_pixels_ptr                         // $acde  
    sta plot_pixels_ptr                         // $ace0  
    lda #$00                                    // $ace2  
    adc plot_pixels_ptr+1                       // $ace4  
    sta plot_pixels_ptr+1                       // $ace6  
    lda draw_line_start_y                       // $ace8  
    and #$07                                    // $acea  
    adc plot_pixels_ptr                         // $acec  
    sta plot_pixels_ptr                         // $acee  
    lda draw_line_start_x                       // $acf0  
    and #$07                                    // $acf2  
    sta pixel_column_index                      // $acf4  
    rts                                         // $acf6  
plot_teleport_effect_step_horizontal:
    .label jump_fn_1_addr_LO = *+1
    .label jump_fn_1_addr_HI = *+2
    jmp pixels_ptr_add_7                        // $acf7  SELF-MODIFIED CODE
plot_teleport_effect_step_vertical:
    .label jump_fn_2_addr_LO = *+1
    .label jump_fn_2_addr_HI = *+2
    jmp pixels_ptr_increment                    // $acfa  SELF-MODIFIED CODE
plot_teleport_effect_3:
    lda plot_pixels_ptr                         // $acfd  
    pha                                         // $acff  
    lda plot_pixels_ptr+1                       // $ad00  
    pha                                         // $ad02  
    lda pixel_column_index                      // $ad03  
    pha                                         // $ad05  
    ldx teleport_ring_count                     // $ad06  
Lad08:
    jsr plot_teleport_effect_step_horizontal    // $ad08  
    dex                                         // $ad0b  
    bne Lad08                                   // $ad0c  
    lda teleport_ring_count                     // $ad0e  
    sta teleport_row_count                      // $ad10  
Lad12:
    lda plot_pixels_ptr                         // $ad12  
    pha                                         // $ad14  
    lda plot_pixels_ptr+1                       // $ad15  
    pha                                         // $ad17  
    ldx #$08                                    // $ad18  
Lad1a:
    jsr plot_teleport_pixels                    // $ad1a  
    jsr plot_teleport_effect_step_vertical      // $ad1d  
    dex                                         // $ad20  
    bne Lad1a                                   // $ad21  
    pla                                         // $ad23  
    sta plot_pixels_ptr+1                       // $ad24  
    pla                                         // $ad26  
    sta plot_pixels_ptr                         // $ad27  
    ldx #$08                                    // $ad29  
Lad2b:
    jsr plot_teleport_effect_step_horizontal    // $ad2b  
    dex                                         // $ad2e  
    bne Lad2b                                   // $ad2f  
    dec teleport_row_count                      // $ad31  
    bne Lad12                                   // $ad33  
    pla                                         // $ad35  
    sta pixel_column_index                      // $ad36  
    pla                                         // $ad38  
    sta plot_pixels_ptr+1                       // $ad39  
    pla                                         // $ad3b  
    sta plot_pixels_ptr                         // $ad3c  
    rts                                         // $ad3e  
pixel_masks_1:
    .byte $c0,$00,$30,$00,$0c,$00,$03,$00       // $ad3f  
plot_teleport_pixels:
    ldy pixel_column_index                      // $ad47  
    lda pixel_masks_1,y                         // $ad49  
    and pixel_colour_mask                       // $ad4c  
    ldy #$00                                    // $ad4e  
    eor (plot_pixels_ptr),y                     // $ad50  
    sta (plot_pixels_ptr),y                     // $ad52  
    rts                                         // $ad54  
plot_teleport_effect_1:
    lda #$55                                    // $ad55  
    sta pixel_colour_mask                       // $ad57  
    lda old_plot_pixels_ptr                     // $ad59  
    sta plot_pixels_ptr                         // $ad5b  
    lda old_plot_pixels_ptr+1                   // $ad5d  
    sta plot_pixels_ptr+1                       // $ad5f  
    lda old_pixel_column_index                  // $ad61  
    sta pixel_column_index                      // $ad63  
    jsr plot_teleport_effect_2                  // $ad65  
    lda #$ff                                    // $ad68  
    sta pixel_colour_mask                       // $ad6a  
    lda teleport_screen_addr_LO                 // $ad6c  
    sta plot_pixels_ptr                         // $ad6e  
    lda teleport_screen_addr_HI                 // $ad70  
    sta plot_pixels_ptr+1                       // $ad72  
    beq plot_teleport_effect_1_return           // $ad74  
    lda current_obj_visible_flag                // $ad76  
    sta pixel_column_index                      // $ad78  
    jsr plot_teleport_effect_2                  // $ad7a  
plot_teleport_effect_1_return:
    rts                                         // $ad7d  
plot_teleport_effect_2:
    lda #<pixels_ptr_add_7                      // $ad7e  
    sta jump_fn_1_addr_LO                       // $ad80  MODIFIES CODE
    lda #>pixels_ptr_add_7                      // $ad83  
    sta jump_fn_1_addr_HI                       // $ad85  MODIFIES CODE
    lda #<pixels_ptr_increment                  // $ad88  
    sta jump_fn_2_addr_LO                       // $ad8a  MODIFIES CODE
    lda #>pixels_ptr_increment                  // $ad8d  
    sta jump_fn_2_addr_HI                       // $ad8f  MODIFIES CODE
    jsr plot_teleport_effect_3                  // $ad92  
    lda #<pixels_ptr_sbc_8                      // $ad95  
    sta jump_fn_1_addr_LO                       // $ad97  MODIFIES CODE
    lda #>pixels_ptr_sbc_8                      // $ad9a  
    sta jump_fn_1_addr_HI                       // $ad9c  MODIFIES CODE
    ldx #$09                                    // $ad9f  
loop_1:
    jsr pixels_ptr_sbc_8                        // $ada1  
    dex                                         // $ada4  
    bne loop_1                                  // $ada5  
    jsr plot_teleport_effect_3                  // $ada7  
    lda #<pixels_ptr_decrement                  // $adaa  
    sta jump_fn_1_addr_LO                       // $adac  MODIFIES CODE
    lda #>pixels_ptr_decrement                  // $adaf  
    sta jump_fn_1_addr_HI                       // $adb1  MODIFIES CODE
    lda #<pixels_ptr_add_7                      // $adb4  
    sta jump_fn_2_addr_LO                       // $adb6  MODIFIES CODE
    lda #>pixels_ptr_add_7                      // $adb9  
    sta jump_fn_2_addr_HI                       // $adbb  MODIFIES CODE
    jsr pixels_ptr_add_7                        // $adbe  
    jsr pixels_ptr_decrement                    // $adc1  
    jsr plot_teleport_effect_3                  // $adc4  
    lda #<pixels_ptr_increment                  // $adc7  
    sta jump_fn_1_addr_LO                       // $adc9  MODIFIES CODE
    lda #>pixels_ptr_increment                  // $adcc  
    sta jump_fn_1_addr_HI                       // $adce  MODIFIES CODE
    ldx #$09                                    // $add1  
loop_2:
    jsr pixels_ptr_increment                    // $add3  
    dex                                         // $add6  
    bne loop_2                                  // $add7  
    jsr plot_teleport_effect_3                  // $add9  
    rts                                         // $addc  
pixels_ptr_add_7:
    ldy pixel_column_index                      // $addd  
    iny                                         // $addf  
    cpy #$08                                    // $ade0  
    bne pixels_ptr_add_7_return                 // $ade2  
    ldy #$00                                    // $ade4  
    lda plot_pixels_ptr                         // $ade6  
    adc #$07                                    // $ade8  
    sta plot_pixels_ptr                         // $adea  
    bcc pixels_ptr_add_7_return                 // $adec  
    inc plot_pixels_ptr+1                       // $adee  
pixels_ptr_add_7_return:
    sty pixel_column_index                      // $adf0  
    rts                                         // $adf2  
pixels_ptr_sbc_8:
    dec pixel_column_index                      // $adf3  
    bmi Ladf8                                   // $adf5  
    rts                                         // $adf7  
Ladf8:
    ldy #$07                                    // $adf8  
    sty pixel_column_index                      // $adfa  
    sec                                         // $adfc  
    lda plot_pixels_ptr                         // $adfd  
    sbc #$08                                    // $adff  
    sta plot_pixels_ptr                         // $ae01  
    bcs pixels_ptr_sbc_8_return                 // $ae03  
    dec plot_pixels_ptr+1                       // $ae05  
pixels_ptr_sbc_8_return:
    rts                                         // $ae07  
pixels_ptr_increment:
    inc plot_pixels_ptr                         // $ae08  
    lda plot_pixels_ptr                         // $ae0a  
    and #$07                                    // $ae0c  
    beq Lae11                                   // $ae0e  
    rts                                         // $ae10  
Lae11:
    dec plot_pixels_ptr                         // $ae11  
    clc                                         // $ae13  
    lda plot_pixels_ptr                         // $ae14  
    adc #$39                                    // $ae16  
    sta plot_pixels_ptr                         // $ae18  
    lda plot_pixels_ptr+1                       // $ae1a  
    adc #$01                                    // $ae1c  
    sta plot_pixels_ptr+1                       // $ae1e  
    rts                                         // $ae20  
pixels_ptr_decrement:
    dec plot_pixels_ptr                         // $ae21  
    lda plot_pixels_ptr                         // $ae23  
    and #$07                                    // $ae25  
    cmp #$07                                    // $ae27  
    beq Lae2c                                   // $ae29  
    rts                                         // $ae2b  
Lae2c:
    inc plot_pixels_ptr                         // $ae2c  
    lda plot_pixels_ptr                         // $ae2e  
    sbc #$39                                    // $ae30  
    sta plot_pixels_ptr                         // $ae32  
    lda plot_pixels_ptr+1                       // $ae34  
    sbc #$01                                    // $ae36  
    sta plot_pixels_ptr+1                       // $ae38  
    rts                                         // $ae3a  
draw_new_line:
    lda pod_destroying_player_timer             // $ae3b  
    bpl Lae43                                   // $ae3d  
    lda pod_attached_flag_1                     // $ae3f  
    bne Lae48                                   // $ae41  
Lae43:
    lda pod_line_exists_flag                    // $ae43  
    bne Lae48                                   // $ae45  
    rts                                         // $ae47  
Lae48:
    lda #$02                                    // $ae48  
    sta line_drawn_flag                         // $ae4a  
    jsr calculate_line_coordinates              // $ae4c  
    jmp draw_line_sprite                        // $ae4f  
calculate_line_coordinates:
    clc                                         // $ae52  
    lda ship_window_ypos_INT                    // $ae53  
    adc #$0a                                    // $ae55  
    sta draw_line_start_y                       // $ae57  
    lda pod_window_ypos_INT                     // $ae59  
    adc #$0a                                    // $ae5b  
    sta draw_line_end_y                         // $ae5d  
    lda ship_window_xpos_FRAC                   // $ae5f  
    sta draw_line_start_x                       // $ae61  
    lda pod_window_xpos_FRAC                    // $ae63  
    sta draw_line_start_y+1                     // $ae65  
    rts                                         // $ae67  
text_colour:
    .byte $ff                                   // $ae68  
draw_fuel_beam:
    lda fuel_beam_position_flag                 // $ae69  
    beq draw_fuel_beam_test                     // $ae6b  
    lda #$00                                    // $ae6d  
    sta fuel_beam_position_flag                 // $ae6f  
draw_fuel_beam_test:
    lda collecting_fuel_flag                    // $ae71  
    bne draw_fuel_beam_on                       // $ae73  
calculate_line_coordinates_return:
    rts                                         // $ae75  
draw_fuel_beam_on:
    jsr add_fuel                                // $ae76  
    lda level_tick_counter                      // $ae79  
    ror                                         // $ae7b  
    bcc calculate_line_coordinates_return       // $ae7c  
    lda VIC_SPR7_Y                              // $ae7e  beam sprites below the ship
    clc                                         // $ae81  
    adc #$18                                    // $ae82  
    sta spr_y                                   // $ae84  
    lda VIC_SPR7_X                              // $ae86  
    clc                                         // $ae89  
    sec                                         // $ae8a  
    sbc #$01                                    // $ae8b  
    sta spr_x_lo                                // $ae8d  
    lda #$00                                    // $ae8f  
    sta spr_x_hi                                // $ae91  
    lda #$07                                    // $ae93  
    sta spr_colour                              // $ae95  
    lda #$2f                                    // $ae97  frames $2F/$30 = fuel beam
    sta spr_frame                               // $ae99  
    jsr sprite_list_add                         // $ae9b  
    inc spr_frame                               // $ae9e  
    lda spr_y                                   // $aea0  
    clc                                         // $aea2  
    adc #$15                                    // $aea3  
    sta spr_y                                   // $aea5  
    lda #$01                                    // $aea7  
    sta fuel_beam_position_flag                 // $aea9  
    jmp sprite_list_add                         // $aeab  
do_teleport_animation:
    lda #$00                                    // $aeae  
    sta teleport_ring_count                     // $aeb0  
Laeb2:
    inc teleport_ring_count                     // $aeb2  
    jsr plot_teleport_effect_1                  // $aeb4  
    jsr teleport_step_appear                    // $aeb7  
    lda teleport_ring_count                     // $aeba  
    cmp #$06                                    // $aebc  
    bne Laeb2                                   // $aebe  
Laec0:
    jsr teleport_step_disappear                 // $aec0  
    jsr teleport_step_disappear                 // $aec3  
    jsr plot_teleport_effect_1                  // $aec6  
    dec teleport_ring_count                     // $aec9  
    bne Laec0                                   // $aecb  
    rts                                         // $aecd  
teleport_step_disappear:
    lda teleport_appear_or_disappear            // $aece  
    beq teleport_step_ship_gone                 // $aed0  
    bne go_to_draw                              // $aed2  
teleport_step_appear:
    lda teleport_appear_or_disappear            // $aed4  
    bne teleport_step_ship_gone                 // $aed6  
    beq go_to_draw                              // $aed8  
teleport_step_ship_gone:
    lda teleport_ring_count                     // $aeda  
    cmp #$03                                    // $aedc  
    bcs go_to_draw                              // $aede  
    ldx #$00                                    // $aee0  
    stx plot_ship_collision_detected            // $aee2  
    stx pod_line_exists_flag                    // $aee4  
    stx pod_attached_flag_1                     // $aee6  
go_to_draw:
    jsr draw_player_timed_to_vsync              // $aee8  
    jsr check_collisions                        // $aeeb  
    jmp wait_game_tick                          // $aeee  
player_teleport_appear:
    lda #$00                                    // $aef1  
    sta teleport_appear_or_disappear            // $aef3  
    beq player_teleport                         // $aef5  
player_teleport_disappear:
    lda #$00                                    // $aef7  
    sta ship_sprite_plotted_flag                // $aef9  
    sta player_ship_destroyed_flag              // $aefb  
    lda #$ff                                    // $aefd  
    sta teleport_appear_or_disappear            // $aeff  
player_teleport:
    lda pod_line_exists_flag                    // $af01  
    pha                                         // $af03  
    lda plot_ship_collision_detected            // $af04  
    pha                                         // $af06  
    lda pod_attached_flag_1                     // $af07  
    pha                                         // $af09  
    ldx #$ff                                    // $af0a  
    stx plot_ship_collision_detected            // $af0c  
    inx                                         // $af0e  
    stx pod_line_exists_flag                    // $af0f  
    stx pod_attached_flag_1                     // $af11  
    jsr draw_player_timed_to_vsync              // $af13  
    jsr calculate_line_coordinates              // $af16  
    sec                                         // $af19  
    lda draw_line_start_x                       // $af1a  
    sbc #$0d                                    // $af1c  
    sta draw_line_start_x                       // $af1e  
    sec                                         // $af20  
    lda draw_line_end_x                         // $af21  
    sbc #$0d                                    // $af23  
    sta draw_line_end_x                         // $af25  
    sec                                         // $af27  
    lda draw_line_start_y                       // $af28  
    sbc #$32                                    // $af2a  
    sta draw_line_start_y                       // $af2c  
    sec                                         // $af2e  
    lda draw_line_end_y                         // $af2f  
    sbc #$32                                    // $af31  
    sta draw_line_end_y                         // $af33  
    jsr calculate_pixels_ptr                    // $af35  
    jsr pixels_ptr_offset_diagonal_by_4         // $af38  
    lda plot_pixels_ptr                         // $af3b  
    sta old_plot_pixels_ptr                     // $af3d  
    lda plot_pixels_ptr+1                       // $af3f  
    sta old_plot_pixels_ptr+1                   // $af41  
    lda pixel_column_index                      // $af43  
    sta old_pixel_column_index                  // $af45  
    lda draw_line_end_x                         // $af47  
    sta draw_line_start_x                       // $af49  
    lda draw_line_end_y                         // $af4b  
    sta draw_line_start_y                       // $af4d  
    jsr calculate_pixels_ptr                    // $af4f  
    jsr pixels_ptr_offset_diagonal_by_4         // $af52  
    lda plot_pixels_ptr                         // $af55  
    sta teleport_screen_addr_LO                 // $af57  
    lda plot_pixels_ptr+1                       // $af59  
    sta teleport_screen_addr_HI                 // $af5b  
    lda pixel_column_index                      // $af5d  
    sta current_obj_visible_flag                // $af5f  
    pla                                         // $af61  
    pha                                         // $af62  
    bne Laf69                                   // $af63  
    lda #$00                                    // $af65  
    sta teleport_screen_addr_HI                 // $af67  
Laf69:
    jsr do_teleport_animation                   // $af69  
    pla                                         // $af6c  
    sta pod_attached_flag_1                     // $af6d  
    pla                                         // $af6f  
    sta plot_ship_collision_detected            // $af70  
    pla                                         // $af72  
    sta pod_line_exists_flag                    // $af73  
    rts                                         // $af75  
pixels_ptr_offset_diagonal_by_4:
    ldx #$04                                    // $af76  
pixels_ptr_offset_diagonal_by_4_loop:
    jsr pixels_ptr_add_7                        // $af78  
    jsr pixels_ptr_decrement                    // $af7b  
    dex                                         // $af7e  
    bne pixels_ptr_offset_diagonal_by_4_loop    // $af7f  
    rts                                         // $af81  
game_start:
    lda #$00                                    // $af82  from init2: sound on, go to the title screen
    sta mute_sound_flag                         // $af84  
    jmp start_game                              // $af86  
title_shown_flag:
    .byte $00                                   // $af89  
level_hostile_gun_probability:
    .byte $00                                   // $af8a  
planet_destroyed_hostile_gun_modifier:
    .byte $00                                   // $af8b  
reverse_gravity_msg_shown:
    .byte $00                                   // $af8c  
invisible_landscape_msg_shown:
    .byte $00                                   // $af8d  
high_score_time_out:
    .byte $00                                   // $af8e  
landscape_visible_flag:
    .byte $00                                   // $af8f  
collision_ignore_timer:
    .byte $00                                   // $af90  
player_new_high_score:
    jsr check_high_score                        // $af91  
high_score_start:
    lda #$00                                    // $af94  
    sta SID_V1_CTRL                             // $af96  
    sta SID_V2_CTRL                             // $af99  
    sta sfx_v1_ctrl                             // $af9c  
    sta sfx_v2_ctrl                             // $af9f  
    sta SID_V3_CTRL                             // $afa2  
    lda #$00                                    // $afa5  
    sta sfx_explosion_timer                     // $afa7  
    sta sfx_engine_timer                        // $afaa  
    sta sfx_shield_timer                        // $afad  
    sta sfx_own_gun_timer                       // $afb0  
    sta sfx_hostile_gun_timer                   // $afb3  
    sta sfx_ping_timer                          // $afb6  
    lda #$00                                    // $afb9  
    sta total_levels_played                     // $afbb  
    sta invisible_landscape_flag                // $afbd  
    sta level_number                            // $afbf  
    sta reverse_gravity_flag                    // $afc2  
    lda #$ff                                    // $afc5  
    sta demo_mode_flag                          // $afc7  
    lda #$8c                                    // $afc9  
    sta high_score_time_out                     // $afcb  
    lda #$02                                    // $afce  
    sta hostile_gun_shoot_probability           // $afd0  
    jsr initialise_level_pointers               // $afd2  
    jsr level_reset                             // $afd5  
    jsr sprite_list_clear                       // $afd8  
    jsr initialise_landscape                    // $afdb  
    jsr update_window_and_terrain_tables        // $afde  
    jsr landscape_draw                          // $afe1  
    jsr plot_pod_sprite                         // $afe4  
    jsr update_and_draw_all_objects             // $afe7  
    jsr set_text_screen_colours                 // $afea  
    jsr plot_high_score_table                   // $afed  
    jsr write_top_8_thrusters                   // $aff0  
    jsr write_title_screen_texts                // $aff3  thrusty-levels: was write_press_spacebar
    ldx #$00                                    // $aff6  
    stx demo_keypress_bit_mask                  // $aff8  
    stx demo_keypress_timer                     // $affb  
    stx demo_keypress_index                     // $affe  
    lda #$ff                                    // $b001  
    sta demo_mode_flag                          // $b003  
    jsr reset_game_tick                         // $b005  
high_score_tick_loop:
    inc level_tick_counter                      // $b008  
    jsr sprite_bands_build                      // $b00a  
    jsr sprite_list_clear                       // $b00d  
    jsr update_and_draw_all_objects             // $b010  
    jsr particles_update_and_draw               // $b013  
high_score_wait_tick:
    lda game_tick_timer                         // $b016  
    bpl high_score_wait_tick                    // $b019  
    clc                                         // $b01b  
    adc #$03                                    // $b01c  
    sta game_tick_timer                         // $b01e  
    ldx #KEY_SPACE                              // $b021  
    jsr test_key                                // $b023  
    beq start_game                              // $b026  
    lda level_tick_counter                      // $b028  
    and #$01                                    // $b02a  
    beq high_score_tick_loop                    // $b02c  
    dec high_score_time_out                     // $b02e  
    bne high_score_tick_loop                    // $b031  
    jsr clear_screen_and_sprites                // $b033  
    ldy #$0a                                    // $b036  
    jsr wait_time_out_Y                         // $b038  
    jsr initialise_level_pointers               // $b03b  
    lda #$ff                                    // $b03e  
    sta demo_mode_flag                          // $b040  
    jmp level_start_demo_entry                  // $b042  
start_game:
    lda #$00                                    // $b045  
    sta demo_mode_flag                          // $b047  
start_new_game:
    ldx #$01                                    // $b049  
    stx level_hostile_gun_probability           // $b04b  set level_hostile_gun_probability to 1
    dex                                         // $b04e  
    stx planet_destroyed_hostile_gun_modifier   // $b04f  set planet_destroyed_hostile_gun_modifier to 0
    stx reverse_gravity_msg_shown               // $b052  set reverse_gravity_msg_shown to 0
    stx invisible_landscape_msg_shown           // $b055  set invisible_landscape_msg_shown to 0
    ldx #$03                                    // $b058  
zero_fuel_and_score:
    lda #$00                                    // $b05a  
    sta fuel_A,x                                // $b05c  set fuel_A to zero
    sta score_A,x                               // $b05f  set score_A to zero
    dex                                         // $b062  
    bpl zero_fuel_and_score                     // $b063  
    ldx #$0d                                    // $b065  
store_32_loop:
    lda #$20                                    // $b067  
    sta score_C,x                               // $b069  store $20 (32) at L0183 for 13 bytes
    dex                                         // $b06c  
    bne store_32_loop                           // $b06d  
    lda #$00                                    // $b06f  set initial score_A
    jsr add_A_to_score                          // $b071  
    lda #INITIAL_LIVES                          // $b074  set initial number of lives
    sta lives                                   // $b076  
    jsr lose_a_life                             // $b079  
    lda #INITIAL_FUEL                           // $b07c  
    sta fuel_B                                  // $b07e  set initial fuel value (1000)
    lda #$ff                                    // $b081  
    sta total_levels_played                     // $b083  set total_levels_played to 255 (-1)
    lda #$ff                                    // $b085  
    sta level_number                            // $b087  set level_number to 255 (-1)
    lda #$00                                    // $b08a  
    sta mission_number                          // $b08c  zero mission number
    sta level_modifier_flag                     // $b08f  zero level modifier flag (reverse gravity etc.)
    sta invisible_landscape_flag                // $b092  set invisible_landscape_flag to 0
    sta reverse_gravity_flag                    // $b094  set reverse_gravity_flag to 0
    sta fuel_empty_flag                         // $b097  zero fuel flag
    jsr plot_fuel_value                         // $b09a  
    ldy #$02                                    // $b09d  
    jsr wait_time_out_Y                         // $b09f  
    lda VIC_CTRL1                               // $b0a2  
    and #$7f                                    // $b0a5  
    ora #$10                                    // $b0a7  
    sta VIC_CTRL1                               // $b0a9  
    lda title_shown_flag                        // $b0ac  first time: show title / high score screen
    bne start_new_level                         // $b0af  
    lda #$ff                                    // $b0b1  
    sta title_shown_flag                        // $b0b3  
    jmp high_score_start                        // $b0b6  
start_new_level:
    jsr clear_screen_and_sprites                // $b0b9  
    jsr set_text_screen_colours                 // $b0bc  
    lda #$00                                    // $b0bf  
    sta midpoint_ypos_INT                       // $b0c1  
    sta midpoint_ypos_INT_HI                    // $b0c3  
    inc total_levels_played                     // $b0c5  
    inc level_number                            // $b0c7  
    lda level_number                            // $b0ca  
    cmp #$06                                    // $b0cd  NUMBER OF LEVELS - all per-level tables have 6 entries
    bne setup_next_mission                      // $b0cf  
    lda #$00                                    // $b0d1  
    sta level_number                            // $b0d3  reset level number to 0
    lda reverse_gravity_flag                    // $b0d6  
    eor #$ff                                    // $b0d9  
    sta reverse_gravity_flag                    // $b0db  invert flag
    bne setup_reverse_gravity                   // $b0de  
    lda invisible_landscape_flag                // $b0e0  
    eor #$ff                                    // $b0e2  
    sta invisible_landscape_flag                // $b0e4  invert lower 4 bits of flag
setup_reverse_gravity:
    lda reverse_gravity_flag                    // $b0e6  
    beq setup_invisible_landscape               // $b0e9  
    lda reverse_gravity_msg_shown               // $b0eb  
    bne setup_invisible_landscape               // $b0ee  
    jsr clear_screen_and_sprites                // $b0f0  
    jsr write_reverse_gravity                   // $b0f3  
    ldy #$96                                    // $b0f6  
    sty reverse_gravity_msg_shown               // $b0f8  
    jsr wait_time_out_Y                         // $b0fb  
    jmp setup_next_mission                      // $b0fe  
setup_invisible_landscape:
    lda invisible_landscape_flag                // $b101  
    beq setup_next_mission                      // $b103  
    lda invisible_landscape_msg_shown           // $b105  
    bne setup_next_mission                      // $b108  
    jsr clear_screen_and_sprites                // $b10a  
    jsr write_invisible_landscape               // $b10d  
    ldy #$96                                    // $b110  why $96?  Just timeout value recycled as flag!
    sty invisible_landscape_msg_shown           // $b112  
    jsr wait_time_out_Y                         // $b115  
setup_next_mission:
    sed                                         // $b118  set decimal mode
    clc                                         // $b119  
    lda mission_number                          // $b11a  
    adc #$01                                    // $b11d  
    sta mission_number                          // $b11f  increment mission_number by 1
    cld                                         // $b122  clear decimal mode
    lda #$01                                    // $b123  
    ldx mission_number                          // $b125  
    cpx #$03                                    // $b128  
    bcc setup_level                             // $b12a  mission_number less than 3
    inc level_hostile_gun_probability           // $b12c  increment level_hostile_gun_probability
    lda level_hostile_gun_probability           // $b12f  
    cmp #$23                                    // $b132  
    bcc setup_level                             // $b134  
    lda #$23                                    // $b136  
    sta level_hostile_gun_probability           // $b138  cap level_hostile_gun_probability to $23 (35)
setup_level:
    clc                                         // $b13b  
    adc planet_destroyed_hostile_gun_modifier   // $b13c  level_hostile_gun_probability + planet_destroyed_hostile_gun_modifier
    sta hostile_gun_shoot_probability           // $b13f  store at hostile_gun_shoot_probability
    lda #$00                                    // $b141  
    sta planet_destroyed_hostile_gun_modifier   // $b143  reset planet_destroyed_hostile_gun_modifier to zero
    jsr clear_screen_and_sprites                // $b146  
    jsr initialise_level_pointers               // $b149  
level_retry:
    jsr level_reset                             // $b14c  
level_start_demo_entry:
    jsr rnd                                     // $b14f  
    and #$03                                    // $b152  
    adc #$08                                    // $b154  
    sta demo_keypress_timer_rnd_A               // $b156  tweak keypress timers for demo mode
    jsr rnd                                     // $b159  
    and #$03                                    // $b15c  
    adc #$04                                    // $b15e  
    sta demo_keypress_timer_rnd_B               // $b160  tweak keypress timers for demo mode
    lda #$7f                                    // $b163  
    sta demo_keypress_timer_rnd_C               // $b165  tweak keypress timers for demo mode
    jsr rnd                                     // $b168  
    and #$03                                    // $b16b  
    bne demo_no_big_spin                        // $b16d  
    lda #$23                                    // $b16f  
    sta demo_keypress_timer_rnd_C               // $b171  is either $7F (75%) or $23 (25%) - big spin 1 in 4 times? :)
demo_no_big_spin:
    lda #$00                                    // $b174  
    sta level_tick_counter                      // $b176  set level_tick_counter to 0
    jsr sprite_list_clear                       // $b178  
    jsr initialise_landscape                    // $b17b  
    jsr update_window_and_terrain_tables        // $b17e  
    jsr calculate_player_position_from_midpoint // $b181  
    jsr landscape_draw                          // $b184  
    jsr update_and_draw_all_objects             // $b187  
    jsr sprite_bands_build                      // $b18a  
    ldy #$0f                                    // $b18d  
    jsr wait_time_out_Y                         // $b18f  
    jsr draw_player_timed_to_vsync              // $b192  
    jsr player_teleport_appear                  // $b195  
    lda #$00                                    // $b198  
    sta level_tick_state                        // $b19a  
    jsr reset_game_tick                         // $b19c  
tick_loop:
    jsr sprite_list_clear                       // $b19f  
    lda VIC_SPR_SPR_COLL                        // $b1a2  
    lda VIC_SPR_BG_COLL                         // $b1a5  
    lda #$0a                                    // $b1a8  ignore collisions for the first 10 frames
    sta collision_ignore_timer                  // $b1aa  
tick_loop_continue:
    jsr demo_mode_tick                          // $b1ad  
    jsr hide_landscape                          // $b1b0  
    jsr ship_input_rotate                       // $b1b3  
    jsr midpoint_add_velocity_vector            // $b1b6  
    jsr update_window_and_terrain_tables        // $b1b9  
    jsr wait_game_tick                          // $b1bc  wait for the next game tick (CIA timer)
    jsr update_player_and_pod_states            // $b1bf  
    jsr update_and_draw_all_objects             // $b1c2  
    jsr draw_player_timed_to_vsync              // $b1c5  
    jsr draw_new_line                           // $b1c8  
    jsr sprite_bands_build                      // $b1cb  
    jsr sprite_list_clear                       // $b1ce  
    jsr landscape_draw                          // $b1d1  
    jsr ship_input_fire                         // $b1d4  
    jsr particles_update_and_draw               // $b1d7  
    jsr test_for_pause                          // $b1da  
    jsr calculate_player_position_from_midpoint // $b1dd  
    jsr plot_fuel_value                         // $b1e0  
    jsr ship_input_thrust_calculate_force       // $b1e3  
    jsr test_player_escaped_to_orbit            // $b1e6  
    bcs tick_loop_test_end                      // $b1e9  
    lda pod_destroying_player_timer             // $b1eb  
    bpl tick_loop_test_end                      // $b1ed  
    ldy #$03                                    // $b1ef  
    jsr wait_time_out_Y                         // $b1f1  
    jsr update_and_draw_all_objects             // $b1f4  
    jsr sprite_bands_build                      // $b1f7  
    jsr sprite_list_clear                       // $b1fa  
    jsr player_teleport_disappear               // $b1fd  
    ldy #$14                                    // $b200  
    jsr wait_time_out_Y                         // $b202  
    jsr show_landscape                          // $b205  
    lda demo_mode_flag                          // $b208  
    bne go_to_high_score                        // $b20a  
    lda fuel_empty_flag                         // $b20c  
    bne player_out_of_fuel                      // $b20f  
    lda pod_attached_flag_1                     // $b211  
    bne player_completed_mission                // $b213  
    lda planet_countdown_timer                  // $b215  
    bmi player_died_collision                   // $b217  
player_died_countdown:
    jsr clear_screen_and_sprites                // $b219  
    jsr show_landscape                          // $b21c  
    lda #$08                                    // $b21f  
    sta planet_destroyed_hostile_gun_modifier   // $b221  
    jsr set_text_screen_colours                 // $b224  
    jsr write_planet_destroyed                  // $b227  
    jsr write_mission                           // $b22a  
    lda #$20                                    // $b22d  
    jsr plot_char_A                             // $b22f  
    lda mission_number                          // $b232  
    jsr write_decimal_A                         // $b235  
    lda #$20                                    // $b238  
    jsr plot_char_A                             // $b23a  
    jsr plot_char_A                             // $b23d  
    jsr write_failed                            // $b240  
    jsr write_no_bonus                          // $b243  
    ldy #$78                                    // $b246  
    jsr wait_time_out_Y                         // $b248  
    jmp start_new_level                         // $b24b  
tick_loop_test_end:
    jmp test_level_ended_else_tick_loop         // $b24e  
player_out_of_fuel:
    jmp game_over                               // $b251  
go_to_high_score:
    jmp high_score_start                        // $b254  
player_died_collision:
    jsr clear_screen_and_sprites                // $b257  
    jsr set_text_screen_colours                 // $b25a  
    jsr write_mission                           // $b25d  
    jsr write_in                                // $b260  
    jsr write_complete                          // $b263  
    ldy #$3c                                    // $b266  
    jsr wait_time_out_Y                         // $b268  
    jmp level_retry                             // $b26b  
player_completed_mission:
    jsr mission_complete                        // $b26e  
    jmp start_new_level                         // $b271  
jump_tick_loop:
    jmp tick_loop_continue                      // $b274  
test_level_ended_else_tick_loop:
    ldx #KEY_RUN_STOP                           // $b277  
    jsr test_inkey                              // $b279  
    beq key_was_pressed                         // $b27c  
    lda demo_mode_flag                          // $b27e  
    beq skip_test_for_keypress                  // $b280  
    ldx #KEY_SPACE                              // $b282  
    jsr test_key                                // $b284  
    beq key_was_pressed                         // $b287  
skip_test_for_keypress:
    inc level_tick_counter                      // $b289  
    lda level_ended_flag                        // $b28b  
    beq jump_tick_loop                          // $b28d  
    lda demo_mode_flag                          // $b28f  
    bne go_to_high_score                        // $b291  
    lda fuel_empty_flag                         // $b293  
    bne game_over                               // $b296  
    jsr lose_a_life                             // $b298  
    cpx #$ff                                    // $b29b  
    beq game_over                               // $b29d  
    lda planet_countdown_timer                  // $b29f  
    bmi jump_to_retry_level                     // $b2a1  
    jmp player_died_countdown                   // $b2a3  
jump_to_retry_level:
    jmp level_retry                             // $b2a6  
game_over:
    jsr clear_screen_and_sprites                // $b2a9  
    jsr set_text_screen_colours                 // $b2ac  
    jsr show_landscape                          // $b2af  
    lda fuel_empty_flag                         // $b2b2  
    beq show_game_over_message                  // $b2b5  
    jsr write_out_of_fuel                       // $b2b7  
show_game_over_message:
    jsr write_game_over                         // $b2ba  
    ldy #$5a                                    // $b2bd  
    jsr wait_time_out_Y                         // $b2bf  
    jmp player_new_high_score                   // $b2c2  
key_was_pressed:
    jmp high_score_start                        // $b2c5  
update_player_and_pod_states:
    lda #$00                                    // $b2c8  
    sta level_ended_flag                        // $b2ca  
    lda pod_attached_flag_1                     // $b2cc  
    bne Lb2d6                                   // $b2ce  
    lda ship_sprite_plotted_flag                // $b2d0  
    bne Lb2d6                                   // $b2d2  
    sta pod_line_exists_flag                    // $b2d4  
Lb2d6:
    lda pod_destroying_player_timer             // $b2d6  
    bmi Lb2fd                                   // $b2d8  
    lda planet_countdown_timer                  // $b2da  
    beq planet_countdown_at_zero                // $b2dc  
planet_countdown_at_zero:
    dec pod_destroying_player_timer             // $b2de  
    beq set_level_ended                         // $b2e0  
    lda pod_destroying_player_timer             // $b2e2  
    cmp #$28                                    // $b2e4  
    bne Lb2ef                                   // $b2e6  
    lda #$00                                    // $b2e8  
    ldy #$00                                    // $b2ea  
    jsr palette_set_colour_Y_to_A               // $b2ec  
Lb2ef:
    dec tether_length                           // $b2ef  
    dec tether_length                           // $b2f1  
    bpl Lb2fd                                   // $b2f3  
    lda player_ship_destroyed_flag              // $b2f5  
    bmi destroy_player_ship                     // $b2f7  
    lda pod_attached_flag_1                     // $b2f9  
    bne destroy_attached_pod                    // $b2fb  
Lb2fd:
    lda player_ship_destroyed_flag              // $b2fd  
    bpl Lb30c                                   // $b2ff  
    lda pod_attached_flag_1                     // $b301  
    beq Lb30c                                   // $b303  
    lda #$01                                    // $b305  
    sta pod_line_exists_flag                    // $b307  
    jmp Lb314                                   // $b309  
Lb30c:
    lda pod_destroying_player_timer             // $b30c  
    bpl Lb314                                   // $b30e  
    lda #$00                                    // $b310  
    sta pod_line_exists_flag                    // $b312  
Lb314:
    lda plot_pod_collision_detected             // $b314  
    bne destroy_attached_pod                    // $b316  
    lda plot_ship_collision_detected            // $b318  
    bne destroy_player_ship                     // $b31a  
    jsr calculate_pod_pos                       // $b31c  
    rts                                         // $b31f  
set_level_ended:
    lda #$ff                                    // $b320  
    sta level_ended_flag                        // $b322  
    rts                                         // $b324  
destroy_player_ship:
    ldx #$01                                    // $b325  
    stx level_tick_state                        // $b327  
    lda player_ship_destroyed_flag              // $b329  
    bpl destroy_player_ship_return              // $b32b  
    lda #POD_DESTROY_TIMER_INIT                 // $b32d  
    sta pod_destroying_player_timer             // $b32f  
    lda #$00                                    // $b331  
    sta plot_ship_collision_detected            // $b333  
    lda #$01                                    // $b335  
    sta player_ship_destroyed_flag              // $b337  
    lda old_player_xpos_FRAC                    // $b339  
    sta explosion_xpos_FRAC                     // $b33b  
    clc                                         // $b33d  
    lda old_player_xpos_INT                     // $b33e  
    adc #PLAYER_CENTRE_X_OFFSET                 // $b340  to centre of player object?
    sta explosion_xpos_INT                      // $b342  
    clc                                         // $b344  
    lda old_player_ypos_INT                     // $b345  
    adc #PLAYER_CENTRE_Y_OFFSET                 // $b347  to centre of player object?
    sta explosion_ypos_INT                      // $b349  
    lda old_player_ypos_INT_HI                  // $b34b  
    adc #$00                                    // $b34d  
    sta explosion_ypos_INT_HI                   // $b34f  
    lda #$01                                    // $b351  
    sta explosion_angle                         // $b353  
    sta explosion_particle_type                 // $b355  
    jsr create_explosion                        // $b357  
destroy_player_ship_return:
    rts                                         // $b35a  
destroy_attached_pod:
    ldx #$01                                    // $b35b  
    stx level_tick_state                        // $b35d  
    dex                                         // $b35f  
    stx pod_attached_flag_1                     // $b360  
    stx plot_pod_collision_detected             // $b362  
    lda #POD_DESTROY_TIMER_INIT                 // $b364  
    sta pod_destroying_player_timer             // $b366  
    jsr calculate_pod_pos                       // $b368  
    lda pod_xpos_FRAC                           // $b36b  
    sta explosion_xpos_FRAC                     // $b36d  
    lda pod_xpos_INT                            // $b36f  
    sta explosion_xpos_INT                      // $b371  
    lda pod_ypos_FRAC                           // $b373  
    sta explosion_ypos_INT                      // $b375  
    lda pod_ypos_INT_HI                         // $b377  
    sta explosion_ypos_INT_HI                   // $b379  
    lda #$01                                    // $b37b  
    sta explosion_angle                         // $b37d  
    sta explosion_particle_type                 // $b37f  
    jsr create_explosion                        // $b381  
    rts                                         // $b384  
calculate_pod_pos:
    sec                                         // $b385  
    lda midpoint_xpos_FRAC                      // $b386  
    sbc midpoint_deltax_FRAC                    // $b388  
    sta pod_xpos_FRAC                           // $b38a  
    lda midpoint_xpos_INT                       // $b38c  
    sbc midpoint_deltax_INT                     // $b38e  
    clc                                         // $b390  
    adc #$04                                    // $b391  
    sta pod_xpos_INT                            // $b393  
    sec                                         // $b395  
    lda midpoint_ypos_INT                       // $b396  
    sbc midpoint_deltay_INT                     // $b398  
    sta pod_ypos_FRAC                           // $b39a  
    lda midpoint_ypos_INT_HI                    // $b39c  
    sbc #$00                                    // $b39e  
    sta pod_ypos_INT_HI                         // $b3a0  
    lda midpoint_deltay_INT                     // $b3a2  
    bpl Lb3a8                                   // $b3a4  
    inc pod_ypos_INT_HI                         // $b3a6  
Lb3a8:
    clc                                         // $b3a8  
    lda pod_ypos_FRAC                           // $b3a9  
    adc #$05                                    // $b3ab  
    sta pod_ypos_FRAC                           // $b3ad  
    lda pod_ypos_INT_HI                         // $b3af  
    adc #$00                                    // $b3b1  
    sta pod_ypos_INT_HI                         // $b3b3  
    rts                                         // $b3b5  
hide_landscape:
    lda planet_countdown_timer                  // $b3b6  
    beq set_landscape_colour_to_black           // $b3b8  
    lda pod_destroying_player_timer             // $b3ba  
    bpl show_landscape                          // $b3bc  
    lda invisible_landscape_flag                // $b3be  
    beq show_landscape                          // $b3c0  
    lda shield_tractor_pressed                  // $b3c2  
    beq set_landscape_colour_to_black           // $b3c4  
    jmp show_landscape                          // $b3c6  
set_landscape_colour_to_black:
    lda #$00                                    // $b3c9  
    sta landscape_visible_flag                  // $b3cb  
    rts                                         // $b3ce  
show_landscape:
    lda #$ff                                    // $b3cf  
    sta landscape_visible_flag                  // $b3d1  
    rts                                         // $b3d4  
test_player_escaped_to_orbit:
    lda midpoint_ypos_INT_HI                    // $b3d5  
    cmp #$01                                    // $b3d7  
    bne Lb3e1                                   // $b3d9  
    lda midpoint_ypos_INT                       // $b3db  
    cmp #$20                                    // $b3dd  
    bcc Lb3e3                                   // $b3df  
Lb3e1:
    sec                                         // $b3e1  
    rts                                         // $b3e2  
Lb3e3:
    clc                                         // $b3e3  
    rts                                         // $b3e4  
escape_pressed:
    jmp key_was_pressed                         // $b3e5  
wait_time_out_Y:
    sty wait_frames                             // $b3e8  
wait_loop:
    cmp vsync_count                             // $b3ea  
    beq wait_loop                               // $b3ec  
    ldx #KEY_RUN_STOP                           // $b3ee  
    jsr test_inkey                              // $b3f0  
    beq escape_pressed                          // $b3f3  
    lda vsync_count                             // $b3f5  
    dec wait_frames                             // $b3f7  
    bne wait_loop                               // $b3f9  
    jmp reset_game_tick                         // $b3fb  
clear_screen_and_sprites:
    lda #$00                                    // $b3fe  
    sta VIC_SPR_ENABLE                          // $b400  
    sta ship_spr_enable                         // $b403  
    sta pod_spr_enable                          // $b406  
    sta playfield_bg_colour                     // $b409  
    jsr sprite_list_clear                       // $b40c  
    jsr sprite_bands_build                      // $b40f  
clear_screen_and_init:
    lda #$00                                    // $b412  
    ldy #$00                                    // $b414  
    jsr palette_set_colour_Y_to_A               // $b416  
    lda #$20                                    // $b419  
    jsr write_countdown_timer                   // $b41b  
    ldx #$09                                    // $b41e  
Lb420:
    lda #$00                                    // $b420  
    sta terrain_draw_table_1,x                  // $b422  
    lda #$50                                    // $b425  
    sta terrain_draw_table_3,x                  // $b427  
    inx                                         // $b42a  
    bpl Lb420                                   // $b42b  
    ldx #LEVEL_MAX_OBJECTS                      // $b42d  max number of objects
Lb42f:
    lda level_obj_flags,x                       // $b42f  
    and #$fe                                    // $b432  
    sta level_obj_flags,x                       // $b434  
    dex                                         // $b437  
    bpl Lb42f                                   // $b438  
    ldx #$20                                    // $b43a  
Lb43c:
    lda #$00                                    // $b43c  
    sta particles_lifetime,x                    // $b43e  
    dex                                         // $b441  
    bpl Lb43c                                   // $b442  
    lda #$00                                    // $b444  
    sta clear_screen_ptr                        // $b446  
    lda #$62                                    // $b448  
    sta clear_screen_ptr+1                      // $b44a  
    ldy #$80                                    // $b44c  
    lda #$00                                    // $b44e  
clear_screen_loop:
    sta (clear_screen_ptr),y                    // $b450  
    iny                                         // $b452  
    bne clear_screen_loop                       // $b453  
    inc clear_screen_ptr+1                      // $b455  
    bpl clear_screen_loop                       // $b457  
    rts                                         // $b459  
wait_game_tick:
    lda game_tick_timer                         // $b45a  wait until the CIA timer IRQ counted 3 ticks
    bpl wait_game_tick                          // $b45d  
    clc                                         // $b45f  
    adc #$03                                    // $b460  
    bcs wait_game_tick_store                    // $b462  
    lda #$00                                    // $b464  
wait_game_tick_store:
    sta game_tick_timer                         // $b466  
    rts                                         // $b469  
reset_game_tick:
    lda #$03                                    // $b46a  restart the tick counter
    sta game_tick_timer                         // $b46c  
    rts                                         // $b46f  
draw_player_timed_to_vsync:
    jsr plot_ship_and_pod                       // $b470  
    jsr update_pod_tractor_beam                 // $b473  
    jmp draw_fuel_beam                          // $b476  
game_tick_timer:
    .byte $00                                   // $b479  
unused_b47a:
    .byte $00,$00,$00,$00,$00,$00               // $b47a  
test_key:
    php                                         // $b480  test real keyboard only
    jmp test_key_matrix                         // $b481  
test_inkey:
    php                                         // $b484  test key X (matrix index row*8+col)
    cpx #$3f                                    // $b485  RUN/STOP is never faked
    beq test_key_matrix                         // $b487  
    lda demo_mode_flag                          // $b489  demo mode: keys come from the demo tables
    bne demo_fake_keypress                      // $b48b  
test_key_matrix:
    txa                                         // $b48d  
    pha                                         // $b48e  
    and #$07                                    // $b48f  
    tay                                         // $b491  
    pla                                         // $b492  
    ror                                         // $b493  
    ror                                         // $b494  
    ror                                         // $b495  
    and #$07                                    // $b496  
    tax                                         // $b498  
    lda bit_table,y                             // $b499  
    and key_matrix,x                            // $b49c  
    beq test_key_not_pressed                    // $b49f  
    ldx #$ff                                    // $b4a1  
    plp                                         // $b4a3  
    cpx #$ff                                    // $b4a4  
    rts                                         // $b4a6  
test_key_not_pressed:
    ldx #$00                                    // $b4a7  
    plp                                         // $b4a9  
    cpx #$ff                                    // $b4aa  
    rts                                         // $b4ac  
demo_fake_keypress:
    plp                                         // $b4ad  
    txa                                         // $b4ae  
    ldx #$04                                    // $b4af  
Lb4b1:
    cmp demo_inkey_table,x                      // $b4b1  
    beq Lb4bc                                   // $b4b4  
    dex                                         // $b4b6  
    bpl Lb4b1                                   // $b4b7  
    inx                                         // $b4b9  
    beq demo_return_keypress_match              // $b4ba  
Lb4bc:
    lda lookup_index_to_bit,x                   // $b4bc  
    ldx #$00                                    // $b4bf  
    and demo_keypress_bit_mask                  // $b4c1  
    beq demo_return_keypress_match              // $b4c4  
    dex                                         // $b4c6  
demo_return_keypress_match:
    cpx #$ff                                    // $b4c7  
    rts                                         // $b4c9  
demo_inkey_table:
    .byte $0a,$0d,$01,$34,$3c                   // $b4ca  
lookup_index_to_bit:
    .byte $01,$02,$04,$08,$10                   // $b4cf  
demo_keypress_bit_mask:
    .byte $00                                   // $b4d4  
demo_keypress_timer:
    .byte $00                                   // $b4d5  
demo_keypress_index:
    .byte $00                                   // $b4d6  
demo_mode_tick:
    lda demo_mode_flag                          // $b4d7  
    beq demo_mode_tick_return                   // $b4d9  
    dec demo_keypress_timer                     // $b4db  
    bmi demo_mode_next_keypress                 // $b4de  
demo_mode_tick_return:
    rts                                         // $b4e0  
demo_mode_next_keypress:
    ldx demo_keypress_index                     // $b4e1  
    lda demo_keypress_bit_mask_table,x          // $b4e4  
    sta demo_keypress_bit_mask                  // $b4e7  
    lda demo_keypress_timer_table,x             // $b4ea  
    sta demo_keypress_timer                     // $b4ed  
    inc demo_keypress_index                     // $b4f0  
    rts                                         // $b4f3  
bit_table_2:
    .byte $01,$02,$04,$08,$10,$20,$40,$80       // $b4f4  
demo_keypress_bit_mask_table:
    .byte $00,$02,$00,$04,$01,$10,$18,$00,$01,$00,$18,$08,$0a,$08,$0a,$08  // $b4fc  
    .byte $0a,$08                               // $b50c  
demo_keypress_timer_table:
    .byte $18,$0f,$05,$05,$08,$14,$17,$0f       // $b50e  
demo_keypress_timer_rnd_A:
    .byte $08,$0d,$26,$0d                       // $b516  
demo_keypress_timer_rnd_B:
    .byte $06                                   // $b51a  
demo_keypress_timer_rnd_C:
    .byte $7f,$14,$0a,$0f,$7f                   // $b51b  
pod_attached_flag_2:
    .byte $00                                   // $b520  
check_high_score:
    jsr clear_screen_and_sprites                // $b521  
    jsr set_text_screen_colours                 // $b524  
enter_new_high_score_name:
    lda #$09                                    // $b527  
    sta high_score_counter                      // $b529  
    lda #$01                                    // $b52b  
    sta high_score_ptr_A+1                      // $b52d  
    sta high_score_ptr_B+1                      // $b52f  
    lda #$80                                    // $b531  
    sta high_score_ptr_A                        // $b533  
    lda #$70                                    // $b535  
    sta high_score_ptr_B                        // $b537  
Lb539:
    ldy #$02                                    // $b539  
Lb53b:
    lda (high_score_ptr_A),y                    // $b53b  
    cmp (high_score_ptr_B),y                    // $b53d  
    bcc Lb546                                   // $b53f  
    bne Lb54d                                   // $b541  
    dey                                         // $b543  
    bpl Lb53b                                   // $b544  
Lb546:
    lda high_score_ptr_A                        // $b546  
    cmp #$80                                    // $b548  
    bne Lb56a                                   // $b54a  
    rts                                         // $b54c  
Lb54d:
    dec high_score_counter                      // $b54d  
    ldy #$00                                    // $b54f  
Lb551:
    lda (high_score_ptr_A),y                    // $b551  
    pha                                         // $b553  
    lda (high_score_ptr_B),y                    // $b554  
    sta (high_score_ptr_A),y                    // $b556  
    pla                                         // $b558  
    sta (high_score_ptr_B),y                    // $b559  
    iny                                         // $b55b  
    cpy #$10                                    // $b55c  
    bne Lb551                                   // $b55e  
    lda high_score_ptr_B                        // $b560  
    sta high_score_ptr_A                        // $b562  
    sbc #$10                                    // $b564  
    sta high_score_ptr_B                        // $b566  
    bcs Lb539                                   // $b568  
Lb56a:
    clc                                         // $b56a  
    lda high_score_ptr_A                        // $b56b  
    adc #$06                                    // $b56d  
    sta high_score_ptr_C                        // $b56f  
    lda high_score_ptr_A+1                      // $b571  
    sta high_score_ptr_C_HI                     // $b573  
    jsr plot_high_score_table                   // $b575  
    jsr write_congratulations                   // $b578  
    jsr write_enter_name                        // $b57b  
    ldx #$e8                                    // $b57e  
    ldy #$66                                    // $b580  
    jsr plot_char_set_scr_addr_XY               // $b582  
    ldy high_score_counter                      // $b585  
Lb587:
    ldx #$28                                    // $b587  
Lb589:
    jsr char_write_ptr_next_column              // $b589  
    dex                                         // $b58c  
    bne Lb589                                   // $b58d  
    dey                                         // $b58f  
    bne Lb587                                   // $b590  
    lda #$ff                                    // $b592  
    sta char_flag_cursor                        // $b594  
    lda #$00                                    // $b597  
    jsr plot_char_A                             // $b599  
    jsr read_key_reset                          // $b59c  
    jsr calc_text_colour_ptr                    // $b59f  
    lda text_colour                             // $b5a2  
    rol                                         // $b5a5  
    rol                                         // $b5a6  
    rol                                         // $b5a7  
    rol                                         // $b5a8  
    and #$f0                                    // $b5a9  
    sta font_byte_mask                          // $b5ab  
    ldy #$0a                                    // $b5ae  
Lb5b0:
    sta (text_ptr),y                            // $b5b0  
    dey                                         // $b5b2  
    bpl Lb5b0                                   // $b5b3  
    ldy #$00                                    // $b5b5  
Lb5b7:
    jsr read_key_ascii                          // $b5b7  
    cmp #$0d                                    // $b5ba  
    beq Lb5e9                                   // $b5bc  
    cmp #$14                                    // $b5be  
    beq Lb5d7                                   // $b5c0  
    cmp #$20                                    // $b5c2  
    bcc Lb5b7                                   // $b5c4  
    cmp #$7f                                    // $b5c6  
    bcs Lb5b7                                   // $b5c8  
    cpy #$0a                                    // $b5ca  
    bcs Lb5b7                                   // $b5cc  
    sta (high_score_ptr_C),y                    // $b5ce  
    jsr plot_char_A                             // $b5d0  
    iny                                         // $b5d3  
    jmp Lb5b7                                   // $b5d4  
Lb5d7:
    cpy #$00                                    // $b5d7  
    beq Lb5b7                                   // $b5d9  
    lda #$7f                                    // $b5db  
    jsr plot_char_A                             // $b5dd  
    dey                                         // $b5e0  
    jmp Lb5b7                                   // $b5e1  
Lb5e4:
    lda #$20                                    // $b5e4  
    sta (high_score_ptr_C),y                    // $b5e6  
    iny                                         // $b5e8  
Lb5e9:
    cpy #$0a                                    // $b5e9  
    bne Lb5e4                                   // $b5eb  
    lda #$0f                                    // $b5ed  
    sta font_byte_mask                          // $b5ef  
    lda #$00                                    // $b5f2  
    sta char_flag_cursor                        // $b5f4  
enter_name_done:
    jmp clear_screen_and_sprites                // $b5f7  
unused_plot_char:
    jmp plot_char_A                             // $b5fa  address gets written into code in main_entry
    .byte $60                                   // $b5fd  
write_decimal_A:
    pha                                         // $b5fe  
    ror                                         // $b5ff  
    ror                                         // $b600  
    ror                                         // $b601  
    ror                                         // $b602  
    and #$0f                                    // $b603  
    beq Lb60d                                   // $b605  
    clc                                         // $b607  
    adc #$30                                    // $b608  
    jsr plot_char_A                             // $b60a  
Lb60d:
    pla                                         // $b60d  
    and #$0f                                    // $b60e  
    clc                                         // $b610  
    adc #$30                                    // $b611  
    jmp plot_char_A                             // $b613  
mission_complete:
    lda #$00                                    // $b616  
    sta level_modifier_flag                     // $b618  
    jsr clear_screen_and_sprites                // $b61b  
    jsr set_text_screen_colours                 // $b61e  
    jsr write_mission                           // $b621  
    ldx #$18                                    // $b624  
    ldy #$6d                                    // $b626  
    jsr plot_char_set_scr_addr_XY               // $b628  
    lda mission_number                          // $b62b  
    jsr write_decimal_A                         // $b62e  
    lda #$20                                    // $b631  
    jsr plot_char_A                             // $b633  
    jsr write_complete                          // $b636  
    sed                                         // $b639  
    clc                                         // $b63a  
    cld                                         // $b63b  
    lda #$00                                    // $b63c  
    sta bonus_score                             // $b63e  
    lda level_number                            // $b641  
    clc                                         // $b644  
    adc #$05                                    // $b645  
    ldy planet_countdown_timer                  // $b647  
    bmi Lb653                                   // $b649  
    pha                                         // $b64b  
    jsr write_planet_destroyed                  // $b64c  
    pla                                         // $b64f  
    clc                                         // $b650  
    adc #$05                                    // $b651  
Lb653:
    tay                                         // $b653  
Lb654:
    tya                                         // $b654  
    pha                                         // $b655  
    lda #$40                                    // $b656  
    jsr add_A_to_score                          // $b658  
    lda bonus_score                             // $b65b  
    sed                                         // $b65e  
    adc #$04                                    // $b65f  
    sta bonus_score                             // $b661  
    cld                                         // $b664  
    pla                                         // $b665  
    tay                                         // $b666  
    dey                                         // $b667  
    bne Lb654                                   // $b668  
    jsr write_bonus                             // $b66a  
    lda bonus_score                             // $b66d  
    jsr write_decimal_A                         // $b670  
    lda #$30                                    // $b673  
    jsr plot_char_A                             // $b675  
    jsr plot_char_A                             // $b678  
    ldy #$64                                    // $b67b  
    jmp wait_time_out_Y                         // $b67d  jump to entry
bonus_score:
    .byte $00                                   // $b680  
mission_number:
    .byte $00                                   // $b681  
level_modifier_flag:
    .byte $00                                   // $b682  
init:
    lda #<gfx_load                              // $b683  copy graphics: $6C55 (load address) -> $4000, 13 pages
    sta boot_read_ptr                           // $b685  
    lda #>gfx_load                              // $b687  
    sta value_HI                                // $b689  
    lda #<sprite_data                           // $b68b  
    sta gfx_copy_dst_ptr                        // $b68d  
    lda #>sprite_data                           // $b68f  
    sta gfx_copy_dst_ptr+1                      // $b691  
    ldx #(filler2_load - gfx_load) >> 8         // $b693  number of pages ($0D)
Lb695:
    ldy #$00                                    // $b695  
Lb697:
    lda (boot_read_ptr),y                       // $b697  
    sta (gfx_copy_dst_ptr),y                    // $b699  
    iny                                         // $b69b  
    bne Lb697                                   // $b69c  
    inc value_HI                                // $b69e  
    inc gfx_copy_dst_ptr+1                      // $b6a0  
    dex                                         // $b6a2  
    bne Lb695                                   // $b6a3  
init_clear:
    ldx #$ff                                    // $b6a5  
    txs                                         // $b6a7  reset stack
    ldx #$fd                                    // $b6a8  clear zero page $03-$FF
zp_loop:
    lda #$00                                    // $b6aa  
    sta planet_explode_anim,x                   // $b6ac  
    dex                                         // $b6ae  
    bne zp_loop                                 // $b6af  reset first $A7 entries of zero page to 0
    ldy #$4f                                    // $b6b1  build the column -> bitmap byte tables (80 columns, 4 pixels each)
    ldx #$00                                    // $b6b3  
    lda #$00                                    // $b6b5  index into multiplication table arrays
    sta value_LO                                // $b6b7  
    sta value_HI                                // $b6b9  
mult_by_8_loop:
    lda value_LO                                // $b6bb  
    sta column_bitmap_offset_LO,x               // $b6bd  two columns per bitmap byte
    sta column_bitmap_offset_LO+1,x             // $b6c0  
    lda value_HI                                // $b6c3  
    sta column_bitmap_offset_HI,x               // $b6c5  
    sta column_bitmap_offset_HI+1,x             // $b6c8  
    lda #$a0                                    // $b6cb  left half pixels
    sta column_pixel_byte,x                     // $b6cd  
    lda #$0a                                    // $b6d0  right half pixels
    sta column_pixel_byte+1,x                   // $b6d2  store high byte at $A10
    clc                                         // $b6d5  
    lda value_LO                                // $b6d6  
    adc #$08                                    // $b6d8  
    sta value_LO                                // $b6da  
    lda value_HI                                // $b6dc  
    adc #$00                                    // $b6de  
    sta value_HI                                // $b6e0  add 8 to 16-bit number stored at $70
    inx                                         // $b6e2  
    inx                                         // $b6e3  
    dey                                         // $b6e4  
    dey                                         // $b6e5  
    bpl mult_by_8_loop                          // $b6e6  
    ldx #$1f                                    // $b6e8  copy the angle -> vector tables
store_32_bytes_loop:
    lda lookup_angle_to_y_FRAC,x                // $b6ea  
    sta angle_to_y_FRAC,x                       // $b6ed  
    lda lookup_angle_to_y_INT,x                 // $b6f0  
    sta angle_to_y_INT,x                        // $b6f3  
    lda lookup_angle_to_x_FRAC,x                // $b6f6  
    sta angle_to_x_FRAC,x                       // $b6f9  
    lda lookup_angle_to_x_INT,x                 // $b6fc  
    sta angle_to_x_INT,x                        // $b6ff  
    dex                                         // $b702  
    bpl store_32_bytes_loop                     // $b703  loop 32 times
    ldx #$0b                                    // $b705  copy raster interrupt table
Lb707:
    lda raster_table_load+RELOC_OFFSET,x        // $b707  
    sta raster_table,x                          // $b70a  
    dex                                         // $b70d  
    bpl Lb707                                   // $b70e  
    jmp init_copy_low                           // $b710  
}

// ============================================================================
// raster_table  (load $6493-$6498, runtime $0e00-$0e05)
// Raster interrupt table - copied to $0E00 at init
// (the copy loop moves 12 bytes; the last 6 are the code that follows)
// ============================================================================
raster_table_load:
.pseudopc $0e00 {
raster_table:
    .byte $31,$02,$00                           // $0e00  
    .byte $3f,$03,$00                           // $0e03  
}

// ============================================================================
// main2  (load $6499-$6500, runtime $b719-$b780)
// ============================================================================
main2_load:
.pseudopc main2_load + RELOC_OFFSET {
init_copy_low:
    lda #<(init_low_load+RELOC_OFFSET)          // $b719  copy init_low ($0400-$06FF) and run it
    sta relocate_src_ptr                        // $b71b  
    lda #>(init_low_load+RELOC_OFFSET)          // $b71d  
    sta relocate_src_ptr+1                      // $b71f  
    lda #<init2                                 // $b721  
    sta relocate_dest_ptr                       // $b723  
    lda #>init2                                 // $b725  
    sta relocate_dest_ptr+1                     // $b727  
    ldy #$00                                    // $b729  
    ldx #$03                                    // $b72b  
Lb72d:
    lda (relocate_src_ptr),y                    // $b72d  
    sta (relocate_dest_ptr),y                   // $b72f  
    iny                                         // $b731  
    bne Lb72d                                   // $b732  
    inc relocate_src_ptr+1                      // $b734  
    inc relocate_dest_ptr+1                     // $b736  
    dex                                         // $b738  
    bne Lb72d                                   // $b739  
    ldx #$00                                    // $b73b  high score table -> $0100
store_at_0100_loop:
    lda high_score_table_relocated,x            // $b73d  
    sta high_score_table,x                      // $b740  
    inx                                         // $b743  
    bpl store_at_0100_loop                      // $b744  store 128 bytes at $0100
    ldx #$7d                                    // $b746  in-game messages -> $0900
store_at_0900_loop:
    lda in_game_messages_relocated,x            // $b748  
    sta msg_game_over,x                         // $b74b  
    dex                                         // $b74e  
    bpl store_at_0900_loop                      // $b74f  
    lda #$04                                    // $b751  
    sta level_hostile_gun_probability           // $b753  
    jmp init2                                   // $b756  
unused_bbc_instructions:
    lda #<bbc_instructions_text                 // $b759  
    sta relocate_src_ptr                        // $b75b  
    lda #>bbc_instructions_text                 // $b75d  
    sta relocate_src_ptr+1                      // $b75f  
    ldy #$00                                    // $b761  
write_chars_loop:
    lda (relocate_src_ptr),y                    // $b763  
    cmp #$ff                                    // $b765  stop when hitting $FF
    beq wait_for_spacebar                       // $b767  
    jsr CHROUT                                  // $b769  write char
    iny                                         // $b76c  
    bne write_chars_loop                        // $b76d  
    inc relocate_src_ptr+1                      // $b76f  
    jmp write_chars_loop                        // $b771  write chars until reach $FF
wait_for_spacebar:
    jsr read_key_reset                          // $b774  *FX 15,0 - flush all buffers
    jsr read_key_ascii                          // $b777  wait for keypress
    cmp #$20                                    // $b77a  32 = space bar
    bne wait_for_spacebar                       // $b77c  wait until spacebar is pressed
    jmp init2                                   // $b77e  jump to game start at $0400
}

// ============================================================================
// init_low  (load $6501-$65f4, runtime $0400-$04f3)
// Second stage init - copied to $0400 and run from there
// ============================================================================
init_low_load:
.pseudopc $0400 {
init2:
    lda #$00                                    // $0400  VIC: sprites off and at 0,0
    ldy #$0f                                    // $0402  
L0404:
    sta VIC_SPR0_X,y                            // $0404  
    dey                                         // $0407  
    bpl L0404                                   // $0408  
    lda #$ff                                    // $040a  all sprites enabled
    sta VIC_SPR_ENABLE                          // $040c  MODIFIES CODE
    lda #$00                                    // $040f  
    sta VIC_SPR_EXPAND_Y                        // $0411  MODIFIES CODE
    sta VIC_SPR_EXPAND_X                        // $0414  
    lda #$03                                    // $0417  VIC bank 1 ($4000-$7FFF)
    sta CIA2_DDRA                               // $0419  
    lda CIA2_PRA                                // $041c  
    and #$fc                                    // $041f  
    ora #$02                                    // $0421  
    sta CIA2_PRA                                // $0423  
    lda #$00                                    // $0426  black border
    sta VIC_BORDER                              // $0428  
    lda VIC_CTRL1                               // $042b  bitmap mode, display off
    ora #$20                                    // $042e  
    and #$ef                                    // $0430  
    sta VIC_CTRL1                               // $0432  
    lda VIC_CTRL2                               // $0435  multicolour
    ora #$10                                    // $0438  
    sta VIC_CTRL2                               // $043a  
    lda #$70                                    // $043d  screen $5C00, bitmap $6000
    ora #$08                                    // $043f  
    sta VIC_MEMSETUP                            // $0441  
    lda #$00                                    // $0444  
    sta VIC_BG0                                 // $0446  
    sta level_number                            // $0449  level 0
    jsr set_level_colours                       // $044c  level colours
    lda #<status_charset_data                   // $044f  status bar charset -> $5800 and $6000
    sta copy_src_ptr                            // $0451  
    lda #>status_charset_data                   // $0453  
    sta copy_src_ptr+1                          // $0455  
    lda #$00                                    // $0457  
    sta copy_dst_ptr                            // $0459  
    lda #$58                                    // $045b  
    sta copy_dst_ptr+1                          // $045d  
    lda #$00                                    // $045f  
    sta copy_dst2_ptr                           // $0461  
    lda #$60                                    // $0463  
    sta copy_dst2_ptr+1                         // $0465  
    ldy #$00                                    // $0467  
    ldx #$03                                    // $0469  
L046b:
    lda (copy_src_ptr),y                        // $046b  
    sta (copy_dst_ptr),y                        // $046d  
    sta (copy_dst2_ptr),y                       // $046f  
    iny                                         // $0471  
    bne L046b                                   // $0472  
    inc copy_src_ptr+1                          // $0474  
    inc copy_dst_ptr+1                          // $0476  
    inc copy_dst2_ptr+1                         // $0478  
    dex                                         // $047a  
    bne L046b                                   // $047b  
    jsr clear_screen_and_sprites                // $047d  clear screen
    jsr sprite_list_clear                       // $0480  
    jsr sprite_bands_build                      // $0483  
    jsr sprite_bands_commit                     // $0486  
init2_irq:
    lda CINV                                    // $0489  save the KERNAL IRQ vector
    sta old_irq_vector                          // $048c  
    lda CINV_HI                                 // $048f  
    sta $08c1                                   // $0492  
    sei                                         // $0495  
    lda #<irq_handler                           // $0496  install irq_handler (IRQ and BRK)
    sta CINV                                    // $0498  
    sta CBINV                                   // $049b  
    lda #>irq_handler                           // $049e  
    sta CINV_HI                                 // $04a0  
    sta CBINV_HI                                // $04a3  
    lda #$00                                    // $04a6  first raster interrupt at line 0
    sta VIC_RASTER                              // $04a8  
    lda VIC_CTRL1                               // $04ab  
    and #$7f                                    // $04ae  
    sta VIC_CTRL1                               // $04b0  
    lda #$01                                    // $04b3  enable raster interrupt
    sta VIC_IRQ_ENABLE                          // $04b5  
    lda #$00                                    // $04b8  CIA 1 timer A: $276A cycles (~97 Hz game tick)
    sta CIA1_CRA                                // $04ba  
    lda #$6a                                    // $04bd  
    sta CIA1_TA_LO                              // $04bf  
    lda #$27                                    // $04c2  
    sta CIA1_TA_HI                              // $04c4  
    lda #$81                                    // $04c7  
    sta CIA1_ICR                                // $04c9  
    lda #$01                                    // $04cc  
    sta CIA1_CRA                                // $04ce  
    lda #$7e                                    // $04d1  disable other CIA interrupts
    sta CIA1_ICR                                // $04d3  
    lda #$7f                                    // $04d6  
    sta CIA2_ICR                                // $04d8  
    cli                                         // $04db  enable interrupts
init2_sid:
    ldy #$14                                    // $04dc  silence the SID
    lda #$00                                    // $04de  
init2_sid_loop:
    sta SID_V1_FREQ_LO,y                        // $04e0  
    dey                                         // $04e3  
    bpl init2_sid_loop                          // $04e4  
    sta SID_RES_FILT                            // $04e6  
    lda #$0f                                    // $04e9  volume 15
    sta sfx_volume                              // $04eb  
    sta SID_MODE_VOL                            // $04ee  
    jmp game_start                              // $04f1  start
}

// ============================================================================
// hiscore_init  (load $65f5-$6674, runtime $0100-$017f)
// High score table - copied to $0100 at init
// ============================================================================
hiscore_init_load:
.pseudopc $0100 {
high_score_table:
    .byte $00,$08,$00,$20,$20,$20,$46,$69,$72,$65,$62,$69,$72,$64,$20,$20  // $0100  "...   Firebird  "
    .byte $00,$07,$00,$20,$20,$20,$46,$69,$72,$65,$62,$69,$72,$64,$20,$20  // $0110  "...   Firebird  "
    .byte $00,$06,$00,$20,$20,$20,$46,$69,$72,$65,$62,$69,$72,$64,$20,$20  // $0120  "...   Firebird  "
    .byte $00,$05,$00,$20,$20,$20,$46,$69,$72,$65,$62,$69,$72,$64,$20,$20  // $0130  "...   Firebird  "
    .byte $00,$04,$00,$20,$20,$20,$46,$69,$72,$65,$62,$69,$72,$64,$20,$20  // $0140  "...   Firebird  "
    .byte $00,$03,$00,$20,$20,$20,$46,$69,$72,$65,$62,$69,$72,$64,$20,$20  // $0150  "...   Firebird  "
    .byte $00,$02,$00,$20,$20,$20,$46,$69,$72,$65,$62,$69,$72,$64,$20,$20  // $0160  "...   Firebird  "
    .byte $00,$01,$00,$20,$20,$20,$46,$69,$72,$65,$62,$69,$72,$64,$20,$20  // $0170  "...   Firebird  "
}

// ============================================================================
// tab_0880  (load $6675-$6694, runtime $0880-$089f)
// Table copied to $0880
// ============================================================================
tab_0880_load:
.pseudopc $0880 {
angle_to_y_FRAC:
    .byte $80,$8d,$b1,$ec,$3c,$9d,$0c,$84,$00,$7c,$f4,$63,$c4,$14,$4f,$73  // $0880  
    .byte $80,$73,$4f,$14,$c4,$63,$f4,$7c,$00,$84,$0c,$9d,$3c,$ec,$b1,$8d  // $0890  
}

// ============================================================================
// tab_08a0  (load $6695-$66b4, runtime $08a0-$08bf)
// Table copied to $08A0
// ============================================================================
tab_08a0_load:
.pseudopc $08a0 {
angle_to_y_INT:
    .byte $fd,$fd,$fd,$fd,$fe,$fe,$ff,$ff,$00,$00,$00,$01,$01,$02,$02,$02  // $08a0  
    .byte $02,$02,$02,$02,$01,$01,$00,$00,$00,$ff,$ff,$fe,$fe,$fd,$fd,$fd  // $08b0  
}

// ============================================================================
// tab_0980  (load $66b5-$66d4, runtime $0980-$099f)
// Table copied to $0980
// ============================================================================
tab_0980_load:
.pseudopc $0980 {
angle_to_x_FRAC:
    .byte $00,$3e,$7a,$b1,$e2,$0a,$27,$39,$40,$39,$27,$0a,$e2,$b1,$7a,$3e  // $0980  
    .byte $00,$c2,$86,$4f,$1e,$f6,$d9,$c7,$c0,$c7,$d9,$f6,$1e,$4f,$86,$c2  // $0990  
}

// ============================================================================
// tab_09a0  (load $66d5-$66f4, runtime $09a0-$09bf)
// Table copied to $09A0
// ============================================================================
tab_09a0_load:
.pseudopc $09a0 {
angle_to_x_INT:
    .byte $00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00  // $09a0  
    .byte $00,$ff,$ff,$ff,$ff,$fe,$fe,$fe,$fe,$fe,$fe,$fe,$ff,$ff,$ff,$ff  // $09b0  
}

// ============================================================================
// tab_0900  (load $66f5-$676a, runtime $0900-$0975)
// In-game messages copied to $0900
// (the copy loop moves 126 bytes; the last 8 belong to the text that follows)
// ============================================================================
tab_0900_load:
.pseudopc $0900 {
msg_game_over:
    .byte $38,$6e,$47,$61,$6d,$65,$20,$4f,$76,$65,$72,$ff  // $0900  "8nGame Over."
msg_top_eight_thrusters:
    .byte $50,$65,$54,$6f,$70,$20,$45,$69,$67,$68,$74,$20,$54,$68,$72,$75  // $090c  "PeTop Eight Thru"
    .byte $73,$74,$65,$72,$73,$ff               // $091c  "sters."
msg_congratulations:
    .byte $60,$65,$43,$6f,$6e,$67,$72,$61,$74,$75,$6c,$61,$74,$69,$6f,$6e  // $0922  "`eCongratulation"
    .byte $73,$ff                               // $0932  "s."
msg_enter_name:
    .byte $48,$74,$50,$6c,$65,$61,$73,$65,$20,$65,$6e,$74,$65,$72,$20,$79  // $0934  "HtPlease enter y"
    .byte $6f,$75,$72,$20,$6e,$61,$6d,$65,$ff   // $0944  "our name."
msg_press_space:
    .byte $b8,$76,$50,$72,$65,$73,$73,$20,$53,$50,$41,$43,$45,$20,$42,$41  // $094d  "..Press SPACE BA" (thrusty-levels: at $76b8 = row 18, was $7438 = row 16)
    .byte $52,$20,$74,$6f,$20,$73,$74,$61,$72,$74,$ff  // $095d  "R to start."
msg_out_of_fuel:
    .byte $b0,$6b,$4f,$75,$74,$20,$6f,$66,$20,$66,$75,$65,$6c,$ff  // $0968  ".kOut of fuel."
}

// ============================================================================
// main3  (load $676b-$6c23, runtime $b9eb-$bea3)
// ============================================================================
main3_load:
.pseudopc main3_load + RELOC_OFFSET {
bbc_instructions_text:
    .byte $16,$07,$84,$9d,$83,$8d,$20,$20,$20,$20,$20,$4a,$65,$72,$65,$6d  // $b9eb  "......     Jerem"
    .byte $79,$27,$73,$20,$54,$68,$72,$75,$73,$74,$65,$72,$20,$47,$61,$6d  // $b9fb  "y's Thruster Gam"
    .byte $65,$0a,$0d,$84,$9d,$83,$8d,$20,$20,$20,$20,$20,$4a,$65,$72,$65  // $ba0b  "e......     Jere"
    .byte $6d,$79,$27,$73,$20,$54,$68,$72,$75,$73,$74,$65,$72,$20,$47,$61  // $ba1b  "my's Thruster Ga"
    .byte $6d,$65,$0d,$0a,$0a,$0a,$83,$54,$68,$65,$20,$6b,$65,$79,$73,$20  // $ba2b  "me.....The keys "
    .byte $61,$72,$65,$3a,$0d,$0a,$0a,$0a,$85,$20,$20,$20,$20,$20,$20,$20  // $ba3b  "are:.....       "
    .byte $43,$41,$50,$53,$20,$4c,$4f,$43,$4b,$20,$20,$5f,$20,$20,$52,$6f  // $ba4b  "CAPS LOCK  _  Ro"
    .byte $74,$61,$74,$65,$20,$4c,$65,$66,$74,$0d,$0a,$85,$20,$20,$20,$20  // $ba5b  "tate Left...    "
    .byte $20,$20,$20,$20,$20,$20,$20,$20,$43,$54,$52,$4c,$20,$20,$5f,$20  // $ba6b  "        CTRL  _ "
    .byte $20,$52,$6f,$74,$61,$74,$65,$20,$52,$69,$67,$68,$74,$0d,$0a,$0a  // $ba7b  " Rotate Right..."
    .byte $82,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$52,$45,$54,$55,$52  // $ba8b  ".          RETUR"
    .byte $4e,$20,$20,$5f,$20,$20,$46,$69,$72,$65,$0d,$0a,$20,$20,$20,$82  // $ba9b  "N  _  Fire..   ."
    .byte $20,$20,$20,$20,$20,$20,$20,$20,$53,$48,$49,$46,$54,$20,$20,$5f  // $baab  "        SHIFT  _"
    .byte $20,$20,$54,$68,$72,$75,$73,$74,$0d,$0a,$0a,$83,$20,$20,$20,$20  // $babb  "  Thrust....    "
    .byte $20,$20,$20,$20,$20,$20,$20,$53,$50,$41,$43,$45,$20,$20,$5f,$20  // $bacb  "       SPACE  _ "
    .byte $20,$53,$68,$69,$65,$6c,$64,$2f,$54,$72,$61,$63,$74,$6f,$72,$0d  // $badb  " Shield/Tractor."
    .byte $0a,$0a,$0a,$81,$20,$20,$20,$20,$20,$43,$4f,$50,$59,$2c,$44,$45  // $baeb  "....     COPY,DE"
    .byte $4c,$45,$54,$45,$20,$20,$5f,$20,$20,$46,$72,$65,$65,$7a,$65,$2c  // $bafb  "LETE  _  Freeze,"
    .byte $55,$6e,$66,$72,$65,$65,$7a,$65,$0d,$0a,$81,$20,$20,$20,$20,$20  // $bb0b  "Unfreeze...     "
    .byte $20,$20,$20,$20,$20,$20,$20,$20,$51,$2c,$53,$20,$20,$5f,$20,$20  // $bb1b  "        Q,S  _  "
    .byte $51,$75,$69,$65,$74,$2c,$53,$6f,$75,$6e,$64,$0d,$0a,$81,$20,$20  // $bb2b  "Quiet,Sound...  "
    .byte $20,$20,$20,$20,$20,$20,$20,$20,$45,$53,$43,$41,$50,$45,$20,$20  // $bb3b  "        ESCAPE  "
    .byte $5f,$20,$20,$51,$75,$69,$74,$20,$67,$61,$6d,$65,$0d,$0a,$0a,$0a  // $bb4b  "_  Quit game...."
    .byte $86,$20,$43,$6f,$70,$79,$72,$69,$67,$68,$74,$20,$28,$43,$29,$20  // $bb5b  ". Copyright (C) "
    .byte $4a,$65,$72,$65,$6d,$79,$20,$43,$2e,$20,$53,$6d,$69,$74,$68,$20  // $bb6b  "Jeremy C. Smith "
    .byte $31,$39,$38,$35,$0d,$0a,$0a,$88,$20,$20,$20,$20,$50,$72,$65,$73  // $bb7b  "1985....    Pres"
    .byte $73,$20,$74,$68,$65,$20,$73,$70,$61,$63,$65,$20,$62,$61,$72,$20  // $bb8b  "s the space bar "
    .byte $74,$6f,$20,$73,$74,$61,$72,$74,$ff   // $bb9b  "to start."
status_charset_data:
    .byte $00,$d5,$c0,$ca,$c0,$ca,$c0,$c0       // $bba4  
    .byte $00,$55,$00,$aa,$00,$aa,$00,$00       // $bbac  
    .byte $00,$55,$00,$aa,$00,$aa,$00,$00       // $bbb4  
    .byte $00,$55,$00,$aa,$00,$aa,$00,$00       // $bbbc  
    .byte $00,$55,$00,$a8,$00,$a8,$00,$00       // $bbc4  
    .byte $00,$00,$fe,$c0,$fc,$c0,$c0,$00       // $bbcc  
    .byte $00,$00,$c6,$c6,$c6,$c6,$fe,$00       // $bbd4  
    .byte $00,$00,$fe,$c0,$fc,$c0,$fe,$00       // $bbdc  
    .byte $00,$00,$c0,$c0,$c0,$c0,$fe,$00       // $bbe4  
    .byte $00,$55,$00,$2a,$00,$2a,$00,$00       // $bbec  
    .byte $00,$55,$00,$aa,$00,$aa,$00,$00       // $bbf4  
    .byte $00,$55,$00,$aa,$00,$aa,$00,$00       // $bbfc  
    .byte $00,$55,$00,$aa,$00,$aa,$00,$00       // $bc04  
    .byte $00,$55,$00,$aa,$00,$aa,$00,$00       // $bc0c  
    .byte $00,$55,$00,$aa,$00,$aa,$00,$00       // $bc14  
    .byte $00,$55,$00,$aa,$00,$aa,$00,$00       // $bc1c  
    .byte $00,$55,$00,$a8,$00,$a8,$00,$00       // $bc24  
    .byte $00,$00,$c0,$c0,$c0,$c0,$fe,$00       // $bc2c  
    .byte $00,$00,$7e,$18,$18,$18,$7e,$00       // $bc34  
    .byte $00,$00,$c6,$c6,$cc,$d8,$f0,$00       // $bc3c  
    .byte $00,$00,$fe,$c0,$fc,$c0,$fe,$00       // $bc44  
    .byte $00,$00,$fc,$c0,$fe,$06,$fe,$00       // $bc4c  
    .byte $00,$55,$00,$2a,$00,$2a,$00,$00       // $bc54  
    .byte $00,$55,$00,$aa,$00,$aa,$00,$00       // $bc5c  
    .byte $00,$55,$00,$aa,$00,$aa,$00,$00       // $bc64  
    .byte $00,$55,$00,$aa,$00,$aa,$00,$00       // $bc6c  
    .byte $00,$55,$00,$aa,$00,$aa,$00,$00       // $bc74  
    .byte $00,$55,$00,$aa,$00,$aa,$00,$00       // $bc7c  
    .byte $00,$55,$00,$aa,$00,$aa,$00,$00       // $bc84  
    .byte $00,$55,$00,$a8,$00,$a8,$00,$00       // $bc8c  
    .byte $00,$00,$fc,$c0,$fe,$06,$fe,$00       // $bc94  
    .byte $00,$00,$fe,$c6,$c0,$c0,$fe,$00       // $bc9c  
    .byte $00,$00,$fe,$c6,$c6,$c6,$fe,$00       // $bca4  
    .byte $00,$00,$fe,$c6,$fe,$cc,$c6,$00       // $bcac  
    .byte $00,$00,$fe,$c0,$fc,$c0,$fe,$00       // $bcb4  
    .byte $00,$55,$00,$2a,$00,$2a,$00,$00       // $bcbc  
    .byte $00,$55,$00,$aa,$00,$aa,$00,$00       // $bcc4  
    .byte $00,$55,$00,$aa,$00,$aa,$00,$00       // $bccc  
    .byte $00,$55,$00,$aa,$00,$aa,$00,$00       // $bcd4  
    .byte $00,$57,$03,$a3,$03,$a3,$03,$03       // $bcdc  
    .byte $c0,$60,$30,$18,$0c,$06,$03,$03       // $bce4  
    .byte $00,$00,$00,$00,$00,$00,$00,$ff       // $bcec  
    .byte $00,$00,$00,$00,$00,$00,$00,$ff       // $bcf4  
    .byte $00,$00,$00,$00,$00,$00,$00,$ff       // $bcfc  
    .byte $00,$00,$00,$00,$00,$00,$00,$ff       // $bd04  
    .byte $00,$00,$00,$00,$00,$00,$00,$ff       // $bd0c  
    .byte $00,$00,$00,$00,$00,$00,$00,$ff       // $bd14  
    .byte $00,$00,$00,$00,$00,$00,$00,$ff       // $bd1c  
    .byte $00,$00,$00,$00,$00,$00,$00,$ff       // $bd24  
    .byte $00,$00,$00,$00,$00,$00,$00,$ff       // $bd2c  
    .byte $00,$00,$00,$00,$00,$00,$00,$ff       // $bd34  
    .byte $00,$00,$00,$00,$00,$00,$00,$ff       // $bd3c  
    .byte $00,$00,$00,$00,$00,$00,$00,$ff       // $bd44  
    .byte $00,$00,$00,$00,$00,$00,$00,$ff       // $bd4c  
    .byte $00,$00,$00,$00,$00,$00,$00,$ff       // $bd54  
    .byte $00,$00,$00,$00,$00,$00,$00,$ff       // $bd5c  
    .byte $00,$00,$00,$00,$00,$00,$00,$ff       // $bd64  
    .byte $00,$00,$00,$00,$00,$00,$00,$ff       // $bd6c  
    .byte $00,$00,$00,$00,$00,$00,$00,$ff       // $bd74  
    .byte $00,$00,$00,$00,$00,$00,$00,$ff       // $bd7c  
    .byte $00,$00,$00,$00,$00,$00,$00,$ff       // $bd84  
    .byte $00,$00,$00,$00,$00,$00,$00,$ff       // $bd8c  
    .byte $00,$00,$00,$00,$00,$00,$00,$ff       // $bd94  
    .byte $00,$00,$00,$00,$00,$00,$00,$ff       // $bd9c  
    .byte $00,$00,$00,$00,$00,$00,$00,$ff       // $bda4  
    .byte $00,$00,$00,$00,$00,$00,$00,$ff       // $bdac  
    .byte $00,$00,$00,$00,$00,$00,$00,$ff       // $bdb4  
    .byte $00,$00,$00,$00,$00,$00,$00,$ff       // $bdbc  
    .byte $00,$00,$00,$00,$00,$00,$00,$ff       // $bdc4  
    .byte $00,$00,$00,$00,$00,$00,$00,$ff       // $bdcc  
    .byte $00,$00,$00,$00,$00,$00,$00,$ff       // $bdd4  
    .byte $00,$00,$00,$00,$00,$00,$00,$ff       // $bddc  
    .byte $00,$00,$00,$00,$00,$00,$00,$ff       // $bde4  
    .byte $00,$00,$00,$00,$00,$00,$00,$ff       // $bdec  
    .byte $00,$fe,$c6,$c6,$de,$fe,$00,$ff       // $bdf4  
    .byte $00,$00,$00,$00,$00,$00,$00,$ff       // $bdfc  
    .byte $00,$00,$00,$00,$00,$00,$00,$ff       // $be04  
    .byte $00,$00,$00,$00,$00,$00,$00,$ff       // $be0c  
    .byte $00,$00,$00,$00,$00,$00,$00,$ff       // $be14  
    .byte $03,$06,$0c,$18,$30,$60,$c0,$c0       // $be1c  
    .byte $00,$00,$00,$00,$00,$00,$00,$00       // $be24  
    .byte $00,$00,$00,$00,$00,$00,$00,$00       // $be2c  
    .byte $00,$00,$00,$00,$00,$00,$00,$00       // $be34  
    .byte $00,$00,$00,$00,$00,$00,$00,$00       // $be3c  
    .byte $00,$00,$00,$00,$00,$00,$00,$00       // $be44  
    .byte $00,$00,$00,$00,$00,$00,$00,$00       // $be4c  
    .byte $00,$00,$00,$00,$00,$00,$00,$00       // $be54  
    .byte $00,$00,$00,$00,$00,$00,$00,$00       // $be5c  
    .byte $00,$00,$00,$00,$00,$00,$00,$00       // $be64  
    .byte $00,$00,$00,$00,$00,$00,$00,$00       // $be6c  
    .byte $00,$00,$00,$00,$00,$00,$00,$00       // $be74  
    .byte $00,$00,$00,$00,$00,$00,$00,$00       // $be7c  
    .byte $00,$00,$00,$00,$00,$00,$00,$00       // $be84  
    .byte $00,$00,$00,$00,$00,$00,$00,$00       // $be8c  
    .byte $00,$00,$00,$00,$00,$00,$00,$00       // $be94  
    .byte $00,$00,$00,$00,$00,$00,$00,$00       // $be9c  

// ----------------------------------------------------------------------------
// thrusty-levels: title screen text (high score table, music playing).
// "Press SPACE BAR to start." moved down 2 rows (row 16 -> 18, its first two
// bytes in tab_0900) to make room for the title on row 16.
// Messages: <bitmap address>, ASCII text, $FF. Bitmap $6000, 40x25 cells.
// ----------------------------------------------------------------------------
write_title_screen_texts:
    jsr plot_qr_code                            // title_qr.asm (in the music area)
    jsr write_press_spacebar
    lda #$07                                    // yellow, like "Game Over"
    sta font_byte_mask
    lda #>msg_title
    sta plot_string_ptr+1
    ldx #<msg_title
    jmp write_message
.function text_pos(row, col) { .return $6000 + row * 320 + col * 8 }
msg_title:
    .byte <text_pos(16, 10), >text_pos(16, 10)
    .encoding "ascii"
    .text "SUPER THRUSTY MAKER"
    .byte $ff
}

// ============================================================================
// relocator  (load $6c24-$6c54, runtime $6c24-$6c54)
// Program entry (SYS 27684): relocate main block and start
// ============================================================================
relocator_load:
entry:
    lda #$2f                                    // $6c24  Entry point (SYS 27684)
    sta $00                                     // $6c26  
    lda $01                                     // $6c28  BASIC ROM off
    and #$f8                                    // $6c2a  
    ora #$06                                    // $6c2c  
    sta $01                                     // $6c2e  
    lda #<music_stub_load                       // $6c30  copy $3000-$6CFF to $8280-$BF7F
    sta boot_read_ptr                           // $6c32  
    lda #>music_stub_load                       // $6c34  
    sta boot_read_ptr+1                         // $6c36  
    lda #<(music_stub_load+RELOC_OFFSET)        // $6c38  
    sta boot_write_ptr                          // $6c3a  
    lda #>(music_stub_load+RELOC_OFFSET)        // $6c3c  
    sta boot_write_ptr+1                        // $6c3e  set boot_write_ptr to &0A60
    ldx #((relocator_load - music_stub_load) >> 8) + 1  // $6c40  number of pages ($3D)
relocate:
    ldy #$00                                    // $6c42  
relocate_loop:
    lda (boot_read_ptr),y                       // $6c44  
    sta (boot_write_ptr),y                      // $6c46  
    dey                                         // $6c48  
    bne relocate_loop                           // $6c49  
    inc boot_read_ptr+1                         // $6c4b  
    inc boot_write_ptr+1                        // $6c4d  
    dex                                         // $6c4f  
    bne relocate                                // $6c50  relocate &3D pages (~16k) from &1A01 to &0A60
    jmp init                                    // $6c52  continue in the relocated code

// ============================================================================
// gfx  (load $6c55-$7954, runtime $4000-$4cff)
// Sprite and character graphics, copied to $4000 (VIC bank 1)
// ============================================================================
gfx_load:
.pseudopc $4000 {

    #import "sprites.asm"
}

// ============================================================================
// filler2  (load $7955-$7f16, runtime $7955-$7f16)
// Unused filler ($FA) left by the cruncher
// ============================================================================
filler2_load:
    .fill $05c2, $fa

// ----------------------------------------------------------------------------
// Load-image addresses of relocated blocks (used by the init copy loops)
// ----------------------------------------------------------------------------
.label high_score_table_relocated     = hiscore_init_load + RELOC_OFFSET  // copy source of the block at $b875
.label lookup_angle_to_y_FRAC         = tab_0880_load + RELOC_OFFSET  // copy source of the block at $b8f5
.label lookup_angle_to_y_INT          = tab_08a0_load + RELOC_OFFSET  // copy source of the block at $b915
.label lookup_angle_to_x_FRAC         = tab_0980_load + RELOC_OFFSET  // copy source of the block at $b935
.label lookup_angle_to_x_INT          = tab_09a0_load + RELOC_OFFSET  // copy source of the block at $b955
.label in_game_messages_relocated     = tab_0900_load + RELOC_OFFSET  // copy source of the block at $b975

// ----------------------------------------------------------------------------
// Layout checks
// ----------------------------------------------------------------------------
.assert "relocator source is $3000", music_stub_load, $3000
.assert "SYS address needs 5 digits", entry >= 10000, true
.assert "music must end below $3000", music_stub_load <= $3000, true
// .errorif (not .assert): a failed .assert still writes the PRG
.label main_end = main3_load + RELOC_OFFSET + (relocator_load - main3_load)
.errorif main_end > $c000, "main code + level_tables.asm end at $" + toHexString(main_end) + ": " + (main_end - $c000) + " bytes past $C000"
