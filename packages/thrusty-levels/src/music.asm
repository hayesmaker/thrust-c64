// ============================================================================
// music.asm - Rob Hubbard music driver and Thrust theme
// Included from thrust.asm. Runtime addresses $2000-$2fff
// ============================================================================

// ----------------------------------------------------------------------------
// Music driver - Rob Hubbard (Thrust theme, 1986)
// The classic Hubbard engine: three voices, each with a track list of pattern
// numbers ($FF = loop, $FE = stop). Patterns hold note-length / note bytes and end
// with $FF. Instruments are 8 bytes: pulse lo, pulse hi, control, AD, SR,
// vibrato depth, pulse speed, fx flags.
// ----------------------------------------------------------------------------
music_driver:
    dec music_frame_skip                        // $2000  called once per frame via music_play ($3000)
    bpl music_play_frame                        // $2003  every 10th call is skipped
    lda #$09                                    // $2005  
    sta music_frame_skip                        // $2007  
    rts                                         // $200a  
music_play_frame:
    inc music_frame_counter                     // $200b  
    lda demo_mode_flag                          // $200e  music only plays in demo/title mode
    bne L2015                                   // $2010  
    jmp music_silence                           // $2012  
L2015:
    lda mute_sound_flag                         // $2015  or when sound is muted
    beq music_play_voices                       // $2017  
    jmp music_silence                           // $2019  
music_play_voices:
    lda #$00                                    // $201c  
    sta music_silenced_flag                     // $201e  
    lda #$00                                    // $2021  no filter
    sta SID_RES_FILT                            // $2023  
    lda #$0f                                    // $2026  volume 15
    sta SID_MODE_VOL                            // $2028  
    ldx #$02                                    // $202b  X = voice 2..0
    dec music_speed_counter                     // $202d  speed counter: new notes only every (speed+1) frames
    bpl music_voice_loop                        // $2030  
    lda music_speed                             // $2032  
    sta music_speed_counter                     // $2035  
music_voice_loop:
    lda music_voice_reg_offset,x                // $2038  voice register offset (0/7/14)
    sta music_voice_reg                         // $203b  
    tay                                         // $203d  
    lda music_speed_counter                     // $203e  
    cmp music_speed                             // $2041  
    bne music_voice_no_new_note                 // $2044  
    lda music_track_ptr_lo,x                    // $2046  track list pointer for this voice
    sta music_track_ptr                         // $2049  
    lda music_track_ptr_hi,x                    // $204b  
    sta music_track_ptr_HI                      // $204e  
    dec music_note_length_left,x                // $2050  note still sounding?
    bmi music_get_next_pattern                  // $2053  
    jmp music_note_playing                      // $2055  
    jmp music_next_voice                        // $2058  
music_voice_no_new_note:
    jmp music_effects                           // $205b  
music_get_next_pattern:
    ldy music_track_pos,x                       // $205e  
    lda (music_track_ptr),y                     // $2061  next pattern number from the track list
    cmp #$ff                                    // $2063  $FF = loop track
    beq music_restart_track                     // $2065  
    cmp #$fe                                    // $2067  $FE = stop music
    bne music_new_pattern_ok                    // $2069  
    jsr music_silence                           // $206b  
    jmp music_return                            // $206e  
music_restart_track:
    lda #$00                                    // $2071  
    sta music_note_length_left,x                // $2073  
    sta music_track_pos,x                       // $2076  
    sta music_pattern_pos,x                     // $2079  
    jmp music_get_next_pattern                  // $207c  
    jmp music_next_voice                        // $207f  
music_new_pattern_ok:
    tay                                         // $2082  
    lda music_pattern_ptr_lo,y                  // $2083  pattern pointer
    sta music_pattern_ptr                       // $2086  
    lda music_pattern_ptr_hi,y                  // $2088  
    sta music_pattern_ptr_HI                    // $208b  
    lda #$00                                    // $208d  
    sta music_porta_lo,x                        // $208f  
    ldy music_pattern_pos,x                     // $2092  
    lda #$ff                                    // $2095  
    sta music_gate_mask                         // $2097  gate on
    lda (music_pattern_ptr),y                   // $209a  note length byte: bits 0-4 length, bit 5 no release, bit 6 append, bit 7 instrument/porta follows
    sta music_note_length_flags,x               // $209c  
    sta music_temp_length                       // $209f  
    and #$1f                                    // $20a2  
    sta music_note_length_left,x                // $20a4  
    bit music_temp_length                       // $20a7  
    bvs music_append_note                       // $20aa  
    inc music_pattern_pos,x                     // $20ac  
    lda music_temp_length                       // $20af  
    bpl music_get_note                          // $20b2  
    iny                                         // $20b4  
    lda (music_pattern_ptr),y                   // $20b5  
    bpl L20c8                                   // $20b7  negative = portamento value follows
    sta music_porta_lo,x                        // $20b9  
    iny                                         // $20bc  
    lda (music_pattern_ptr),y                   // $20bd  
    sta music_porta_hi,x                        // $20bf  
    inc music_pattern_pos,x                     // $20c2  
    jmp L20cb                                   // $20c5  
L20c8:
    sta music_instrument_nr,x                   // $20c8  positive = new instrument number
L20cb:
    inc music_pattern_pos,x                     // $20cb  
music_get_note:
    iny                                         // $20ce  
    lda (music_pattern_ptr),y                   // $20cf  note number
    sta music_note_nr,x                         // $20d1  
    asl                                         // $20d3  
    tay                                         // $20d4  
    lda music_freq_table,y                      // $20d5  look up SID frequency
    sta music_temp_freq                         // $20d8  
    lda music_freq_table+1,y                    // $20db  
    ldy music_voice_reg                         // $20de  
    sta SID_V1_FREQ_HI,y                        // $20e0  
    sta music_freq_hi,x                         // $20e3  
    lda music_temp_freq                         // $20e6  
    sta SID_V1_FREQ_LO,y                        // $20e9  
    sta music_freq_lo,x                         // $20ec  
    jmp music_set_instrument                    // $20ef  
music_append_note:
    dec music_gate_mask                         // $20f2  
