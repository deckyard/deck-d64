# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# d64 - the shared primitives every other topic builds on.
# Spliced into d64.j via include - not a standalone module.

/** The `kind` of every `Error` this deck throws. */
export def const ERROR_KIND as string init "d64";

/**
 * Raise a deck error.
 *
 * Every failure in the deck goes through here, so a caller can catch the
 * whole surface with one `kind` test. The message is written for a human:
 * it names the track, sector or file the operation was on.
 *
 * @param message {string} what went wrong, in plain words
 * @throws {Error} always, with `kind` `"d64"`
 */
func fail(message as string) {
    throw Error{kind: ERROR_KIND, message: $message, file: "", line: 0, col: 0};
}

/**
 * A block of `n` zero bytes.
 *
 * Throws the deck's own error kind on a negative size, not the interpreter's.
 *
 * @param n {int} how many bytes; 0 gives an empty block
 * @return {bytes} `n` zero bytes
 * @throws {Error} when `n` is negative
 */
func zeroBytes(n as int) {
    if ($n < 0) {
        fail("cannot build a block of " + convert.toString($n) + " bytes");
    }
    return binary.make($n);
}

/**
 * Test one bit of an integer.
 *
 * @param value {int} the integer to read
 * @param bit {int} which bit, 0 = least significant
 * @return {bool} true when the bit is set
 */
func bitSet(value as int, bit as int) {
    return ($value >> $bit) & 1 == 1;
}

/**
 * Return `value` with one bit turned on.
 *
 * @param value {int} the integer to change
 * @param bit {int} which bit, 0 = least significant
 * @return {int} the new value
 */
func setBit(value as int, bit as int) {
    return $value | (1 << $bit);
}

/**
 * Return `value` with one bit turned off.
 *
 * @param value {int} the integer to change
 * @param bit {int} which bit, 0 = least significant
 * @return {int} the new value
 */
func clearBit(value as int, bit as int) {
    return $value & (~ (1 << $bit) & 0xff);
}

/**
 * The number of 254-byte data blocks a payload of `n` bytes occupies.
 *
 * CBM DOS gives even an empty file one block - the block that records "no
 * bytes used" - so the floor is 1.
 *
 * @param n {int} payload size in bytes
 * @return {int} block count, at least 1
 */
func blocksForBytes(n as int) {
    if ($n <= 0) {
        return 1;
    }
    return ($n + DATA_BYTES_PER_SECTOR - 1) // DATA_BYTES_PER_SECTOR;
}
