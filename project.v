/*
 * KIBO Leak-Inspection Target Controller
 * Tiny Tapeout / Wokwi top-level module.
 *
 * Pin map
 * -------
 * ui_in[0] target_detected
 * ui_in[1] target_reached
 * ui_in[2] position_aligned
 * ui_in[3] orientation_aligned
 * ui_in[4] inspection_done
 * ui_in[5] obstacle_detected
 * ui_in[6] system_fault
 * ui_in[7] new_target
 *
 * uo_out[2:0] move_cmd
 * uo_out[4:3] align_cmd
 * uo_out[5]   inspect_enable
 * uo_out[6]   abort_cmd
 * uo_out[7]   target_locked
 *
 * uio_out[2:0] state (debug)
 *
 * rst_n is the Tiny Tapeout active-low reset (internal rst = ~rst_n).
 * hold_complete is generated internally by a small counter.
 */

`default_nettype none

module tt_um_kibo_leak_inspect (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: input path
    output wire [7:0] uio_out,  // IOs: output path
    output wire [7:0] uio_oe,   // IOs: enable path (1 = output)
    input  wire       ena,      // always 1 when powered
    input  wire       clk,      // clock
    input  wire       rst_n     // reset, active low
);

    // ---------------------------------------------------------------
    // Input naming
    // ---------------------------------------------------------------
    wire rst                 = ~rst_n;
    wire target_detected     = ui_in[0];
    wire target_reached      = ui_in[1];
    wire position_aligned    = ui_in[2];
    wire orientation_aligned = ui_in[3];
    wire inspection_done     = ui_in[4];
    wire obstacle_detected   = ui_in[5];
    wire system_fault        = ui_in[6];
    wire new_target          = ui_in[7];

    // ---------------------------------------------------------------
    // Encodings
    // ---------------------------------------------------------------
    localparam [2:0] IDLE     = 3'b000,
                     SEARCH   = 3'b001,
                     APPROACH = 3'b010,
                     ALIGN    = 3'b011,
                     HOLD     = 3'b100,
                     INSPECT  = 3'b101,
                     COMPLETE = 3'b110,
                     ABORT    = 3'b111;

    localparam [2:0] MOVE_STOP     = 3'b000,
                     MOVE_FORWARD  = 3'b001,
                     MOVE_BACKWARD = 3'b010,
                     MOVE_LEFT     = 3'b011,
                     MOVE_RIGHT    = 3'b100,
                     MOVE_UP       = 3'b101,
                     MOVE_DOWN     = 3'b110;

    localparam [1:0] ALIGN_NONE   = 2'b00,
                     ALIGN_LEFT   = 2'b01,
                     ALIGN_RIGHT  = 2'b10,
                     ALIGN_DONE   = 2'b11;

    // Number of clock cycles to hold position before inspecting
    localparam [1:0] HOLD_CYCLES = 2'd3;

    // ---------------------------------------------------------------
    // State register + hold counter
    // ---------------------------------------------------------------
    reg [2:0] state, next_state;
    reg [1:0] hold_cnt;

    wire hold_complete = (hold_cnt == HOLD_CYCLES);
    wire safety_trip   = system_fault | obstacle_detected;

    always @(posedge clk) begin
        if (rst) begin
            state    <= IDLE;
            hold_cnt <= 2'd0;
        end else begin
            state <= next_state;
            if (state == HOLD && !hold_complete)
                hold_cnt <= hold_cnt + 2'd1;
            else if (state != HOLD)
                hold_cnt <= 2'd0;
        end
    end

    // ---------------------------------------------------------------
    // Next-state logic (safety has highest priority)
    // ---------------------------------------------------------------
    always @(*) begin
        next_state = state;

        if (state == ABORT) begin
            next_state = ABORT;              // latched until reset
        end else if (safety_trip) begin
            next_state = ABORT;              // fault/obstacle beats everything
        end else begin
            case (state)
                IDLE:     if (target_detected)                         next_state = SEARCH;
                SEARCH:   if (target_detected)                         next_state = APPROACH;
                APPROACH: if (target_reached)                          next_state = ALIGN;
                ALIGN:    if (position_aligned && orientation_aligned) next_state = HOLD;
                HOLD:     if (hold_complete)                           next_state = INSPECT;
                INSPECT:  if (inspection_done)                         next_state = COMPLETE;
                COMPLETE: next_state = new_target ? SEARCH : IDLE;
                default:  next_state = ABORT;
            endcase
        end
    end

    // ---------------------------------------------------------------
    // Output logic (Moore)
    // ---------------------------------------------------------------
    reg [2:0] move_cmd;
    reg [1:0] align_cmd;
    reg       inspect_enable;
    reg       abort_cmd;
    reg       target_locked;

    always @(*) begin
        move_cmd       = MOVE_STOP;
        align_cmd      = ALIGN_NONE;
        inspect_enable = 1'b0;
        abort_cmd      = 1'b0;
        target_locked  = 1'b0;

        case (state)
            APPROACH: begin
                move_cmd = MOVE_FORWARD;
            end

            ALIGN: begin
                // Placeholder corrections until error values replace the flags
                move_cmd = position_aligned ? MOVE_STOP : MOVE_FORWARD;
                if (!orientation_aligned)
                    align_cmd = ALIGN_LEFT;
                else if (position_aligned)
                    align_cmd = ALIGN_DONE;
            end

            HOLD: begin
                align_cmd = ALIGN_DONE;
            end

            INSPECT: begin
                align_cmd      = ALIGN_DONE;
                inspect_enable = 1'b1;
            end

            COMPLETE: begin
                target_locked = 1'b1;
            end

            ABORT: begin
                abort_cmd = 1'b1;
            end

            default: ;
        endcase
    end

    // ---------------------------------------------------------------
    // Pin assignments
    // ---------------------------------------------------------------
    assign uo_out  = {target_locked, abort_cmd, inspect_enable, align_cmd, move_cmd};
    assign uio_out = {5'b00000, state};
    assign uio_oe  = 8'b0000_0111;

    // Unused inputs
    wire _unused = &{ena, uio_in, 1'b0};

endmodule
