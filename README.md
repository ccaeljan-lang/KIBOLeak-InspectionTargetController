# KIBO Leak-Inspection Target Controller

![gds](../../workflows/gds/badge.svg) ![docs](../../workflows/docs/badge.svg) ![test](../../workflows/test/badge.svg)

## What is Kibo?

**Kibo** (きぼう, Japanese for "hope") is the Japanese Experiment Module of the International Space Station, operated by JAXA. Free-flying robots such as JAXA's **Int-Ball2** and NASA's **Astrobee** fly around inside it to help the crew, and students program them in the **Kibo Robot Programming Challenge (Kibo-RPC)**.

## Overview

This project is the "brain" of an inspection robot like those. It is a small digital circuit, built for [Tiny Tapeout](https://tinytapeout.com), that guides a robot through checking a suspected leak: **find the target, fly to it, line up with it, hold still, inspect it, and stop safely if anything goes wrong.**

It also draws its status on a VGA monitor, so you can watch each step happen live.

**Try it in your browser:** [open in VGA Playground](https://vga-playground.com/?repo=https://github.com/ccaeljan-lang/KIBOLeak-InspectionTargetController)

## How it works

You control it with 8 switches, and the circuit steps through these states:

```
IDLE -> SEARCH -> APPROACH -> ALIGN -> HOLD -> INSPECT -> COMPLETE
```

| Switch  | Name                  | What it does                                   |
| ------- | --------------------- | ---------------------------------------------- |
| `ui[0]` | `target_detected`     | A target has been spotted: start the mission   |
| `ui[1]` | `target_reached`      | The robot is close enough to the target        |
| `ui[2]` | `position_aligned`    | Position is within tolerance                   |
| `ui[3]` | `orientation_aligned` | Orientation is within tolerance                |
| `ui[4]` | `inspection_done`     | The inspection is finished                     |
| `ui[5]` | `obstacle_detected`   | Something is in the way: **abort**             |
| `ui[6]` | `system_fault`        | Critical fault: **abort**                      |
| `ui[7]` | `new_target`          | After finishing, go look for another target    |

- **Safety comes first.** An obstacle or fault stops everything immediately, from any state, and only a reset clears it.
- Once the inspection is done the robot returns to `IDLE`, or back to `SEARCH` if `new_target` is on.

## How to use it

1. Connect a Tiny VGA PMOD and a monitor, and set the clock to **25.175 MHz**.
2. Pulse `rst_n` low then high. The IDLE box lights up.
3. Turn on the switches in order: `ui[0]`, then `ui[1]`, then `ui[2]` and `ui[3]` together, then `ui[4]`.
4. Watch the screen move through each state. Turn on `ui[5]` or `ui[6]` at any time to see the abort.

## The display

Rows on the screen, top to bottom (no text, so rows are identified by position):

| Row | Shows |
| --- | ----- |
| 1 | A banner in the current state's colour (blinks red on abort) |
| 2 | The 8 states, with the active one lit |
| 3 | The 8 switch inputs |
| 4 | Movement command: stop, forward, back, left, right, up, down |
| 5 | Rotation command: none, left, right, aligned |
| 6 | Lamps: inspecting, target locked, abort |
| 7 | Mission progress bar |

## Outputs

- **VGA** on `uo[7:0]` in the Tiny VGA PMOD order: `hsync, B0, G0, R0, vsync, B1, G1, R1`
- **Status** on `uio[2:0]` (state, 0 to 7), `uio[3]` inspecting, `uio[4]` abort, `uio[5]` target locked

## Running the tests

```sh
cd test
pip install -r requirements.txt
make -B
```

Needs Python 3, cocotb and Icarus Verilog. See [docs/info.md](docs/info.md) for more detail.

## Limitations

Alignment uses simple yes/no flags. A more realistic version would take signed position and rotation errors and decide which way to move.

## Routing stats

| Utilisation (%) | Wire length (um) |
| --------------- | ---------------- |
| 23.551 %        | 11049            |

## Cell usage by Category

| Category    | Cells                         | Count |
| ----------- | ----------------------------- | ----: |
| Fill        | decap fill                    | 1961  |
| NOR         | nor2 nor3 nor4 nor2b xnor2    | 85    |
| NAND        | nand2 nand2b nand3 nand4 nand3b | 79  |
| Combo Logic | o21ai a21oi a21o a221oi a22oi | 58    |
| Flip Flops  | dfrbpq                        | 56    |
| Misc        | dlygate4sd3                   | 56    |
| Buffer      | buf                           | 48    |
| AND         | and2 and4 and3                | 41    |
| Inverter    | inv                           | 21    |
| OR          | or4 or2 or3 xor2              | 11    |
| Multiplexer | mux4                          | 2     |

### 457 total cells (excluding fill and tap cells)

## Tiny Tapeout Precheck Results

| Check                                | Result |
| ------------------------------------ | :----: |
| KLayout pin label overlapping drawing | ✅ |
| KLayout SG13G2 DRC                   | ✅ |
| KLayout zero area                    | ✅ |
| KLayout Checks                       | ✅ |
| Pin check                            | ✅ |
| Boundary check                       | ✅ |
| Layer check                          | ✅ |
| Cell name check                      | ✅ |
| Analog pin check                     | ✅ |
| Verilog syntax check                 | ✅ |

## 2D Viewer

[View the layout in 2D](https://ccaeljan-lang.github.io/KIBOLeak-InspectionTargetController/)

## 3D Viewer

[View the layout in 3D](https://ccaeljan-lang.github.io/KIBOLeak-InspectionTargetController/)
