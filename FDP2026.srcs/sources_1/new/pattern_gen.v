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
// ============================================================================

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
// ============================================================================

// ============================================================================
// TEMPO pattern generator
//
// Reads the fixed song ROM, creates piano/drum tile pulses, and maintains
// independent expected-event FIFOs for piano and drums.
//
// A duet ROM entry is pushed into both FIFOs. This allows performance
// evaluation to judge the piano and drum hits independently while comparing
// their expected timestamps for synchronisation.
//
// INTERFACE SUMMARY
//   -> Pei Ling (B): *_exp_*   oldest unjudged event (FIFO head), level signals
//   <- Pei Ling (B): *_judged_id  ID of the event just judged, HIT OR MISS
//                    (63 = none). B reports her own misses with this too.
//                    If B is late, the head auto-expires after HIT_WINDOW_MS
//                    so the FIFO never stalls.
//   -> Ji Yong  (D): *_ev_*    one-clock spawn pulse, LOOKAHEAD_MS before the
//                              hit time. Must be captured on clk (100 MHz).
//   -> Meiyi    (C FSM): song_len_ms
//   <- Meiyi    (C FSM): song_time_ms
//
// Lane codes come from TEMPO_defs.vh: piano NOTE_C..NOTE_G, drums
// DRUM_CRASH / DRUM_SNARE / DRUM_KICK. DRUM_NONE is never emitted as a lane.
// The song ROM currently uses no CRASH.
// ============================================================================
module pattern_gen (
    input  wire        clk,
    input  wire        rst,
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

    localparam integer TOTAL_EVENTS = TOTAL_NOTES;
    localparam [17:0] SONG_LENGTH_MS = LAST_NOTE_TIME_MS +
                                        SONG_END_PADDING_MS;

    assign song_len_ms = SONG_LENGTH_MS;

    // ------------------------------------------------------------------------
    // Song ROM and field decoding.
    // ------------------------------------------------------------------------
    reg  [5:0]  rom_addr;
    wire [31:0] rom_data;

    song_rom u_song_rom (
        .addr(rom_addr),
        .event_data(rom_data)
    );

    wire [17:0] rom_time_ms = {2'b00, rom_data[31:16]};
    wire [1:0]  rom_type    = rom_data[15:14];
    wire [3:0]  rom_piano   = rom_data[13:10];
    wire [3:0]  rom_drum    = rom_data[9:6];
    wire [5:0]  rom_id      = rom_data[5:0];

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

    wire song_time_changed = (song_time_ms != last_song_time_ms);
    wire rewound           = (song_time_ms < last_song_time_ms);
    wire schedule_step     = song_time_changed;
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

    wire pno_expected_expired = pno_queue_head_valid &&
                                 (song_time_ms >
                                  (pno_queue_head_time + HIT_WINDOW_MS));
    wire drm_expected_expired = drm_queue_head_valid &&
                                 (song_time_ms >
                                  (drm_queue_head_time + HIT_WINDOW_MS));

    wire queue_clear = rewound;

    wire pno_queue_pop = !queue_clear &&
                         (pno_expected_matches || pno_expected_expired);
    wire drm_queue_pop = !queue_clear &&
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

            if (pno_judged_valid) begin
                pno_judged_id_seen     <= pno_judged_id;
                pno_judged_id_was_valid <= 1'b1;
            end
            else begin
                pno_judged_id_was_valid <= 1'b0;
            end

            if (drm_judged_valid) begin
                drm_judged_id_seen     <= drm_judged_id;
                drm_judged_id_was_valid <= 1'b1;
            end
            else begin
                drm_judged_id_was_valid <= 1'b0;
            end

            // Spawn outputs are one-clock pulses.
            pno_ev_valid <= 1'b0;
            drm_ev_valid <= 1'b0;

            if (rewound) begin
                rom_addr <= 6'd0;
            end
            else begin
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
                end
                else if (schedule_step && event_missed &&
                         (rom_addr < TOTAL_EVENTS)) begin
                    // Discard events that are already behind song_time_ms.
                    rom_addr <= rom_addr + 6'd1;
                end
            end
        end
    end
endmodule


