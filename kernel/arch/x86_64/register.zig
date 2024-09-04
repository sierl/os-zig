/// RFLAGS Register
pub const RFLAGS = packed struct(u64) {
    /// Carry Flag
    carry: bool,
    /// Reserved
    reserve_1: u1 = 1,
    /// Parity Flag
    parity: bool,
    /// Reserved
    reserve_2: u1 = 0,
    /// Auxiliary Carry Flag
    auxiliary_carry: bool,
    /// Reserved
    reserve_3: u1 = 0,
    /// Zero Flag
    zero: bool,
    /// Sign Flag
    sign: bool,
    /// Trap Flag
    trap: bool,
    /// Interrupt Enable Flag
    interrupt_enable: bool,
    /// Direction Flag
    direction: bool,
    /// Overflow Flag
    overflow: bool,
    /// I/O Privilege Level
    io_privilege_level: u2,
    /// Nested Task
    nested_task: bool,
    /// Reserved
    reserve_4: u1 = 0,
    /// Resume Flag
    @"resume": bool,
    /// Virtual-8086 Mode
    virtual_8086: bool,
    /// Alignment Check / Access Control
    alignment_check: bool,
    /// Virtual Interrupt Flag
    virtual_interrupt: bool,
    /// Virtual Interrupt Pending
    virtual_interrupt_pending: bool,
    /// ID Flag
    id: bool,
    /// Reserved
    reserve_5: u42,
};
