# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# d64 - formatting a disk, and the four BAM layouts a D64 may carry.
# Spliced into d64.j via include - not a standalone module.

/**
 * Which BAM layout a disk uses.
 *
 * A stock 1541 formats 35 tracks and its BAM has entries for exactly those.
 * The speeder DOSes formatted 40 and each put the five extra entries in a
 * different place in sector 18/0:
 *
 *   `Cbm`         the stock layout; tracks 36-42 have no BAM entry at all
 *   `SpeedDos`    entries for tracks 36-40 at `$c0`-`$d3`
 *   `DolphinDos`  entries for tracks 36-40 at `$ac`-`$bf`
 *   `PrologicDos` entries for tracks 36-40 at `$90`-`$a3`, which is where the
 *                 disk name normally sits, so the whole header moves to `$a4`
 *
 * The zero value is `Cbm`.
 */
export def enum DiskFormat {
    Cbm,
    SpeedDos,
    DolphinDos,
    PrologicDos
};

/**
 * What {@link formatDiskWith} should produce.
 *
 * A zero field takes its default, so `FormatOptions{}` is a stock 35-track
 * CBM disk with no error table, blocks filled with `$00`.
 *
 * @field tracks {int}    35, 40 or 42; 0 means the format's own default
 * @field format {DiskFormat}    which BAM layout to write
 * @field errorInfo {bool} true to append the per-block error table
 * @field dosType {string}   the two-character DOS type; "" means "2a"
 * @field fill {int}      the byte every block is set to, 0 to 255
 * @field mode {FormatMode}      how much to rewrite; only {@link reformatWith}
 *                               reads it - a new image has nothing to preserve
 */
export def struct FormatOptions {
    tracks as int,
    format as DiskFormat,
    errorInfo as bool,
    dosType as string,
    fill as int,
    mode as FormatMode
};

/**
 * How much of the disk a format rewrites.
 *
 * The distinction CBM DOS draws between `N0:NAME,ID` and `N0:NAME`:
 *
 *   `Full`   every block is set to the fill byte, then the BAM and the
 *            directory are written. A real drive re-writes each track's
 *            sector headers here, which is why it takes a minute.
 *   `Quick`  only the BAM and the first directory block are written. Every
 *            other block keeps its bytes, so the files are unreachable rather
 *            than erased. The drive calls this a soft format; it is instant.
 *
 * The zero value is `Full`.
 */
export def enum FormatMode {
    Full,
    Quick
};

/** The DOS version byte CBM DOS 2.6 writes at offset `$02` of the BAM. */
export def const DOS_VERSION_BYTE as int init 0x41;

/**
 * The DOS type a 1541 stamps into the disk header.
 *
 * Spelled lower case because PETSCII text is written in the lower-case
 * convention this deck uses throughout: the bytes are `$32 $41`, which a C64
 * shows as `2A`. See {@link toPetscii}.
 */
export def const DOS_TYPE as string init "2a";

/** Offset of the disk header inside the BAM sector, stock layout. */
export def const HEADER_OFFSET as int init 0x90;

/** Offset of the disk header inside the BAM sector, PrologicDOS layout. */
export def const HEADER_OFFSET_PROLOGIC as int init 0xa4;

/**
 * The name of a disk format, as the docs and the CLI spell it.
 *
 * @param format {DiskFormat} the BAM layout
 * @return {string} `"cbm"`, `"speeddos"`, `"dolphindos"` or `"prologicdos"`
 * @example
 *   formatName(DiskFormat.DolphinDos);   # "dolphindos"
 */
export func formatName(format as DiskFormat) {
    match ($format) {
        when Cbm { return "cbm"; }
        when SpeedDos { return "speeddos"; }
        when DolphinDos { return "dolphindos"; }
        when PrologicDos { return "prologicdos"; }
    }
    return "cbm";
}

