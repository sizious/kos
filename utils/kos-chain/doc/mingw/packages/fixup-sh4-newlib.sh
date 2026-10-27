#!/usr/bin/env bash

# You can change these options if needed.
export toolchains_base=/opt/toolchains/dc
export kos_base=$toolchains_base/kos
export newlib_inc=$toolchains_base/sh-elf/sh-elf/include

# In original kos-chain Makefile, the instructions below are symbolic links.
# But the "ln" tool under MinGW/MSYS is not working properly.
# So each time you update KallistiOS, you'll need to run this tool to update
# the includes used by the SH4 compiler.
#
# The actual list of headers is maintained in kos-chain's
# 'scripts/fixup-newlib.sh'; this is just a convenience wrapper.
exec bash "$kos_base/utils/kos-chain/scripts/fixup-newlib.sh" -c "$kos_base" "$newlib_inc"
