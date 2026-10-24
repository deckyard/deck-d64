<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# PETSCII

PETSCII and ASCII agree on digits, space and most punctuation, not on
letters. The C64 has two character sets that draw some bytes differently:

| Byte | `Charset.Shifted` (lower/upper case) | `Charset.Unshifted` (upper case/graphics, the power-on set) |
|---|---|---|
| `$41`-`$5a` | `a`-`z` | `A`-`Z` |
| `$c1`-`$da` | `A`-`Z` | box drawing, shades, card suits |
| `$a0`-`$bf` | block elements | block elements |

`$60`-`$7f` draw the same glyphs as `$c0`-`$df`.

Calls without a charset use `Charset.Shifted`, as `petcat` and `c1541` do.
ASCII lower case maps to `$41`-`$5a`, which the power-on C64 shows upper
case:

```jennifer
import "@deckyard/d64/" as d64;

d64.toPetscii("hello");   # $48 $45 $4c $4c $4f - the C64 shows HELLO
d64.toPetscii("Hello");   # $c8 $45 $4c $4c $4f
```

**Write names lower case.** Upper-case ASCII becomes `$c1`-`$da`, which the
power-on set draws as graphics.

## What round-trips

`fromPetscii(toPetscii(s)) == s` for:

- both letter cases;
- `$20`-`$40`: space, digits, `! " # $ % & ' ( ) * + , - . / : ; < = > ? @`;
- `[` and `]`;
- control codes `$00`-`$1f`, passed through unchanged;
- `\n` ↔ `$0d`, the CBM line terminator, so PETSCII text splits on `\n`;
- `£` `$5c`, `↑` `$5e`, `←` `$5f`, `π` `$ff`;
- `U+00A0` ↔ `$a0`, the shifted space used to pad filenames.

Any other character - `{` `}` `~` `` ` `` `_` `\`, accented letters, anything
not in the graphics table - is written as `?` (`SUBSTITUTE_BYTE`, `$3f`).

```jennifer
d64.toPetscii("a{b}");   # $41 $3f $42 $3f
```

Decoding turns `$80`-`$9f` (the colour and cursor controls) and `$e0`-`$fe`
into `?`.

## The other character set

Every transcoding function has an `...In` form that takes a `Charset`:
`toPetsciiIn`, `fromPetsciiIn`, `encodeNameIn`, `decodeNameIn`, `diskNameIn`,
`directoryTextIn`.

```jennifer
def raw as bytes init d64.toPetsciiIn("╭──╮", d64.Charset.Unshifted);
d64.fromPetsciiIn($raw, d64.Charset.Unshifted);   # "╭──╮"
d64.fromPetsciiIn($raw, d64.Charset.Shifted);     # "U──I"
```

Two asymmetries follow from the hardware:

- **Unshifted has no lower case.** A lower-case letter is written as its
  upper-case code and reads back upper case.
- **Shifted cannot write the graphics at `$c1`-`$da`**, because those codes
  are its upper-case letters; they become `?`. The `$a0`-`$bf` block elements
  write in either set.

### Border art

Scene disks draw directory frames from those graphics. Read shifted they come
out as capitals:

```jennifer
io.printf("%s", d64.directoryTextIn($img, d64.Charset.Unshifted));
```

`Entry.name` is always the shifted reading, and decoding is lossy, so
`nameBytes(img, entry)` gives the raw 16 bytes to decode another way:

```jennifer
d64.decodeNameIn(d64.nameBytes($img, $entry), d64.Charset.Unshifted);
```

## Text only

`fromPetscii` is for names and SEQ text; `?` substitution loses bytes, so
never run program data through it.

```jennifer
d64.readFile($img, "demo");    # raw bytes
d64.readText($img, "readme");  # transcoded
```

## Filenames

16 bytes, padded with `$a0`.

```jennifer
d64.encodeName("hello");                   # $48 $45 $4c $4c $4f + 11 x $a0
d64.decodeName(d64.encodeName("hello"));   # "hello"
```

`encodeName` throws on an empty name, one over 16 PETSCII bytes, and one
containing the pad byte. `decodeName` drops trailing padding and decodes a pad
byte inside a name as a space. Every filename argument in the deck goes
through `encodeName`.

## Wildcards

```jennifer
d64.matchName("*", "anything");    # true
d64.matchName("he*", "hello");     # true
d64.matchName("h?llo", "hello");   # true
d64.matchName("hello", "hell");    # false
```

`*` matches the rest of the name and ends the pattern; the drive ignores
anything after it, and so does `matchName`. `?` matches one character. The
match is case-insensitive. `findFiles` applies it to the directory.
