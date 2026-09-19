# KIBO Leak-Inspection Target Controller

![gds](../../workflows/gds/badge.svg) ![docs](../../workflows/docs/badge.svg) ![test](../../workflows/test/badge.svg)

A small hardware finite-state machine (FSM) with a live **VGA status display**, written in Verilog for [Tiny Tapeout](https://tinytapeout.com). It decides when an autonomous inspection robot should **approach, align with, hold at, inspect, or abort** on a suspected leak-inspection target, and draws the controller's state, inputs and commands on a 640x480 @ 60 Hz screen.

It is modelled on the kind of task performed by free-flying robots such as Int-Ball2 on the Kibo module of the ISS, and is inspired by the Kibo-RPC challenge. Sensor inputs are simplified to single-bit flags.

- [Full datasheet](docs/info.md)

## How it works

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

## VGA display

Output goes to the Tiny VGA PMOD on `uo_out`, pin order `{hsync, B0, G0, R0, vsync, B1, G1, R1}`, with a 25.175 MHz clock.

| Row | Content |
| --- | ------- |
| 0 | Banner in the current state's colour (blinks in `ABORT`) |
| 1 | State boxes: IDLE, SEARCH, APPROACH, ALIGN, HOLD, INSPECT, COMPLETE, ABORT |
| 2 | The 8 input flags `ui[0]`..`ui[7]` (obstacle and fault light red) |
| 3 | `move_cmd`: STOP, FORWARD, BACKWARD, LEFT, RIGHT, UP, DOWN |
| 4 | `align_cmd`: none, rotate left, rotate right, aligned |
| 5 | Lamps: `inspect_enable`, `target_locked`, `abort_cmd` |
| 6 | Mission progress bar |

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

| Pin          | Signal                                   |
| ------------ | ---------------------------------------- |
| `uo[7:0]`    | VGA: `hsync, B0, G0, R0, vsync, B1, G1, R1` |
| `uio[2:0]`   | `state`                                  |
| `uio[3]`     | `inspect_enable`                         |
| `uio[4]`     | `abort_cmd`                              |
| `uio[5]`     | `target_locked`                          |
| `uio_in[7]`  | `fast_step` (input, simulation only)     |

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
