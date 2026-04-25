// kernel/src/main.rs
//
// nerv:: — Gehirn System entry point
// Orchestrates the initialization of all subsystems.
// This file does not belong to any module — it is the conductor, not a musician.
// It calls nerv::, magi::, rei:: and others in sequence as they are built out.

#![no_std]
#![no_main]

use limine::request::{FramebufferRequest, StackSizeRequest};
use limine::{BaseRevision, RequestsEndMarker, RequestsStartMarker};

// ── Limine Protocol ───────────────────────────────────────────────────────────
//
// The Limine bootloader scans the ".requests" ELF section before transferring
// control to the kernel. It looks for request structs, fills in their response
// fields, and only then calls kernel_main.
//
// #[used] prevents the compiler from silently discarding these as "unused".
// link_section places them in the correct ELF section for Limine to find.
// KEEP() in the linker script ensures the linker does not strip them either.

#[used]
#[unsafe(link_section = ".requests_start_marker")]
static _REQUESTS_START: RequestsStartMarker = RequestsStartMarker::new();

#[used]
#[unsafe(link_section = ".requests_end_marker")]
static _REQUESTS_END: RequestsEndMarker = RequestsEndMarker::new();

// Declares which revision of the Limine protocol this kernel supports.
// The bootloader checks this and will refuse to boot if incompatible.
#[used]
#[unsafe(link_section = ".requests")]
static BASE_REVISION: BaseRevision = BaseRevision::new();

// Requests a larger stack before boot.
// Limine's default stack is too small for debug Rust builds — 1MB is safe.
#[used]
#[unsafe(link_section = ".requests")]
static STACK_SIZE: StackSizeRequest = StackSizeRequest::new(0x100000);

// Requests framebuffer info: base address, resolution, bytes per row.
// Without this response we have no way to write pixels to the screen.
#[used]
#[unsafe(link_section = ".requests")]
static FRAMEBUFFER: FramebufferRequest = FramebufferRequest::new();

// ── Entry Point ───────────────────────────────────────────────────────────────
//
// extern "C" uses the C ABI, which is what Limine expects when calling the kernel.
// -> ! means this function never returns. A kernel has nowhere to return to.

#[unsafe(no_mangle)]
extern "C" fn kernel_main() -> ! {
    // Sanity check: did Limine process our revision tag correctly?
    // If not, we cannot make any assumptions about the system state.
    assert!(BASE_REVISION.is_supported());

    // Retrieve the framebuffer that Limine prepared for us.
    // get_response() returns None if the bootloader did not fill this request,
    // which would indicate an incompatible bootloader or bad configuration.
    let fb = FRAMEBUFFER
        .response()
        .expect("no framebuffer response from Limine")
        .framebuffers()
        .first()
        .expect("no framebuffer available");

    // ── Phase 1: paint the screen a solid color ───────────────────────────────
    //
    // The framebuffer is a linear array of pixels mapped directly in RAM.
    // For a pixel at position (x, y) with `pitch` bytes per row:
    //   address = base + y * pitch + x * bytes_per_pixel
    //
    // We start by filling the entire screen with a single color.
    // If it works, we know three things are true:
    //   1. The kernel booted successfully
    //   2. Limine delivered a valid framebuffer
    //   3. We are writing pixels to RAM correctly
    //
    // Color: #1a1a2e — the project's deep blue, coherent with gehirn.systems aesthetics.
    // Pixel format is BGRX: memory bytes are Blue, Green, Red, Padding (not RGB).
    let color: u32 = 0x001a1a2e;

    let fb_ptr = fb.address() as *mut u32;
    let width  = fb.width  as usize;
    let height = fb.height as usize;

    // pitch is bytes per row. Dividing by 4 converts to u32 pixels per row,
    // because fb_ptr is *mut u32 and Rust pointer arithmetic accounts for type size.
    let pitch  = fb.pitch as usize / 4;

    for y in 0..height {
        for x in 0..width {
            unsafe {
                // write_volatile tells the compiler: do not optimize this away.
                // Without volatile, the compiler may decide that writing the same
                // value thousands of times is redundant and eliminate the entire loop.
                fb_ptr.add(y * pitch + x).write_volatile(color);
            }
        }
    }

    // ── Halt loop ─────────────────────────────────────────────────────────────
    //
    // The kernel has nothing else to do for now.
    // `hlt` suspends the CPU until the next interrupt — far more efficient
    // than a busy loop that would spin at 100% CPU doing nothing useful.
    // Phase 2 will replace this with actual subsystem initialization.
    loop {
        unsafe { core::arch::asm!("hlt") };
    }
}

// ── Panic handler ─────────────────────────────────────────────────────────────
//
// In no_std, Rust requires you to define what happens on a panic.
// Phase 1: silent halt — the screen will just freeze.
// Phase 2 (rei::uart): will print the panic message to the serial console.
// Phase 3 (evangelion::): will render the panic info directly on the framebuffer.
#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {
        unsafe { core::arch::asm!("hlt") };
    }
}