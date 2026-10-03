"""Annotations: level door logic ($917D-$926A) - hard-coded per level."""

LABELS = {
    0x917d: 'tick_door_logic',
    0x9183: 'door_switch_zero',
    0x91ad: 'level_3_door_visible',
    0x91b8: 'level_3_door_closing',
    0x91c0: 'level_3_door_draw',
    0x91d0: 'level_3_door_draw_loop',
    0x91ec: 'level_4_door_visible',
    0x91f7: 'level_4_door_closing',
    0x91ff: 'level_4_door_draw',
    0x920d: 'level_4_door_draw_loop',
    0x9213: 'level_4_door_store',
    0x922f: 'level_5_door_visible',
    0x923a: 'level_5_door_closing',
    0x9242: 'level_5_door_draw',
    0x9253: 'level_5_door_draw_top',
    0x925f: 'level_5_door_draw_bottom',
}

COMMENTS = {
    0x917d: 'door switch shot: counter set to $FF, counts down',
    0x9183: 'only levels 3, 4 and 5 have doors',
    0x919a: 'door top: world Y $0269',
    0x91a8: 'on screen?',
    0x91ad: 'door open amount follows the switch counter,',
    0x91b8: 'then closes slowly',
    0x91c1: 'door: left wall X = $AE - opening',
    0x91c6: 'wall array row of the door top',
    0x91ce: '13 rows',
    0x91d9: 'door top: world Y $0343',
    0x91ee: 'max opening 21 rows',
    0x9206: 'bottom row of the door',
    0x9209: 'closed door wall X',
    0x9211: 'open part: wall X $98',
    0x921c: 'door top: world Y $0370',
    0x9231: 'max opening $12',
    0x9243: 'diamond door: wall X = $C0 - opening',
    0x9251: '7 rows sloping right',
    0x925d: '8 rows sloping back',
}

BLOCK_COMMENTS = {
    0x917d: """Level doors (levels 3, 4 and 5 only - level 0-2 have none)
Shooting a door switch sets door_switch_counter_A to $FF; the door then opens
(door_switch_counter_B follows it) and closes again as the counter runs out.
A door is drawn by overwriting entries of terrain_left_wall (the decoded left
wall) for the rows where the door is. The door positions and shapes are
hard-coded below, so a NEW LEVEL WITH A DOOR needs its own routine here.""",
    0x9199: 'Level 3: door at world Y $0269, 13 rows, wall moves left as it opens',
    0x91d8: 'Level 4: door at world Y $0343, opens row by row (21 rows)',
    0x921b: 'Level 5: diamond shaped door at world Y $0370',
}