music_set_instrument:
    ldy music_voice_reg                         // $20f5  
    lda music_instrument_nr,x                   // $20f7  
    stx music_temp_store                        // $20fa  
    asl                                         // $20fd  instrument number * 8
    asl                                         // $20fe  
    asl                                         // $20ff  
    tax                                         // $2100  
    lda music_instruments+2,x                   // $2101  instrument waveform/control
    sta music_temp_ctrl                         // $2104  
    lda music_instruments+2,x                   // $2107  
    and music_gate_mask                         // $210a  
    sta SID_V1_CTRL,y                           // $210d  
    lda music_instruments,x                     // $2110  instrument pulse width
    sta SID_V1_PW_LO,y                          // $2113  
    pha                                         // $2116  
    lda music_instruments+1,x                   // $2117  
    sta SID_V1_PW_HI,y                          // $211a  
    pha                                         // $211d  
    lda music_instruments+3,x                   // $211e  instrument attack/decay
    sta SID_V1_AD,y                             // $2121  
    lda music_instruments+4,x                   // $2124  instrument sustain/release
    sta SID_V1_SR,y                             // $2127  
    ldx music_temp_store                        // $212a  
    lda #$00                                    // $212d  
    sta music_pulse_dir,x                       // $212f  
    sta music_pulse_delay,x                     // $2131  
    pla                                         // $2133  
    sta music_pulse_hi,x                        // $2134  
    pla                                         // $2137  
    sta music_pulse_lo,x                        // $2138  
    lda music_temp_ctrl                         // $213b  
    sta music_voice_ctrl,x                      // $213e  
    inc music_pattern_pos,x                     // $2141  
    ldy music_pattern_pos,x                     // $2144  
    lda (music_pattern_ptr),y                   // $2147  end of pattern?
    cmp #$ff                                    // $2149  
    bne music_note_done                         // $214b  
    lda #$00                                    // $214d  
    sta music_pattern_pos,x                     // $214f  
    inc music_track_pos,x                       // $2152  advance to next pattern in the track
music_note_done:
    jmp music_next_voice                        // $2155  
music_note_playing:
    ldy music_voice_reg                         // $2158  
    lda music_note_length_flags,x               // $215a  
    and #$20                                    // $215d  bit 5 set: no release
    bne music_effects                           // $215f  
    lda music_note_length_left,x                // $2161  
    bne music_effects                           // $2164  
    lda music_voice_ctrl,x                      // $2166  release: gate off
    and #$fe                                    // $2169  
    sta SID_V1_CTRL,y                           // $216b  
    lda #$00                                    // $216e  
    sta SID_V1_AD,y                             // $2170  
    sta SID_V1_SR,y                             // $2173  
music_effects:
    lda music_instrument_nr,x                   // $2176  
    asl                                         // $2179  
    asl                                         // $217a  
    asl                                         // $217b  
    tay                                         // $217c  
    sty music_instrument_offset                 // $217d  
    lda music_instruments+7,y                   // $2180  instrument fx flags
    sta music_instrument_fx                     // $2183  
    lda music_instruments+6,y                   // $2186  instrument pulse speed
    sta music_pulse_speed                       // $2189  
    lda music_instruments+5,y                   // $218c  instrument vibrato depth
    bne music_vibrato                           // $218f  
    jmp music_pulse_fx                          // $2191  
music_vibrato:
    pha                                         // $2194  
    and #$78                                    // $2195  
    lsr                                         // $2197  
    lsr                                         // $2198  
    lsr                                         // $2199  
    sta music_vib_range,x                       // $219a  
    pla                                         // $219c  
    and #$07                                    // $219d  
    sta music_vibrato_depth                     // $219f  
    lda music_vib_direction,x                   // $21a2  
    bpl L21ae                                   // $21a4  
    dec music_vib_counter,x                     // $21a6  
    bne L21bc                                   // $21a8  
    inc music_vib_direction,x                   // $21aa  
    bpl L21bc                                   // $21ac  
L21ae:
    inc music_vib_counter,x                     // $21ae  
    lda music_vib_range,x                       // $21b0  
    cmp music_vib_counter,x                     // $21b2  
    bcs L21bc                                   // $21b4  
    sta music_vib_counter,x                     // $21b6  
    dec music_vib_direction,x                   // $21b8  
    dec music_vib_counter,x                     // $21ba  
L21bc:
    lda music_note_nr,x                         // $21bc  
    asl                                         // $21be  
    tay                                         // $21bf  
    sec                                         // $21c0  
    lda music_freq_table,y                      // $21c1  
    sbc music_freq_table-2,y                    // $21c4  
    sta music_vib_step_lo                       // $21c7  
    lda music_freq_table+1,y                    // $21c9  
    sbc music_freq_table-1,y                    // $21cc  
music_vibrato_shift:
    dec music_vibrato_depth                     // $21cf  
    bmi L21da                                   // $21d2  
    lsr                                         // $21d4  
    ror music_vib_step_lo                       // $21d5  
    jmp music_vibrato_shift                     // $21d7  
L21da:
    sta music_vib_step_hi                       // $21da  
    lda music_freq_table,y                      // $21dc  
    sta music_vib_freq_lo                       // $21df  
    lda music_freq_table+1,y                    // $21e1  
    sta music_vib_freq_hi                       // $21e4  
    lda music_vib_range,x                       // $21e6  
    lsr                                         // $21e8  
    tay                                         // $21e9  
L21ea:
    dey                                         // $21ea  
    bmi L21fd                                   // $21eb  
    sec                                         // $21ed  
    lda music_vib_freq_lo                       // $21ee  
    sbc music_vib_step_lo                       // $21f0  
    sta music_vib_freq_lo                       // $21f2  
    lda music_vib_freq_hi                       // $21f4  
    sbc music_vib_step_hi                       // $21f6  
    sta music_vib_freq_hi                       // $21f8  
    jmp L21ea                                   // $21fa  
L21fd:
    lda music_note_length_flags,x               // $21fd  
    and #$1f                                    // $2200  
    cmp #$04                                    // $2202  
    bcc music_pulse_fx                          // $2204  
    ldy music_vib_counter,x                     // $2206  
L2208:
    dey                                         // $2208  
    bmi L221b                                   // $2209  
    clc                                         // $220b  
    lda music_vib_freq_lo                       // $220c  
    adc music_vib_step_lo                       // $220e  
    sta music_vib_freq_lo                       // $2210  
    lda music_vib_freq_hi                       // $2212  
    adc music_vib_step_hi                       // $2214  
    sta music_vib_freq_hi                       // $2216  
    jmp L2208                                   // $2218  
