<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# D64 cheatsheet

Every export. Names are written bare; after
`import "@deckyard/d64/" as d64;` they read `d64.formatDisk(...)`. Every
failure throws an `Error` with `kind` `"d64"`. Functions that return an `Image`
leave their `img` argument unchanged.

## Types

### `Image`

A disk image in memory.

| Field | Notes |
|---|---|
| `data as bytes` | the blocks, then the optional error table |
| `tracks as int` | 35, 40 or 42 |
| `errorInfo as bool` | true when `data` carries one error byte per block |
| `format as DiskFormat` | which BAM layout the disk uses |

### `Link`

A track/sector pair, the link CBM DOS chains blocks with.

| Field | Notes |
|---|---|
| `track as int` | 1 to 42 |
| `sector as int` | within the track |

### `Entry`

One directory slot.

| Field | Notes |
|---|---|
| `name as string` | the filename, pad bytes trimmed, shifted reading |
| `kind as FileType` | `Del`, `Seq`, `Prg`, `Usr` or `Rel` |
| `closed as bool` | false marks a splat file the drive never closed |
| `locked as bool` | true marks a file `SCRATCH` refuses, listed `<` |
| `track as int` | first block |
| `sector as int` | first block |
| `blocks as int` | length as the directory records it |
| `recordLength as int` | REL files only |
| `slot as int` | position in the directory chain, 0-based |

### `Program`

A PRG split at its load address.

| Field | Notes |
|---|---|
| `address as int` | the load address the first two bytes carry |
| `data as bytes` | everything after it |

### `FileInfo`

A file's metadata with its chain. A DEL entry reports an empty chain.

| Field | Notes |
|---|---|
| `entry as Entry` | the directory entry, verbatim |
| `chain as list of Link` | every block, first to last |
| `blocks as int` | blocks actually in the chain |
| `size as int` | payload bytes over the whole chain |
| `lastUsed as int` | payload bytes in the last block |
| `loadAddress as int` | the PRG load address, -1 when there is none |
| `blocksMatch as bool` | whether the entry's block count is right |

### `FormatOptions`

What to format. A zero field takes its default.

| Field | Notes |
|---|---|
| `tracks as int` | 35, 40 or 42; 0 means the format's own default |
| `format as DiskFormat` | which BAM layout to write |
| `errorInfo as bool` | true to append the per-block error table |
| `dosType as string` | two characters; `""` means `"2a"` |
| `fill as int` | the byte every block is set to, 0 to 255 |
| `mode as FormatMode` | how much to rewrite; only `reformatWith` reads it |

### `DiskFormat`

Which BAM layout a disk uses. Zero value `Cbm`.

| Variant | Notes |
|---|---|
| `Cbm` | the stock layout; tracks 36-42 have no BAM entry |
| `SpeedDos` | entries for tracks 36-40 at `$c0`-`$d3` |
| `DolphinDos` | entries for tracks 36-40 at `$ac`-`$bf` |
| `PrologicDos` | entries at `$90`-`$a3`; the header moves to `$a4` |

### `FileType`

What kind of file a directory entry describes. Zero value `Del`.

| Variant | Notes |
|---|---|
| `Del` | a scratched or decorative slot, not a file |
| `Seq` | a stream of bytes |
| `Prg` | a program, with a two-byte load address in front |
| `Usr` | as `Seq`, named for the program's own use |
| `Rel` | record-oriented, with a side-sector index |

### `FormatMode`

How much of the disk a format rewrites. Zero value `Full`.

| Variant | Notes |
|---|---|
| `Full` | every block to the fill byte, then the BAM and directory |
| `Quick` | the BAM and first directory block only; other blocks keep their bytes |

### `Charset`

Which of the C64's two character sets a PETSCII byte is read in. Zero value `Shifted`.

| Variant | Notes |
|---|---|
| `Shifted` | `$41`-`$5a` lower case, `$c1`-`$da` upper case |
| `Unshifted` | `$41`-`$5a` upper case, `$c1`-`$da` box drawing and shades |

