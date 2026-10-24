# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# d64 - the image itself: bytes in, bytes out, one block at a time.
# Spliced into d64.j via include - not a standalone module.

/**
 * A D64 disk image held in memory.
 *
 * Value-semantic like every Jennifer value: a function that changes the disk
 * returns a fresh `Image` and leaves the one you passed in alone, so the
 * calling shape is always `$img = something($img, ...)`.
 *
 * @field data {bytes}      the image, block data then the optional error table
 * @field tracks {int}    35, 40 or 42
 * @field errorInfo {bool} true when `data` carries one error byte per block
 * @field format {DiskFormat}    which BAM layout the disk uses
 */
export def struct Image {
    data as bytes,
    tracks as int,
    errorInfo as bool,
    format as DiskFormat
};

/**
 * A track/sector pair: the link CBM DOS chains blocks with.
 *
 * @field track {int}  track number, 1-42
 * @field sector {int} sector number within the track
 */
export def struct Link {
    track as int,
    sector as int
};

/** The error byte a block with no recorded fault carries: "00, OK". */
export def const ERROR_OK as int init 0x01;

/**
 * Read a D64 image out of a byte buffer.
 *
 * The geometry comes from the length - the six D64 sizes are unambiguous -
 * and the BAM layout from {@link detectFormat}.
 *
 * @param raw {bytes} the whole image file
 * @return {Image} the image
 * @throws {Error} when the buffer is not one of the six D64 sizes
 * @example
 *   def img as Image init fromBytes(fs.readBytes("game.d64"));
 */
export func fromBytes(raw as bytes) {
    def tracks as int init tracksForSize(len($raw));
    if ($tracks == 0) {
        fail(convert.toString(len($raw)) + " bytes is not a D64 image size");
    }
    def img as Image init Image{
        data: $raw,
        tracks: $tracks,
        errorInfo: sizeHasErrorInfo(len($raw)),
        format: DiskFormat.Cbm
    };
    $img.format = detectFormat(readSector($img, DIRECTORY_TRACK, BAM_SECTOR), $tracks);
    return $img;
}

/**
 * The image as a byte buffer, ready to write to a file.
 *
 * @param img {Image} the disk to read
 * @return {bytes} the whole image file
 * @example
 *   fs.writeBytes("out.d64", toBytes($img));
 */
export func toBytes(img as Image) {
    return $img.data;
}

/**
 * Read a D64 image from a file.
 *
 * @param path {string} the file to read
 * @return {Image} the image
 * @throws {Error} when the file is missing or is not a D64
 * @example
 *   def img as Image init open("game.d64");
 */
export func open(path as string) {
    if (not fs.exists($path)) {
        fail("no such image: " + $path);
    }
    return fromBytes(fs.readBytes($path));
}

/**
 * Write an image to a file, replacing whatever is there.
 *
 * @param img {Image} the disk to write
 * @param path {string} the file to write
 * @throws {Error} when the file cannot be written
 * @example
 *   save($img, "out.d64");
 */
export func save(img as Image, path as string) {
    fs.writeBytes($path, $img.data);
    return;
}

/**
 * Override the BAM layout {@link fromBytes} guessed.
 *
 * No byte of the disk changes; only how the BAM in sector 18/0 is read from
 * here on.
 *
 * @param img {Image} the disk to re-read
 * @param format {DiskFormat} the layout to use
 * @return {Image} the same image, read under the new layout
 * @example
 *   $img = withFormat($img, DiskFormat.DolphinDos);
 */
export func withFormat(img as Image, format as DiskFormat) {
    def out as Image init $img;
    $out.format = $format;
    return $out;
}

/**
 * How many blocks the image holds, free or not.
 *
 * @param img {Image} the disk to read
 * @return {int} 683, 768 or 802
 * @example
 *   blockCount(formatDisk("d", "01"));   # 683
 */
export func blockCount(img as Image) {
    return totalSectors($img.tracks);
}

/**
 * Read one 256-byte block.
 *
 * @param img {Image} the disk to read
 * @param track {int}  track number, 1 to the image's track count
 * @param sector {int} sector number within the track
 * @return {bytes} the 256 bytes of the block
 * @throws {Error} when the track or the sector is outside the image
 * @example
 *   def bam as bytes init readSector($img, 18, 0);
 *   $bam[2];   # $41, the DOS version byte
 */
export func readSector(img as Image, track as int, sector as int) {
    def at as int init checkedOffset($img, $track, $sector);
    return $img.data[$at..$at + SECTOR_SIZE];
}

