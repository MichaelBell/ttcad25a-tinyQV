# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

from riscvmodel.insn import *

from riscvmodel.regnames import x0, gp, tp, a0, a1

import test_util as tqv

BASE_ADDRESS = 0x410
PERIPHERAL_NUM = 17

REG_LEVEL = 0x00
REG_COUNT = 0x01

async def write_reg(dut, reg, value):
    await tqv.send_instr(dut, InstructionADDI(a0, tp, BASE_ADDRESS).encode())
    await tqv.send_instr(dut, InstructionADDI(a1, x0, value).encode())
    await tqv.send_instr(dut, InstructionSB(a0, a1, reg).encode())


async def read_reg(dut, reg):
    await tqv.send_instr(dut, InstructionADDI(a0, tp, BASE_ADDRESS).encode())
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

    # Set all outputs to PWM
    await tqv.set_all_outputs_to_peripheral(dut, PERIPHERAL_NUM)

    # Set the input values you want to test
    await write_reg(dut, REG_LEVEL, 128)
    value = await read_reg(dut, REG_LEVEL)
    assert value == 128

    # Counter should count up
    value1 = await read_reg(dut, REG_COUNT)
    value2 = await read_reg(dut, REG_COUNT)

    if value2 < value1: value2 += 255
    assert value2 - value1 > 90
    assert value2 - value1 < 160

    for level in (0, 1, 66, 128, 203, 255):
        await write_reg(dut, REG_LEVEL, level)

        tqv.start_nops(dut)
        await ClockCycles(dut.clk, 24)
            
        count = 0
        for i in range(255):
            count += dut.uo_out.value & 1
            assert dut.uo_out.value == 0xff or dut.uo_out.value == 0
            await ClockCycles(dut.clk, 1)

        assert count == level

        await tqv.stop_nops()
