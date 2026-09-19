# KIBO Leak-Inspection Target Controller

![gds](../../workflows/gds/badge.svg) ![docs](../../workflows/docs/badge.svg) ![test](../../workflows/test/badge.svg)

A small hardware finite-state machine (FSM), written in Verilog for [Tiny Tapeout](https://tinytapeout.com), that decides when an autonomous inspection robot should **approach, align with, hold at, inspect, or abort** on a suspected leak-inspection target.

It is modelled on the kind of task performed by free-flying robots such as Int-Ball2 on the Kibo module of the ISS, and is inspired by the Kibo-RPC challenge. Sensor inputs are simplified to single-bit flags.

- [Full datasheet](docs/info.md)

## How it works

The controller is a Moore FSM with 8 states. The current state is visible on `uio[2:0]`.

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
| 100  | `HOLD`     | Holds position for 3 clock cycles (internal counter)       |
| 101  | `INSPECT`  | Asserts `inspect_enable` until `inspection_done`           |
| 110  | `COMPLETE` | Asserts `target_locked`; `new_target` -> `SEARCH`, else `IDLE` |
| 111  | `ABORT`    | Asserts `abort_cmd`, stops all motion, latched until reset |

**Safety has the highest priority.** A fault or obstacle sends the FSM to `ABORT` from any state, even if `inspection_done` arrives in the same cycle.

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

### Outputs (`uo_out`)

| Pin         | Signal           |
| ----------- | ---------------- |
| `uo[2:0]`   | `move_cmd`       |
| `uo[4:3]`   | `align_cmd`      |
| `uo[5]`     | `inspect_enable` |
| `uo[6]`     | `abort_cmd`      |
| `uo[7]`     | `target_locked`  |
| `uio[2:0]`  | `state` (debug)  |

### Command encodings

| `move_cmd` | Meaning   | `align_cmd` | Meaning        |
| ---------- | --------- | ----------- | -------------- |
| `000`      | STOP      | `00`        | NO_ALIGNMENT   |
| `001`      | FORWARD   | `01`        | ROTATE_LEFT    |
| `010`      | BACKWARD  | `10`        | ROTATE_RIGHT   |
| `011`      | LEFT      | `11`        | ALIGNED        |
| `100`      | RIGHT     |             |                |
| `101`      | UP        |             |                |
| `110`      | DOWN      |             |                |

`rst_n` is the Tiny Tapeout active-low reset.