/**
 * Write one 256-byte block.
 *
 * @param img {Image} the disk to change
 * @param track {int}  track number, 1 to the image's track count
 * @param sector {int} sector number within the track
 * @param block {bytes}  exactly 256 bytes
 * @return {Image} the image with the block replaced
 * @throws {Error} when the block is the wrong size or the address is outside
 * @example
 *   $img = writeSector($img, 1, 0, $block);
 */
export func writeSector(img as Image, track as int, sector as int, block as bytes) {
    if (len($block) != SECTOR_SIZE) {
        fail("a block is 256 bytes, not " + convert.toString(len($block)));
    }
    def at as int init checkedOffset($img, $track, $sector);
    # Splice with two slices and a join: that is three memory moves in Go
    # against 256 interpreter iterations, and measures about three times
    # faster even for a single block.
    def parts as list of bytes init [$img.data[0..$at], $block, $img.data[$at + SECTOR_SIZE..]];
    $img.data = binary.join($parts);
    return $img;
}

/**
 * The recorded read result of one block.
 *
 * `$01` is "no error"; the other codes are the 1541's own - `$02` header
 * block not found, `$05` data block not present, `$0b` checksum error in the
 * data block, and so on. An image with no error table reports `$01` for
 * every block.
 *
 * @param img {Image} the disk to read
 * @param track {int}  track number
 * @param sector {int} sector number within the track
 * @return {int} the error code, `$01` when the block is good
 * @throws {Error} when the address is outside the image
 * @example
 *   sectorError($img, 18, 0);   # 1
 */
export func sectorError(img as Image, track as int, sector as int) {
    checkedOffset($img, $track, $sector);
    if (not $img.errorInfo) {
        return ERROR_OK;
    }
    return $img.data[errorByteOffset($img, $track, $sector)];
}

/**
 * Record the read result of one block.
 *
 * @param img {Image} the disk to change
 * @param track {int}  track number
 * @param sector {int} sector number within the track
 * @param code {int}   the error code, `$01` for a good block
 * @return {Image} the image with the code recorded
 * @throws {Error} when the image has no error table, or the address is outside
 * @example
 *   $img = setSectorError($img, 18, 0, 0x0b);
 */
export func setSectorError(img as Image, track as int, sector as int, code as int) {
    checkedOffset($img, $track, $sector);
    if (not $img.errorInfo) {
        fail("this image has no error table - format it with errorInfo set");
    }
    if ($code < 0 or $code > 0xff) {
        fail("an error code is one byte, not " + convert.toString($code));
    }
    def data as bytes init $img.data;
    $data[errorByteOffset($img, $track, $sector)] = $code;
    def out as Image init $img;
    $out.data = $data;
    return $out;
}

/**
 * Mark every block of the error table good.
 *
 * A no-op on an image that has no error table, which is why
 * {@link formatDiskWith} can call it unconditionally.
 *
 * @param img {Image} the disk to change
 * @return {Image} the image with a clean error table
 * @example
 *   $img = clearErrorTable($img);
 */
export func clearErrorTable(img as Image) {
    if (not $img.errorInfo) {
        return $img;
    }
    def base as int init blockCount($img) * SECTOR_SIZE;
    def parts as list of bytes init [$img.data[0..$base], binary.make(blockCount($img), ERROR_OK)];
    def out as Image init $img;
    $out.data = binary.join($parts);
    return $out;
}

/**
 * The byte offset of a block, checked against this image's geometry.
 *
 * @param img {Image} the disk to read
 * @param track {int}  track number
 * @param sector {int} sector number within the track
 * @return {int} the offset of the block's first byte
 * @throws {Error} when the address is outside the image
 */
func checkedOffset(img as Image, track as int, sector as int) {
    if ($track < 1 or $track > $img.tracks) {
        fail("track " + convert.toString($track) + " is outside 1-" +
            convert.toString($img.tracks) + " on this image");
    }
    return sectorOffset($track, $sector);
}

/**
 * The offset of a block's byte in the trailing error table.
 *
 * @param img {Image} the disk to read
 * @param track {int}  track number
 * @param sector {int} sector number within the track
 * @return {int} the offset of the error byte
 */
func errorByteOffset(img as Image, track as int, sector as int) {
    return blockCount($img) * SECTOR_SIZE + totalSectors($track - 1) + $sector;
}

/**
 * The position of a block in the image, counting from 0 at track 1 sector 0.
 *
 * Blocks are stored back to back in track order, so this is the index the
 * range calls address blocks by.
 *
 * @param track {int}  track number, 1-42
 * @param sector {int} sector number within the track
 * @return {int} the block number
 * @throws {Error} when the track or the sector is out of range
 * @example
 *   blockNumber(1, 0);    # 0
 *   blockNumber(18, 0);   # 357 - the BAM
 */
