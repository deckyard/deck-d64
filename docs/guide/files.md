<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Reading and writing files

A file is a chain of blocks; bytes `$00`-`$01` link to the next. In the last
block the track byte is `0` and the sector byte `n` means bytes `$02`-`$n` are
data (`n - 1` bytes). Every other block carries 254.

## Writing

```jennifer
use io;
import "@deckyard/d64/" as d64;

def img as d64.Image init d64.formatDisk("work disk", "wd");

$img = d64.writeFile($img, "blob", d64.FileType.Prg, $bytes);
$img = d64.writeText($img, "readme", d64.FileType.Seq, "hello\nworld\n");
$img = d64.writeProgram($img, "demo", 0x0801, $code);
```

| Function | Stores |
|---|---|
| `writeFile` | raw bytes |
| `writeText` | PETSCII; `\n` becomes the CBM carriage return `$0d` |
| `writeProgram` | two-byte load address, low byte first, then the data; type PRG |

Blocks come from the [allocator](sectors.md#the-allocator) at interleave 10.
The directory slot is claimed last, growing the directory if needed.

`writeFile` throws on a name already on the disk, on `FileType.Rel` (no
side-sector index is built; existing REL files read fine with `readFile`) and
on `FileType.Del`. An empty file takes one block; 254 bytes take one, 255
take two.

## Reading

```jennifer
def raw as bytes init d64.readFile($img, "blob");
def text as string init d64.readText($img, "readme");
def prg as d64.Program init d64.readProgram($img, "demo");

$prg.address;   # 2049
$prg.data;      # after the load address
```

`readFile` returns the bytes as stored, a PRG with its load address.
`readText` runs them through `fromPetscii`; `readProgram` splits off the load
address and throws on a file under two bytes. `readFile` throws on a
[DEL entry](directory.md#del-entries), a chain that loops, and a last block
with length byte `0`.

### The chain

```jennifer
def e as d64.Entry init d64.findFile($img, "demo");
for (def link in d64.chainOf($img, $e.track, $e.sector)) {
    io.printf("%d/%d ", $link.track, $link.sector);
}
# a three-block file on a fresh disk: 17/0 17/10 17/20
```

`readChain(img, track, sector)` reads a chain without an entry, such as a
scratched file whose blocks have not been reused.

## Metadata

`fileInfo` returns the directory entry with the walked chain, so the two can
be compared.

```jennifer
def info as d64.FileInfo init d64.fileInfo($img, "demo");

$info.entry.name;      # "demo"
$info.entry.kind;      # FileType.Prg
$info.entry.blocks;    # what the directory records
$info.blocks;          # blocks actually chained
$info.blocksMatch;     # whether those two agree
$info.size;            # payload bytes
$info.lastUsed;        # payload bytes in the last block
$info.loadAddress;     # 2049 for a PRG, -1 otherwise
$info.chain;           # list of Link, first to last
```

It reads the chain and the first and last blocks, not the whole file.
`loadAddress` is also -1 for a PRG under two bytes. `listFileInfo(img)` covers
every listed file:

```jennifer
for (def i in d64.listFileInfo($img)) {
    io.printf("%s %d blocks %d bytes\n", $i.entry.name, $i.blocks, $i.size);
}
```

## Patching in place

```jennifer
$img = d64.patchFile($img, "demo", 2, d64.toPetscii("hi"));
```

Overwrites bytes in the file's existing blocks; chain, entry and BAM are
unchanged. Offset 0 is the first byte (for a PRG, the load address low byte).
Throws on an empty patch or one past the end of the file.

## Replacing

```jennifer
$img = d64.updateFile($img, "blob", d64.FileType.Prg, $newBytes);
```

Scratches the old copy, then writes the new one, which may reuse its blocks.
Writes the file if absent; can change the type. Throws on a locked file, or if
the new copy does not fit, leaving the caller's image as it was.

## Scratching

```jennifer
$img = d64.deleteFile($img, "blob");
```

Frees the blocks and zeroes the slot's type byte; name and block pointer
stay. Throws on a locked file.

## Image files

```jennifer
d64.save($img, "work.d64");
def again as d64.Image init d64.open("work.d64");
```

The only two functions that touch the filesystem; `save` replaces an
existing file. For other transports use the byte forms:

```jennifer
def raw as bytes init d64.toBytes($img);
def img as d64.Image init d64.fromBytes($raw);
```
