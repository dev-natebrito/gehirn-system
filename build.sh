#!/usr/bin/env bash
# build.sh — gehirn.system build script

set -e

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
LIMINE_DIR="$REPO_ROOT/limine"
ISO_ROOT="$REPO_ROOT/iso_root"
OUTPUT_ISO="$REPO_ROOT/gehirn.iso"
TARGET_JSON="$REPO_ROOT/targets/x86_64-gehirn.json"
KERNEL_BIN="$REPO_ROOT/target/x86_64-gehirn/debug/gehirn-kernel.elf"

# ── Step 0: Build the Limine BIOS installer tool ─────────────────────────────
if [ ! -f "$LIMINE_DIR/limine" ]; then
    echo ">> [boot] compiling limine tool..."
    make -C "$LIMINE_DIR"
fi

# ── Step 1: Compile ───────────────────────────────────────────────────────────
echo ">> [nerv] compiling kernel..."
cd "$REPO_ROOT/kernel"

RUSTFLAGS="" cargo +nightly build \
    -Z build-std=core,compiler_builtins \
    -Z build-std-features=compiler-builtins-mem \
    -Z json-target-spec \
    --target "$TARGET_JSON"

cd "$REPO_ROOT"

# ── Step 2: ISO root ──────────────────────────────────────────────────────────
echo ">> [nerv] assembling ISO root..."
rm -rf "$ISO_ROOT"
mkdir -p "$ISO_ROOT/boot/limine"
mkdir -p "$ISO_ROOT/EFI/BOOT"

cp "$KERNEL_BIN"                          "$ISO_ROOT/boot/gehirn-kernel"
cp "$REPO_ROOT/boot/limine.conf"          "$ISO_ROOT/boot/limine/limine.conf"
cp "$LIMINE_DIR/limine-bios.sys"          "$ISO_ROOT/boot/limine/"
cp "$LIMINE_DIR/limine-bios-cd.bin"       "$ISO_ROOT/boot/limine/"
cp "$LIMINE_DIR/limine-uefi-cd.bin"       "$ISO_ROOT/boot/limine/"
cp "$LIMINE_DIR/BOOTX64.EFI"              "$ISO_ROOT/EFI/BOOT/"
cp "$LIMINE_DIR/BOOTIA32.EFI"             "$ISO_ROOT/EFI/BOOT/"

# ── Step 3: Create ISO ────────────────────────────────────────────────────────
echo ">> [nerv] creating ISO..."
xorriso -as mkisofs \
    -R -r -J \
    -b boot/limine/limine-bios-cd.bin \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -hfsplus -apm-block-size 2048 \
    --efi-boot boot/limine/limine-uefi-cd.bin \
    -efi-boot-part --efi-boot-image --protective-msdos-label \
    "$ISO_ROOT" -o "$OUTPUT_ISO"

"$LIMINE_DIR/limine" bios-install "$OUTPUT_ISO"
echo ">> [nerv] ISO ready: $OUTPUT_ISO"

# ── Step 4: QEMU ─────────────────────────────────────────────────────────────
echo ">> [nerv] launching QEMU..."
qemu-system-x86_64 \
    -M q35 -m 256M \
    -cdrom "$OUTPUT_ISO" -boot d \
    -serial stdio \
    -no-reboot -no-shutdown