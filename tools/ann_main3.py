"""Annotations: main block part 3 ($AA8C-$BEA3), init stages, relocated tables."""

ENTRY_POINTS = [0xaa8c, 0xb5fa, 0xb759]

LABELS = {
    0xaa8c: 'unused_init_particle',
    # tether / tractor beam line (drawn into a multiplexed sprite)
    0xab1e: 'line_step_fn_LO',
    0xab1f: 'line_step_fn_HI',
    0xab20: 'line_pixel_mask',
    0xab21: 'line_sprite_offset',
    0xab22: 'line_sprite_offset_start',
    0xab23: 'line_bytes_left',
    0xab24: 'line_rows_left',
    0xab25: 'line_sprite_buffer',
    0xab26: 'draw_line_sprite',
    0xab4b: 'draw_line_clear_buffer_0',
    0xab54: 'draw_line_clear_buffer_1',
    0xab56: 'draw_line_clear_buffer_1_loop',
    0xac66: 'line_step_right',
    0xac79: 'line_step_return',
    0xac7a: 'line_step_down',
    0xac8b: 'line_step_up',
    0xac9c: 'line_next_sprite',
    # fuel beam
    0xae68: 'text_colour',
    0xae69: 'draw_fuel_beam',
    0xae71: 'draw_fuel_beam_test',
    0xae76: 'draw_fuel_beam_on',
    0xaef7: 'player_teleport_disappear',
    0xaece: 'teleport_step_disappear',
    0xaed4: 'teleport_step_appear',
    0xaeda: 'teleport_step_ship_gone',
    0xa49f: 'particle_test_hit_ship',
    # game flow
    0xaf82: 'game_start',
    0xaf89: 'title_shown_flag',
    0xaf8f: 'landscape_visible_flag',
    0xaf90: 'collision_ignore_timer',
    0xb016: 'high_score_wait_tick',
    0xb045: 'start_game',
    0xb1ad: 'tick_loop_continue',
    0xb24e: 'tick_loop_test_end',
    0xb3fe: 'clear_screen_and_sprites',
    0xb45a: 'wait_game_tick',
    0xb466: 'wait_game_tick_store',
    0xb46a: 'reset_game_tick',
    0xb470: 'draw_player_timed_to_vsync',
    0xb479: 'game_tick_timer',
    0xb47a: 'unused_b47a',
    0xb480: 'test_key',
    0xb484: 'test_inkey',
    0xb48d: 'test_key_matrix',
    0xb4a7: 'test_key_not_pressed',
    0xb4f4: 'bit_table_2',
    0xb521: 'check_high_score',
    0xb5f7: 'enter_name_done',
    0xb5fa: 'unused_plot_char',
    0xb683: 'init',
    0xb6a5: 'init_clear',
    0xb719: 'init_copy_low',
    0xb759: 'unused_bbc_instructions',
    0xb9eb: 'bbc_instructions_text',
    0xbba4: 'status_charset_data',
    # init_low ($0400)
    0x0400: 'init2',
    0x0489: 'init2_irq',
    0x04dc: 'init2_sid',
    0x04e0: 'init2_sid_loop',
    # relocated tables
    0x0100: 'high_score_table',
    0x0880: 'angle_to_y_FRAC',
    0x08a0: 'angle_to_y_INT',
    0x0980: 'angle_to_x_FRAC',
    0x09a0: 'angle_to_x_INT',
    0x0e00: 'raster_table',
    0x6c24: 'entry',
    0x6c42: 'relocate',
    0x6c44: 'relocate_loop',
    0x4000: 'sprite_data',
}

RAM_LABELS = {
    0x08c0: 'old_irq_vector',
    0x0b01: None,
}
del RAM_LABELS[0x0b01]

COMMENTS = {
    0xab26: 'alternate between two sprite buffers',
    0xab2e: 'sprite frame $4C/$4D ($5300) or $4E/$4F ($5380)',
    0xab37: '21 rows',
    0xac52: 'plot into the sprite data',
    0xae7e: 'beam sprites below the ship',
    0xae97: 'frames $2F/$30 = fuel beam',
    0xaf82: 'from init2: sound on, go to the title screen',
    0xb0ac: 'first time: show title / high score screen',
    0xb0cd: 'NUMBER OF LEVELS - all per-level tables have 6 entries',
    0xb1a8: 'ignore collisions for the first 10 frames',
    0xb1bc: 'wait for the next game tick (CIA timer)',
    0xb45a: 'wait until the CIA timer IRQ counted 3 ticks',
    0xb46a: 'restart the tick counter',
    0xb480: 'test real keyboard only',
    0xb484: 'test key X (matrix index row*8+col)',
    0xb485: 'RUN/STOP is never faked',
    0xb489: 'demo mode: keys come from the demo tables',
    0xb5f7: '',
    0xb683: 'copy graphics: $6C55 (load address) -> $4000, 13 pages',
    0xb68b: '',
    0xb6a5: '',
    0xb6a8: 'clear zero page $03-$FF',
    0xb6b1: 'build the column -> bitmap byte tables (80 columns, 4 pixels each)',
    0xb6bd: 'two columns per bitmap byte',
    0xb6cb: 'left half pixels',
    0xb6d0: 'right half pixels',
    0xb6e8: 'copy the angle -> vector tables',
    0xb705: 'copy raster interrupt table',
    0xb710: '',
    0xb719: 'copy init_low ($0400-$06FF) and run it',
    0xb73b: 'high score table -> $0100',
    0xb746: 'in-game messages -> $0900',
    0xb751: '',
    0xb756: '',
    0x0400: 'VIC: sprites off and at 0,0',
    0x040a: 'all sprites enabled',
    0x0417: 'VIC bank 1 ($4000-$7FFF)',
    0x0426: 'black border',
    0x042b: 'bitmap mode, display off',
    0x0435: 'multicolour',
    0x043d: 'screen $5C00, bitmap $6000',
    0x0449: 'level 0',
    0x044c: 'level colours',
    0x044f: 'status bar charset -> $5800 and $6000',
    0x047d: 'clear screen',
    0x0489: 'save the KERNAL IRQ vector',
    0x0496: 'install irq_handler (IRQ and BRK)',
    0x04a6: 'first raster interrupt at line 0',
    0x04b3: 'enable raster interrupt',
    0x04b8: 'CIA 1 timer A: $276A cycles (~97 Hz game tick)',
    0x04d1: 'disable other CIA interrupts',
    0x04dc: 'silence the SID',
    0x04e9: 'volume 15',
    0x04f1: 'start',
    0x6c24: 'Entry point (SYS 27684)',
    0x6c28: 'BASIC ROM off',
    0x6c30: 'copy $3000-$6CFF to $8280-$BF7F',
    0x6c40: 'number of pages ($3D)',
    0xb693: 'number of pages ($0D)',
    0x6c52: 'continue in the relocated code',
}

