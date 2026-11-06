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
//   MENU       TEMPO (x2) / PIANO or DRUMS / PRESS START (blinking)
//   COUNTDOWN  3, 2, 1, GO: x4 white digits with a 1-px outline in my colour (big_*)
//   PAUSED     PAUSED (x2) / U RESUME / D QUIT       (screen_layout dims the field)
//   RESULTS    RESULTS (x2) / PERFECT nn / GOOD nn / MISS nn / PRESS C (blinking)
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
                     L_RESULTS = 7, L_PERF = 8, L_GOOD = 9, L_MISS = 10, L_PRESSC = 11;

    reg [3:0]  line;
    reg [6:0]  x0;                  // the line's leftmost column
    reg [5:0]  y0;                  // the line's top row
    reg        big;                 // 1 = drawn x2

    always @(*) begin
        line = L_NONE;  x0 = 7'd0;  y0 = 6'd0;  big = 1'b0;
        case (state)
            ST_MENU: begin
                if      (y >= 12 && y < 26) begin line = L_TITLE;   x0 = 19; y0 = 12; big = 1; end
                else if (y >= 31 && y < 38) begin line = L_ROLE;    x0 = 34; y0 = 31;          end
                else if (y >= 47 && y < 54) begin line = L_PRESS;   x0 = 15; y0 = 47;          end
            end
            ST_PAUSED: begin
                if      (y >= 20 && y < 34) begin line = L_PAUSED;  x0 = 13; y0 = 20; big = 1; end
                else if (y >= 40 && y < 47) begin line = L_RESUME;  x0 = 24; y0 = 40;          end
                else if (y >= 49 && y < 56) begin line = L_QUIT;    x0 = 30; y0 = 49;          end
            end
            ST_RESULTS: begin
                if      (y >= 13 && y < 27) begin line = L_RESULTS; x0 = 7;  y0 = 13; big = 1; end
                else if (y >= 31 && y < 38) begin line = L_PERF;    x0 = 15; y0 = 31;          end
                else if (y >= 39 && y < 46) begin line = L_GOOD;    x0 = 15; y0 = 39;          end
                else if (y >= 47 && y < 54) begin line = L_MISS;    x0 = 15; y0 = 47;          end
                else if (y >= 56 && y < 63) begin line = L_PRESSC;  x0 = 27; y0 = 56;          end
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

    // the character codes of each line
    reg [4:0] code;
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
                                  9: code = {1'b0, perfect_d[7:4]}; 10: code = {1'b0, perfect_d[3:0]};
                                  default: code = CH_SP; endcase
            L_GOOD:    case (idx) 0: code = CH_G; 1: code = CH_O; 2: code = CH_O; 3: code = CH_D;
                                  9: code = {1'b0, good_d[7:4]}; 10: code = {1'b0, good_d[3:0]};
                                  default: code = CH_SP; endcase
            L_MISS:    case (idx) 0: code = CH_M; 1: code = CH_I; 2: code = CH_S; 3: code = CH_S;
                                  9: code = {1'b0, miss_d[7:4]}; 10: code = {1'b0, miss_d[3:0]};
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
            L_PERF:             text_colour = (idx >= 9) ? WHITE : GREEN;
            L_GOOD:             text_colour = (idx >= 9) ? WHITE : YELLOW;
            L_MISS:             text_colour = (idx >= 9) ? WHITE : RED;
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

    wire [4:0] code = go ? (idx ? CH_O : CH_G) : {3'b000, num};

    wire [34:0] glyph;
    font_rom font (.code(code), .glyph(glyph));

    assign ink = in_box && (col < 5) && glyph[34 - (row * 5 + col)];

endmodule