/**
 * The disk format a name spells, the inverse of {@link formatName}.
 *
 * @param name {string} the format name, case-insensitive
 * @return {DiskFormat} the format
 * @throws {Error} when the name is not one of the four
 * @example
 *   formatFromName("SpeedDOS");   # DiskFormat.SpeedDos
 */
export func formatFromName(name as string) {
    match (strings.lower(strings.trim($name))) {
        when "cbm", "1541", "commodore" { return DiskFormat.Cbm; }
        when "speeddos", "speed-dos", "speed" { return DiskFormat.SpeedDos; }
        when "dolphindos", "dolphin-dos", "dolphin" { return DiskFormat.DolphinDos; }
        when "prologicdos", "prologic-dos", "prologic" { return DiskFormat.PrologicDos; }
    }
    fail("\"" + $name + "\" is not a known disk format");
    return DiskFormat.Cbm;
}

/**
 * The track count a format is meant for.
 *
 * @param format {DiskFormat} the BAM layout
 * @return {int} 35 for `Cbm`, 40 for the three speeder formats
 * @example
 *   formatTracks(DiskFormat.SpeedDos);   # 40
 */
export func formatTracks(format as DiskFormat) {
    if ($format == DiskFormat.Cbm) {
        return TRACKS_STANDARD;
    }
    return TRACKS_EXTENDED;
}

/**
 * Where the disk header - name, ID and DOS type - sits in the BAM sector.
 *
 * @param format {DiskFormat} the BAM layout
 * @return {int} `$90`, or `$a4` under PrologicDOS
 * @example
 *   headerOffsetFor(DiskFormat.PrologicDos);   # 164
 */
export func headerOffsetFor(format as DiskFormat) {
    if ($format == DiskFormat.PrologicDos) {
        return HEADER_OFFSET_PROLOGIC;
    }
    return HEADER_OFFSET;
}

/**
 * Where a track's four BAM bytes sit in the BAM sector.
 *
 * Tracks 1-35 are always at `$04 + (track - 1) * 4`. Tracks 36-40 depend on
 * the format, and tracks 41-42 have no BAM entry under any of them - a
 * 42-track image is addressed sector by sector, never through the allocator.
 *
 * @param format {DiskFormat} the BAM layout
 * @param track {int}  track number, 1-42
 * @return {int} the byte offset, or -1 when the track has no BAM entry
 * @throws {Error} when `track` is outside 1-42
 * @example
 *   bamEntryOffset(DiskFormat.Cbm, 1);           # 4
 *   bamEntryOffset(DiskFormat.SpeedDos, 36);     # 192
 *   bamEntryOffset(DiskFormat.Cbm, 36);          # -1
 */
export func bamEntryOffset(format as DiskFormat, track as int) {
    if ($track < 1 or $track > TRACKS_MAX) {
        fail("track " + convert.toString($track) + " is outside 1-42");
    }
    if ($track <= TRACKS_STANDARD) {
        return 0x04 + ($track - 1) * 4;
    }
    if ($track > TRACKS_EXTENDED) {
        return -1;
    }
    match ($format) {
        when SpeedDos { return 0xc0 + ($track - 36) * 4; }
        when DolphinDos { return 0xac + ($track - 36) * 4; }
        when PrologicDos { return 0x90 + ($track - 36) * 4; }
        when Cbm { return -1; }
    }
    return -1;
}

/**
 * Guess the BAM layout of an image from its BAM sector.
 *
 * A 35-track image is always `Cbm` - it has no extra entries to place. On a
 * larger one the layouts are told apart by where the DOS type lands:
 * PrologicDOS moves the header, so `"2A"` sits at `$b9` instead of `$a5`.
 * The two that leave the header alone are told apart by which extra BAM
 * region carries a plausible free-sector count.
 *
 * A heuristic: an image with neither region reads as `Cbm`. Override the
 * result with {@link withFormat}.
 *
 * @param bam {bytes}    the 256 bytes of sector 18/0
 * @param tracks {int} the image's track count
 * @return {DiskFormat} the detected format
 * @example
 *   detectFormat(readSector($img, 18, 0), $img.tracks);
 */
