# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# d64 - the Block Availability Map: what is free, what is taken, and the
# disk header that shares sector 18/0 with it.
# Spliced into d64.j via include - not a standalone module.

/**
 * Whether a track is covered by this disk's BAM.
 *
 * Tracks 1-35 always are. Tracks 36-40 are only under the three speeder
 * layouts, and tracks 41-42 never are - see {@link bamEntryOffset}.
 *
 * @param img {Image} the disk to read
 * @param track {int} track number
 * @return {bool} true when the track has four BAM bytes of its own
 * @example
 *   hasBamEntry(formatDisk("d", "01"), 18);   # true
 */
export func hasBamEntry(img as Image, track as int) {
    if ($track < 1 or $track > $img.tracks) {
        return false;
    }
    return bamEntryOffset($img.format, $track) >= 0;
}

/**
 * Whether a block is free.
 *
 * A block on a track the BAM does not cover is never free - nothing can be
 * allocated there, because there would be no way to record it.
 *
 * @param img {Image} the disk to read
 * @param track {int}  track number
 * @param sector {int} sector number within the track
 * @return {bool} true when the block is available
 * @throws {Error} when the address is outside the image
 * @example
 *   isFree(formatDisk("d", "01"), 18, 0);   # false - that is the BAM itself
 */
export func isFree(img as Image, track as int, sector as int) {
    checkedOffset($img, $track, $sector);
    def at as int init bamEntryOffset($img.format, $track);
    if ($at < 0) {
        return false;
    }
    def bam as bytes init readSector($img, DIRECTORY_TRACK, BAM_SECTOR);
    return bitSet($bam[$at + 1 + ($sector // 8)], $sector % 8);
}

/**
 * Whether a block is taken - the inverse of {@link isFree}.
 *
 * @param img {Image} the disk to read
 * @param track {int}  track number
 * @param sector {int} sector number within the track
 * @return {bool} true when the block is in use or unavailable
 * @throws {Error} when the address is outside the image
 * @example
 *   isAllocated(formatDisk("d", "01"), 18, 1);   # true
 */
export func isAllocated(img as Image, track as int, sector as int) {
    return not isFree($img, $track, $sector);
}

/**
 * Free blocks on one track, as the BAM's own count byte reports it.
 *
 * @param img {Image} the disk to read
 * @param track {int} track number
 * @return {int} free blocks, 0 when the track has no BAM entry
 * @throws {Error} when the track is outside the image
 * @example
 *   trackBlocksFree(formatDisk("d", "01"), 1);    # 21
 *   trackBlocksFree(formatDisk("d", "01"), 18);   # 17 of 19
 */
export func trackBlocksFree(img as Image, track as int) {
    if ($track < 1 or $track > $img.tracks) {
        fail("track " + convert.toString($track) + " is outside 1-" +
            convert.toString($img.tracks) + " on this image");
    }
    def at as int init bamEntryOffset($img.format, $track);
    if ($at < 0) {
        return 0;
    }
    return readSector($img, DIRECTORY_TRACK, BAM_SECTOR)[$at];
}

/**
 * Free blocks a file could use, which is what a 1541 prints.
 *
 * Track 18 is left out: CBM DOS keeps it for the BAM and the directory and
 * never puts file data there. A freshly formatted 35-track disk answers 664.
 *
 * @param img {Image} the disk to read
 * @return {int} allocatable free blocks
 * @example
 *   blocksFree(formatDisk("sample", "01"));   # 664
 */
export func blocksFree(img as Image) {
    # one BAM read, not one per track: writeFile asks for this before every
    # file, and trackBlocksFree would re-slice the same sector 35 times
    def bam as bytes init readSector($img, DIRECTORY_TRACK, BAM_SECTOR);
    def total as int init 0;
    for (def t as int init 1; $t <= $img.tracks; $t = $t + 1) {
        def at as int init bamEntryOffset($img.format, $t);
        if ($t != DIRECTORY_TRACK and $at >= 0) {
            $total = $total + $bam[$at];
        }
    }
    return $total;
}

/**
 * Mark a block taken.
 *
 * Allocating a block that is already taken throws: two chains would share it,
 * which is how a disk loses a file.
 *
 * @param img {Image} the disk to change
 * @param track {int}  track number
 * @param sector {int} sector number within the track
 * @return {Image} the image with the block allocated
 * @throws {Error} when the block is already taken or has no BAM entry
 * @example
 *   $img = allocateSector($img, 17, 0);
 */
export func allocateSector(img as Image, track as int, sector as int) {
    if (not isFree($img, $track, $sector)) {
        fail("block " + convert.toString($track) + "/" + convert.toString($sector) +
            " is already allocated");
    }
    return setBamBit($img, $track, $sector, false);
}

/**
 * Mark a block free.
 *
 * Freeing a block that is already free throws: it means the count byte and
 * the bitmap have drifted apart.
 *
 * @param img {Image} the disk to change
 * @param track {int}  track number
 * @param sector {int} sector number within the track
 * @return {Image} the image with the block freed
 * @throws {Error} when the block is already free or has no BAM entry
 * @example
 *   $img = freeSector($img, 17, 0);
 */
export func freeSector(img as Image, track as int, sector as int) {
    if (bamEntryOffset($img.format, $track) < 0) {
        fail("track " + convert.toString($track) + " has no BAM entry under " +
            formatName($img.format));
    }
    if (isFree($img, $track, $sector)) {
        fail("block " + convert.toString($track) + "/" + convert.toString($sector) +
            " is already free");
    }
    return setBamBit($img, $track, $sector, true);
}

/**
 * Find the next free block to chain onto, the way CBM DOS does.
 *
 * The search stays on `near`'s track while it has room, stepping `interleave`
 * sectors on at a time - the gap that lets the drive read the next block
 * without waiting a whole revolution. When the track fills, the search
 * spirals outward from the directory track: 17, 19, 16, 20, and so on, so
 * a file lands as close to the directory as it can.
 *
 * @param img {Image} the disk to read
 * @param near {Link}       where to start looking; `Link{track: 0, sector: 0}`
 *                           means "anywhere"
 * @param interleave {int} sectors to skip between blocks, 1 or more
 * @return {Link} the block found
 * @throws {Error} when the disk is full
 * @example
 *   def first as Link init nextFreeSector($img, Link{track: 0, sector: 0}, 10);
 */
export func nextFreeSector(img as Image, near as Link, interleave as int) {
    if ($interleave < 1) {
        fail("an interleave is 1 or more, not " + convert.toString($interleave));
    }
    return freeBlockNear(
        $img,
        readSector($img, DIRECTORY_TRACK, BAM_SECTOR),
        $near,
        $interleave,
        trackSearchOrder($img, 0));
}

/**
 * The same search, over a track order the caller already has.
 *
 * {@link trackSearchOrder} does not depend on `near`, only on the image, so a
 * loop allocating a whole file would otherwise rebuild the same list once per
 * block. `near`'s own track is preferred here instead of being folded into
 * the list.
 *
 * @param img {Image} the disk to read
 * @param bam {bytes}        the BAM sector to search, which may hold
 *                                 claims not yet written back to `img`
 * @param near {Link}       where to start looking
 * @param interleave {int} sectors to skip between blocks
 * @param spiral {list of int}     the track order, from `trackSearchOrder(img, 0)`
 * @return {Link} the block found
 * @throws {Error} when the disk is full
 */
func freeBlockNear(
    img as Image,
    bam as bytes,
    near as Link,
    interleave as int,
    spiral as list of int) {
    if ($near.track >= 1 and $near.track <= $img.tracks and $near.track != DIRECTORY_TRACK and
        hasBamEntry($img, $near.track)) {
        def start as int init ($near.sector + $interleave) % sectorsPerTrack($near.track);
        def found as int init freeSectorIn($bam, $img.format, $near.track, $start, $interleave);
        if ($found >= 0) {
            return Link{track: $near.track, sector: $found};
        }
    }
    for (def track in $spiral) {
        if ($track != $near.track) {
            def found as int init freeSectorIn($bam, $img.format, $track, 0, $interleave);
            if ($found >= 0) {
                return Link{track: $track, sector: $found};
            }
        }
    }
    fail("the disk is full: no free block left");
    return Link{track: 0, sector: 0};
}

/**
 * The order the allocator walks tracks in.
 *
 * `preferred` comes first when it can still hold data; the rest spiral out
 * from the directory track, nearest first. Track 18 never appears - it is
 * the directory's - and neither does a track with no BAM entry.
 *
 * @param img {Image} the disk to read
 * @param preferred {int} the track to try first, 0 for none
 * @return {list of int} the tracks to try, in order
 * @example
 *   trackSearchOrder(formatDisk("d", "01"), 0)[0];   # 17
 */
export func trackSearchOrder(img as Image, preferred as int) {
    def order as list of int;
    def first as int init 0;
    if ($preferred >= 1 and $preferred <= $img.tracks and $preferred != DIRECTORY_TRACK and
        hasBamEntry($img, $preferred)) {
        $first = $preferred;
        $order[] = $preferred;
    }
    # The spiral visits 18-step and 18+step, distinct for every step >= 1, so
    # no track can repeat and no dedupe scan is needed. This runs once per
    # allocated block; a `lists.contains` over the growing list made it
    # quadratic in the track count.
    for (def step as int init 1; $step < TRACKS_MAX; $step = $step + 1) {
        def below as int init DIRECTORY_TRACK - $step;
        if ($below != $first and hasBamEntry($img, $below)) {
            $order[] = $below;
        }
        def above as int init DIRECTORY_TRACK + $step;
        if ($above != $first and hasBamEntry($img, $above)) {
            $order[] = $above;
        }
    }
    return $order;
}

/**
 * The first free sector on one track, hunting by interleave then linearly.
 *
 * The interleave walk visits `start`, `start + interleave` and so on, which
 * only covers the whole track when the two are coprime; a linear sweep picks
 * up whatever it missed, so a track with any free block always yields one.
 *
 * @param bam {bytes} the BAM sector to search
 * @param format {DiskFormat} the layout to read it under
 * @param track {int}      the track to search
 * @param start {int}      the sector to try first
 * @param interleave {int} sectors to skip between tries
 * @return {int} the sector found, or -1 when the track is full
 */
func freeSectorIn(
    bam as bytes,
    format as DiskFormat,
    track as int,
    start as int,
    interleave as int) {
    def at as int init bamEntryOffset($format, $track);
    if ($at < 0) {
        return -1;
    }
    # A full track has no bit set; the count byte is not trusted for this,
    # because a damaged disk can disagree with its own map.
    if (($bam[$at + 1] | $bam[$at + 2] | $bam[$at + 3]) == 0) {
        return -1;
    }
    def count as int init sectorsPerTrack($track);
    for (def i as int init 0; $i < $count; $i = $i + 1) {
        def s as int init ($start + $i * $interleave) % $count;
        if (bitSet($bam[$at + 1 + ($s // 8)], $s % 8)) {
            return $s;
        }
    }
    for (def s as int init 0; $s < $count; $s = $s + 1) {
        if (bitSet($bam[$at + 1 + ($s // 8)], $s % 8)) {
            return $s;
        }
    }
    return -1;
}

/**
 * Mark a block taken in a BAM sector held outside the image.
 *
 * The batching half of {@link allocateSector}: a caller reserving a whole
 * chain claims each block here and writes the sector back once, instead of
 * copying the whole image per block.
 *
 * @param bam {bytes}    the BAM sector
 * @param format {DiskFormat} the layout to read it under
 * @param track {int}  track number
 * @param sector {int} sector number within the track
 * @return {bytes} the sector with the block claimed
 */
func claimIn(bam as bytes, format as DiskFormat, track as int, sector as int) {
    def at as int init bamEntryOffset($format, $track);
    def byteAt as int init $at + 1 + ($sector // 8);
    def out as bytes init $bam;
    $out[$byteAt] = clearBit($out[$byteAt], $sector % 8);
    $out[$at] = $out[$at] -1;
    return $out;
}

/**
 * Mark a block free in a BAM sector held outside the image.
 *
 * The batching half of {@link freeSector}, with the same checks: a caller
 * releasing a whole chain frees each block here and writes the sector back
 * once, instead of copying the whole image per block.
 *
 * @param bam {bytes} the BAM sector
 * @param format {DiskFormat} the layout to read it under
 * @param track {int} track number
 * @param sector {int} sector number within the track
 * @return {bytes} the sector with the block freed
 * @throws {Error} when the block is already free or has no BAM entry
 */
func releaseIn(bam as bytes, format as DiskFormat, track as int, sector as int) {
    def at as int init bamEntryOffset($format, $track);
    if ($at < 0) {
        fail("track " + convert.toString($track) + " has no BAM entry under " +
            formatName($format));
    }
    def byteAt as int init $at + 1 + ($sector // 8);
    if (bitSet($bam[$byteAt], $sector % 8)) {
        fail("block " + convert.toString($track) + "/" + convert.toString($sector) +
            " is already free");
    }
    $bam[$byteAt] = setBit($bam[$byteAt], $sector % 8);
    $bam[$at] = $bam[$at] + 1;
    return $bam;
}

/**
 * Set or clear one bit of the BAM and fix the track's count byte with it.
 *
 * @param img {Image} the disk to change
 * @param track {int}  track number
 * @param sector {int} sector number within the track
 * @param free {bool}   true to mark free, false to mark taken
 * @return {Image} the image with the BAM updated
 */
func setBamBit(img as Image, track as int, sector as int, free as bool) {
    # Edit the parameter and return it: value semantics still hand the caller
    # an untouched image, and with `$img = allocateSector($img, ...)` the
    # interpreter moves the image instead of copying it. Copying `data` into a
    # local and the struct into `out` cost three 175 KB copies per bit.
    def base as int init sectorOffset(DIRECTORY_TRACK, BAM_SECTOR) +
        bamEntryOffset($img.format, $track);
    def byteAt as int init $base + 1 + ($sector // 8);
    if ($free) {
        $img.data[$byteAt] = setBit($img.data[$byteAt], $sector % 8);
        $img.data[$base] = $img.data[$base] + 1;
    } else {
        $img.data[$byteAt] = clearBit($img.data[$byteAt], $sector % 8);
        $img.data[$base] = $img.data[$base] -1;
    }
    return $img;
}

/**
 * The disk name, as the header of a directory listing shows it.
 *
 * @param img {Image} the disk to read
 * @return {string} the name, pad bytes trimmed
 * @example
 *   diskName(formatDisk("sample disk", "01"));   # "sample disk"
 */
export func diskName(img as Image) {
    return diskNameIn($img, Charset.Shifted);
}

/**
 * The disk name, read in a chosen character set.
 *
 * `Charset.Unshifted` is what shows a name drawn out of border graphics
 * rather than the run of capitals a shifted reading makes of it.
 *
 * @param img {Image} the disk to read
 * @param charset {Charset} which character set to read it in
 * @return {string} the name, pad bytes trimmed
 * @example
 *   diskNameIn($img, Charset.Unshifted);
 */
export func diskNameIn(img as Image, charset as Charset) {
    def at as int init headerOffsetFor($img.format);
    def bam as bytes init readSector($img, DIRECTORY_TRACK, BAM_SECTOR);
    return decodeNameIn($bam[$at..$at + MAX_FILENAME], $charset);
}

/**
 * Rename the disk.
 *
 * @param img {Image} the disk to change
 * @param name {string} the new name, 1 to 16 characters
 * @return {Image} the image with the header rewritten
 * @throws {Error} when the name will not fit
 * @example
 *   $img = setDiskName($img, "work disk");
 */
export func setDiskName(img as Image, name as string) {
    def at as int init headerOffsetFor($img.format);
    def label as bytes init encodeName($name);
    def bam as bytes init readSector($img, DIRECTORY_TRACK, BAM_SECTOR);
    for (def i as int init 0; $i < MAX_FILENAME; $i = $i + 1) {
        $bam[$at + $i] = $label[$i];
    }
    return writeSector($img, DIRECTORY_TRACK, BAM_SECTOR, $bam);
}

/**
 * The disk ID.
 *
 * @param img {Image} the disk to read
 * @return {string} the ID, one or two characters, pad byte trimmed
 * @example
 *   diskId(formatDisk("sample", "01"));   # "01"
 */
export func diskId(img as Image) {
    def at as int init headerOffsetFor($img.format) + 0x12;
    def bam as bytes init readSector($img, DIRECTORY_TRACK, BAM_SECTOR);
    return decodeName($bam[$at..$at + 2]);
}

/**
 * Change the disk ID.
 *
 * A one-character ID is padded with `$a0`. A 1541 compares the ID to detect
 * a disk swap.
 *
 * @param img {Image} the disk to change
 * @param id {string}  the new ID, one or two characters
 * @return {Image} the image with the header rewritten
 * @throws {Error} when the ID will not fit
 * @example
 *   $img = setDiskId($img, "aa");
 */
export func setDiskId(img as Image, id as string) {
    def at as int init headerOffsetFor($img.format) + 0x12;
    def code as bytes init encodeDiskId($id);
    def bam as bytes init readSector($img, DIRECTORY_TRACK, BAM_SECTOR);
    $bam[$at] = $code[0];
    $bam[$at + 1] = $code[1];
    return writeSector($img, DIRECTORY_TRACK, BAM_SECTOR, $bam);
}

/**
 * The two-character DOS type: `"2a"` (shown `2A`) on everything a 1541 wrote.
 *
 * @param img {Image} the disk to read
 * @return {string} the DOS type
 * @example
 *   dosType(formatDisk("sample", "01"));   # "2a"
 */
export func dosType(img as Image) {
    def at as int init headerOffsetFor($img.format) + 0x15;
    def bam as bytes init readSector($img, DIRECTORY_TRACK, BAM_SECTOR);
    return decodeName($bam[$at..$at + 2]);
}

/**
 * The DOS version byte at offset `$02` of the BAM.
 *
 * `$41` is what CBM DOS 2.6 writes. A 1541 will not write to a disk that
 * carries any other value there (a soft write protect); reading still works.
 *
 * @param img {Image} the disk to read
 * @return {int} the version byte
 * @example
 *   dosVersion(formatDisk("sample", "01"));   # 65
 */
export func dosVersion(img as Image) {
    return readSector($img, DIRECTORY_TRACK, BAM_SECTOR)[2];
}
