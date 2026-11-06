`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// ui_renderer - the ribbon and the judgement word for ONE screen (Ji Yong)
//
// Pure combinational logic, like tile_calc: the OLED asks about pixel (x, y)
// and this answers straight away. screen_layout decides which layer wins.
//
// Ribbon (rows 0..10):
//   row 0      song progress bar: light grey up to how far through the song we are
//   rows 2..8  teammate's score (grey, left)   xN (green, centre)   my score (my colour, right)
//   row 10     divider line; while a buff is on, a green fuse burns down towards the centre
//
// Judgement word (rows 28..34): PERFECT / GOOD / MISS in the grade colour, on a
// small black box so it stays readable over passing tiles.
//
// "My" depends on SCREEN: on the piano screen, my score is the piano score.
//////////////////////////////////////////////////////////////////////////////////

module ui_renderer #(parameter SCREEN = 0) (     // SCREEN: 0 = piano, 1 = drum
    input  [6:0]  x,                // pixel column, 0..95
    input  [5:0]  y,                // pixel row, 0..63
    input  [17:0] song_time_ms,     // how far into the song we are
    input  [17:0] song_len_ms,      // how long the song is
    input  [19:0] my_digits,        // my score as 5 decimal digits ([19:16] = ten-thousands)
    input  [19:0] mate_digits,      // my teammate's score, the same way
    input  [3:0]  mult,             // team multiplier: 1 = no buff, 2..9 = buffed
    input  [11:0] buff_ms_left,     // ms left on the buff, 0..3000
    input         fx_on,            // my latest judgement is still showing
    input  [1:0]  fx_grade,         // its grade
    output reg [15:0] ribbon_colour,    // the colour of this pixel if it is in the ribbon
    output        word_on,          // 1 = the judgement word (or its black box) covers this pixel
    output [15:0] word_colour,      // ... in this colour
    output [15:0] fx_colour         // the grade's colour (screen_layout also uses it for the pad)
    );

    `include "TEMPO_defs.vh"       // GRADE_PERFECT, GRADE_GOOD
    `include "TEMPO_layout.vh"     // geometry, colours, CH_ codes

    localparam [15:0] MY_COLOUR = (SCREEN == 0) ? CYAN : ORANGE;

    // ---- 1. Song progress bar (row 0) --------------------------------------------
    // Lit if x / 96 < song_time / song_len. Dividing is expensive in hardware, so
    // cross-multiply instead: x * song_len < song_time * 96.
    wire prog_lit = (x * song_len_ms) < (song_time_ms * 96);

    // ---- 2. Buff fuse (row 10) -----------------------------------------------------
    // The lit part is centred and shrinks towards the middle as the buff runs out.
    // from_mid = how many columns this pixel is from the centre line (0..47).
    // Lit if from_mid / 48 < buff_ms_left / BUFF_MS, cross-multiplied again.
    wire [5:0] from_mid = (x < 48) ? (47 - x) : (x - 48);
    wire       fuse_lit = (from_mid * BUFF_MS) < (buff_ms_left * 48);

    // ---- 3. Ribbon text (rows TEXT_Y .. TEXT_Y+6) -----------------------------------
    // One char_cell per character; each says "this pixel is ink" or not.
    // A decimal digit d is drawn with code {1'b0, d}.

    // teammate's score, 5 digits starting at MATE_X
    wire t0, t1, t2, t3, t4;
    char_cell ct0 (.x(x), .y(y), .x0(MATE_X),          .y0(TEXT_Y), .code({1'b0, mate_digits[19:16]}), .on(t0));
    char_cell ct1 (.x(x), .y(y), .x0(MATE_X + 7'd6),   .y0(TEXT_Y), .code({1'b0, mate_digits[15:12]}), .on(t1));
    char_cell ct2 (.x(x), .y(y), .x0(MATE_X + 7'd12),  .y0(TEXT_Y), .code({1'b0, mate_digits[11:8]}),  .on(t2));
    char_cell ct3 (.x(x), .y(y), .x0(MATE_X + 7'd18),  .y0(TEXT_Y), .code({1'b0, mate_digits[7:4]}),   .on(t3));
    char_cell ct4 (.x(x), .y(y), .x0(MATE_X + 7'd24),  .y0(TEXT_Y), .code({1'b0, mate_digits[3:0]}),   .on(t4));
    wire mate_on = t0 | t1 | t2 | t3 | t4;

    // my score, 5 digits starting at MINE_X
    wire s0, s1, s2, s3, s4;
    char_cell cs0 (.x(x), .y(y), .x0(MINE_X),          .y0(TEXT_Y), .code({1'b0, my_digits[19:16]}), .on(s0));
    char_cell cs1 (.x(x), .y(y), .x0(MINE_X + 7'd6),   .y0(TEXT_Y), .code({1'b0, my_digits[15:12]}), .on(s1));
    char_cell cs2 (.x(x), .y(y), .x0(MINE_X + 7'd12),  .y0(TEXT_Y), .code({1'b0, my_digits[11:8]}),  .on(s2));
    char_cell cs3 (.x(x), .y(y), .x0(MINE_X + 7'd18),  .y0(TEXT_Y), .code({1'b0, my_digits[7:4]}),   .on(s3));
    char_cell cs4 (.x(x), .y(y), .x0(MINE_X + 7'd24),  .y0(TEXT_Y), .code({1'b0, my_digits[3:0]}),   .on(s4));
    wire mine_on = s0 | s1 | s2 | s3 | s4;

    // multiplier "xN", only while buffed (mult 2..9)
    wire buffed = (mult >= 2);
    wire mx, mn;
    char_cell cmx (.x(x), .y(y), .x0(MULT_X),          .y0(TEXT_Y), .code(CH_X),         .on(mx));
    char_cell cmn (.x(x), .y(y), .x0(MULT_X + 7'd6),   .y0(TEXT_Y), .code({1'b0, mult}), .on(mn));
    wire mult_on = buffed && (mx | mn);

    // ---- 4. Ribbon colour: first test that says yes paints the pixel ----------------
    always @(*) begin
        if      (y == PROG_Y) ribbon_colour = prog_lit ? BAR : DIVIDER;
        else if (y == FUSE_Y) ribbon_colour = (buffed && fuse_lit) ? GREEN : DIVIDER;
        else if (mine_on)     ribbon_colour = MY_COLOUR;
        else if (mate_on)     ribbon_colour = GREY;
        else if (mult_on)     ribbon_colour = GREEN;
        else                  ribbon_colour = NAVY;
    end

    // ---- 5. Judgement word ---------------------------------------------------------
    assign fx_colour = (fx_grade == GRADE_PERFECT) ? GREEN  :
                       (fx_grade == GRADE_GOOD)    ? YELLOW :
                                                     RED;

    // The 7 letters for this grade (GOOD and MISS use 4, the rest blank)
    reg [4:0] w0, w1, w2, w3, w4, w5, w6;
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

    assign word_on     = fx_on && in_box;
    assign word_colour = letter_on ? fx_colour : BLACK;

endmodule
