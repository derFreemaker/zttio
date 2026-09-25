const std = @import("std");
const assert = std.debug.assert;

// ref: https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-dtyp/cca27429-5689-4a16-b2b4-9325d93e4ba2

pub fn P(comptime T: type) type {
    return *T;
}
pub const LP = P;

pub fn PC(comptime T: type) type {
    return *const T;
}

fn Bool(comptime BackingIntT: type) type {
    return enum(Backing) {
        /// false
        FALSE = 0,
        /// true
        _,

        /// This is not the only truthy value, comparisons against this value are always a bug.
        pub const TRUE: @This() = @enumFromInt(1);

        pub const Backing = BackingIntT;

        pub fn toBool(b: @This()) bool {
            return b != .FALSE;
        }

        pub fn fromBool(b: bool) @This() {
            return @enumFromInt(@intFromBool(b));
        }
    };
}

fn ANYSIZE_ARRAY(comptime T: type) type {
    _ = T;
    @compileError("convert to a generic/comptime type instead of using 'ANYSIZE_ARRAY'");
}

pub const VOID = anyopaque;

pub const BOOL = Bool(INT);
pub const BOOLEAN = Bool(BYTE);

pub const BYTE = u8;
pub const INT = c_int;
pub const UINT = c_uint;
// pub const UINT8 = u8;
// pub const UINT16 = u16;
// pub const UINT32 = u32;
// pub const UINT64 = u64;
pub const SHORT = i16;
pub const USHORT = u16;
pub const LONG = i32;
// pub const LONGLONG = i64;
// pub const LONG_PTR = usize;
// pub const LONG32 = i32;
// pub const LONG64 = i64;
pub const ULONG = u32;
pub const ULONG_PTR = usize;
// pub const ULONG32 = u32;
// pub const ULONG64 = u64;
pub const ULONGLONG = u64;

// pub const SIZE_T = ULONG_PTR;

pub const CHAR = u8;
// pub const UCHAR = u8;
pub const WCHAR = u16;
// pub const UNICODE = WCHAR;

pub const WORD = u16;
pub const DWORD = u32;
// pub const DWORD64 = u64;
// pub const DWORDLONG = ULONGLONG;
// pub const QWORD = u64;
pub const LARGE_INTEGER = i64;
// pub const ULARGE_INTEGER = u64;

// pub const FLOAT = f32;
// pub const DOUBLE = f64;

pub const HANDLE = P(VOID);
pub const HWND = HANDLE;

// pub const BSTR = [*:0]WCHAR;
// pub const LPCSTR = [*:0]CHAR;
// pub const LPCWSTR = [*]WCHAR;
// pub const LPSTR = [*]CHAR;
// pub const PSTR = LPSTR;
// pub const LPWSTR = [*]WCHAR;
// pub const PWSTR = LPWSTR;

// pub const LPARAM = LONG_PTR;

// pub const va_list = *opaque {};

fn STRING(comptime Char: type) type {
    return extern struct {
        Length: USHORT,
        MaximumLength: USHORT,
        Buffer: ?[*]Char,

        pub const empty: @This() = .{ .Length = 0, .MaximumLength = 0, .Buffer = null };

        pub fn init(string: []const Char) @This() {
            const len: USHORT = @intCast(@sizeOf(Char) * string.len);
            return .{
                .Length = len,
                .MaximumLength = len,
                .Buffer = @constCast(string.ptr),
            };
        }

        pub fn initZ(string: [:0]const Char) @This() {
            const len: USHORT = @intCast(@sizeOf(Char) * string.len);
            return .{
                .Length = len,
                .MaximumLength = len + @sizeOf(Char),
                .Buffer = @constCast(string.ptr),
            };
        }

        pub fn isEmpty(string: *const @This()) bool {
            return string.Length == 0;
        }

        pub fn slice(string: *const @This()) []Char {
            return if (string.isEmpty()) &.{} else string.Buffer.?[0..@divExact(string.Length, @sizeOf(Char))];
        }

        pub fn sliceZ(string: *const @This()) [:0]Char {
            assert(string.Length + @sizeOf(Char) <= string.MaximumLength);
            return string.Buffer.?[0..@divExact(string.Length, @sizeOf(Char)) :0];
        }
    };
}
pub const ANSI_STRING = STRING(CHAR);
pub const UNICODE_STRING = STRING(WCHAR);

pub const NTSTATUS = @import("ntstatus.zig").NTSTATUS;

/// - ref: https://learn.microsoft.com/en-us/windows/win32/fileio/maximum-file-path-limitation
pub const MAX_PATH = 260;

/// > The maximum path of 32,767 characters is approximate, because the "\\?\"
/// > prefix may be expanded to a longer string by the system at run time, and
/// > this expansion applies to the total length.
///
/// - ref: https://learn.microsoft.com/en-us/windows/win32/fileio/maximum-file-path-limitation
pub const PATH_MAX_WIDE = 32767;

/// - ref: um/wingdi.h
pub const LF_FACESIZE = 32;

/// - ref: um/wincontypes.h
pub const COORD = extern struct {
    X: SHORT,
    Y: SHORT,
};

/// - ref: shared/windef.h
pub const POINT = extern struct {
    x: LONG,
    y: LONG,
};

/// - ref: shared/windef.h
pub const RECT = extern struct {
    left: LONG,
    top: LONG,
    right: LONG,
    bottom: LONG,
};

/// - ref: um/wincontypes.h
pub const SMALL_RECT = extern struct {
    Left: SHORT,
    Top: SHORT,
    Right: SHORT,
    Bottom: SHORT,
};

/// - ref: shared/windef.h
/// - ref: https://learn.microsoft.com/en-us/windows/win32/gdi/colorref
pub const COLORREF = packed struct(DWORD) {
    Red: u8 = 0,
    Green: u8 = 0,
    Blue: u8 = 0,
    /// have to be always zero
    Unused: u8 = 0,
};

/// - ref: shared/ntdef.h
pub const LANGID = enum(USHORT) {
    // @TODO: fill
    //     see: https://winprotocoldoc.z19.web.core.windows.net/MS-LCID/[MS-LCID].pdf
    _,
};

/// - ref: um/wincontypes.h
pub const CHAR_INFO = extern struct {
    Char: extern union {
        UnicodeChar: WCHAR,
        AsciiChar: CHAR,
    },
    Attributes: TEXT_ATTRIBUTES,
};

/// - ref: um/consoleapi2.h
pub const TEXT_ATTRIBUTES = packed struct(USHORT) {
    /// text color contains blue.
    FOREGROUND_BLUE: bool = false,
    /// text color contains green.
    FOREGROUND_GREEN: bool = false,
    /// text color contains red.
    FOREGROUND_RED: bool = false,
    /// text color is intensified.
    FOREGROUND_INTENSITY: bool = false,

    /// background color contains blue.
    BACKGROUND_BLUE: bool = false,
    /// background color contains green.
    BACKGROUND_GREEN: bool = false,
    /// background color contains red.
    BACKGROUND_RED: bool = false,
    /// background color is intensified.
    BACKGROUND_INTENSIFIED: bool = false,

    /// Leading Byte of DBCS
    LVB_LEADING_BYTE: bool = false,
    /// Trailing Byte of DBCS
    LVB_TRAILING_BYTE: bool = false,

    Unused9: u1 = 0,

    LVB_GRID_HORIZONTAL: bool = false,
    LVB_GRID_LVERTICAL: bool = false,
    LVB_GRID_RVERTICAL: bool = false,

    /// Reverse fore/back ground attribute.
    LVB_REVERSE_VIDEO: bool = false,
    LVB_UNDERSCORE: bool = false,
};

/// - ref: um/winternl.h
/// - ref: https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/wdm/ns-wdm-_io_status_block
pub const IO_STATUS_BLOCK = extern struct {
    // "DUMMYUNIONNAME" expands to "u"
    u: extern union {
        /// This is the completion status, either STATUS_SUCCESS if the requested operation was
        /// completed successfully or an informational, warning, or error value.
        Status: NTSTATUS,
        /// Reserved. For internal use only.
        Pointer: P(VOID),
    },
    /// This is set to a request-dependent value. For example, on successful completion of a
    /// transfer request, this is set to the number of bytes transferred.
    /// If a transfer request is completed with another `NTSTATUS`, this member is set to zero.
    Information: ULONG_PTR,
};

/// - ref: km/wdm.h
pub const IO_APC_ROUTINE = fn (
    IN_ApcContext: ?P(VOID),
    IN_IoStatusBlock: ?P(IO_STATUS_BLOCK),
    IN_Reserved: ULONG,
) callconv(.winapi) void;

/// - ref: km/ntddk.h 'CTL_CODE'
pub const IO_CONTROL_CODE = packed struct(ULONG) {
    METHOD: Method,
    FUNCTION: u12,
    ACCESS: Access,
    DEVICE_TYPE: DeviceType,

    /// - ref: km/ntddk.h
    pub const Method = enum(u2) {
        BUFFERED = 0,
        IN_DIRECT = 1,
        OUT_DIRECT = 2,
        NEITHER = 3,
    };

    /// - ref: km/ntddk.h
    pub const Access = enum(u2) {
        pub const SPECIAL: Access = .ANY;

        ANY = 0,
        READ = 1,
        WRITE = 2,
    };

    /// 0000 - 07ff reserved for Microsoft Corporation
    /// 07ff - 0fff reserved for customers
    /// - ref: km/ntddk.h
    pub const DeviceType = enum(u16) {
        BEEP = 0x0001,
        CD_ROM = 0x0002,
        CD_ROM_FILE_SYSTEM = 0x0003,
        CONTROLLER = 0x0004,
        DATALINK = 0x0005,
        DFS = 0x0006,
        DISK = 0x0007,
        DISK_FILE_SYSTEM = 0x0008,
        FILE_SYSTEM = 0x0009,
        INPORT_PORT = 0x000a,
        KEYBOARD = 0x000b,
        MAILSLOT = 0x000c,
        MIDI_IN = 0x000d,
        MIDI_OUT = 0x000e,
        MOUSE = 0x000f,
        MULTI_UNC_PROVIDER = 0x0010,
        NAMED_PIPE = 0x0011,
        NETWORK = 0x0012,
        NETWORK_BROWSER = 0x0013,
        NETWORK_FILE_SYSTEM = 0x0014,
        NULL = 0x0015,
        PARALLEL_PORT = 0x0016,
        PHYSICAL_NETCARD = 0x0017,
        PRINTER = 0x0018,
        SCANNER = 0x0019,
        SERIAL_MOUSE_PORT = 0x001a,
        SERIAL_PORT = 0x001b,
        SCREEN = 0x001c,
        SOUND = 0x001d,
        STREAMS = 0x001e,
        TAPE = 0x001f,
        TAPE_FILE_SYSTEM = 0x0020,
        TRANSPORT = 0x0021,
        UNKNOWN = 0x0022,
        VIDEO = 0x0023,
        VIRTUAL_DISK = 0x0024,
        WAVE_IN = 0x0025,
        WAVE_OUT = 0x0026,
        @"8042_PORT" = 0x0027,
        NETWORK_REDIRECTOR = 0x0028,
        BATTERY = 0x0029,
        BUS_EXTENDER = 0x002a,
        MODEM = 0x002b,
        VDM = 0x002c,
        MASS_STORAGE = 0x002d,
        SMB = 0x002e,
        KS = 0x002f,
        CHANGER = 0x0030,
        SMARTCARD = 0x0031,
        ACPI = 0x0032,
        DVD = 0x0033,
        FULLSCREEN_VIDEO = 0x0034,
        DFS_FILE_SYSTEM = 0x0035,
        DFS_VOLUME = 0x0036,
        SERENUM = 0x0037,
        TERMSRV = 0x0038,
        KSEC = 0x0039,
        FIPS = 0x003a,
        INFINIBAND = 0x003b,
        // 0x003c,
        // 0x003d,
        VMBUS = 0x003e,
        CRYPT_PROVIDER = 0x003f,
        WPD = 0x0040,
        BLUETOOTH = 0x0041,
        MT_COMPOSITE = 0x0042,
        MT_TRANSPORT = 0x0043,
        BIOMETRIC = 0x0044,
        PMI = 0x0045,
        EHSTOR = 0x0046,
        DEVAPI = 0x0047,
        GPIO = 0x0048,
        USBEX = 0x0049,
        CONSOLE = 0x0050,
        NFP = 0x0051,
        SYSENV = 0x0052,
        VIRTUAL_BLOCK = 0x0053,
        POINT_OF_SERVICE = 0x0054,
        STORAGE_REPLICATION = 0x0055,
        TRUST_ENV = 0x0056,
        UCM = 0x0057,
        UCMTCPCI = 0x0058,
        PERSISTENT_MEMORY = 0x0059,
        NVDIMM = 0x005a,
        HOLOGRAPHIC = 0x005b,
        SDFXHCI = 0x005c,
        UCMUCSI = 0x005d,
        PRM = 0x005e,
        EVENT_COLLECTOR = 0x005f,
        USB4 = 0x0060,
        SOUNDWIRE = 0x0061,
        FABRIC_NVME = 0x0062,
        SVM = 0x0063,
        HARDWARE_ACCELERATOR = 0x0064,
        I3C = 0x0065,
        MULTITIER_MEMORY = 0x0066,
        CXL_TYPE3 = 0x0067,

        // @TODO: check if it is a FSCTL or IOCTL code
        // /// - ref: km/d4drvif.h
        // DOT4 = 0x003a,

        _,
    };

    // // battery control codes

    // /// This IOCTL is for internal use only.
    // /// - ref: km/charging.h
    // /// - ref: https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/_battery/
    // pub const CAD_DISABLE_CHARGING = IO_CONTROL_CODE{
    //     .METHOD = .BUFFERED,
    //     .FUNCTION = 0x0120,
    //     .ACCESS = .NEITHER,
    //     .DEVICE_TYPE = .BATTERY,
    // };

    // /// Microsoft reserves the IOCTL_CAD_GET_CHARGING_STATUS_COMPLETE system call for internal use only.
    // /// Don't use this system call in your code.
    // /// - ref: km/charging.h
    // /// - ref: https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/_battery/
    // pub const CAD_GET_CHARGING_STATUS_COMPLETE = IO_CONTROL_CODE{
    //     .METHOD = .BUFFERED,
    //     .FUNCTION = 0x0122,
    //     .ACCESS = .NEITHER,
    //     .DEVICE_TYPE = .BATTERY,
    // };

    // console control codes
    // ref: https://github.com/microsoft/terminal/dep/Console/condrv.h

    pub const CONDRV_READ_IO: IO_CONTROL_CODE = .{
        .METHOD = .OUT_DIRECT,
        .FUNCTION = 1,
        .ACCESS = .ANY,
        .DEVICE_TYPE = .CONSOLE,
    };

    pub const CONDRV_COMPLETE_IO: IO_CONTROL_CODE = .{
        .METHOD = .NEITHER,
        .FUNCTION = 2,
        .ACCESS = .ANY,
        .DEVICE_TYPE = .CONSOLE,
    };

    pub const CONDRV_READ_INPUT: IO_CONTROL_CODE = .{
        .METHOD = .NEITHER,
        .FUNCTION = 3,
        .ACCESS = .ANY,
        .DEVICE_TYPE = .CONSOLE,
    };

    pub const CONDRV_WRITE_OUTPUT: IO_CONTROL_CODE = .{
        .METHOD = .NEITHER,
        .FUNCTION = 4,
        .ACCESS = .ANY,
        .DEVICE_TYPE = .CONSOLE,
    };

    pub const CONDRV_ISSUE_USER_IO: IO_CONTROL_CODE = .{
        .METHOD = .OUT_DIRECT,
        .FUNCTION = 5,
        .ACCESS = .ANY,
        .DEVICE_TYPE = .CONSOLE,
    };

    pub const CONDRV_DISCONNECT_PIPE: IO_CONTROL_CODE = .{
        .METHOD = .NEITHER,
        .FUNCTION = 6,
        .ACCESS = .ANY,
        .DEVICE_TYPE = .CONSOLE,
    };

    pub const CONDRV_SET_SERVER_INFORMATION: IO_CONTROL_CODE = .{
        .METHOD = .NEITHER,
        .FUNCTION = 7,
        .ACCESS = .ANY,
        .DEVICE_TYPE = .CONSOLE,
    };

    pub const CONDRV_GET_SERVER_PID: IO_CONTROL_CODE = .{
        .METHOD = .NEITHER,
        .FUNCTION = 8,
        .ACCESS = .ANY,
        .DEVICE_TYPE = .CONSOLE,
    };

    pub const CONDRV_GET_DISPLAY_SIZE: IO_CONTROL_CODE = .{
        .METHOD = .NEITHER,
        .FUNCTION = 9,
        .ACCESS = .ANY,
        .DEVICE_TYPE = .CONSOLE,
    };

    pub const CONDRV_UPDATE_DISPLAY: IO_CONTROL_CODE = .{
        .METHOD = .NEITHER,
        .FUNCTION = 10,
        .ACCESS = .ANY,
        .DEVICE_TYPE = .CONSOLE,
    };

    pub const CONDRV_SET_CURSOR: IO_CONTROL_CODE = .{
        .METHOD = .NEITHER,
        .FUNCTION = 11,
        .ACCESS = .ANY,
        .DEVICE_TYPE = .CONSOLE,
    };

    pub const CONDRV_ALLOW_VIA_UIACCESS: IO_CONTROL_CODE = .{
        .METHOD = .NEITHER,
        .FUNCTION = 12,
        .ACCESS = .ANY,
        .DEVICE_TYPE = .CONSOLE,
    };

    pub const CONDRV_LAUNCH_SERVER: IO_CONTROL_CODE = .{
        .METHOD = .NEITHER,
        .FUNCTION = 13,
        .ACCESS = .ANY,
        .DEVICE_TYPE = .CONSOLE,
    };

    pub const CONDRV_GET_FONT_SIZE: IO_CONTROL_CODE = .{
        .METHOD = .NEITHER,
        .FUNCTION = 14,
        .ACCESS = .ANY,
        .DEVICE_TYPE = .CONSOLE,
    };
};

