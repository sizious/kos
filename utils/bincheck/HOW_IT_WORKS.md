# How bincheck works

This document explains how `bincheck` decides whether a Sega Dreamcast
`.BIN` file is **scrambled** (the layout expected when booting from a CD,
typically `1ST_READ.BIN`) or **unscrambled** (a plain, linear program
image). For build and usage instructions, see [README.md](README.md).

In one sentence: `bincheck` descrambles the file and checks which of the
two versions has the structure of a real program.

## Overview

The tool is made of three parts:

| File | Role |
|------|------|
| [`src/main.c`](src/main.c) | Command-line front end: parses options, prints the verdict and warnings. |
| [`src/scramble.c`](src/scramble.c) | The real scramble/descramble algorithm. |
| [`src/check.c`](src/check.c) | The detection itself (`bincheck_analyze_buffer()`). |

## Step 1: descrambling

`scramble.c` is a port of Marcus Comstedt's `scramble` tool from
KallistiOS (`utils/scramble`).

Dreamcast scrambling is **not encryption**. No byte value is changed. The
file is cut into **32-byte slices**, and those slices are shuffled
(Fisher-Yates) in chunks that shrink from 2 MB down to 32 bytes. The
pseudo-random generator driving the shuffle is seeded with the file size.

Because the shuffle depends only on the file size, it is fully
deterministic and can be reversed exactly. `dc_descramble_buffer()`
computes the real inverse permutation, not an approximation. This was
checked with a byte-exact round trip on dcload-ip: descrambling its
`1st_read.bin` gives exactly `loader.bin`, and scrambling `loader.bin`
gives exactly `1st_read.bin`.

`bincheck` only uses descrambling for detection and does not write the
result anywhere. To actually scramble or unscramble a file, use the
`scramble` tool that ships with KallistiOS (`utils/scramble`).

## Step 2: detection

`bincheck_analyze_buffer()` (in `src/check.c`) does the following:

1. It **always descrambles** the input, whether it was scrambled or not,
   and keeps both the original and the descrambled copy.
2. It computes the **entropy variance** (see below) of each copy.
3. It compares the two values:

   ```
   relative_increase = (variance_unscrambled - variance_as_is) / variance_as_is
   is_scrambled      = relative_increase > margin      (default margin: 0.15)
   ```

   In other words, if descrambling makes the entropy variance rise by more
   than 15%, the file was scrambled.

