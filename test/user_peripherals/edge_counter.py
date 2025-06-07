# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

from riscvmodel.insn import *

from riscvmodel.regnames import x0, gp, tp, a0, a1

import test_util as tqv


REG_RESET = 0x00
REG_INC = 0x01
REG_VALUE = 0x02
REG_CFG = 0x03

EDGE_NONE = 0
EDGE_RISING = 1
EDGE_FALLING = 2

async def write_reg(dut, reg, value):
    await tqv.send_instr(dut, InstructionADDI(a0, tp, 0x400).encode())
    await tqv.send_instr(dut, InstructionADDI(a1, x0, value).encode())
    await tqv.send_instr(dut, InstructionSB(a0, a1, reg).encode())


async def read_reg(dut, reg):
    await tqv.send_instr(dut, InstructionADDI(a0, tp, 0x400).encode())
    await tqv.send_instr(dut, InstructionLBU(a1, a0, reg).encode())
    return await tqv.read_reg(dut, a1)

@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")
    
    clock = Clock(dut.clk, 15.624, units="ns")
    cocotb.start_soon(clock.start())

    # Reset
    await tqv.reset(dut)
    
    # Should start reading flash after 1 cycle
    await ClockCycles(dut.clk, 1)
    await tqv.start_read(dut, 0)

    dut._log.info("Test register access")

    # Set all outputs to edge detector
    await tqv.send_instr(dut, InstructionADDI(a0, x0, 0xc0).encode())
    await tqv.send_instr(dut, InstructionSW(tp, a0, 0xc).encode())
    await tqv.send_instr(dut, InstructionADDI(a0, x0, 16).encode())
    for func_sel in range(0x60, 0x80, 4):
        await tqv.send_instr(dut, InstructionSW(tp, a0, func_sel).encode())

    # Set the input values you want to test
    await write_reg(dut, REG_RESET, 0)
    await write_reg(dut, REG_INC, 1)
    await write_reg(dut, REG_INC, 1)
    await write_reg(dut, REG_INC, 1)
    value = await read_reg(dut, REG_VALUE)
    assert value == 3

    dut._log.info("Test seven segment display")
    assert dut.uo_out.value == 0b01001111  # 3 encoded for seven segment display

    dut._log.info("Test rising edge detection")
    await write_reg(dut, REG_CFG, EDGE_RISING)
    await write_reg(dut, REG_RESET, 0)
    value = await read_reg(dut, REG_VALUE)
    dut.ui_in.value = 0x01
    #await ClockCycles(dut.clk, 20)
    value = await read_reg(dut, REG_VALUE)
    assert value == 1

    dut.ui_in.value = 0x00
    #await ClockCycles(dut.clk, 10)
    value = await read_reg(dut, REG_VALUE)
    assert value == 1

    dut.ui_in.value = 0x01
    #await ClockCycles(dut.clk, 1)
    value = await read_reg(dut, REG_VALUE)
    assert value == 2

    dut._log.info("Test falling edge detection")
    await write_reg(dut, REG_CFG, EDGE_FALLING)
    await write_reg(dut, REG_RESET, 0)
    value = await read_reg(dut, REG_VALUE)
    dut.ui_in.value = 0x00
    #await ClockCycles(dut.clk, 10)
    value = await read_reg(dut, REG_VALUE)
    assert value == 1

    dut.ui_in.value = 0x01
    #await ClockCycles(dut.clk, 1)
    value = await read_reg(dut, REG_VALUE)
    assert value == 1

    dut.ui_in.value = 0x00
    #await ClockCycles(dut.clk, 10)
    value = await read_reg(dut, REG_VALUE)
    assert value == 2

    assert dut.uo_out.value == 0b01011011  # 2 encoded for seven segment display