/// - ref: km/ntifs.h
/// - ref: https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/ntifs/ns-ntifs-_sid_identifier_authority
pub const SID = extern struct {
    pub const MAX_SUB_AUTHORITIES = 15;
    pub const RECOMMENDED_SUB_AUTHORITIES = 1;

    /// The revision level assigned to the SID.
    Revision: BYTE = 1, // > current revision level
    SubAuthorityCount: BYTE,
    IdentifierAuthority: IDENTIFIER_AUTHORITY, // > Will change to around 6 in a future release.
    // TODO: check what type this really is
    SubAuthority: [*]ULONG,

    // TODO: check what type this really is
    pub const IDENTIFIER_AUTHORITY = extern struct {
        Value: [6]BYTE,
    };

    pub const NULL_AUTHORITY: IDENTIFIER_AUTHORITY = .{ .Value = .{ 0, 0, 0, 0, 0, 0 } };
    pub const WORLD_AUTHORITY: IDENTIFIER_AUTHORITY = .{ .Value = .{ 0, 0, 0, 0, 0, 1 } };
    pub const LOCAL_AUTHORITY: IDENTIFIER_AUTHORITY = .{ .Value = .{ 0, 0, 0, 0, 0, 2 } };
    pub const CREATOR_AUTHORITY: IDENTIFIER_AUTHORITY = .{ .Value = .{ 0, 0, 0, 0, 0, 3 } };
    pub const NON_UNIQUE_AUTHORITY: IDENTIFIER_AUTHORITY = .{ .Value = .{ 0, 0, 0, 0, 0, 4 } };
    pub const NT_AUTHORITY: IDENTIFIER_AUTHORITY = .{ .Value = .{ 0, 0, 0, 0, 0, 5 } };
    pub const RESOURCE_MANAGER_AUTHORITY: IDENTIFIER_AUTHORITY = .{ .Value = .{ 0, 0, 0, 0, 0, 9 } };
};

/// - ref: um/winnt.h
/// - ref: https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/wdm/ns-wdm-_acl
pub const ACL = extern struct {
    /// Revision level of the ACL.
    AclRevision: BYTE,
    /// A zero byte of padding that aligns the AclRevision member on a 16-bit boundary.
    Sbz1: BYTE = 0,
    /// Size, in bytes, of the ACL. This value includes both the ACL structure and all the ACEs.
    AclSize: WORD,
    /// Number of ACEs stored in the ACL.
    AceCount: WORD,
    /// Two zero bytes of padding that align the ACL structure on a 32-bit boundary.
    Sbz2: WORD = 0,
};

