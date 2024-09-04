const std = @import("std");
const memory = @import("memory.zig");
const pmm = @import("pmm.zig");

const ENTRIES_PER_TABLE = memory.PAGE_SIZE / @sizeOf(u64);
const FRAME_MASK = 0x000FFFFFFFFFF000;

const PageTable = extern struct {
    entries: [ENTRIES_PER_TABLE]u64,
};

comptime {
    std.debug.assert(ENTRIES_PER_TABLE == 512);
    std.debug.assert(@sizeOf(PageTable) == memory.PAGE_SIZE);
}

/// The kernels root page table: Page Map Level 4.
var root_page_table: PageTable align(memory.PAGE_SIZE) = .{
    .entries = .{0} ** ENTRIES_PER_TABLE,
};

const Entry = packed struct {
    value: u64,

    const Self = @This();
    const FRAME_MASK = 0x000FFFFFFFFFF000;

    comptime {
        std.debug.assert(@sizeOf(Self) == 8);
        std.debug.assert(@bitSizeOf(Self) == 64);
    }

    fn init(entry: u64) Self {
        return Self{ .value = entry };
    }

    fn has_attribute(self: Self, attribute_mask: AttributeMask) bool {
        return self.value & @intFromEnum(attribute_mask) == @intFromEnum(attribute_mask);
    }

    fn get_frame(self: Self) u64 {
        return self.value & Self.FRAME_MASK;
    }
};

// Bit masks for setting and clearing attributes.
const AttributeMask = enum(u64) {
    Present = 0x1,
    Writable = 0x2,
    User = 0x4,
    WriteThrough = 0x8,
    CacheDisabled = 0x10,
    Accessed = 0x20,
    Zero = 0x40,
    MemoryType = 0x80,
};

/// Check if an entry has an attribute.
inline fn has_attribute(entry: u64, attribute_mask: AttributeMask) bool {
    return entry & @intFromEnum(attribute_mask) == @intFromEnum(attribute_mask);
}

inline fn hasAttribute(entry: u64, attr: u64) bool {
    return entry & attr == attr;
}

/// Set the bit(s) associated with an attribute.
///
/// Arguments:
///     entry: *u64 - The entry to modify.
///     attribute_mask: u64   - The bits corresponding to the attribute to set.
inline fn set_attribute(entry: *u64, attribute_mask: AttributeMask) void {
    entry.* |= @intFromEnum(attribute_mask);
}

inline fn clear_attribute(entry: *u64, attr: AttributeMask) void {
    entry.* &= ~@intFromEnum(attr);
}

/// Get the physical/frame address out of a page entry. Currently this is a 40 bit address, will
/// need to check the CPUID 0x80000008 as this is hardcoded to 40 bits.
///
/// Arguments:
///     IN entry: u64 - The page entry to get the frame from.
///
/// Return: u64
///     The physical address. This will point to the next page entry in the chain.
inline fn get_frame(entry: u64) u64 {
    return entry & FRAME_MASK;
}

/// Set the physical/frame address of a page entry. Currently this is a 40 bit address, will
/// need to check the CPUID 0x80000008 as this is hardcoded to 40 bits.
/// This assumes the address is aligned to the page boundary.
///
/// Arguments:
///     IN entry: *u64           - The page entry to set the frame to.
///     IN physical_address: u64 - The address to set the entry.
///
inline fn set_frame(entry: *u64, physical_address: u64) void {
    std.debug.assert(std.mem.isAlignedGeneric(u64, physical_address, memory.PAGE_SIZE));
    entry.* |= physical_address & FRAME_MASK;
}

// const PageLevel = enum(u8) {
//     Four = 3,
//     Three = 2,
//     Two = 1,
//     One = 0,
// };

inline fn virtToPML4EntryIdx(virt: u64) u64 {
    return virt >> 39 & 0x1FF;
}

inline fn virtToPDPTEntryIdx(virt: u64) u64 {
    return virt >> 30 & 0x1FF;
}

inline fn virtToPDEntryIdx(virt: u64) u64 {
    return virt >> 21 & 0x1FF;
}

inline fn virtToPTEntryIdx(virt: u64) u64 {
    return virt >> 12 & 0x1FF;
}

