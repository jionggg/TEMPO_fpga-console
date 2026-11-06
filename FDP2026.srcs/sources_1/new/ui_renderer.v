`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// ui_renderer - the ribbon and the judgement word for ONE screen (Ji Yong)
//
// Pure combinational logic, like tile_calc: the OLED asks about pixel (x, y)
// and this answers straight away. screen_layout decides which layer wins.
//
// Ribbon (rows 0..12):
//   rows 0..2   song progress bar: light grey up to how far through the song we are
//   rows 4..10  drummer's score (left)   xN (green, centre)   pianist's score (right)
//               The same on both screens. My own score is in my colour, my teammate's
//               in grey. A score turns green for 250 ms each time it goes up.
//   row 12      divider line; while a buff is on, a green fuse burns down towards the centre
//
// Judgement word (rows 28..34): PERFECT / GOOD / MISS in the grade colour, on a
// small black box so it stays readable over passing tiles.
// SYNC'D (rows 18..24, just above): shown on both screens after a good duet,
// green if both players were PERFECT, orange if either was GOOD.
//////////////////////////////////////////////////////////////////////////////////

module ui_renderer #(parameter SCREEN = 0) (     // SCREEN: 0 = piano, 1 = drum
    input  [6:0]  x,                // pixel column, 0..95
    input  [5:0]  y,                // pixel row, 0..63
    input  [17:0] song_time_ms,     // how far into the song we are
    input  [17:0] song_len_ms,      // how long the song is
    input  [19:0] drm_digits,       // drummer's score as 5 decimal digits ([19:16] = ten-thousands)
    input  [19:0] pno_digits,       // pianist's score, the same way
    input         drm_flash,        // drummer's score just went up: draw it green
    input         pno_flash,        // pianist's score just went up: draw it green
    input  [3:0]  mult,             // team multiplier: 1 = no buff, 2..9 = buffed
    input  [11:0] buff_ms_left,     // ms left on the buff, 0..3000
    input         fx_on,            // my latest judgement is still showing
    input  [1:0]  fx_grade,         // its grade
    input         sync_on,          // SYNC'D is showing
    input         sync_perfect,     // ... and both players were PERFECT
    output reg [15:0] ribbon_colour,    // the colour of this pixel if it is in the ribbon
    output        word_on,          // 1 = a word (or its black box) covers this pixel
    output [15:0] word_colour,      // ... in this colour
    output [15:0] fx_colour         // the grade's colour
    );

    `include "TEMPO_defs.vh"       // GRADE_PERFECT, GRADE_GOOD
    `include "TEMPO_layout.vh"     // geometry, colours, CH_ codes

    // colours of the two scores: my own in my colour, my teammate's in grey
    localparam [15:0] DRM_COLOUR = (SCREEN == 1) ? ORANGE : GREY;
    localparam [15:0] PNO_COLOUR = (SCREEN == 0) ? CYAN   : GREY;

    // ---- 1. Song progress bar (rows 0..2) -----------------------------------------
    // Lit if x / 96 < song_time / song_len. Dividing is expensive in hardware, so
    // cross-multiply instead: x * song_len < song_time * 96.
    wire prog_lit = (x * song_len_ms) < (song_time_ms * 96);

    // ---- 2. Buff fuse (row 12) -----------------------------------------------------
    // The lit part is centred and shrinks towards the middle as the buff runs out.
    // from_mid = how many columns this pixel is from the centre line (0..47).
    // Lit if from_mid / 48 < buff_ms_left / BUFF_MS, cross-multiplied again.
    wire [5:0] from_mid = (x < 48) ? (47 - x) : (x - 48);
    wire       fuse_lit = (from_mid * BUFF_MS) < (buff_ms_left * 48);

    // ---- 3. Ribbon text (rows TEXT_Y .. TEXT_Y+6) -----------------------------------
    // One char_cell per character; each says "this pixel is ink" or not.
    // A decimal digit d is drawn with code {2'b00, d}.

    // drummer's score, 5 digits starting at DRM_X (left)
    wire t0, t1, t2, t3, t4;
    char_cell ct0 (.x(x), .y(y), .x0(DRM_X),           .y0(TEXT_Y), .code({2'b00, drm_digits[19:16]}), .on(t0));
    char_cell ct1 (.x(x), .y(y), .x0(DRM_X + 7'd6),    .y0(TEXT_Y), .code({2'b00, drm_digits[15:12]}), .on(t1));
    char_cell ct2 (.x(x), .y(y), .x0(DRM_X + 7'd12),   .y0(TEXT_Y), .code({2'b00, drm_digits[11:8]}),  .on(t2));
    char_cell ct3 (.x(x), .y(y), .x0(DRM_X + 7'd18),   .y0(TEXT_Y), .code({2'b00, drm_digits[7:4]}),   .on(t3));
    char_cell ct4 (.x(x), .y(y), .x0(DRM_X + 7'd24),   .y0(TEXT_Y), .code({2'b00, drm_digits[3:0]}),   .on(t4));
    wire drm_on = t0 | t1 | t2 | t3 | t4;

    // pianist's score, 5 digits starting at PNO_X (right)
    wire s0, s1, s2, s3, s4;
    char_cell cs0 (.x(x), .y(y), .x0(PNO_X),           .y0(TEXT_Y), .code({2'b00, pno_digits[19:16]}), .on(s0));
    char_cell cs1 (.x(x), .y(y), .x0(PNO_X + 7'd6),    .y0(TEXT_Y), .code({2'b00, pno_digits[15:12]}), .on(s1));
    char_cell cs2 (.x(x), .y(y), .x0(PNO_X + 7'd12),   .y0(TEXT_Y), .code({2'b00, pno_digits[11:8]}),  .on(s2));
    char_cell cs3 (.x(x), .y(y), .x0(PNO_X + 7'd18),   .y0(TEXT_Y), .code({2'b00, pno_digits[7:4]}),   .on(s3));
    char_cell cs4 (.x(x), .y(y), .x0(PNO_X + 7'd24),   .y0(TEXT_Y), .code({2'b00, pno_digits[3:0]}),   .on(s4));
    wire pno_on = s0 | s1 | s2 | s3 | s4;

    // multiplier "xN", only while buffed (mult 2..9)
    wire buffed = (mult >= 2);
    wire mx, mn;
    char_cell cmx (.x(x), .y(y), .x0(MULT_X),          .y0(TEXT_Y), .code(CH_X),          .on(mx));
    char_cell cmn (.x(x), .y(y), .x0(MULT_X + 7'd6),   .y0(TEXT_Y), .code({2'b00, mult}), .on(mn));
    wire mult_on = buffed && (mx | mn);

    // ---- 4. Ribbon colour: first test that says yes paints the pixel ----------------
    always @(*) begin
        if      (y < PROG_H)  ribbon_colour = prog_lit ? BAR : DIVIDER;
        else if (y == FUSE_Y) ribbon_colour = (buffed && fuse_lit) ? GREEN : DIVIDER;
        else if (drm_on)      ribbon_colour = drm_flash ? GREEN : DRM_COLOUR;
        else if (pno_on)      ribbon_colour = pno_flash ? GREEN : PNO_COLOUR;
        else if (mult_on)     ribbon_colour = GREEN;
        else                  ribbon_colour = NAVY;
    end

    // ---- 5. Judgement word ---------------------------------------------------------
    assign fx_colour = (fx_grade == GRADE_PERFECT) ? GREEN  :
                       (fx_grade == GRADE_GOOD)    ? YELLOW :
                                                     RED;

    // The 7 letters for this grade (GOOD and MISS use 4, the rest blank)
    reg [5:0] w0, w1, w2, w3, w4, w5, w6;
    always @(*) begin
        if (fx_grade == GRADE_PERFECT) begin
            w0 = CH_P; w1 = CH_E; w2 = CH_R; w3 = CH_F; w4 = CH_E; w5 = CH_C; w6 = CH_T;
        end else if (fx_grade == GRADE_GOOD) begin
            w0 = CH_G; w1 = CH_O; w2 = CH_O; w3 = CH_D; w4 = CH_SP; w5 = CH_SP; w6 = CH_SP;
        end else begin
            w0 = CH_M; w1 = CH_I; w2 = CH_S; w3 = CH_S; w4 = CH_SP; w5 = CH_SP; w6 = CH_SP;
        end
    end

    // Centre the word: PERFECT is 7 * 6 - 1 = 41 px wide, GOOD / MISS are 23 px.
    // (96 - 41) / 2 = 27.5 -> 28,   (96 - 23) / 2 = 36.5 -> 37
    wire [6:0] word_x0 = (fx_grade == GRADE_PERFECT) ? 7'd28 : 7'd37;
    wire [6:0] word_w  = (fx_grade == GRADE_PERFECT) ? 7'd41 : 7'd23;

    wire k0, k1, k2, k3, k4, k5, k6;
    char_cell cw0 (.x(x), .y(y), .x0(word_x0),         .y0(WORD_Y), .code(w0), .on(k0));
    char_cell cw1 (.x(x), .y(y), .x0(word_x0 + 7'd6),  .y0(WORD_Y), .code(w1), .on(k1));
    char_cell cw2 (.x(x), .y(y), .x0(word_x0 + 7'd12), .y0(WORD_Y), .code(w2), .on(k2));
    char_cell cw3 (.x(x), .y(y), .x0(word_x0 + 7'd18), .y0(WORD_Y), .code(w3), .on(k3));
    char_cell cw4 (.x(x), .y(y), .x0(word_x0 + 7'd24), .y0(WORD_Y), .code(w4), .on(k4));
    char_cell cw5 (.x(x), .y(y), .x0(word_x0 + 7'd30), .y0(WORD_Y), .code(w5), .on(k5));
    char_cell cw6 (.x(x), .y(y), .x0(word_x0 + 7'd36), .y0(WORD_Y), .code(w6), .on(k6));
    wire letter_on = k0 | k1 | k2 | k3 | k4 | k5 | k6;

    // Black box 2 px bigger than the word on every side.
    // (x + 2 >= word_x0) is the same as (x >= word_x0 - 2), written so nothing goes negative.
    wire in_box = (x + 2 >= word_x0) && (x <= word_x0 + word_w + 1) &&
                  (y + 2 >= WORD_Y)  && (y <= WORD_Y + 8);

    // ---- 6. SYNC'D, one line above the word ------------------------------------------
    wire q0, q1, q2, q3, q4, q5;
    char_cell cq0 (.x(x), .y(y), .x0(SYNC_X),          .y0(SYNC_Y), .code(CH_S),  .on(q0));
    char_cell cq1 (.x(x), .y(y), .x0(SYNC_X + 7'd6),   .y0(SYNC_Y), .code(CH_Y),  .on(q1));
    char_cell cq2 (.x(x), .y(y), .x0(SYNC_X + 7'd12),  .y0(SYNC_Y), .code(CH_N),  .on(q2));
    char_cell cq3 (.x(x), .y(y), .x0(SYNC_X + 7'd18),  .y0(SYNC_Y), .code(CH_C),  .on(q3));
    char_cell cq4 (.x(x), .y(y), .x0(SYNC_X + 7'd24),  .y0(SYNC_Y), .code(CH_AP), .on(q4));
    char_cell cq5 (.x(x), .y(y), .x0(SYNC_X + 7'd30),  .y0(SYNC_Y), .code(CH_D),  .on(q5));
    wire sync_letter = q0 | q1 | q2 | q3 | q4 | q5;

    // its black box: SYNC'D is 35 px wide, plus 2 px on every side
    wire in_sbox = (x + 2 >= SYNC_X) && (x <= SYNC_X + 7'd36) &&
                   (y + 2 >= SYNC_Y) && (y <= SYNC_Y + 8);
    wire sync_here = sync_on && in_sbox;

    wire [15:0] sync_colour = sync_perfect ? GREEN : ORANGE;

    assign word_on     = (fx_on && in_box) || sync_here;
    assign word_colour = sync_here ? (sync_letter ? sync_colour : BLACK) :
                                     (letter_on   ? fx_colour   : BLACK);

endmodule
