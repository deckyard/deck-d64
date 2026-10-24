<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Blocks and the BAM

Under the filesystem is a flat array of 256-byte blocks. `readSector` and
`writeSector` address it by track and sector, as the drive's block commands
do; the BAM calls say what is free.

## Geometry

Outer tracks hold more sectors (see [zone bit recording](../reference/hardware.md#gcr-and-mfm)).

| Tracks | Sectors each | Blocks |
|---|---:|---:|
| 1-17 | 21 | 357 |
| 18-24 | 19 | 133 |
| 25-30 | 18 | 108 |
| 31-35 | 17 | 85 |
| 36-40 | 17 | 85 |
| 41-42 | 17 | 34 |

The image stores blocks in track order, then sector order.

```jennifer
import "@deckyard/d64/" as d64;

d64.sectorsPerTrack(1);     # 21
d64.sectorsPerTrack(18);    # 19
d64.totalSectors(35);       # 683
d64.sectorOffset(1, 0);     # 0
d64.sectorOffset(18, 0);    # 91392 - the BAM
```

## Blocks

```jennifer
def bam as bytes init d64.readSector($img, 18, 0);
$bam[2];                                  # $41, DOS version byte

def block as bytes init d64.readSector($img, 1, 0);
$block[0] = 0xc7;
$img = d64.writeSector($img, 1, 0, $block);
```

`writeSector` throws unless given exactly 256 bytes. Both throw on an address
outside the image. **Neither consults the BAM.**

## Block ranges

Blocks are contiguous in the image, so a run reads or writes in one call.

```jennifer
def run as bytes init d64.readBlocks($img, d64.Link{track: 18, sector: 0}, 2);
len($run);   # 512 - the BAM and the first directory block

$img = d64.writeBlocks($img, d64.Link{track: 1, sector: 0}, $run);
```

A run continues past the last sector of a track at sector 0 of the next one,
and throws if it reaches past the last block of the image. `writeBlocks` takes
a non-empty whole multiple of 256 bytes.

These ignore the BAM too. Call `allocateSector` for blocks that must stay
claimed. Each block also has a flat number, 0 at 1/0:

```jennifer
d64.blockNumber(1, 0);     # 0
d64.blockNumber(18, 0);    # 357 - the BAM
d64.blockLink(357);        # Link{track: 18, sector: 0}
```

The whole block area as one run:

```jennifer
def all as bytes init d64.readBlocks($img, d64.Link{track: 1, sector: 0},
    d64.blockCount($img));
# equal to d64.toBytes($img) on an image with no error table
```

## The BAM

Four bytes per track: a free-sector count, then a 24-bit map where a **set bit
means free**. `blocksFree` sums the counts of every track but 18;
`trackBlocksFree` reads one count byte as stored.

```jennifer
d64.blocksFree($img);              # 664 on a fresh 35-track disk
d64.trackBlocksFree($img, 1);      # 21
d64.trackBlocksFree($img, 18);     # 17 of 19
d64.isFree($img, 17, 0);           # true
d64.isAllocated($img, 18, 0);      # true
```

```jennifer
$img = d64.allocateSector($img, 1, 0);
$img = d64.freeSector($img, 1, 0);
```

Both update the bit and the count. Both throw when the block is already in
the requested state: a double allocate would let two chains share a block, a
double free means count and bitmap have drifted.

A block on a track with no BAM entry (36-42 under `Cbm`, 41-42 under every
layout) is never free, and `allocateSector` and `freeSector` throw on it. See
[Formatting a disk](format.md).

## The allocator

```jennifer
def first as d64.Link init d64.nextFreeSector($img,
    d64.Link{track: 0, sector: 0}, d64.FILE_INTERLEAVE);
# 17/0 on a fresh disk

def next as d64.Link init d64.nextFreeSector($img, $first, d64.FILE_INTERLEAVE);
# 17/10
```

**Interleave.** On `near`'s track the search starts `interleave` sectors past
`near` and steps by `interleave` (10 for files, 3 for directory blocks), so the
next block reaches the head after the drive has handled the previous one. When
the steps miss sectors (10 and 18 share a factor) a linear sweep covers them.
`interleave` below 1 throws.

**Spiral.** When `near`'s track is full, or `near` is `Link{track: 0, sector: 0}`,
the search moves outward from track 18: 17, 19, 16, 20, 15, 21, and so on,
starting each track at sector 0. Track 18 and tracks without a BAM entry are
never used.

```jennifer
d64.trackSearchOrder($img, 0);    # [17, 19, 16, 20, 15, 21, ...]
d64.trackSearchOrder($img, 30);   # [30, 17, 19, 16, ...]
```

`nextFreeSector` throws when nothing is free.

## Outside the filesystem

A block claimed in the BAM and written without a directory entry:

```jennifer
$img = d64.allocateSector($img, 1, 0);
def block as bytes init d64.readSector($img, 1, 0);
$block[0] = 0xc7;
$block[1] = 0x00;
$img = d64.writeSector($img, 1, 0, $block);
```

The allocator will not use the block, and `readSector` reads it back. Tracks
41 and 42 are outside every BAM layout, so files never land there.
