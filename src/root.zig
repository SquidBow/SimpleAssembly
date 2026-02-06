const std = @import("std");

pub const Instructions = union(enum) {
    add: struct { valA: u8, valB: Operator },
    sub: struct { valA: u8, valB: Operator },
    mov: struct { valA: u8, valB: Operator },
    cmp: struct { valA: Operator, valB: Operator },
    jmp: Label,
    je: Label,
    print: Operator,
    write: struct { valA: Operator, valB: Operator },
};

pub const Label = union(enum) {
    value: u32,
    label: []const u8,
};

pub const Operator = union(enum) {
    register: u8,
    value: u32,
    string: []const u8,
    label: []const u8,
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
    registers: [4]u32 = .{0} ** 4,
    flags: [3]u8 = .{0} ** 3, //0.Zero, 1.Sign, 2.Carry
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
                const valB = try self.parseOperatorValue(data.valB);

                const addition = @addWithOverflow(self.registers[data.valA], valB);
                self.registers[data.valA] = addition[0];
                self.flags[2] = addition[1];

                self.flags[0] = if (self.registers[data.valA] == 0) 1 else 0;
                self.flags[1] = if (@as(i32, @bitCast(self.registers[data.valA])) < 0) 1 else 0;
            },
            .sub => |data| {
                const valB = try self.parseOperatorValue(data.valB);

                const subtraction = @subWithOverflow(self.registers[data.valA], valB);

                self.registers[data.valA] = subtraction[0];
                self.flags[2] = subtraction[1];

                self.flags[0] = if (self.registers[data.valA] == 0) 1 else 0;
                self.flags[1] = if (@as(i32, @bitCast(self.registers[data.valA])) < 0) 1 else 0;
            },
            .mov => |data| {
                const valB = try self.parseOperatorValue(data.valB);

                self.registers[data.valA] = valB;

                self.flags[0] = if (self.registers[data.valA] == 0) 1 else 0;
                self.flags[1] = if (@as(i32, @bitCast(self.registers[data.valA])) < 0) 1 else 0;
            },
            .cmp => |data| {
                const valB = try self.parseOperatorValue(data.valB);
                const valA = try self.parseOperatorValue(data.valA);

                self.flags[0] = if (valA == valB) 1 else 0;
                self.flags[1] = if (valA < valB) 1 else 0;
            },
            .print => |operator| {
                self.print(operator) catch {
                    // std.debug.print("Failed to print: {any}\n", .{operator});
                    return error.UnableToPrintOperator;
                };
            },
            .write => |data| {
                self.WriteToOpearator(data.valA, data.valB) catch {
                    std.debug.print("Failed to write to ram", .{});
                    return error.FailedToWriteToRam;
                };
            },
            else => {},
        }
    }

    fn print(self: *Cpu, op: Operator) !void {
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
            .label => |label| if (self.dataTable.get(label)) |variable| {
                return switch (variable.dataType) {
                    .db => {
                        const value = std.mem.readInt(u8, self.ram[variable.pointer..][0..1], .little);
                        std.debug.print("{c}", .{value});
                    },
                    .dw => {
                        const value = std.mem.readInt(u16, self.ram[variable.pointer..][0..2], .little);
                        const char: u8 = @intCast(value);
                        std.debug.print("{c}", .{char});
                    },
                    .dd => {
                        const value = std.mem.readInt(u32, self.ram[variable.pointer..][0..4], .little);
                        const char: u8 = @intCast(value);
                        std.debug.print("{c}", .{char});
                    },
                    .string => {
                        std.debug.print("{s}", .{self.ram[variable.pointer .. variable.pointer + variable.len]});
                    },
                };
            } else {
                std.debug.print("Vairable: {s} doesn't exist\n", .{label});
                return error.InvalidVairableName;
            },
        }
    }

    fn parseOperatorValue(self: *Cpu, op: Operator) !u32 {
        return switch (op) {
            .register => |regIndex| self.registers[regIndex],
            .value => |value| value,
            .string => error.InvalidDataType,
            .label => |label| if (self.dataTable.get(label)) |variable| {
                return switch (variable.dataType) {
                    .db => std.mem.readInt(u8, self.ram[variable.pointer..][0..1], .little),
                    .dw => std.mem.readInt(u16, self.ram[variable.pointer..][0..2], .little),
                    .dd => std.mem.readInt(u32, self.ram[variable.pointer..][0..4], .little),
                    .string => error.InvalidDataType,
                };
            } else return error.InvalidVairableName,
        };
    }

    fn WriteToOpearator(self: *Cpu, write: Operator, read: Operator) !void {
        switch (write) {
            .register => |regIndex| {
                self.registers[regIndex] = try self.parseOperatorValue(read);
            },
            .value => |value| {
                self.WriteToRam(read, value) catch {
                    std.debug.print("Failed to write to ram", .{});
                    return error.FailedToWriteToRam;
                };
            },
            .label => |label| if (self.dataTable.get(label)) |variable| {
                self.WriteToRam(read, variable.pointer) catch {
                    std.debug.print("Failed to write to ram", .{});
                    return error.FailedToWriteToRam;
                };
            } else return error.InvalidVairableName,
            .string => return error.CantWriteToAString,
        }
    }

    fn WriteToRam(self: *Cpu, operator: Operator, ramPointer: usize) !void {
        switch (operator) {
            .register => |reg| {
                const value = self.registers[reg];

                if (value < std.math.maxInt(u8)) {
                    self.ram[ramPointer] = @as(u8, @intCast(value));
                } else if (value < std.math.maxInt(u16)) {
                    std.mem.writeInt(u16, self.ram[ramPointer..][0..2], @as(u16, @intCast(value)), .little);
                } else {
                    std.mem.writeInt(u32, self.ram[ramPointer..][0..4], value, .little);
                }
            },
            .value => |value| {
                if (value < std.math.maxInt(u8)) {
                    self.ram[ramPointer] = @as(u8, @intCast(value));
                } else if (value < std.math.maxInt(u16)) {
                    std.mem.writeInt(u16, self.ram[ramPointer..][0..2], @as(u16, @intCast(value)), .little);
                } else if (value < std.math.maxInt(u32)) {
                    std.mem.writeInt(u32, self.ram[ramPointer..][0..4], value, .little);
                } else return error.NumberIsTooBig;
            },
            .string => |string| {
                @memcpy(self.ram[ramPointer .. ramPointer + string.len], string);
            },
            .label => |label| {
                if (self.dataTable.get(label)) |variable| {
                    switch (variable.dataType) {
                        .db => {
                            const value: u8 = std.mem.readInt(u8, self.ram[variable.pointer..][0..1], .little);
                            // std.debug.print("\n\nValue: {}\n\n", .{value});
                            self.ram[ramPointer] = value;
                            // const value2: u8 = self.ram[ramPointer];
                            // std.debug.print("\n\nValue2: {}\n\n", .{value2});
                        },
                        .dw => {
                            const value: u16 = std.mem.readInt(u16, self.ram[variable.pointer..][0..2], .little);
                            std.mem.writeInt(u16, self.ram[ramPointer..][0..2], value, .little);
                        },
                        .dd => {
                            const value: u32 = std.mem.readInt(u32, self.ram[variable.pointer..][0..4], .little);
                            std.mem.writeInt(u32, self.ram[ramPointer..][0..4], value, .little);
                        },
                        .string => {
                            const string: []const u8 = self.ram[variable.pointer .. variable.len + 1];
                            @memcpy(self.ram[ramPointer .. ramPointer + string.len], string);
                        },
                    }
                }
            },
        }
    }

    pub fn printRegisters(self: *Cpu) void {
        for (0.., self.registers) |index, register| {
            std.debug.print("Reg {d}: {d}\t", .{ index, register });
        }
    }

    pub fn executeCode(self: *Cpu, instructions: []Instructions) !void {
        {
            var i: u32 = 0;

            while (i < instructions.len) : ({
                i += 1;
            }) {
                const instruction = instructions[i];

                switch (instruction) {
                    .jmp => |label| {
                        i = self.parseLabel(label) catch {
                            std.debug.print("Unable to parse the label", .{});
                            return;
                        };
                        i -= 1;
                    },
                    .je => |label| {
                        if (self.flags[0] == 1) {
                            i = self.parseLabel(label) catch {
                                std.debug.print("Unable to parse the label", .{});
                                return;
                            };
                            i -= 1;
                        }
                    },
                    else => {
                        try self.executeInstruction(instruction);
                    },
                }
            }
        }
    }

    fn parseLabel(self: *Cpu, label: Label) !u32 {
        return switch (label) {
            .value => |value| value,
            .label => |string| self.codeTable.get(string) orelse error.InvalidLabel,
        };
    }
};

