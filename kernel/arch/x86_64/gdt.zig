//! The Global Descriptor Table

const log = @import("std").log.scoped(.GDT);

/// The access bits for a GDT entry.
const AccessBits = packed struct(u8) {
    /// Whether the segment has been access. This shouldn't be set as it is set by the CPU when the
    /// segment is accessed.
    accessed: u1,

    /// For code segments, when set allows the code segment to be readable. Code segments are
    /// always executable. For data segments, when set allows the data segment to be writeable.
    /// Data segments are always readable.
    read_write: u1,

    /// For code segments, when set allows this code segments to be executed from a equal or lower
    /// privilege level. The privilege bits represent the highest privilege level that is allowed
    /// to execute this segment. If not set, then the code segment can only be executed from the
    /// same ring level specified in the privilege level bits. For data segments, when set the data
    /// segment grows downwards. When not set, the data segment grows upwards. So for both code and
    /// data segments, this shouldn't be set.
    direction_conforming: u1,

    /// When set, the segment can be executed, a code segments. When not set, the segment can't be
    /// executed, data segment.
    executable: u1,

    /// Should be set for code and data segments, but not set for TSS.
    descriptor_type: u1,

    /// Privilege/ring level. The kernel level is level 3, the highest privilege. The user level is
    /// level 0, the lowest privilege.
    privilege_level: u2,

    /// Whether the segment is present. This must be set for all valid selectors, not the null
    /// segment.
    present: u1,
};

/// The flag bits for a GDT entry.
const FlagBits = packed struct(u4) {
    /// The lowest bits must be 0 as this is reserved for future use.
    reserved_zero: u1 = 0,

    /// When set indicates the segment is a x86-64 segment. If set, then the IS_32_BIT flag must
    /// not be set. If both are set, then will throw an exception.
    is_64_bit: u1,

    /// When set indicates the segment is a 32 bit protected mode segment. When not set, indicates
    /// the segment is a 16 bit protected mode segment.
    is_32_bit: u1,

    /// The granularity bit. When set the limit is in 4KB blocks (page granularity). When not set,
    /// then limit is in 1B blocks (byte granularity). This should be set as we are doing paging.
    granularity: u1,
};

/// The structure that contains all the information that each GDT entry needs.
const GdtEntry = packed struct(u64) {
    /// The lower 16 bits of the limit address. Describes the size of memory that can be addressed.
    limit_low: u16,

    /// The lower 24 bits of the base address. Describes the start of memory for the entry.
    base_low: u24,

    /// The access bits, see AccessBits for all the options. 8 bits.
    access: AccessBits,

    /// The upper 4 bits of the limit address. Describes the size of memory that can be addressed.
    limit_high: u4,

    /// The flag bits, see above for all the options. 4 bits.
    flags: FlagBits,

    /// The upper 8 bits of the base address. Describes the start of memory for the entry.
    base_high: u8,

    ///
    /// Make a GDT entry.
    ///
    /// Arguments:
    ///     IN base: u32          - The linear address where the segment begins.
    ///     IN limit: u20         - The maximum addressable unit whether it is 1B units or page units.
    ///     IN access: AccessBits - The access bits for the descriptor.
    ///     IN flags: FlagBits    - The flag bits for the descriptor.
    ///
    /// Return: GdtEntry
    ///     A new GDT entry with the give access and flag bits set with the base at 0x00000000 and
    ///     limit at 0xFFFFF.
    ///
    fn new(base: u32, limit: u20, access: AccessBits, flags: FlagBits) GdtEntry {
        return .{
            .limit_low = @truncate(limit),
            .base_low = @truncate(base),
            .access = access,
            .limit_high = @truncate(limit >> 16),
            .flags = flags,
            .base_high = @truncate(base >> 24),
        };
    }
};

/// The GDT pointer structure that contains the pointer to the beginning of the GDT and the number
/// of the table (minus 1). Used to load the GDT with LGDT instruction.
pub const GdtPtr = packed struct(u80) {
    /// 16 bit entry for the size of entries in bytes (minus 1).
    limit: u16,

    /// 64 bit entry for the base address for the GDT.
    base: u64,
};

/// The total number of entries in the GDT including: null, kernel code, kernel data, user code,
/// user data and the TSS.
const NUMBER_OF_ENTRIES: u16 = 3;

/// The size of the GTD in bytes (minus 1).
const TABLE_SIZE: u16 = (@sizeOf(GdtEntry) * NUMBER_OF_ENTRIES) - 1;

/// The null segment, everything is set to zero.
const NULL_SEGMENT: AccessBits = .{
    .accessed = 0,
    .read_write = 0,
    .direction_conforming = 0,
    .executable = 0,
    .descriptor_type = 0,
    .privilege_level = 0,
    .present = 0,
};

