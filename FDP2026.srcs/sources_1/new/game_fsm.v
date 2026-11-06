`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 30.10.2026 01:54:40
// Design Name: 
// Module Name: game_fsm
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
// ============================================================================

// ============================================================================
// TEMPO game FSM (top module)
//
//   MENU(0) --btnC--> COUNTDOWN(1) --3,2,1,GO done--> PLAYING(2) --song end--> RESULTS(4)
//   PLAYING <--btnU--> PAUSED(3)        PAUSED --btnD--> MENU
//   RESULTS --btnC--> MENU              rst (any state) --> MENU
//
// Structure
//   ms_tick          1 kHz enable pulse from the 100 MHz clock (shared)
//   btn_debounce x3  btnC / btnU / btnD -> clean one-clock press pulses
//   countdown_timer  3, 2, 1, GO  (num goes to the OLED; done -> PLAYING)
//   ms_timer         the song timer, song_time_ms
//   song_select      independent 0..2 menu selection; up/down navigate in MENU
//   Block 1          the ONLY place game_state changes (state transitions)
//   Block 2          decides what every output does in each state
//
// Everything runs on the single 100 MHz clk. The 1 kHz tick is a clock ENABLE.
//
// Song timer per state: MENU cleared | COUNTDOWN held at 0 | PLAYING counts
//                       PAUSED frozen | RESULTS stopped at song_len_ms
// countdown_num: 3, 2, 1, 0 = GO. Only meaningful while game_state == ST_COUNTDOWN.
// new_game:      one-clock pulse as the game leaves MENU; clear scores/combos.
// ============================================================================
module game_fsm #(
    parameter integer CLKS_PER_MS = 100_000,   // 100 MHz / 1000 (use a small value in sim)
    parameter integer DEBOUNCE_MS = 10
)(
    input  wire        clk,
    input  wire        rst,

    input  wire        btnC,
    input  wire        btnU,
    input  wire        btnD,

    input  wire [17:0] song_len_ms,        // from pattern_gen

    output reg  [2:0]  game_state,
    output reg  [1:0]  song_select,        // 0=existing chart, 1/2=placeholder charts
    output wire [17:0] song_time_ms,
    output wire [1:0]  countdown_num,
    output wire        countdown_go,
    output reg         new_game
);
    `include "TEMPO_defs.vh"

    // ------------------------------------------------------------------------
    // Sub-modules
    // ------------------------------------------------------------------------
    wire tick_1ms;
    wire c_press, u_press, d_press;
    wire c_lvl,   u_lvl,   d_lvl;
    wire cd_done;

    // outputs of Block 2 that drive the timers
    reg  cd_enable;
    reg  song_clear;
    reg  song_run;

    ms_tick #(.CLKS_PER_MS(CLKS_PER_MS)) u_ms_tick (
        .clk(clk), .rst(rst), .tick(tick_1ms)
    );

    btn_debounce #(.DEBOUNCE_MS(DEBOUNCE_MS)) u_deb_c (
        .clk(clk), .rst(rst), .tick_1ms(tick_1ms), .btn_in(btnC),
        .pressed(c_press), .level(c_lvl));
    btn_debounce #(.DEBOUNCE_MS(DEBOUNCE_MS)) u_deb_u (
        .clk(clk), .rst(rst), .tick_1ms(tick_1ms), .btn_in(btnU),
        .pressed(u_press), .level(u_lvl));
    btn_debounce #(.DEBOUNCE_MS(DEBOUNCE_MS)) u_deb_d (
        .clk(clk), .rst(rst), .tick_1ms(tick_1ms), .btn_in(btnD),
        .pressed(d_press), .level(d_lvl));

    countdown_timer u_countdown (
        .clk(clk), .rst(rst), .tick_1ms(tick_1ms),
        .enable(cd_enable),
        .num(countdown_num), .go(countdown_go), .done(cd_done)
    );

    ms_timer #(.WIDTH(18)) u_song_timer (
        .clk(clk), .rst(rst), .tick_1ms(tick_1ms),
        .clear(song_clear), .run(song_run),
        .count(song_time_ms)
    );

    wire song_end = (song_time_ms >= song_len_ms);

    // ------------------------------------------------------------------------
    // Block 1: state transitions (the only writer of game_state)
    // ------------------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            game_state <= ST_MENU;
        end else begin
            case (game_state)
                ST_MENU:      if (c_press)      game_state <= ST_COUNTDOWN;

                ST_COUNTDOWN: if (cd_done)      game_state <= ST_PLAYING;

                ST_PLAYING: begin
                    if (song_end)      game_state <= ST_RESULTS;
                    else if (u_press) game_state <= ST_PAUSED;
                end

                ST_PAUSED:    if (u_press)      game_state <= ST_PLAYING;  // resume wins
                              else if (d_press) game_state <= ST_MENU;     // if both pressed

                ST_RESULTS:   if (c_press)      game_state <= ST_MENU;

                default:                        game_state <= ST_MENU;
            endcase
        end
    end

    // Song selection is separate from game_state. Up/down navigate the three
    // menu choices; selecting an option does not create a new game state.
    // btnC has priority if it is pressed in the same cycle as up/down.
    always @(posedge clk or posedge rst) begin
        if (rst)
            song_select <= SONG_1;
        else if (game_state == ST_MENU && !c_press) begin
            if (u_press && !d_press)
                song_select <= (song_select == SONG_1) ? SONG_3 : song_select - 2'd1;
            else if (d_press && !u_press)
                song_select <= (song_select == SONG_3) ? SONG_1 : song_select + 2'd1;
        end
    end

    // ------------------------------------------------------------------------
    // Block 2: what the outputs do in each state
    // ------------------------------------------------------------------------
    always @* begin
        cd_enable  = 1'b0;
        song_clear = 1'b0;
        song_run   = 1'b0;
        new_game   = 1'b0;

        case (game_state)
            ST_MENU: begin
                song_clear = 1'b1;              // timer cleared to 0
                new_game   = c_press;           // leaving MENU: fresh game
            end
            ST_COUNTDOWN: begin
                cd_enable  = 1'b1;              // run 3, 2, 1, GO
                song_clear = 1'b1;              // song timer held at 0
            end
            ST_PLAYING: begin
                song_run   = !song_end;         // counts up every ms
            end
            ST_PAUSED: begin
                // everything frozen
            end
            ST_RESULTS: begin
                // song timer stopped at song_len_ms
            end
            default: ;
        endcase
    end
endmodule