## Formatting

| Function | Returns | Notes |
|---|---|---|
| `formatDisk(name, id)` | `Image` | blank 35-track CBM disk, 664 blocks free. `NEW0:NAME,ID` on a 1541. Name 1-16 characters, ID 1-2 |
| `formatDiskWith(options, name, id)` | `Image` | explicit geometry and BAM layout; throws on a speeder layout with fewer than 40 tracks |
| `reformat(img, name, id)` | `Image` | full wipe to `$00`, keeping geometry, layout and error table. `N0:NAME,ID` |
| `quickFormat(img, name)` | `Image` | erase the BAM and directory only; other blocks keep their bytes, the ID is kept. `N0:NAME` |
| `reformatWith(img, options, name, id)` | `Image` | explicit `mode`, `fill` and `dosType`; geometry and layout always come from the image |
| `defaultFormatOptions()` | `FormatOptions` | 35 tracks, `Cbm`, no error table, DOS type `"2a"`, fill `$00`, mode `Full` |
| `formatName(format)` | `string` | `"cbm"` / `"speeddos"` / `"dolphindos"` / `"prologicdos"` |
| `formatFromName(name)` | `DiskFormat` | inverse, case-insensitive; also `"1541"`, `"commodore"`, `"speed"`, `"dolphin"`, `"prologic"`, hyphenated |
| `formatTracks(format)` | `int` | 35 for `Cbm`, 40 for the speeder layouts |
| `detectFormat(bam, tracks)` | `DiskFormat` | guess the layout from sector 18/0; used by `fromBytes`. Always `Cbm` for 35 tracks |
| `headerOffsetFor(format)` | `int` | `$90`, or `$a4` under PrologicDOS |
| `bamEntryOffset(format, track)` | `int` | offset of a track's four BAM bytes, `-1` when it has none |

## Image

| Function | Returns | Notes |
|---|---|---|
| `fromBytes(raw)` | `Image` | geometry from the length, layout from `detectFormat`; throws when the length is not a D64 size |
| `toBytes(img)` | `bytes` | the image, ready to write |
| `open(path)` | `Image` | read one from a file; throws when the file is missing |
| `save(img, path)` |  | write one to a file, replacing it |
| `withFormat(img, format)` | `Image` | overrule `detectFormat`. No bytes change |
| `blockCount(img)` | `int` | 683, 768 or 802 |
| `readSector(img, track, sector)` | `bytes` | exactly 256 bytes. The BAM is not consulted |
| `writeSector(img, track, sector, block)` | `Image` | takes exactly 256. The BAM is not consulted or updated |
| `readBlocks(img, first, count)` | `bytes` | a run of consecutive blocks, crossing track boundaries; `count * 256` bytes |
| `writeBlocks(img, first, data)` | `Image` | the same in reverse; `data` is a whole multiple of 256 bytes |
| `blockNumber(track, sector)` | `int` | the flat block index, 0 at 1/0 |
| `blockLink(number)` | `Link` | the inverse; `number` 0-801 |
| `patchSector(img, track, sector, offset, data)` | `Image` | overwrite part of one block, leaving the rest of it alone |
| `readAt(img, offset, length)` | `bytes` | the flat byte view, block boundaries ignored; the error table is outside it |
| `writeAt(img, offset, data)` | `Image` | the same in reverse |
| `findBytes(img, pattern)` | `list of int` | every offset the pattern occurs at, ascending. `blockLink($at // SECTOR_SIZE)` gives the address |
| `sectorError(img, track, sector)` | `int` | recorded read result; `ERROR_OK` when there is no error table |
| `setSectorError(img, track, sector, code)` | `Image` | throws without an error table |
| `clearErrorTable(img)` | `Image` | mark every block good; no-op without a table |

## Geometry

