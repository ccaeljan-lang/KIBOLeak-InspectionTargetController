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


def state(dut):
    return int(dut.uio_out.value) & 0x7


def abort_cmd(dut):
    return (int(dut.uo_out.value) >> 6) & 1


def inspect_enable(dut):
    return (int(dut.uo_out.value) >> 5) & 1


def target_locked(dut):
    return (int(dut.uo_out.value) >> 7) & 1


async def tick(dut, n=1):
    for _ in range(n):
        await FallingEdge(dut.clk)


async def reset(dut):
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await tick(dut, 3)
    dut.rst_n.value = 1
    await tick(dut, 1)


async def start(dut):
    # If the template's test.py uses `units="us"`, change `unit` below to match.
    cocotb.start_soon(Clock(dut.clk, 10, units="us").start())
    await reset(dut)


async def drive_to_inspect(dut):
    dut.ui_in.value = TARGET_DETECTED
    await tick(dut, 2)
    assert state(dut) == APPROACH

    dut.ui_in.value = TARGET_DETECTED | TARGET_REACHED
    await tick(dut, 1)
    assert state(dut) == ALIGN

    dut.ui_in.value = TARGET_DETECTED | TARGET_REACHED | POSITION_ALIGNED | ORIENTATION_ALIGNED
    await tick(dut, 1)
    assert state(dut) == HOLD

    # Hold runs for a few cycles, then moves on to INSPECT
    for _ in range(6):
        await tick(dut, 1)
        if state(dut) == INSPECT:
            break
    assert state(dut) == INSPECT
    assert inspect_enable(dut) == 1


@cocotb.test()
async def test_happy_path(dut):
    await start(dut)
    assert state(dut) == IDLE

    await drive_to_inspect(dut)

    dut.ui_in.value = INSPECTION_DONE
    await tick(dut, 1)
    assert state(dut) == COMPLETE
    assert target_locked(dut) == 1
    assert inspect_enable(dut) == 0

    # No new target -> back to IDLE
    dut.ui_in.value = 0
    await tick(dut, 1)
    assert state(dut) == IDLE


@cocotb.test()
async def test_new_target_returns_to_search(dut):
    await start(dut)
    await drive_to_inspect(dut)

    dut.ui_in.value = INSPECTION_DONE
    await tick(dut, 1)
    assert state(dut) == COMPLETE

    dut.ui_in.value = NEW_TARGET
    await tick(dut, 1)
    assert state(dut) == SEARCH


@cocotb.test()
async def test_abort_beats_complete_and_latches(dut):
    await start(dut)
    await drive_to_inspect(dut)

    # inspection_done and obstacle in the same cycle -> ABORT, not COMPLETE
    dut.ui_in.value = INSPECTION_DONE | OBSTACLE
    await tick(dut, 1)
    assert state(dut) == ABORT
    assert abort_cmd(dut) == 1
    assert inspect_enable(dut) == 0

    # Clearing the input does not leave ABORT
    dut.ui_in.value = 0
    await tick(dut, 3)
    assert state(dut) == ABORT

    # Only reset clears it
    await reset(dut)
    assert state(dut) == IDLE
    assert abort_cmd(dut) == 0


@cocotb.test()
async def test_fault_aborts_from_idle(dut):
    await start(dut)
    dut.ui_in.value = FAULT
    await tick(dut, 1)
    assert state(dut) == ABORT