/// - ref: https://learn.microsoft.com/en-us/windows-hardware/drivers/ifs/access-mask
/// - ref: km/wdm.h
pub const ACCESS_MASK = packed struct(DWORD) {
    SPECIFIC: Specific = .{ .bits = 0 },
    STANDARD: Standard = .{},
    Reserved21: u3 = 0,
    ACCESS_SYSTEM_SECURITY: bool = false,
    MAXIMUM_ALLOWED: bool = false,
    Reserved26: u2 = 0,
    GENERIC: Generic = .{},

    pub const Specific = packed union {
        bits: u16,

        /// Define access rights to files and directories
        FILE: File,
        FILE_DIRECTORY: File.Directory,
        FILE_PIPE: File.Pipe,
        // /// Registry Specific Access Rights.
        // KEY: Key,
        // /// Object Manager Object Type Specific Access Rights.
        // OBJECT_TYPE: ObjectType,
        // /// Object Manager Directory Specific Access Rights.
        // DIRECTORY: Directory,
        // /// Object Manager Symbolic Link Specific Access Rights.
        // SYMBOLIC_LINK: SymbolicLink,
        // /// Section Access Rights.
        // SECTION: Section,
        // /// Session Specific Access Rights.
        // SESSION: Session,
        // /// Process Specific Access Rights.
        // PROCESS: Process,
        // /// Thread Specific Access Rights.
        // THREAD: Thread,
        // /// Partition Specific Access Rights.
        // MEMORY_PARTITION: MemoryPartition,
        // /// Generic mappings for transaction manager rights.
        // TRANSACTIONMANAGER: TransactionManager,
        // /// Generic mappings for transaction rights.
        // TRANSACTION: Transaction,
        // /// Generic mappings for resource manager rights.
        // RESOURCEMANAGER: ResourceManager,
        // /// Generic mappings for enlistment rights.
        // ENLISTMENT: Enlistment,
        // /// Event Specific Access Rights.
        // EVENT: Event,
        // /// Semaphore Specific Access Rights.
        // SEMAPHORE: Semaphore,

        // // ref: km/ntifs.h

        // /// Token Specific Access Rights.
        // TOKEN: Token,

        // // ref: um/winnt.h

        // /// Job Object Specific Access Rights.
        // JOB_OBJECT: JobObject,
        // /// Mutant Specific Access Rights.
        // MUTANT: Mutant,
        // /// Timer Specific Access Rights.
        // TIMER: Timer,
        // /// I/O Completion Specific Access Rights.
        // IO_COMPLETION: IoCompletion,

        /// - ref: km/wdm.h
        pub const File = packed struct(u16) {
            READ_DATA: bool = false,
            WRITE_DATA: bool = false,
            APPEND_DATA: bool = false,
            READ_EA: bool = false,
            WRITE_EA: bool = false,
            EXECUTE: bool = false,
            Reserved6: u1 = 0,
            READ_ATTRIBUTES: bool = false,
            WRITE_ATTRIBUTES: bool = false,
            Reserved9: u7 = 0,

            pub const ALL_ACCESS: ACCESS_MASK = .{
                .STANDARD = .{
                    .RIGHTS = .REQUIRED,
                    .SYNCHRONIZE = true,
                },
                .SPECIFIC = .{ .FILE = .{
                    .READ_DATA = true,
                    .WRITE_DATA = true,
                    .APPEND_DATA = true,
                    .READ_EA = true,
                    .WRITE_EA = true,
                    .EXECUTE = true,
                    .Reserved6 = std.math.maxInt(@FieldType(File, "Reserved6")),
                    .READ_ATTRIBUTES = true,
                    .WRITE_ATTRIBUTES = true,
                } },
            };

            pub const GENERIC_READ: ACCESS_MASK = .{
                .STANDARD = .{
                    .RIGHTS = .READ,
                    .SYNCHRONIZE = true,
                },
                .SPECIFIC = .{ .FILE = .{
                    .READ_DATA = true,
                    .READ_ATTRIBUTES = true,
                    .READ_EA = true,
                } },
            };

            pub const GENERIC_WRITE: ACCESS_MASK = .{
                .STANDARD = .{
                    .RIGHTS = .WRITE,
                    .SYNCHRONIZE = true,
                },
                .SPECIFIC = .{ .FILE = .{
                    .WRITE_DATA = true,
                    .WRITE_ATTRIBUTES = true,
                    .WRITE_EA = true,
                    .APPEND_DATA = true,
                } },
            };

            pub const GENERIC_EXECUTE: ACCESS_MASK = .{
                .STANDARD = .{
                    .RIGHTS = .EXECUTE,
                    .SYNCHRONIZE = true,
                },
                .SPECIFIC = .{ .FILE = .{
                    .READ_ATTRIBUTES = true,
                    .EXECUTE = true,
                } },
            };

            /// - ref: km/wdm.h
            pub const Directory = packed struct(u16) {
                LIST: bool = false,
                ADD_FILE: bool = false,
                ADD_SUBDIRECTORY: bool = false,
                READ_EA: bool = false,
                WRITE_EA: bool = false,
                TRAVERSE: bool = false,
                DELETE_CHILD: bool = false,
                READ_ATTRIBUTES: bool = false,
                WRITE_ATTRIBUTES: bool = false,
                Reserved9: u7 = 0,
            };

            /// - ref: km/wdm.h
            pub const Pipe = packed struct(u16) {
                READ_DATA: bool = false,
                WRITE_DATA: bool = false,
                /// for named pipes
                CREATE_PIPE_INSTANCE: bool = false,
                Reserved3: u4 = 0,
                READ_ATTRIBUTES: bool = false,
                WRITE_ATTRIBUTES: bool = false,
                Reserved9: u7 = 0,
            };
        };

        // pub const Key = packed struct(u16) {
        //     /// Required to query the values of a registry key.
        //     QUERY_VALUE: bool = false,
        //     /// Required to create, delete, or set a registry value.
        //     SET_VALUE: bool = false,
        //     /// Required to create a subkey of a registry key.
        //     CREATE_SUB_KEY: bool = false,
        //     /// Required to enumerate the subkeys of a registry key.
        //     ENUMERATE_SUB_KEYS: bool = false,
        //     /// Required to request change notifications for a registry key or for subkeys of a registry key.
        //     NOTIFY: bool = false,
        //     /// Reserved for system use.
        //     CREATE_LINK: bool = false,
        //     Reserved6: u2 = 0,
        //     /// Indicates that an application on 64-bit Windows should operate on the 64-bit registry view.
        //     /// This flag is ignored by 32-bit Windows.
        //     WOW64_64KEY: bool = false,
        //     /// Indicates that an application on 64-bit Windows should operate on the 32-bit registry view.
        //     /// This flag is ignored by 32-bit Windows.
        //     WOW64_32KEY: bool = false,
        //     Reserved10: u6 = 0,

        //     pub const WOW64_RES: ACCESS_MASK = .{
        //         .SPECIFIC = .{ .KEY = .{
        //             .WOW64_32KEY = true,
        //             .WOW64_64KEY = true,
        //         } },
        //     };

        //     /// Combines the STANDARD_RIGHTS_READ, KEY_QUERY_VALUE, KEY_ENUMERATE_SUB_KEYS, and KEY_NOTIFY values.
        //     pub const READ: ACCESS_MASK = .{
        //         .STANDARD = .{
        //             .RIGHTS = .READ,
        //             .SYNCHRONIZE = false,
        //         },
        //         .SPECIFIC = .{ .KEY = .{
        //             .QUERY_VALUE = true,
        //             .ENUMERATE_SUB_KEYS = true,
        //             .NOTIFY = true,
        //         } },
        //     };

        //     /// Combines the STANDARD_RIGHTS_WRITE, KEY_SET_VALUE, and KEY_CREATE_SUB_KEY access rights.
        //     pub const WRITE: ACCESS_MASK = .{
        //         .STANDARD = .{
        //             .RIGHTS = .WRITE,
        //             .SYNCHRONIZE = false,
        //         },
        //         .SPECIFIC = .{ .KEY = .{
        //             .SET_VALUE = true,
        //             .CREATE_SUB_KEY = true,
        //         } },
        //     };

        //     /// Equivalent to KEY_READ.
        //     pub const EXECUTE = READ;

        //     pub const ALL_ACCESS: ACCESS_MASK = .{
        //         .STANDARD = .{
        //             .RIGHTS = .ALL,
        //             .SYNCHRONIZE = false,
        //         },
        //         .SPECIFIC = .{ .KEY = .{
        //             .QUERY_VALUE = true,
        //             .SET_VALUE = true,
        //             .CREATE_SUB_KEY = true,
        //             .ENUMERATE_SUB_KEYS = true,
        //             .NOTIFY = true,
        //             .CREATE_LINK = true,
        //         } },
        //     };
        // };

        // pub const ObjectType = packed struct(u16) {
        //     CREATE: bool = false,
        //     Reserved1: u15 = 0,

        //     pub const ALL_ACCESS: ACCESS_MASK = .{
        //         .STANDARD = .{ .RIGHTS = .REQUIRED },
        //         .SPECIFIC = .{ .OBJECT_TYPE = .{
        //             .CREATE = true,
        //         } },
        //     };
        // };

        // pub const Directory = packed struct(u16) {
        //     QUERY: bool = false,
        //     TRAVERSE: bool = false,
        //     CREATE_OBJECT: bool = false,
        //     CREATE_SUBDIRECTORY: bool = false,
        //     Reserved3: u12 = 0,

        //     pub const ALL_ACCESS: ACCESS_MASK = .{
        //         .STANDARD = .{ .RIGHTS = .REQUIRED },
        //         .SPECIFIC = .{ .DIRECTORY = .{
        //             .QUERY = true,
        //             .TRAVERSE = true,
        //             .CREATE_OBJECT = true,
        //             .CREATE_SUBDIRECTORY = true,
        //         } },
        //     };
        // };

        // pub const SymbolicLink = packed struct(u16) {
        //     QUERY: bool = false,
        //     SET: bool = false,
        //     Reserved2: u14 = 0,

        //     pub const ALL_ACCESS: ACCESS_MASK = .{
        //         .STANDARD = .{ .RIGHTS = .REQUIRED },
        //         .SPECIFIC = .{ .SYMBOLIC_LINK = .{
        //             .QUERY = true,
        //         } },
        //     };

        //     pub const ALL_ACCESS_EX: ACCESS_MASK = .{
        //         .STANDARD = .{ .RIGHTS = .REQUIRED },
        //         .SPECIFIC = .{ .SYMBOLIC_LINK = .{
        //             .QUERY = true,
        //             .SET = true,
        //             .Reserved2 = std.math.maxInt(@FieldType(SymbolicLink, "Reserved2")),
        //         } },
        //     };
        // };

        // pub const Section = packed struct(u16) {
        //     QUERY: bool = false,
        //     MAP_WRITE: bool = false,
        //     MAP_READ: bool = false,
        //     MAP_EXECUTE: bool = false,
        //     EXTEND_SIZE: bool = false,
        //     /// not included in `ALL_ACCESS`
        //     MAP_EXECUTE_EXPLICIT: bool = false,
        //     Reserved6: u10 = 0,

        //     pub const ALL_ACCESS: ACCESS_MASK = .{
        //         .STANDARD = .{ .RIGHTS = .REQUIRED },
        //         .SPECIFIC = .{ .SECTION = .{
        //             .QUERY = true,
        //             .MAP_WRITE = true,
        //             .MAP_READ = true,
        //             .MAP_EXECUTE = true,
        //             .EXTEND_SIZE = true,
        //         } },
        //     };
        // };

        // pub const Session = packed struct(u16) {
        //     QUERY_ACCESS: bool = false,
        //     MODIFY_ACCESS: bool = false,
        //     Reserved2: u14 = 0,

        //     pub const ALL_ACCESS: ACCESS_MASK = .{
        //         .STANDARD = .{ .RIGHTS = .REQUIRED },
        //         .SPECIFIC = .{ .SESSION = .{
        //             .QUERY_ACCESS = true,
        //             .MODIFY_ACCESS = true,
        //         } },
        //     };
        // };

        // pub const Process = packed struct(u16) {
        //     TERMINATE: bool = false,
        //     CREATE_THREAD: bool = false,
        //     SET_SESSIONID: bool = false,
        //     VM_OPERATION: bool = false,
        //     VM_READ: bool = false,
        //     VM_WRITE: bool = false,
        //     DUP_HANDLE: bool = false,
        //     CREATE_PROCESS: bool = false,
        //     SET_QUOTA: bool = false,
        //     SET_INFORMATION: bool = false,
        //     QUERY_INFORMATION: bool = false,
        //     SUSPEND_RESUME: bool = false,
        //     QUERY_LIMITED_INFORMATION: bool = false,
        //     SET_LIMITED_INFORMATION: bool = false,
        //     Reserved14: u2 = 0,

        //     pub const ALL_ACCESS: ACCESS_MASK = .{
        //         .STANDARD = .{
        //             .RIGHTS = .REQUIRED,
        //             .SYNCHRONIZE = true,
        //         },
        //         .SPECIFIC = .{ .PROCESS = .{
        //             .TERMINATE = true,
        //             .CREATE_THREAD = true,
        //             .SET_SESSIONID = true,
        //             .VM_OPERATION = true,
        //             .VM_READ = true,
        //             .VM_WRITE = true,
        //             .DUP_HANDLE = true,
        //             .CREATE_PROCESS = true,
        //             .SET_QUOTA = true,
        //             .SET_INFORMATION = true,
        //             .QUERY_INFORMATION = true,
        //             .SUSPEND_RESUME = true,
        //             .QUERY_LIMITED_INFORMATION = true,
        //             .SET_LIMITED_INFORMATION = true,
        //             .Reserved14 = std.math.maxInt(@FieldType(Process, "Reserved14")),
        //         } },
        //     };
        // };

        // pub const Thread = packed struct(u16) {
        //     TERMINATE: bool = false,
        //     SUSPEND_RESUME: bool = false,
        //     ALERT: bool = false,
        //     GET_CONTEXT: bool = false,
        //     SET_CONTEXT: bool = false,
        //     SET_INFORMATION: bool = false,
        //     QUERY_INFORMATION: bool = false,
        //     SET_THREAD_TOKEN: bool = false,
        //     IMPERSONATE: bool = false,
        //     DIRECT_IMPERSONATION: bool = false,
        //     SET_LIMITED_INFORMATION: bool = false,
        //     QUERY_LIMITED_INFORMATION: bool = false,
        //     RESUME: bool = false,
        //     Reserved13: u3 = 0,

        //     pub const ALL_ACCESS: ACCESS_MASK = .{
        //         .STANDARD = .{
        //             .RIGHTS = .REQUIRED,
        //             .SYNCHRONIZE = true,
        //         },
        //         .SPECIFIC = .{ .THREAD = .{
        //             .TERMINATE = true,
        //             .SUSPEND_RESUME = true,
        //             .ALERT = true,
        //             .GET_CONTEXT = true,
        //             .SET_CONTEXT = true,
        //             .SET_INFORMATION = true,
        //             .QUERY_INFORMATION = true,
        //             .SET_THREAD_TOKEN = true,
        //             .IMPERSONATE = true,
        //             .DIRECT_IMPERSONATION = true,
        //             .SET_LIMITED_INFORMATION = true,
        //             .QUERY_LIMITED_INFORMATION = true,
        //             .RESUME = true,
        //             .Reserved13 = std.math.maxInt(@FieldType(Thread, "Reserved13")),
        //         } },
        //     };
        // };

        // pub const MemoryPartition = packed struct(u16) {
        //     QUERY_ACCESS: bool = false,
        //     MODIFY_ACCESS: bool = false,
        //     Required2: u14 = 0,

        //     pub const ALL_ACCESS: ACCESS_MASK = .{
        //         .STANDARD = .{
        //             .RIGHTS = .REQUIRED,
        //             .SYNCHRONIZE = true,
        //         },
        //         .SPECIFIC = .{ .MEMORY_PARTITION = .{
        //             .QUERY_ACCESS = true,
        //             .MODIFY_ACCESS = true,
        //         } },
        //     };
        // };

        // pub const TransactionManager = packed struct(u16) {
        //     QUERY_INFORMATION: bool = false,
        //     SET_INFORMATION: bool = false,
        //     RECOVER: bool = false,
        //     RENAME: bool = false,
        //     CREATE_RM: bool = false,
        //     /// The following right is intended for DTC's use only; it will be deprecated, and no one else should take a dependency on it.
        //     BIND_TRANSACTION: bool = false,
        //     Reserved6: u10 = 0,

        //     pub const GENERIC_READ: ACCESS_MASK = .{
        //         .STANDARD = .{ .RIGHTS = .READ },
        //         .SPECIFIC = .{ .TRANSACTIONMANAGER = .{
        //             .QUERY_INFORMATION = true,
        //         } },
        //     };

        //     pub const GENERIC_WRITE: ACCESS_MASK = .{
        //         .STANDARD = .{ .RIGHTS = .WRITE },
        //         .SPECIFIC = .{ .TRANSACTIONMANAGER = .{
        //             .SET_INFORMATION = true,
        //             .RECOVER = true,
        //             .RENAME = true,
        //             .CREATE_RM = true,
        //         } },
        //     };

        //     pub const GENERIC_EXECUTE: ACCESS_MASK = .{
        //         .STANDARD = .{ .RIGHTS = .EXECUTE },
        //         .SPECIFIC = .{ .TRANSACTIONMANAGER = .{} },
        //     };

        //     pub const ALL_ACCESS: ACCESS_MASK = .{
        //         .STANDARD = .{ .RIGHTS = .REQUIRED },
        //         .SPECIFIC = .{ .TRANSACTIONMANAGER = .{
        //             .QUERY_INFORMATION = true,
        //             .SET_INFORMATION = true,
        //             .RECOVER = true,
        //             .RENAME = true,
        //             .CREATE_RM = true,
        //             .BIND_TRANSACTION = true,
        //         } },
        //     };
        // };

        // pub const Transaction = packed struct(u16) {
        //     QUERY_INFORMATION: bool = false,
        //     SET_INFORMATION: bool = false,
        //     ENLIST: bool = false,
        //     COMMIT: bool = false,
        //     ROLLBACK: bool = false,
        //     PROPAGATE: bool = false,
        //     RIGHT_RESERVED1: bool = false,
        //     Reserved7: u9 = 0,

        //     pub const GENERIC_READ: ACCESS_MASK = .{
        //         .STANDARD = .{
        //             .RIGHTS = .READ,
        //             .SYNCHRONIZE = true,
        //         },
        //         .SPECIFIC = .{ .TRANSACTION = .{
        //             .QUERY_INFORMATION = true,
        //         } },
        //     };

        //     pub const GENERIC_WRITE: ACCESS_MASK = .{
        //         .STANDARD = .{
        //             .RIGHTS = .WRITE,
        //             .SYNCHRONIZE = true,
        //         },
        //         .SPECIFIC = .{ .TRANSACTION = .{
        //             .SET_INFORMATION = true,
        //             .COMMIT = true,
        //             .ENLIST = true,
        //             .ROLLBACK = true,
        //             .PROPAGATE = true,
        //         } },
        //     };

        //     pub const GENERIC_EXECUTE: ACCESS_MASK = .{
        //         .STANDARD = .{
        //             .RIGHTS = .EXECUTE,
        //             .SYNCHRONIZE = true,
        //         },
        //         .SPECIFIC = .{ .TRANSACTION = .{
        //             .COMMIT = true,
        //             .ROLLBACK = true,
        //         } },
        //     };

        //     pub const ALL_ACCESS: ACCESS_MASK = .{
        //         .STANDARD = .{
        //             .RIGHTS = .REQUIRED,
        //             .SYNCHRONIZE = true,
        //         },
        //         .SPECIFIC = .{ .TRANSACTION = .{
        //             .QUERY_INFORMATION = true,
        //             .SET_INFORMATION = true,
        //             .COMMIT = true,
        //             .ENLIST = true,
        //             .ROLLBACK = true,
        //             .PROPAGATE = true,
        //         } },
        //     };

        //     pub const RESOURCE_MANAGER_RIGHTS: ACCESS_MASK = .{
        //         .STANDARD = .{
        //             .RIGHTS = .{
        //                 .READ_CONTROL = true,
        //             },
        //             .SYNCHRONIZE = true,
        //         },
        //         .SPECIFIC = .{ .TRANSACTION = .{
        //             .QUERY_INFORMATION = true,
        //             .SET_INFORMATION = true,
        //             .ENLIST = true,
        //             .ROLLBACK = true,
        //             .PROPAGATE = true,
        //         } },
        //     };
        // };

        // pub const ResourceManager = packed struct(u16) {
        //     QUERY_INFORMATION: bool = false,
        //     SET_INFORMATION: bool = false,
        //     RECOVER: bool = false,
        //     ENLIST: bool = false,
        //     GET_NOTIFICATION: bool = false,
        //     REGISTER_PROTOCOL: bool = false,
        //     COMPLETE_PROPAGATION: bool = false,
        //     Reserved7: u9 = 0,

        //     pub const GENERIC_READ: ACCESS_MASK = .{
        //         .STANDARD = .{
        //             .RIGHTS = .READ,
        //             .SYNCHRONIZE = true,
        //         },
        //         .SPECIFIC = .{ .RESOURCEMANAGER = .{
        //             .QUERY_INFORMATION = true,
        //         } },
        //     };

        //     pub const GENERIC_WRITE: ACCESS_MASK = .{
        //         .STANDARD = .{
        //             .RIGHTS = .WRITE,
        //             .SYNCHRONIZE = true,
        //         },
        //         .SPECIFIC = .{ .RESOURCEMANAGER = .{
        //             .SET_INFORMATION = true,
        //             .RECOVER = true,
        //             .ENLIST = true,
        //             .GET_NOTIFICATION = true,
        //             .REGISTER_PROTOCOL = true,
        //             .COMPLETE_PROPAGATION = true,
        //         } },
        //     };

        //     pub const GENERIC_EXECUTE: ACCESS_MASK = .{
        //         .STANDARD = .{
        //             .RIGHTS = .EXECUTE,
        //             .SYNCHRONIZE = true,
        //         },
        //         .SPECIFIC = .{ .RESOURCEMANAGER = .{
        //             .RECOVER = true,
        //             .ENLIST = true,
        //             .GET_NOTIFICATION = true,
        //             .COMPLETE_PROPAGATION = true,
        //         } },
        //     };

        //     pub const ALL_ACCESS: ACCESS_MASK = .{
        //         .STANDARD = .{
        //             .RIGHTS = .REQUIRED,
        //             .SYNCHRONIZE = true,
        //         },
        //         .SPECIFIC = .{ .RESOURCEMANAGER = .{
        //             .QUERY_INFORMATION = true,
        //             .SET_INFORMATION = true,
        //             .RECOVER = true,
        //             .ENLIST = true,
        //             .GET_NOTIFICATION = true,
        //             .REGISTER_PROTOCOL = true,
        //             .COMPLETE_PROPAGATION = true,
        //         } },
        //     };
        // };

        // pub const Enlistment = packed struct(u16) {
        //     QUERY_INFORMATION: bool = false,
        //     SET_INFORMATION: bool = false,
        //     RECOVER: bool = false,
        //     SUBORDINATE_RIGHTS: bool = false,
        //     SUPERIOR_RIGHTS: bool = false,
        //     Reserved5: u11 = 0,

        //     pub const GENERIC_READ: ACCESS_MASK = .{
        //         .STANDARD = .{ .RIGHTS = .READ },
        //         .SPECIFIC = .{ .ENLISTMENT = .{
        //             .QUERY_INFORMATION = true,
        //         } },
        //     };

        //     pub const GENERIC_WRITE: ACCESS_MASK = .{
        //         .STANDARD = .{ .RIGHTS = .WRITE },
        //         .SPECIFIC = .{ .ENLISTMENT = .{
        //             .SET_INFORMATION = true,
        //             .RECOVER = true,
        //             .SUBORDINATE_RIGHTS = true,
        //             .SUPERIOR_RIGHTS = true,
        //         } },
        //     };

        //     pub const GENERIC_EXECUTE: ACCESS_MASK = .{
        //         .STANDARD = .{ .RIGHTS = .EXECUTE },
        //         .SPECIFIC = .{ .ENLISTMENT = .{
        //             .RECOVER = true,
        //             .SUBORDINATE_RIGHTS = true,
        //             .SUPERIOR_RIGHTS = true,
        //         } },
        //     };

        //     pub const ALL_ACCESS: ACCESS_MASK = .{
        //         .STANDARD = .{ .RIGHTS = .REQUIRED },
        //         .SPECIFIC = .{ .ENLISTMENT = .{
        //             .QUERY_INFORMATION = true,
        //             .SET_INFORMATION = true,
        //             .RECOVER = true,
        //             .SUBORDINATE_RIGHTS = true,
        //             .SUPERIOR_RIGHTS = true,
        //         } },
        //     };
        // };

        // pub const Event = packed struct(u16) {
        //     QUERY_STATE: bool = false,
        //     MODIFY_STATE: bool = false,
        //     Reserved2: u14 = 0,

        //     pub const ALL_ACCESS: ACCESS_MASK = .{
        //         .STANDARD = .{
        //             .RIGHTS = .REQUIRED,
        //             .SYNCHRONIZE = true,
        //         },
        //         .SPECIFIC = .{ .EVENT = .{
        //             .QUERY_STATE = true,
        //             .MODIFY_STATE = true,
        //         } },
        //     };
        // };

        // pub const Semaphore = packed struct(u16) {
        //     QUERY_STATE: bool = false,
        //     MODIFY_STATE: bool = false,
        //     Reserved2: u14 = 0,

        //     pub const ALL_ACCESS: ACCESS_MASK = .{
        //         .STANDARD = .{
        //             .RIGHTS = .REQUIRED,
        //             .SYNCHRONIZE = true,
        //         },
        //         .SPECIFIC = .{ .SEMAPHORE = .{
        //             .QUERY_STATE = true,
        //             .MODIFY_STATE = true,
        //         } },
        //     };
        // };

        // pub const Token = packed struct(u16) {
        //     ASSIGN_PRIMARY: bool = false,
        //     DUPLICATE: bool = false,
        //     IMPERSONATE: bool = false,
        //     QUERY: bool = false,
        //     QUERY_SOURCE: bool = false,
        //     ADJUST_PRIVILEGES: bool = false,
        //     ADJUST_GROUPS: bool = false,
        //     ADJUST_DEFAULT: bool = false,
        //     ADJUST_SESSIONID: bool = false,
        //     Reserved9: u7 = 0,

        //     pub const ALL_ACCESS_P: ACCESS_MASK = .{
        //         .STANDARD = .{ .RIGHTS = .REQUIRED },
        //         .SPECIFIC = .{ .TOKEN = .{
        //             .ASSIGN_PRIMARY = true,
        //             .DUPLICATE = true,
        //             .IMPERSONATE = true,
        //             .QUERY = true,
        //             .QUERY_SOURCE = true,
        //             .ADJUST_PRIVILEGES = true,
        //             .ADJUST_GROUPS = true,
        //             .ADJUST_DEFAULT = true,
        //         } },
        //     };

        //     pub const ALL_ACCESS: ACCESS_MASK = .{
        //         .STANDARD = .{ .RIGHTS = .REQUIRED },
        //         .SPECIFIC = .{ .TOKEN = .{
        //             .ASSIGN_PRIMARY = true,
        //             .DUPLICATE = true,
        //             .IMPERSONATE = true,
        //             .QUERY = true,
        //             .QUERY_SOURCE = true,
        //             .ADJUST_PRIVILEGES = true,
        //             .ADJUST_GROUPS = true,
        //             .ADJUST_DEFAULT = true,
        //             .ADJUST_SESSIONID = true,
        //         } },
        //     };

        //     pub const READ: ACCESS_MASK = .{
        //         .STANDARD = .{ .RIGHTS = .READ },
        //         .SPECIFIC = .{ .TOKEN = .{
        //             .QUERY = true,
        //         } },
        //     };

        //     pub const WRITE: ACCESS_MASK = .{
        //         .STANDARD = .{ .RIGHTS = .WRITE },
        //         .SPECIFIC = .{ .TOKEN = .{
        //             .ADJUST_PRIVILEGES = true,
        //             .ADJUST_GROUPS = true,
        //             .ADJUST_DEFAULT = true,
        //         } },
        //     };

        //     pub const EXECUTE: ACCESS_MASK = .{
        //         .STANDARD = .{ .RIGHTS = .EXECUTE },
        //         .SPECIFIC = .{ .TOKEN = .{} },
        //     };

        //     pub const TRUST_CONSTRAINT_MASK: ACCESS_MASK = .{
        //         .STANDARD = .{ .RIGHTS = .READ },
        //         .SPECIFIC = .{ .TOKEN = .{
        //             .QUERY = true,
        //             .QUERY_SOURCE = true,
        //         } },
        //     };

        //     pub const TRUST_ALLOWED_MASK: ACCESS_MASK = .{
        //         .STANDARD = .{ .RIGHTS = .READ },
        //         .SPECIFIC = .{ .TOKEN = .{
        //             .QUERY = true,
        //             .QUERY_SOURCE = true,
        //             .DUPLICATE = true,
        //             .IMPERSONATE = true,
        //         } },
        //     };
        // };

        // pub const JobObject = packed struct(u16) {
        //     ASSIGN_PROCESS: bool = false,
        //     SET_ATTRIBUTES: bool = false,
        //     QUERY: bool = false,
        //     TERMINATE: bool = false,
        //     SET_SECURITY_ATTRIBUTES: bool = false,
        //     IMPERSONATE: bool = false,
        //     Reserved6: u10 = 0,

        //     pub const ALL_ACCESS: ACCESS_MASK = .{
        //         .STANDARD = .{
        //             .RIGHTS = .REQUIRED,
        //             .SYNCHRONIZE = true,
        //         },
        //         .SPECIFIC = .{ .JOB_OBJECT = .{
        //             .ASSIGN_PROCESS = true,
        //             .SET_ATTRIBUTES = true,
        //             .QUERY = true,
        //             .TERMINATE = true,
        //             .SET_SECURITY_ATTRIBUTES = true,
        //             .IMPERSONATE = true,
        //         } },
        //     };
        // };

        // pub const Mutant = packed struct(u16) {
        //     QUERY_STATE: bool = false,
        //     Reserved1: u15 = 0,

        //     pub const ALL_ACCESS: ACCESS_MASK = .{
        //         .STANDARD = .{
        //             .RIGHTS = .REQUIRED,
        //             .SYNCHRONIZE = true,
        //         },
        //         .SPECIFIC = .{ .MUTANT = .{
        //             .QUERY_STATE = true,
        //         } },
        //     };
        // };

        // pub const Timer = packed struct(u16) {
        //     QUERY_STATE: bool = false,
        //     MODIFY_STATE: bool = false,
        //     Reserved2: u14 = 0,

        //     pub const ALL_ACCESS: ACCESS_MASK = .{
        //         .STANDARD = .{
        //             .RIGHTS = .REQUIRED,
        //             .SYNCHRONIZE = true,
        //         },
        //         .SPECIFIC = .{ .TIMER = .{
        //             .QUERY_STATE = true,
        //             .MODIFY_STATE = true,
        //         } },
        //     };
        // };

        // pub const IoCompletion = packed struct(u16) {
        //     Reserved0: u1 = 0,
        //     MODIFY_STATE: bool = false,
        //     Reserved2: u14 = 0,

        //     pub const ALL_ACCESS: ACCESS_MASK = .{
        //         .STANDARD = .{ .RIGHTS = .REQUIRED, .SYNCHRONIZE = true },
        //         .SPECIFIC = .{ .IO_COMPLETION = .{
        //             .Reserved0 = std.math.maxInt(@FieldType(IoCompletion, "Reserved0")),
        //             .MODIFY_STATE = true,
        //         } },
        //     };
        // };

        pub const RIGHTS_ALL: Specific = .{ .bits = std.math.maxInt(@FieldType(Specific, "bits")) };
    };

    pub const Standard = packed struct(u5) {
        RIGHTS: Rights = .{},
        SYNCHRONIZE: bool = false,

        pub const RIGHTS_ALL: Standard = .{
            .RIGHTS = .ALL,
            .SYNCHRONIZE = true,
        };

        pub const Rights = packed struct(u4) {
            DELETE: bool = false,
            READ_CONTROL: bool = false,
            WRITE_DAC: bool = false,
            WRITE_OWNER: bool = false,

            pub const REQUIRED: Rights = .{
                .DELETE = true,
                .READ_CONTROL = true,
                .WRITE_DAC = true,
                .WRITE_OWNER = true,
            };

            pub const READ: Rights = .{
                .READ_CONTROL = true,
            };
            pub const WRITE: Rights = .{
                .READ_CONTROL = true,
            };
            pub const EXECUTE: Rights = .{
                .READ_CONTROL = true,
            };

            pub const ALL = REQUIRED;
        };
    };

    pub const Generic = packed struct(u4) {
        ALL: bool = false,
        EXECUTE: bool = false,
        WRITE: bool = false,
        READ: bool = false,
    };
};

