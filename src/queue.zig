const std = @import("std");

// greatly inspired by https://github.com/rockorager/libvaxis/blob/37d4ce98a86249fdb3a0d1ba6aa18b7f3a1d2a92/src/queue.zig

const MAX_BUFFER_SIZE = (std.math.maxInt(usize) / 2) - 1;

pub fn Queue(comptime T: type, comptime n: usize) type {
    if (n > MAX_BUFFER_SIZE) {
        @compileError("size too big");
    }

    return struct {
        const Self = @This();

        buf: []T,

        push_idx: usize = 0,
        pop_idx: usize = 0,

        mutex: std.Thread.Mutex = .{},
        not_full: std.Thread.Condition = .{},
        not_empty: std.Thread.Condition = .{},

        pub fn init(allocator: std.mem.Allocator) error{OutOfMemory}!Self {
            return .{
                .buf = try allocator.alloc(T, n),
            };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            allocator.free(self.buf);
        }

        pub fn pop(self: *Self) T {
            self.mutex.lock();
            defer self.mutex.unlock();
            while (self.isEmptyLH()) {
                self.not_empty.wait(&self.mutex);
            }
            std.debug.assert(!self.isEmptyLH());
            const was_full = self.isFullLH();

            const result = self.popLH();

            if (was_full) {
                self.not_full.signal();
            }

            return result;
        }

        inline fn popLH(self: *Self) T {
            const result = self.buf[self.idxIntoBuf(self.pop_idx)];
            self.pop_idx = self.wrappedIdx(self.pop_idx + 1);
            return result;
        }

        pub fn push(self: *Self, item: T) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            while (self.isFullLH()) {
                self.not_full.wait(&self.mutex);
            }
            std.debug.assert(!self.isFullLH());
            const was_empty = self.isEmptyLH();

            self.buf[self.idxIntoBuf(self.push_idx)] = item;
            self.push_idx = self.wrappedIdx(self.push_idx + 1);

            if (was_empty) {
                self.not_empty.signal();
            }
        }

        pub fn tryPush(self: *Self, item: T) bool {
            if (self.isFull()) {
                return false;
            }

            self.push(item);
            return true;
        }

        pub fn tryPop(self: *Self) ?T {
            if (self.isEmpty()) {
                return null;
            }

            return self.pop();
        }

        pub fn poll(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            while (self.isEmptyLH()) {
                self.not_empty.wait(&self.mutex);
            }
            std.debug.assert(!self.isEmptyLH());
        }

        pub inline fn isEmpty(self: *Self) bool {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.isEmptyLH();
        }

        inline fn isEmptyLH(self: Self) bool {
            return self.push_idx == self.pop_idx;
        }

        pub inline fn isFull(self: *Self) bool {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.isFullLH();
        }

        inline fn isFullLH(self: Self) bool {
            return self.wrappedIdx(self.push_idx + self.buf.len) == self.pop_idx;
        }

        fn len(self: Self) usize {
            const wrap_offset = 2 * self.buf.len * @intFromBool(self.push_idx < self.pop_idx);
            const adjusted_write_index = self.push_idx + wrap_offset;
            return adjusted_write_index - self.pop_idx;
        }

        inline fn idxIntoBuf(self: Self, index: usize) usize {
            return index % self.buf.len;
        }

        inline fn wrappedIdx(self: Self, index: usize) usize {
            return index % (2 * self.buf.len);
        }
    };
}
