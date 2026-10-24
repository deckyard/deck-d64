<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# @deckyard/d64

Read, write, create and format Commodore 1541 D64 disk images.

This deck is part of [Deckyard](https://github.com/deckyard), community decks for [Jennifer](https://jennifer-lang.dev/).

A D64 is the blocks of a 5.25" disk stored back to back with no header: 683
blocks of 256 bytes on a 35-track disk. Inside them is CBM DOS 2.6 - the BAM in
18/0, a chain of 32-byte directory slots from 18/1, one linked list of blocks
per file. Four BAM layouts are supported: stock 35-track `Cbm` and the 40-track
`SpeedDos`, `DolphinDos` and `PrologicDos`.

## Import

```jennifer
use io;
import "@deckyard/d64/" as d64;

def img as d64.Image init d64.formatDisk("sample disk", "01");
$img = d64.writeText($img, "readme", d64.FileType.Seq, "hello\n");
io.printf("%s", d64.directoryText($img));
d64.save($img, "sample.d64");
```

The trailing slash resolves to the entry module.

## Value semantics

Every function that changes the disk returns a new `Image` and leaves its
argument untouched:

```jennifer
def before as d64.Image init d64.formatDisk("work", "01");
def after as d64.Image init d64.writeText($before, "readme", d64.FileType.Seq, "hi\n");

len(d64.listFiles($before));   # 0
len(d64.listFiles($after));    # 1
```

The calling shape is `$img = something($img, ...)`. An operation that fails
part-way throws, and the caller's image is unchanged.

## Case

The transcoder swaps case, as `petcat` does: `toPetscii("hello")` gives the
bytes a C64 shows as `HELLO`. Write names lower case. See
[PETSCII](guide/petscii.md).

## Errors

Every failure is an `Error` with `kind` `"d64"` (`ERROR_KIND`).

```jennifer
try {
    $img = d64.writeFile($img, "toobig", d64.FileType.Prg, $huge);
} catch (e) {
    io.printf("%s\n", $e.message);
}
```

Thrown for, among others: a name that is empty, over 16 PETSCII characters or
already on the disk, a full disk, a full directory, a track or sector outside
the image, scratching a locked file, a block chain that loops, and a buffer
whose length is not a D64 size.

## Contents

| Page | Covers |
|---|---|
| [Formatting a disk](guide/format.md) | `formatDisk`, geometries, the four BAM layouts, error tables |
| [The directory](guide/directory.md) | listing, patterns, rename, lock, chain growth |
| [Reading and writing files](guide/files.md) | block chains, PRG load addresses, replace, scratch |
| [PETSCII](guide/petscii.md) | transcoder, filenames, wildcards |
| [Blocks and the BAM](guide/sectors.md) | raw blocks, allocation, interleave |
| [Drives and computers](reference/hardware.md) | 1540-1581, the machines, GCR and MFM |
| [The D64 format on disk](reference/format.md) | every byte offset |
| [Versioning](internal/versioning.md) | git tags, `VERSION`, CI injection |
| [Cheatsheet](reference/cheatsheet.md) | full API surface |

Runnable programs:
[`examples/`](https://github.com/deckyard/deck-d64/tree/main/examples).