L221b:
    ldy music_voice_reg                         // $221b  
    lda music_vib_freq_lo                       // $221d  
    sta SID_V1_FREQ_LO,y                        // $221f  
    lda music_vib_freq_hi                       // $2222  
    sta SID_V1_FREQ_HI,y                        // $2224  
music_pulse_fx:
    lda music_instrument_fx                     // $2227  fx bit 3: pulse width add
    and #$08                                    // $222a  
    beq music_pulse_sweep                       // $222c  
    ldy music_instrument_offset                 // $222e  
    lda music_instruments,y                     // $2231  
    adc music_pulse_speed                       // $2234  
    sta music_instruments,y                     // $2237  
    ldy music_voice_reg                         // $223a  
    sta SID_V1_PW_LO,y                          // $223c  
    jmp music_portamento                        // $223f  
music_pulse_sweep:
    lda music_pulse_speed                       // $2242  pulse width sweep
    beq music_portamento                        // $2245  
    ldy music_voice_reg                         // $2247  
    and #$0f                                    // $2249  
    dec music_pulse_delay,x                     // $224b  
    bpl music_portamento                        // $224d  
    sta music_pulse_delay,x                     // $224f  
    lda music_pulse_speed                       // $2251  
    and #$f0                                    // $2254  
    sta music_pulse_step                        // $2256  
    lda music_pulse_dir,x                       // $2259  
    bne L2276                                   // $225b  
    lda music_pulse_step                        // $225d  
    clc                                         // $2260  
    adc music_pulse_lo,x                        // $2261  
    pha                                         // $2264  
    lda music_pulse_hi,x                        // $2265  
    adc #$00                                    // $2268  
    and #$0f                                    // $226a  
    pha                                         // $226c  
    cmp #$0e                                    // $226d  
    bne L228c                                   // $226f  
    inc music_pulse_dir,x                       // $2271  
    jmp L228c                                   // $2273  
L2276:
    sec                                         // $2276  
    lda music_pulse_lo,x                        // $2277  
    sbc music_pulse_step                        // $227a  
    pha                                         // $227d  
    lda music_pulse_hi,x                        // $227e  
    sbc #$00                                    // $2281  
    and #$0f                                    // $2283  
    pha                                         // $2285  
    cmp #$08                                    // $2286  
    bne L228c                                   // $2288  
    dec music_pulse_dir,x                       // $228a  
L228c:
    pla                                         // $228c  
    sta music_pulse_hi,x                        // $228d  
    sta SID_V1_PW_HI,y                          // $2290  
    pla                                         // $2293  
    sta music_pulse_lo,x                        // $2294  
    sta SID_V1_PW_LO,y                          // $2297  
music_portamento:
    ldy music_voice_reg                         // $229a  
    lda music_porta_lo,x                        // $229c  portamento active?
    beq music_drum_fx                           // $229f  
    and #$7e                                    // $22a1  
    sta music_temp_store                        // $22a3  
    lda music_porta_lo,x                        // $22a6  
    and #$01                                    // $22a9  
    beq L22c9                                   // $22ab  
    sec                                         // $22ad  
    lda music_freq_lo,x                         // $22ae  
    sbc music_temp_store                        // $22b1  
    sta music_freq_lo,x                         // $22b4  
    sta SID_V1_FREQ_LO,y                        // $22b7  
    lda music_freq_hi,x                         // $22ba  
    sbc music_porta_hi,x                        // $22bd  
    sta music_freq_hi,x                         // $22c0  
    sta SID_V1_FREQ_HI,y                        // $22c3  
    jmp music_drum_fx                           // $22c6  
L22c9:
    clc                                         // $22c9  
    lda music_freq_lo,x                         // $22ca  
    adc music_temp_store                        // $22cd  
    sta music_freq_lo,x                         // $22d0  
    sta SID_V1_FREQ_LO,y                        // $22d3  
    lda music_freq_hi,x                         // $22d6  
    adc music_porta_hi,x                        // $22d9  
    sta music_freq_hi,x                         // $22dc  
    sta SID_V1_FREQ_HI,y                        // $22df  
music_drum_fx:
    lda music_instrument_fx                     // $22e2  fx bit 0: drum (frequency drop)
    and #$01                                    // $22e5  
    beq music_skydive_fx                        // $22e7  
    lda music_freq_hi,x                         // $22e9  
    beq music_skydive_fx                        // $22ec  
    lda music_note_length_left,x                // $22ee  
    beq music_skydive_fx                        // $22f1  
    lda music_note_length_flags,x               // $22f3  
    and #$1f                                    // $22f6  
    sec                                         // $22f8  
    sbc #$01                                    // $22f9  
    cmp music_note_length_left,x                // $22fb  
    ldy music_voice_reg                         // $22fe  
    bcc L2312                                   // $2300  
    lda music_freq_hi,x                         // $2302  
    dec music_freq_hi,x                         // $2305  
    sta SID_V1_FREQ_HI,y                        // $2308  
    lda music_voice_ctrl,x                      // $230b  
    and #$fe                                    // $230e  
    bne L231a                                   // $2310  
L2312:
    lda music_freq_hi,x                         // $2312  
    sta SID_V1_FREQ_HI,y                        // $2315  
    lda #$80                                    // $2318  
L231a:
    sta SID_V1_CTRL,y                           // $231a  
music_skydive_fx:
    lda music_instrument_fx                     // $231d  fx bit 1: skydive (slow frequency rise)
    and #$02                                    // $2320  
    beq music_octave_arpeggio                   // $2322  
    lda music_frame_counter                     // $2324  
    and #$03                                    // $2327  
    bne music_octave_arpeggio                   // $2329  
    inc music_note_nr,x                         // $232b  
    lda music_note_nr,x                         // $232d  
    asl                                         // $232f  
    tay                                         // $2330  
    lda music_freq_table,y                      // $2331  
    sta music_temp_freq                         // $2334  
    lda music_freq_table+1,y                    // $2337  
    ldy music_voice_reg                         // $233a  
    sta SID_V1_FREQ_HI,y                        // $233c  
    lda music_temp_freq                         // $233f  
    sta SID_V1_FREQ_LO,y                        // $2342  
