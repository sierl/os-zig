const std = @import("std");
const gdt = @import("gdt.zig");
const register = @import("register.zig");

const log = std.log.scoped(.IDT);

const GateType = enum(u4) {
    /// 0b1110 or 0xE: 64-bit Interrupt Gate
    InterruptGate = 0xE,

    /// 0b1111 or 0xF: 64-bit Trap Gate
    TrapGate = 0xF,

    _,
};

const PrivilegeLevel = enum(u2) {
    Kernel = 0,
    User = 3,
    _,
};

const IDTEntry = packed struct(u128) {
    /// The lower 16 bits of the base address of the interrupt service routine.
    offset_lo: u16,

    /// The code segment in the GDT which the handlers will be held.
    segment_selector: u16,

    /// A 3-bit value which is an offset into the Interrupt Stack Table, which is stored in the Task State Segment.
    ist: u3,

    /// Reserved (Must be zero)
    reserved_1: u5 = 0,

    /// A 4-bit value which defines the type of gate this Interrupt Descriptor represents.
    /// In long mode there are two valid type values:
    ///     0b1110 or 0xE: 64-bit Interrupt Gate
    ///     0b1111 or 0xF: 64-bit Trap Gate
    gate_type: GateType,

    /// Reserved (Must be zero)
    reserved_2: u1 = 0,

    /// The minimum ring level that the calling code must have to run the handler.
    /// So user code may not be able to run some interrupts.
    privilege_level: PrivilegeLevel,

    /// Whether the IDT entry is present.
    present: u1,

    /// The higher 48 bits of the base address of the interrupt service routine.
    offset_hi: u48,

    /// Reserved (Must be zero)
    reserved_3: u32 = 0,

    fn new(isr_address: u64, segment_selector: u16, gate_type: GateType, privilege_level: PrivilegeLevel) IDTEntry {
        return IDTEntry{
            .offset_lo = @truncate(isr_address),
            .segment_selector = segment_selector,
            .ist = 0,
            .gate_type = gate_type,
            .privilege_level = privilege_level,
            .present = 1,
            .offset_hi = @truncate(isr_address >> 16),
        };
    }
};

/// The IDT pointer structure used to load the IST with LIDT instruction.
const IDTR = packed struct(u80) {
    const Self = @This();

    /// The total size of the IDT (minus 1) in bytes.
    limit: u16,

    /// The base address where the IDT is located.
    base: u64,

    /// Load the IDT into the CPU.
    fn load(self: *const Self) void {
        asm volatile ("lidt (%[addr])"
            :
            : [addr] "{rax}" (self),
        );
    }
};

/// Interrupt Function Type
const InterruptFunction = *const fn () callconv(.Naked) noreturn;

/// Global IDT
var idt: [256]IDTEntry = .{IDTEntry{
    .offset_lo = 0,
    .segment_selector = 0,
    .ist = 0,
    .gate_type = GateType.InterruptGate,
    .privilege_level = PrivilegeLevel.Kernel,

    // By default, all entries are not present.
    .present = 0,
    .offset_hi = 0,
}} ** 256;

var descriptor = IDTR{ .limit = @sizeOf(@TypeOf(idt)) - 1, .base = undefined };

/// Initialize the IDT
pub fn init() void {
    // make descriptor point to global idt
    descriptor.base = @intFromPtr(&idt);

    // construct the idt generically
    inline for (0..255) |i| {
        if (get_vector(i)) |vector| {
            switch (i) {
                0...14, 16...21, 28...31 => {
                    // trap
                    idt[i] = IDTEntry.new(@intFromPtr(vector), gdt.KERNEL_CODE_OFFSET, GateType.TrapGate, PrivilegeLevel.Kernel);
                },
                else => {
                    // normal
                    idt[i] = IDTEntry.new(@intFromPtr(vector), gdt.KERNEL_CODE_OFFSET, GateType.InterruptGate, PrivilegeLevel.Kernel);
                },
            }
        } else {
            idt[i].present = 0;
        }
    }
    // Load the IDT
    descriptor.load();

    // Enable interrupts
    asm volatile ("sti");

    log.info("IDT Initialised!", .{});
}

/// Is the given interrupt number an exception?
inline fn is_exception(interrupt_number: u8) bool {
    return switch (interrupt_number) {
        0...14, 16...21, 28...30 => true,
        else => false,
    };
}

/// Has the given exception an error code?
inline fn has_error_code(interrupt_number: u8) bool {
    return switch (interrupt_number) {
        8, 10...14, 17, 21, 29, 30 => true,
        else => false,
    };
}

/// Generic Interrupt Caller
fn get_vector(comptime vector_number: u8) ?InterruptFunction {
    const error_code_asm = comptime if (!has_error_code(vector_number)) "push $0\n" else "";
    const vector_number_asm = std.fmt.comptimePrint("push ${d}\n", .{vector_number});

    return switch (vector_number) {
        inline 15, 22...27, 31 => null,
        else => blk: {
            // normal or trap
            break :blk struct {
                fn vector() callconv(.Naked) noreturn {
                    asm volatile (error_code_asm ++ vector_number_asm ++ "jmp interrupt_common");
                }
            }.vector;
        },
    };
    // return switch (vector_number) {
    //     inline 15, 22...27, 31 => null,
    //     else => blk: {
    //         // normal or trap
    //         break :blk struct {
    //             fn vector() callconv(.Naked) noreturn {
    //                 if (has_error_code(vector_number)) {
    //                     asm volatile (
    //                         \\push %[num]
    //                         \\jmp interrupt_common
    //                         :
    //                         : [num] "i" (vector_number),
    //                     );
    //                 } else {
    //                     asm volatile (
    //                         \\push $0
    //                         \\push %[num]
    //                         \\jmp interrupt_common
    //                         :
    //                         : [num] "i" (vector_number),
    //                     );
    //                 }
    //             }
    //         }.vector;
    //     },
    // };
}

