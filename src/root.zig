const std = @import("std");

pub const Instructions = union(enum) {
    add: struct { regA: u8, valB: Operator },
    sub: struct { regA: u8, valB: Operator },
    mov: struct { regA: u8, valB: Operator },
    cmp: struct { valA: Operator, valB: Operator },
    jmp: []const u8,
    je: []const u8,
    print: u8,
};

pub const Operator = union(enum) {
    register: u8,
    value: i32,
};

pub const Cpu = struct {
    registers: [4]i32,
    flags: [3]u8,

    pub fn init() Cpu {
        return Cpu{
            .registers = [_]i32{0} ** 4,
            .flags = [_]u8{0} ** 3,
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

                self.flags[0] = if (self.registers[data.regA] == 0) 1 else 0;
                self.flags[1] = if (self.registers[data.regA] < 0) 1 else 0;
            },
            .sub => |data| {
                const valB = switch (data.valB) {
                    .register => |regIndex| self.registers[regIndex],
                    .value => |value| value,
                };

                const subtraction = @subWithOverflow(self.registers[data.regA], valB);

                self.registers[data.regA] = subtraction[0];
                self.flags[2] = subtraction[1];

                self.flags[0] = if (self.registers[data.regA] == 0) 1 else 0;
                self.flags[1] = if (self.registers[data.regA] < 0) 1 else 0;
            },
            .mov => |data| {
                const valB = switch (data.valB) {
                    .register => |regIndex| self.registers[regIndex],
                    .value => |value| value,
                };

                self.registers[data.regA] = valB;

                self.flags[0] = if (self.registers[data.regA] == 0) 1 else 0;
                self.flags[1] = if (self.registers[data.regA] < 0) 1 else 0;
            },
            .cmp => |data| {
                const valB = switch (data.valB) {
                    .register => |regIndex| self.registers[regIndex],
                    .value => |value| value,
                };

                const valA = switch (data.valA) {
                    .register => |regIndex| self.registers[regIndex],
                    .value => |value| value,
                };

                const subtraction = valA - valB;

                self.flags[0] = if (subtraction == 0) 1 else 0;
                self.flags[1] = if (subtraction < 0) 1 else 0;
            },
            .print => |reg| {
                const char: u8 = @intCast(self.registers[reg]);
                std.debug.print("{c}", .{char});
            },
            else => {},
        }
    }

    pub fn printRegisters(self: *Cpu) void {
        for (0.., self.registers) |index, register| {
            std.debug.print("Reg {d}: {d}\t", .{ index, register });
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