| Function | Returns | Notes |
|---|---|---|
| `sectorsPerTrack(track)` | `int` | 21, 19, 18 or 17 |
| `totalSectors(tracks)` | `int` | 683/768/802 at 35/40/42; `0` answers `0` |
| `sectorOffset(track, sector)` | `int` | the byte offset of a block |
| `imageSize(tracks, errorInfo)` | `int` | one of the six D64 sizes |
| `tracksForSize(size)` | `int` | 35/40/42, or `0` when not a D64 size |
| `sizeHasErrorInfo(size)` | `bool` | whether the size includes the error table |

## BAM

| Function | Returns | Notes |
|---|---|---|
| `blocksFree(img)` | `int` | allocatable free blocks, track 18 excluded; 664 on a fresh 35-track disk |
| `trackBlocksFree(img, track)` | `int` | `0` when the track has no BAM entry |
| `hasBamEntry(img, track)` | `bool` | whether the track is covered |
| `isFree(img, track, sector)` | `bool` | whether the block is available |
| `isAllocated(img, track, sector)` | `bool` | the inverse |
| `allocateSector(img, track, sector)` | `Image` | throws if already taken or the track has no BAM entry |
| `freeSector(img, track, sector)` | `Image` | throws if already free or the track has no BAM entry |
| `nextFreeSector(img, near, interleave)` | `Link` | stay on `near`'s track at the interleave, then spiral out from track 18. Throws on a full disk |
| `trackSearchOrder(img, preferred)` | `list of int` | that spiral, `preferred` first when usable |

## Disk header

| Function | Returns | Notes |
|---|---|---|
| `diskName(img)` | `string` | the shifted reading |
| `diskNameIn(img, charset)` | `string` | the name in a chosen character set |
| `setDiskName(img, name)` | `Image` | 1 to 16 characters |
| `diskId(img)` | `string` | pad byte trimmed |
| `setDiskId(img, id)` | `Image` | one or two characters; one is padded with `$a0` |
| `dosType(img)` | `string` | `"2a"` on anything a 1541 wrote |
| `dosVersion(img)` | `int` | the byte at `$02` of the BAM; `$41` normally. A 1541 will not write to a disk with another value |

## Directory

| Function | Returns | Notes |
|---|---|---|
| `listFiles(img)` | `list of Entry` | live files, in directory order |
| `findFiles(img, pattern)` | `list of Entry` | matching a CBM pattern |
| `findFile(img, name)` | `Entry` | exact name, case-insensitive; throws on a miss |
| `hasFile(img, name)` | `bool` | exact name, case-insensitive |
| `directoryText(img)` | `string` | the `LOAD"$",8` listing |
| `directoryTextIn(img, charset)` | `string` | the same listing in a chosen character set; `Charset.Unshifted` shows border art as borders |
| `nameBytes(img, entry)` | `bytes` | the 16 raw name bytes of an entry's slot, the lossless route to the other reading |
| `renameFile(img, oldName, newName)` | `Image` | throws on a missing file or a name already taken |
| `lockFile(img, name)` | `Image` | `SCRATCH` then refuses it |
| `unlockFile(img, name)` | `Image` |  |
| `directorySectors(img)` | `list of Link` | the directory chain; throws if it loops or leaves track 18 |
| `fileTypeName(kind)` | `string` | `"del"` / `"seq"` / `"prg"` / `"usr"` / `"rel"` |
| `fileTypeFromName(name)` | `FileType` | inverse, case-insensitive |
| `fileTypeFromByte(raw)` | `FileType` | the low nibble of a type byte |
| `fileTypeByte(kind, closed, locked)` | `int` | `$82` is a closed PRG |

## Files