export func blockNumber(track as int, sector as int) {
    return sectorOffset($track, $sector) // SECTOR_SIZE;
}

/**
 * The track and sector of a block number, the inverse of {@link blockNumber}.
 *
 * @param number {int} the block number, 0 to 801
 * @return {Link} the address
 * @throws {Error} when the number is outside every D64 geometry
 * @example
 *   blockLink(357);   # Link{track: 18, sector: 0}
 */
export func blockLink(number as int) {
    if ($number < 0 or $number >= totalSectors(TRACKS_MAX)) {
        fail("block " + convert.toString($number) + " is outside 0-" +
            convert.toString(totalSectors(TRACKS_MAX) - 1));
    }
    def track as int init 1;
    def left as int init $number;
    while ($left >= sectorsPerTrack($track)) {
        $left = $left - sectorsPerTrack($track);
        $track = $track + 1;
    }
    return Link{track: $track, sector: $left};
}

/**
 * Read a run of consecutive blocks.
 *
 * Past the last sector of a track the run continues at sector 0 of the next
 * one. The BAM is not consulted: free, allocated and orphaned blocks read
 * alike.
 *
 * @param img {Image} the disk to read
 * @param first {Link} where to start
 * @param count {int} how many blocks, 1 or more
 * @return {bytes} `count * 256` bytes
 * @throws {Error} when the run starts outside the image or reaches past its end
 * @example
 *   readBlocks($img, Link{track: 18, sector: 0}, 2);   # the BAM and 18/1
 */
export func readBlocks(img as Image, first as Link, count as int) {
    def start as int init checkedRun($img, $first, $count);
    def at as int init $start * SECTOR_SIZE;
    return $img.data[$at..$at + $count * SECTOR_SIZE];
}

/**
 * Write a run of consecutive blocks.
 *
 * Ignores the BAM like {@link readBlocks}: it overwrites a block a file is
 * using. Call {@link allocateSector} for blocks that must stay claimed.
 *
 * @param img {Image} the disk to change
 * @param first {Link} where to start
 * @param data {bytes}  the blocks, a whole multiple of 256 bytes
 * @return {Image} the image with the run replaced
 * @throws {Error} when `data` is not whole blocks, or the run leaves the image
 * @example
 *   $img = writeBlocks($img, Link{track: 1, sector: 0}, $twoBlocks);
 */
export func writeBlocks(img as Image, first as Link, data as bytes) {
    if (len($data) == 0 or len($data) % SECTOR_SIZE != 0) {
        fail("a block run is a whole multiple of 256 bytes, not " + convert.toString(len($data)));
    }
    def count as int init len($data) // SECTOR_SIZE;
    def at as int init checkedRun($img, $first, $count) * SECTOR_SIZE;
    def parts as list of bytes init [$img.data[0..$at], $data, $img.data[$at + len($data)..]];
    def out as Image init $img;
    $out.data = binary.join($parts);
    return $out;
}

/**
 * The block number a run starts at, checked against the image.
 *
 * @param img {Image} the disk to read
 * @param first {Link} where the run starts
 * @param count {int} how many blocks
 * @return {int} the first block's number
 * @throws {Error} when the count is not positive or the run leaves the image
 */
func checkedRun(img as Image, first as Link, count as int) {
    if ($count < 1) {
        fail("a block run is 1 or more blocks, not " + convert.toString($count));
    }
    def start as int init checkedOffset($img, $first.track, $first.sector) // SECTOR_SIZE;
    if ($start + $count > blockCount($img)) {
        fail("a run of " + convert.toString($count) + " blocks from " +
            convert.toString($first.track) + "/" + convert.toString($first.sector) +
            " reaches past the last block of this image");
    }
    return $start;
}

/**
 * Overwrite part of one block, leaving the rest of it alone.
 *
 * Ignores the BAM like every block call, so it patches a block a file is
 * using.
 *
 * @param img {Image} the disk to change
 * @param track {int}  track number
 * @param sector {int} sector number within the track
 * @param offset {int} where in the block to start, 0 to 255
 * @param data {bytes}   the bytes to write, at least one
 * @return {Image} the image with the block patched
 * @throws {Error} when the patch is empty or reaches past the end of the block
 * @example
 *   $img = patchSector($img, 18, 0, 0x02, $dosVersionByte);
 */
