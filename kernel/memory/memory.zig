const boot = @import("../boot.zig");

pub const PAGE_SIZE = 4096;

var ADDR_OFFSET: u64 = undefined;

/// Convert a physical address to its virtual counterpart by adding the kernel virtual offset to the physical address.
///
/// Arguments:
///     IN phys: anytype - The physical address to covert. Either an integer or pointer.
///
/// Return: @TypeOf(virt)
///     The virtual address.
pub fn physical_to_virtual(physical: anytype) @TypeOf(physical) {
    const T = @TypeOf(physical);

    return switch (@typeInfo(T)) {
        .Pointer => @ptrFromInt(@intFromPtr(physical) + ADDR_OFFSET),
        .Int => physical + ADDR_OFFSET,
        else => @compileError("Only pointers and integers are supported"),
    };
}

/// Convert a virtual address to its physical counterpart by subtracting the kernel virtual offset from the virtual address.
///
/// Arguments:
///     IN virt: anytype - The virtual address to covert. Either an integer or pointer.
///
/// Return: @TypeOf(virt)
///     The physical address.
pub fn virtual_to_physical(virtual: anytype) @TypeOf(virtual) {
    const T = @TypeOf(virtual);
    return switch (@typeInfo(T)) {
        .Pointer => @ptrFromInt(@intFromPtr(virtual) - ADDR_OFFSET),
        .Int => virtual - ADDR_OFFSET,
        else => @compileError("Only pointers and integers are supported"),
    };
}

pub fn init() void {
    ADDR_OFFSET = boot.directMapOffset();
}

// //const std = @import("std");
// const memory = @import("memory.zig");

// const ENTRIES_PER_TABLE = memory.PAGE_SIZE / @sizeOf(u64);

// const PageTable = packed struct {
//     entries: [ENTRIES_PER_TABLE]u64,
// };

// comptime {
//     std.debug.assert(ENTRIES_PER_TABLE == 512);
//     std.debug.assert(@sizeOf(PageTable) == memory.PAGE_SIZE);
// }

// var root_page_table: PageTable = .{
//     .entries = .{0} ** ENTRIES_PER_TABLE,
// };

// // Bit masks for setting and clearing attributes.
// const ENTRY_PRESENT: u64 = 0x1;
// const ENTRY_WRITABLE: u64 = 0x2;
// const ENTRY_USER: u64 = 0x4;
// const ENTRY_WRITE_THROUGH: u64 = 0x8;
// const ENTRY_CACHE_DISABLED: u64 = 0x10;
// const ENTRY_ACCESSED: u64 = 0x20;
// const ENTRY_ZERO: u64 = 0x40;
// const ENTRY_MEMORY_TYPE: u64 = 0x80;

// const AttributeMask = enum(u64) {
//     Present = 0x1,
//     Writable = 0x2,
//     User = 0x4,
//     WriteThrough = 0x8,
//     CacheDisabled = 0x10,
//     Accessed = 0x20,
//     Zero = 0x40,
//     MemoryType = 0x80,
// };

// /// Check if an entry has an attribute.
// inline fn has_attribute(entry: u64, attribute_mask: AttributeMask) bool {
//     return entry & @intFromEnum(attribute_mask) == @intFromEnum(attribute_mask);
// }

// /// Get the physical/frame address out of a page entry. Currently this is a 40 bit address, will
// /// need to check the CPUID 0x80000008 as this is hardcoded to 40 bits.
// ///
// /// Arguments:
// ///     IN entry: u64 - The page entry to get the frame from.
// ///
// /// Return: u64
// ///     The physical address. This will point to the next page entry in the chain.
// inline fn get_frame(entry: u64) u64 {
//     const FRAME_MASK = 0x000FFFFFFFFFF000;

//     return entry & FRAME_MASK;
// }

// // const PageLevel = enum(u8) {
// //     Four = 3,
// //     Three = 2,
// //     Two = 1,
// //     One = 0,
// // };

// /// Extract the three 9-bit page table indices from a virtual address.
// fn virtual_to_page_table_index(virtual_address: u64, level: u8) u9 {
//     std.debug.assert(1 <= level and level <= 4);

//     const MASK = 0b1_1111_1111; // 9 bits

//     // bits of offset within a page
//     const offset_shift = 12;
//     const level_shift = offset_shift + (9 * (level - 1));

//     return virtual_address >> level_shift & MASK;
// }

// /// Returns page table, if it is present.
// fn get_table_from_entry(entry: u64) ?*PageTable {
//     if (!has_attribute(entry, AttributeMask.Present)) {
//         return null;
//     }

//     const table_virtual_address = memory.physical_to_virtual(get_frame(entry));
//     return @ptrFromInt(table_virtual_address);
// }

// fn map(virtual_address: u64, physical_address: u64, flags: u64) void {
//     if (!std.mem.isAlignedGeneric(u64, virtual_address, memory.PAGE_SIZE)) {
//         std.debug.panic("virtual address to map 0x{x} is not aligned to page size", .{virtual_address});
//     }
//     if (!std.mem.isAlignedGeneric(u64, physical_address, memory.PAGE_SIZE)) {
//         std.debug.panic("physical address 0x{x} to be mapped is not aligned to page size", .{physical_address});
//     }

//     const pml4_index = virtual_to_page_table_index(virtual_address, 4);

//     const ptl3 = get_table_from_entry(root_page_table.entries[pml4_index]) orelse {
//         // Allocate one
//         var new_pml4_entry: u64 = 0;
//         const pdpt = &(try allocator.alignedAlloc(DirectoryPointerTable, PAGE_SIZE_4KB, 1))[0];
//         @memset(@ptrCast([*]u8, pdpt), 0, @sizeOf(DirectoryPointerTable));
//         const phys_addr = mem.virtToPhys(@ptrToInt(pdpt));
//         setFrame(&new_pml4_entry, phys_addr);
//         setAttribute(&new_pml4_entry, ENTRY_PRESENT);
//         setAllAttributes(&new_pml4_entry, attrs);
//         page_table.entries[pml4_part] = new_pml4_entry;
//         break :brk pdpt;
//     };
// }

// pub fn init() void {}
