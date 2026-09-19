# KIBO Leak-Inspection Target Controller

![gds](../../workflows/gds/badge.svg) ![docs](../../workflows/docs/badge.svg) ![test](../../workflows/test/badge.svg)

## What is Kibo?

**Kibo** (きぼう, Japanese for "hope") is the Japanese Experiment Module of the International Space Station (ISS), built and operated by JAXA, the Japanese space agency. It is the largest single module on the station and includes a pressurised laboratory where astronauts run experiments.

Kibo is also home to free-flying robots that work alongside the crew. JAXA's **Int-Ball2** is a spherical camera drone that drifts through the module to take photos and video, so astronauts spend less time on documentation. NASA's **Astrobee** free-flyers operate in the same environment, and students program them in the **Kibo Robot Programming Challenge (Kibo-RPC)**, where teams write software that makes a robot navigate the module, find targets and carry out tasks.

This project is a piece of hardware inspired by that kind of mission: the decision logic for a robot that has to find a suspected leak location, fly to it, line up, and inspect it safely.

## What this project does

A small hardware finite-state machine (FSM) with a live **VGA status display**, written in Verilog for [Tiny Tapeout](https://tinytapeout.com). It decides when an autonomous inspection robot should **approach, align with, hold at, inspect, or abort** on a suspected leak-inspection target, and it draws the controller's state, inputs and commands on a 640x480 @ 60 Hz screen.

Sensor inputs are simplified to single-bit flags (target detected, target reached, position aligned, and so on). The design is a teaching and demonstration model, not flight software.

- [Full datasheet](docs/info.md)

## How it works

### Architecture

```
 ui[7:0] ──► 2-FF synchroniser ──► ┌──────────────┐ ──► state, inspect_enable,
 uio[7] (fast_step) ──►            │  Leak-       │     abort_cmd, target_locked
                                   │  inspection  │     (uio[5:0])
 frame counter ──► step tick ────► │  FSM         │
                                   └──────┬───────┘
                                          │ state, move_cmd, align_cmd, ...
                                          ▼
 clock ──► hpos/vpos counters ──► pixel renderer ──► RGB + hsync/vsync
           (640x480 @ 60 Hz)                          registers ──► uo[7:0] (VGA)
```

### State machine

The controller is a Moore FSM with 8 states. The current state is on `uio[2:0]` and on the display.

```
IDLE -> SEARCH -> APPROACH -> ALIGN -> HOLD -> INSPECT -> COMPLETE
  ^         ^                                                |
  |         +---------------- new_target = 1 ---------------+
  +------------------------ new_target = 0 -----------------+

any state --(system_fault | obstacle_detected)--> ABORT (latched until reset)
```

| Code | State      | Behaviour                                                  |
| ---- | ---------- | ---------------------------------------------------------- |
| 000  | `IDLE`     | Waits for `target_detected`                                |
| 001  | `SEARCH`   | Waits for `target_detected` to confirm a target            |
| 010  | `APPROACH` | Commands `MOVE_FORWARD` until `target_reached`             |
| 011  | `ALIGN`    | Corrects position and orientation until both are aligned   |
| 100  | `HOLD`     | Holds position for 3 FSM steps                             |
| 101  | `INSPECT`  | Asserts `inspect_enable` until `inspection_done`           |
| 110  | `COMPLETE` | Asserts `target_locked`; `new_target` -> `SEARCH`, else `IDLE` |
| 111  | `ABORT`    | Asserts `abort_cmd`, stops all motion, latched until reset |

- **Safety has the highest priority.** A fault or obstacle is checked on every clock and sends the FSM to `ABORT` from any state, even if `inspection_done` arrives in the same cycle.
- **Watchable speed.** Normal transitions happen once every 16 video frames (about 0.27 s). Driving `uio[7]` high makes the FSM step every clock, which is used for simulation.
- **Inputs are synchronised** with a 2-flip-flop synchroniser.

### Command encodings

| `move_cmd` | Meaning  | `align_cmd` | Meaning       |
| ---------- | -------- | ----------- | ------------- |
| `000`      | STOP     | `00`        | NO_ALIGNMENT  |
| `001`      | FORWARD  | `01`        | ROTATE_LEFT   |
| `010`      | BACKWARD | `10`        | ROTATE_RIGHT  |
| `011`      | LEFT     | `11`        | ALIGNED       |
| `100`      | RIGHT    |             |               |
| `101`      | UP       |             |               |
| `110`      | DOWN     |             |               |

## How to use it

### What you need

- A Tiny Tapeout demo board (or the design running on an FPGA or in simulation)
- A Tiny VGA PMOD (or any 2-bit-per-channel VGA DAC with the same pin order) and a VGA monitor
- A **25.175 MHz** clock
- 8 switches or buttons on the `ui` pins, and optionally LEDs on `uio[5:0]`

### Steps

1. Connect the Tiny VGA PMOD to the `uo` connector and plug in the monitor. Set the clock to 25.175 MHz.
2. Pulse `rst_n` low, then high. The **IDLE** box lights up.
3. Set `ui[0]` (`target_detected`). The FSM moves to **SEARCH**, then **APPROACH**.
4. Set `ui[1]` (`target_reached`). The FSM moves to **ALIGN**.
5. Set `ui[2]` and `ui[3]` (`position_aligned`, `orientation_aligned`). The FSM moves to **HOLD**, then **INSPECT** after 3 steps.
6. Set `ui[4]` (`inspection_done`). The FSM moves to **COMPLETE** and `target_locked` lights.
7. If `ui[7]` (`new_target`) is high the FSM returns to **SEARCH**, otherwise to **IDLE**.
8. At any point, set `ui[5]` (`obstacle_detected`) or `ui[6]` (`system_fault`) to trigger **ABORT**. The banner blinks red and only a reset clears it.

## VGA display

Output goes to the Tiny VGA PMOD on `uo_out`, pin order `{hsync, B0, G0, R0, vsync, B1, G1, R1}`. Each row is 64 px tall and each cell 64 px wide, starting at x = 64. Lit cells are coloured, unlit cells are dark grey. There is no text; rows are identified by position.

| Row | Content |
| --- | ------- |
| 0 | Banner in the current state's colour (blinks in `ABORT`) |
| 1 | State boxes, left to right: IDLE, SEARCH, APPROACH, ALIGN, HOLD, INSPECT, COMPLETE, ABORT |
| 2 | The 8 input flags `ui[0]`..`ui[7]` (obstacle and fault light red) |
| 3 | `move_cmd`, left to right: STOP, FORWARD, BACKWARD, LEFT, RIGHT, UP, DOWN |
| 4 | `align_cmd`, left to right: none, rotate left, rotate right, aligned |
| 5 | Lamps: `inspect_enable` (magenta), `target_locked` (green), `abort_cmd` (red) |
| 6 | Mission progress bar (cyan), green on `COMPLETE`, solid red in `ABORT` |

State colours: IDLE grey, SEARCH light blue, APPROACH blue, ALIGN yellow, HOLD orange, INSPECT magenta, COMPLETE green, ABORT red.

## Pinout

### Inputs (`ui_in`)

| Pin     | Signal                |
| ------- | --------------------- |
| `ui[0]` | `target_detected`     |
| `ui[1]` | `target_reached`      |
| `ui[2]` | `position_aligned`    |
| `ui[3]` | `orientation_aligned` |
| `ui[4]` | `inspection_done`     |
| `ui[5]` | `obstacle_detected`   |
| `ui[6]` | `system_fault`        |
| `ui[7]` | `new_target`          |

### Outputs

| Pin          | Signal                                      |
| ------------ | ------------------------------------------- |
| `uo[7:0]`    | VGA: `hsync, B0, G0, R0, vsync, B1, G1, R1` |
| `uio[2:0]`   | `state`                                     |
| `uio[3]`     | `inspect_enable`                            |
| `uio[4]`     | `abort_cmd`                                 |
| `uio[5]`     | `target_locked`                             |
| `uio_in[7]`  | `fast_step` (input, simulation only)        |

`move_cmd` and `align_cmd` are shown on the display only. `rst_n` is the Tiny Tapeout active-low reset.

## Repository layout

```
.
├── info.yaml        Tiny Tapeout project description and pinout
├── src/
│   └── project.v    FSM + VGA generator (top module: tt_um_kibo_leak_inspect)
├── docs/
│   └── info.md      Datasheet text
└── test/
    ├── test.py      cocotb tests
    ├── tb.v         Testbench wrapper
    ├── Makefile
    └── requirements.txt
```

## Running the tests

Requires Python 3, [cocotb](https://www.cocotb.org/) and [Icarus Verilog](https://steveicarus.github.io/iverilog/).

```sh
cd test
pip install -r requirements.txt
make -B
```

The tests cover the full happy path, `new_target` returning to `SEARCH`, abort priority over `COMPLETE`, abort latching until reset, a fault raised from `IDLE`, slow-mode stepping, and VGA hsync timing with blanked colour outputs. Simulation writes a waveform to `test/tb.fst`, viewable with [GTKWave](https://gtkwave.sourceforge.net/) or [Surfer](https://surfer-project.org/).

## Known limitations and ideas

- Alignment uses single-bit flags. The `ALIGN` corrections are placeholders; a more realistic version would take signed `x/y/z` and `roll/pitch/yaw` error values and choose move and rotate commands from them.
- Target loss during `APPROACH` and `ALIGN` is not handled.
- The display has no text; rows are identified by position (see the table above).

## License

Apache-2.0. See [LICENSE](LICENSE).