music_octave_arpeggio:
    lda music_instrument_fx                     // $2345  fx bit 2: octave arpeggio
    and #$04                                    // $2348  
    beq music_next_voice                        // $234a  
    lda music_instrument_fx                     // $234c  
    lsr                                         // $234f  
    lsr                                         // $2350  
    lsr                                         // $2351  
    lsr                                         // $2352  
    sta music_arp_interval+1                    // $2353  modifies the interval below
    ldy #$02                                    // $2356  
    cmp #$0c                                    // $2358  
    beq L235e                                   // $235a  
    ldy #$01                                    // $235c  
L235e:
    sty music_arp_mask+1                        // $235e  modifies the mask below
    lda music_frame_counter                     // $2361  
music_arp_mask:
    and #$04                                    // $2364  
    bne L2370                                   // $2366  
    lda music_note_nr,x                         // $2368  
    sec                                         // $236a  
music_arp_interval:
    sbc #$0c                                    // $236b  
    jmp L2372                                   // $236d  
L2370:
    lda music_note_nr,x                         // $2370  
L2372:
    asl                                         // $2372  
    tay                                         // $2373  
    lda music_freq_table,y                      // $2374  
    sta music_temp_freq                         // $2377  
    lda music_freq_table+1,y                    // $237a  
    ldy music_voice_reg                         // $237d  
    sta SID_V1_FREQ_HI,y                        // $237f  
    lda music_temp_freq                         // $2382  
    sta SID_V1_FREQ_LO,y                        // $2385  
music_next_voice:
    dex                                         // $2388  
    bmi music_return                            // $2389  
music_next_voice_jmp:
    jmp music_voice_loop                        // $238b  
music_return:
    rts                                         // $238e  
music_freq_table:
    .word $0116,$0127,$0138,$014b,$015f,$0173,$018a,$01a1  // $238f  
    .word $01ba,$01d4,$01f0,$020e,$022d,$024e,$0271,$0296  // $239f  
    .word $02bd,$02e7,$0313,$0342,$0374,$03a9,$03e0,$041b  // $23af  
    .word $045a,$049b,$04e2,$052c,$057b,$05ce,$0627,$0685  // $23bf  
    .word $06e8,$0751,$07c1,$0837,$08b4,$0937,$09c4,$0a57  // $23cf  
    .word $0af5,$0b9c,$0c4e,$0d09,$0dd0,$0ea3,$0f82,$106e  // $23df  
    .word $1168,$126e,$1388,$14af,$15eb,$1739,$189c,$1a13  // $23ef  
    .word $1ba1,$1d46,$1f04,$20dc,$22d0,$24dc,$2710,$295e  // $23ff  
    .word $2bd6,$2e72,$3138,$3426,$3742,$3a8c,$3e08,$41b8  // $240f  
    .word $45a0,$49b8,$4e20,$52bc,$57ac,$5ce4,$6270,$684c  // $241f  
    .word $6e84,$7518,$7c10,$8370,$8b40,$9370,$9c40,$a578  // $242f  
    .word $af58,$b9c8,$c4e0,$d098,$dd08,$ea30,$f820,$fd2e  // $243f  
music_voice_reg_offset:
    .byte $00,$07,$0e                           // $244f  
music_track_pos:
    .byte $00,$00,$00                           // $2452  
music_pattern_pos:
    .byte $00,$00,$00                           // $2455  
music_note_length_left:
    .byte $00,$00,$00                           // $2458  
music_note_length_flags:
    .byte $00,$00,$00                           // $245b  
music_voice_ctrl:
    .byte $00,$00,$00                           // $245e  
music_instrument_nr:
    .byte $13,$09,$02                           // $2461  
music_gate_mask:
    .byte $00                                   // $2464  
music_temp_length:
    .byte $00                                   // $2465  
music_temp_freq:
    .byte $00                                   // $2466  
music_temp_store:
    .byte $00                                   // $2467  
music_temp_ctrl:
    .byte $00                                   // $2468  
music_vibrato_depth:
    .byte $00                                   // $2469  
music_pulse_speed:
    .byte $00                                   // $246a  
music_speed_counter:
    .byte $00                                   // $246b  
music_speed:
    .byte $02                                   // $246c  
music_frame_skip:
    .byte $00                                   // $246d  
music_instrument_offset:
    .byte $00                                   // $246e  
music_silenced_flag:
    .byte $00                                   // $246f  
music_freq_hi:
    .byte $00,$00,$00                           // $2470  
music_freq_lo:
    .byte $00,$00,$00                           // $2473  
music_porta_lo:
    .byte $00,$00,$00                           // $2476  
music_porta_hi:
    .byte $00,$00,$00                           // $2479  
music_instrument_fx:
    .byte $00                                   // $247c  
music_pulse_step:
    .byte $00                                   // $247d  
music_frame_counter:
    .byte $00                                   // $247e  
music_pulse_lo:
    .byte $00,$00,$00                           // $247f  
music_pulse_hi:
    .byte $00,$00,$00                           // $2482  
music_instruments:
    .byte $00,$08,$41,$09,$08,$00,$00,$01       // $2485  
    .byte $00,$03,$41,$08,$0f,$00,$00,$05       // $248d  
    .byte $40,$01,$41,$09,$f0,$00,$00,$00       // $2495  
    .byte $00,$08,$81,$0f,$0a,$00,$00,$f5       // $249d  
    .byte $00,$05,$15,$0f,$ff,$00,$00,$02       // $24a5  
    .byte $00,$04,$41,$08,$00,$00,$50,$54       // $24ad  
    .byte $00,$08,$41,$2a,$9f,$22,$30,$00       // $24b5  
    .byte $00,$02,$41,$08,$0a,$00,$40,$05       // $24bd  
    .byte $80,$01,$41,$08,$0a,$00,$20,$35       // $24c5  
    .byte $40,$01,$41,$1c,$da,$22,$40,$00       // $24cd  
    .byte $00,$04,$81,$59,$00,$00,$00,$c6       // $24d5  
    .byte $00,$04,$41,$07,$df,$00,$00,$05       // $24dd  
    .byte $00,$02,$41,$4d,$8f,$33,$20,$00       // $24e5  
    .byte $20,$00,$41,$0a,$80,$00,$20,$e6       // $24ed  
    .byte $00,$0d,$41,$0f,$00,$00,$a0,$44       // $24f5  
    .byte $00,$0d,$41,$0f,$00,$00,$a0,$34       // $24fd  
    .byte $00,$0d,$41,$0f,$00,$00,$a0,$24       // $2505  
    .byte $00,$0d,$41,$0f,$00,$00,$a0,$54       // $250d  
    .byte $00,$04,$41,$0a,$0a,$00,$90,$55       // $2515  
    .byte $80,$08,$15,$0f,$ff,$00,$00,$03       // $251d  
    .byte $00,$04,$41,$9f,$ff,$13,$00,$00       // $2525  
    .byte $40,$00,$41,$0f,$ff,$11,$13,$00       // $252d  
    .byte $a0,$01,$41,$0d,$ff,$10,$10,$00       // $2535  
    .byte $a0,$0a,$15,$c0,$8d,$00,$00,$f6       // $253d  
    .byte $a0,$0a,$81,$08,$08,$00,$00,$01       // $2545  
    .byte $00,$06,$41,$0f,$0b,$00,$80,$c5       // $254d  
    .byte $00,$06,$15,$2f,$fd,$30,$00,$00       // $2555  
    .byte $00,$08,$43,$0f,$fd,$00,$00,$46       // $255d  
