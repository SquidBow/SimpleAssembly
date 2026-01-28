const std = @import("std");

pub const Instructions = union(enum) {
    add: struct { regA: u8, valB: Operator },
    sub: struct { regA: u8, valB: Operator },
    mov: struct { regA: u8, valB: Operator },
};

pub const Operator = union(enum) {
    register: u8,
    value: i32,
};

pub const Cpu = struct {
    registers: [4]i32,
    flags: [8]u8,

    pub fn init() Cpu {
        return Cpu{
            .registers = [_]i32{0} ** 4,
            .flags = [_]u8{0} ** 8,
        };
    }

    pub fn executeInstruction(self: *Cpu, instruction: Instructions) !void {
        switch (instruction) {
            .add => |data| {
                const valB = switch (data.valB) {
                    .register => |regIndex| self.registers[regIndex],
                    .value => |value| value,
                };

                self.registers[data.regA] += valB;
            },
            .sub => |data| {
                const valB = switch (data.valB) {
                    .register => |regIndex| self.registers[regIndex],
                    .value => |value| value,
                };

                self.registers[data.regA] -= valB;
            },
            .mov => |data| {
                const valB = switch (data.valB) {
                    .register => |regIndex| self.registers[regIndex],
                    .value => |value| value,
                };

                self.registers[data.regA] = valB;
            },
        }
    }
};

test "InstructionsAdd" {
    var cpu = Cpu.init();
    const instruction = Instructions{ .add = .{ .regA = 0, .valB = .{ .value = 5 } } };

    try cpu.executeInstruction(instruction);
    try std.testing.expect(cpu.registers[0] == 5);
}

test "InstructionsSub" {
    var cpu = Cpu.init();
    const instruction = Instructions{ .sub = .{ .regA = 0, .valB = .{ .value = -5 } } };

    try cpu.executeInstruction(instruction);
    try std.testing.expect(cpu.registers[0] == 5);
}

test "InstructionsMov" {
    var cpu = Cpu.init();
    const instruction = Instructions{ .mov = .{ .regA = 0, .valB = .{ .value = 5 } } };

    try cpu.executeInstruction(instruction);
    try std.testing.expect(cpu.registers[0] == 5);
}

test "AddSubMov" {
    var cpu = Cpu.init();
    // std.debug.print("Welcome to my new pc: {s}.\n", .{pc.name});

    var myInstruction = Instructions{ .add = .{ .regA = 0, .valB = .{ .value = 10 } } };
    try cpu.executeInstruction(myInstruction);

    myInstruction = Instructions{ .sub = .{ .regA = 0, .valB = .{ .value = 5 } } };
    try cpu.executeInstruction(myInstruction);

    myInstruction = Instructions{ .mov = .{ .regA = 1, .valB = .{ .value = 4 } } };
    try cpu.executeInstruction(myInstruction);

    myInstruction = Instructions{ .sub = .{ .regA = 0, .valB = .{ .register = 1 } } };
    try cpu.executeInstruction(myInstruction);

    try std.testing.expect(cpu.registers[0] == 1);
}
