import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge

IDLE, SEARCH, APPROACH, ALIGN, HOLD, INSPECT, COMPLETE, ABORT = range(8)

TARGET_DETECTED = 1 << 0
TARGET_REACHED = 1 << 1
POSITION_ALIGNED = 1 << 2
ORIENTATION_ALIGNED = 1 << 3
INSPECTION_DONE = 1 << 4
OBSTACLE = 1 << 5
FAULT = 1 << 6
NEW_TARGET = 1 << 7

FAST_STEP = 0x80  # uio_in[7]: FSM steps every clock (simulation only)


def uio(dut):
    return int(dut.uio_out.value)


def state(dut):
    return uio(dut) & 0x7


def inspect_enable(dut):
    return (uio(dut) >> 3) & 1


def abort_cmd(dut):
    return (uio(dut) >> 4) & 1


def target_locked(dut):
    return (uio(dut) >> 5) & 1


async def tick(dut, n=1):
    for _ in range(n):
        await FallingEdge(dut.clk)


async def wait_state(dut, target, timeout=30):
    """Wait (sampling every cycle) until the FSM reaches `target`."""
    for _ in range(timeout):
        if state(dut) == target:
            return
        await tick(dut)
    raise AssertionError(f"timed out waiting for state {target}, still in {state(dut)}")


async def reset(dut, fast=True):
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = FAST_STEP if fast else 0
    dut.rst_n.value = 0
    await tick(dut, 4)
    dut.rst_n.value = 1
    await tick(dut, 1)


async def start(dut, fast=True):
    # If the template's test.py uses `units="us"`, change `unit` below to match.
    cocotb.start_soon(Clock(dut.clk, 40, units="ns").start())
    await reset(dut, fast)


async def drive_to_inspect(dut):
    dut.ui_in.value = TARGET_DETECTED
    await wait_state(dut, APPROACH)

    dut.ui_in.value = TARGET_DETECTED | TARGET_REACHED
    await wait_state(dut, ALIGN)

    dut.ui_in.value = TARGET_DETECTED | TARGET_REACHED | POSITION_ALIGNED | ORIENTATION_ALIGNED
    await wait_state(dut, INSPECT)  # passes through HOLD
    assert inspect_enable(dut) == 1


@cocotb.test()
async def test_happy_path(dut):
    await start(dut)
    assert state(dut) == IDLE

    await drive_to_inspect(dut)

    dut.ui_in.value = INSPECTION_DONE
    await wait_state(dut, COMPLETE)
    assert target_locked(dut) == 1
    assert inspect_enable(dut) == 0

    # No new target -> back to IDLE
    await wait_state(dut, IDLE)


@cocotb.test()
async def test_new_target_returns_to_search(dut):
    await start(dut)
    await drive_to_inspect(dut)

    dut.ui_in.value = INSPECTION_DONE | NEW_TARGET
    await wait_state(dut, COMPLETE)
    await wait_state(dut, SEARCH)
    await tick(dut, 3)
    assert state(dut) == SEARCH


@cocotb.test()
async def test_abort_beats_complete_and_latches(dut):
    await start(dut)
    await drive_to_inspect(dut)

    # inspection_done and obstacle in the same cycle -> ABORT, never COMPLETE
    dut.ui_in.value = INSPECTION_DONE | OBSTACLE
    for _ in range(10):
        await tick(dut)
        assert state(dut) != COMPLETE
        if state(dut) == ABORT:
            break
    assert state(dut) == ABORT
    assert abort_cmd(dut) == 1
    assert inspect_enable(dut) == 0

    # Clearing the input does not leave ABORT
    dut.ui_in.value = 0
    await tick(dut, 8)
    assert state(dut) == ABORT

    # Only reset clears it
    await reset(dut)
    assert state(dut) == IDLE
    assert abort_cmd(dut) == 0


@cocotb.test()
async def test_fault_aborts_from_idle(dut):
    await start(dut)
    dut.ui_in.value = FAULT
    await wait_state(dut, ABORT)


@cocotb.test()
async def test_slow_mode_does_not_step_every_clock(dut):
    # With fast_step low the FSM only steps once per 16 video frames,
    # so nothing should happen within a couple of hundred clocks.
    await start(dut, fast=False)
    dut.ui_in.value = TARGET_DETECTED
    await tick(dut, 200)
    assert state(dut) == IDLE


@cocotb.test()
async def test_vga_hsync_and_blanking(dut):
    await start(dut)
    falls = []
    prev = (int(dut.uo_out.value) >> 7) & 1
    cycle = 0
    while len(falls) < 3 and cycle < 3000:
        await tick(dut)
        cycle += 1
        out = int(dut.uo_out.value)
        cur = (out >> 7) & 1
        if prev == 1 and cur == 0:
            falls.append(cycle)
        if cur == 0:
            # colour bits (B0,G0,R0,B1,G1,R1) must be 0 during hsync/blanking
            assert (out & 0x77) == 0
        prev = cur
    assert len(falls) == 3
    assert falls[1] - falls[0] == 800
    assert falls[2] - falls[1] == 800
