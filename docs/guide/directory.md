<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# The directory

A chain of blocks on track 18 starting at 18/1, each linked to the next by its
first two bytes. Eight 32-byte slots per block, at most 18 blocks: **144 files
maximum**.

## Listing

`directoryText` renders what `LOAD"$",8` shows:

```jennifer
use io;
import "@deckyard/d64/" as d64;

io.printf("%s", d64.directoryText($img));
```

```
0 "sample disk     " 01 2a
   1 "hello"             prg<
   1 "readme"            seq
   1 "notes"             seq
   1 "scores"            usr
660 blocks free.
```

Header: disk name padded to 16, ID, DOS type. Per file: blocks, quoted name,
`*` if never closed, type, `<` if locked. Footer: `blocksFree`. Names are in
the lower-case spelling a C64 shows upper case; see [PETSCII](petscii.md).

## Entries

```jennifer
for (def e in d64.listFiles($img)) {
    io.printf("%s %s %d blocks at %d/%d\n",
        $e.name, d64.fileTypeName($e.kind), $e.blocks, $e.track, $e.sector);
}
```

| Field | Meaning |
|---|---|
| `name` | filename, pad bytes trimmed |
| `kind` | `FileType`: `Del`, `Seq`, `Prg`, `Usr`, `Rel` |
| `closed` | false = "splat" file the drive never closed |
| `locked` | true = `SCRATCH` refuses it, listed `<` |
| `track`, `sector` | first block |
| `blocks` | length in blocks, as the slot records it |
| `recordLength` | REL only |
| `slot` | position in the chain, 0-based |

`listFiles` skips scratched slots (type byte `$00`); their name and block
pointer stay until the slot is reused.

## DEL entries

A listed `Del` entry (non-zero type byte, type bits DEL, usually `$80`) is
not a file. Scene disks use them to draw a border in the listing, with the
first-block pointer left at whatever was there, often the BAM. So:

- `readFile` throws on one; `readChain(img, track, sector)` reads what the
  pointer names if you want it.
- `deleteFile` clears the slot and frees no blocks. This removes border art
  safely.
- `fileInfo` reports an empty chain.

## The other character set

```jennifer
io.printf("%s", d64.directoryTextIn($img, d64.Charset.Unshifted));
```

The same bytes in the upper case/graphics set; see [PETSCII](petscii.md).

## Finding

```jennifer
d64.hasFile($img, "HELLO");        # exact name, case-insensitive
d64.findFile($img, "hello");       # throws on a miss

d64.findFiles($img, "*");          # every file
d64.findFiles($img, "he*");        # prefix
d64.findFiles($img, "h?llo");      # ? is one character
```

`*` matches the rest of the name and ends the pattern. `findFiles` returns an
empty list when nothing matches.

## Rename and lock

```jennifer
$img = d64.renameFile($img, "notes", "notes v2");
$img = d64.lockFile($img, "hello");
$img = d64.unlockFile($img, "hello");
```

`renameFile` rewrites the name only. It throws if the new name is taken
(the same name in another case is allowed) or over 16 PETSCII bytes.
`deleteFile` throws on a locked file.

## Chain growth

The ninth file adds a directory block at interleave 3: 18/1, 18/4, 18/7, and
so on.

```jennifer
len(d64.directorySectors($img));   # 1 fresh, 2 after nine files
```

Scratched slots are reused before the chain grows. With all 144 slots taken,
`writeFile` throws a full-directory error, distinct from disk-full.
`directorySectors` throws on a chain that leaves track 18 or loops.