OPERAND = {
    0xb683: '#<gfx_load', 0xb687: '#>gfx_load',
    0xb68b: '#<sprite_data', 0xb68f: '#>sprite_data',
    0xb6c0: 'column_bitmap_offset_LO+1,x',
    0xb6c8: 'column_bitmap_offset_HI+1,x',
    0xb6d2: 'column_pixel_byte+1,x',
    0x044f: '#<status_charset_data', 0x0453: '#>status_charset_data',
    0x6c30: '#<music_stub_load', 0x6c34: '#>music_stub_load',
    0x6c40: '#((relocator_load - music_stub_load) >> 8) + 1',
    0xb693: '#(filler2_load - gfx_load) >> 8',
    0x6c38: '#<(music_stub_load+RELOC_OFFSET)', 0x6c3c: '#>(music_stub_load+RELOC_OFFSET)',
}

BLOCK_COMMENTS = {
    0xaa8c: 'Unused - never called',
    0xab1e: """Tether / tractor beam line. On the C64 the line is drawn into sprite data
($5300 or $5380, alternating each frame) and shown with the multiplexer.""",
    0xab26: 'Draw the ship-pod line into a sprite',
    0xac66: 'Line step routines (called through the self-modified JSRs above)',
    0xae68: 'Text colour for the in-game messages (= level terrain colour)',
    0xae69: 'Fuel collection beam: two sprites below the ship while collecting fuel',
    0xaf82: """==========================================================================
GAME FLOW
==========================================================================
init2 jumps here once everything is set up.""",
    0xaf89: 'Game flow variables',
    0xb3fe: 'Turn off all sprites, then clear the playfield and object/particle state',
    0xb45a: """Game timing: the CIA 1 timer interrupt decrements game_tick_timer; the main
loop waits for it to go negative and adds 3, so the game runs at a fixed rate
independent of the raster.""",
    0xb479: 'Game tick counter (decremented by the CIA timer IRQ)',
    0xb480: """Key tests: X = matrix index (KEY_xxx). Returns Z set (and X = $FF) when the
key is down. test_inkey substitutes the demo key table in demo mode.""",
    0xb521: 'Game over: check the score against the high score table',
    0xb5fa: 'Unused',
    0xb683: """==========================================================================
INITIALISATION (runs once)
==========================================================================
Stage 2, entered from the relocator at $6C24 after the main block has been
copied to $8280.""",
    0xb759: """Unused: prints bbc_instructions_text with CHROUT and waits for SPACE.
A leftover from the BBC Micro version (never called).""",
    0xb9eb: 'Leftover BBC Micro instructions screen text (unused)',
    0xbba4: """Status bar character set, 96 characters. Copied to $5800 (text charset for
the status bar) and to $6000 (top of the bitmap) by init2.""",
    0x0400: """Stage 3 init, copied to $0400 (this area is reused for terrain_left_wall
once the game runs). Sets up the VIC, IRQs and SID, then starts the game.""",
    0x0100: """High score table, 8 entries of 16 bytes: 3 score bytes (BCD) + name.
Copied to $0100 at init. The score/fuel variables follow at $0180.""",
    0x0880: 'Angle (0-31) -> Y vector, fractional and integer parts',
    0x0980: 'Angle (0-31) -> X vector, fractional and integer parts',
    0x0900: 'In-game messages (relocated to $0900), same format as the messages above',
    0x0e00: """Raster interrupt table: [raster line, handler number, next]...
The sprite multiplexer appends its bands after the first two entries.""",
    0x6c24: """==========================================================================
ENTRY POINT - SYS 27684 ($6C24)
==========================================================================
Copies $3000-$6CFF up to $8280-$BF7F and jumps to init.""",
    0x4000: """Sprite graphics (VIC bank 1, sprite pointer = address / 64):
$00-$1F ship (32 rotation frames)  $20 shield        $21 pod
$22-$25 guns (4 directions)        $26/$27 fuel tank outline + "FUEL" label
$28/$29 pod stand                  $2A/$2B generator (reactor)
$2C/$2D door switches (right/left) $2E fuel tank (single sprite)
$2F/$30 fuel beam                  $31-$33 not used as sprites
Frames $4C-$4F ($5300-$53FF) are generated at run time for the tether line.""",
}

FORMATS = {
    0xb9eb: ('text',),
    0xbba4: ('rows', 8),
    0x0100: ('text',),
    0x0880: ('rows', 16), 0x08a0: ('rows', 16), 0x0980: ('rows', 16), 0x09a0: ('rows', 16),
    0x0900: ('text',),
    0x0e00: ('rows', 3),
    0x4000: ('sprites',),
}