export func patchSector(img as Image, track as int, sector as int, offset as int, data as bytes) {
    if (len($data) == 0) {
        fail("a patch needs at least one byte");
    }
    if ($offset < 0 or $offset + len($data) > SECTOR_SIZE) {
        fail("a patch of " + convert.toString(len($data)) + " bytes at offset " +
            convert.toString($offset) + " does not fit in a 256-byte block");
    }
    def at as int init checkedOffset($img, $track, $sector) + $offset;
    def raw as bytes init $img.data;
    for (def i as int init 0; $i < len($data); $i = $i + 1) {
        $raw[$at + $i] = $data[$i];
    }
    def out as Image init $img;
    $out.data = $raw;
    return $out;
}

/**
 * Read bytes at an image offset, ignoring block boundaries.
 *
 * The flat view a hex editor works in. Offsets run from 0 to the last byte of
 * the last block; the trailing error table is not addressed here - use
 * {@link sectorError} for that.
 *
 * @param img {Image} the disk to read
 * @param offset {int} the first byte
 * @param length {int} how many bytes, 1 or more
 * @return {bytes} the bytes
 * @throws {Error} when the range leaves the block area
 * @example
 *   readAt($img, sectorOffset(18, 0), 4);   # the BAM's first four bytes
 */
export func readAt(img as Image, offset as int, length as int) {
    checkedRange($img, $offset, $length);
    return $img.data[$offset..$offset + $length];
}

/**
 * Write bytes at an image offset, ignoring block boundaries.
 *
 * A run that crosses a block boundary writes straight through it, track/sector
 * links included.
 *
 * @param img {Image} the disk to change
 * @param offset {int} the first byte
 * @param data {bytes}   the bytes to write, at least one
 * @return {Image} the image with the range replaced
 * @throws {Error} when the range leaves the block area
 * @example
 *   $img = writeAt($img, sectorOffset(17, 0) + 2, $payload);
 */
export func writeAt(img as Image, offset as int, data as bytes) {
    checkedRange($img, $offset, len($data));
    def raw as bytes init $img.data;
    for (def i as int init 0; $i < len($data); $i = $i + 1) {
        $raw[$offset + $i] = $data[$i];
    }
    def out as Image init $img;
    $out.data = $raw;
    return $out;
}

/**
 * Every offset at which a byte pattern occurs on the disk.
 *
 * Searches the block area, not the error table, in one linear pass; matches
 * may overlap. Turn an offset into an address with {@link blockLink}:
 *
 *   def where as Link init blockLink($at // SECTOR_SIZE);
 *   def inBlock as int init $at % SECTOR_SIZE;
 *
 * @param img {Image} the disk to read
 * @param pattern {bytes} the bytes to look for, at least one
 * @return {list of int} the offsets, ascending; empty when there is no match
 * @throws {Error} when the pattern is empty or longer than the disk
 * @example
 *   findBytes($img, toPetscii("hello"));   # where that name is written
 */
export func findBytes(img as Image, pattern as bytes) {
    def limit as int init blockCount($img) * SECTOR_SIZE;
    def span as int init len($pattern);
    if ($span == 0) {
        fail("a search pattern needs at least one byte");
    }
    if ($span > $limit) {
        fail("a pattern of " + convert.toString($span) + " bytes is longer than the disk");
    }
    # One linear pass: binary.indexOf scans in Go and resumes from an offset,
    # so finding every match costs no more than finding the first. A match
    # reaching into the trailing error table ends the search, and so does the
    # first miss, because matches come back in ascending order.
    def hits as list of int;
    def at as int init 0;
    while ($at + $span <= $limit) {
        def found as int init binary.indexOf($img.data, $pattern, $at);
        if ($found < 0 or $found + $span > $limit) {
            return $hits;
        }
        $hits[] = $found;
        $at = $found + 1;
    }
    return $hits;
}

/**
 * Check a byte range against the image's block area.
 *
 * @param img {Image} the disk to read
 * @param offset {int} the first byte
 * @param length {int} how many bytes
 * @throws {Error} when the range is empty or leaves the block area
 */
func checkedRange(img as Image, offset as int, length as int) {
    def limit as int init blockCount($img) * SECTOR_SIZE;
    if ($length < 1) {
        fail("a byte range is 1 or more bytes, not " + convert.toString($length));
    }
    if ($offset < 0 or $offset + $length > $limit) {
        fail("bytes " + convert.toString($offset) + ".." + convert.toString($offset + $length) +
            " leave this image, which holds " + convert.toString($limit) + " bytes of blocks");
    }
    return;
}
