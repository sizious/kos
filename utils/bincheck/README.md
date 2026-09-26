# Sega Dreamcast Binary Checker (bincheck)

`bincheck` tells you whether a Sega Dreamcast homebrew program in `.BIN`
format is **scrambled** or **unscrambled**.

## Scrambled or unscrambled?

A `.BIN` file is a compiled Dreamcast program, the kind of file you find in
homebrew packages labelled "plain files". It can exist in two states:

- **Scrambled**: required when the program is booted from a CD-ROM, that
  is, started by the bootstrap (usually called `IP.BIN`). Such programs are
  commonly named `1ST_READ.BIN`.
- **Unscrambled**: used in every other case, for example when the program
  is started by another program, such as a loader.

This distinction only applies to homebrew programs, built with homebrew
toolchains such as KallistiOS.

`bincheck` works on raw `.BIN` files only. It warns you if you give it an
ELF file, or a file that does not look like Dreamcast (SH-4) code at all,
since the result would be meaningless.

This tool is a C rewrite of the original Binary Checker (`bincheck.dll`,
written in Delphi in 2005). The original recognized a fixed list of
toolchain signatures; this version looks at the file's content instead,
so it does not depend on the toolchain.

## Usage

```
./bincheck [options] <file.bin>

  -b <bytes>     Block size for the entropy variance (default: 256)
  -m <margin>    Decision threshold, relative increase (default: 0.15)
  -v             Verbose mode (show details)
  -h             Show this help
```

For example:

```
$ ./bincheck 1ST_READ.BIN
1ST_READ.BIN: Scrambled

$ ./bincheck -v 1ST_READ.BIN
File                         : 1ST_READ.BIN
Entropy variance, as-is      : 1.1451
Entropy variance, unscrambled: 2.6444
Threshold (relative increase): +15%
SH-4 code score              : 109.63 (minimum: 2.00)
---
1ST_READ.BIN: Scrambled

$ ./bincheck notepad.exe
Warning: "notepad.exe" does not look like SH-4 code (Dreamcast program) so this result is probably meaningless
notepad.exe: Unscrambled
```

Warnings are printed on `stderr`, so scripts reading the verdict on
`stdout` are not affected.

To actually scramble or unscramble a file, use the `scramble` tool that
ships with KallistiOS (`utils/scramble`).

## How it works

In short: `bincheck` descrambles the file, then checks which of the two
versions has the structure of a real program.

Scrambling does not change any byte; it only shuffles the file in 32-byte
slices. A normal program has distinct regions (code, data, runs of zeros),
and scrambling mixes them together. `bincheck` measures how different the
regions of a file are from one another, using the variance of the Shannon
entropy computed over 256-byte blocks. If that variance rises clearly
after descrambling, the file was scrambled.

The code is split into two parts:

- **`src/scramble.c`**: the real scramble/descramble algorithm, ported from
  Marcus Comstedt's `scramble` tool (`utils/scramble` in KallistiOS).
- **`src/check.c`**: the detection itself.

Before that, `bincheck` checks that the file really is a raw Dreamcast
program: it rejects ELF files, and looks for two SH-4 instructions that
GCC emits in almost every function. Either failed check prints a warning.

See [HOW_IT_WORKS.md](HOW_IT_WORKS.md) for the full explanation, including
a worked example and why disassembling the file is not a reliable way to
tell the two states apart.

## Accuracy

The detection threshold (`BINCHECK_DEFAULT_VARIANCE_MARGIN` in
`src/check.h`, +15% by default) has so far been checked on only a few real
programs (dcload-ip, dcload-serial, a KOS example). It has not yet been
validated on binaries from a wide range of toolchains, so keep this in mind
before relying on it. If you get a wrong verdict, you can adjust the
threshold with `-m` and the block size with `-b`, and please report the
case.

## Build

```
make
```

This builds everything in `src/` and places the stripped `bincheck` binary
in this directory. `make clean` removes the build artifacts.

You can also work directly in `src/`: there, `make` builds and strips the
binary, and `make install` moves it up to this directory.

`bincheck` has no dependencies besides the C standard library and the math library
(`libm`). It has been tested with GCC on Linux, and should build as-is on
macOS and on Windows with MinGW.

## Project layout

```
bincheck/
├── src/
│   ├── scramble.h/.c        # scramble/descramble algorithm (Comstedt)
│   ├── check.h/.c           # detection (entropy variance)
│   ├── main.c               # command-line tool
│   └── Makefile             # builds bincheck and installs it in ../
├── HOW_IT_WORKS.md          # detailed explanation of the detection
├── LICENSE                  # BSD 2-Clause License
├── Makefile                 # runs make and make install in src/
└── README.md
```

## Possible improvements

- Calibrate the detection threshold on more real programs, built with
  different toolchains (KallistiOS, NetBSD ELF toolchain, others).

## License

- `bincheck` is released under the **BSD 2-Clause License** (see
  [LICENSE](LICENSE)).
- `src/scramble.c` is a port of Marcus Comstedt's `scramble.c` (KallistiOS
  `utils/scramble`), released under the KOS License (BSD-style).