music_track_ptr_lo:
    .byte <(music_track_voice1)                 // $2565  
    .byte <(music_track_voice2)                 // $2566  
    .byte <(music_track_voice3)                 // $2567  
music_track_ptr_hi:
    .byte >(music_track_voice1)                 // $2568  
    .byte >(music_track_voice2)                 // $2569  
    .byte >(music_track_voice3)                 // $256a  
music_pattern_ptr_lo:
    .byte <(music_pattern_00)                   // $256b  
    .byte <(music_pattern_01)                   // $256c  
    .byte <(music_pattern_02)                   // $256d  
    .byte <(music_pattern_03)                   // $256e  
    .byte <(music_pattern_04)                   // $256f  
    .byte <(music_pattern_05)                   // $2570  
    .byte <(music_pattern_06)                   // $2571  
    .byte <(music_pattern_07)                   // $2572  
    .byte <(music_pattern_08)                   // $2573  
    .byte <(music_pattern_09)                   // $2574  
    .byte <(music_pattern_0a)                   // $2575  
    .byte <(music_pattern_0b)                   // $2576  
    .byte <(music_pattern_0c)                   // $2577  
    .byte <(music_pattern_0d)                   // $2578  
    .byte <(music_pattern_0e)                   // $2579  
    .byte <(music_pattern_0f)                   // $257a  
    .byte <(music_pattern_10)                   // $257b  
    .byte <(music_pattern_11)                   // $257c  
    .byte <(music_pattern_12)                   // $257d  
    .byte <(music_pattern_13)                   // $257e  
    .byte <(music_pattern_14)                   // $257f  
    .byte <(music_pattern_15)                   // $2580  
    .byte <(music_pattern_16)                   // $2581  
    .byte <(music_pattern_17)                   // $2582  
    .byte <(music_pattern_18)                   // $2583  
    .byte <(music_pattern_19)                   // $2584  
    .byte <(music_pattern_1a)                   // $2585  
    .byte <(music_pattern_1b)                   // $2586  
    .byte <(music_pattern_1c)                   // $2587  
    .byte <(music_pattern_1d)                   // $2588  
    .byte <(music_pattern_1e)                   // $2589  
    .byte <(music_pattern_1f)                   // $258a  
    .byte <(music_pattern_20)                   // $258b  
    .byte <(music_pattern_21)                   // $258c  
    .byte <(music_pattern_22)                   // $258d  
    .byte <(music_pattern_23)                   // $258e  
    .byte <(music_pattern_24)                   // $258f  
    .byte <(music_pattern_25)                   // $2590  
    .byte <(music_pattern_26)                   // $2591  
music_pattern_ptr_hi:
    .byte >(music_pattern_00)                   // $2592  
    .byte >(music_pattern_01)                   // $2593  
    .byte >(music_pattern_02)                   // $2594  
    .byte >(music_pattern_03)                   // $2595  
    .byte >(music_pattern_04)                   // $2596  
    .byte >(music_pattern_05)                   // $2597  
    .byte >(music_pattern_06)                   // $2598  
    .byte >(music_pattern_07)                   // $2599  
    .byte >(music_pattern_08)                   // $259a  
    .byte >(music_pattern_09)                   // $259b  
    .byte >(music_pattern_0a)                   // $259c  
    .byte >(music_pattern_0b)                   // $259d  
    .byte >(music_pattern_0c)                   // $259e  
    .byte >(music_pattern_0d)                   // $259f  
    .byte >(music_pattern_0e)                   // $25a0  
    .byte >(music_pattern_0f)                   // $25a1  
    .byte >(music_pattern_10)                   // $25a2  
    .byte >(music_pattern_11)                   // $25a3  
    .byte >(music_pattern_12)                   // $25a4  
    .byte >(music_pattern_13)                   // $25a5  
    .byte >(music_pattern_14)                   // $25a6  
    .byte >(music_pattern_15)                   // $25a7  
    .byte >(music_pattern_16)                   // $25a8  
    .byte >(music_pattern_17)                   // $25a9  
    .byte >(music_pattern_18)                   // $25aa  
    .byte >(music_pattern_19)                   // $25ab  
    .byte >(music_pattern_1a)                   // $25ac  
    .byte >(music_pattern_1b)                   // $25ad  
    .byte >(music_pattern_1c)                   // $25ae  
    .byte >(music_pattern_1d)                   // $25af  
    .byte >(music_pattern_1e)                   // $25b0  
    .byte >(music_pattern_1f)                   // $25b1  
    .byte >(music_pattern_20)                   // $25b2  
    .byte >(music_pattern_21)                   // $25b3  
    .byte >(music_pattern_22)                   // $25b4  
    .byte >(music_pattern_23)                   // $25b5  
    .byte >(music_pattern_24)                   // $25b6  
    .byte >(music_pattern_25)                   // $25b7  
    .byte >(music_pattern_26)                   // $25b8  
