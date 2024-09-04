/// References:
/// - https://wiki.osdev.org/Serial_Ports
/// - https://wiki.osdev.org/UART
///
const std = @import("std");
const port = @import("arch/x86_64/port.zig");

const COM1 = 0x3F8;

pub const Error = error{
    DeviceIsFaulty,
};

pub const BaudRate = enum(u32) {
    @"115200" = 115200,
    @"57600" = 57600,
    @"38400" = 38400,
    @"19200" = 19200,
    @"9600" = 9600,
    @"4800" = 4800,

    const base = 115200;

    const Self = @This();

    /// Get the numeric baudrate
    pub fn getBaudrate(self: Self) u32 {
        return @intFromEnum(self);
    }

    /// Get the clock divisor for a specific speed
    pub fn getDivisor(self: Self) u16 {
        return @intCast(std.math.divExact(u32, base, self.getBaudrate()) catch unreachable);
    }
};

pub fn init(baud_rate: BaudRate) Error!void {
    // Disable all interrupts
    port.out(u8, COM1 + 1, 0x00);

    // Enable DLAB to allow access to the divisor registers
    port.out(u8, COM1 + 3, 0b1000_0000);

    // Send baud rate divisor
    const rate_divisor = baud_rate.getDivisor();
    port.out(u8, COM1, @truncate(rate_divisor)); // Send least significant byte
    port.out(u8, COM1 + 1, @truncate(rate_divisor >> 8)); // Send most significant byte

    // 8 data bits, no parity, one stop bit (disables DLAB)
    port.out(u8, COM1 + 3, 3);

    // Enable FIFO, clear TX/RX queues (receiver/transmitter queues) and set interrupt watermark at 14 bytes
    port.out(u8, COM1 + 2, 0xC7);

    // IRQs enabled, RTS/DSR set
    port.out(u8, COM1 + 4, 0x0B);

    // Set in loopback mode to test the serial chip
    port.out(u8, COM1 + 4, 0x1E);

    // Test serial chip (send byte 0xAE and check if serial returns same byte)
    port.out(u8, COM1, 0xAE);

    // Check if serial is faulty (i.e: not same byte as sent)
    if (port.in(u8, COM1) != 0xAE) {
        return Error.DeviceIsFaulty;
    }

    // If serial is not faulty set it in normal operation mode
    // (not-loopback with IRQs enabled and OUT#1 and OUT#2 bits enabled)
    port.out(u8, COM1 + 4, 0x0F);
}

inline fn isTransmissionBufferNotEmpty() bool {
    return port.in(u8, COM1 + 5) & 0x20 == 0;
}

pub fn writeByte(byte: u8) void {
    // Wait for transmit buffer to be empty
    while (isTransmissionBufferNotEmpty()) {}

    // Send byte
    port.out(u8, COM1, byte);
}

pub fn writeBytes(bytes: []const u8) void {
    for (bytes) |byte| {
        writeByte(byte);
    }
}

const Writer = std.io.GenericWriter(void, error{}, logCallback);

fn logCallback(context: void, bytes: []const u8) error{}!usize {
    _ = context;
    writeBytes(bytes);
    return bytes.len;
}

pub fn out(comptime format: []const u8, args: anytype) void {
    // FIXME: Panic on failure
    std.fmt.format(Writer{ .context = {} }, format, args) catch unreachable;
}

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const color = comptime switch (level) {
        .debug => "\x1b[32m",
        .info => "\x1b[36m",
        .warn => "\x1b[33m",
        .err => "\x1b[31m",
    };

    const prefix = color ++ @tagName(scope) ++ ":\x1b[0m ";
    out(prefix ++ format ++ "\n", args);
}