/// This bit pattern represents a kernel code segment with bits: readable, executable, descriptor,
/// privilege 0, and present set.
const KERNEL_SEGMENT_CODE: AccessBits = .{
    .accessed = 0,
    .read_write = 1,
    .direction_conforming = 0,
    .executable = 1,
    .descriptor_type = 1,
    .privilege_level = 0,
    .present = 1,
};

/// This bit pattern represents a kernel data segment with bits: writeable, descriptor, privilege 0,
/// and present set.
const KERNEL_SEGMENT_DATA: AccessBits = .{
    .accessed = 0,
    .read_write = 1,
    .direction_conforming = 0,
    .executable = 0,
    .descriptor_type = 1,
    .privilege_level = 0,
    .present = 1,
};

/// The bit pattern for all bits set to zero.
const NULL_FLAGS: FlagBits = .{
    .is_64_bit = 0,
    .is_32_bit = 0,
    .granularity = 0,
};

/// The bit pattern for all segments where we are in 64 bit long mode and paging enabled.
const PAGING_64_BIT: FlagBits = .{
    .is_64_bit = 1,
    .is_32_bit = 0,
    .granularity = 1,
};

// ----------
// The indexes into the GDT where each segment resides.
// ----------

/// The index of the NULL GDT entry.
const NULL_INDEX = 0;

/// The index of the kernel code GDT entry.
const KERNEL_CODE_INDEX = 1;

/// The index of the kernel data GDT entry.
const KERNEL_DATA_INDEX = 2;

// ----------
// The offsets into the GDT where each segment resides.
// ----------

/// The offset of the NULL GDT entry.
pub const NULL_OFFSET: u16 = NULL_OFFSET * @sizeOf(GdtEntry);

/// The offset of the kernel code GDT entry.
pub const KERNEL_CODE_OFFSET: u16 = KERNEL_CODE_INDEX * @sizeOf(GdtEntry);

/// The offset of the kernel data GDT entry.
pub const KERNEL_DATA_OFFSET: u16 = KERNEL_DATA_INDEX * @sizeOf(GdtEntry);

/// The GDT entry table of NUMBER_OF_ENTRIES entries.
var gdt_entries: [NUMBER_OF_ENTRIES]GdtEntry = init: {
    var gdt_entries_temp: [NUMBER_OF_ENTRIES]GdtEntry = undefined;

    // Null descriptor
    gdt_entries_temp[NULL_INDEX] = GdtEntry.new(0, 0, NULL_SEGMENT, NULL_FLAGS);

    // Kernel code descriptor
    gdt_entries_temp[KERNEL_CODE_INDEX] = GdtEntry.new(0, 0xFFFFF, KERNEL_SEGMENT_CODE, PAGING_64_BIT);

    // Kernel data descriptor
    gdt_entries_temp[KERNEL_DATA_INDEX] = GdtEntry.new(0, 0xFFFFF, KERNEL_SEGMENT_DATA, PAGING_64_BIT);

    break :init gdt_entries_temp;
};

/// The GDT pointer that the CPU is loaded with that contains the base address of the GDT and the
/// size.
var gdt_ptr: GdtPtr = .{
    .limit = TABLE_SIZE,
    .base = undefined,
};

/// Initialise the Global Descriptor table.
pub fn init() void {
    // Set the base address where all the GDT entries are.
    gdt_ptr.base = @intFromPtr(&gdt_entries[0]);

    // Load the GDT
    lgdt(&gdt_ptr);
}

/// Load the GDT and refreshing the code segment with the code segment offset of the kernel as we
/// are still in kernel land. Also loads the kernel data segment into all the other segment
/// registers.
///
/// Arguments:
///     IN gdt_ptr: *gdt.GdtPtr - The address to the GDT.
///
fn lgdt(gdt_ptr_: *const GdtPtr) void {
    // Disable interrupts
    asm volatile ("cli");

    // Load the GDT into the CPU
    asm volatile ("lgdt (%[addr])"
        :
        : [addr] "{rax}" (gdt_ptr_),
    );

    // Load the kernel data segment, index into the GDT
    asm volatile ("mov %%bx, %%ds"
        :
        : [KERNEL_DATA_OFFSET] "{bx}" (KERNEL_DATA_OFFSET),
    );

    asm volatile ("mov %%bx, %%es");
    asm volatile ("mov %%bx, %%fs");
    asm volatile ("mov %%bx, %%gs");
    asm volatile ("mov %%bx, %%ss");

    // Load the kernel code segment into the CS register
    set_cs(KERNEL_CODE_OFFSET);

    log.info("GDT Initialised!", .{});
}

/// Set the value of the CS register
fn set_cs(value: u16) void {
    // a bit more difficult than other things because it can't be loaded via MOV
    // so we first load it and then change it via far return
    _ = asm volatile (
        \\push %[val]
        \\lea setCSOut(%rip), %[tmp]
        \\push %[tmp]
        \\lretq
        \\setCSOut:
        : [tmp] "={rax}" (-> usize),
        : [val] "{rcx}" (@as(u64, value)),
        : "memory"
    );
}