/// Extract the three 9-bit page table indices from a virtual address.
fn virtual_to_page_table_index(virtual_address: u64, comptime level: u8) u9 {
    std.debug.assert(1 <= level and level <= 4);

    const MASK = 0b1_1111_1111; // 9 bits

    // bits of offset within a page
    const offset_shift = 12;
    const level_shift: comptime_int = offset_shift + (9 * (level - 1));

    return @truncate(virtual_address >> level_shift & MASK);
}

/// Returns page table, if it is present.
fn get_table_from_entry(entry: u64) ?*PageTable {
    if (!hasAttribute(entry, 0x1)) {
        return null;
    }

    const table_virtual_address = memory.physical_to_virtual(get_frame(entry));
    return @ptrFromInt(table_virtual_address);
}

/// Attributes for a virtual memory allocation
pub const Attributes = struct {
    /// Whether this memory belongs to the kernel and can therefore not be accessed in user mode
    kernel: bool,

    /// If this memory can be written to
    writable: bool,

    /// If this memory can be cached. Memory mapped to a device shouldn't, for example
    cachable: bool,
};

fn set_all_attributes(entry: *u64, attrs: Attributes) void {
    if (attrs.writable) {
        set_attribute(entry, AttributeMask.Writable);
    } else {
        clear_attribute(entry, AttributeMask.Writable);
    }

    if (attrs.kernel) {
        clear_attribute(entry, AttributeMask.User);
    } else {
        set_attribute(entry, AttributeMask.User);
    }

    if (attrs.cachable) {
        clear_attribute(entry, AttributeMask.CacheDisabled);
    } else {
        set_attribute(entry, AttributeMask.CacheDisabled);
    }
}

fn map_entry(virtual_address: u64, physical_address: u64, attributes: Attributes) !void {
    if (!std.mem.isAlignedGeneric(u64, virtual_address, memory.PAGE_SIZE)) {
        std.debug.panic("virtual address to map 0x{x} is not aligned to page size", .{virtual_address});
    }
    if (!std.mem.isAlignedGeneric(u64, physical_address, memory.PAGE_SIZE)) {
        std.debug.panic("physical address 0x{x} to be mapped is not aligned to page size", .{physical_address});
    }

    // Get page table
    const ptl4_index = virtToPML4EntryIdx(virtual_address);

    const ptl3 = get_table_from_entry(root_page_table.entries[ptl4_index]) orelse block: {
        var new_ptl4_entry: u64 = 0;

        // Allocate a new page table and set it to zero
        const ptl3: *PageTable = @ptrFromInt(try pmm.allocatePage());
        errdefer pmm.deallocatePage(@intFromPtr(ptl3));
        @memset(ptl3.entries[0..ENTRIES_PER_TABLE], 0);

        const ptl3_physical_address = memory.virtual_to_physical(@intFromPtr(ptl3));
        set_frame(&new_ptl4_entry, ptl3_physical_address);
        set_attribute(&new_ptl4_entry, AttributeMask.Present);
        set_all_attributes(&new_ptl4_entry, attributes);

        root_page_table.entries[ptl4_index] = new_ptl4_entry;
        break :block ptl3;
    };

    // Get page table
    const ptl3_index = virtToPDPTEntryIdx(virtual_address);

    const ptl2 = get_table_from_entry(ptl3.entries[ptl3_index]) orelse block: {
        var new_ptl3_entry: u64 = 0;

        // Allocate a new page table and set it to zero
        const ptl2: *PageTable = @ptrFromInt(try pmm.allocatePage());
        errdefer pmm.deallocatePage(@intFromPtr(ptl2));
        @memset(ptl3.entries[0..ENTRIES_PER_TABLE], 0);

        const ptl2_physical_address = memory.virtual_to_physical(@intFromPtr(ptl2));
        set_frame(&new_ptl3_entry, ptl2_physical_address);
        set_attribute(&new_ptl3_entry, AttributeMask.Present);
        set_all_attributes(&new_ptl3_entry, attributes);

        ptl3.entries[ptl3_index] = new_ptl3_entry;
        break :block ptl2;
    };

    // Get page table
    const ptl2_index = virtToPDEntryIdx(virtual_address);

    const ptl1 = get_table_from_entry(ptl2.entries[ptl2_index]) orelse block: {
        var new_ptl2_entry: u64 = 0;

        // Allocate a new page table and set it to zero
        const ptl1: *PageTable = @ptrFromInt(try pmm.allocatePage());
        errdefer pmm.deallocatePage(@intFromPtr(ptl1));
        @memset(ptl2.entries[0..ENTRIES_PER_TABLE], 0);

        const ptl1_physical_address = memory.virtual_to_physical(@intFromPtr(ptl1));
        set_frame(&new_ptl2_entry, ptl1_physical_address);
        set_attribute(&new_ptl2_entry, AttributeMask.Present);
        set_all_attributes(&new_ptl2_entry, attributes);

        ptl2.entries[ptl2_index] = new_ptl2_entry;
        break :block ptl1;
    };

    // Set entry
    const ptl1_index = virtToPTEntryIdx(virtual_address);

    var new_pt_entry: u64 = 0;
    set_frame(&new_pt_entry, physical_address);
    set_attribute(&new_pt_entry, AttributeMask.Present);
    set_all_attributes(&new_pt_entry, attributes);

    ptl1.entries[ptl1_index] = new_pt_entry;
}

