/* kernel/linker.ld
 *
 * Places all kernel segments in the Higher Half (above 0xffffffff80000000).
 * The Limine protocol mandates this — it refuses to load kernels with
 * segments in the lower half of the address space.
 *
 * The requests PHDR must come first and be separate from .text,
 * otherwise the bootloader may not find the request structures.
 */

OUTPUT_FORMAT(elf64-x86-64)
OUTPUT_ARCH(i386:x86-64)

ENTRY(kernel_main)

PHDRS {
    requests PT_LOAD;   /* Limine request structures — must be first   */
    text     PT_LOAD;   /* R+X — executable code                       */
    rodata   PT_LOAD;   /* R   — read-only data                        */
    data     PT_LOAD;   /* R+W — read/write data and bss               */
}

SECTIONS {
    /*
     * Start at the canonical Higher Half base for x86_64 kernels.
     * The Limine spec mandates placement in the topmost 2GiB of the
     * address space, and 0xffffffff80000000 is the standard starting point.
     */
    . = 0xffffffff80000000;

    /* ── .requests — Limine protocol structures ─────────────────────────── */
    /*
     * This section must come before .text and live in its own PHDR.
     * The bootloader scans this region to find our requests before
     * transferring control. KEEP() prevents the linker from stripping
     * these as unreferenced — the bootloader reads them directly from
     * the ELF, bypassing normal Rust call chains.
     */
    .requests : {
        KEEP(*(.requests_start_marker))
        KEEP(*(.requests .requests.*))
        KEEP(*(.requests_end_marker))
    } :requests

    . = ALIGN(4096);

    /* ── .text — executable code ─────────────────────────────────────────── */
    .text : {
        *(.text .text.*)
    } :text

    . = ALIGN(4096);

    /* ── .rodata — constants, string literals ────────────────────────────── */
    .rodata : {
        *(.rodata .rodata.*)
    } :rodata

    . = ALIGN(4096);

    /* ── .data — initialized globals ─────────────────────────────────────── */
    .data : {
        *(.data .data.*)
    } :data

    /* ── .bss — zero-initialized globals ─────────────────────────────────── */
    .bss : {
        __bss_start = .;
        *(.bss .bss.*)
        *(COMMON)
        __bss_end = .;
    } :data

    /* ── Discard unwind tables and debug metadata ─────────────────────────── */
    /DISCARD/ : {
        *(.eh_frame)
        *(.note .note.*)
    }
}