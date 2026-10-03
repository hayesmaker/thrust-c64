"""Corrections to comments/names carried over from the BBC Micro source that
do not apply to the C64 version."""

BLOCK_COMMENTS = {
    0x9e09: """Ship routines
Read the A / S keys to rotate the ship left or right""",
    0xb3b6: """Invisible landscape: shows playfield screen B (terrain colour black)
instead of screen A while the flag is set and the shield is not in use""",
    0xb3e5: 'RUN/STOP pressed: back to the title / high score screen',
    0xb3e8: """Params: Y = number of frames to wait (vsync_count, 50 per second)
Waits Y frames, RUN/STOP aborts to the title screen""",
}

COMMENTS = {
    0x0492: '',
    0x04d8: '',
    0x8835: '',
    0x89d5: 'BBC leftover, not used on the C64',
}

ZP_COMMENTS = {
    0x1a: 'incremented by the top-of-frame raster interrupt',
    0xa1: 'BBC timer flag, only cleared on the C64',
}

LABELS = {
    0xa52e: 'particle_type_pixels',
    0xa526: 'particles_xpos_byte_mask',
}
COMMENTS.update({
    0xa705: 'player bullet pixels: $AA, or $FF when the landscape is invisible',
})
BLOCK_COMMENTS.update({
    0xa52e: 'Pixel pattern per particle type: player bullet, debris, star, hostile bullet',
})
