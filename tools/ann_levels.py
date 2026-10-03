"""Annotations: level data and level setup ($A004-$A99A)."""
from ann_levels_gen import LABELS, FORMATS, COMMENTS, BLOCK_COMMENTS

ENTRY_POINTS = [0xa004]

LABELS.update({
    0xa004: 'debug_print_hex_A',
    0xa029: 'debug_hex_value',
    0xa02a: 'debug_print_hex_digit',
    0xa037: 'debug_print_hex_digit_2',
    0xa352: 'level_obj_flags',
    0xa5b9: 'level_reset',
    0xa61d: 'level_reset_loop',
    0xa631: 'level_reset_found',
    0xa63b: 'level_reset_use_entry',
    0xa645: 'level_reset_set_position',
    0xa68b: 'level_reset_set_pod_angle',
    0xa695: 'level_reset_done',
    0xa6a4: 'level_number',
    0xa6a5: 'reverse_gravity_flag',
    0xa6a6: 'level_reset_with_pod_flag',
    0xa6a7: 'initialise_level_pointers',
    0xa75f: 'set_level_colours',
    0xa76a: 'set_level_colours_wait',
    0xa78a: 'set_level_colours_screen_A',
    0xa79c: 'set_level_colours_screen_B',
    0xa7b3: 'set_level_colours_colour_ram',
    0xa7da: 'set_level_colours_wait_raster',
    0xa7e8: 'set_status_bar_chars',
    0xa7f9: 'set_status_bar_colours',
    0xa832: 'set_text_screen_colours',
    0xa853: 'set_text_screen_colours_loop',
    0xa85e: 'set_text_screen_colours_next',
    0xa86d: 'set_text_screen_colours_wait',
    0xa873: 'level_reset_data_sizes',
    0xa8df: 'level_reset_ptr_table_LO',
    0xa8e5: 'level_reset_ptr_table_HI',
    0xa8eb: 'level_reset_ptr2_table_LO',
    0xa8f1: 'level_reset_ptr2_table_HI',
    0xa8f7: 'level_gravity_FRAC_table',
    0xa8fd: 'terrain_left_wall_counter_ptrs_LO',
    0xa903: 'terrain_left_wall_counter_ptrs_HI',
    0xa909: 'terrain_left_wall_increment_ptrs_LO',
    0xa90f: 'terrain_left_wall_increment_ptrs_HI',
    0xa915: 'terrain_right_wall_counter_ptrs_LO',
    0xa91b: 'terrain_right_wall_counter_ptrs_HI',
    0xa921: 'terrain_right_wall_increment_ptrs_LO',
    0xa927: 'terrain_right_wall_increment_ptrs_HI',
    0xa92d: 'level_colour_terrain',
    0xa933: 'level_colour_mc1',
    0xa939: 'level_colour_mc3',
    0xa93f: 'level_colour_status',
    0xa945: 'level_colour_objects',
    0xa94b: 'level_colour_shield',
    0xa951: 'palette_set_colour_Y_to_A',
    0xa952: 'unused_a952',
})

TABLES = {
    0xa95e: (0xa96a, 'level_obj_pos_X_lookup'),
    0xa96a: (0xa976, 'level_obj_pos_Y_lookup'),
    0xa976: (0xa982, 'level_obj_pos_Y_EXT_lookup'),
    0xa982: (0xa98e, 'level_obj_type_lookup'),
    0xa98e: (0xa99a, 'level_gun_param_lookup'),
    0xa879: (0xa87f, 'level_0_reset_data'),
    0xa87f: (0xa885, 'level_1_reset_data'),
    0xa885: (0xa897, 'level_2_reset_data'),
    0xa897: (0xa8a9, 'level_3_reset_data'),
    0xa8a9: (0xa8c1, 'level_4_reset_data'),
    0xa8c1: (0xa8df, 'level_5_reset_data'),
}

