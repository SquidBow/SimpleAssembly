const std = @import("std");

pub const Instructions = union(enum) {
    add: struct { reg: u8, val: Operand },
    sub: struct { reg: u8, val: Operand },
    mov: struct { reg: u8, val: Operand },
    cmp: struct { valA: Operand, valB: Operand },
    jmp: Label,
    je: Label,
    print: Operand,
    write: struct { destination: Operand, data: Operand },
    read: struct { register: u8, dataPointer: Operand },
    readCmpl: struct { destination: Operand, dataPointer: Operand, dataType: DataTypes, stringLength: usize },
    push: u8,
    pop: u8,
};

pub const Label = union(enum) {
    value: u32,
    label: []const u8,
};

pub const Operand = union(enum) {
    register: u8,
    value: u32,
    string: []const u8,
    label: []const u8,
};

pub const DataTypes = enum {
    // none,
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
    stackPointer: usize = 1024,
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
                const valB = try self.parseOperandValue(data.val);

                const addition = @addWithOverflow(self.registers[data.reg], valB);
                self.registers[data.reg] = addition[0];
                self.flags[2] = addition[1];

                self.flags[0] = if (self.registers[data.reg] == 0) 1 else 0;
                self.flags[1] = if (@as(i32, @bitCast(self.registers[data.reg])) < 0) 1 else 0;
            },
            .sub => |data| {
                const valB = try self.parseOperandValue(data.val);

                const subtraction = @subWithOverflow(self.registers[data.reg], valB);

                self.registers[data.reg] = subtraction[0];
                self.flags[2] = subtraction[1];

                self.flags[0] = if (self.registers[data.reg] == 0) 1 else 0;
                self.flags[1] = if (@as(i32, @bitCast(self.registers[data.reg])) < 0) 1 else 0;
            },
            .mov => |data| {
                const valB = try self.parseOperandValue(data.val);

                self.registers[data.reg] = valB;

                self.flags[0] = if (self.registers[data.reg] == 0) 1 else 0;
                self.flags[1] = if (@as(i32, @bitCast(self.registers[data.reg])) < 0) 1 else 0;
            },
            .cmp => |data| {
                const valB = try self.parseOperandValue(data.valA);
                const valA = try self.parseOperandValue(data.valB);

                self.flags[0] = if (valA == valB) 1 else 0;
                self.flags[1] = if (valA < valB) 1 else 0;
            },
            .print => |operand| {
                self.print(operand) catch {
                    // std.debug.print("Failed to print: {any}\n", .{Operand});
                    return error.UnableToPrintOperand;
                };
            },
            .write => |data| {
                const destination = self.parseOperandDestination(data.destination) catch {
                    std.debug.print("Failed to write to ram\n", .{});
                    return error.FailedToWriteToRam;
                };
                self.WriteToRam(data.data, destination) catch {
                    std.debug.print("Was unable to write to ram at: {}\n", .{destination});
                    return error.FailedToWriteToRam;
                };
            },
            .readCmpl => |data| {
                const dataPointer = try self.parseOperandDestination(data.dataPointer);
                // std.debug.print("\n\nDataPointer: {d}\n\n", .{dataPointer});

                switch (data.destination) {
                    .register => |reg| {
                        self.registers[reg] = switch (data.dataType) {
                            .db => std.mem.readInt(u8, self.ram[dataPointer..][0..1], .little),
                            .dw => std.mem.readInt(u16, self.ram[dataPointer..][0..2], .little),
                            .dd => std.mem.readInt(u32, self.ram[dataPointer..][0..4], .little),
                            else => return error.InvalidDataType,
                        };
                    },
                    else => {
                        const destination = self.parseOperandDestination(data.destination) catch {
                            std.debug.print("Unable to find destination to read to", .{});
                            return error.InvalidDestination;
                        };

                        switch (data.dataType) {
                            .string => {
                                if (data.stringLength == 0) return error.InvalidStringLength;
                                @memmove(self.ram[destination..][0..data.stringLength], self.ram[dataPointer..][0..data.stringLength]);
                            },
                            .db => self.ram[destination] = self.ram[dataPointer],
                            .dw => {
                                const value: u16 = std.mem.readInt(u16, self.ram[dataPointer..][0..2], .little);
                                std.mem.writeInt(u16, self.ram[destination..][0..2], value, .little);
                            },
                            .dd => {
                                const value: u32 = std.mem.readInt(u32, self.ram[dataPointer..][0..4], .little);
                                std.mem.writeInt(u32, self.ram[destination..][0..4], value, .little);
                            },
                        }
                    },
                }
            },
            .read => |data| {
                const dataPointer = try self.parseOperandDestination(data.dataPointer);

                self.registers[data.register] = std.mem.readInt(u32, self.ram[dataPointer..][0..4], .little);
            },
            .push => |register| {
                if (self.stackPointer < 4) {
                    return error.StackOverflow;
                }

                self.stackPointer -= 4;

                std.mem.writeInt(u32, self.ram[self.stackPointer..][0..4], self.registers[register], .little);
            },
            .pop => |register| {
                if (self.stackPointer == 1024) {
                    return error.StackIsEmpty;
                }

                self.registers[register] = std.mem.readInt(u32, self.ram[self.stackPointer..][0..4], .little);
                self.stackPointer += 4;
            },
            else => {},
        }
    }

    fn print(self: *Cpu, op: Operand) !void {
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
                    // .none => {},
                };
            } else {
                std.debug.print("Vairable: {s} doesn't exist\n", .{label});
                return error.InvalidVairableName;
            },
        }
    }

    fn parseOperandValue(self: *Cpu, op: Operand) !u32 {
        return switch (op) {
            .register => |regIndex| self.registers[regIndex],
            .value => |value| value,
            .string => error.InvalidDataType,
            .label => |label| if (self.dataTable.get(label)) |variable| {
                return switch (variable.dataType) {
                    .db => std.mem.readInt(u8, self.ram[variable.pointer..][0..1], .little),
                    .dw => std.mem.readInt(u16, self.ram[variable.pointer..][0..2], .little),
                    .dd => std.mem.readInt(u32, self.ram[variable.pointer..][0..4], .little),
                    .string => error.InvalidLabel,
                    // .none => error.DataTypeMustExist,
                };
            } else return error.InvalidVairableName,
        };
    }

    fn parseOperandDestination(self: *Cpu, write: Operand) !u32 {
        return switch (write) {
            .register => return error.CantWriteToARegister,
            .value => |value| value,
            .label => |label| if (self.dataTable.get(label)) |variable| variable.pointer else return error.InvalidLabel,
            .string => return error.CantWriteToAString,
        };
    }

    fn WriteToRam(self: *Cpu, operand: Operand, ramPointer: usize) !void {
        switch (operand) {
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
                        // .none => {},
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
                            std.debug.print("Unable to parse the label\n", .{});
                            return;
                        };
                        i -= 1;
                    },
                    .je => |label| {
                        if (self.flags[0] == 1) {
                            i = self.parseLabel(label) catch {
                                std.debug.print("Unable to parse the label\n", .{});
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
