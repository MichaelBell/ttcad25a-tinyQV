# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import random

import cocotb
from cocotb.clock import Clock, Timer
from cocotb.triggers import ClockCycles

from riscvmodel.insn import *

from riscvmodel.regnames import x0, gp, tp, a0, a1
from riscvmodel import csrnames

import test_util as tqv

BASE_ADDRESS = 0x100
PERIPHERAL_NUM = 4

REG_ENABLE = 0x00
REG_CONTROLLER1 = 0x04
REG_CONTROLLER2 = 0x08
REG_INTR = 0x10

async def write_reg(dut, reg, value):
    await tqv.send_instr(dut, InstructionADDI(a0, tp, BASE_ADDRESS).encode())
    await tqv.send_instr(dut, InstructionADDI(a1, x0, value).encode())
    await tqv.send_instr(dut, InstructionSW(a0, a1, reg).encode())


async def read_reg(dut, reg):
    await tqv.send_instr(dut, InstructionADDI(a0, tp, BASE_ADDRESS).encode())
    await tqv.send_instr(dut, InstructionLW(a1, a0, reg).encode())
    return await tqv.read_reg(dut, a1)

async def send_game_data(dut, game_word):
    tqv.start_nops(dut)

    val = game_word
    for _ in range(24):
        dut.game_data.value = (1 if val & 0x800000 else 0)
        await Timer(5, "us")
        dut.game_clk.value = 1
        await Timer(5, "us")
        dut.game_clk.value = 0
        val <<= 1
    
    await Timer(5, "us")
    dut.game_latch.value = 1
    await Timer(5, "us")
    dut.game_latch.value = 0
    await tqv.stop_nops()


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

    # Initial state
    value = await read_reg(dut, REG_ENABLE)
    assert value == 0
    value = await read_reg(dut, REG_CONTROLLER1)
    assert value == 0xFFF
    value = await read_reg(dut, REG_CONTROLLER2)
    assert value == 0xFFF

    await write_reg(dut, REG_ENABLE, 1)
    value = await read_reg(dut, REG_ENABLE)
    assert value == 1

    dut._log.info("Test data read")
    was_select_pressed = 1

    for i in range(10):
        game_word = random.randint(0, 0xffffff)
        await send_game_data(dut, game_word)

        value = await read_reg(dut, REG_CONTROLLER1)
        assert value == game_word & 0xFFF
        value = await read_reg(dut, REG_CONTROLLER2)
        assert value == game_word >> 12

        value = await read_reg(dut, REG_INTR)
        select_pressed = game_word & 0x200
        if select_pressed and not was_select_pressed:
            assert value == 1
            await write_reg(dut, REG_INTR, 1)
            assert await read_reg(dut, REG_INTR) == 0
        else:
            assert value == 0
        was_select_pressed = select_pressed

        tqv.start_nops(dut)

    dut._log.info("Test interupt on controller 1 select")
    await send_game_data(dut, 0)
    assert await read_reg(dut, REG_INTR) == 0

    # Enable interrupt
    await tqv.send_instr(dut, InstructionLUI(a0, 0x100).encode())
    await tqv.send_instr(dut, InstructionCSRRW(x0, a0, csrnames.mie).encode())

    tqv.start_nops(dut)

    val = 0x200
    for _ in range(24):
        dut.game_data.value = (1 if val & 0x800000 else 0)
        await Timer(5, "us")
        dut.game_clk.value = 1
        await Timer(5, "us")
        dut.game_clk.value = 0
        val <<= 1
    
    await Timer(5, "us")
    await tqv.stop_nops()
    dut.game_latch.value = 1

    loops = 0
    while dut.qspi_flash_select.value == 0:
        await tqv.send_instr(dut, InstructionADDI(x0, x0, 0).encode(), True)
        assert loops < 2
        loops += 1

    await ClockCycles(dut.clk, 2)
    await tqv.start_read(dut, 8)
    await tqv.send_instr(dut, InstructionCSRRS(a1, x0, csrnames.mcause).encode())
    assert await tqv.read_reg(dut, a1) == 0x80000014
