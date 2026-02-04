const std = @import("std");

pub const Instructions = union(enum) {
    add: struct { regA: u8, valB: Operator },
    sub: struct { regA: u8, valB: Operator },
    mov: struct { regA: u8, valB: Operator },
    cmp: struct { valA: Operator, valB: Operator },
    jmp: Label,
    je: Label,
    print: Operator,
};

pub const Label = union(enum) {
    value: u32,
    label: []const u8,
};

pub const Operator = union(enum) {
    register: u8,
    value: i32,
    string: []const u8,
};

pub const DataTypes = enum {
    db,
    dw,
    dd,
    string,
};

pub const Variable = struct {
    pointer: u32,
    dataType: DataTypes,
    len: usize,
};

pub const Cpu = struct {
    registers: [4]i32 = .{0} ** 4,
    flags: [3]u8 = .{0} ** 3,
    ram: [1024]u8 = undefined,
    dataTable: std.StringHashMap(Variable),
    codeTable: std.StringHashMap(u32),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Cpu {
        return Cpu{
            .dataTable = std.StringHashMap(Variable).init(allocator),
            .codeTable = std.StringHashMap(u32).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Cpu) void {
        self.dataTable.deinit();
        self.codeTable.deinit();
    }

    pub fn executeInstruction(self: *Cpu, instruction: Instructions) !void {
        switch (instruction) {
            .add => |data| {
                const valB = self.parseOperator(data.valB);

                const addition = @addWithOverflow(self.registers[data.regA], valB);
                self.registers[data.regA] = addition[0];
                self.flags[2] = addition[1];

                self.flags[0] = if (self.registers[data.regA] == 0) 1 else 0;
                self.flags[1] = if (self.registers[data.regA] < 0) 1 else 0;
            },
            .sub => |data| {
                const valB = self.parseOperator(data.valB);

                const subtraction = @subWithOverflow(self.registers[data.regA], valB);

                self.registers[data.regA] = subtraction[0];
                self.flags[2] = subtraction[1];

                self.flags[0] = if (self.registers[data.regA] == 0) 1 else 0;
                self.flags[1] = if (self.registers[data.regA] < 0) 1 else 0;
            },
            .mov => |data| {
                const valB = self.parseOperator(data.valB);

                self.registers[data.regA] = valB;

                self.flags[0] = if (self.registers[data.regA] == 0) 1 else 0;
                self.flags[1] = if (self.registers[data.regA] < 0) 1 else 0;
            },
            .cmp => |data| {
                const valB = self.parseOperator(data.valB);

                const valA = self.parseOperator(data.valA);

                const subtraction = valA - valB;

                self.flags[0] = if (subtraction == 0) 1 else 0;
                self.flags[1] = if (subtraction < 0) 1 else 0;
            },
            .print => |operator| {
                self.print(operator);
            },
            else => {},
        }
    }

    fn print(self: *Cpu, op: Operator) void {
        switch (op) {
            .register => |reg| {
                const char: u8 = @intCast(self.registers[reg]);
                std.debug.print("{c}", .{char});
            },
            .value => |value| {
                const char: u8 = @intCast(value);
                std.debug.print("{c}", .{char});
            },
            .string => |string| std.debug.print("{s}", .{string}),
        }
    }

    fn parseOperator(self: *Cpu, op: Operator) i32 {
        return switch (op) {
            .register => |regIndex| self.registers[regIndex],
            .value => |value| value,
            else => 0,
        };
    }

    pub fn printRegisters(self: *Cpu) void {
        for (0.., self.registers) |index, register| {
            std.debug.print("Reg {d}: {d}\t", .{ index, register });
        }
    }

    pub fn executeCode(self: *Cpu, instructions: []Instructions) void {
        {
            var i: u32 = 0;

            while (i < instructions.len) : ({
                i += 1;
            }) {
                const instruction = instructions[i];

                switch (instruction) {
                    .jmp => |line| {
                        i = line.value;
                        i -= 1;
                    },
                    .je => |line| {
                        if (self.flags[0] == 1) {
                            i = line.value;
                            i -= 1;
                        }
                    },
                    else => {
                        try self.executeInstruction(instruction);
                        // if (instruction != .cmp) {
                        //     self.printRegisters();
                        //     std.debug.print("\n", .{});
                        // }
                    },
                }
            }
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
