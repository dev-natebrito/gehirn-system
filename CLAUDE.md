# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**gehirn.system** is a bare-metal OS written in Rust, purpose-built for local LLM inference. It targets x86-64 UEFI systems using the Limine bootloader protocol with a higher-half kernel layout.

Status: **Pre-alpha, Phase 01 in progress.** Only the `kernel` crate (`nerv::`) exists so far — all other crates listed in the architecture table are planned.

## Build and Run

The full build pipeline (compile → ISO → QEMU) is driven by `build.sh`:

```sh
./build.sh
```

This requires:
- **Rust nightly** toolchain (the build uses `-Z build-std` and `-Z json-target-spec`)
- **Limine** — included as a git submodule at `limine/`; run `git submodule update --init` after cloning
- **`gcc`** (or `cc`) to compile the `limine` BIOS installer tool on first build
- **`xorriso`** for ISO creation
- **`qemu-system-x86_64`** for emulation

To compile only (no ISO or QEMU), run from the `kernel/` directory:

```sh
cd kernel
RUSTFLAGS="" cargo +nightly build \
    -Z build-std=core,compiler_builtins \
    -Z build-std-features=compiler-builtins-mem \
    -Z json-target-spec \
    --target ../targets/x86_64-gehirn.json
```

Build output: `kernel/target/x86_64-gehirn/debug/gehirn-kernel` (ELF). ISO: `gehirn.iso` at repo root.

For type-checking without building:

```sh
cd kernel && cargo +nightly check -Z build-std=core,compiler_builtins -Z json-target-spec --target ../targets/x86_64-gehirn.json
```

There are no runnable tests yet — kernel tests require QEMU integration.

## Architecture

The OS is organized as a Cargo workspace of `no_std` crates, each mapped to a named subsystem:

| Crate | Role |
|-------|------|
| `nerv::` | Kernel core — entry point, interrupt handling, panic handler |
| `magi::` | Memory — physical/virtual allocators named Melchior/Balthasar/Caspar |
| `seele::` | Scheduler — task and process management |
| `rei::` | Driver layer — hardware abstraction, device drivers |
| `unit00::` | GPU / VFIO passthrough — compute workload isolation |
| `puppet::` | Inference engine — LLM inference runtime |
| `ghost::` | Internal network stack — IPC over network primitives |
| `wired::` | External networking — internet access |
| `bebop::` | IPC / message bus |
| `section9::` | CLI |
| `lain::` | Telemetry / observability |
| `evangelion::` | UI / human interface |

### Boot flow

Limine bootloader → `nerv::` entry point (higher-half, kernel mapped at `0xffffffff80000000`) → `magi::` memory init → `rei::` driver init → `seele::` scheduler start → `puppet::` inference ready.

The framebuffer is provided by Limine at boot and handed to `evangelion::` / `lain::` early.

### Current state (Phase 1)

`kernel/src/main.rs` is the sole source file. It:
1. Declares Limine protocol requests in the `.requests` ELF section (start marker, end marker, base revision, stack size, framebuffer)
2. In `kernel_main()`: validates the Limine revision, retrieves the framebuffer, fills the screen with `#1a1a2e` using `write_volatile`, then halts with `hlt`
3. Defines a minimal panic handler that halts

### Custom target (`targets/x86_64-gehirn.json`)

Key settings that differ from standard targets:
- `"disable-redzone": true` — required for interrupt safety in kernel mode
- `"features": "-mmx,-sse,+soft-float"` — SSE disabled to avoid saving FPU state on every interrupt
- `"relocation-model": "static"` — no PIC; kernel is position-dependent
- `"code-model": "kernel"` — addresses fit in the upper 2 GB of the address space
- `"linker-flavor": "ld.lld"` + `"linker": "rust-lld"` — uses LLD, not system ld

### Linker script (`kernel/linker.ld`)

Places sections starting at `KERNEL_BASE = 0xffffffff80000000`. ELF segments: `.text` (R+X), `.rodata` + `.requests` (R), `.data` + `.bss` (R+W). Discards `.eh_frame` (unneeded because `panic = "abort"`). `KEEP()` on the `.requests*` sections is critical — without it, the linker strips them as dead code and Limine finds no boot requests.

### Limine protocol

Request structs are placed in the `.requests` ELF section with `#[unsafe(link_section = "...")]` and `#[used]`. Limine scans that section before calling `kernel_main`, fills in response pointers, then transfers control. The framebuffer pixel layout is **BGRX** (Blue, Green, Red, padding — not RGB).

### Key constraints

- `no_std` throughout — no Rust standard library
- Higher-half kernel: all kernel virtual addresses above `0xffffffff80000000`
- VFIO passthrough in `unit00::` requires IOMMU-enabled hardware for GPU isolation
- `Cargo.lock` is excluded from git (treated as a library crate)
