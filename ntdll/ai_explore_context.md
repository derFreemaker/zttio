meant to do a quick explore on how roughly the project could look like
everything in here is subject to change

# Context summary: Zig ntdll bindings library

## Goal

A Windows ntdll binding library for Zig 0.16 with a nicer API than translate-c or a plain port. It is grown on demand from your own project.

## Architecture

```
ntdll_raw -> hand-written externs + ABI types + info class enums (like std.os.windows)
     |          void* + length style, plain HANDLE, NTSTATUS as u32-backed enum
     |          functions ungated, structs use StructExtension via builtin only
     v
ntdll     -> flat namespace, same names as raw (shadows it), re-exports raw types if needed
                NtXxx(..., *len)         -> unmanaged, error union, no allocation
                NtXxxAlloc(config, ...)  -> managed, only where it removes boilerplate
                handle.close()           -> method form of NtClose (NtClose stays too)
                imports the options module (b.addOptions), raw does not
```

- **Layout**: one repo, two modules, underscore names (`ntdll_raw`, `ntdll`).
- **Target**: x64 first, ARM64 later on request.
- **Scope**: grows over time, starting with what your project needs.

## Error handling

- **Error sets**: each function gets a prefiltered set of realistic statuses, named after the NTSTATUS without the `STATUS_` prefix (for example `error.ACCESS_DENIED`).
- **Unlisted statuses**: they become `error.Unexpected`.
- **Last unexpected status**:
  - `getLastUnexpectedError()` returns the raw NTSTATUS, thread-local.
  - It exists only behind a build option, so no TLS variable exists when it is off.
  - It is written only when `error.Unexpected` is returned.
- **Logging**: unexpected statuses are logged like Zig std does it (`std_options`, debug builds).
- **Invented errors**: `error.BufferCapTooSmall` is the only one, plus `error.OutOfMemory` in managed functions.

## Buffers and the managed variants

- **Length**: unmanaged functions take a pointer that receives the length when Windows provides one.
- **Partial data**: unmanaged functions return the error, and the doc comment notes "partial data was written" where it applies.
- **AllocationConfig**: passed by value, `{ allocator, cap (optional) }`, with no default cap.
- **Growth**:
  - If Windows reports a length within the cap, resize to exactly that length.
  - Otherwise double.
  - A reported length above the cap returns `error.BufferCapTooSmall` immediately.
  - If doubling would pass the cap, clamp to the cap for one final attempt.
  - With no cap, the loop is uncapped, which is the caller's choice.
- **Fixed-size info classes**: the size is known at comptime, so no loop and no `Alloc` variant are needed for them.

## Version gating

- **Version source**: `builtin.target.os.version_range.windows`, using the **minimum only**.
- **Floor**: Windows 10 (1507). Nothing older is bound.
- **Rounding**: builds missing from Zig's version enum round up to the next known entry. This is documented in the README.
- **Range**: each item has `since` and an optional open-ended `until`.
- **Ungated items**: raw functions stay ungated, and the version is documented only.
- **Gated items**: gating in `ntdll` produces a `@compileError` that names the required version. For an `until`, it also names the removal version and link.
- **Unverified items**: they are available everywhere and marked `Version: unknown`. Lazy analysis means the risk only applies if they are used. The `dontAllowVersionUnknown` build option turns their use into a compile error.
- **Alloc variants**: they have no metadata of their own and inherit gating from the underlying function.
- **Versioned structs**:
  - `StructExtension(T, .{ .since, .until })` returns `T` in range, otherwise a zero-size type (`void` or `[0]u8`, whichever 0.16 accepts).
  - `MatchedStructExtension(T, range)` returns `T` in range, otherwise a byte array of `@sizeOf(T)` with matching alignment, so offsets stay stable.
- **Layout tests**: they exist only for structs that change between versions. Each Windows version gets its own test step in `build.zig`.

## Documentation convention

Every function, class, and field carries doc comments with:

- **Version line**: `Version: since <build> [until <build>] (link;...)` or `Version: unknown`.
- **Errors section**: each status is listed with a link to where it was found.
- **Sources**: referneces to Microsoft docs, phnt, ntdoc, ReactOS, Wine, and similar. No code is ever pasted (ReactOS is GPL, Wine is LGPL).
- **Related finds**: "found this too" comments for related functions that are not bound yet.
- **Trust level**: there are no evidence levels, because the reader judges trust from the reference.

## Build options (through `b.addOptions`)

- **Accessor**: enables `getLastUnexpectedError()`.
- **Unexpected logging**: controls the debug logging of unexpected statuses.
- **dontAllowUnverified**: turns use of unverified functions into a compile error.
- **Forwarding**: options pass through `b.dependency(...)`, and more can be added later.

## Checks to run on Zig 0.16 before the patterns spread

- Does `void` work as a field in an `extern struct`, or is `[0]u8` needed?
- Can a placeholder byte array carry alignment, or does it need a wrapper type?
- How granular is `std.Target.Os.WindowsVersion`, and which Windows 10 releases does it have?

## Philosophical Uncertainty

Open questions that are not decided yet:

- **Flag typing**: should share access, create disposition, and pipe type/mode be packed structs and enums in `ntdll_raw`, or plain integers there and typed only in `ntdll`?
- **Typed handles**: postponed until we reach those functions, including how they change signatures compared to online examples.
- **Fixed-size typed info classes**: postponed, including whether they return the struct by value.
