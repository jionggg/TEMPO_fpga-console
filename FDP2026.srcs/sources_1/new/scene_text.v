`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// scene_text - the words on the MENU, COUNTDOWN, PAUSED and RESULTS screens (Ji Yong)
//
// One copy per screen, pure combinational logic. The OLED asks about one pixel at a
// time, so this works like a librarian answering one question at a time:
//   1. which text line is this pixel's row in (depends on the game state)?
//   2. which character of that line is this pixel's column in?
//   3. look that one character up in font_rom, and pick the pixel out of it.
// Lines marked "x2" are drawn twice the size: every font pixel becomes a 2 x 2 block.
//
//   MENU       TEMPO (x2) / PIANO or DRUMS / EASY, NORMAL, HARD / PRESS START (blinking)
//              The chosen song (Meiyi's song_select: btnU up, btnD down) is drawn in my
//              colour between > <, the other two in grey. btnC starts it.
//   COUNTDOWN  3, 2, 1, GO: x4 white digits with a 1-px outline in my colour (big_*)
//   PAUSED     PAUSED (x2) / U RESUME / D QUIT       (screen_layout dims the field)
//   RESULTS    RESULTS / SYNC'D nn/tt / PERFECT nn / GOOD nn / MISS nn / PRESS C (blinking)
//              tt = how many duets the song had, in grey (the ribbon above still shows
//              both final scores)
//
// Also in this file: lane_label, the C..G and HAT / SNARE / BASS names under the
// white line.
//////////////////////////////////////////////////////////////////////////////////

module scene_text #(parameter SCREEN = 0) (     // SCREEN: 0 = piano, 1 = drum
    input  [6:0]  x,
    input  [5:0]  y,
    input  [2:0]  state,            // game_state
    input  [1:0]  countdown_num,    // 3, 2, 1, then 0 = GO
    input         blink,            // toggles every 500 ms: blinking lines show when 1
    input  [7:0]  perfect_d,        // my PERFECT count as 2 decimal digits: [7:4] tens, [3:0] ones
    input  [7:0]  good_d,
    input  [7:0]  miss_d,
    input  [7:0]  sync_d,           // SYNC'D count (both players), 2 decimal digits
    input  [7:0]  sync_total_d,     // how many duets were judged (= duets in the song)
    input  [1:0]  song_select,      // menu choice: 0 EASY, 1 NORMAL, 2 HARD
    output reg    text_on,          // this pixel is part of a word
    output reg [15:0] text_colour,
    output        big_on,           // this pixel is part of the big countdown (fill or outline)
    output [15:0] big_colour
    );

    `include "TEMPO_defs.vh"       // ST_*
    `include "TEMPO_layout.vh"     // colours, CH_ codes

    localparam [15:0] MY_COLOUR = (SCREEN == 0) ? CYAN : ORANGE;

    // ---- 1. which line? ------------------------------------------------------------
    localparam [3:0] L_NONE = 0, L_TITLE = 1, L_ROLE = 2, L_PRESS = 3,
                     L_PAUSED = 4, L_RESUME = 5, L_QUIT = 6,
                     L_RESULTS = 7, L_PERF = 8, L_GOOD = 9, L_MISS = 10, L_PRESSC = 11,
                     L_SYNC = 12, L_SONG0 = 13, L_SONG1 = 14, L_SONG2 = 15;

    reg [3:0]  line;
    reg [6:0]  x0;                  // the line's leftmost column
    reg [5:0]  y0;                  // the line's top row
    reg        big;                 // 1 = drawn x2

    always @(*) begin
        line = L_NONE;  x0 = 7'd0;  y0 = 6'd0;  big = 1'b0;
        case (state)
            ST_MENU: begin
                // "> EASY <" and "> HARD <" are 8 characters (47 px), "> NORMAL <" is 10 (59 px)
                if      (y >=  2 && y < 16) begin line = L_TITLE;   x0 = 19; y0 =  2; big = 1; end
                else if (y >= 19 && y < 26) begin line = L_ROLE;    x0 = 34; y0 = 19;          end
                else if (y >= 29 && y < 36) begin line = L_SONG0;   x0 = 24; y0 = 29;          end
                else if (y >= 38 && y < 45) begin line = L_SONG1;   x0 = 18; y0 = 38;          end
                else if (y >= 47 && y < 54) begin line = L_SONG2;   x0 = 24; y0 = 47;          end
                else if (y >= 57)           begin line = L_PRESS;   x0 = 15; y0 = 57;          end
            end
            ST_PAUSED: begin
                if      (y >= 17 && y < 31) begin line = L_PAUSED;  x0 = 13; y0 = 17; big = 1; end
                else if (y >= 35 && y < 42) begin line = L_RESUME;  x0 = 24; y0 = 35;          end
                else if (y >= 44 && y < 51) begin line = L_QUIT;    x0 = 30; y0 = 44;          end
            end
            ST_RESULTS: begin
                // the ribbon takes rows 0..12, so RESULTS is normal size to fit 5 lines below it.
                // Stat lines: label at characters 0..6, count at 8..9; SYNC'D adds /tt at 10..12
                // ("SYNC'D  02/03" is 13 characters = 77 px, so the lines start at x = 9)
                if      (y >= 15 && y < 22) begin line = L_RESULTS; x0 = 28; y0 = 15;          end
                else if (y >= 25 && y < 32) begin line = L_SYNC;    x0 = 9;  y0 = 25;          end
                else if (y >= 33 && y < 40) begin line = L_PERF;    x0 = 9;  y0 = 33;          end
                else if (y >= 41 && y < 48) begin line = L_GOOD;    x0 = 9;  y0 = 41;          end
                else if (y >= 49 && y < 56) begin line = L_MISS;    x0 = 9;  y0 = 49;          end
                else if (y >= 57)           begin line = L_PRESSC;  x0 = 27; y0 = 57;          end
            end
            default: ;
        endcase
    end

    // ---- 2. which character, and where inside it? ------------------------------------
    // A normal character is 6 px wide (5 glyph + 1 gap); an x2 character is 12 px.
    wire [6:0] rx  = x - x0;                        // columns from the line's left edge
    wire [5:0] ry  = y - y0;                        // rows from the line's top
    wire [3:0] idx = big ? rx / 12 : rx / 6;        // character number in the line
    wire [3:0] cx  = big ? (rx % 12) >> 1 : rx % 6; // column inside it, 0..4 (5 = gap)
    wire [2:0] row = big ? ry >> 1 : ry;            // row inside it, 0..6

    // the menu cursor: > and < only on the chosen song's line
    wire [5:0] gt0 = (song_select == 2'd0) ? CH_GT : CH_SP;
    wire [5:0] lt0 = (song_select == 2'd0) ? CH_LT : CH_SP;
    wire [5:0] gt1 = (song_select == 2'd1) ? CH_GT : CH_SP;
    wire [5:0] lt1 = (song_select == 2'd1) ? CH_LT : CH_SP;
    wire [5:0] gt2 = (song_select == 2'd2) ? CH_GT : CH_SP;
    wire [5:0] lt2 = (song_select == 2'd2) ? CH_LT : CH_SP;

    // the character codes of each line
    reg [5:0] code;
    always @(*) begin
        code = CH_SP;
        case (line)
            L_TITLE:   case (idx) 0: code = CH_T; 1: code = CH_E; 2: code = CH_M; 3: code = CH_P;
                                  4: code = CH_O; default: code = CH_SP; endcase
            L_ROLE:    if (SCREEN == 0)
                           case (idx) 0: code = CH_P; 1: code = CH_I; 2: code = CH_A; 3: code = CH_N;
                                      4: code = CH_O; default: code = CH_SP; endcase
                       else
                           case (idx) 0: code = CH_D; 1: code = CH_R; 2: code = CH_U; 3: code = CH_M;
                                      4: code = CH_S; default: code = CH_SP; endcase
            L_SONG0:   case (idx) 0: code = gt0;  2: code = CH_E; 3: code = CH_A; 4: code = CH_S;
                                  5: code = CH_Y; 7: code = lt0;  default: code = CH_SP; endcase
            L_SONG1:   case (idx) 0: code = gt1;  2: code = CH_N; 3: code = CH_O; 4: code = CH_R;
                                  5: code = CH_M; 6: code = CH_A; 7: code = CH_L; 9: code = lt1;
                                  default: code = CH_SP; endcase
            L_SONG2:   case (idx) 0: code = gt2;  2: code = CH_H; 3: code = CH_A; 4: code = CH_R;
                                  5: code = CH_D; 7: code = lt2;  default: code = CH_SP; endcase
            L_PRESS:   case (idx) 0: code = CH_P; 1: code = CH_R; 2: code = CH_E; 3: code = CH_S;
                                  4: code = CH_S; 6: code = CH_S; 7: code = CH_T; 8: code = CH_A;
                                  9: code = CH_R; 10: code = CH_T; default: code = CH_SP; endcase
            L_PAUSED:  case (idx) 0: code = CH_P; 1: code = CH_A; 2: code = CH_U; 3: code = CH_S;
                                  4: code = CH_E; 5: code = CH_D; default: code = CH_SP; endcase
            L_RESUME:  case (idx) 0: code = CH_U; 2: code = CH_R; 3: code = CH_E; 4: code = CH_S;
                                  5: code = CH_U; 6: code = CH_M; 7: code = CH_E; default: code = CH_SP; endcase
            L_QUIT:    case (idx) 0: code = CH_D; 2: code = CH_Q; 3: code = CH_U; 4: code = CH_I;
                                  5: code = CH_T; default: code = CH_SP; endcase
            L_RESULTS: case (idx) 0: code = CH_R; 1: code = CH_E; 2: code = CH_S; 3: code = CH_U;
                                  4: code = CH_L; 5: code = CH_T; 6: code = CH_S; default: code = CH_SP; endcase
            L_PERF:    case (idx) 0: code = CH_P; 1: code = CH_E; 2: code = CH_R; 3: code = CH_F;
                                  4: code = CH_E; 5: code = CH_C; 6: code = CH_T;
                                  8: code = {2'b00, perfect_d[7:4]}; 9: code = {2'b00, perfect_d[3:0]};
                                  default: code = CH_SP; endcase
            L_GOOD:    case (idx) 0: code = CH_G; 1: code = CH_O; 2: code = CH_O; 3: code = CH_D;
                                  8: code = {2'b00, good_d[7:4]}; 9: code = {2'b00, good_d[3:0]};
                                  default: code = CH_SP; endcase
            L_MISS:    case (idx) 0: code = CH_M; 1: code = CH_I; 2: code = CH_S; 3: code = CH_S;
                                  8: code = {2'b00, miss_d[7:4]}; 9: code = {2'b00, miss_d[3:0]};
                                  default: code = CH_SP; endcase
            L_SYNC:    case (idx) 0: code = CH_S; 1: code = CH_Y; 2: code = CH_N; 3: code = CH_C;
                                  4: code = CH_AP; 5: code = CH_D;
                                  8: code = {2'b00, sync_d[7:4]}; 9: code = {2'b00, sync_d[3:0]};
                                  10: code = CH_SL;
                                  11: code = {2'b00, sync_total_d[7:4]}; 12: code = {2'b00, sync_total_d[3:0]};
                                  default: code = CH_SP; endcase
            L_PRESSC:  case (idx) 0: code = CH_P; 1: code = CH_R; 2: code = CH_E; 3: code = CH_S;
                                  4: code = CH_S; 6: code = CH_C; default: code = CH_SP; endcase
            default:   code = CH_SP;
        endcase
    end

    // ---- 3. one font lookup -----------------------------------------------------------
    wire [34:0] glyph;
    font_rom font (.code(code), .glyph(glyph));

    wire ink = (line != L_NONE) && (x >= x0) && (cx < 5) && glyph[34 - (row * 5 + cx)];

    // blinking lines are hidden while blink = 0
    wire hidden = ((line == L_PRESS) || (line == L_PRESSC)) && !blink;

    always @(*) begin
        text_on = ink && !hidden;
        case (line)
            L_TITLE, L_RESULTS: text_colour = MY_COLOUR;
            L_RESUME, L_QUIT:   text_colour = BAR;
            L_SONG0:            text_colour = (song_select == 2'd0) ? MY_COLOUR : GREY;
            L_SONG1:            text_colour = (song_select == 2'd1) ? MY_COLOUR : GREY;
            L_SONG2:            text_colour = (song_select == 2'd2) ? MY_COLOUR : GREY;
            L_SYNC:             text_colour = (idx >= 10) ? GREY : (idx >= 8) ? WHITE : YELLOW;
            L_PERF:             text_colour = (idx >= 8) ? WHITE : GREEN;
            L_GOOD:             text_colour = (idx >= 8) ? WHITE : ORANGE;
            L_MISS:             text_colour = (idx >= 8) ? WHITE : RED;
            default:            text_colour = WHITE;
        endcase
    end

    // ---- the big countdown: 3, 2, 1, GO at x4 with an outline ------------------------
    // A pixel is "fill" if the big text covers it, and "outline" if it is not covered
    // but one of its 8 neighbours is. big_ink answers "is (px, py) covered?"; we ask it
    // 9 times: for this pixel and each neighbour. Coordinates are shifted by +1 so that
    // x - 1 never goes negative.
    wire [7:0] px = {1'b0, x} + 8'd1;
    wire [7:0] py = {2'b00, y} + 8'd1;
    wire c, n, s, e, w, ne, nw, se, sw;
    big_ink b_c  (.px(px),        .py(py),        .num(countdown_num), .ink(c));
    big_ink b_n  (.px(px),        .py(py - 8'd1), .num(countdown_num), .ink(n));
    big_ink b_s  (.px(px),        .py(py + 8'd1), .num(countdown_num), .ink(s));
    big_ink b_e  (.px(px + 8'd1), .py(py),        .num(countdown_num), .ink(e));
    big_ink b_w  (.px(px - 8'd1), .py(py),        .num(countdown_num), .ink(w));
    big_ink b_ne (.px(px + 8'd1), .py(py - 8'd1), .num(countdown_num), .ink(ne));
    big_ink b_nw (.px(px - 8'd1), .py(py - 8'd1), .num(countdown_num), .ink(nw));
    big_ink b_se (.px(px + 8'd1), .py(py + 8'd1), .num(countdown_num), .ink(se));
    big_ink b_sw (.px(px - 8'd1), .py(py + 8'd1), .num(countdown_num), .ink(sw));

    wire outline = !c && (n | s | e | w | ne | nw | se | sw);
    wire in_cd   = (state == ST_COUNTDOWN);

    assign big_on     = in_cd && (c || outline);
    assign big_colour = c ? WHITE : MY_COLOUR;

endmodule


//////////////////////////////////////////////////////////////////////////////////
// big_ink - is (px, py) covered by the big countdown text? (coordinates are +1)
//   num 3, 2, 1: one digit at x 38..57;  num 0: "GO" at x 26..69;  rows 18..45
//   Every font pixel is a 4 x 4 block; characters are 24 px apart (20 glyph + 4 gap).
//////////////////////////////////////////////////////////////////////////////////

module big_ink (
    input  [7:0] px,
    input  [7:0] py,
    input  [1:0] num,
    output       ink
    );

    `include "TEMPO_layout.vh"     // CH_G, CH_O

    wire       go = (num == 2'd0);
    wire [7:0] x0 = go ? 8'd27 : 8'd39;            // 26 or 38, +1
    wire [7:0] y0 = 8'd19;                         // 18, +1
    wire [7:0] w  = go ? 8'd44 : 8'd20;            // total width

    wire in_box = (px >= x0) && (px < x0 + w) && (py >= y0) && (py < y0 + 8'd28);

    wire [7:0] rx  = px - x0;
    wire [7:0] ry  = py - y0;
    wire       idx = (rx >= 8'd24);                // second character (the O of GO)?
    wire [7:0] cxx = idx ? rx - 8'd24 : rx;        // column inside the character, 0..23
    wire [2:0] col = cxx >> 2;                     // font column 0..5 (5 = gap)
    wire [2:0] row = ry >> 2;                      // font row 0..6

    wire [5:0] code = go ? (idx ? CH_O : CH_G) : {4'b0000, num};

    wire [34:0] glyph;
    font_rom font (.code(code), .glyph(glyph));

    assign ink = in_box && (col < 5) && glyph[34 - (row * 5 + col)];

endmodule


//////////////////////////////////////////////////////////////////////////////////
// lane_label - the name of each lane, under the white line (rows 57..63)
//   piano: C  D  E  F  G, one letter in the middle of each 17-px lane
//   drums: HAT (hi-hat)  SNARE  BASS. SNARE is 29 px in a 28-px lane, so it starts
//          1 px into the black gap on its left.
// A lane's label is hidden while that lane shows its hit sprite (hide[lane] = 1),
// like a key whose printed letter is covered by your finger.
//////////////////////////////////////////////////////////////////////////////////

module lane_label #(parameter SCREEN = 0) (     // SCREEN: 0 = piano, 1 = drum
    input  [6:0] x,
    input  [5:0] y,
    input  [4:0] hide,              // bit L = lane L's label is covered by its sprite
    output       on                 // this pixel is part of a label
    );

    `include "TEMPO_layout.vh"     // LABEL_Y, CH_ codes

    // which lane's label is this column in, and where does that label start?
    reg       in_label;
    reg [2:0] ln;
    reg [6:0] x0;
    always @(*) begin
        in_label = 1'b0;  ln = 3'd0;  x0 = 7'd0;
        if (SCREEN == 0) begin
            // lanes start at 1, 20, 39, 58, 77 and are 17 px wide: letter at lane + 6
            if      (x >=  7 && x <= 11) begin in_label = 1'b1; ln = 3'd0; x0 = 7'd7;  end
            else if (x >= 26 && x <= 30) begin in_label = 1'b1; ln = 3'd1; x0 = 7'd26; end
            else if (x >= 45 && x <= 49) begin in_label = 1'b1; ln = 3'd2; x0 = 7'd45; end
            else if (x >= 64 && x <= 68) begin in_label = 1'b1; ln = 3'd3; x0 = 7'd64; end
            else if (x >= 83 && x <= 87) begin in_label = 1'b1; ln = 3'd4; x0 = 7'd83; end
        end else begin
            // lanes 2..29, 34..61, 66..93: HAT 17 px, SNARE 29 px, BASS 23 px, centred
            if      (x >=  7 && x <= 23) begin in_label = 1'b1; ln = 3'd0; x0 = 7'd7;  end
            else if (x >= 33 && x <= 61) begin in_label = 1'b1; ln = 3'd1; x0 = 7'd33; end
            else if (x >= 68 && x <= 90) begin in_label = 1'b1; ln = 3'd2; x0 = 7'd68; end
        end
    end

    wire [6:0] rx  = x - x0;                // columns from the label's left edge
    wire [2:0] idx = rx / 6;                // character number in the label
    wire [2:0] cx  = rx % 6;                // column inside it (5 = the gap)
    wire [5:0] ry  = y - LABEL_Y;           // row inside it, 0..6

    reg [5:0] code;
    always @(*) begin
        code = CH_SP;
        if (SCREEN == 0) begin
            case (ln)
                3'd0: code = CH_C;
                3'd1: code = CH_D;
                3'd2: code = CH_E;
                3'd3: code = CH_F;
                default: code = CH_G;
            endcase
        end else begin
            case (ln)
                3'd0:    case (idx) 0: code = CH_H; 1: code = CH_A; 2: code = CH_T;
                                    default: code = CH_SP; endcase
                3'd1:    case (idx) 0: code = CH_S; 1: code = CH_N; 2: code = CH_A; 3: code = CH_R;
                                    4: code = CH_E; default: code = CH_SP; endcase
                default: case (idx) 0: code = CH_B; 1: code = CH_A; 2: code = CH_S; 3: code = CH_S;
                                    default: code = CH_SP; endcase
            endcase
        end
    end

    wire [34:0] glyph;
    font_rom font (.code(code), .glyph(glyph));

    assign on = in_label && (y >= LABEL_Y) && (cx < 5) && !hide[ln] &&
                glyph[34 - (ry[2:0] * 5 + cx)];

endmodule
