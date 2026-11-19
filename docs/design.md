<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Design

## Scope

The deck reads, writes, creates and formats Commodore 1541 D64 disk images:
the CBM DOS 2.6 BAM and directory, SEQ / PRG / USR file chains, PETSCII names,
raw block access, the optional error table, and the 40-track BAM layouts of
SpeedDOS, DolphinDOS and PrologicDOS. Tracks 41 and 42 are reachable block by
block.

It is pure computation over a byte buffer. Only `open` and `save` touch the
filesystem, so the deck needs no capability and runs on `jennifer-tiny`.

Out of scope:

- Writing REL files. Their side-sector index is not built, so `writeFile`
  refuses REL; reading a REL file's data chain works.
- Other image formats (D71, D81, G64, T64) and GCR-level copy protection.
- Emulating the drive: no DOS commands, no block-level timing.

## Decisions

- **The image is one byte buffer.** `Image` holds the whole file (683, 768 or
  802 blocks of 256 bytes, then an optional error table of one byte per
  block), the track count, whether an error table is present, and the BAM
  layout. `fromBytes` derives the geometry from the length: six sizes are
  legal, anything else is an error.
- **Value semantics.** Every mutator returns a new `Image`
  (`$img = writeFile($img, ...)`). A failed `updateFile` therefore leaves the
  caller's image holding the old file; no undo log is needed.
- **The BAM layout is detected, and can be overridden.** A 35-track image is
  always standard CBM. A 40-track image is PrologicDOS if its header carries
  the PrologicDOS marker, else SpeedDOS or DolphinDOS by which BAM region
  looks populated. Detection is a heuristic, so `withFormat` sets the layout
  without touching bytes.
- **Allocation follows the drive.** Files start near the directory track and
  spiral outward (17, 19, 16, 20, ...), stepping `FILE_INTERLEAVE` (10)
  within a track; directory blocks are added on track 18 at
  `DIRECTORY_INTERLEAVE` (3). Track 18 is never used for data and does not
  count toward the free blocks (664 on a fresh disk). The interleave walk is
  followed by a linear sweep, so an interleave that does not divide evenly
  still finds every free block.
- **The bitmap is the truth.** The free-sector search trusts the BAM bits
  and ignores the per-track free count, since a damaged disk can disagree
  with itself.
- **DEL entries own no blocks.** `readFile` refuses them and `deleteFile`
  clears the slot without freeing anything: scene disks use DEL slots as
  decoration with garbage block pointers, often pointing at the BAM.
- **Scratch as the drive does it.** Deleting zeroes only the type byte; name
  and pointer stay. A zero type byte is a free slot.
- **Names.** 1 to `MAX_FILENAME` (16) PETSCII bytes, never the `PAD_BYTE`.
  Lookup is case-insensitive and compares raw bytes, without decoding.
  `matchName` follows the drive: `*` ends the pattern, so `he*lo` matches
  every name starting `he`.
- **PETSCII defaults to the shifted charset**, the convention of `petcat`
  and `c1541`: `toPetscii("hello")` shows as `HELLO` on a C64. Some graphics
  characters map above U+FFFF (Symbols for Legacy Computing). `DOS_TYPE` is
  `"2a"` in lower case for the same reason; on screen it shows as `2A`.
- **Performance is a design constraint.** Passing an `Image` to a function
  that edits it copies the whole buffer (about 175 KB), so the hot paths avoid
  per-block copies: BAM bits are flipped in place, `writeFile` and
  `deleteFile` work on a detached copy of the BAM block and write it back
  once, a file's blocks are built first and spliced into the image in one
  pass, reads collect parts and join once, and the sector offset is
  closed-form. New mutators should keep these patterns.
- **Pure `.j`, a deck and not core**: a retro format with a small, stable
  audience, and a test of the language on byte-level work.

## Errors

Every failure the deck detects is `Error{kind: "d64"}` (`ERROR_KIND`), with
a message naming the track, sector or file. Filesystem failures in `open`
and `save` come from `fs` and pass on with their own kind.

## Security and limits

Images are treated as untrusted; a damaged or crafted disk must throw, not
loop or write out of bounds.

- Block chains are walked at most as many steps as the disk has blocks, and
  the directory chain at most as many as track 18 has sectors, so a looping
  chain throws.
- Every track / sector pair is range-checked against the image's geometry;
  tracks without a BAM entry are refused by the allocator.
- The directory holds at most `MAX_DIRECTORY_ENTRIES` (144) entries.
- `open` reads the whole file before checking its size; size is checked
  against the six legal lengths before anything is parsed.

## Testing and validation

- One overlay per topic; no fixture files. Every image is built in memory
  with `formatDisk` / `formatDiskWith`, so the suite runs on `jennifer-tiny`
  and from a bare copy of `src/`. `open` and `save` are tested in a
  temporary directory.
- The examples run in CI; the one that writes files uses a temporary
  directory and removes it.
- Not covered: comparison against images written by a real drive or by
  VICE's `c1541` in the test suite.

## Known limitations and open questions

- REL files cannot be written.
- Format detection for 40-track images is a heuristic; `withFormat` is the
  escape hatch.
- `open` has no size cap before reading; a huge file is read into memory
  before it is refused.

## Dependencies on the interpreter

Floor `>=0.26.0` for `jennifer` and `jennifer-tiny`, no capability. It needs
nothing beyond `bytes`, `fs` and the standard libraries.
