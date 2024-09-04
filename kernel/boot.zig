const std = @import("std");
const limine = @import("limine");

export var base_revision: limine.BaseRevision = .{ .revision = 2 };

// From docs:
// Memory between 0 and 0x1000 is never marked as usable memory. The kernel
// and modules loaded are not marked as usable memory. They are marked as
// Kernel/Modules. The entries are guaranteed to be sorted by base address,
// lowest to highest. Usable and bootloader reclaimable entries are guaranteed
// to be 4096 byte aligned for both base and length. Usable and bootloader
// reclaimable entries are guaranteed not to overlap with any other entry.
// To the contrary, all non-usable entries (including kernel/modules) are
// not guaranteed any alignment, nor is it guaranteed that they do not
// overlap other entries.
export var memory_map_request: limine.MemoryMapRequest = .{};

export var hhdm_request: limine.HhdmRequest = .{};

export var paging_mode_request: limine.PagingModeRequest = .{
    .mode = limine.PagingMode.four_level,
    .flags = 0,
};

export var kernel_address_request: limine.KernelAddressRequest = .{};

pub fn init() void {
    // Ensure the bootloader actually understands our base revision (see spec).
    if (!base_revision.is_supported()) {
        std.debug.panic("bootloader revision {} is not supported", .{base_revision.revision});
    }

    // Ensure the correct paging mode is set
    if (paging_mode_request.response) |response| {
        if (response.mode != paging_mode_request.mode) {
            std.debug.panic("bootloader used paging mode {any}; but requested {any}", .{
                response.mode,
                paging_mode_request.mode,
            });
        }
    } else {
        std.debug.panic("bootloader didn't provide paging mode", .{});
    }
}

pub fn memoryMap() []*limine.MemoryMapEntry {
    if (memory_map_request.response) |response| {
        return response.entries();
    }

    std.debug.panic("bootloader didn't provide memory map", .{});
}

/// Returns the direct map offset provided by the bootloader.
pub fn directMapOffset() u64 {
    if (hhdm_request.response) |hhdm_response| {
        return hhdm_response.offset;
    }

    std.debug.panic("bootloader didn't provide direct map offset", .{});
}

pub const KernelBaseAddress = struct {
    virtual_base: u64,
    physical_base: u64,
};

/// Returns the kernel virtual and physical base addresses provided by the bootloader, if any.
pub fn kernelBaseAddress() KernelBaseAddress {
    if (kernel_address_request.response) |kernel_address_response| {
        return .{
            .virtual_base = kernel_address_response.virtual_base,
            .physical_base = kernel_address_response.physical_base,
        };
    }

    std.debug.panic("bootloader didn't provide kernel base address", .{});
}