music_track_voice1:
    .byte $26,$1d,$1d,$1d,$1d,$09,$09,$09,$09,$09,$09,$09,$09,$09,$09,$09  // $25b9  
    .byte $09,$09,$09,$09,$09,$0b,$0b,$0b,$0b,$1a,$01,$05,$04,$03,$01,$05  // $25c9  
    .byte $04,$03,$01,$05,$04,$03,$01,$05,$04,$03,$0b,$0c,$0d,$0e,$0b,$0c  // $25d9  
    .byte $0d,$0e,$0c,$0c,$0e,$0e,$11,$11,$0d,$0d,$0b,$0b,$0e,$0e,$11,$11  // $25e9  
    .byte $0d,$0d,$1a,$01,$05,$04,$03,$01,$05,$04,$03,$01,$05,$04,$03,$01  // $25f9  
    .byte $05,$04,$03,$1a,$1f,$1f,$1f,$1f,$1f,$1f,$1f,$1f,$1f,$1f,$1f,$1f  // $2609  
    .byte $1b,$0b,$0c,$0d,$0e,$0b,$0c,$0d,$0e,$0c,$0c,$0e,$0e,$11,$11,$0d  // $2619  
    .byte $0d,$0b,$0b,$0e,$0e,$11,$11,$0d,$0d,$1a,$01,$05,$04,$03,$01,$05  // $2629  
    .byte $04,$03,$01,$05,$04,$03,$01,$05,$04,$03,$01,$05,$04,$03,$01,$05  // $2639  
    .byte $04,$03,$01,$05,$04,$03,$01,$05,$04,$03,$19,$25,$24,$ff  // $2649  
music_track_voice2:
    .byte $26,$26,$26,$0a,$0a,$0a,$0a,$0a,$0a,$0a,$0a,$02,$02,$02,$02,$02  // $2657  
    .byte $02,$02,$02,$02,$02,$02,$02,$1b,$02,$02,$02,$02,$02,$02,$02,$02  // $2667  
    .byte $02,$02,$02,$02,$02,$02,$02,$02,$10,$10,$10,$10,$10,$10,$10,$10  // $2677  
    .byte $13,$13,$14,$13,$13,$15,$15,$16,$16,$17,$17,$16,$16,$18,$1b,$02  // $2687  
    .byte $02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$1b  // $2697  
    .byte $20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$1a,$10,$10,$10  // $26a7  
    .byte $10,$10,$10,$10,$10,$13,$13,$14,$13,$13,$15,$15,$16,$16,$17,$17  // $26b7  
    .byte $16,$16,$18,$1b,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02  // $26c7  
    .byte $02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02  // $26d7  
    .byte $02,$02,$02,$02,$1a,$24,$24,$ff       // $26e7  
music_track_voice3:
    .byte $26,$1c,$1c,$1e,$08,$08,$08,$08,$08,$08,$08,$08,$19,$07,$06,$06  // $26ef  
    .byte $0f,$12,$19,$07,$06,$06,$19,$1d,$1d,$21,$08,$08,$08,$08,$19,$0f  // $26ff  
    .byte $12,$19,$07,$22,$22,$22,$1b,$23,$24,$ff  // $270f  
music_pattern_00:
    .byte $5f,$ff                               // $2719  
music_pattern_06:
    .byte $81,$05,$45,$01,$45,$01,$45,$01,$45,$01,$4c,$01,$4c,$01,$45,$01  // $271b  
    .byte $45,$01,$48,$01,$48,$01,$4c,$01,$4c,$01,$45,$01,$45,$01,$4c,$01  // $272b  
    .byte $4c,$01,$4f,$01,$4f,$01,$4f,$01,$4f,$01,$4f,$01,$4f,$01,$4d,$01  // $273b  
    .byte $4d,$01,$4d,$01,$4d,$01,$4d,$01,$4d,$01,$4c,$01,$4c,$01,$4c,$01  // $274b  
    .byte $4c,$01,$48,$01,$48,$01,$48,$01,$48,$01,$4d,$01,$4d,$01,$45,$01  // $275b  
    .byte $45,$01,$48,$01,$48,$01,$4d,$01,$4d,$01,$45,$01,$45,$01,$4d,$01  // $276b  
    .byte $4d,$01,$4a,$01,$4a,$01,$4a,$01,$4a,$01,$4a,$01,$4a,$01,$48,$01  // $277b  
    .byte $48,$01,$48,$01,$48,$01,$48,$01,$48,$01,$4a,$01,$4a,$01,$4a,$01  // $278b  
    .byte $4a,$ff                               // $279b  
music_pattern_07:
    .byte $8b,$06,$39,$0b,$3b,$07,$3c,$0b,$40,$0b,$3e,$07,$3c,$0b,$39,$0b  // $279d  
    .byte $3c,$07,$41,$07,$3e,$07,$3e,$03,$3c,$0b,$3e,$0b,$39,$0b,$3c,$07  // $27ad  
    .byte $40,$0b,$43,$0b,$41,$07,$40,$0b,$3c,$0b,$40,$07,$41,$07,$3e,$07  // $27bd  
    .byte $3e,$03,$3c,$0b,$3b,$ff               // $27cd  
music_pattern_0f:
    .byte $83,$03,$40,$83,$09,$40,$01,$3e,$03,$3c,$09,$39,$03,$37,$03,$39  // $27d3  
    .byte $83,$03,$40,$83,$09,$40,$01,$3e,$03,$3c,$01,$3e,$81,$0a,$3e,$01  // $27e3  
    .byte $3e,$01,$3e,$01,$3e,$01,$3e,$01,$3e,$01,$3e,$01,$3e,$83,$03,$40  // $27f3  
    .byte $83,$09,$3e,$01,$3c,$03,$3b,$09,$3c,$03,$3b,$03,$39,$1f,$37,$83  // $2803  
    .byte $03,$40,$83,$09,$40,$01,$3e,$03,$3c,$09,$39,$03,$3c,$03,$40,$83  // $2813  
    .byte $03,$40,$83,$09,$45,$01,$43,$03,$41,$05,$3e,$81,$0a,$3e,$01,$3e  // $2823  
    .byte $01,$3e,$01,$3e,$01,$3e,$01,$3e,$83,$03,$40,$83,$09,$43,$01,$41  // $2833  
    .byte $03,$40,$09,$41,$07,$43,$0d,$41,$11,$40,$ff  // $2843  
music_pattern_12:
    .byte $bf,$0c,$3e,$4f,$07,$40,$07,$41,$3f,$3c,$5f,$3f,$3c,$4f,$07,$3e  // $284e  
    .byte $07,$40,$1f,$3b,$9f,$0d,$37,$bf,$0c,$3c,$4f,$07,$40,$07,$41,$3f  // $285e  
    .byte $40,$5f,$3f,$41,$4f,$07,$43,$07,$45,$1f,$43,$9f,$0d,$37,$ff  // $286e  
