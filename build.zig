const std = @import("std");

pub fn build(b: *std.Build) void {
    b.top_level_steps.clearRetainingCapacity();

    // Build the kernel
    // Define a freestanding x86_64 cross-compilation target.
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .abi = .none,

        // Disable CPU features that require additional initialization
        // like MMX, SSE/2 and AVX. That requires us to enable the soft-float feature.
        .cpu_features_add = std.Target.x86.featureSet(&.{.soft_float}),
        .cpu_features_sub = std.Target.x86.featureSet(&.{ .mmx, .sse, .sse2, .avx, .avx2 }),
    });

    const optimize = b.standardOptimizeOption(.{});

    const kernel = b.addExecutable(.{
        .name = "kernel",
        .root_source_file = b.path("kernel/kmain.zig"),
        .target = target,
        .optimize = optimize,
        .code_model = .kernel,
    });
    kernel.want_lto = false;
    kernel.setLinkerScriptPath(b.path("meta/linker.ld"));

    const limine = b.dependency("limine", .{});
    kernel.root_module.addImport("limine", limine.module("limine"));

    const kernel_step = b.step("kernel", "Build the kernel");
    // b.installArtifact(kernel);
    kernel_step.dependOn(&b.addInstallArtifact(kernel, .{}).step);

    // Copy over the required files
    const iso_dir_tree = b.addWriteFiles();
    _ = iso_dir_tree.addCopyFile(kernel.getEmittedBin(), "kernel");
    _ = iso_dir_tree.addCopyFile(b.path("meta/limine.conf"), "limine.conf");
    _ = iso_dir_tree.addCopyFile(b.path("vendor/limine/limine-bios.sys"), "limine-bios.sys");
    _ = iso_dir_tree.addCopyFile(b.path("vendor/limine/limine-uefi-cd.bin"), "limine-uefi-cd.bin");
    _ = iso_dir_tree.addCopyFile(b.path("vendor/limine/limine-bios-cd.bin"), "limine-bios-cd.bin");

    // Make xorriso command
    const iso_xorriso = b.addSystemCommand(&.{"xorriso"});
    iso_xorriso.addArgs(&.{ "-report_about", "ALL" });
    iso_xorriso.addArgs(&.{ "-as", "mkisofs" });
    iso_xorriso.addArgs(&.{ "-b", "limine-bios-cd.bin" });
    iso_xorriso.addArg("-no-emul-boot");
    iso_xorriso.addArgs(&.{ "-boot-load-size", "4" });
    iso_xorriso.addArg("-boot-info-table");
    iso_xorriso.addArgs(&.{ "--efi-boot", "limine-uefi-cd.bin" });
    iso_xorriso.addArg("-efi-boot-part");
    iso_xorriso.addArg("--efi-boot-image");
    iso_xorriso.addArg("--protective-msdos-label");
    iso_xorriso.addDirectoryArg(iso_dir_tree.getDirectory());
    iso_xorriso.addArg("-o");
    const iso_path = iso_xorriso.addOutputFileArg("disk.iso");

    // run limine on generated iso
    const run_limine = b.addSystemCommand(&.{"vendor/limine/limine"});
    run_limine.addArg("bios-install");
    run_limine.addFileArg(iso_path);
    // run_limine.addArg("--quiet");
    // run_limine.has_side_effects = true;
    run_limine.step.dependOn(&b.addInstallFile(iso_path, "disk.iso").step);

    const iso_step = b.step("iso", "Create a ISO");
    iso_step.dependOn(&run_limine.step);

    b.default_step = iso_step;

    // Make qemu command
    const qemu = b.addSystemCommand(&.{"qemu-system-x86_64"});
    qemu.addArg("-cdrom");
    qemu.addFileArg(iso_path);
    qemu.addArgs(&.{ "-m", "2G" });
    qemu.addArgs(&.{ "-serial", "stdio" });
    // qemu.addArgs(&.{ "-no-reboot", "-no-shutdown" });
    qemu.step.dependOn(iso_step);
    qemu.step.dependOn(kernel_step);

    const qemu_step = b.step("qemu", "Run the stub ISO in QEMU");
    qemu_step.dependOn(&qemu.step);
    // qemu_step.dependOn(iso_step);

    //
    const qemu_debug = b.addSystemCommand(&.{"qemu-system-x86_64"});
    qemu_debug.addArg("-cdrom");
    qemu_debug.addFileArg(iso_path);
    qemu_debug.addArgs(&.{ "-serial", "stdio" });
    qemu_debug.addArg("-S");
    qemu_debug.addArgs(&.{ "-gdb", "tcp::9999" });

    const debug_step = b.step("debug", "Debug the kernel");
    debug_step.dependOn(&qemu_debug.step);

    // const kernel_unit_tests = b.addTest(.{
    //     .root_source_file = b.path("kernel/kmain.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });
    // kernel_unit_tests.root_module.addImport("limine", limine.module("limine"));

    // const run_kernel_unit_tests = b.addRunArtifact(kernel_unit_tests);

    // // Similar to creating the run step earlier, this exposes a `test` step to
    // // the `zig build --help` menu, providing a way for the user to request
    // // running the unit tests.
    // const test_step = b.step("test", "Run unit tests");
    // test_step.dependOn(&run_kernel_unit_tests.step);
}