| Function | Returns | Notes |
|---|---|---|
| `readFile(img, name)` | `bytes` | raw; nothing transcoded. Refuses a DEL entry, which is a directory slot rather than a file |
| `readText(img, name)` | `string` | PETSCII to text |
| `readProgram(img, name)` | `Program` | split at the load address |
| `readChain(img, track, sector)` | `bytes` | the payload of any chain, entry or not |
| `chainOf(img, track, sector)` | `list of Link` | the blocks a file uses |
| `fileInfo(img, name)` | `FileInfo` | the entry, the chain, the real size and the PRG load address. A DEL entry reports an empty chain |
| `listFileInfo(img)` | `list of FileInfo` | the same for every file |
| `writeFile(img, name, kind, data)` | `Image` | throws on a taken name, a REL or DEL kind, or a full disk or directory |
| `writeText(img, name, kind, text)` | `Image` | transcodes to PETSCII |
| `writeProgram(img, name, address, data)` | `Image` | load address first, low byte first |
| `updateFile(img, name, kind, data)` | `Image` | replace, or write if absent; throws on a locked file |
| `patchFile(img, name, offset, data)` | `Image` | overwrite bytes in place; chain, entry and BAM untouched. Cannot change the length |
| `deleteFile(img, name)` | `Image` | scratch; throws on a locked file. A DEL entry loses its slot and frees no blocks |

## PETSCII

| Function | Returns | Notes |
|---|---|---|
| `toPetscii(text)` | `bytes` | case-swapped, the `petcat` convention. `Charset.Shifted` |
| `fromPetscii(data)` | `string` | inverse; `$80`-`$9f` and `$e0`-`$fe` become `?` |
| `toPetsciiIn(text, charset)` | `bytes` | the same in a chosen character set |
| `fromPetsciiIn(data, charset)` | `string` | the same in a chosen character set |
| `encodeName(name)` | `bytes` | 16 PETSCII bytes, pad-filled. Raises on an empty name, one over 16 characters, or one holding the pad byte |
| `decodeName(raw)` | `string` | trailing padding dropped, an inner pad byte read as a space |
| `encodeNameIn(name, charset)` | `bytes` | the same in a chosen character set |
| `decodeNameIn(raw, charset)` | `string` | the same in a chosen character set |
| `matchName(pattern, name)` | `bool` | the drive's `*` and `?`, case-insensitive |

## Constants

| Name | Value | What it is |
|---|---:|---|
| `SECTOR_SIZE` | 256 | bytes in one block |
| `DATA_BYTES_PER_SECTOR` | 254 | payload bytes per block |
| `DIRECTORY_TRACK` | 18 | the track CBM DOS keeps for itself |
| `BAM_SECTOR` | 0 | the BAM, on that track |
| `FIRST_DIRECTORY_SECTOR` | 1 | where the directory chain starts |
| `TRACKS_STANDARD` | 35 | a stock 1541 disk |
| `TRACKS_EXTENDED` | 40 | what the speeder DOSes formatted |
| `TRACKS_MAX` | 42 | the largest D64 in circulation |
| `FILE_INTERLEAVE` | 10 | sectors skipped between file blocks |
| `DIRECTORY_INTERLEAVE` | 3 | sectors skipped between directory blocks |
| `ENTRIES_PER_SECTOR` | 8 | directory slots in one block |
| `ENTRY_SIZE` | 32 | bytes in one slot |
| `MAX_DIRECTORY_ENTRIES` | 144 | 18 blocks of 8 |
| `MAX_FILENAME` | 16 | characters CBM DOS stores |
| `PAD_BYTE` | `$a0` | the shifted space a short name is padded with |
| `SUBSTITUTE_BYTE` | `$3f` | what an unmappable character becomes |
| `DOS_VERSION_BYTE` | `$41` | the byte at `$02` of the BAM |
| `DOS_TYPE` | `"2a"` | the DOS type a 1541 stamps in |
| `HEADER_OFFSET` | `$90` | where the disk header sits |
| `HEADER_OFFSET_PROLOGIC` | `$a4` | where PrologicDOS moved it |
| `ERROR_OK` | `$01` | the error code of a good block |
| `ERROR_KIND` | `"d64"` | the `kind` every `Error` here carries |
| `VERSION` | generated | the deck version, injected from the git tag |
