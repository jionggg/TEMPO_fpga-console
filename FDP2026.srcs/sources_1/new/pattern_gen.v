`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 30.10.2026 02:31:01
// Design Name: 
// Module Name: pattern_gen
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

module pattern_gen (
    input  wire        clk,
    input  wire        rst,
    input  wire        new_game,
    input  wire        play_enable,
    input  wire [1:0]  song_select,
    input  wire [17:0] song_time_ms,

    // Separate judgement IDs are required because piano and drum hits are
    // evaluated independently. NO_JUDGEMENT_ID means no new hit occurred.
    input  wire [5:0]  pno_judged_id,
    input  wire [5:0]  drm_judged_id,

    // Independent expected piano event.
    output wire        pno_exp_valid,
    output wire [5:0]  pno_exp_id,
    output wire [2:0]  pno_exp_lane,
    output wire [17:0] pno_exp_time_ms,

    // Independent expected drum event.
    output wire        drm_exp_valid,
    output wire [5:0]  drm_exp_id,
    output wire [2:0]  drm_exp_lane,
    output wire [17:0] drm_exp_time_ms,

    // One-clock tile spawn pulses (for the OLED). time_ms is the HIT time.
    output reg         pno_ev_valid,
    output reg  [5:0]  pno_ev_id,
    output reg  [2:0]  pno_ev_lane,
    output reg [17:0]  pno_ev_time_ms,

    output reg         drm_ev_valid,
    output reg  [5:0]  drm_ev_id,
    output reg  [2:0]  drm_ev_lane,
    output reg [17:0]  drm_ev_time_ms,

    output wire [17:0] song_len_ms
);
    `include "TEMPO_defs.vh"

    // Song 0 is Hot Cross Buns, song 1 is Lightly Row, and song 2 is Ode to Joy 
    reg [6:0] selected_event_count;
    reg [17:0] selected_song_length;
    always @* begin
        case (song_select)
            2'd1: begin
                selected_event_count = S1_TOTAL_NOTES;
                selected_song_length = S1_LENGTH_MS;
            end
            2'd2: begin
                selected_event_count = S2_TOTAL_NOTES;
                selected_song_length = S2_LENGTH_MS;
            end
            default: begin
                selected_event_count = S0_TOTAL_NOTES;
                selected_song_length = S0_LENGTH_MS;
            end
        endcase
    end
    assign song_len_ms = selected_song_length;

    // ------------------------------------------------------------------------
    // Song ROM and field decoding.
    // ------------------------------------------------------------------------
    reg  [5:0]  rom_addr;
    wire [31:0] rom0_data, rom1_data, rom2_data;
    reg  [31:0] rom_data;
    reg  [31:0] rom_data_q = 32'd0;      

    song_rom u_song0 (
        .addr(rom_addr),
        .event_data(rom0_data)
    );

    song_rom_2 u_song1 (
        .addr(rom_addr),
        .event_data(rom1_data)
    );

    song_rom_3 u_song2 (
        .addr(rom_addr),
        .event_data(rom2_data)
    );

    always @* begin
        case (song_select)
            2'd1:    rom_data = rom1_data;
            2'd2:    rom_data = rom2_data;
            default: rom_data = rom0_data;
        endcase
    end

    always @(posedge clk) rom_data_q <= rom_data;

    wire [17:0] rom_time_ms = {2'b00, rom_data_q[31:16]};
    wire [1:0]  rom_type    = rom_data_q[15:14];
    wire [3:0]  rom_piano   = rom_data_q[13:10];
    wire [3:0]  rom_drum    = rom_data_q[9:6];
    wire [5:0]  rom_id      = rom_data_q[5:0];

    wire rom_piano_valid = (rom_type == EVENT_PIANO) ||
                           (rom_type == EVENT_DUET);
    wire rom_drum_valid  = (rom_type == EVENT_DRUM) ||
                           (rom_type == EVENT_DUET);

    // The ROM stores the shared lane codes (NOTE_C..NOTE_G = 0..4) directly.
    wire [2:0] rom_piano_lane = rom_piano[2:0];

    // The ROM stores the shared drum lane codes from TEMPO_defs.vh directly
    // (DRUM_CRASH / DRUM_SNARE / DRUM_KICK; DRUM_NONE = no drum in this event).
    // No conversion or randomisation occurs.
    wire [2:0] rom_drum_lane = rom_drum[2:0];

    // ------------------------------------------------------------------------
    // Look-ahead scheduling.
    // ------------------------------------------------------------------------
    reg [17:0] last_song_time_ms;
    reg [1:0]  song_select_q;

    wire song_time_changed = (song_time_ms != last_song_time_ms);
    wire rewound           = (song_time_ms < last_song_time_ms);
    wire schedule_step     = song_time_changed && play_enable;
    wire event_missed      = (rom_time_ms < song_time_ms);
    wire event_in_window   = (rom_time_ms >= song_time_ms) &&
                             ((rom_time_ms - song_time_ms) <= LOOKAHEAD_MS);
    wire event_present     = rom_piano_valid || rom_drum_valid;

    // ------------------------------------------------------------------------
    // Independent piano expected-event FIFO.
    // ------------------------------------------------------------------------
    wire        pno_queue_full;
    wire        pno_queue_head_valid;
    wire [17:0] pno_queue_head_time;
    wire [5:0]  pno_queue_head_id;
    wire        pno_queue_head_is_drum;
    wire [3:0]  pno_queue_head_note;

    // ------------------------------------------------------------------------
    // Independent drum expected-event FIFO.
    // ------------------------------------------------------------------------
    wire        drm_queue_full;
    wire        drm_queue_head_valid;
    wire [17:0] drm_queue_head_time;
    wire [5:0]  drm_queue_head_id;
    wire        drm_queue_head_is_drum;
    wire [3:0]  drm_queue_head_note;

    // A ROM entry advances only when every FIFO needed by that entry has room.
    // This is important for duet entries, which push into both FIFOs.
    wire schedule_valid = schedule_step &&
                           event_in_window &&
                           event_present &&
                           (!rom_piano_valid || !pno_queue_full) &&
                           (!rom_drum_valid  || !drm_queue_full);

    wire pno_queue_push = schedule_valid && rom_piano_valid;
    wire drm_queue_push = schedule_valid && rom_drum_valid;

    // ------------------------------------------------------------------------
    // Independent judgement tracking.
    // ------------------------------------------------------------------------
    reg [5:0] pno_judged_id_seen;
    reg [5:0] drm_judged_id_seen;
    reg       pno_judged_id_was_valid;
    reg       drm_judged_id_was_valid;

    wire pno_judged_valid = (pno_judged_id != NO_JUDGEMENT_ID);
    wire drm_judged_valid = (drm_judged_id != NO_JUDGEMENT_ID);

    wire pno_judged_pulse = pno_judged_valid &&
                            (!pno_judged_id_was_valid ||
                             pno_judged_id != pno_judged_id_seen);
    wire drm_judged_pulse = drm_judged_valid &&
                            (!drm_judged_id_was_valid ||
                             drm_judged_id != drm_judged_id_seen);

    wire pno_expected_matches = pno_judged_pulse &&
                                 pno_queue_head_valid &&
                                 (pno_judged_id == pno_queue_head_id);
    wire drm_expected_matches = drm_judged_pulse &&
                                 drm_queue_head_valid &&
                                 (drm_judged_id == drm_queue_head_id);

    // v2: registered head deadlines; used only while the registered ID matches the live head
    reg [17:0] pno_head_deadline = 18'd0, drm_head_deadline = 18'd0;
    reg [5:0]  pno_head_id_q = 6'd0,      drm_head_id_q = 6'd0;
    reg        pno_head_valid_q = 1'b0,   drm_head_valid_q = 1'b0;
    always @(posedge clk) begin
        pno_head_deadline <= pno_queue_head_time + HIT_WINDOW_MS;
        drm_head_deadline <= drm_queue_head_time + HIT_WINDOW_MS;
        pno_head_id_q     <= pno_queue_head_id;
        drm_head_id_q     <= drm_queue_head_id;
        pno_head_valid_q  <= pno_queue_head_valid;
        drm_head_valid_q  <= drm_queue_head_valid;
    end

    wire pno_expected_expired = pno_queue_head_valid && pno_head_valid_q &&
                                 (pno_head_id_q == pno_queue_head_id) &&
                                 (song_time_ms > pno_head_deadline);
    wire drm_expected_expired = drm_queue_head_valid && drm_head_valid_q &&
                                 (drm_head_id_q == drm_queue_head_id) &&
                                 (song_time_ms > drm_head_deadline);

    wire song_changed = (song_select != song_select_q);
    wire queue_clear = new_game || song_changed || rewound;

    wire pno_queue_pop = play_enable && !queue_clear &&
                         (pno_expected_matches || pno_expected_expired);
    wire drm_queue_pop = play_enable && !queue_clear &&
                         (drm_expected_matches || drm_expected_expired);

    event_queue u_piano_event_queue (
        .clk(clk),
        .rst(rst),
        .clear(queue_clear),
        .push(pno_queue_push),
        .push_time_ms(rom_time_ms),
        .push_id(rom_id),
        .push_is_drum(1'b0),
        .push_note({1'b0, rom_piano_lane}),
        .pop(pno_queue_pop),
        .head_valid(pno_queue_head_valid),
        .head_time_ms(pno_queue_head_time),
        .head_id(pno_queue_head_id),
        .head_is_drum(pno_queue_head_is_drum),
        .head_note(pno_queue_head_note),
        .full(pno_queue_full)
    );

    event_queue u_drum_event_queue (
        .clk(clk),
        .rst(rst),
        .clear(queue_clear),
        .push(drm_queue_push),
        .push_time_ms(rom_time_ms),
        .push_id(rom_id),
        .push_is_drum(1'b1),
        .push_note({1'b0, rom_drum_lane}),
        .pop(drm_queue_pop),
        .head_valid(drm_queue_head_valid),
        .head_time_ms(drm_queue_head_time),
        .head_id(drm_queue_head_id),
        .head_is_drum(drm_queue_head_is_drum),
        .head_note(drm_queue_head_note),
        .full(drm_queue_full)
    );

    assign pno_exp_valid   = pno_queue_head_valid;
    assign pno_exp_id      = pno_queue_head_id;
    assign pno_exp_lane    = pno_queue_head_note[2:0];
    assign pno_exp_time_ms = pno_queue_head_time;

    assign drm_exp_valid   = drm_queue_head_valid;
    assign drm_exp_id      = drm_queue_head_id;
    assign drm_exp_lane    = drm_queue_head_note[2:0];
    assign drm_exp_time_ms = drm_queue_head_time;


    // ------------------------------------------------------------------------
    // Sequential scheduler and one-clock tile pulses.
    // ------------------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rom_addr            <= 6'd0;
            last_song_time_ms   <= 18'd0;
            song_select_q       <= 2'd0;
            pno_judged_id_seen  <= NO_JUDGEMENT_ID;
            drm_judged_id_seen  <= NO_JUDGEMENT_ID;
            pno_judged_id_was_valid <= 1'b0;
            drm_judged_id_was_valid <= 1'b0;

            pno_ev_valid   <= 1'b0;
            pno_ev_id      <= 6'd0;
            pno_ev_lane    <= NOTE_C;
            pno_ev_time_ms <= 18'd0;
            drm_ev_valid   <= 1'b0;
            drm_ev_id      <= 6'd0;
            drm_ev_lane    <= DRUM_NONE;
            drm_ev_time_ms <= 18'd0;

        end
        else begin
            last_song_time_ms <= song_time_ms;

            // Changing the menu selection, starting a round, or rewinding
            // selects a clean chart and discards the old expected-event heads.
            if (song_changed || new_game || rewound) begin
                rom_addr                <= 6'd0;
                song_select_q           <= song_select;
                pno_judged_id_seen      <= NO_JUDGEMENT_ID;
                drm_judged_id_seen      <= NO_JUDGEMENT_ID;
                pno_judged_id_was_valid <= 1'b0;
                drm_judged_id_was_valid <= 1'b0;
                pno_ev_valid            <= 1'b0;
                drm_ev_valid            <= 1'b0;
            end else begin
                if (pno_judged_valid) begin
                    pno_judged_id_seen      <= pno_judged_id;
                    pno_judged_id_was_valid <= 1'b1;
                end else begin
                    pno_judged_id_was_valid <= 1'b0;
                end

                if (drm_judged_valid) begin
                    drm_judged_id_seen      <= drm_judged_id;
                    drm_judged_id_was_valid <= 1'b1;
                end else begin
                    drm_judged_id_was_valid <= 1'b0;
                end

                // Spawn outputs are one-clock pulses.
                pno_ev_valid <= 1'b0;
                drm_ev_valid <= 1'b0;

                if (schedule_valid) begin
                    rom_addr <= rom_addr + 6'd1;

                    if (rom_piano_valid) begin
                        pno_ev_valid   <= 1'b1;
                        pno_ev_id      <= rom_id;
                        pno_ev_lane    <= rom_piano_lane;
                        pno_ev_time_ms <= rom_time_ms;
                    end

                    if (rom_drum_valid) begin
                        drm_ev_valid   <= 1'b1;
                        drm_ev_id      <= rom_id;
                        drm_ev_lane    <= rom_drum_lane;
                        drm_ev_time_ms <= rom_time_ms;
                    end
                end else if (schedule_step && event_missed &&
                             (rom_addr < selected_event_count)) begin
                    // Discard events that are already behind song_time_ms.
                    rom_addr <= rom_addr + 6'd1;
                end
            end // not restarting/changing chart
        end
    end
endmodule

