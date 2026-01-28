const std = @import("std");
const root = @import("root.zig");

pub fn main() !void {
    var cpu = root.Cpu.init();
    // std.debug.print("Welcome to my new pc: {s}.\n", .{pc.name});

    const myInstruction = root.Instructions{ .add = .{ .regA = 0, .valB = .{ .value = 1 } } };

    try cpu.executeInstruction(myInstruction);

    std.debug.print("Reg 0: {d}", .{cpu.registers[0]});
}
