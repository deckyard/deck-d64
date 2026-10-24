# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * d64 - read, write, create and format Commodore 1541 disk images.
 *
 * A D64 file holds the 256-byte blocks of a 1541 disk back to back: 683 on
 * 35 tracks, in four zones of 21, 19, 18 and 17 sectors per track. Inside is
 * CBM DOS 2.6: the BAM in sector 18/0, a chain of 32-byte directory slots
 * from 18/1, and one linked list of blocks per file.
 *
 *   format   {@link formatDisk} / {@link formatDiskWith} / {@link reformat}
 *   list     {@link listFiles} / {@link findFiles} / {@link directoryText}
 *   read     {@link readFile} / {@link readText} / {@link readProgram}
 *   write    {@link writeFile} / {@link writeText} / {@link writeProgram}
 *   replace  {@link updateFile}
 *   scratch  {@link deleteFile}
 *   blocks   {@link readSector} / {@link writeSector} / {@link blocksFree}
 *
 * Four BAM layouts: `DiskFormat.Cbm`, the stock 35-track one, and
 * `SpeedDos`, `DolphinDos` and `PrologicDos`, which place the entries for
 * tracks 36-40 differently. {@link detectFormat} guesses the layout and
 * {@link withFormat} overrides it.
 *
 * Names and text are PETSCII. {@link toPetscii} and {@link fromPetscii} swap
 * case as `petcat` does, so `toPetscii("hello")` gives the bytes a C64 shows
 * as `HELLO`.
 *
 * A function that changes the disk returns a new `Image` and leaves its
 * argument untouched: `$img = something($img, ...)`. Every failure throws an
 * `Error` with `kind` {@link ERROR_KIND}.
 *
 * The topic files under `topics/` are spliced in with `include`; this file is
 * the module boundary. White-box tests: `d64_test.j`.
 *
 * @module d64
 * @see https://www.c64-wiki.de/wiki/D64
 * @example
 *   import "@deckyard/d64/" as d64;
 *
 *   def img as d64.Image init d64.formatDisk("sample disk", "01");
 *   $img = d64.writeText($img, "readme", d64.FileType.Seq, "hello\n");
 *   io.printf("%s", d64.directoryText($img));
 *   d64.save($img, "sample.d64");
 */

use strings;
use convert;
use binary;
use io;
use fs;

include "topics/version.j";
include "topics/core.j";
include "topics/geometry.j";
include "topics/petscii.j";
include "topics/format.j";
include "topics/image.j";
include "topics/bam.j";
include "topics/directory.j";
include "topics/files.j";