export func detectFormat(bam as bytes, tracks as int) {
    if (len($bam) < SECTOR_SIZE or $tracks <= TRACKS_STANDARD) {
        return DiskFormat.Cbm;
    }
    if ($bam[0xb9] == 0x32 and $bam[0xba] == 0x41) {
        return DiskFormat.PrologicDos;
    }
    if (looksLikeBamRegion($bam, 0xc0)) {
        return DiskFormat.SpeedDos;
    }
    if (looksLikeBamRegion($bam, 0xac)) {
        return DiskFormat.DolphinDos;
    }
    return DiskFormat.Cbm;
}

/**
 * Whether the five BAM entries at `offset` could describe tracks 36-40.
 *
 * Every one of the five must claim at most 17 free sectors - the track length
 * up there - and at least one must be non-zero, so an untouched run of $00
 * does not read as a BAM.
 *
 * @param bam {bytes}    the BAM sector
 * @param offset {int} where the five entries would start
 * @return {bool} true when the region is plausible
 */
func looksLikeBamRegion(bam as bytes, offset as int) {
    def any as bool init false;
    for (def i as int init 0; $i < 5; $i = $i + 1) {
        def entry as int init $bam[$offset + $i * 4];
        if ($entry > 17) {
            return false;
        }
        if ($entry > 0) {
            $any = true;
        }
    }
    return $any;
}

/**
 * The default format options: a stock 35-track CBM disk, no error table,
 * blocks filled with `$00`.
 *
 * @return {FormatOptions} the defaults
 * @example
 *   def opts as FormatOptions init defaultFormatOptions();
 *   $opts.tracks = 40;
 */
export func defaultFormatOptions() {
    return FormatOptions{
        tracks: TRACKS_STANDARD,
        format: DiskFormat.Cbm,
        errorInfo: false,
        dosType: DOS_TYPE,
        fill: 0,
        mode: FormatMode.Full
    };
}

/**
 * Format a blank 35-track CBM disk.
 *
 * What `NEW0:NAME,ID` on a 1541 produces: tracks 1-35 free except 18/0 and
 * 18/1, and one empty directory block. {@link formatDiskWith} with
 * {@link defaultFormatOptions}.
 *
 * @param name {string} the disk name, 1 to 16 characters
 * @param id {string}   the disk ID, one or two characters
 * @return {Image} the formatted image
 * @throws {Error} when the name or the ID will not fit
 * @example
 *   def img as Image init formatDisk("sample disk", "01");
 *   blocksFree($img);   # 664
 */
export func formatDisk(name as string, id as string) {
    return formatDiskWith(defaultFormatOptions(), $name, $id);
}

/**
 * Format a blank disk to an explicit geometry and BAM layout.
 *
 * A 40-track geometry with `DiskFormat.Cbm` is allowed and a stock drive
 * reads it, but tracks 36-40 have no BAM entry, so the allocator never uses
 * them and {@link blocksFree} does not count them. A speeder layout with
 * fewer than 40 tracks throws.
 *
 * Tracks 41 and 42 are outside every BAM layout. {@link readSector} and
 * {@link writeSector} reach them; no file is placed there.
 *
 * @param options {FormatOptions} geometry and layout; zero fields take defaults
 * @param name {string}    the disk name, 1 to 16 characters
 * @param id {string}      the disk ID, one or two characters
 * @return {Image} the formatted image
 * @throws {Error} when the options, the name or the ID will not fit
 * @example
 *   def opts as FormatOptions init defaultFormatOptions();
 *   $opts.tracks = 40;
 *   $opts.format = DiskFormat.SpeedDos;
 *   def img as Image init formatDiskWith($opts, "40 track", "sd");
 *   blocksFree($img);   # 749
 */