/// Interrupt Frame
const InterruptFrame = extern struct {
    /// Extra Segment Selector
    es: u64,
    /// Data Segment Selector
    ds: u64,
    /// General purpose register R15
    r15: u64,
    /// General purpose register R14
    r14: u64,
    /// General purpose register R13
    r13: u64,
    /// General purpose register R12
    r12: u64,
    /// General purpose register R11
    r11: u64,
    /// General purpose register R10
    r10: u64,
    /// General purpose register R9
    r9: u64,
    /// General purpose register R8
    r8: u64,
    /// Destination index for string operations
    rdi: u64,
    /// Source index for string operations
    rsi: u64,
    /// Base Pointer (meant for stack frames)
    rbp: u64,
    /// Data (commonly extends the A register)
    rdx: u64,
    /// Counter
    rcx: u64,
    /// Base
    rbx: u64,
    /// Accumulator
    rax: u64,
    /// Interrupt Number
    vector_number: u64,
    /// Error code
    error_code: u64,
    /// Instruction Pointer
    rip: u64,
    /// Code Segment
    cs: u64,
    /// RFLAGS
    rflags: register.RFLAGS,
    /// Stack Pointer
    rsp: u64,
    /// Stack Segment
    ss: u64,
};

/// Common interrupt calling code
/// Should be called after pushing the error code and the interrupt number
export fn interrupt_common() callconv(.Naked) void {
    asm volatile (
    // push general-purpose registers
        \\push %%rax
        \\push %%rbx
        \\push %%rcx
        \\push %%rdx
        \\push %%rbp
        \\push %%rsi
        \\push %%rdi
        \\push %%r8
        \\push %%r9
        \\push %%r10
        \\push %%r11
        \\push %%r12
        \\push %%r13
        \\push %%r14
        \\push %%r15
        // push segment registers
        \\mov %%ds, %%rax
        \\push %%rax
        \\mov %%es, %%rax
        \\push %%rax
        \\mov %%rsp, %%rdi
        // set segment to run in
        // does not push so we don't need to pop
        \\mov %[kernel_data], %%ax
        \\mov %%ax, %%es
        \\mov %%ax, %%ds
        \\call interrupt_handler
        // pop segment registers
        \\pop %%rax
        \\mov %%rax, %%es
        \\pop %%rax
        \\mov %%rax, %%ds
        // pop general-purpose registers
        \\pop %%r15
        \\pop %%r14
        \\pop %%r13
        \\pop %%r12
        \\pop %%r11
        \\pop %%r10
        \\pop %%r9
        \\pop %%r8
        \\pop %%rdi
        \\pop %%rsi
        \\pop %%rbp
        \\pop %%rdx
        \\pop %%rcx
        \\pop %%rbx
        \\pop %%rax
        // pop error code
        \\add $16, %%rsp
        // return
        \\iretq
        :
        : [kernel_data] "i" (gdt.KERNEL_DATA_OFFSET),
    );
}

/// The exception messaged that is printed when a exception happens
const exception_message = [32][]const u8{
    "Divide By Zero",
    "Single Step (Debugger)",
    "Non Maskable Interrupt",
    "Breakpoint (Debugger)",
    "Overflow",
    "Bound Range Exceeded",
    "Invalid Opcode",
    "No Coprocessor, Device Not Available",
    "Double Fault",
    "Coprocessor Segment Overrun",
    "Invalid Task State Segment (TSS)",
    "Segment Not Present",
    "Stack Segment Overrun",
    "General Protection Fault",
    "Page Fault",
    "Unknown Interrupt",
    "x87 FPU Floating Point Error",
    "Alignment Check",
    "Machine Check",
    "SIMD Floating Point",
    "Virtualization",
    "Reserved",
    "Reserved",
    "Reserved",
    "Reserved",
    "Reserved",
    "Reserved",
    "Reserved",
    "Reserved",
    "Reserved",
    "Security",
    "Reserved",
};

/// Interrupt Handler
export fn interrupt_handler(frame: *InterruptFrame) void {
    log.info("Received interrupt {}", .{frame.vector_number});
    // specific interrupt handling
    // switch (frame.vector_number) {
    //     100 => ps2.keyboardHandler(frame.vector_number),
    //     else => {},
    // }

    log.info("err code: {}", .{frame.*.error_code});
    log.info("rax: {}", .{frame.*.rax});
    log.info("rip: {}", .{frame.*.rip});
    log.info("cs: {}", .{frame.*.cs});
    log.info("rbx: {}\n", .{frame.*.rbx});

    if (frame.*.vector_number < 32) {
        // Display the description for the Exception that occurred.
        // For now, we will simply halt the system using an infinite loop.
        log.info("{s}", .{exception_message[frame.*.vector_number]});
        log.info("err code: {}", .{frame.*.error_code});
        log.info("Exception. System Halted!\n", .{});

        while (true) {}
    }
}
