Author: Caeljan Cristobal

# KIBO Leak-Inspection Target Controller

![gds](../../workflows/gds/badge.svg) ![docs](../../workflows/docs/badge.svg) ![test](../../workflows/test/badge.svg)

## What is Kibo?

**Kibo** (きぼう, Japanese for "hope") is the Japanese Experiment Module of the International Space Station, operated by JAXA. Free-flying robots such as JAXA's **Int-Ball2** and NASA's **Astrobee** fly around inside it to help the crew, and students program them in the **Kibo Robot Programming Challenge (Kibo-RPC)**.

## Overview

This project is the "brain" of an inspection robot like those. It is a small digital circuit, built for [Tiny Tapeout](https://tinytapeout.com), that guides a robot through checking a suspected leak: **find the target, fly to it, line up with it, hold still, inspect it, and stop safely if anything goes wrong.**

It also draws its status on a VGA monitor, so you can watch each step happen live.

**Try it in your browser:** [open in VGA Playground](https://vga-playground.com/?repo=https://github.com/ccaeljan-lang/KIBOLeak-InspectionTargetController)

## How it works

The screen shows the controller live. In [VGA Playground](https://vga-playground.com/?repo=https://github.com/ccaeljan-lang/KIBOLeak-InspectionTargetController), the 8 **`ui_in` buttons above the display** act as the robot's sensors, and the circuit steps through these states as you press them:

```
IDLE -> SEARCH -> APPROACH -> ALIGN -> HOLD -> INSPECT -> COMPLETE
```

| Button  | Name                  | What it does                                   |
| ------- | --------------------- | ---------------------------------------------- |
| `ui_in[0]` | `target_detected`     | A target has been spotted: start the mission   |
| `ui_in[1]` | `target_reached`      | The robot is close enough to the target        |
| `ui_in[2]` | `position_aligned`    | Position is within tolerance                   |
| `ui_in[3]` | `orientation_aligned` | Orientation is within tolerance                |
| `ui_in[4]` | `inspection_done`     | The inspection is finished                     |
| `ui_in[5]` | `obstacle_detected`   | Something is in the way: **abort**             |
| `ui_in[6]` | `system_fault`        | Critical fault: **abort**                      |
| `ui_in[7]` | `new_target`          | After finishing, go look for another target    |

- **Safety comes first.** An obstacle or fault stops everything immediately, from any state, and only a reset clears it.
- **Watchable speed.** The circuit moves to the next state about 4 times a second (once every 16 video frames), so keep a button pressed until the highlighted box moves on.
- After the inspection the robot returns to `IDLE`, or back to `SEARCH` if `new_target` is on.

## How to use it

1. Open the [VGA Playground link](https://vga-playground.com/?repo=https://github.com/ccaeljan-lang/KIBOLeak-InspectionTargetController). The design starts in **IDLE** (the first state box is lit).
2. Press `ui_in[0]` (target detected). The screen moves to **SEARCH**, then **APPROACH**.
3. Press `ui_in[1]` (target reached). It moves to **ALIGN**.
4. Press `ui_in[2]` and `ui_in[3]` (position and orientation aligned). It moves to **HOLD**, then **INSPECT**.
5. Press `ui_in[4]` (inspection done). It moves to **COMPLETE**, then back to **IDLE**.
6. At any point press `ui_in[5]` or `ui_in[6]` to see the **ABORT** state. The banner blinks red until you restart the simulation.

On a real Tiny Tapeout board the same 8 signals are the `ui` pins: connect a Tiny VGA PMOD and monitor, set the clock to **25.175 MHz**, and use switches in place of the playground buttons.

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

<img width="2021" height="1550" alt="Cristobal_2D_View_KIBOLeak-InspectionTargetController" src="https://github.com/user-attachments/assets/73808b4a-5448-4550-b9cb-09637e2c3170" />

## 3D Viewer

[View the layout in 3D](https://gds-viewer.tinytapeout.com/?model=https://ccaeljan-lang.github.io/KIBOLeak-InspectionTargetController/tinytapeout.oas&pdk=ihp-sg13g2)

<img width="780" height="647" alt="Screenshot 2026-09-19 at 4 57 07 PM" src="https://github.com/user-attachments/assets/46c12b00-195b-4cb3-95a9-f3e9016fc626" />

