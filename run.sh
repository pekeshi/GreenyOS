#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
ESP_DIR="${BUILD_DIR}/esp"
QEMU_EXE="${QEMU_EXE:-qemu-system-x86_64}"
QEMU_DISPLAY="${QEMU_DISPLAY:-auto}"

bash "$ROOT_DIR/build.sh"

if ! command -v "$QEMU_EXE" >/dev/null 2>&1; then
    printf 'ERROR: QEMU was not found. Install qemu-system-x86 or set QEMU_EXE.\n' >&2
    exit 1
fi

DISPLAY_BACKENDS="$("$QEMU_EXE" -display help 2>&1 | awk '/^Available display backend types:/ { in_list=1; next } in_list && NF { print $1 } !NF { in_list=0 }')"
if [[ "$QEMU_DISPLAY" == auto ]]; then
    for backend in gtk sdl; do
        if grep -Fxq "$backend" <<< "$DISPLAY_BACKENDS"; then
            QEMU_DISPLAY="$backend"
            break
        fi
    done
    if [[ "$QEMU_DISPLAY" == auto ]]; then
        printf 'ERROR: QEMU has no GTK or SDL display backend. On Arch Linux, install qemu-ui-gtk or qemu-ui-sdl (or qemu-desktop).\n' >&2
        printf 'Available display backends: %s\n' "${DISPLAY_BACKENDS//$'\n'/, }" >&2
        exit 1
    fi
elif ! grep -Fxq "$QEMU_DISPLAY" <<< "$DISPLAY_BACKENDS"; then
    printf 'ERROR: QEMU display backend "%s" is unavailable.\n' "$QEMU_DISPLAY" >&2
    printf 'Available display backends: %s\n' "${DISPLAY_BACKENDS//$'\n'/, }" >&2
    exit 1
fi

if [[ -z "${OVMF_CODE:-}" ]]; then
    for firmware in \
        /usr/share/edk2/x64/OVMF_CODE.4m.fd \
        /usr/share/OVMF/OVMF_CODE.fd \
        /usr/share/ovmf/OVMF_CODE.fd \
        /usr/share/edk2/ovmf/OVMF_CODE.fd \
        /usr/share/edk2/x64/OVMF_CODE.fd \
        /usr/share/qemu/OVMF_CODE.fd; do
        if [[ -f "$firmware" ]]; then
            OVMF_CODE="$firmware"
            break
        fi
    done
fi

if [[ -z "${OVMF_CODE:-}" ]]; then
    printf 'ERROR: OVMF firmware not found. Set OVMF_CODE to the x64 firmware image.\n' >&2
    exit 1
fi
if [[ ! -f "$OVMF_CODE" ]]; then
    printf 'ERROR: OVMF_CODE does not exist: "%s"\n' "$OVMF_CODE" >&2
    exit 1
fi

if [[ -z "${OVMF_VARS:-}" ]]; then
    for firmware in \
        /usr/share/edk2/x64/OVMF_VARS.4m.fd \
        /usr/share/OVMF/OVMF_VARS.fd \
        /usr/share/ovmf/OVMF_VARS.fd \
        /usr/share/edk2/ovmf/OVMF_VARS.fd \
        /usr/share/edk2/x64/OVMF_VARS.fd \
        /usr/share/qemu/OVMF_VARS.fd; do
        if [[ -f "$firmware" ]]; then
            OVMF_VARS="$firmware"
            break
        fi
    done
fi

if [[ -n "${OVMF_VARS:-}" && ! -f "$OVMF_VARS" ]]; then
    printf 'ERROR: OVMF_VARS does not exist: "%s"\n' "$OVMF_VARS" >&2
    exit 1
fi

RUN_ID="$(date +%Y%m%d-%H%M%S)-$$"
SERIAL_LOG="$BUILD_DIR/serial-$RUN_ID.log"
QEMU_ARGS=(
    -name 'GreenyOS - 0.1 - pekeshi'
    -machine q35
    -m 256M
    -display "$QEMU_DISPLAY"
    -device qemu-xhci
    -device usb-kbd
)

if [[ -n "${OVMF_VARS:-}" ]]; then
    OVMF_VARS_RUN="$(mktemp "$BUILD_DIR/OVMF_VARS-XXXXXX.fd")"
    cp "$OVMF_VARS" "$OVMF_VARS_RUN"
    trap 'rm -f -- "$OVMF_VARS_RUN"' EXIT
    QEMU_ARGS+=(
        -drive "if=pflash,format=raw,unit=0,file=$OVMF_CODE,readonly=on"
        -drive "if=pflash,format=raw,unit=1,file=$OVMF_VARS_RUN"
    )
else
    printf 'WARNING: No OVMF variable-store image found; using firmware without persistent variables.\n' >&2
    QEMU_ARGS+=(-bios "$OVMF_CODE")
fi

QEMU_ARGS+=(
    -drive "format=raw,file=fat:rw:$ESP_DIR,if=ide,index=0"
    -serial "file:$SERIAL_LOG"
    -monitor none
)

printf 'Serial log: %s\n' "$SERIAL_LOG"
"$QEMU_EXE" "${QEMU_ARGS[@]}"