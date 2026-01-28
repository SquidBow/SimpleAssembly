const std = @import("std");
const root = @import("root.zig");

pub fn main() !void {
    var cpu = root.Cpu.init();
    // std.debug.print("Welcome to my new pc: {s}.\n", .{pc.name});

    var myInstruction = root.Instructions{ .add = .{ .regA = 0, .valB = .{ .value = 10 } } };
    try cpu.executeInstruction(myInstruction);

    myInstruction = root.Instructions{ .sub = .{ .regA = 0, .valB = .{ .value = 5 } } };
    try cpu.executeInstruction(myInstruction);

    myInstruction = root.Instructions{ .mov = .{ .regA = 1, .valB = .{ .value = 4 } } };
    try cpu.executeInstruction(myInstruction);

    myInstruction = root.Instructions{ .sub = .{ .regA = 0, .valB = .{ .register = 1 } } };
    try cpu.executeInstruction(myInstruction);

    std.debug.print("Reg 0: {d}", .{cpu.registers[0]});
}