export func formatDiskWith(options as FormatOptions, name as string, id as string) {
    def opts as FormatOptions init resolveFormatOptions($options);
    def img as Image init Image{
        data: zeroBytes(imageSize($opts.tracks, $opts.errorInfo)),
        tracks: $opts.tracks,
        errorInfo: $opts.errorInfo,
        format: $opts.format
    };
    if ($opts.fill != 0) {
        $img = fillBlocks($img, $opts.fill);
    }
    $img = clearErrorTable($img);
    return writeSystemBlocks($img, $opts, $name, $id);
}

/**
 * Re-format a disk: wipe every block, then write a blank BAM and directory.
 *
 * `N0:NAME,ID` on a 1541. Geometry, BAM layout and error table are kept; the
 * blocks are set to `$00`. {@link quickFormat} is the instant alternative
 * that leaves the blocks alone.
 *
 * @param img {Image} the disk to wipe
 * @param name {string} the new disk name, 1 to 16 characters
 * @param id {string}   the new disk ID, one or two characters
 * @return {Image} a blank image with the same geometry
 * @throws {Error} when the name or the ID will not fit
 * @example
 *   $img = reformat($img, "empty again", "02");
 */
export func reformat(img as Image, name as string, id as string) {
    return reformatWith($img, fullOptions(0), $name, $id);
}

/**
 * Erase the BAM and the directory, leaving every other block untouched.
 *
 * `N0:NAME` on a 1541, the soft format. The disk lists as empty and every
 * block is free, but the old files' bytes are still there: this does not
 * erase them.
 *
 * The disk ID and DOS type are kept, as on the drive. Two disks
 * quick-formatted from the same original share an ID, which is how a real
 * 1541 comes to use a stale BAM after a disk swap.
 *
 * @param img {Image} the disk to erase
 * @param name {string} the new disk name, 1 to 16 characters
 * @return {Image} the image with an empty directory
 * @throws {Error} when the name will not fit
 * @example
 *   $img = quickFormat($img, "empty again");
 *   len(listFiles($img));   # 0
 */
export func quickFormat(img as Image, name as string) {
    def opts as FormatOptions init fullOptions(0);
    $opts.mode = FormatMode.Quick;
    return reformatWith($img, $opts, $name, diskId($img));
}

/**
 * Re-format a disk, choosing how much of it to rewrite and with what.
 *
 * Only `mode`, `fill` and `dosType` are read from the options; geometry and
 * BAM layout come from the image (use {@link formatDiskWith} to change them).
 * A `dosType` of `""` keeps the image's own.
 *
 * @param img {Image} the disk to format
 * @param options {FormatOptions} mode, fill byte and DOS type
 * @param name {string}    the new disk name, 1 to 16 characters
 * @param id {string}      the new disk ID, one or two characters
 * @return {Image} the formatted image
 * @throws {Error} when the name, the ID or the fill byte will not fit
 * @example
 *   def opts as FormatOptions init defaultFormatOptions();
 *   $opts.fill = 0xff;
 *   $img = reformatWith($img, $opts, "wiped", "02");
 */
export func reformatWith(img as Image, options as FormatOptions, name as string, id as string) {
    def opts as FormatOptions init resolveFormatOptions(imageOptions($img, $options));
    match ($opts.mode) {
        when Quick { return writeSystemBlocks($img, $opts, $name, $id); }
        when Full {
            def wiped as Image init clearErrorTable(fillBlocks($img, $opts.fill));
            return writeSystemBlocks($wiped, $opts, $name, $id);
        }
    }
    return $img;
}

/**
 * Format options that wipe with one byte, geometry left to the caller.
 *
 * @param fill {int} the byte every block is set to
 * @return {FormatOptions} the options
 */
func fullOptions(fill as int) {
    return FormatOptions{
        tracks: 0,
        format: DiskFormat.Cbm,
        errorInfo: false,
        dosType: "",
        fill: $fill,
        mode: FormatMode.Full
    };
}

/**
 * Options with the geometry and layout of an image already in hand.
 *
 * @param img {Image} the disk being formatted
 * @param options {FormatOptions} what the caller asked for
 * @return {FormatOptions} the options, anchored to the image
 */
