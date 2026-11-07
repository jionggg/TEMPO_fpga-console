// TEMPO_layout.vh | v5 | 06 Nov 2026 SGT
// v5 (Ji Yong): progress bar 3 px thick (ribbon now rows 0..12), lane labels under the
//     white line, SYNC'D line, menu song list; font codes 6 bits wide (H B Y ' > <);
//     drum lane 0 is the hi-hat lane on screen (TEMPO_defs still calls it DRUM_CRASH).
// v4 (Ji Yong): scene screens (menu, countdown, pause, results), hit sprites under the
//     white line, dragging hit colour; letters A L N Q U; dark grade shades.
// v3 (Ji Yong): merged feat/ui-renderer: ribbon geometry, judgement colours, font codes.
// v2: LOOKAHEAD_MS renamed TILE_LOOKAHEAD_MS. TEMPO_defs.vh already has a LOOKAHEAD_MS
//     (Meiyi's 1500 ms spawn time); screen_layout includes both files, so the same
//     name twice was a 'already declared' compile error.
// params that screen_layout, tile_calc and ui_renderer need. ie the hit line, tile height and colours


// Geometry (96 x 64 pixels; x 0,...,95 left to right, y 0,...,63 top to bottom)
localparam RIBBON_H = 13;     // ribbon is rows y = 0,...,12
localparam HIT_Y    = 55;     // a tile's bottom row touches this line y, at its event time
localparam PAD_Y0   = 57;     // pads are rows y = 57,...,63
localparam TILE_H   = 8;      // tiles are 8 rows tall

// Fall speed: 2^SHIFT ms per pixel. SHIFT = 5 -> 32 ms per pixel.
localparam SHIFT             = 5;
localparam TILE_LOOKAHEAD_MS = (HIT_Y - RIBBON_H) << SHIFT;   // 42 px * 32 ms = 1344 ms of warning
localparam LATE_MS           = 300;                      // a missed tile keeps falling this long

// Ribbon (rows 0..12), top to bottom:
//   rows 0..2  song progress bar (3 px)
//   rows 4..10 text: drummer's score (left) | xN (green, centre) | pianist's score (right)
//              on both screens; my own score in my colour, my teammate's in grey
//   row 12     divider line, doubles as the green buff fuse
// (sized like x [6:0] and y [5:0], so they plug straight into char_cell's ports)
// Each character is 6 px wide: 5 px of glyph + 1 px gap.
localparam       PROG_H  = 3;        // progress bar rows 0 .. PROG_H-1
localparam       FUSE_Y  = 12;       // divider / fuse row (last ribbon row)
localparam [5:0] TEXT_Y  = 6'd4;     // top row of the ribbon text (5x7 font: rows 4..10)
localparam [6:0] DRM_X   = 7'd1;     // drummer's score, 5 digits: x = 1..29
localparam [6:0] PNO_X   = 7'd66;    // pianist's score, 5 digits: x = 66..94
localparam [6:0] MULT_X  = 7'd43;    // "x3": x = 43..53, centred on the screen
localparam [5:0] WORD_Y  = 6'd28;    // judgement word rows 28..34, in the middle of the field
localparam [5:0] SYNC_Y  = 6'd18;    // SYNC'D line rows 18..24, just above the word
localparam [6:0] SYNC_X  = 7'd31;    // SYNC'D is 6 * 6 - 1 = 35 px wide: x = 31..65, centred
localparam BUFF_MS = 3000;    // a full buff lasts 3 s: the fuse is full width at 3000 ms left
localparam FX_MS   = 250;     // judgement word, SYNC'D, hit sprite, gold line, score flash: 250 ms

// Under the white line (rows 56..63): hit sprites and the dragging hit colour
localparam SPRITE_Y0 = 56;    // sprites are 16 x 8: rows 56..63
localparam [5:0] LABEL_Y = 6'd57;    // lane labels (C..G, HAT / SNARE / BASS): rows 57..63
localparam MARK_MS   = 520;   // a hit's colour is kept until it has scrolled off the bottom
localparam [1:0] MARK_WRONG = 2'd3;  // hit_mark grade code for a wrong press (grades use 0..2)

// Colours (RGB565)
localparam [15:0] BLACK   = 16'h0000,
                  WHITE   = 16'hFFFF,
                  NAVY    = 16'h0010,
                  DIVIDER = 16'h2104,
                  PAD     = 16'h18E3,
                  CYAN    = 16'h07FF,   // piano tiles, piano's own score
                  ORANGE  = 16'hFD00,   // drum tiles, drum's own score, SYNC'D (with a GOOD; results)
                  GREY    = 16'h8410,   // teammate's score (medium grey)
                  BAR     = 16'hC618,   // song progress bar, played part (light grey)
                  GREEN   = 16'h07E0,   // PERFECT, and the buff (xN + fuse)
                  YELLOW  = 16'hFFE0,   // GOOD
                  RED     = 16'hF800,   // MISS
                  GOLD    = 16'hFEA0,   // hit line flash on a good sync
                  LABEL   = 16'hC618,   // lane labels under the white line (light grey)
                  BURGUNDY = 16'h8004,  // a wrong press under the white line (#800020)
                  DK_GREEN  = 16'h03E0, // half-bright shades: the part of a hit that
                  DK_YELLOW = 16'h7BE0, //   lies outside its target tile (early / late)
                  DK_RED    = 16'h7800;

// Font character codes (font_rom), 6 bits since v5 (5 bits had only 32 codes).
// Digits 0..9 use their own value as the code, so a decimal digit d is code {2'b00, d}.
localparam [5:0] CH_X  = 6'd10,   // small "x" for the multiplier
                 CH_SP = 6'd11,   // blank
                 CH_P  = 6'd12,
                 CH_E  = 6'd13,
                 CH_R  = 6'd14,
                 CH_F  = 6'd15,
                 CH_C  = 6'd16,
                 CH_T  = 6'd17,
                 CH_G  = 6'd18,
                 CH_O  = 6'd19,
                 CH_D  = 6'd20,
                 CH_M  = 6'd21,
                 CH_I  = 6'd22,
                 CH_S  = 6'd23,
                 CH_A  = 6'd24,
                 CH_L  = 6'd25,
                 CH_N  = 6'd26,
                 CH_Q  = 6'd27,
                 CH_U  = 6'd28,
                 CH_H  = 6'd29,
                 CH_B  = 6'd30,
                 CH_Y  = 6'd31,
                 CH_AP = 6'd32,   // apostrophe, for SYNC'D
                 CH_GT = 6'd33,   // >  (menu cursor)
                 CH_LT = 6'd34,   // <
                 CH_SL = 6'd35;   // /  (results: SYNC'D 02/03)
