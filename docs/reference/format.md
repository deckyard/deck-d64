<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# The D64 format on disk

Every byte offset the deck implements, in hexadecimal, relative to the start
of the block.

## The image

The blocks of the disk back to back, in track order, then sector order. One
error byte per block may follow.

| Tracks | Blocks | Plain | With error table |
|---:|---:|---:|---:|
| 35 | 683 | 174,848 | 175,531 |
| 40 | 768 | 196,608 | 197,376 |
| 42 | 802 | 205,312 | 206,114 |

There is no header; the six sizes are distinct, so the length gives the
geometry.

### Zones

| Tracks | Sectors each |
|---|---:|
| 1-17 | 21 |
| 18-24 | 19 |
| 25-30 | 18 |
| 31-42 | 17 |

Tracks 36-42 are beyond a stock drive's range; every extended format uses the
innermost zone's 17 sectors.

`offset(track, sector) = (totalSectors(track - 1) + sector) * 256`

## Sector 18/0 - the BAM

| Offset | Content |
|---|---|
| `$00`-`$01` | track/sector of the first directory block - `18 / 1` |
| `$02` | DOS version byte, `$41` (`'A'`) |
| `$03` | unused, `$00` |
| `$04`-`$8f` | BAM entries for tracks 1-35, four bytes each |
| `$90`-`$9f` | disk name, 16 bytes, PETSCII padded with `$a0` |
| `$a0`-`$a1` | `$a0 $a0` |
| `$a2`-`$a3` | disk ID, two bytes |
| `$a4` | `$a0` |
| `$a5`-`$a6` | DOS type, `"2A"` (`$32 $41`) |
| `$a7`-`$aa` | `$a0 $a0 $a0 $a0` |
| `$ab`-`$ff` | unused on a stock disk - see below |

### A BAM entry

Four bytes per track: a free-sector count, then a 24-bit map where a **set bit
means free**. Sector *n* is bit *n % 8* of byte `1 + n / 8`. Bits past the end
of the track stay clear.

```
track 1, all free:       15 ff ff 1f  21 free, bits 0-20 set
track 18, fresh disk:    11 fc ff 07  17 free, bits 0 and 1 clear
```

### The 40-track extensions

Each speeder DOS put the five entries for tracks 36-40 in a different place:

| Format | Tracks 36-40 | Disk header |
|---|---|---|
| CBM | - | `$90` |
| SpeedDOS | `$c0`-`$d3` | `$90` |
| DolphinDOS | `$ac`-`$bf` | `$90` |
| PrologicDOS | `$90`-`$a3` | `$a4` |

PrologicDOS put the entries over the disk name and moved the whole header -
name, filler, ID, filler, DOS type, filler - up 20 bytes, so its DOS type sits
at `$b9`-`$ba`. `detectFormat` tests for that first.

No format ever defined entries for tracks 41 and 42.

## Track 18 - the directory

A chain from 18/1, each block linked by its first two bytes, at interleave 3
(18/1, 18/4, 18/7, and so on). 18 blocks fit, 8 slots each: 144 files
maximum.

On the last block of the chain the link is `$00 $ff`.

### A directory slot

| Offset | Content |
|---|---|
| `$00`-`$01` | track/sector of the next directory block - **first slot only**, `$00 $00` in the rest |
| `$02` | file type byte |
| `$03`-`$04` | track/sector of the file's first block |
| `$05`-`$14` | filename, 16 bytes, PETSCII padded with `$a0` |
| `$15`-`$16` | track/sector of the first side-sector block, REL only |
| `$17` | record length, REL only, at most 254 |
| `$18`-`$1d` | unused (GEOS uses them) |
| `$1e`-`$1f` | file length in blocks, low byte first |

Slots start at `$00`, `$20`, `$40`, `$60`, `$80`, `$a0`, `$c0`, `$e0`.

### The file type byte

Bits 0-3 are the type. Values 5-15 are invalid and a real drive's behaviour
on them is undefined; the deck reads them as DEL.

| Value | Type |
|---:|---|
| 0 | DEL |
| 1 | SEQ |
| 2 | PRG |
| 3 | USR |
| 4 | REL |

| Bit | Meaning |
|---:|---|
| 6 | locked - lists as `<`, `SCRATCH` refuses it |
| 7 | closed - clear means a "splat" file, listed with a leading `*` |

So `$82` is a closed PRG, `$c2` a closed locked PRG, `$02` an unclosed PRG,
and `$00` a scratched slot.

**A scratch zeroes the type byte and nothing else** in the slot. The name and
first-block pointer remain, and the file's blocks are freed in the BAM.

## A file

A linked list of blocks at an interleave of 10.

| Offset | Content |
|---|---|
| `$00` | track of the next block, or `$00` in the last one |
| `$01` | sector of the next block - or, when `$00` is zero, the **length** |
| `$02`-`$ff` | payload, 254 bytes |

In the last block a length byte of `n` means bytes `$02`-`$n` are file data:
`n - 1` payload bytes. `$02` is one byte, `$ff` the full 254, `$01` none (an
empty file). `$00` is not a length; the deck throws on it.

A PRG's first two payload bytes are its load address, low byte first: `$01
$08` is `$0801`, the start of BASIC on a C64.

## Sources

- [C64-Wiki: D64](https://www.c64-wiki.de/wiki/D64) - container, sizes, zones.
- Peter Schepers, *D64 (Electronic form of a physical 1541 disk)*, rev 1.11 -
  BAM, directory, chain, and the three speeder BAM offsets.
- [VICE](https://vice-emu.sourceforge.io/) - reference implementation these
  offsets were checked against.