func imageOptions(img as Image, options as FormatOptions) {
    def opts as FormatOptions init $options;
    $opts.tracks = $img.tracks;
    $opts.format = $img.format;
    $opts.errorInfo = $img.errorInfo;
    if ($opts.dosType == "") {
        $opts.dosType = dosType($img);
    }
    return $opts;
}

/**
 * Set every block of an image to one byte, error table untouched.
 *
 * @param img {Image} the disk to change
 * @param fill {int} the byte, 0 to 255
 * @return {Image} the image with every block filled
 * @throws {Error} when the fill byte is not a byte
 */
func fillBlocks(img as Image, fill as int) {
    if ($fill < 0 or $fill > 0xff) {
        fail("a fill byte is 0 to 255, not " + convert.toString($fill));
    }
    def limit as int init blockCount($img) * SECTOR_SIZE;
    # the error table sits past the blocks and keeps its own codes
    def parts as list of bytes init [binary.make($limit, $fill), $img.data[$limit..]];
    def out as Image init $img;
    $out.data = binary.join($parts);
    return $out;
}

/**
 * Write the BAM and the first directory block, and claim them both.
 *
 * The whole of a quick format, and the last step of a full one.
 *
 * @param img {Image} the disk to change
 * @param opts {FormatOptions} the resolved options
 * @param name {string} the disk name
 * @param id {string}   the disk ID
 * @return {Image} the image with a blank filesystem on it
 * @throws {Error} when the name or the ID will not fit
 */
func writeSystemBlocks(img as Image, opts as FormatOptions, name as string, id as string) {
    def out as Image init writeSector(
        $img,
        DIRECTORY_TRACK,
        BAM_SECTOR,
        blankBamSector($opts, $name, $id));
    $out = writeSector($out, DIRECTORY_TRACK, FIRST_DIRECTORY_SECTOR, blankDirectorySector());
    $out = allocateSector($out, DIRECTORY_TRACK, BAM_SECTOR);
    return allocateSector($out, DIRECTORY_TRACK, FIRST_DIRECTORY_SECTOR);
}

/**
 * Fill in the zero fields of a {@link FormatOptions} and check the rest.
 *
 * @param options {FormatOptions} what the caller asked for
 * @return {FormatOptions} the same options with defaults applied
 * @throws {Error} when the geometry and the layout disagree
 */
func resolveFormatOptions(options as FormatOptions) {
    def opts as FormatOptions init $options;
    if ($opts.tracks == 0) {
        $opts.tracks = formatTracks($opts.format);
    }
    if ($opts.dosType == "") {
        $opts.dosType = DOS_TYPE;
    }
    if ($opts.tracks != TRACKS_STANDARD and $opts.tracks != TRACKS_EXTENDED and
        $opts.tracks != TRACKS_MAX) {
        fail("a D64 has 35, 40 or 42 tracks, not " + convert.toString($opts.tracks));
    }
    if ($opts.format != DiskFormat.Cbm and $opts.tracks < TRACKS_EXTENDED) {
        fail(formatName($opts.format) + " is a 40-track format; " + convert.toString($opts.tracks) +
            " tracks leaves its BAM entries unused");
    }
    if (len(toPetscii($opts.dosType)) != 2) {
        fail("the DOS type is two characters, not \"" + $opts.dosType + "\"");
    }
    if ($opts.fill < 0 or $opts.fill > 0xff) {
        fail("a fill byte is 0 to 255, not " + convert.toString($opts.fill));
    }
    return $opts;
}

/**
 * The BAM sector of a freshly formatted disk.
 *
 * @param opts {FormatOptions} the resolved options
 * @param name {string} the disk name
 * @param id {string}   the disk ID
 * @return {bytes} 256 bytes ready for sector 18/0
 * @throws {Error} when the name or the ID will not fit
 */
