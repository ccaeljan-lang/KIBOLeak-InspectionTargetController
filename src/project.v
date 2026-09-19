/*
 * KIBO Leak-Inspection Target Controller with VGA status display
 * Tiny Tapeout top-level module (640x480 @ 60 Hz, 25.175 MHz clock).
 *
 * Pin map
 * -------
 * ui_in[0] target_detected      ui_in[4] inspection_done
 * ui_in[1] target_reached       ui_in[5] obstacle_detected
 * ui_in[2] position_aligned     ui_in[6] system_fault
 * ui_in[3] orientation_aligned  ui_in[7] new_target
 *
 * uo_out (Tiny VGA PMOD): {hsync, B0, G0, R0, vsync, B1, G1, R1}
 *
 * uio_out[2:0] state          uio_out[3] inspect_enable
 * uio_out[4]   abort_cmd      uio_out[5] target_locked
 * uio_in[7]    fast_step (1 = FSM steps every clock, used for simulation;
 *                         0 = FSM steps once every 16 video frames)
 *
 * move_cmd and align_cmd are shown on the display only.
 * rst_n is the Tiny Tapeout active-low reset.
 */

`default_nettype none

// ---------------------------------------------------------------------
// Controller FSM. `step` gates normal transitions; safety is checked on
// every clock so fault/obstacle always wins immediately.
// ---------------------------------------------------------------------
module kibo_leak_fsm (
    input  wire       clk,
    input  wire       rst,
    input  wire       step,
    input  wire [7:0] in,
    output reg  [2:0] state,
    output reg  [2:0] move_cmd,
    output reg  [1:0] align_cmd,
    output reg        inspect_enable,
    output reg        abort_cmd,
    output reg        target_locked
);

    localparam [2:0] IDLE     = 3'd0,
                     SEARCH   = 3'd1,
                     APPROACH = 3'd2,
                     ALIGN    = 3'd3,
                     HOLD     = 3'd4,
                     INSPECT  = 3'd5,
                     COMPLETE = 3'd6,
                     ABORT    = 3'd7;

    localparam [2:0] MOVE_STOP    = 3'b000,
                     MOVE_FORWARD = 3'b001;

    localparam [1:0] ALIGN_NONE = 2'b00,
                     ALIGN_LEFT = 2'b01,
                     ALIGN_DONE = 2'b11;

    localparam [1:0] HOLD_CYCLES = 2'd3;   // FSM steps spent in HOLD

    wire target_detected     = in[0];
    wire target_reached      = in[1];
    wire position_aligned    = in[2];
    wire orientation_aligned = in[3];
    wire inspection_done     = in[4];
    wire obstacle_detected   = in[5];
    wire system_fault        = in[6];
    wire new_target          = in[7];

    wire safety_trip = system_fault | obstacle_detected;

    reg [1:0] hold_cnt;
    wire hold_complete = (hold_cnt == HOLD_CYCLES);

    reg [2:0] next_state;

    always @(*) begin
        next_state = state;
        case (state)
            IDLE:     if (target_detected)                         next_state = SEARCH;
            SEARCH:   if (target_detected)                         next_state = APPROACH;
            APPROACH: if (target_reached)                          next_state = ALIGN;
            ALIGN:    if (position_aligned && orientation_aligned) next_state = HOLD;
            HOLD:     if (hold_complete)                           next_state = INSPECT;
            INSPECT:  if (inspection_done)                         next_state = COMPLETE;
            COMPLETE: next_state = new_target ? SEARCH : IDLE;
            default:  next_state = ABORT;                          // ABORT latches
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            state    <= IDLE;
            hold_cnt <= 2'd0;
        end else if (safety_trip && state != ABORT) begin
            state    <= ABORT;                                     // highest priority
        end else if (step) begin
            state <= next_state;
            if (state == HOLD && !hold_complete)
                hold_cnt <= hold_cnt + 2'd1;
            else if (state != HOLD)
                hold_cnt <= 2'd0;
        end
    end

    always @(*) begin
        move_cmd       = MOVE_STOP;
        align_cmd      = ALIGN_NONE;
        inspect_enable = 1'b0;
        abort_cmd      = 1'b0;
        target_locked  = 1'b0;

        case (state)
            APPROACH: move_cmd = MOVE_FORWARD;

            ALIGN: begin
                // Placeholder corrections until error values replace the flags
                move_cmd = position_aligned ? MOVE_STOP : MOVE_FORWARD;
                if (!orientation_aligned)
                    align_cmd = ALIGN_LEFT;
                else if (position_aligned)
                    align_cmd = ALIGN_DONE;
            end

            HOLD:     align_cmd = ALIGN_DONE;

            INSPECT: begin
                align_cmd      = ALIGN_DONE;
                inspect_enable = 1'b1;
            end

            COMPLETE: target_locked = 1'b1;
            ABORT:    abort_cmd     = 1'b1;
            default: ;
        endcase
    end

endmodule


// ---------------------------------------------------------------------
// Top level: input sync + FSM + VGA timing + status display
// ---------------------------------------------------------------------
module tt_um_kibo_leak_inspect (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    wire rst = ~rst_n;

    localparam [2:0] IDLE = 3'd0, SEARCH = 3'd1, APPROACH = 3'd2, ALIGN = 3'd3,
                     HOLD = 3'd4, INSPECT = 3'd5, COMPLETE = 3'd6, ABORT = 3'd7;

    // 6-bit colours: {R[1:0], G[1:0], B[1:0]}
    localparam [5:0] C_BG      = 6'b000001,
                     C_DIM     = 6'b010101,
                     C_DARKRED = 6'b010000,
                     C_WHITE   = 6'b111111,
                     C_RED     = 6'b110000,
                     C_GREEN   = 6'b001100,
                     C_YELLOW  = 6'b111100,
                     C_CYAN    = 6'b001111,
                     C_MAGENTA = 6'b110011;

    // ---------------- input synchronisers (2-FF) ----------------
    reg [8:0] sync0, sync1;
    always @(posedge clk) begin
        if (rst) begin
            sync0 <= 9'd0;
            sync1 <= 9'd0;
        end else begin
            sync0 <= {uio_in[7], ui_in};
            sync1 <= sync0;
        end
    end
    wire [7:0] inputs = sync1[7:0];
    wire       fast   = sync1[8];

    // ---------------- VGA timing 640x480 @ 60 Hz ----------------
    reg [9:0] hpos, vpos;
    reg [4:0] frame_cnt;

    wire line_end  = (hpos == 10'd799);
    wire frame_end = line_end && (vpos == 10'd524);

    always @(posedge clk) begin
        if (rst) begin
            hpos      <= 10'd0;
            vpos      <= 10'd0;
            frame_cnt <= 5'd0;
        end else begin
            if (line_end) begin
                hpos <= 10'd0;
                if (vpos == 10'd524) begin
                    vpos      <= 10'd0;
                    frame_cnt <= frame_cnt + 5'd1;
                end else begin
                    vpos <= vpos + 10'd1;
                end
            end else begin
                hpos <= hpos + 10'd1;
            end
        end
    end

    // FSM steps once every 16 frames (~0.27 s) unless fast mode is set
    wire slow_tick = frame_end && (frame_cnt[3:0] == 4'hF);
    wire step      = fast | slow_tick;
    wire blink     = frame_cnt[4];

    // ---------------- controller ----------------
    wire [2:0] state, move_cmd;
    wire [1:0] align_cmd;
    wire       inspect_enable, abort_cmd, target_locked;

    kibo_leak_fsm fsm (
        .clk(clk), .rst(rst), .step(step), .in(inputs),
        .state(state), .move_cmd(move_cmd), .align_cmd(align_cmd),
        .inspect_enable(inspect_enable), .abort_cmd(abort_cmd),
        .target_locked(target_locked)
    );

    // ---------------- display ----------------
    // Rows (64 px each):  0 banner | 1 states | 2 inputs | 3 move_cmd |
    //                     4 align_cmd | 5 lamps | 6 mission progress
    // Cells are 64 px wide starting at x = 64 (8 cells max), 56 px inner box.
    function [5:0] state_color(input [2:0] s);
        case (s)
            3'd0:    state_color = 6'b101010;   // IDLE     grey
            3'd1:    state_color = 6'b001011;   // SEARCH   light blue
            3'd2:    state_color = 6'b000111;   // APPROACH blue
            3'd3:    state_color = 6'b111100;   // ALIGN    yellow
            3'd4:    state_color = 6'b111000;   // HOLD     orange
            3'd5:    state_color = 6'b110011;   // INSPECT  magenta
            3'd6:    state_color = 6'b001100;   // COMPLETE green
            default: state_color = 6'b110000;   // ABORT    red
        endcase
    endfunction

    wire active = (hpos < 10'd640) && (vpos < 10'd480);

    wire [3:0] cx     = hpos[9:6];
    wire [3:0] cy     = vpos[9:6];
    wire       col_ok = (cx >= 4'd1) && (cx <= 4'd8);
    wire [3:0] idx    = cx - 4'd1;
    wire       in_x   = (hpos[5:0] >= 6'd4) && (hpos[5:0] <= 6'd59);
    wire       in_y   = (vpos[5:0] >= 6'd4) && (vpos[5:0] <= 6'd59);
    wire       band_y = (vpos[5:0] >= 6'd8) && (vpos[5:0] <= 6'd55);
    wire       in_cell   = col_ok && in_x && in_y;
    wire [2:0] i3     = idx[2:0];

    reg [5:0] pix;
    always @(*) begin
        pix = 6'b000000;
        if (active) begin
            pix = C_BG;
            case (cy)
                4'd0: if (col_ok && band_y)
                          pix = (state == ABORT && !blink) ? C_DARKRED : state_color(state);

                4'd1: if (in_cell)
                          pix = (i3 == state) ? state_color(state) : C_DIM;

                4'd2: if (in_cell)
                          pix = inputs[i3] ? ((i3 == 3'd5 || i3 == 3'd6) ? C_RED : C_WHITE)
                                           : C_DIM;

                4'd3: if (in_cell && idx < 4'd7)
                          pix = (i3 == move_cmd) ? ((i3 == 3'd0) ? C_WHITE : C_CYAN)
                                                 : C_DIM;

                4'd4: if (in_cell && idx < 4'd4)
                          pix = (i3[1:0] == align_cmd)
                                ? ((align_cmd == 2'b11) ? C_GREEN : C_YELLOW)
                                : C_DIM;

                4'd5: if (in_cell && idx < 4'd3) begin
                          case (i3[1:0])
                              2'd0:    pix = inspect_enable ? C_MAGENTA : C_DIM;
                              2'd1:    pix = target_locked  ? C_GREEN   : C_DIM;
                              default: pix = abort_cmd ? (blink ? C_RED : C_DARKRED) : C_DIM;
                          endcase
                      end

                4'd6: if (in_cell && idx < 4'd7) begin
                          if (state == ABORT)         pix = C_RED;
                          else if (state == COMPLETE) pix = C_GREEN;
                          else                        pix = (state > i3) ? C_CYAN : C_DIM;
                      end

                default: ;
            endcase
        end
    end

    // Register sync and colour together so they stay aligned
    reg       hs, vs;
    reg [5:0] rgb;
    always @(posedge clk) begin
        if (rst) begin
            hs  <= 1'b1;
            vs  <= 1'b1;
            rgb <= 6'd0;
        end else begin
            hs  <= ~((hpos >= 10'd656) && (hpos < 10'd752));
            vs  <= ~((vpos >= 10'd490) && (vpos < 10'd492));
            rgb <= pix;
        end
    end

    // ---------------- pins ----------------
    assign uo_out  = {hs, rgb[0], rgb[2], rgb[4], vs, rgb[1], rgb[3], rgb[5]};
    assign uio_out = {2'b00, target_locked, abort_cmd, inspect_enable, state};
    assign uio_oe  = 8'b0011_1111;

    wire _unused = &{ena, uio_in[6:0], 1'b0};

endmodule