test "InstructionsAdd" {
    var cpu = Cpu.init();
    const instruction = Instructions{ .add = .{ .valA = 0, .valB = .{ .value = 5 } } };

    try cpu.executeInstruction(instruction);
    try std.testing.expect(cpu.registers[0] == 5);
}

test "InstructionsSub" {
    var cpu = Cpu.init();
    const instruction = Instructions{ .sub = .{ .valA = 0, .valB = .{ .value = -5 } } };

    try cpu.executeInstruction(instruction);
    try std.testing.expect(cpu.registers[0] == 5);
}

test "InstructionsMov" {
    var cpu = Cpu.init();
    const instruction = Instructions{ .mov = .{ .valA = 0, .valB = .{ .value = 5 } } };

    try cpu.executeInstruction(instruction);
    try std.testing.expect(cpu.registers[0] == 5);
}

test "AddSubMov" {
    var cpu = Cpu.init();

    var myInstruction = Instructions{ .add = .{ .valA = 0, .valB = .{ .value = 10 } } };
    try cpu.executeInstruction(myInstruction);

    myInstruction = Instructions{ .sub = .{ .valA = 0, .valB = .{ .value = 5 } } };
    try cpu.executeInstruction(myInstruction);

    myInstruction = Instructions{ .mov = .{ .valA = 1, .valB = .{ .value = 4 } } };
    try cpu.executeInstruction(myInstruction);

    myInstruction = Instructions{ .sub = .{ .valA = 0, .valB = .{ .register = 1 } } };
    try cpu.executeInstruction(myInstruction);

    try std.testing.expect(cpu.registers[0] == 1);
}