pub const OBJECT = struct {
    /// - ref: um/winternl.h
    /// - ref: https://learn.microsoft.com/en-us/windows/win32/api/ntdef/ns-ntdef-_object_attributes
    pub const ATTRIBUTES = extern struct {
        /// The number of bytes of data contained in this structure.
        Length: ULONG = @sizeOf(ATTRIBUTES),
        /// Optional handle to the root object directory for the path name specified by the `ObjectName` member.
        /// If `RootDirectory` is `null`, `ObjectName` must point to a fully qualified object name that
        /// includes the full path to the target object. If `RootDirectory` is non-`null`,
        /// `ObjectName` specifies an object name relative to the RootDirectory directory.
        /// The RootDirectory handle can refer to a file system directory or
        /// an object directory in the object manager namespace.
        RootDirectory: ?HANDLE = null,
        /// Pointer to a Unicode string that contains the name of the object for which a handle is to be opened.
        /// This must either be a fully qualified object name, or a relative path name to the directory
        /// specified by the `RootDirectory` member.
        ObjectName: P(UNICODE_STRING) = @constCast(&UNICODE_STRING.empty),
        Attributes: Flags,
        /// Specifies a `SECURITY.DESCRIPTOR` for the object when the object is created.
        /// If `SecurityDescriptor` is `null`, the object will receive default security settings.
        /// See [DACL for a New Object](https://learn.microsoft.com/en-us/windows/win32/secauthz/dacl-for-a-new-object).
        SecurityDescriptor: ?P(SECURITY.DESCRIPTOR) = null,
        /// Optional quality of service to be applied to the object when it is created.
        /// Used to indicate the security impersonation level and context tracking mode (dynamic or static).
        SecurityQualityOfService: ?P(SECURITY.QUALITY_OF_SERVICE) = null,

        pub const Flags = packed struct(ULONG) {
            Reserved0: u1 = 0,
            /// This handle can be inherited by child processes of the current process.
            INHERIT: bool = false,
            Reserved2: u2 = 0,
            /// This flag only applies to objects that are named within the object manager.
            /// By default, such objects are deleted when all open handles to them are closed.
            /// If this flag is specified, the object is not deleted when all open handles are closed.
            /// Drivers can use the [ZwMakeTemporaryObject](https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/content/wdm/nf-wdm-zwmaketemporaryobject)
            /// routine to make a permanent object non-permanent.
            PERMANENT: bool = false,
            /// If this flag is set and the `OBJECT.ATTRIBUTES` structure is passed to a routine that
            /// creates an object, the object can be accessed exclusively. That is, once a process
            /// opens such a handle to the object, no other processes can open handles to this object.
            ///
            /// If this flag is set and the `OBJECT.ATTRIBUTES` structure is passed to a routine that
            /// creates an object handle, the caller is requesting exclusive access to the object
            /// for the process context that the handle was created in. This request can be granted
            /// only if the `OBJECT.ATTRIBUTES.Flags.EXCLUSIVE` flag was set when the object was created.
            EXCLUSIVE: bool = false,
            /// If this flag is specified, a case-insensitive comparison is used when matching the name
            /// pointed to by the `ObjectName` member against the names of existing objects.
            /// Otherwise, object names are compared using the default system settings.
            CASE_INSENSITIVE: bool = false,
            /// If this flag is specified, by using the object handle, to a routine that
            /// creates objects and if that object already exists, the routine should open that object.
            /// Otherwise, the routine creating the object returns an `NTSTATUS` code of `OBJECT_NAME_COLLISION`.
            OPENIF: bool = false,
            /// If an object handle, with this flag set, is passed to a routine that
            /// opens objects and if the object is a symbolic link object, the routine should
            /// open the symbolic link object itself, rather than the object that
            /// the symbolic link refers to (which is the default behavior).
            OPENLINK: bool = false,
            /// The handle is created in system process context and can only be accessed from kernel mode.
            KERNEL_HANDLE: bool = false,
            /// The routine that opens the handle should enforce all access checks for the object,
            /// even if the handle is being opened in kernel mode.
            FORCE_ACCESS_CHECK: bool = false,
            /// A device map is a mapping between DOS device names and devices in the system,
            /// and is used when resolving DOS names. Separate device maps exists for each user
            /// in the system, and users can manage their own device maps.
            /// Typically during impersonation, the impersonated user's device map would be used.
            /// However, when this flag is set, the process user's device map is used instead.
            IGNORE_IMPERSONATED_DEVICEMAP: bool = false,
            /// If this flag is set, no reparse points will be followed when parsing the name
            /// of the associated object. If any reparses are encountered the attempt will fail and
            /// return an `NTSTATUS.REPARSE_POINT_ENCOUNTERED` result.
            /// This can be used to determine if there are any reparse points in the object's path,
            /// in security scenarios.
            DONT_REPARSE: bool = false,
            Reserved13: u19 = 0,

            // Reserved
            pub const VALID_ATTRIBUTES: Flags = .{
                .INHERIT = true,
                .PERMANENT = true,
                .EXCLUSIVE = true,
                .CASE_INSENSITIVE = true,
                .OPENIF = true,
                .OPENLINK = true,
                .KERNEL_HANDLE = true,
                .FORCE_ACCESS_CHECK = true,
                .IGNORE_IMPERSONATED_DEVICEMAP = true,
                .DONT_REPARSE = true,
            };
        };
    };
};

