const boot = @import("boot.zig");
const std = @import("std");
const uart = @import("uart.zig");
const gdt = @import("arch/x86_64/gdt.zig");
const idt = @import("arch/x86_64/idt.zig");
const memory = @import("memory/memory.zig");
const pmm = @import("memory/pmm.zig");
const vmm = @import("memory/vmm.zig");
const paging = @import("memory/paging.zig");

const log = std.log.scoped(.kmain);

/// Standard Library Options
pub const std_options = .{
    .log_level = .debug,
    .logFn = uart.log,
};

export fn hang() noreturn {
    while (true) {
        asm volatile ("hlt");
    }
}

// \\    mov $kernel_stack, %rsp
comptime {
    asm (
        \\.extern kernel_stack
        \\.extern kmain
        \\.extern hang
        \\
        \\.global _start;
        \\.type _start, @function;
        \\_start:
        \\    mov $kernel_stack, %rsp
        \\    call kmain
        \\    call hang
    );
}
// // The following will be our kernel's entry point.
// export fn _start() callconv(.C) noreturn {
//     kmain();

//     // We're done, just hang...
//     hang();
// }

var already_panicking: bool = false;

pub fn panic(message: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = error_return_trace;
    _ = ret_addr;

    @setCold(true);

    if (already_panicking) {
        uart.writeBytes("\npanicked during kernel panic");
        hang();
    }
    already_panicking = true;

    uart.writeBytes("\nKERNEL PANIC!\n");
    uart.writeBytes(message);
    uart.writeByte('\n');

    hang();
}

/// The kernels stack size.
const stack_size: usize = 4 * 1024;

/// The kernels stack.
export var kernel_stack: [stack_size]u8 align(16) linksection(".stack") = [_]u8{0} ** stack_size;

const direct_map_offset = 0xffff800000000000;

// const stack_start = @as(u64, @ptrCast(&kernel_stack[0]));
export const stack_address = &kernel_stack[stack_size - 1];

export fn kmain() void {
    uart.init(uart.BaudRate.@"38400") catch hang();
    log.debug("Control passed on to kernel", .{});

    boot.init();
    log.debug("Boot info initialised", .{});

    gdt.init();
    idt.init();

    log.debug("addr of stack: start 0x{x} & end 0x{x}", .{ @intFromPtr(&kernel_stack[0]), @intFromPtr(&kernel_stack[stack_size - 1]) });

    var is_zero = true;
    // const ks = @ptrCast(value: anytype)
    // for (kernel_stack) |byte| {
    //     if (byte != 0) {
    //         is_zero = false;
    //     }
    // }
    const dest: [stack_size]u8 = .{0} ** stack_size;
    // std.mem.copyForwards(u8, dest[0..stack_size], &kernel_stack);
    for (dest) |byte| {
        if (byte != 0) {
            is_zero = false;
        }
    }
    // if (@as(*u8, @ptrFromInt(@intFromPtr(&kernel_stack[0]) + stack_size - 1)).* != 0) {
    //     is_zero = false;
    // }

    log.debug("is_zero: {any}", .{is_zero});

    // asm volatile ("int $0x80");
    // asm volatile ("int $0x40");
    // var ptr: [*]volatile u8 = @ptrFromInt(0xdeadbeef);
    // ptr[0] = 4;

    memory.init();
    pmm.init();
    paging.init() catch |err| log.debug("paging err: {any}", .{err});

    {
        const virtual_address = pmm.allocatePage() catch unreachable;
        defer pmm.deallocatePage(virtual_address);

        const byte_slice: []u8 = @as([*]u8, @ptrFromInt(virtual_address))[0..4096];
        var fba = std.heap.FixedBufferAllocator.init(byte_slice);
        const allocator = fba.allocator();

        var vec = std.ArrayList(u8).init(allocator);
        defer vec.deinit();
        vec.append(1) catch unreachable;
        vec.append(2) catch unreachable;
        vec.append(3) catch unreachable;
        vec.append(4) catch unreachable;
        log.debug("vec: {}", .{vec});
    }

    const addr = boot.kernelBaseAddress();
    log.debug("kernel phy base addr: 0x{x}", .{addr.physical_base});
    log.debug("kernel virt base addr: 0x{x}", .{addr.virtual_base});

    log.debug("direct map offset: 0x{x}", .{boot.directMapOffset()});

    hang();
}