fn add_min(end: u64, start: u64, add: u64) u64 {
    const try_add = std.math.add(u64, start, add) catch 0xFFFFFFFF_FFFFF000;
    return std.math.min(end, try_add);
}

fn map(virt_start: u64, virt_end: u64, phys_start: u64, phys_end: u64, attrs: Attributes) !void {
    std.debug.assert(phys_start < phys_end);
    std.debug.assert(virt_start < virt_end);

    std.debug.assert(std.mem.isAlignedGeneric(u64, phys_start, memory.PAGE_SIZE));
    std.debug.assert(std.mem.isAlignedGeneric(u64, phys_end, memory.PAGE_SIZE));
    std.debug.assert(std.mem.isAlignedGeneric(u64, virt_start, memory.PAGE_SIZE));
    std.debug.assert(std.mem.isAlignedGeneric(u64, virt_end, memory.PAGE_SIZE));

    std.debug.assert((phys_end - phys_start) == (virt_end - virt_start));

    var virt_addr = virt_start;
    var phys_addr = phys_start;

    // TODO: Remove this
    std.debug.assert(std.mem.alignBackward(u64, virt_addr, memory.PAGE_SIZE) == virt_addr);
    std.debug.assert(std.mem.alignBackward(u64, phys_addr, memory.PAGE_SIZE) == phys_addr);

    var virt_next = add_min(virt_end, virt_addr, memory.PAGE_SIZE);
    var phys_next = add_min(phys_end, phys_addr, memory.PAGE_SIZE);

    while (virt_addr < virt_end) : ({
        virt_addr = virt_next;
        phys_addr = phys_next;
        virt_next = add_min(virt_end, virt_next, memory.PAGE_SIZE);
        phys_next = add_min(phys_end, phys_next, memory.PAGE_SIZE);
    }) {
        try map_entry(virt_addr, phys_addr, attrs);
    }
}

// Write the address of page table to cr3
fn activate_page_table(page_table: *const PageTable) void {
    const physical_address = @intFromPtr(memory.virtual_to_physical(page_table));

    asm volatile ("mov %[address], %%cr3"
        :
        : [address] "r" (physical_address),
        : "memory"
    );
}

inline fn NUM_PAGES(n: u64) u64 {
    return (n + memory.PAGE_SIZE - 1) / memory.PAGE_SIZE;
}

fn vmm_map(vaddr: u64, paddr: u64, np: u64, attributes: Attributes) !void {
    // if (addrspace == NULL) {
    //     mem_map_t mm = {
    //         .vaddr = vaddr, .paddr = paddr, .flags= flags, .np = np
    //     };
    //     vec_push_back(&global_mmap_list, mm);
    // }
    var i: u64 = 0;
    while (i < np * memory.PAGE_SIZE) : (i += memory.PAGE_SIZE) {
        try map_entry(vaddr + i, paddr + i, attributes);
    }

    log.debug("PML4 mapped phys 0x{x} to virt 0x{x} ({} pages)", .{ paddr, vaddr, np });
}