pub const FILE = struct {
    pub const PIPE = struct {
        /// - ref: um/WinBase.h
        pub const UNLIMITED_INSTANCES: ULONG = 0xffffffff;

        /// Define the `NamedPipeType` flags for `NtCreateNamedPipeFile`
        /// - ref: km/ntifs.h
        pub const TYPE = packed struct(ULONG) {
            TYPE: enum(u1) {
                BYTE_STREAM = 0b0,
                MESSAGE = 0b1,
            } = .BYTE_STREAM,
            REMOTE_CLIENTS: enum(u1) {
                ACCEPT = 0b0,
                REJECT = 0b1,
            } = .ACCEPT,
            Reserved2: u30 = 0,

            pub const VALID_MASK: TYPE = .{
                .TYPE = .MESSAGE,
                .REMOTE_CLIENTS = .REJECT,
            };
        };

        /// Define the `CompletionMode` flags for `NtCreateNamedPipeFile`
        /// - ref: km/ntifs.h
        pub const COMPLETION_MODE = packed struct(ULONG) {
            OPERATION: enum(u1) {
                QUEUE = 0b0,
                COMPLETE = 0b1,
            } = .QUEUE,
            Reserved1: u31 = 0,
        };

        /// Define the `ReadMode` flags for `NtCreateNamedPipeFile`
        /// - ref: km/ntifs.h
        pub const READ_MODE = packed struct(ULONG) {
            MODE: enum(u1) {
                BYTE_STREAM = 0b0,
                MESSAGE = 0b1,
            },
            Reserved1: u31 = 0,
        };

        /// Define the `NamedPipeConfiguration` flags for `NtQueryInformationFile`
        /// - ref: km/ntifs.h
        pub const CONFIGURATION = enum(ULONG) {
            INBOUND = 0x00000000,
            OUTBOUND = 0x00000001,
            FULL_DUPLEX = 0x00000002,
        };

        /// Define the `NamedPipeState` flags for `NtQueryInformationFile`
        /// - ref: km/ntifs.h
        pub const STATE = enum(ULONG) {
            DISCONNECTED = 0x00000001,
            LISTENING = 0x00000002,
            CONNECTED = 0x00000003,
            CLOSING = 0x00000004,
        };

        /// Define the `NamedPipeEnd` flags for `NtQueryInformationFile`
        /// - ref: km/ntifs.h
        pub const END = enum(ULONG) {
            CLIENT = 0x00000000,
            SERVER = 0x00000001,
        };

        /// - ref: km/ntifs.h
        pub const INFORMATION = extern struct {
            ReadMode: READ_MODE,
            CompletionMode: COMPLETION_MODE,
        };

        /// - ref: km/ntifs.h
        pub const LOCAL_INFORMATION = extern struct {
            NamedPipeType: TYPE,
            NamedPipeConfiguration: CONFIGURATION,
            MaximumInstances: ULONG,
            CurrentInstances: ULONG,
            InboundQuota: ULONG,
            ReadDataAvailable: ULONG,
            OutboundQuota: ULONG,
            WriteQuotaAvailable: ULONG,
            NamedPipeState: STATE,
            NamedPipeEnd: END,
        };

        /// - ref: km/ntifs.h
        pub const REMOTE_INFORMATION = extern struct {
            CollectDataTime: LARGE_INTEGER,
            MaximumCollectionCount: ULONG,
        };

        /// - ref: km/ntifs.h
        pub const WAIT_FOR_BUFFER = extern struct {
            Timeout: LARGE_INTEGER,
            NameLength: ULONG,
            TimeoutSpecified: BOOLEAN,
            Name: [PATH_MAX_WIDE]WCHAR,

            pub const WAIT_FOREVER: LARGE_INTEGER = std.math.minInt(LARGE_INTEGER);

            pub fn init(opts: struct {
                Timeout: ?LARGE_INTEGER = null,
                Name: []const WCHAR,
            }) WAIT_FOR_BUFFER {
                var fpwfb: WAIT_FOR_BUFFER = .{
                    .Timeout = opts.Timeout orelse undefined,
                    .NameLength = @intCast(@sizeOf(WCHAR) * opts.Name.len),
                    .TimeoutSpecified = .fromBool(opts.Timeout != null),
                    .Name = undefined,
                };
                @memcpy(fpwfb.Name[0..opts.Name.len], opts.Name);
                return fpwfb;
            }

            pub fn getName(fpwfb: *const WAIT_FOR_BUFFER) []const WCHAR {
                return fpwfb.Name[0..@divExact(fpwfb.NameLength, @sizeOf(WCHAR))];
            }

            pub fn toBuffer(fpwfb: *const WAIT_FOR_BUFFER) []const u8 {
                const name_ptr: [*]const u8 = @ptrCast(&fpwfb.Name);
                return name_ptr[0..fpwfb.NameLength];
            }
        };
    };

    /// - ref: um/winnt.h
    pub const SHARE = packed struct(ULONG) {
        /// The file can be opened for read access by other threads.
        READ: bool = false,
        /// The file can be opened for write access by other threads.
        WRITE: bool = false,
        /// The file can be opened for delete access by other threads.
        DELETE: bool = false,
        Reserved3: u29 = 0,

        pub const VALID_FLAGS: SHARE = .{
            .READ = true,
            .WRITE = true,
            .DELETE = true,
        };
    };

    /// - ref: um/winternl.h
    /// - ref: <phnt>/ntioapi.h
    pub const CREATE_DISPOSITION = enum(ULONG) {
        /// If the file already exists, replace it with the given file. If it does not, create the given file.
        SUPERSEDE = 0x00000000,
        /// If the file already exists, open it instead of creating a new file.
        /// If it does not, fail the request and do not create a new file.
        OPEN = 0x00000001,
        /// If the file already exists, fail the request and do not create or
        /// open the given file. If it does not, create the given file.
        CREATE = 0x00000002,
        /// If the file already exists, open it. If it does not, create the given file.
        OPEN_IF = 0x00000003,
        /// If the file already exists, open it and overwrite it. If it does not, fail the request.
        OVERWRITE = 0x00000004,
        /// If the file already exists, open it and overwrite it. If it does not, create the given file.
        OVERWRITE_IF = 0x00000005,

        pub const MAXIMUM_DISPOSITION: CREATE_DISPOSITION = .OVERWRITE_IF;
    };

    /// - ref: km/wdm.h
    /// - ref: https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/ntifs/nf-ntifs-ntcreatefile
    /// - ref: <phnt>/ntioapi.h
    pub const MODE = packed struct(ULONG) {
        /// The file being created or opened is a directory file.
        /// With this flag, the CreateDisposition parameter must be set to `CREATE`, `OPEN`, or `OPEN_IF`.
        /// With this flag, other compatible CreateOptions flags include only `SYNCHRONOUS_IO`,
        /// `WRITE_THROUGH`, `OPEN_FOR_BACKUP_INTENT`, and `OPEN_BY_FILE_ID`.
        DIRECTORY_FILE: bool = false,
        /// Applications that write data to the file must actually transfer the
        /// data into the file before any requested write operation is
        /// considered complete. This flag is automatically set if the
        /// CreateOptions flag `NO_INTERMEDIATE_BUFFERING` is set.
        WRITE_THROUGH: bool = false,
        /// All accesses to the file are sequential.
        SEQUENTIAL_ONLY: bool = false,
        /// The file cannot be cached or buffered in a driver's internal
        /// buffers. This flag is incompatible with the DesiredAccess
        /// `FILE_APPEND_DATA` flag.
        NO_INTERMEDIATE_BUFFERING: bool = false,
        IO: enum(u2) {
            /// All operations on the file are performed asynchronously.
            ASYNCHRONOUS = 0b00,
            /// All operations on the file are performed synchronously. Any
            /// wait on behalf of the caller is subject to premature
            /// termination from alerts. This flag also causes the I/O system
            /// to maintain the file position context. If this flag is set, the
            /// DesiredAccess `SYNCHRONIZE` flag also must be set.
            SYNCHRONOUS_ALERT = 0b01,
            /// All operations on the file are performed synchronously. Waits
            /// in the system to synchronize I/O queuing and completion are not
            /// subject to alerts. This flag also causes the I/O system to
            /// maintain the file position context. If this flag is set, the
            /// DesiredAccess `SYNCHRONIZE` flag also must be set.
            SYNCHRONOUS_NONALERT = 0b10,
            _,

            pub const VALID_FLAGS: @This() = @enumFromInt(0b11);
        },
        /// The file being opened must not be a directory file or this call fails.
        /// The file object being opened can represent a data file, a logical, virtual,
        /// or physical device, or a volume.
        NON_DIRECTORY_FILE: bool = false,
        /// Create a tree connection for this file in order to open it over the network.
        /// This flag is not used by device and intermediate drivers.
        CREATE_TREE_CONNECTION: bool = false,
        /// Complete this operation immediately with an alternate success code of `OPLOCK_BREAK_IN_PROGRESS`
        /// if the target file is oplocked, rather than blocking the caller's thread.
        /// If the file is oplocked, another caller already has access to the file.
        /// This flag is not used by device and intermediate drivers.
        COMPLETE_IF_OPLOCKED: bool = false,
        /// If the extended attributes on an existing file being opened indicate that the caller
        /// must understand EAs to properly interpret the file, fail this request because the caller
        /// does not understand how to deal with EAs.
        /// This flag is irrelevant for device and intermediate drivers.
        NO_EA_KNOWLEDGE: bool = false,
        /// Open a remote instance of a file object, rather than attempting to reuse or
        /// collapse it into an existing local or cached file object.
        OPEN_REMOTE_INSTANCE: bool = false,
        /// Accesses to the file can be random, so no sequential read-ahead operations should be
        /// performed on the file by FSDs or the system.
        RANDOM_ACCESS: bool = false,
        /// Delete the file when the last handle to it is passed to NtClose.
        /// If this flag is set, the `DELETE` flag must be set in the DesiredAccess parameter.
        DELETE_ON_CLOSE: bool = false,
        /// The file name specified by the ObjectAttributes parameter includes the 8-byte file
        /// reference number for the file. This number is assigned by and specific to the particular
        /// file system. If the file is a reparse point, the file name will also include the name
        /// of a device. Note that the FAT file system does not support this flag.
        /// This flag is not used by device and intermediate drivers.
        OPEN_BY_FILE_ID: bool = false,
        /// The file is being opened for backup intent.
        /// Therefore, the system should check for certain access rights and grant the caller the
        /// appropriate access to the file before checking the DesiredAccess parameter against the
        /// file's security descriptor.
        /// This flag is not used by device and intermediate drivers.
        OPEN_FOR_BACKUP_INTENT: bool = false,
        /// Suppress inheritance of `FILE.ATTRIBUTE.COMPRESSED` from the parent directory.
        /// This allows creation of a non-compressed file in a directory that is marked compressed.
        NO_COMPRESSION: bool = false,
        /// The file is being opened and an opportunistic lock on the file is being requested as a
        /// single atomic operation. The file system checks for oplocks before it performs the
        /// create operation and fails the create with `CANNOT_BREAK_OPLOCK` if the result would break an existing oplock.
        OPEN_REQUIRING_OPLOCK: bool = false,
        /// When opening an existing file, if FILE_SHARE_READ is not specified and file system access
        /// checks would not grant the caller write access to the file, fail this open with
        /// `NTSTATUS.ACCESS_DENIED`. This was default behavior prior to Windows 7.
        DISALLOW_EXCLUSIVE: bool = false,
        /// The client opening the file or device is session aware and per session access is
        /// validated if necessary.
        SESSION_AWARE: bool = false,
        Reserved19: u1 = 0,
        /// Allows an application to request a filter opportunistic lock to prevent other
        /// applications from getting share violations.
        /// If there are already open handles, the create request fails with `NTSTATUS.OPLOCK_NOT_GRANTED`.
        RESERVE_OPFILTER: bool = false,
        /// Open a file with a reparse point and bypass normal reparse point processing for the file.
        OPEN_REPARSE_POINT: bool = false,
        /// Instructs any filters that perform offline storage or virtualization to not recall the
        /// contents of the file as a result of this open.
        OPEN_NO_RECALL: bool = false,
        /// Instructs the file system to capture the user associated with the calling thread.
        /// Subsequent calls to `FltQueryVolumeInformation` or `ZwQueryVolumeInformationFile` using
        /// the returned handle use the captured user, rather than the calling user at that time, to
        /// compute available free space.
        /// This applies to `FileFsSizeInformation`, `FileFsFullSizeInformation`,
        /// and `FileFsFullSizeInformationEx`.
        OPEN_FOR_FREE_SPACE_QUERY: bool = false,
        Reserved24: u8 = 0,

        pub const VALID_OPTION_FLAGS: MODE = .{
            .DIRECTORY_FILE = true,
            .WRITE_THROUGH = true,
            .SEQUENTIAL_ONLY = true,
            .NO_INTERMEDIATE_BUFFERING = true,
            .IO = .VALID_FLAGS,
            .NON_DIRECTORY_FILE = true,
            .CREATE_TREE_CONNECTION = true,
            .COMPLETE_IF_OPLOCKED = true,
            .NO_EA_KNOWLEDGE = true,
            .OPEN_REMOTE_INSTANCE = true,
            .RANDOM_ACCESS = true,
            .DELETE_ON_CLOSE = true,
            .OPEN_BY_FILE_ID = true,
            .OPEN_FOR_BACKUP_INTENT = true,
            .NO_COMPRESSION = true,
            .OPEN_REQUIRING_OPLOCK = true,
            .DISALLOW_EXCLUSIVE = true,
            .SESSION_AWARE = true,
            .Reserved19 = 0b1,
            .RESERVE_OPFILTER = true,
            .OPEN_REPARSE_POINT = true,
            .OPEN_NO_RECALL = true,
            .OPEN_FOR_FREE_SPACE_QUERY = true,
        };

        pub const VALID_PIPE_OPTION_FLAGS: MODE = .{
            .WRITE_THROUGH = true,
            .IO = .VALID_FLAGS,
        };

        pub const VALID_MAILSLOT_OPTION_FLAGS: MODE = .{
            .WRITE_THROUGH = true,
            .IO = .VALID_FLAGS,
        };

        pub const VALID_SET_OPTION_FLAGS: MODE = .{
            .WRITE_THROUGH = true,
            .SEQUENTIAL_ONLY = true,
            .IO = .VALID_FLAGS,
        };

        /// - ref: km/ntifs.h
        pub const INFORMATION = extern struct {
            /// The set of flags that specify the mode in which the file can be
            /// accessed. These flags are a subset of `MODE`.
            Mode: MODE,
        };
    };
};

pub const SECURITY = struct {
    /// - ref: um/winnt.h
    /// - ref: https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/ntifs/ns-ntifs-_security_descriptor
    pub const DESCRIPTOR = extern struct {
        /// Specifies the revision level of the security descriptor.
        Revision: BYTE,
        /// Specifies a zero byte of padding that aligns the Revision member on a 16-bit boundary.
        Sbz1: BYTE,
        Control: CONTROL,
        Owner: P(SID),
        Group: P(SID),
        Sacl: P(ACL),
        Dacl: P(ACL),

        /// - ref: km/ntifs.h
        /// - ref: https://learn.microsoft.com/en-us/windows-hardware/drivers/ifs/security-descriptor-control
        pub const CONTROL = packed struct(USHORT) {
            /// A default mechanism, rather than the original provider of the security descriptor,
            /// provided the security descriptor's owner security identifier (SID).
            /// To set this flag, use [`RtlSetOwnerSecurityDescriptor`](https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/ntifs/nf-ntifs-rtlsetownersecuritydescriptor).
            OWNER_DEFAULTED: bool = false,
            /// A default mechanism, rather than the original provider of the security descriptor,
            /// provided the security descriptor's group SID.
            GROUP_DEFAULTED: bool = false,
            /// Indicates a security descriptor that has a DACL. If this flag isn't set,
            /// or if this flag is set and the DACL is NULL, the security descriptor allows
            /// full access to everyone. This flag is used to hold the security information specified
            /// by a caller until the security descriptor is associated with a securable object.
            /// Once the security descriptor is associated with a securable object,
            /// the `DACL_PRESENT` flag is always set in the security descriptor control.
            /// To set this flag, use [`RtlSetDaclSecurityDescriptor`](https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/wdm/nf-wdm-rtlsetdaclsecuritydescriptor).
            DACL_PRESENT: bool = false,
            /// Indicates a security descriptor with a default DACL. For example, if an object's creator
            /// doesn't specify a DACL, the object receives the default DACL from the creator's access token.
            /// This flag can affect how the system treats the DACL, with respect to ACE inheritance.
            /// The system ignores this flag if the `DACL_PRESENT` flag isn't set.
            /// This flag is used to determine how the final DACL on the object is to be computed and
            /// isn't stored physically in the security descriptor control of the securable object.
            /// To set this flag, use [`RtlSetDaclSecurityDescriptor`](https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/wdm/nf-wdm-rtlsetdaclsecuritydescriptor).
            DACL_DEFAULTED: bool = false,
            /// Indicates a security descriptor that has a SACL.
            SACL_PRESENT: bool = false,
            /// A default mechanism, rather than the original provider of the security descriptor, provided the SACL.
            /// This flag can affect how the system treats the SACL, with respect to ACE inheritance.
            /// The system ignores this flag if the `SACL_PRESENT` flag isn't set.
            SACL_DEFAULTED: bool = false,
            /// Indicates that the ACL pointed to by the DACL of the security descriptor was
            /// provided by an untrusted source. If this flag is set and a compound ACE is encountered,
            /// the system substitutes known valid SIDs for the server SIDs in the ACEs.
            DACL_UNTRUSTED: bool = false,
            /// Requests that the provider for the object protected by the security descriptor whose
            /// ACL should a server ACL based on the input ACL, regardless of its source (explicit or defaulting).
            /// This is done by replacing all of the GRANT ACEs with compound ACEs granting the current server.
            /// This flag is only meaningful if the subject is impersonating.
            SERVER_SECURITY: bool = false,
            /// Requests that the provider for the object protected by the security descriptor
            /// automatically propagate the DACL to existing child objects. If the provider supports
            /// automatic inheritance, it propagates the DACL to any existing child objects, and sets
            /// the `DACL_AUTO_INHERITED` bit in the security descriptors of the object and its child objects.
            DACL_AUTO_INHERIT_REQ: bool = false,
            /// Requests that the provider for the object protected by the security descriptor
            /// automatically propagate the SACL to existing child objects. If the provider supports
            /// automatic inheritance, it propagates the SACL to any existing child objects, and sets
            /// the `SACL_AUTO_INHERITED` bit in the security descriptors of the object and its child objects.
            SACL_AUTO_INHERIT_REQ: bool = false,
            /// Starting with Windows 2000, indicates a security descriptor in which the DACL supports
            /// automatic propagation of inheritable ACEs to existing child objects.
            /// For Windows 2000 ACLs that support autoinheritance, this bit is always set.
            /// It's used to distinguish these ACLs from Windows NT 4.0 ACLs that don't support autoinheritance.
            /// This bit isn't set in security descriptors for Windows NT 4.0 and earlier,
            /// which don't support automatic propagation of inheritable ACEs.
            DACL_AUTO_INHERITED: bool = false,
            /// Indicates a security descriptor in which the SACL supports automatic propagation of
            /// inheritable ACEs to existing child objects. This bit is set only if the automatic
            /// inheritance algorithm has been performed for the object and its existing child objects.
            /// This bit isn't set in security descriptors for Windows NT 4.0 and earlier,
            /// which didn't support automatic propagation of inheritable ACEs.
            SACL_AUTO_INHERITED: bool = false,
            /// Protects the DACL of the security descriptor from being modified by inheritable ACEs.
            DACL_PROTECTED: bool = false,
            /// Protects the SACL of the security descriptor from being modified by inheritable ACEs.
            SACL_PROTECTED: bool = false,
            /// Indicates that the resource control manager bits in the security descriptor are valid.
            /// The Resource Manager control bits are eight bits in the `Sbz1` member of
            /// the `SECURITY.DESCRIPTOR` structure that contains information specific to
            /// the Resource Manager accessing the structure.
            RM_CONTROL_VALID: bool = false,
            /// Indicates a security descriptor in self-relative format with all the security
            /// information in a contiguous block of memory. If this flag isn't set,
            /// the security descriptor is in absolute format.
            SELF_RELATIVE: bool = false,
        };
    };

    /// - ref: km/wdm.h
    /// - ref: https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-security_quality_of_service
    pub const QUALITY_OF_SERVICE = extern struct {
        /// Specifies the size, in bytes, of this structure.
        Length: ULONG,
        /// Specifies the information given to the server about the client,
        /// and how the server may represent, or impersonate, the client.
        /// Security impersonation levels govern the degree to which a server process can act on
        /// behalf of a client process.
        ImpersonationLevel: IMPERSONATION_LEVEL,
        /// Specifies whether the server is to be given a snapshot of the client's security
        /// context (called static tracking), or is to be continually updated to track changes to
        /// the client's security context (called dynamic tracking). The SECURITY_STATIC_TRACKING
        /// value specifies static tracking, and the SECURITY_DYNAMIC_TRACKING value specifies
        /// dynamic tracking. Not all communications mechanisms support dynamic tracking;
        /// those that do not will default to static tracking.
        ContextTrackingMode: CONTEXT_TRACKING_MODE,
        /// Specifies whether the server may enable or disable privileges and groups that the
        /// client's security context may include.
        EffectiveOnly: BOOLEAN,
    };

    /// - ref: um/winnt.h
    /// - ref: https://learn.microsoft.com/en-us/windows/win32/api/winnt/ne-winnt-security_impersonation_level
    // NOTE(freemaker): no size specified default for c should be 'int'
    pub const IMPERSONATION_LEVEL = enum(INT) {
        Anonymous = 0x0000,
        Identification = 0x0001,
        Impersonation = 0x0002,
        Delegation = 0x0003,

        pub const MAX: IMPERSONATION_LEVEL = .Delegation;
        pub const MIN: IMPERSONATION_LEVEL = .Anonymous;
        pub const DEFAULT: IMPERSONATION_LEVEL = .Impersonation;

        pub fn isValid(self: IMPERSONATION_LEVEL) bool {
            return @intFromEnum(self) >= @intFromEnum(MIN) and @intFromEnum(self) <= @intFromEnum(MAX);
        }
    };

    /// - ref: um/winnt.h
    /// - ref: https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-lsad/6bb42770-b924-41ff-8a57-83e37b8b7797
    pub const CONTEXT_TRACKING_MODE = enum(BOOLEAN.Backing) {
        Static = 0,
        Dynamic = 1,
    };
};

