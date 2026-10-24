#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * petscii example - the character set CBM DOS stores names and text in.
 *
 * The transcoder swaps case: lower-case text becomes the bytes a C64 shows
 * upper case. Anything PETSCII can spell round-trips; everything else
 * becomes `?`.
 *
 *   jennifer run examples/petscii.j
 */

use io;
use encoding;

import "../src/d64.j" as d64;

def samples as list of string init [
    "hello",
    "HELLO",
    "Mixed Case",
    "side b (1987)",
    "£100",
    'a{b}'
];

io.printf("%s|pad=16|align=left %s|pad=28|align=left %s\n", "text", "petscii", "back");
for (def s in $samples) {
    def raw as bytes init d64.toPetscii($s);
    io.printf(
        "%s|pad=16|align=left %s|pad=28|align=left %s\n",
        "\"" + $s + "\"",
        encoding.toText($raw, "hex"),
        "\"" + d64.fromPetscii($raw) + "\"");
}

# a filename is PETSCII padded to sixteen bytes with the shifted space $a0
io.printf("\nencodeName(\"hello\") = %s\n", encoding.toText(d64.encodeName("hello"), "hex"));
io.printf("decodeName(...)      = \"%s\"\n", d64.decodeName(d64.encodeName("hello")));

# the drive's own wildcards, the ones LOAD"HE*",8 uses
def patterns as list of string init ["*", "he*", "h?llo", "hell"];
io.printf("\nmatching against \"hello\":\n");
for (def p in $patterns) {
    io.printf("  %s|pad=8|align=left %t\n", $p, d64.matchName($p, "hello"));
}

# on the disk a newline is a carriage return, which is what a C64 reads
def text as bytes init d64.toPetscii("one\ntwo\n");
io.printf("\n\"one\\ntwo\\n\" on disk: %s\n", encoding.toText($text, "hex"));
