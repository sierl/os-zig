/// Assembly that reads data from a given port and returns its value.
///
/// Arguments:
///     IN comptime T: type - The type of the data. This can only be u8, u16 or u32.
///     IN port: u16        - The port to read data from.
///
/// Return: T
///     The data that the port returns.
pub fn in(comptime T: type, port: u16) T {
    return switch (T) {
        u8 => asm volatile ("inb %[port], %[result]"
            : [result] "={al}" (-> u8),
            : [port] "{dx}" (port),
            : "dx", "al"
        ),

        u16 => asm volatile ("inw %[port], %[result]"
            : [result] "={ax}" (-> u16),
            : [port] "N{dx}" (port),
        ),

        u32 => asm volatile ("inl %[port], %[result]"
            : [result] "={eax}" (-> u32),
            : [port] "N{dx}" (port),
        ),

        else => @compileError("Invalid data type. Expected u8, u16 or u32, found " ++ @typeName(T)),
    };
}

/// Assembly to write to a given port with a give type of data.
///
/// Arguments:
///     IN comptime T: type - The type of data to write to the port. This must be a u8, u16 or u32 type.
///     IN port: u16        - The port to write to.
///     IN data: T          - The data that will be sent.
pub fn out(comptime T: type, port: u16, data: T) void {
    switch (T) {
        u8 => asm volatile ("outb %[data], %[port]"
            :
            : [port] "{dx}" (port),
              [data] "{al}" (data),
        ),

        u16 => asm volatile ("outw %[data], %[port]"
            :
            : [port] "{dx}" (port),
              [data] "{ax}" (data),
        ),

        u32 => asm volatile ("outl %[data], %[port]"
            :
            : [port] "{dx}" (port),
              [data] "{eax}" (data),
        ),

        else => @compileError("Invalid data type. Expected u8, u16 or u32, found " ++ @typeName(T)),
    }
}
