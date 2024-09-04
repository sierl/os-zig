const boot = @import("../boot.zig");

/// phy addr -> virtual addr
pub fn directMapFromPhysicalAddress(physical_address: u64) u64 {
    const direct_map_offset = boot.directMapOffset();
    return physical_address + direct_map_offset;
}

/// Returns the physical range of the given direct map virtual range.
pub fn physicalAddressFromDirectMap(virtual_address: u64) u64 {
    const direct_map_offset = boot.directMapOffset();

    // TODO: should we wrap on overflow?
    return virtual_address -% direct_map_offset;
}

// -----------------------------
// const std = @import("std");
// const builtin = @import("builtin");
// const boot = @import("../boot.zig");
// const vmm = @import("vmm.zig");

// const log = std.log.scoped(.PMM);

// const page_size = 4096;

// const PageNode = struct {
//     next: ?*PageNode,
// };

// var free_list: ?*PageNode = null;

// pub fn init() void {
//     log.debug("adding free memory to pmm", .{});
//     addFreeMemory();
// }

// fn addFreeMemory() void {
//     var size: u64 = 0;
//     const memory_map_entries = boot.memoryMap();

//     for (memory_map_entries) |memory_map_entry| {
//         if (memory_map_entry.kind != .usable) {
//             continue;
//         }

//         addRange(memory_map_entry.base, memory_map_entry.length);
//         size += memory_map_entry.length;
//     }

//     log.debug("added {} bytes of memory to pmm", .{size});
// }

// fn addRange(physical_base_address: u64, size: u64) void {
//     if (!std.mem.isAlignedGeneric(u64, physical_base_address, page_size)) {
//         std.debug.panic("range address 0x{x} is not aligned to page size", .{physical_base_address});
//     }
//     if (!std.mem.isAlignedGeneric(u64, size, page_size)) {
//         std.debug.panic("range size 0x{x} is not aligned to page size", .{size});
//     }

//     var current_virtual_address = vmm.directMapFromPhysicalAddress(physical_base_address);

//     // This is the last virtual address *included* in the given range of memory
//     const last_virtual_address = current_virtual_address + size - 1;

//     log.debug("adding {} available pages from 0x{x} to 0x{x}", .{
//         size / page_size,
//         current_virtual_address,
//         last_virtual_address,
//     });

//     while (current_virtual_address <= last_virtual_address) : (current_virtual_address += page_size) {
//         const page_node: *PageNode = @ptrFromInt(current_virtual_address);

//         // Add page_node to the top of the list
//         page_node.next = free_list;
//         free_list = page_node;
//     }
// }

// fn fillPageWithJunk(page: *PageNode) void {
//     const byte_slice: []u8 = @as([*]u8, @ptrCast(page))[0..page_size];
//     @memset(byte_slice, undefined);
// }

// pub const AllocateError = error{OutOfPhysicalMemory};

// /// Allocates a physical page, returning its virtual address
// pub fn allocatePage() AllocateError!u64 {
//     // Allocate free page
//     const free_page_node = free_list orelse return AllocateError.OutOfPhysicalMemory;
//     free_list = free_page_node.next;

//     // Set memory to undefined
//     if (builtin.mode == .Debug or builtin.mode == .ReleaseSafe) {
//         fillPageWithJunk(free_page_node);
//     }

//     const virtual_address: u64 = @intFromPtr(free_page_node);

//     // Convert free page's virtual address to physical address
//     const physical_address = vmm.physicalAddressFromDirectMap(virtual_address);

//     log.debug("allocated at physical address 0x{x} or virtual address 0x{x}", .{ physical_address, virtual_address });

//     return physical_address;
// }

// /// Deallocates a physical page.
// ///
// /// **REQUIREMENTS**:
// /// - `address` must be aligned to `kernel.arch.paging.standard_page_size`
// pub fn deallocatePage(physical_address: u64) void {
//     std.debug.assert(std.mem.isAlignedGeneric(u64, physical_address, page_size));

//     const virtual_address = vmm.directMapFromPhysicalAddress(physical_address);
//     const page_node: *PageNode = @ptrFromInt(virtual_address);

//     // Set memory to undefined
//     if (builtin.mode == .Debug or builtin.mode == .ReleaseSafe) {
//         fillPageWithJunk(page_node);
//     }

//     // TODO: Add lock when we have concurrency
//     page_node.next = free_list;
//     free_list = page_node;

//     log.debug("deallocated at physical address 0x{x} or virtual address 0x{x}", .{ physical_address, virtual_address });
// }
