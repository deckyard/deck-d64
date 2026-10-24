# @deckyard/d64

[![test](https://github.com/deckyard/deck-d64/actions/workflows/test.yml/badge.svg)](https://github.com/deckyard/deck-d64/actions/workflows/test.yml)
[![Documentation](https://img.shields.io/badge/docs-github%20pages-blue)](https://deckyard.github.io/deck-d64/)
[![release](https://img.shields.io/github/v/release/deckyard/deck-d64)](https://github.com/deckyard/deck-d64/releases/latest)

Reads, writes, creates and formats Commodore 1541 D64 disk images: the CBM DOS
2.6 BAM and directory, SEQ, PRG and USR files, PETSCII names, raw block
access, and the 40-track SpeedDOS, DolphinDOS and PrologicDOS BAM layouts.
Pure Jennifer with no capabilities, so it runs on `jennifer-tiny`; only `open`
and `save` touch the filesystem.

Manual: **<https://deckyard.github.io/deck-d64/>**

## Install

Requires Jennifer 0.25.0 or newer.

```sh
jvc add @deckyard/d64
```

jvc vendors the deck to `vendor/deckyard/d64/`. Without jvc, copy `src/` from
a checkout or a `deckyard-d64-<version>.tar.gz` release archive there, minus
the test overlays:

```sh
mkdir -p vendor/deckyard/d64
cp -R path/to/deck-d64/src/. vendor/deckyard/d64/
find vendor/deckyard/d64 -name '*_test.j' -delete
```

## Example

```jennifer
use io;
use binary;
import "@deckyard/d64/" as d64;

def code as bytes init binary.make(600);
def img as d64.Image init d64.formatDisk("sample disk", "01");
$img = d64.writeText($img, "readme", d64.FileType.Seq, "hello from jennifer\n");
$img = d64.writeProgram($img, "demo", 0x0801, $code);

io.printf("%s", d64.directoryText($img));
# 0 "sample disk     " 01 2a
#    1 "readme"            seq
#    3 "demo"              prg
# 660 blocks free.

d64.save($img, "sample.d64");
```

## Licence

LGPL-3.0-only, see [LICENSE](LICENSE). Copyright (C) 2026 mplx &lt;mplx@jennifer-lang.dev&gt;.