music_pattern_19:
    .byte $83,$12,$39,$03,$39,$03,$39,$03,$39,$01,$39,$01,$39,$03,$39,$03  // $287d  
    .byte $39,$01,$39,$03,$39,$01,$39,$03,$39,$03,$39,$03,$39,$07,$39,$81  // $288d  
    .byte $0a,$40,$01,$3c,$01,$39,$01,$36,$ff   // $289d  
music_pattern_1a:
    .byte $83,$02,$15,$03,$15,$03,$15,$03,$15,$01,$15,$01,$15,$03,$15,$03  // $28a6  
    .byte $15,$01,$15,$03,$15,$01,$15,$03,$15,$03,$15,$03,$15,$07,$15,$81  // $28b6  
    .byte $04,$45,$01,$45,$01,$45,$01,$45,$ff   // $28c6  
music_pattern_1b:
    .byte $83,$00,$2d,$83,$13,$45,$03,$45,$83,$00,$2d,$01,$2d,$81,$13,$45  // $28cf  
    .byte $03,$45,$03,$45,$81,$00,$2d,$03,$2d,$81,$13,$45,$03,$43,$03,$43  // $28df  
    .byte $03,$43,$07,$40,$81,$00,$2d,$01,$2d,$01,$2d,$01,$2d,$ff  // $28ef  
music_pattern_02:
    .byte $83,$00,$2d,$81,$01,$34,$01,$39,$81,$04,$45,$81,$01,$3c,$01,$40  // $28fd  
    .byte $81,$00,$2d,$03,$2d,$81,$01,$39,$01,$39,$81,$04,$46,$81,$01,$40  // $290d  
    .byte $01,$3e,$01,$3c,$ff                   // $291d  
music_pattern_0a:
    .byte $83,$00,$2d,$43,$81,$04,$45,$43,$81,$00,$2d,$03,$2d,$43,$81,$04  // $2922  
    .byte $46,$45,$ff                           // $2932  
music_pattern_10:
    .byte $83,$00,$2d,$81,$0b,$28,$01,$2b,$81,$04,$45,$81,$0b,$30,$01,$2d  // $2935  
    .byte $81,$00,$2d,$03,$2d,$81,$0b,$2b,$01,$2d,$81,$04,$46,$81,$0b,$30  // $2945  
    .byte $01,$2d,$01,$2b,$ff                   // $2955  
music_pattern_13:
    .byte $83,$00,$2d,$83,$0e,$39,$81,$04,$45,$83,$0e,$39,$81,$00,$2d,$03  // $295a  
    .byte $2d,$81,$0e,$39,$01,$2d,$81,$04,$46,$83,$0e,$39,$01,$39,$ff  // $296a  
music_pattern_14:
    .byte $83,$00,$2d,$83,$10,$37,$81,$04,$45,$83,$10,$37,$81,$00,$2d,$03  // $2979  
    .byte $2d,$81,$10,$37,$01,$2d,$81,$04,$46,$83,$10,$37,$01,$37,$83,$00  // $2989  
    .byte $2d,$83,$0f,$37,$81,$04,$45,$83,$0f,$37,$81,$00,$2d,$03,$2d,$81  // $2999  
    .byte $0f,$37,$01,$2d,$81,$04,$46,$83,$0f,$37,$01,$37,$ff  // $29a9  
music_pattern_15:
    .byte $83,$00,$2d,$83,$0e,$3b,$81,$04,$45,$83,$0e,$3b,$81,$00,$2d,$03  // $29b6  
    .byte $2d,$81,$0e,$3b,$01,$2d,$81,$04,$46,$83,$0e,$3b,$01,$3b,$ff  // $29c6  
music_pattern_16:
    .byte $83,$00,$2d,$83,$0f,$3c,$81,$04,$45,$83,$0f,$3c,$81,$00,$2d,$03  // $29d5  
    .byte $2d,$81,$0f,$3c,$01,$2d,$81,$04,$46,$83,$0f,$3c,$01,$3c,$ff  // $29e5  
music_pattern_17:
    .byte $83,$00,$2d,$83,$11,$3c,$81,$04,$45,$83,$11,$3c,$81,$00,$2d,$03  // $29f4  
    .byte $2d,$81,$11,$3c,$01,$2d,$81,$04,$46,$83,$11,$3c,$01,$3c,$ff  // $2a04  
music_pattern_18:
    .byte $83,$00,$2d,$83,$10,$3e,$81,$04,$45,$83,$10,$3e,$81,$00,$2d,$03  // $2a13  
    .byte $2d,$81,$10,$3e,$01,$2d,$81,$04,$46,$83,$10,$3e,$01,$3e,$83,$00  // $2a23  
    .byte $2d,$83,$0f,$3e,$81,$04,$45,$83,$0f,$3e,$81,$00,$2d,$03,$2d,$81  // $2a33  
    .byte $0f,$3e,$01,$2d,$81,$04,$46,$83,$0f,$3e,$01,$37,$ff  // $2a43  
music_pattern_01:
    .byte $81,$02,$21,$01,$15,$01,$1f,$01,$21,$83,$03,$38,$83,$02,$21,$01  // $2a50  
    .byte $21,$01,$15,$01,$1f,$01,$21,$83,$03,$38,$83,$02,$21,$ff  // $2a60  
music_pattern_03:
    .byte $81,$02,$26,$01,$1a,$01,$24,$01,$26,$83,$03,$38,$83,$02,$26,$01  // $2a6e  
    .byte $26,$01,$1a,$01,$24,$01,$26,$83,$03,$38,$83,$02,$26,$ff  // $2a7e  
music_pattern_04:
    .byte $81,$02,$1d,$01,$11,$01,$1c,$01,$1d,$83,$03,$38,$83,$02,$1d,$01  // $2a8c  
    .byte $1d,$01,$11,$01,$1c,$01,$1d,$83,$03,$38,$83,$02,$1d,$ff  // $2a9c  
music_pattern_05:
    .byte $81,$02,$24,$01,$18,$01,$23,$01,$24,$83,$03,$38,$83,$02,$24,$01  // $2aaa  
    .byte $24,$01,$18,$01,$23,$01,$24,$83,$03,$38,$83,$02,$24,$ff  // $2aba  