pub const CON_DRV = struct {
    /// - ref: https://github.com/microsoft/terminal/dep/Console/condrv.h
    pub const IO_BUFFER = extern struct {
        Size: ULONG,
        Buffer: P(VOID),

        pub fn fromPtr(self: *IO_BUFFER, buffer_ptr: anytype) void {
            if (@typeInfo(@TypeOf(buffer_ptr)) != .pointer) {
                @compileError("expected a pointer");
            }
            const info = @typeInfo(@TypeOf(buffer_ptr)).pointer;

            self.Size = @sizeOf(info.child);
            self.Buffer = buffer_ptr;
        }

        pub fn fromSlice(self: *IO_BUFFER, slice: anytype) void {
            if (@typeInfo(@TypeOf(slice)) != .pointer) {
                @compileError("expected a slice");
            }
            const info = @typeInfo(@TypeOf(slice)).pointer;
            comptime std.debug.assert(info.size == .slice);

            self.Size = @sizeOf(info.child) * slice.len;
            self.Buffer = slice.ptr;
        }

        pub fn fromArr(self: *IO_BUFFER, arr: anytype) void {
            if (@typeInfo(@TypeOf(arr)) != .pointer) {
                @compileError("expected a pointer to an array");
            }
            const ptr_info = @typeInfo(@TypeOf(arr)).pointer;
            comptime std.debug.assert(ptr_info.size == .one);

            const info = @typeInfo(ptr_info.child).array;

            self.Size = @sizeOf(info.child) * info.len;
            self.Buffer = arr;
        }
    };

    /// - ref: https://github.com/microsoft/terminal/dep/Console/condrv.h
    pub fn USER_DEFINED_IO(comptime InputCount: comptime_int, comptime OutputCount: comptime_int) type {
        return extern struct {
            Client: ?HANDLE = null,
            InputCount: ULONG = InputCount,
            OutputCount: ULONG = OutputCount,
            Buffers: [InputCount + OutputCount]IO_BUFFER = undefined,
        };
    }
};