const log = std.log.scoped(.paging);
pub fn init() !void {
    log.debug("Setting up paging...; max {}", .{(4 * 1024 * 1024 * 1024) / memory.PAGE_SIZE});

    const boot = @import("../boot.zig");
    const memory_map_entries = boot.memoryMap();

    var phys_limit: u64 = 0;
    for (memory_map_entries) |entry| {
        const new_limit = entry.base + entry.length;
        if (new_limit > phys_limit) {
            phys_limit = new_limit;
        }
    }

    const np = NUM_PAGES(phys_limit);
    var i: u64 = 0;
    while (i < np * memory.PAGE_SIZE) : (i += memory.PAGE_SIZE) {
        try map_entry(memory.physical_to_virtual(i), i, .{ .kernel = true, .writable = true, .cachable = true });
    }
    log.debug("Mapped {} bytes memory to 0x{x}\n", .{ phys_limit, boot.directMapOffset() });

    for (memory_map_entries) |entry| {
        _ = entry;
        // switch (entry.kind) {
        //     .kernel_and_modules => {
        //         const kernel = boot.kernelBaseAddress();

        //         const vaddr: u64 = kernel.virtual_base + entry.base - kernel.physical_base;
        //         // vmm_map: this should share for all tasks
        //         try vmm_map(vaddr, entry.base, NUM_PAGES(entry.length), .{ .kernel = true, .writable = true, .cachable = true });
        //         log.debug("Mapped kernel 0x{x} to 0x{x} (len: {}, #{})", .{ entry.base, vaddr, entry.length, i });
        //     },
        //     .framebuffer => {
        //         // vmm_map: this should share for all tasks
        //         try vmm_map(memory.physical_to_virtual(entry.base), entry.base, NUM_PAGES(entry.length), .{ .kernel = true, .writable = true, .cachable = true });
        //         log.info("Mapped framebuffer 0x{x} to 0x{x} (len: {}, #{})", .{ entry.base, memory.physical_to_virtual(entry.base), entry.length, i });
        //     },
        //     .bootloader_reclaimable => {
        //         // vmm_map: do nothing
        //         try vmm_map(memory.physical_to_virtual(entry.base), entry.base, NUM_PAGES(entry.length), .{ .kernel = true, .writable = true, .cachable = true });
        //         log.info("Mapped br 0x{x} to 0x{x} (len: {}, #{})", .{ entry.base, memory.physical_to_virtual(entry.base), entry.length, i });
        //     },
        //     .usable => {
        //         try vmm_map(memory.physical_to_virtual(entry.base), entry.base, NUM_PAGES(entry.length), .{ .kernel = true, .writable = true, .cachable = true });
        //         log.info("Mapped 0x{x} to 0x{x}(len: {}, type {any}, #{})", .{ entry.base, memory.physical_to_virtual(entry.base), entry.length, entry.kind, i });
        //     },
        //     else => {},
        // }
    }
    //

    // const gib = 1024 * 1024 * 1024;

    // var i: u64 = 0;
    // while (i < 4 * gib) : (i += memory.PAGE_SIZE) {
    //     try map_entry(i, i, .{ .kernel = true, .writable = true, .cachable = true });
    //     // log.debug("index: {}", .{i / memory.PAGE_SIZE});
    // }
    // log.debug("1/3: Mapped first 4 GiB of memory", .{});

    // // map higher half kernel address space
    // i = 0;
    // while (i < 4 * gib) : (i += memory.PAGE_SIZE) {
    //     try map_entry(memory.physical_to_virtual(i), i, .{ .kernel = true, .writable = true, .cachable = true });
    // }
    // log.debug("2/3: Mapped higher half kernel address space", .{});

    try map_entry(4096, 4096, .{ .kernel = true, .writable = true, .cachable = true });
    log.debug("Lets see", .{});
    activate_page_table(&root_page_table);
    log.debug("Survived", .{});
}
// pub fn init() !void {
//     const log = std.log.scoped(.paging);

//     log.debug("Setting up paging...; max {}", .{(4 * 1024 * 1024 * 1024) / memory.PAGE_SIZE});

//     const gib = 1024 * 1024 * 1024;

//     var i: u64 = 0;
//     while (i < 4 * gib) : (i += memory.PAGE_SIZE) {
//         try map_entry(i, i, .{ .kernel = true, .writable = true, .cachable = true });
//         // log.debug("index: {}", .{i / memory.PAGE_SIZE});
//     }
//     log.debug("1/3: Mapped first 4 GiB of memory", .{});

//     // map higher half kernel address space
//     i = 0;
//     while (i < 4 * gib) : (i += memory.PAGE_SIZE) {
//         try map_entry(memory.physical_to_virtual(i), i, .{ .kernel = true, .writable = true, .cachable = true });
//     }
//     log.debug("2/3: Mapped higher half kernel address space", .{});

//     log.debug("Lets see", .{});
//     activate_page_table(&root_page_table);
//     log.debug("Survived", .{});
// }