func blankBamSector(opts as FormatOptions, name as string, id as string) {
    def bam as bytes init zeroBytes(SECTOR_SIZE);
    $bam[0] = DIRECTORY_TRACK;
    $bam[1] = FIRST_DIRECTORY_SECTOR;
    $bam[2] = DOS_VERSION_BYTE;
    $bam[3] = 0x00;
    for (def t as int init 1; $t <= $opts.tracks; $t = $t + 1) {
        def at as int init bamEntryOffset($opts.format, $t);
        if ($at >= 0) {
            $bam = writeFreeTrackEntry($bam, $at, sectorsPerTrack($t));
        }
    }
    return writeDiskHeader($bam, $opts, $name, $id);
}

/**
 * Mark one track wholly free in a BAM sector under construction.
 *
 * The count byte is the sector count and every bit of the 24-bit map below
 * the track length is set - a set bit means "free". Bits past the end of the
 * track stay clear, the way a real drive leaves them.
 *
 * @param bam {bytes}     the BAM sector
 * @param at {int}      offset of the track's four bytes
 * @param sectors {int} how many sectors the track has
 * @return {bytes} the BAM sector with the entry written
 */
func writeFreeTrackEntry(bam as bytes, at as int, sectors as int) {
    def out as bytes init $bam;
    $out[$at] = $sectors;
    $out[$at + 1] = 0x00;
    $out[$at + 2] = 0x00;
    $out[$at + 3] = 0x00;
    for (def s as int init 0; $s < $sectors; $s = $s + 1) {
        def byteAt as int init $at + 1 + ($s // 8);
        $out[$byteAt] = setBit($out[$byteAt], $s % 8);
    }
    return $out;
}

/**
 * Stamp the disk name, ID, DOS type and their `$a0` filler into a BAM sector.
 *
 * @param bam {bytes}  the BAM sector
 * @param opts {FormatOptions} the resolved options
 * @param name {string} the disk name
 * @param id {string}   the disk ID
 * @return {bytes} the BAM sector with the header written
 * @throws {Error} when the name or the ID will not fit
 */
func writeDiskHeader(bam as bytes, opts as FormatOptions, name as string, id as string) {
    def out as bytes init $bam;
    def at as int init headerOffsetFor($opts.format);
    def label as bytes init encodeName($name);
    def code as bytes init encodeDiskId($id);
    def kind as bytes init toPetscii($opts.dosType);
    for (def i as int init 0; $i < MAX_FILENAME; $i = $i + 1) {
        $out[$at + $i] = $label[$i];
    }
    $out[$at + 0x10] = PAD_BYTE;
    $out[$at + 0x11] = PAD_BYTE;
    $out[$at + 0x12] = $code[0];
    $out[$at + 0x13] = $code[1];
    $out[$at + 0x14] = PAD_BYTE;
    $out[$at + 0x15] = $kind[0];
    $out[$at + 0x16] = $kind[1];
    for (def i as int init 0x17; $i <= 0x1a; $i = $i + 1) {
        $out[$at + $i] = PAD_BYTE;
    }
    return $out;
}

/**
 * Encode a disk ID into the two bytes the header holds.
 *
 * @param id {string} the ID, one or two characters
 * @return {bytes} exactly two PETSCII bytes, pad-filled when the ID is short
 * @throws {Error} when the ID is empty or longer than two characters
 */
func encodeDiskId(id as string) {
    def raw as bytes init toPetscii($id);
    if (len($raw) == 0 or len($raw) > 2) {
        fail("a disk ID is one or two characters, not \"" + $id + "\"");
    }
    def out as bytes init $raw;
    if (len($out) == 1) {
        $out[] = PAD_BYTE;
    }
    return $out;
}

/**
 * The single empty directory sector a fresh disk carries.
 *
 * Its link is `00/ff`: no next sector, and all 255 bytes after the link byte
 * count as used, which is how CBM DOS writes the last block of a chain.
 *
 * @return {bytes} 256 bytes ready for sector 18/1
 */
func blankDirectorySector() {
    def dir as bytes init zeroBytes(SECTOR_SIZE);
    $dir[0] = 0x00;
    $dir[1] = 0xff;
    return $dir;
}
