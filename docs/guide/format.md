<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Formatting a disk

`formatDisk` is `NEW0:NAME,ID` on a 1541: a blank BAM and disk header in
18/0, one empty directory block in 18/1, every other block free.

```jennifer
use io;
import "@deckyard/d64/" as d64;

def img as d64.Image init d64.formatDisk("sample disk", "01");

len(d64.toBytes($img));   # 174848
d64.blocksFree($img);     # 664
d64.diskName($img);       # "sample disk"
d64.diskId($img);         # "01"
d64.dosType($img);        # "2a"
```

664, not 683: like the drive, `blocksFree` leaves out track 18. The name is
1 to 16 characters, the ID one or two (one is padded with `$a0`); write both
lower case.

## Geometries

`formatDiskWith` takes a `FormatOptions`. A zero field takes its default.

```jennifer
def opts as d64.FormatOptions init d64.FormatOptions{
    tracks: 40,
    format: d64.DiskFormat.SpeedDos,
    errorInfo: false,
    dosType: "", fill: 0, mode: d64.FormatMode.Full
};
def img as d64.Image init d64.formatDiskWith($opts, "forty track", "40");

len(d64.toBytes($img));   # 196608
d64.blocksFree($img);     # 749
```

| Tracks | Blocks | Plain | With error table |
|---:|---:|---:|---:|
| 35 | 683 | 174,848 | 175,531 |
| 40 | 768 | 196,608 | 197,376 |
| 42 | 802 | 205,312 | 206,114 |

`imageSize(tracks, errorInfo)` computes these; `tracksForSize(n)` and
`sizeHasErrorInfo(n)` invert it. `fromBytes` takes the geometry from the
length.

## The four BAM layouts

Tracks 1-35 have entries at `$04`-`$8f`, then comes the disk header. Each
40-track speeder DOS put the entries for tracks 36-40 somewhere else:

| `DiskFormat` | Tracks 36-40 | Header |
|---|---|---|
| `Cbm` | *none* | `$90` |
| `SpeedDos` | `$c0`-`$d3` | `$90` |
| `DolphinDos` | `$ac`-`$bf` | `$90` |
| `PrologicDos` | `$90`-`$a3` | `$a4` |

PrologicDOS put them over the disk name and moved the header up 20 bytes.
Every BAM call goes through `headerOffsetFor` and `bamEntryOffset`.

```jennifer
d64.bamEntryOffset(d64.DiskFormat.SpeedDos, 36);     # 192 ($c0)
d64.bamEntryOffset(d64.DiskFormat.DolphinDos, 36);   # 172 ($ac)
d64.bamEntryOffset(d64.DiskFormat.Cbm, 36);          # -1
```

### 40 tracks in the stock layout

Allowed, and a stock drive reads it, but tracks 36-40 have no BAM entry, so
nothing is allocated there.

```jennifer
def plain as d64.FormatOptions init d64.FormatOptions{
    tracks: 40, format: d64.DiskFormat.Cbm, errorInfo: false, dosType: "", fill: 0, mode: d64.FormatMode.Full
};
def img as d64.Image init d64.formatDiskWith($plain, "plain forty", "01");

d64.blocksFree($img);          # 664, not 749
d64.hasBamEntry($img, 36);     # false
d64.isFree($img, 36, 0);       # false - unavailable
```

A speeder layout on 35 tracks throws.

### Tracks 41 and 42

No layout has BAM entries for them. `readSector` and `writeSector` reach
them; the allocator and `blocksFree` do not.

## Detection

`fromBytes` and `open` call `detectFormat` on sector 18/0:

1. 35 tracks: `Cbm`.
2. DOS type `"2a"` (`$32 $41`) at `$b9` instead of `$a5`: `PrologicDos`.
3. A plausible region at `$c0`: `SpeedDos`; else at `$ac`: `DolphinDos`.
   Plausible means all five counts are 17 or less and at least one is
   non-zero.
4. Otherwise `Cbm`.

When you know the layout, override the guess:

```jennifer
def img as d64.Image init d64.withFormat(d64.open("mystery.d64"),
    d64.DiskFormat.DolphinDos);
```

`withFormat` changes no bytes.

## Error tables

One byte per block after the block data: the read result a mastering tool
recorded. `$01` (`ERROR_OK`) is no error; other values are 1541 error codes.

```jennifer
def opts as d64.FormatOptions init d64.FormatOptions{
    tracks: 35, format: d64.DiskFormat.Cbm, errorInfo: true, dosType: "", fill: 0, mode: d64.FormatMode.Full
};
def img as d64.Image init d64.formatDiskWith($opts, "protected", "01");

d64.sectorError($img, 18, 0);                    # 1
$img = d64.setSectorError($img, 17, 3, 0x0b);    # data checksum error
$img = d64.clearErrorTable($img);
```

On an image without a table `sectorError` returns `ERROR_OK` for every block
and `setSectorError` throws.

## Quick and full

| | Writes | Leaves | On a 1541 |
|---|---|---|---|
| `reformat` / `FormatMode.Full` (`N0:NAME,ID`) | every block, then BAM + directory | nothing | ~1 minute |
| `quickFormat` / `FormatMode.Quick` (`N0:NAME`) | BAM + first directory block | every other block | instant |

```jennifer
$img = d64.reformat($img, "fresh", "02");    # full wipe, blocks set to $00
$img = d64.quickFormat($img, "fresh");       # soft format, ID kept
```

A quick format leaves the old files' bytes on the disk, unreachable. It keeps
the disk ID, as the drive does; two disks soft-formatted from one original
share an ID, which is how a real 1541 comes to use a stale BAM after a swap.

### The fill byte

A full format sets every block to `fill`, `$00` by default.

```jennifer
def opts as d64.FormatOptions init d64.defaultFormatOptions();
$opts.fill = 0xff;
$img = d64.reformatWith($img, $opts, "wiped", "02");

d64.readSector($img, 17, 0)[0];   # 255
```

`formatDiskWith` takes `fill` too. The error table is set to `ERROR_OK`, not
filled. `reformatWith` reads only `mode`, `fill` and `dosType` (`""` keeps the
image's own); geometry and layout come from the image.
