"""Names for the shared zero page temporaries ($70-$8F) in code the BBC
alignment did not cover (mostly C64-specific routines)."""

ZP_RANGE_NAMES = [
    (0x044f, 0x047d, {0x80: 'copy_src_ptr', 0x82: 'copy_dst_ptr', 0x84: 'copy_dst2_ptr'}),
    (0x82e4, 0x83b4, {0x70: 'terrain_pixel_byte', 0x72: 'terrain_draw_ptr', 0x74: 'terrain_draw_wall_index',
                      0x76: 'terrain_draw_addr_LO', 0x77: 'terrain_draw_addr_HI'}),
    (0x831d, 0x8330, {0x74: 'terrain_draw_wall_index'}),
    (0x850d, 0x8933, {0x7a: 'current_object', 0x73: 'obj_screen_x', 0x74: 'obj_screen_y',
                      0x83: 'object_type', 0x87: 'score_accumulation'}),
    (0x8ba7, 0x8c9b, {0x70: 'band_next_raster', 0x71: 'band_sprite_count', 0x72: 'build_list_pos',
                      0x73: 'raster_build_pos'}),
    (0x9471, 0x9515, {0x80: 'plot_string_ptr'}),
    (0x97e0, 0x98b2, {0x70: 'ship_spr_x_calc', 0x76: 'plot_ship_sprite_number', 0x78: 'ship_spr_y_calc'}),
    (0x9ab4, 0x9b43, {0x71: 'plot_pod_xpos_INT', 0x7b: 'pod_temp'}),
    (0xa38e, 0xa5b9, {0x76: 'particle_pixel_byte', 0x7e: 'player_to_particle_deltay_INT'}),
    (0xa832, 0xa873, {0x80: 'colour_ptr_A', 0x82: 'colour_ptr_B', 0x84: 'colour_pages'}),
    (0xab5c, 0xac3c, {0x70: 'draw_line_delta_x', 0x75: 'draw_line_delta_major'}),
    (0xae52, 0xae68, {0x88: 'draw_line_start_x', 0x8a: 'draw_line_end_x', 0x8b: 'draw_line_end_y'}),
    (0xb3e8, 0xb3fe, {0x8f: 'wait_frames'}),
    (0xb56a, 0xb580, {0x85: 'high_score_ptr_C', 0x86: 'high_score_ptr_C_HI'}),
    (0xb683, 0xb6a5, {0x70: 'gfx_copy_src_ptr', 0x72: 'gfx_copy_dst_ptr'}),
    (0xb719, 0xb73b, {0x80: 'relocate_src_ptr', 0x82: 'relocate_dest_ptr'}),
]
