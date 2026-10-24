# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * White-box unit tests for the d64 module.
 *
 * Run with `jennifer test src/d64_test.j`. One test file per topic under
 * `topics/`, spliced with `include` in the order `d64.j` splices the topics.
 *
 * The deck is pure computation over a byte buffer, so no fixture files are
 * needed; `open` and `save` are tested in a temporary directory.
 */

use testing;
use strings;
use lists;
use convert;

include "topics/core_test.j";
include "topics/geometry_test.j";
include "topics/petscii_test.j";
include "topics/format_test.j";
include "topics/image_test.j";
include "topics/bam_test.j";
include "topics/directory_test.j";
include "topics/files_test.j";