music_pattern_08:
    .byte $83,$08,$48,$a1,$07,$34,$01,$40,$21,$34,$01,$40,$21,$30,$01,$3c  // $2ac8  
    .byte $03,$2d,$83,$08,$48,$a1,$07,$37,$01,$39,$21,$43,$01,$45,$ff  // $2ad8  
music_pattern_09:
    .byte $47,$87,$03,$38,$47,$07,$38,$ff       // $2ae7  
music_pattern_0b:
    .byte $83,$02,$15,$03,$15,$83,$03,$38,$41,$81,$02,$15,$07,$15,$83,$03  // $2aef  
    .byte $38,$43,$ff                           // $2aff  
music_pattern_0c:
    .byte $83,$02,$1a,$03,$1a,$83,$03,$38,$41,$81,$02,$1a,$07,$1a,$83,$03  // $2b02  
    .byte $38,$43,$ff                           // $2b12  
music_pattern_0d:
    .byte $83,$02,$13,$03,$13,$83,$03,$38,$41,$81,$02,$13,$07,$13,$83,$03  // $2b15  
    .byte $38,$43,$ff                           // $2b25  
music_pattern_0e:
    .byte $83,$02,$18,$03,$18,$83,$03,$38,$41,$81,$02,$18,$07,$18,$83,$03  // $2b28  
    .byte $38,$43,$ff                           // $2b38  
music_pattern_11:
    .byte $83,$02,$1d,$03,$1d,$83,$03,$38,$41,$81,$02,$1d,$07,$1d,$83,$03  // $2b3b  
    .byte $38,$43,$ff                           // $2b4b  
music_pattern_1c:
    .byte $a3,$14,$21,$bb,$15,$21,$9f,$16,$21,$a3,$14,$24,$bb,$15,$24,$9f  // $2b4e  
    .byte $16,$24,$a3,$14,$1d,$bb,$15,$1d,$9f,$16,$1d,$a3,$14,$1a,$bb,$15  // $2b5e  
    .byte $1a,$9f,$16,$1a,$ff                   // $2b6e  
music_pattern_1e:
    .byte $a3,$14,$18,$bb,$15,$18,$9f,$16,$18,$a3,$14,$15,$bb,$15,$15,$9f  // $2b73  
    .byte $16,$15,$ff                           // $2b83  
music_pattern_1d:
    .byte $bf,$17,$39,$5f,$ff                   // $2b86  
music_pattern_1f:
    .byte $81,$00,$2d,$83,$03,$38,$81,$00,$2d,$83,$03,$38,$81,$00,$2d,$01  // $2b8b  
    .byte $2d,$01,$2d,$83,$03,$38,$81,$00,$2d,$83,$03,$38,$81,$00,$2d,$01  // $2b9b  
    .byte $2d,$01,$2d,$83,$03,$38,$81,$00,$2d,$83,$03,$38,$81,$00,$2d,$01  // $2bab  
    .byte $2d,$01,$2d,$83,$03,$38,$81,$00,$2d,$83,$03,$38,$01,$38,$01,$38  // $2bbb  
    .byte $ff                                   // $2bcb  
music_pattern_20:
    .byte $81,$18,$55,$81,$04,$45,$81,$18,$45,$01,$55,$81,$04,$45,$81,$18  // $2bcc  
    .byte $50,$01,$45,$01,$45,$01,$55,$81,$04,$45,$81,$18,$45,$01,$55,$81  // $2bdc  
    .byte $04,$45,$81,$18,$50,$01,$45,$01,$45,$01,$55,$81,$04,$45,$81,$18  // $2bec  
    .byte $45,$01,$55,$81,$04,$45,$81,$18,$50,$01,$45,$01,$45,$01,$55,$81  // $2bfc  
    .byte $04,$45,$81,$18,$45,$01,$55,$81,$04,$45,$81,$18,$50,$81,$04,$45  // $2c0c  
    .byte $01,$45,$ff                           // $2c1c  
music_pattern_21:
    .byte $bf,$15,$45,$bf,$16,$45,$7f,$5f,$bf,$15,$48,$bf,$16,$48,$7f,$5f  // $2c1f  
    .byte $bf,$15,$47,$9f,$16,$47,$bf,$15,$40,$9f,$16,$40,$bf,$15,$39,$bf  // $2c2f  
    .byte $16,$39,$7f,$5f,$ff                   // $2c3f  
music_pattern_22:
    .byte $8b,$19,$51,$0b,$53,$07,$54,$0b,$58,$0b,$56,$07,$54,$0b,$51,$0b  // $2c44  
    .byte $54,$07,$59,$07,$56,$07,$56,$03,$54,$0b,$56,$0b,$51,$0b,$54,$07  // $2c54  
    .byte $58,$0b,$5b,$0b,$59,$07,$58,$0b,$54,$0b,$58,$07,$59,$07,$56,$07  // $2c64  
    .byte $56,$03,$54,$0b,$53,$ff               // $2c74  
music_pattern_23:
    .byte $bf,$1a,$15,$7f,$7f,$5f,$ff           // $2c7a  
music_pattern_24:
    .byte $bf,$1a,$39,$7f,$7f,$5f,$ff           // $2c81  
music_pattern_25:
    .byte $bf,$1b,$0c,$7f,$7f,$5f,$ff           // $2c88  
music_pattern_26:
    .byte $bf,$1a,$45,$7f,$7f,$5f,$ff           // $2c8f  
music_silence:
    lda music_silenced_flag                     // $2c96  stop all three voices once
    beq L2c9c                                   // $2c99  
    rts                                         // $2c9b  
L2c9c:
    lda #$00                                    // $2c9c  
    sta SID_V1_CTRL                             // $2c9e  
    sta SID_V2_CTRL                             // $2ca1  
    sta SID_V3_CTRL                             // $2ca4  
    lda #$01                                    // $2ca7  
    sta music_silenced_flag                     // $2ca9  
    rts                                         // $2cac  
music_unused:
// thrusty-levels: $2CAD-$2FFF is not used by the music (it held leftover
// bytes). The title screen QR code lives here; the rest stays free.
    #import "title_qr.asm"
music_free:
    .errorif * > $3000, "title_qr.asm is " + (* - $3000) + " bytes too big for $2CAD-$2FFF"
    .fill $3000 - *, $ff