pub const CONSOLE = struct {
    pub const CODEPAGE = @import("codepage.zig").CODEPAGE;

    /// - ref: shared/ntdef.h
    pub const HCURSOR = HANDLE;

    /// - ref: shared/wtypes.h
    pub const HMENU = HANDLE;

    /// - ref: shared/wtypes.h
    pub const HPALETTE = HANDLE;

    /// - ref: um/consoleapi.h
    pub const MODE = extern union {
        Input: INPUT,
        Output: OUTPUT,

        pub const INPUT = packed struct(ULONG) {
            ENABLE_PROCESSED_INPUT: bool = false,
            ENABLE_LINE_INPUT: bool = false,
            ENABLE_ECHO_INPUT: bool = false,
            ENABLE_WINDOW_INPUT: bool = false,
            ENABLE_MOUSE_INPUT: bool = false,
            ENABLE_INSERT_MODE: bool = false,
            ENABLE_QUICK_EDIT_MODE: bool = false,
            ENABLE_EXTENDED_FLAGS: bool = false,
            ENABLE_AUTO_POSITION: bool = false,
            ENABLE_VIRTUAL_TERMINAL_INPUT: bool = false,
            Unused10: u22 = 0,
        };

        pub const OUTPUT = packed struct(ULONG) {
            ENABLE_PROCESSED_OUTPUT: bool = false,
            ENABLE_WRAP_AT_EOL_OUTPUT: bool = false,
            ENABLE_VIRTUAL_TERMINAL_PROCESSING: bool = false,
            DISABLE_NEWLINE_AUTO_RETURN: bool = false,
            ENABLE_LVB_GRID_WORLDWIDE: bool = false,
            Unused5: u27 = 0,
        };
    };

    /// - ref: https://github.com/microsoft/terminal/dep/Console/conmsgl2.h
    pub const ELEMENT_TYPE = enum(ULONG) {
        ASCII,
        REAL_UNICODE,
        ATTRIBUTE,
        FALSE_UNICODE,
        _,
    };

    /// - ref: um/consoleapi3.h
    pub const DISPLAY_MODE = packed struct(ULONG) {
        FULLSCREEN_MODE: bool = false,
        WINDOWED_MODE: bool = false,
        Unused2: u30 = 0,
    };

    /// - ref: um/wincontypes.h
    pub const CONTROL_KEY_STATE = packed struct(ULONG) {
        RIGHT_ALT_PRESSED: bool = false,
        LEFT_ALT_PRESSED: bool = false,
        RIGHT_CTRL_PRESSED: bool = false,
        LEFT_CTRL_PRESSED: bool = false,
        SHIFT_PRESSED: bool = false,
        NUMLOCK_ON: bool = false,
        SCROLLLOCK_ON: bool = false,
        CAPSLOCK_ON: bool = false,
        ENHANCED_KEY: bool = false,
        Unused9: u7 = 0,
        /// DBCS for JPN: SBCS/DBCS mode.
        NLS_DBCSCHAR: bool = false,
        // NOTE(freemaker): here this one is listed NLS_APLHANUMERIC with 0x00000000 ('DBCS for JPN: Alphanumeric mode.')
        /// DBCS for JPN: Katakana mode.
        NLS_KATAKANA: bool = false,
        /// DBCS for JPN: Hiragana mode.
        NLS_HIRAGANA: bool = false,
        Unused19: u3 = 0,
        /// DBCS for JPN: Roman/Noroman mode.
        NLS_ROMAN: bool = false,
        /// DBCS for JPN: IME conversion.
        NLS_IME_CONVERSION: bool = false,
        Unused24: u2 = 0,
        /// AltNumpad OEM char (copied from ntuser\inc\kbd.h) ;internal_NT
        ALTNUMPAD_BIT: bool = false,
        Unused27: u2 = 0,
        /// DBCS for JPN: IME enable/disable.
        NLS_IME_DISABLE: bool = false,
        Unused30: u2 = 0,
    };

    /// - ref: um/wincontypes.h
    pub const INPUT_RECORD = extern struct {
        EventType: EVENT_TYPE,
        Event: EVENT,

        /// NOTE(freemaker): these are specified as flags
        /// but are used as an enum
        pub const EVENT_TYPE = enum(WORD) {
            KEY = 0x0001,
            MOUSE = 0x0002,
            WINDOW_BUFFER_SIZE = 0x0004,
            MENU = 0x0008,
            FOCUS = 0x0010,
            _,
        };

        pub const EVENT = extern union {
            Key: KEY_EVENT,
            Mouse: MOUSE_EVENT,
            WindowBufferSize: WINDOW_BUFFER_SIZE_EVENT,
            Menu: MENU_EVENT,
            Focus: FOCUS_EVENT,
        };

        pub const KEY_EVENT = extern struct {
            bKeyDown: BOOL,
            wRepeatCount: WORD,
            wVirtualKeyCode: WORD,
            wVirtualScanCode: WORD,
            uChar: extern union {
                Unicode: WCHAR,
                Ascii: CHAR,
            },
            dwControlKeyState: CONTROL_KEY_STATE,
        };

        pub const MOUSE_EVENT = extern struct {
            dwMousePosition: COORD,
            dwButtonState: BUTTON_STATE,
            dwControlKeyState: CONTROL_KEY_STATE,
            dwEventFlags: FLAGS,

            pub const BUTTON_STATE = packed struct(DWORD) {
                // ref: https://github.com/microsoft/terminal/src/terminal/parser/InputStateMachineEngine.cpp

                /// usually left mouse button
                FROM_LEFT_1ST_BUTTON_PRESSED: bool = false,
                /// usually right mouse button
                RIGHTMOST_BUTTON_PRESSED: bool = false,
                /// usually middle mouse button
                FROM_LEFT_2ND_BUTTON_PRESSED: bool = false,
                FROM_LEFT_3RD_BUTTON_PRESSED: bool = false,
                FROM_LEFT_4TH_BUTTON_PRESSED: bool = false,
                Unused5: u17 = 0,
                /// - ref: https://github.com/microsoft/terminal/src/terminal/parser/InputStateMachineEngine.hpp
                SCROLL_DELTA: bool = false,
                Unused23: u9 = 0,

                /// - ref: https://github.com/microsoft/terminal/src/terminal/parser/InputStateMachineEngine.hpp
                pub fn isScrollDeltaForward(self: BUTTON_STATE) bool {
                    return self.SCROLL_DELTA and @as(DWORD, @bitCast(self)) & 0xFF000000 == 0;
                }

                /// - ref: https://github.com/microsoft/terminal/src/terminal/parser/InputStateMachineEngine.hpp
                pub fn isScrollDeltaBackward(self: BUTTON_STATE) bool {
                    return self.SCROLL_DELTA and @as(DWORD, @bitCast(self)) & 0xFF000000 != 0;
                }

                pub fn getWheelDirection(self: BUTTON_STATE) WHEEL_DIRECTION {
                    std.debug.assert(self.SCROLL_DELTA);

                    return if (self.isScrollDeltaForward())
                        .FORWARD
                    else
                        .BACKWARD;
                }

                pub const WHEEL_DIRECTION = enum(u1) {
                    FORWARD,
                    BACKWARD,
                };
            };

            pub const FLAGS = packed struct(DWORD) {
                MOVED: bool = false,
                DOUBLE_CLICK: bool = false,
                WHEELED: bool = false,
                HWHEELED: bool = false,
                Unused4: u28 = 0,
            };
        };

        pub const WINDOW_BUFFER_SIZE_EVENT = extern struct {
            dwSize: COORD,
        };

        pub const MENU_EVENT = extern struct {
            dwCommandId: UINT,
        };

        pub const FOCUS_EVENT = extern struct {
            bSetFocus: BOOL,
        };
    };

    /// - ref: https://github.com/microsoft/terminal/dep/Console/conmsgl1.h
    pub const HEADER = extern struct {
        ApiNumber: API_NUMBER,
        ApiDescriptorSize: ULONG,

        pub const API_NUMBER = packed struct(ULONG) {
            Function: u24 = 0,
            Layer: LAYER = .None,

            pub fn L1(func: L1Func) API_NUMBER {
                return API_NUMBER{
                    .Layer = .L1,
                    .Function = @intFromEnum(func),
                };
            }

            pub fn L2(func: L2Func) API_NUMBER {
                return API_NUMBER{
                    .Layer = .L2,
                    .Function = @intFromEnum(func),
                };
            }

            pub fn L3(func: L3Func) API_NUMBER {
                return API_NUMBER{
                    .Layer = .L3,
                    .Function = @intFromEnum(func),
                };
            }

            pub const LAYER = enum(u8) {
                None = 0,
                L1 = 1,
                L2 = 2,
                L3 = 3,
                _,
            };

            pub const L1Func = enum(u24) {
                GetCP,
                GetMode,
                SetMode,
                GetNumberOfInputEvents,
                GetConsoleInput,
                ReadConsole,
                WriteConsole,
                /// - *DEPRECATED*
                NotifyLastClose,
                GetLangId,
                /// - *DEPRECATED*
                MapBitmap,
            };

            pub const L2Func = enum(u24) {
                FillConsoleOutput,
                GenerateCtrlEvent,
                SetActiveScreenBuffer,
                FlushInputBuffer,
                SetCP,
                GetCursorInfo,
                SetCursorInfo,
                GetScreenBufferInfo,
                SetScreenBufferInfo,
                SetScreenBufferSize,
                SetCursorPosition,
                GetLargestWindowSize,
                ScrollScreenBuffer,
                SetTextAttribute,
                SetWindowInfo,
                ReadConsoleOutputString,
                WriteConsoleInput,
                WriteConsoleOutput,
                WriteConsoleOutputString,
                ReadConsoleOutput,
                GetTitle,
                SetTitle,
            };

            pub const L3Func = enum(u24) {
                GetNumberOfFonts,
                GetMouseInfo,
                GetFontInfo,
                GetFontSize,
                GetCurrentFont,
                SetFont,
                SetIcon,
                InvalidateBitmapRect,
                VDMOperation,
                SetCursor,
                ShowCursor,
                MenuControl,
                SetPalette,
                SetDisplayMode,
                RegisterVDM,
                GetHardwareState,
                SetHardwareState,
                GetDisplayMode,
                AddAlias,
                GetAlias,
                GetAliasesLength,
                GetAliasExesLength,
                GetAliases,
                GetAliasExes,
                ExpungeCommandHistory,
                SetNumberOfCommands,
                GetCommandHistoryLength,
                GetCommandHistory,
                SetKeyShortcuts,
                SetMenuClose,
                GetKeyboardLayoutName,
                GetConsoleWindow,
                CharType,
                SetLocalEUDC,
                SetCursorMode,
                GetCursorMode,
                RegisterOS2,
                SetOS2OemFormat,
                GetNlsMode,
                SetNlsMode,
                GetSelectionInfo,
                GetConsoleProcessList,
                GetHistory,
                SetHistory,
                SetCurrentFont,
            };
        };
    };

    /// - ref: https://github.com/microsoft/terminal/dep/Console/conmsgl1.h
    pub fn MSG(comptime BodyT: type, comptime api: HEADER.API_NUMBER) type {
        return extern struct {
            Header: HEADER = .{
                .ApiNumber = api,
                .ApiDescriptorSize = @sizeOf(BodyT),
            },
            Body: BodyT = undefined,
        };
    }

    // ref: https://github.com/microsoft/terminal/dep/Console/conmsgl1.h

    pub const GetCPMsg = MSG(GETCP_BODY, .L1(.GetCP));
    pub const GETCP_BODY = extern struct {
        /// - *OUT*
        CodePage: CODEPAGE,
        /// - *IN*
        Output: BOOLEAN,
    };

    pub const GetModeMsg = MSG(MODE_BODY, .L1(.GetMode));
    pub const SetModeMsg = MSG(MODE_BODY, .L1(.SetMode));
    pub const MODE_BODY = extern struct {
        /// - *IN*
        /// - *OUT*
        Mode: MODE,
    };

    pub const GetNumberOfInputEventsMsg = MSG(NUMBEROFINPUTEVENTS_BODY, .L1(.GetNumberOfInputEvents));
    pub const NUMBEROFINPUTEVENTS_BODY = extern struct {
        /// - *OUT*
        ReadyEvents: ULONG,
    };

    /// uses 1 output IO_BUFFER of type [*]INPUT_RECORD
    pub const GetConsoleInputMsg = MSG(INPUT_BODY, .L1(.GetConsoleInput));
    pub const INPUT_BODY = extern struct {
        /// - *OUT*
        NumRecords: ULONG,
        /// - *IN*
        Flags: FLAGS = .{},
        /// - *IN*
        Unicode: BOOLEAN,

        /// - ref: https://github.com/microsoft/terminal/dep/Console/ntcon.h
        pub const FLAGS = packed struct(USHORT) {
            READ_NOREMOVE: bool = false,
            READ_NOWAIT: bool = false,
            Unused2: u14 = 0,

            pub const READ_VALID: FLAGS = .{
                .READ_NOREMOVE = true,
                .READ_NOWAIT = true,
                .Unused2 = 0,
            };
        };
    };

    pub const ReadConsoleMsg = MSG(READ_BODY, .L1(.ReadConsole));
    pub const READ_BODY = extern struct {
        /// - *IN*
        Unicode: BOOLEAN,
        /// - *IN*
        ProcessControlZ: BOOLEAN,
        /// - *IN*
        ExecNameLength: USHORT,
        /// - *IN*
        InitialNumBytes: ULONG,
        /// - *IN*
        CtrlWakeupMask: CTRL_WAKEUP_MASK,
        /// - *OUT*
        ControlKeyState: CONTROL_KEY_STATE,
        /// - *OUT*
        NumBytes: ULONG,

        pub const CTRL_WAKEUP_MASK = packed struct(ULONG) {
            NullCharacter: bool = false,
            StartOfHeader: bool = false,
            StartOfText: bool = false,
            EndOfText: bool = false,
            EndOfTransmission: bool = false,
            Enquiry: bool = false,
            Acknowledge: bool = false,
            Bell: bool = false,
            Backspace: bool = false,
            HorizontalTab: bool = false,
            LineFeed: bool = false,
            VerticalTabulation: bool = false,
            FormFeed: bool = false,
            CarriageReturn: bool = false,
            ShiftOut: bool = false,
            ShiftIn: bool = false,
            DataLinkEscape: bool = false,
            DeviceControlOne: bool = false,
            DeviceControlTwo: bool = false,
            DeviceControlThree: bool = false,
            DeviceControlFour: bool = false,
            NegativeAcknowledge: bool = false,
            SynchronousIdle: bool = false,
            EndOfTransmissionBlock: bool = false,
            Cancel: bool = false,
            EndOfMedium: bool = false,
            Substitute: bool = false,
            Escape: bool = false,
            FileSeparator: bool = false,
            GroupSeparator: bool = false,
            RecordSeparator: bool = false,
            UnitSeparator: bool = false,
        };
    };

    pub const WriteConsoleMsg = MSG(WRITE_BODY, .L1(.WriteConsole));
    pub const WRITE_BODY = extern struct {
        /// - *OUT*
        NumBytes: ULONG,
        /// - *IN*
        Unicode: BOOLEAN,
    };

    /// - *DEPRECATED*
    pub const NotifyLastCloseMsg = MSG(void, .L1(.NotifyLastClose));

    pub const GetLangIdMsg = MSG(LANGID_BODY, .L1(.GetLangId));
    pub const LANGID_BODY = extern struct {
        /// - *OUT*
        LangId: LANGID,
    };

    /// - *DEPRECATED*
    pub const MapBitmapMsg = MSG(MAPBITMAP_BODY, .L1(.MapBitmap));
    /// - *DEPRECATED*
    pub const MAPBITMAP_BODY = extern struct {
        /// - *OUT*
        Mutex: ?HANDLE,
        /// - *OUT*
        Bitmap: ?P(VOID),
    };

    // ref: https://github.com/microsoft/terminal/dep/Console/conmsgl2.h

    pub const FillConsoleOutputMsg = MSG(FILLCONSOLEOUTPUT_BODY, .L2(.FillConsoleOutput));
    pub const FILLCONSOLEOUTPUT_BODY = extern struct {
        /// - *IN*
        WriteCoord: COORD,
        /// - *IN*
        ElementType: ELEMENT_TYPE,
        /// - *IN*
        Element: USHORT,
        /// - *IN*
        /// - *OUT*
        Length: ULONG,
    };

    pub const GenerateCtrlEventMsg = MSG(CTRLEVENT_BODY, .L2(.GenerateCtrlEvent));
    pub const CTRLEVENT_BODY = extern struct {
        /// - *IN*
        CtrlEvent: CTRL_EVENT,
        /// - *IN*
        ProcessGroupId: ULONG,

        pub const CTRL_EVENT = enum(ULONG) {
            C,
            BREAK,
            CLOSE,
            Reserved3,
            Reserved4,
            LOGOFF,
            SHUTDOWN,
            _,
        };
    };

    pub const SetActiveScreenBufferMsg = MSG(void, .L2(.SetActiveScreenBuffer));
    pub const FlushInputBufferMsg = MSG(void, .L2(.FlushInputBuffer));

    pub const SetCPMsg = MSG(SETCP_BODY, .L2(.SetCP));
    pub const SETCP_BODY = extern struct {
        /// - *IN*
        CodePage: CODEPAGE,
        /// - *IN*
        Output: BOOLEAN,
    };

    pub const GetCursorInfoMsg = MSG(GETCURSORINFO_BODY, .L2(.GetCursorInfo));
    pub const GETCURSORINFO_BODY = extern struct {
        /// - *OUT*
        CursorSize: ULONG,
        /// - *OUT*
        Visible: BOOLEAN,
    };

    pub const SetCursorInfoMsg = MSG(SETCURSORINFO_BODY, .L2(.SetCursorInfo));
    pub const SETCURSORINFO_BODY = extern struct {
        /// - *IN*
        CursorSize: ULONG,
        /// - *IN*
        Visible: BOOLEAN,
    };

    pub const GetScreenBufferInfoMsg = MSG(SCREENBUFFERINFO_BODY, .L2(.GetScreenBufferInfo));
    pub const SetScreenBufferInfoMsg = MSG(SCREENBUFFERINFO_BODY, .L2(.SetScreenBufferInfo));
    pub const SCREENBUFFERINFO_BODY = extern struct {
        /// - *IN*
        /// - *OUT*
        Size: COORD,
        /// - *IN*
        /// - *OUT*
        CursorPosition: COORD,
        /// - *IN*
        /// - *OUT*
        ScrollPosition: COORD,
        /// - *IN*
        /// - *OUT*
        Attributes: TEXT_ATTRIBUTES,
        /// - *IN*
        /// - *OUT*
        CurrentWindowSize: COORD,
        /// - *IN*
        /// - *OUT*
        MaximumWindowSize: COORD,
        /// - *IN*
        /// - *OUT*
        PopupAttributes: TEXT_ATTRIBUTES,
        /// - *IN*
        /// - *OUT*
        FullscreenSupported: BOOLEAN,
        /// - *IN*
        /// - *OUT*
        ColorTable: [16]COLORREF,
    };

    pub const SetScreenBufferSizeMsg = MSG(SETSCREENBUFFERSIZE_BODY, .L2(.SetScreenBufferSize));
    pub const SETSCREENBUFFERSIZE_BODY = extern struct {
        /// - *IN*
        Size: COORD,
    };

    pub const SetCursorPositionMsg = MSG(SETCURSORPOSITION_BODY, .L2(.SetCursorPosition));
    pub const SETCURSORPOSITION_BODY = extern struct {
        /// - *IN*
        CursorPosition: COORD,
    };

    pub const GetLargestWindowSizeMsg = MSG(GETLARGESTWINDOWSIZE_BODY, .L2(.GetLargestWindowSize));
    pub const GETLARGESTWINDOWSIZE_BODY = extern struct {
        /// - *OUT*
        Size: COORD,
    };

    pub const ScrollScreenBufferMsg = MSG(SCROLLSCREENBUFFER_BODY, .L2(.ScrollScreenBuffer));
    pub const SCROLLSCREENBUFFER_BODY = extern struct {
        /// - *IN*
        ScrollRectangle: SMALL_RECT,
        /// - *IN*
        ClipRectangle: SMALL_RECT,
        /// - *IN*
        Clip: BOOLEAN,
        /// - *IN*
        Unicode: BOOLEAN,
        /// - *IN*
        DestinationOrigin: COORD,
        /// - *IN*
        Fill: CHAR_INFO,
    };

    pub const SetTextAttributeMsg = MSG(SETTEXTATTRIBUTE_BODY, .L2(.SetTextAttribute));
    pub const SETTEXTATTRIBUTE_BODY = extern struct {
        /// - *IN*
        Attributes: TEXT_ATTRIBUTES,
    };

    pub const SetWindowInfoMsg = MSG(SETWINDOWINFO_BODY, .L2(.SetWindowInfo));
    pub const SETWINDOWINFO_BODY = extern struct {
        /// - *IN*
        Absolute: BOOLEAN,
        /// - *IN*
        Window: SMALL_RECT,
    };

    pub const ReadConsoleOutputStringMsg = MSG(READCONSOLEOUTPUTSTRING_BODY, .L2(.ReadConsoleOutputString));
    pub const READCONSOLEOUTPUTSTRING_BODY = extern struct {
        /// - *IN*
        ReadCoord: COORD,
        /// - *IN*
        StringType: ELEMENT_TYPE,
        /// - *OUT*
        NumRecords: ULONG,
    };

    pub const WriteConsoleInputMsg = MSG(WRITECONSOLEINPUT_BODY, .L2(.WriteConsoleInput));
    pub const WRITECONSOLEINPUT_BODY = extern struct {
        /// - *OUT*
        NumRecords: ULONG,
        /// - *IN*
        Unicode: BOOLEAN,
        /// - *IN*
        Append: BOOLEAN,
    };

    pub const WriteConsoleOutputMsg = MSG(WRITECONSOLEOUTPUT_BODY, .L2(.WriteConsoleOutput));
    pub const WRITECONSOLEOUTPUT_BODY = extern struct {
        /// - *IN*
        /// - *OUT*
        CharRegion: SMALL_RECT,
        /// - *IN*
        Unicode: BOOLEAN,
    };

    pub const WriteConsoleOutputStringMsg = MSG(WRITECONSOLEOUTPUTSTRING_BODY, .L2(.WriteConsoleOutputString));
    pub const WRITECONSOLEOUTPUTSTRING_BODY = extern struct {
        /// - *IN*
        WriteCoord: COORD,
        /// - *IN*
        StringType: ELEMENT_TYPE,
        /// - *OUT*
        NumRecords: ULONG,
    };

    pub const ReadConsoleOutput = MSG(READCONSOLEOUTPUT_BODY, .L2(.ReadConsoleOutput));
    pub const READCONSOLEOUTPUT_BODY = extern struct {
        /// - *IN*
        /// - *OUT*
        CharRegion: SMALL_RECT,
        /// - *IN*
        Unicode: BOOLEAN,
    };

    pub const GetTitleMsg = MSG(GETTITLE_BODY, .L2(.GetTitle));
    pub const GETTITLE_BODY = extern struct {
        /// - *OUT*
        TitleLength: ULONG,
        /// - *IN*
        Unicode: BOOLEAN,
        /// - *IN*
        Original: BOOLEAN,
    };

    pub const SetTitleMsg = MSG(SETTITLE_BODY, .L2(.SetTitle));
    pub const SETTITLE_BODY = extern struct {
        /// - *IN*
        Unicode: BOOLEAN,
    };

    // ref: https://github.com/microsoft/terminal/dep/Console/conmsgl3.h

    /// - *DEPRECATED*
    pub const GetNumberOfFontsMsg = MSG(GETNUMBEROFFONTS_BODY, .L3(.GetNumberOfFonts));
    /// - *DEPRECATED*
    pub const GETNUMBEROFFONTS_BODY = extern struct {
        /// - *OUT*
        NumberOfFonts: ULONG,
    };

    pub const GetMouseInfoMsg = MSG(GETMOUSEINFO_BODY, .L3(.GetMouseInfo));
    pub const GETMOUSEINFO_BODY = extern struct {
        /// - *OUT*
        NumButtons: ULONG,
    };

    /// - *DEPRECATED*
    pub const GetFontInfoMsg = MSG(GETFONTINFO_BODY, .L3(.GetFontInfo));
    /// - *DEPRECATED*
    pub const GETFONTINFO_BODY = extern struct {
        /// - *IN*
        MaximumWindow: BOOLEAN,
        /// - *OUT*
        NumFonts: ULONG, // This value is valid even for error cases
    };

    pub const GetFontSizeMsg = MSG(GETFONTSIZE_BODY, .L3(.GetFontSize));
    pub const GETFONTSIZE_BODY = extern struct {
        /// - *IN*
        FontIndex: ULONG,
        /// - *OUT*
        FontSize: COORD,
    };

    pub const GetCurrentFontMsg = MSG(CURRENTFONT_BODY, .L3(.GetCurrentFont));
    pub const CURRENTFONT_BODY = extern struct {
        /// - *IN*
        MaximumWindow: BOOLEAN,
        /// - *IN*
        /// - *OUT*
        FontIndex: ULONG,
        /// - *IN*
        /// - *OUT*
        FontSize: COORD,
        /// - *IN*
        /// - *OUT*
        FontFamily: ULONG,
        /// - *IN*
        /// - *OUT*
        FontWeight: ULONG,
        /// - *IN*
        /// - *OUT*
        FaceName: [LF_FACESIZE]WCHAR,
    };

    /// - *DEPRECATED*
    pub const SetFontMsg = MSG(SETFONT_BODY, .L3(.SetFont));
    /// - *DEPRECATED*
    pub const SETFONT_BODY = extern struct {
        /// - *IN*
        FontIndex: ULONG,
    };

    /// - *DEPRECATED*
    pub const SetIconMsg = MSG(SETICON_BODY, .L3(.SetIcon));
    /// - *DEPRECATED*
    pub const SETICON_BODY = extern struct {
        /// - *IN*
        hIcon: P(VOID),
    };

    /// - *DEPRECATED*
    pub const InvalidateBitmapRectMsg = MSG(INVALIDATEBITMAPRECT_BODY, .L3(.InvalidateBitmapRect));
    /// - *DEPRECATED*
    pub const INVALIDATEBITMAPRECT_BODY = extern struct {
        /// - *IN*
        Rect: SMALL_RECT,
    };

    /// - *DEPRECATED*
    pub const VDMOperationMsg = MSG(VDM_BODY, .L3(.VDMOperation));
    /// - *DEPRECATED*
    pub const VDM_BODY = extern struct {
        /// - *IN*
        iFunction: ULONG, // no related source found
        /// - *OUT*
        Bool: BOOLEAN, // no related source found
        /// - *IN*
        Point: POINT,
        /// - *OUT*
        Rect: RECT,
    };

    /// - *DEPRECATED*
    pub const SetCursorMsg = MSG(SETCURSOR_BODY, .L3(.SetCursor));
    /// - *DEPRECATED*
    pub const SETCURSOR_BODY = extern struct {
        /// - *IN*
        CursorHandle: HCURSOR,
    };

    /// - *DEPRECATED*
    pub const ShowCursorMsg = MSG(SHOWCURSOR_BODY, .L3(.ShowCursor));
    /// - *DEPRECATED*
    pub const SHOWCURSOR_BODY = extern struct {
        /// - *IN*
        bShow: BOOLEAN,
        /// - *OUT*
        DisplayCount: ULONG,
    };

    /// - *DEPRECATED*
    pub const MenuControlMsg = MSG(MENUCONTROL_BODY, .L3(.MenuControl));
    /// - *DEPRECATED*
    pub const MENUCONTROL_BODY = extern struct {
        /// - *IN*
        CommandIdLow: ULONG,
        /// - *IN*
        CommandIdHigh: ULONG,
        /// - *OUT*
        hMenu: HMENU,
    };

    /// - *DEPRECATED*
    pub const SetPaletteMsg = MSG(SETPALETTE_BODY, .L3(.SetPalette));
    /// - *DEPRECATED*
    pub const SETPALETTE_BODY = extern struct {
        /// - *IN*
        hPalette: HPALETTE,
        /// - *IN*
        dwUsage: ULONG,
    };

    pub const SetDisplayModeMsg = MSG(SETDISPLAYMODE_BODY, .L3(.SetDisplayMode));
    pub const SETDISPLAYMODE_BODY = extern struct {
        /// - *IN*
        dwFlags: ULONG,
        /// - *OUT*
        ScreenBufferDimensions: COORD,
    };

    /// - *DEPRECATED*
    pub const RegisterVDMMsg = MSG(REGISTERVDM_BODY, .L3(.RegisterVDM));
    /// - *DEPRECATED*
    pub const REGISTERVDM_BODY = extern struct {
        /// - *IN*
        RegisterFlags: ULONG, // no related source found
        /// - *IN*
        StartEvent: HANDLE,
        /// - *IN*
        EndEvent: HANDLE,
        /// - *IN*
        ErrorEvent: HANDLE,
        /// - *OUT*
        StateLength: ULONG,
        /// - *OUT*
        StateBuffer: P(VOID),
        /// - *OUT*
        VDMBuffer: P(VOID),
    };

    /// - *DEPRECATED*
    pub const GetHardwareStateMsg = MSG(GETHARDWARESTATE_BODY, .L3(.GetHardwareState));
    /// - *DEPRECATED*
    pub const GETHARDWARESTATE_BODY = extern struct {
        /// - *OUT*
        Resolution: COORD,
        /// - *OUT*
        FontSize: COORD,
    };

    /// - *DEPRECATED*
    pub const SetHardwareStateMsg = MSG(SETHARDWARESTATE_BODY, .L3(.SetHardwareState));
    /// - *DEPRECATED*
    pub const SETHARDWARESTATE_BODY = extern struct {
        /// - *IN*
        Resolution: COORD,
        /// - *IN*
        FontSize: COORD,
    };

    pub const GetDisplayModeMsg = MSG(GETDISPLAYMODE_BODY, .L3(.GetDisplayMode));
    pub const GETDISPLAYMODE_BODY = extern struct {
        /// - *OUT*
        ModeFlags: DISPLAY_MODE,
    };

    pub const AddAliasMsg = MSG(ADDALIAS_BODY, .L3(.AddAlias));
    pub const ADDALIAS_BODY = extern struct {
        /// - *IN*
        SourceLength: USHORT,
        /// - *IN*
        TargetLength: USHORT,
        /// - *IN*
        ExeLength: USHORT,
        /// - *IN*
        Unicode: BOOLEAN,
    };

    pub const GetAliasMsg = MSG(GETALIAS_BODY, .L3(.GetAlias));
    pub const GETALIAS_BODY = extern struct {
        /// - *IN*
        SourceLength: USHORT,
        /// - *OUT*
        TargetLength: USHORT,
        /// - *IN*
        ExeLength: USHORT,
        /// - *IN*
        Unicode: BOOLEAN,
    };

    pub const GetAliasesLengthMsg = MSG(GETALIASESLENGTH_BODY, .L3(.GetAliasesLength));
    pub const GETALIASESLENGTH_BODY = extern struct {
        /// - *OUT*
        AliasesLength: ULONG,
        /// - *IN*
        Unicode: BOOLEAN,
    };

    pub const GetAliasExesLengthMsg = MSG(GETALIASEXESLENGTH_BODY, .L3(.GetAliasExesLength));
    pub const GETALIASEXESLENGTH_BODY = extern struct {
        /// - *OUT*
        AliasExesLength: ULONG,
        /// - *IN*
        Unicode: BOOLEAN,
    };

    pub const GetAliasesMsg = MSG(GETALIASES_BODY, .L3(.GetAliases));
    pub const GETALIASES_BODY = extern struct {
        /// - *IN*
        Unicode: BOOLEAN,
        /// - *OUT*
        AliasesBufferLength: ULONG,
    };

    pub const GetAliasExesMsg = MSG(GETALIASEXES_BODY, .L3(.GetAliasExes));
    pub const GETALIASEXES_BODY = extern struct {
        /// - *OUT*
        AliasExesBufferLength: ULONG,
        /// - *IN*
        Unicode: BOOLEAN,
    };

    pub const ExpungeCommandHistoryMsg = MSG(EXPUNGECOMMANDHISTORY_BODY, .L3(.ExpungeCommandHistory));
    pub const EXPUNGECOMMANDHISTORY_BODY = extern struct {
        /// - *IN*
        Unicode: BOOLEAN,
    };

    pub const SetNumberOfCommandsMsg = MSG(SETNUMBEROFCOMMANDS_BODY, .L3(.SetNumberOfCommands));
    pub const SETNUMBEROFCOMMANDS_BODY = extern struct {
        /// - *IN*
        NumCommands: ULONG,
        /// - *IN*
        Unicode: BOOLEAN,
    };

    pub const GetCommandHistoryLengthMsg = MSG(GETCOMMANDHISTORYLENGTH_BODY, .L3(.GetCommandHistoryLength));
    pub const GETCOMMANDHISTORYLENGTH_BODY = extern struct {
        /// - *OUT*
        CommandHistoryLength: ULONG,
        /// - *IN*
        Unicode: BOOLEAN,
    };

    pub const GetCommandHistoryMsg = MSG(GETCOMMANDHISTORY_BODY, .L3(.GetCommandHistory));
    pub const GETCOMMANDHISTORY_BODY = extern struct {
        /// - *OUT*
        CommandBufferLength: ULONG,
        /// - *IN*
        Unicode: BOOLEAN,
    };

    /// - *DEPRECATED*
    pub const SetKeyShortcutsMsg = MSG(SETKEYSHORTCUTS_BODY, .L3(.SetKeyShortcuts));
    /// - *DEPRECATED*
    pub const SETKEYSHORTCUTS_BODY = extern struct {
        /// - *IN*
        Set: BOOLEAN,
        /// - *IN*
        ReserveKeys: BYTE, // no related source found
    };

    /// - *DEPRECATED*
    pub const SetMenuCloseMsg = MSG(SETMENUCLOSE_BODY, .L3(.SetMenuClose));
    /// - *DEPRECATED*
    pub const SETMENUCLOSE_BODY = extern struct {
        /// - *IN*
        Enable: BOOLEAN,
    };

    /// - *DEPRECATED*
    pub const GetKeyboardLayoutNameMsg = MSG(GETKEYBOARDLAYOUTNAME_BODY, .L3(.GetKeyboardLayoutName));
    /// - *DEPRECATED*
    pub const GETKEYBOARDLAYOUTNAME_BODY = extern struct {
        Layout: extern union {
            awch: [9]WCHAR,
            ach: [9]CHAR,
        },
        bAnsi: BOOLEAN,
    };

    pub const GetConsoleWindowMsg = MSG(GETCONSOLEWINDOW_BODY, .L3(.GetConsoleWindow));
    pub const GETCONSOLEWINDOW_BODY = extern struct {
        /// - *OUT*
        hwnd: HWND,
    };

    /// - *DEPRECATED*
    pub const CharTypeMsg = MSG(CHARTYPE_BODY, .L3(.CharType));
    /// - *DEPRECATED*
    pub const CHARTYPE_BODY = extern struct {
        /// - *IN*
        coordCheck: COORD,
        /// - *OUT*
        dwType: ULONG, // no related source found
    };

    /// - *DEPRECATED*
    pub const SetLocalEUDCMsg = MSG(LOCALEUDC_BODY, .L3(.SetLocalEUDC));
    /// - *DEPRECATED*
    pub const LOCALEUDC_BODY = extern struct {
        /// - *IN*
        CodePoint: USHORT,
        /// - *IN*
        FontSize: COORD,
    };

    /// - *DEPRECATED*
    pub const SetCursorModeMsg = MSG(CURSORMODE_BODY, .L3(.SetCursorMode));
    /// - *DEPRECATED*
    pub const GetCursorModeMsg = MSG(CURSORMODE_BODY, .L3(.GetCursorMode));
    /// - *DEPRECATED*
    pub const CURSORMODE_BODY = extern struct {
        /// - *IN*
        /// - *OUT*
        Blink: BOOLEAN,
        /// - *IN*
        /// - *OUT*
        DBEnable: BOOLEAN,
    };

    /// - *DEPRECATED*
    pub const RegisterOS2Msg = MSG(REGISTEROS2_BODY, .L3(.RegisterOS2));
    /// - *DEPRECATED*
    pub const REGISTEROS2_BODY = extern struct {
        /// - *IN*
        fOs2Register: BOOLEAN,
    };

    /// - *DEPRECATED*
    pub const SetOS2OemFormatMsg = MSG(SETOS2OEMFORMAT_BODY, .L3(.SetOS2OemFormat));
    /// - *DEPRECATED*
    pub const SETOS2OEMFORMAT_BODY = extern struct {
        /// - *IN*
        fOs2OemFormat: BOOLEAN,
    };

    /// - *DEPRECATED*
    pub const GetNlsModeMsg = MSG(NLSMODE_BODY, .L3(.GetNlsMode));
    /// - *DEPRECATED*
    pub const SetNlsModeMsg = MSG(NLSMODE_BODY, .L3(.SetNlsMode));
    /// - *DEPRECATED*
    pub const NLSMODE_BODY = extern struct {
        /// - *IN*
        /// - *OUT*
        Ready: BOOLEAN,
        /// - *IN*
        NlsMode: ULONG, // no related source found
    };

    pub const GetSelectionInfoMsg = MSG(GETSELECTIONINFO_BODY, .L3(.GetSelectionInfo));
    pub const GETSELECTIONINFO_BODY = extern struct {
        /// - *OUT*
        SelectionInfo: SELECTION_INFO,

        /// - ref: um/consoleapi3.h
        pub const SELECTION_INFO = extern struct {
            dwFlags: Flags,
            dwSelectionAnchor: COORD,
            srSelection: SMALL_RECT,

            pub const Flags = packed struct(DWORD) {
                pub const NO_SELECTION: Flags = .{};

                SELECTION_IN_PROGRESS: bool = false,
                SELECTION_NOT_EMPTY: bool = false,
                MOUSE_SELECTION: bool = false,
                MOUSE_DOWN: bool = false,
                Unused4: u28 = 0,
            };
        };
    };

    pub const GetConsoleProcessListMsg = MSG(GETCONSOLEPROCESSLIST_BODY, .L3(.GetConsoleProcessList));
    pub const GETCONSOLEPROCESSLIST_BODY = extern struct {
        /// - *OUT*
        dwProcessCount: ULONG,
    };

    pub const GetHistoryMsg = MSG(HISTORY_BODY, .L3(.GetHistory));
    pub const SetHistoryMsg = MSG(HISTORY_BODY, .L3(.SetHistory));
    pub const HISTORY_BODY = extern struct {
        /// - *OUT*
        HistoryBufferSize: ULONG,
        /// - *OUT*
        NumberOfHistoryBuffers: ULONG,
        /// - *OUT*
        dwFlags: Flags,

        pub const Flags = packed struct(ULONG) {
            NO_DUP: bool = false,
            Unused1: u31 = 0,
        };
    };

    pub const SetCurrentFontMsg = MSG(CURRENTFONT_BODY, .L3(.SetCurrentFont));
};