Before that, it runs two sanity checks to make sure the file is one
`bincheck` can judge; see
[Checking that the file is a Dreamcast program](#checking-that-the-file-is-a-dreamcast-program).
Disassembling the file was tried as a detection method and dropped; see
[Why not use the disassembler?](#why-not-use-the-disassembler).

## What is entropy variance?

### Shannon entropy

The Shannon entropy of a block of bytes measures how unpredictable its
content is, from 0 to 8 bits per byte:

| Content | Typical entropy |
|---------|-----------------|
| Block of zeros (padding, BSS) | 0 |
| Text, tables with repeated patterns | low to medium |
| SH-4 machine code | high (about 5 to 7) |
| Compressed or random data | close to 8 |

It is computed by `shannon_entropy()` from the byte histogram of the
block: `H = -Σ p(b) · log2(p(b))`, where `p(b)` is the frequency of byte
value `b`.

### Variance across blocks

`block_entropy_variance()` goes one step further:

1. It cuts the file into consecutive blocks of 256 bytes (option `-b`).
2. It computes the entropy of each block.
3. It returns the (population) variance of those values, in other words
   how spread out they are around their mean.

### Why it detects scrambling

Since scrambling only moves bytes around, the file contains exactly the
same bytes before and after. Entropy computed over the **whole file** is
therefore identical in both cases and cannot be used as a signal.

What changes is the **local** structure:

- **An unscrambled binary** has distinct regions: dense code (high
  entropy), data tables (medium), runs of zeros (close to 0). The block
  entropies are spread over a wide range, so **the variance is high**.
- **A scrambled binary** has had those regions cut into 32-byte slices and
  scattered. Each 256-byte block now holds a mix of code, data and zeros,
  so every block looks roughly average. **The variance is low.**

This makes the test work in both directions:

- If the file **was scrambled**, descrambling rebuilds the distinct
  regions and the variance rises sharply.
- If the file **was already unscrambled**, "descrambling" it actually
  shuffles it, and the variance stays flat or drops.

## Worked example

Here is `bincheck -v` run on a real 1,236,356-byte homebrew program, in
both states: `test-s.bin` is the scrambled version and `test-u.bin` is the
unscrambled one.

```
$ ./bincheck -v test-s.bin
File                         : test-s.bin
Entropy variance, as-is      : 1.1451
Entropy variance, unscrambled: 2.6444
Threshold (relative increase): +15%
SH-4 code score              : 109.63 (minimum: 2.00)
---
test-s.bin: Scrambled

$ ./bincheck -v test-u.bin
File                         : test-u.bin
Entropy variance, as-is      : 2.6444
Entropy variance, unscrambled: 1.1965
Threshold (relative increase): +15%
SH-4 code score              : 109.63 (minimum: 2.00)
---
test-u.bin: Unscrambled
```

| File | Variance as-is | Variance after descramble | Change | Verdict |
|------|----------------|---------------------------|--------|---------|
| `test-s.bin` | 1.1451 | 2.6444 | **+131%** | Scrambled |
| `test-u.bin` | 2.6444 | 1.1965 | **−55%** | Unscrambled |

The variance of the scrambled file more than doubles once descrambled,
well above the 15% threshold. Descrambling the already-unscrambled file
instead halves its variance. Note that the "unscrambled" variance of
`test-s.bin` is exactly the "as-is" variance of `test-u.bin`: the
descramble reproduces the original file byte for byte.

Other real programs show the same pattern, with smaller gaps:

| Program | Scrambled file, after descramble | Unscrambled file, after descramble |
|---------|----------------------------------|------------------------------------|
| dcload-ip (`1st_read.bin` / `loader.bin`) | +51% | −33% |
| dcload-serial (`1st_read.bin` / `loader.bin`) | +31% | −21% |
| KOS example `nehe05` (`1st_read.bin` / `nehe05.bin`) | +134% | −53% |

All are classified correctly. dcload-serial, at +31%, is the closest to the
15% threshold so far.

## Why not use the disassembler?

An intuitive approach would be to disassemble the file and check whether
the result looks like valid SH-4 code. Earlier versions of `bincheck` did
this with the `dcdis` disassembler, but it does not work well:

- The SH-4 opcode space is **dense**: even random noise decodes to about
  90% "valid" instructions, so a scrambled file still looks mostly valid.
- The difference between the two versions is small and does not always
  point the right way. On the two files of the example above, the ratio
  of valid opcodes (over the first 4 KB) **increases after descrambling
  in both cases**: 86% → 90% for the scrambled file, 90% → 93% for the
  unscrambled one. It cannot tell them apart.

`dcdis` was therefore removed. This also keeps `bincheck` entirely under
permissive licenses, since `dcdis` is GPLv3.

## Checking that the file is a Dreamcast program

The entropy test always gives an answer, even for a file that is not a
Dreamcast program at all: a PC executable, an image or a text file is
usually reported as "Unscrambled". To catch this, `bincheck` runs two
checks on the file and prints a warning (on `stderr`) when one fails. The
checks never change the verdict itself.

**ELF files.** A file starting with the ELF magic bytes (`ELF`) is
reported as an ELF file. `bincheck` only works on raw `.BIN` files, which
are what `objcopy -O binary` produces from an ELF.

**SH-4 code.** Instead of disassembling the file, `bincheck` counts two
specific 16-bit instructions that GCC places at the start and end of
every function that calls another function:

- `sts.l pr,@-r15` (`0x4f22`): save the return address on the stack;
- `lds.l @r15+,pr` (`0x4f26`): restore it.

Unlike "is this a valid instruction?", which is true for about 90% of all
possible 16-bit values, these exact words are very rare in anything that
is not SH-4 code. The **SH-4 code score** is the number of occurrences of
both instructions per 10,000 words. The file is considered SH-4 code if
both instructions are present and the score is at least 2
(`BINCHECK_SH4_MIN_SCORE` in `src/check.h`).

| Files | SH-4 code score |
|-------|-----------------|
| Raw Dreamcast binaries (dcload-ip, dcload-serial, KOS examples, `IP.BIN` bootstraps) | 45 to 140 |
| KOS ELF files (code plus debug information) | about 12 |
| x86 executables and DLLs, ARM code, images, fonts, text | 0 to 0.85 |

The threshold is 20 times lower than the lowest Dreamcast binary measured,
and more than twice the highest score seen on other files (a single
chance occurrence in a small JPEG).

Because scrambling moves whole 32-byte slices, every 16-bit instruction
stays intact: the score is exactly the same for the scrambled and the
unscrambled version of a file, so this check does not need to descramble
anything.

## Limitations

- **Calibration.** The 15% threshold (`BINCHECK_DEFAULT_VARIANCE_MARGIN` in
  `src/check.h`) has only been checked on a few programs (see the
  [worked example](#worked-example)). It should be validated on binaries
  from other toolchains. It can be tuned with `-m`, and the block size
  with `-b`.
- **SH-4 detection.** The SH-4 code check relies on GCC's usual function
  prologue and epilogue. A program with very little code compared to its
  embedded data (large textures or sound), or code produced by another
  compiler or written in assembly, may get a low score and trigger a
  false warning. The verdict is still printed in that case.
- **Raw `.BIN` files only.** ELF files are detected and trigger a warning,
  since the result is meaningless for them.
- **Weakly structured files.** A very small file, or one made almost
  entirely of code with little data or padding, has little entropy
  variance to begin with. The signal will be weaker, and the verdict less
  reliable.