FORMATS.update({
    0xa004: ('rows', 16),
    0xa352: ('rows', 16),
    0xa873: ('rows', 6),
    0xa8df: ('lo', 0xa8e5), 0xa8e5: ('hi', 0xa8df),
    0xa8eb: ('lo', 0xa8f1), 0xa8f1: ('hi', 0xa8eb),
    0xa8f7: ('rows', 6),
    0xa8fd: ('lo', 0xa903), 0xa903: ('hi', 0xa8fd),
    0xa909: ('lo', 0xa90f), 0xa90f: ('hi', 0xa909),
    0xa915: ('lo', 0xa91b), 0xa91b: ('hi', 0xa915),
    0xa921: ('lo', 0xa927), 0xa927: ('hi', 0xa921),
    0xa92d: ('rows', 6), 0xa933: ('rows', 6), 0xa939: ('rows', 6),
    0xa93f: ('rows', 6), 0xa945: ('rows', 6), 0xa94b: ('rows', 6),
    0xa952: ('rows', 12),
    0xa95e: ('words',), 0xa96a: ('words',), 0xa976: ('words',), 0xa982: ('words',), 0xa98e: ('words',),
})

COMMENTS.update({
    0xa5bc: 'redraw the level colours',
    0xa5d2: 'clear game variables $02-$9F (keeps demo flag, random seed, ship Y)',
    0xa5ff: 'find the restart point for the current height:',
    0xa61d: 'first entry whose trigger height is below the ship',
    0xa645: 'restart data rows: Y_EXT, Y, window X, window Y_EXT, window Y, X',
    0xa699: 'BBC palette calls - empty on the C64',
    0xa6af: 'landscape visible',
    0xa6b4: 'generator damage starts at 50',
    0xa6f2: 'reverse gravity: negate gravity',
    0xa701: 'bullet pixels ($AA visible / $FF)',
    0xa75f: 'set up the playfield colours for this level',
    0xa772: 'terrain colour ("10" pixels, screen RAM low nibble)',
    0xa77b: 'colour of "01" pixels (screen RAM high nibble)',
    0xa78a: 'screen A ($5C00): terrain visible',
    0xa79c: 'screen B ($5400): terrain colour 0 = invisible landscape',
    0xa7ae: 'colour of "11" pixels (colour RAM)',
    0xa7c5: 'object sprite colours',
    0xa7da: 'wait for raster line $50',
    0xa7e8: 'status bar: characters 0-79 in rows 0-1 of both screens',
    0xa804: 'status bar label colours',
    0xa832: 'fill both screens with the text colour (title / high score screens)',
})

BLOCK_COMMENTS.update({
    0xa004: """Unused debug routine: print A as two hex digits (never called)""",
    0xa03c: """==========================================================================
LEVEL DATA
==========================================================================
The level data format is identical to the BBC Micro version.

Terrain: each level has four tables. A/B describe the left cave wall, C/D the
right wall. A[i] is a run length in rows, B[i] the X step added on each of
those rows (signed). The terrain is decoded twice per wall (even/odd rows) by
terrain_process as the screen scrolls. X is in 4-pixel units (80 columns
across the screen, the world is 256 units wide and wraps).
The first entries ($FF,$FF,...) are the open space above the planet.

Level 0 terrain""",
    0xa1ee: """Objects: per level five parallel tables, indexed by object number.
types: 0-3 gun (up-right, down-right, up-left, down-left), 4 fuel,
5 pod stand, 6 generator (reactor), 7/8 door switch (right / left).
obj_type is terminated by $FF.

Level 0 objects""",
    0xa352: """Runtime object flags (bit 0 = drawn, bit 1 = active/alive)""",
    0xa5b9: """level_reset
Start or restart the current level. The restart point is chosen from the
depth (Y) the ship had reached: the first restart entry at or below that
depth, stepping back one entry unless the pod was being carried. Sets the
window and ship position and re-attaches the pod if it was being carried.""",
    0xa6a7: """initialise_level_pointers
Points the terrain decoder and the object code (self-modifying) at the data
for level_number, sets gravity and resets the object state.""",
    0xa75f: """Level colours (C64 only). Two screen matrices are used for the playfield
colours: $5C00 shows the terrain, $5400 is identical except the terrain
colour is black (used for the invisible landscape levels).""",
    0xa832: 'Text screen colours (C64 only)',
    0xa873: """Restart points ("level reset data"): number of restart points per level,
followed by each level's table. A table with n entries has 6 rows of n bytes:
ship Y_EXT, ship Y, window X, window Y_EXT, window Y, ship X""",
    0xa8df: 'Pointers to the restart tables (row 0 and row 1)',
    0xa8f7: 'Gravity per level (fractional part)',
    0xa8fd: 'Pointers to the terrain tables',
    0xa92d: """Per-level colours (C64 only)""",
    0xa951: 'BBC palette routine - an empty stub on the C64',
    0xa952: 'Unused bytes',
    0xa95e: 'Pointers to the object tables, one word per level',
})
