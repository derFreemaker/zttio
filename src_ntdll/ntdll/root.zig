const std = @import("std");

pub const raw = @import("ntdll_raw");

pub const HANDLE = raw.HANDLE;

pub const NTSTATUS = raw.NTSTATUS;

pub const UnexpectedError = error{
    /// The Operating System returned an undocumented error code.
    ///
    /// This error is in theory not possible, but it would be better
    /// to handle this error than to invoke undefined behavior.
    ///
    /// When this error code is observed, it usually means the Library needs a small patch
    /// to add the error code to the error set for the respective function.
    Unexpected,
};

threadlocal var lastUnexpectedStatus: NTSTATUS = .SUCCESS;

fn unexpectedStatus(status: NTSTATUS) UnexpectedError {
    // TODO: implement build option
    if (true) {
        std.debug.print("error.Unexpected NTSTATUS=0x{x} ({s})\n", .{
            @intFromEnum(status),
            std.enums.tagName(NTSTATUS, status) orelse "<unnamed>",
        });
        std.debug.dumpCurrentStackTrace(.{ .first_address = @returnAddress() });
    }
    // TODO: implement build option
    if (true) {
        lastUnexpectedStatus = status;
    }
    return error.Unexpected;
}

pub fn getLastUnexpectedStatus() NTSTATUS {
    return lastUnexpectedStatus;
}

// pub fn NtClose(handle: HANDLE) error{ Unexpected, InvalidHandle, HandleNotClosable }!void {
//     switch (raw.NtClose(handle)) {
//         .SUCCESS => {},
//         .INVALID_HANDLE => return error.InvalidHandle,
//         .HANDLE_NOT_CLOSABLE => return error.HandleNotClosable,
//         else => |status| return unexpectedStatus(status),
//     }
// }

// pub fn NtOpenFile(
//     io_status_block: *IO_STATUS_BLOCK,
//     access_mask: ACCESS_MASK,
//     obj_attr: *const OBJECT.ATTRIBUTES,
//     share: FILE.SHARE,
//     mode: FILE.MODE,
// ) error{Unexpected}!HANDLE {
//     var handle: HANDLE = undefined;
//     switch (raw.NtOpenFile(
//         &handle,
//         access_mask,
//         obj_attr,
//         io_status_block,
//         share,
//         mode,
//     )) {
//         .SUCCESS => {},
//         else => |status| return unexpectedStatus(status),
//     }
//     return handle;
// }

pub const Console = struct {
    pub const ScreenBufferInfo = raw.CONSOLE.SCREENBUFFERINFO_BODY;

    pub fn GetScreenBufferInfo(
        handle: HANDLE,
        screen_buffer_info: *ScreenBufferInfo,
    ) error{ InvalidHandle, Unexpected }!void {
        var msg: raw.CONSOLE.GetScreenBufferInfoMsg = .{};

        var user_io: raw.CON_DRV.USER_DEFINED_IO(1, 1) = .{};
        user_io.Buffers[0].is(&msg);
        user_io.Buffers[1].is(screen_buffer_info);

        var iosb: raw.IO_STATUS_BLOCK = undefined;
        switch (raw.NtDeviceIoControlFile(
            handle,
            null,
            null,
            null,
            &iosb,
            .CONDRV_ISSUE_USER_IO,
            &user_io,
            @sizeOf(@TypeOf(user_io)),
            null,
            0,
        )) {
            .SUCCESS => {},
            .INVALID_HANDLE => return error.InvalidHandle,
            else => |status| return unexpectedStatus(status),
        }
    }
};

test {
    @setEvalBranchQuota(1_000_000);
    refAllDeclsRecursive(@This());
}

/// Given a type, recursively references all the declarations inside,
/// so that the semantic analyzer sees them.
/// For deep types, you may use `@setEvalBranchQuota`.
fn refAllDeclsRecursive(comptime T: type) void {
    inline for (comptime std.meta.declarations(T)) |decl| {
        if (@TypeOf(@field(T, decl.name)) == type) {
            switch (@typeInfo(@field(T, decl.name))) {
                .@"struct",
                .@"enum",
                .@"union",
                .@"opaque",
                => refAllDeclsRecursive(@field(T, decl.name)),

                else => {},
            }
        }
        _ = &@field(T, decl.name);

        // @compileLog(decl, @field(T, decl.name), T);
    }
}