// -------------------------------
// |          Functions          |
// -------------------------------

/// - ref: um/winternl.h
/// - version: WIN2K - ...
pub extern "ntdll" fn NtWaitForSingleObject(
    Handle: HANDLE,
    Alertable: BOOLEAN,
    Timeout: ?*const LARGE_INTEGER,
) callconv(.winapi) NTSTATUS;

/// - ref: km/ntifs.h
/// - version: WIN2K - ...
pub extern "ntdll" fn NtClose(
    IN_Handle: HANDLE,
) callconv(.winapi) NTSTATUS;

/// - ref: km/ntifs.h
/// - version: WIN2K - ...
pub extern "ntdll" fn NtOpenFile(
    OUT_FileHandle: P(HANDLE),
    IN_DesiredAccess: ACCESS_MASK,
    IN_ObjectAttributes: PC(OBJECT.ATTRIBUTES),
    OUT_IoStatusBlock: P(IO_STATUS_BLOCK),
    IN_ShareAccess: FILE.SHARE,
    IN_OpenOptions: FILE.MODE,
) callconv(.winapi) NTSTATUS;

/// - ref: km/ntifs.h
/// - version: WIN2K - ...
pub extern "ntdll" fn NtDeviceIoControlFile(
    IN_FileHandle: HANDLE,
    IN_Event: ?HANDLE,
    IN_ApcRoutine: ?PC(IO_APC_ROUTINE),
    IN_ApcContext: ?P(VOID),
    OUT_IoStatusBlock: P(IO_STATUS_BLOCK),
    IN_IoControlCode: IO_CONTROL_CODE,
    IN_InputBuffer: ?P(VOID),
    IN_InputBufferLength: ULONG,
    OUT_OutputBuffer: ?P(VOID),
    IN_OutputBufferLength: ULONG,
) callconv(.winapi) NTSTATUS;

/// - ref: <phnt>/ntioapi.h
/// - ref: https://learn.microsoft.com/en-us/windows/win32/devnotes/nt-create-named-pipe-file
/// - version: unknown
pub extern "ntdll" fn NtCreateNamedPipeFile(
    OUT_FileHandle: P(HANDLE),
    IN_DesiredAccess: ACCESS_MASK,
    IN_ObjectAttributes: PC(OBJECT.ATTRIBUTES),
    OUT_IoStatusBlock: P(IO_STATUS_BLOCK),
    IN_ShareAccess: FILE.SHARE,
    IN_CreateDisposition: FILE.CREATE_DISPOSITION,
    IN_CreateOptions: FILE.MODE,
    IN_NamedPipeType: FILE.PIPE.TYPE,
    IN_ReadMode: FILE.PIPE.READ_MODE,
    IN_CompletionMode: FILE.PIPE.COMPLETION_MODE,
    IN_MaximumInstances: ULONG,
    IN_InboundQuota: ULONG,
    IN_OutboundQuota: ULONG,
    IN_DefaultTimeout: ?PC(LARGE_INTEGER),
) callconv(.winapi) NTSTATUS;
