#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
ESP_DIR="${BUILD_DIR}/esp"
EFI_CC="${EFI_CC:-x86_64-w64-mingw32-gcc}"
KERNEL_CC="${KERNEL_CC:-gcc}"

if ! command -v "$EFI_CC" >/dev/null 2>&1; then
    printf 'ERROR: UEFI compiler not found. Install MinGW-w64 or set EFI_CC.\n' >&2
    exit 1
fi

EFI_TARGET="$("$EFI_CC" -dumpmachine)"
if [[ "$EFI_TARGET" != x86_64-w64-mingw32 ]]; then
    printf 'ERROR: Expected the x86_64-w64-mingw32 target; found "%s".\n' "$EFI_TARGET" >&2
    exit 1
fi

if ! command -v "$KERNEL_CC" >/dev/null 2>&1; then
    printf 'ERROR: Freestanding kernel compiler not found. Install x86_64-elf-gcc or set KERNEL_CC.\n' >&2
    exit 1
fi

KERNEL_TARGET="$("$KERNEL_CC" -dumpmachine)"
case "$KERNEL_TARGET" in
    x86_64-elf|x86_64-linux-gnu|x86_64-pc-linux-gnu) ;;
    *)
        printf 'ERROR: Expected an x86_64 ELF compiler target; found "%s".\n' "$KERNEL_TARGET" >&2
        exit 1
        ;;
esac

mkdir -p "$BUILD_DIR" "$ESP_DIR/EFI/BOOT"

"$KERNEL_CC" \
    -std=c11 -O2 -Wall -Wextra \
    -ffreestanding -fno-builtin -fno-pie -fno-pic -fno-stack-protector \
    -fno-asynchronous-unwind-tables -fno-unwind-tables \
    -mno-red-zone -mgeneral-regs-only -mcmodel=small \
    -I"$ROOT_DIR/kernel/include" -I"$ROOT_DIR/boot" \
    -nostdlib -static -no-pie \
    -Wl,-T,"$ROOT_DIR/kernel/linker.ld" \
    -Wl,-Map,"$BUILD_DIR/KERNEL.map" \
    -Wl,-z,noexecstack \
    "$ROOT_DIR/kernel/entry.S" \
    "$ROOT_DIR/kernel/gdt.c" \
    "$ROOT_DIR/kernel/kernel.c" \
    "$ROOT_DIR/kernel/memory.c" \
    "$ROOT_DIR/kernel/paging.c" \
    "$ROOT_DIR/kernel/interrupts.c" \
    "$ROOT_DIR/kernel/power.c" \
    "$ROOT_DIR/kernel/serial.c" \
    "$ROOT_DIR/kernel/usb_xhci.c" \
    "$ROOT_DIR/kernel/framebuffer.c" \
    "$ROOT_DIR/kernel/keyboard.c" \
    "$ROOT_DIR/kernel/shell.c" \
    "$ROOT_DIR/kernel/vga.c" \
    -o "$BUILD_DIR/KERNEL.ELF"

"$EFI_CC" \
    -std=c11 -O2 -Wall -Wextra \
    -ffreestanding -fno-builtin -fno-stack-protector \
    -fno-asynchronous-unwind-tables -fno-unwind-tables \
    -fshort-wchar \
    -I"$ROOT_DIR/kernel/include" -I"$ROOT_DIR/boot" \
    "$ROOT_DIR/boot/bootx64.c" \
    -nostdlib -Wl,--subsystem,10 -Wl,--entry,efi_main \
    -Wl,--enable-reloc-section -o "$BUILD_DIR/BOOTX64.EFI"

cp "$BUILD_DIR/BOOTX64.EFI" "$ESP_DIR/EFI/BOOT/BOOTX64.EFI"
cp "$BUILD_DIR/KERNEL.ELF" "$ESP_DIR/KERNEL.ELF"

printf 'Built UEFI loader and freestanding kernel.\n'
printf 'Bootloader: %s\n' "$BUILD_DIR/BOOTX64.EFI"
printf 'Kernel:     %s\n' "$BUILD_DIR/KERNEL.ELF"