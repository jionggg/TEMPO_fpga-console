# TEMPO: Two-player Ensemble Music Performance on OLED

EE2026 FPGA design project, group S3_04. Basys 3 (`xc7a35tcpg236-1`), Verilog, Vivado.

Two players play a real piano and a drum kit into one Pmod microphone. The FPGA detects the notes and drum hits, judges them against a generated song, and shows falling tiles, judgements and scores on two OLEDs: one for the piano, one for the drums.

**Diagrams (Miro):** [TEMPO design diagrams](https://miro.com/app/board/uXjVEWCnAYE=/?share_link_id=961799281316) has the game FSM state diagram and a UML of every module's ports, outlined in each owner's colour.

**Status (25 Oct):** the skeleton builds; both OLEDs show the static layout on the board.
The A, B and C modules are still placeholders with their agreed ports.

## Team and ownership

| Member | Role | Owns |
|---|---|---|
| A: annanya | Audio DSP: mic to detected piano notes and drum hits | `src/audio_dsp.v` |
| B: pei ling | Performance evaluation: match hits, grade PERFECT / GOOD / MISS, sync judge | `src/perf_eval.v` |
| C: meiyi | Game intelligence: game FSM, the song clock, song patterns, scoring, difficulty | `src/game_intel.v` |
| D: jiyong | Graphics for both OLEDs; owner of the top level | `src/display_top.v`, `src/My_Top_Module.v` |

## Repository layout

| File | Owner | What it is |
|---|---|---|
| `src/My_Top_Module.v` | Ji Yong | Wiring only: clocks, the four member modules, two `Oled_Display`s |
| `src/audio_dsp.v` | Annanya | Placeholder: ports are the team interface, outputs tied to 0 |
| `src/perf_eval.v` | Pei Ling | Placeholder |
| `src/game_intel.v` | Meiyi | Placeholder (split into game_fsm / pattern_gen / score_keeper inside) |
| `src/display_top.v` | Ji Yong | draw the static bg layout on both OLEDs |
| `src/flexible_clock_divider.v` | shared | slower clock: f = 100 MHz / (2(m + 1)) |
| `src/tick_gen.v` | shared | 1-cycle "tick" every N clocks (`ms_tick` = 1 ms) |
| `src/tempo_defs.vh` | shared | shared names for game states, grades, lane codes |
| `constraints/TEMPO_pins.xdc` | shared | ports of `My_Top_Module`. the mic pins are named `mic_cs` (K17), `mic_miso` (N17), `mic_sclk` (P18), instead of `JC[0]`, `JC[2]`, `JC[3]`. can change at annanya's discretion |
| `sim/tb_display_top.v` | Ji Yong | simulation only: `display_top` on mock inputs, frames at 0 / 250 / 500 ms |
| `sim/tb_top.v` | Ji Yong | simulation only: the whole top through the real `Oled_Display` |

`Oled_Display.v` is a course file provided in FDP2026 zip

## Simulate

testbenches below are simulation sources (!design source).

Simulation Sources > Set as Top, Run Behavioral Simulation, then type `run all` in the Tcl console. .ppm images in `<project>.sim/sim_1/behav/xsim/`can be viewed with IrfanView 

- `sim/tb_display_top.v`: `display_top` alone on mock inputs. Takes seconds; use it daily.
- `sim/tb_top.v`: the whole top through the real `Oled_Display` (~150 ms simulated). Use it before programming the board.

## Team rules

- **One clock between members.** Everything passed between members runs on `clk` (100 MHz), and a pulse is high for exactly one `clk` cycle.
- **Shared clocks are made once,** in `My_Top_Module`. For "every N ms" logic use `ms_tick` (`if (ms_tick) ...`), not a new clock divider.
- **Edit only your own module file.** To change a port, agree in the group first, then change your module and `My_Top_Module.v` in the same commit.
- **Use the names in `tempo_defs.vh`** (`DRUM_SNARE`), never the raw numbers (`3'd1`).
  Put `` `include "tempo_defs.vh" `` inside your module, after the port list.
- **Branches** start with `feat/`, `fix/` or `chore/` (for example `feat/falling-tiles`).

## Shared codes (`src/tempo_defs.vh`)

| `game_state` | 0 | 1 | 2 | 3 | 4 |
|---|---|---|---|---|---|
| Name | `ST_MENU` | `ST_COUNTDOWN` | `ST_PLAYING` | `ST_PAUSED` | `ST_RESULTS` |

| `judge_grade` | 0 | 1 | 2 |
|---|---|---|---|
| Name | `GRADE_MISS` | `GRADE_GOOD` | `GRADE_PERFECT` |

Lane codes are used by `det_note`, `exp_note`, `judge_lane`, `pno_ev_lane` and `drm_ev_lane`.
The is_drum / player bit says which row applies.

| Lane | 0 | 1 | 2 | 3 | 4 |
|---|---|---|---|---|---|
| Piano (`NOTE_*`) | C | D | E | F | G |
| Drum (`DRUM_*`) | crash cymbal | snare drum | bass drum |     |     |

## Board map

| Item | Use |
|---|---|
| Pmod JA (left edge) | Piano OLED |
| Pmod JB (right edge) | Drum OLED |
| Pmod JC (right edge) | Microphone on pins 1, 3, 4 (Annanya to confirm) |
| btnC / btnU / btnD / btnR | Start / pause-resume / quit / reset (proposal for Meiyi) |
| sw[0] | Use Ji Yong's mock inputs instead of the real modules |
| led[2:0] | `game_state` |
| led[15] | Mock inputs on (mirrors sw[0]) |

## quirks / debug

- **Warnings:** "unconnected" / "undriven" port warnings come from the placeholders and are
  harmless. On Windows, `[Common 17-180] Spawn failed` messages are harmless if the bitstream
  is written; moving the project to a short path with no spaces (e.g. `C:\vivado\tempo`) can
  remove them.
- **`tempo_defs.vh` not found:** Settings > General > Verilog options > Include Directories >
  add its folder. Do NOT use "Set Global Include".
