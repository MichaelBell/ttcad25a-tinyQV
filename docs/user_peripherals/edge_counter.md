<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

Edge counter peripheral for TinyQV that counts the number of edges on the `edge_detect` (ui_in[0]) pin.

## How to test

The edge counter is a peripheral for TinyQV that counts the number of edges on the `edge_detect` pin.

It has four 8-bit registers:

| Address | Name  | Access | Description                                                         |
|---------|-------|--------|---------------------------------------------------------------------|
| 0x00    | RESET | W      | Resets the counter to 0                                             |
| 0x01    | INC   | W      | Increments the counter by 1                                         |
| 0x02    | VALUE | R/W    | Reads the current value of the counter                              |
| 0x03    | CFG   | R/W    | Edge detection configuration: 0 = disabled, 1 = rising, 2 = falling |

The lower 4 bits of the counter are displayed on the 7-segment display. The DP is lit when the counter is greater than 0x0F.

## Prompt

The peripheral was created by ChatGPT o3 using the following prompt:

```
Adapt this to an edge counter peripheral:

It has four registers, with the following functions:
1. Write to resets the counter
2. Write to increments the counter
3. Reads/writes the current value.
4. Configures edge counting: 0 - no counting, 1 - ui_in[0] rising edges, 2 - ui_in[0] falling edges

Counter is 8 bits.

The counter low nibble is displayed as HEX value on ui_out on 7-segment, using the following mapping:

segment uo_out[0] is segment A .. uo_out[6] is segment G, uo_out[7] is DP.

If the counter > 15, then DP goes high.
```

The prompt was followed by the sample peripheral code from the [TinyQV project sources](https://github.com/MichaelBell/ttcad25a-tinyQV/blob/main/src/peri_simple_example.v).
