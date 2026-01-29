const std = @import("std");

pub const Instructions = union(enum) {
    add: struct { regA: u8, valB: Operator },
    sub: struct { regA: u8, valB: Operator },
    mov: struct { regA: u8, valB: Operator },
    jmp: []const u8,
    je: []const u8,
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

                const addition = @addWithOverflow(self.registers[data.regA], valB);
                self.registers[data.regA] = addition[0];
                self.flags[2] = addition[1];

                if (self.registers[data.regA] == 0) {
                    self.flags[0] = 1;
                } else if (self.registers[data.regA] < 0) {
                    self.flags[1] = 1;
                } else {
                    self.flags[1] = 0;
                    self.flags[0] = 0;
                }
            },
            .sub => |data| {
                const valB = switch (data.valB) {
                    .register => |regIndex| self.registers[regIndex],
                    .value => |value| value,
                };

                const subtraction = @subWithOverflow(self.registers[data.regA], valB);

                self.registers[data.regA] = subtraction[0];
                self.flags[2] = subtraction[1];

                if (self.registers[data.regA] == 0) {
                    self.flags[0] = 1;
                } else if (self.registers[data.regA] < 0) {
                    self.flags[1] = 1;
                } else {
                    self.flags[1] = 0;
                    self.flags[0] = 0;
                }
            },
            .mov => |data| {
                const valB = switch (data.valB) {
                    .register => |regIndex| self.registers[regIndex],
                    .value => |value| value,
                };

                self.registers[data.regA] = valB;

                if (self.registers[data.regA] == 0) {
                    self.flags[0] = 1;
                } else if (self.registers[data.regA] < 0) {
                    self.flags[1] = 1;
                } else {
                    self.flags[1] = 0;
                    self.flags[0] = 0;
                }
            },
            else => {},
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
