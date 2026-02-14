const std = @import("std");

pub const Instructions = union(enum) {
    add: struct { reg: u8, val: Operand },
    sub: struct { reg: u8, val: Operand },
    mov: struct { valA: Operand, valB: Operand },
    cmp: struct { valA: Operand, valB: Operand },
    jmp: Label,
    je: Label,
    print: Operand,
    printNum: Operand,
    write: struct { destination: Operand, data: Operand },
    read: struct { register: u8, dataPointer: Operand, dataType: DataTypes },
    MovRam: struct { destination: Operand, dataPointer: Operand, variable: Variable },
    push: u8,
    pop: u8,
    call: []const u8,
    ret: void,
    // input: struct { destination: Operand, maxLength: usize },
    input: struct { destination: Operand, variable: Variable }, //dataType: DataTypes, maxLength: usize },
    mul: struct { reg: u8, val: Operand },
    div: struct { reg: u8, val: Operand },
    mod: struct { reg: u8, val: Operand },
    @"and": struct { reg: u8, val: Operand },
    @"or": struct { reg: u8, val: Operand },
    xor: struct { reg: u8, val: Operand },
    shl: struct { reg: u8, val: Operand },
    shr: struct { reg: u8, val: Operand },
    jne: Label,
    jg: Label,
    jl: Label,
    jge: Label,
    jle: Label,
    jc: Label,
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
    flags: [4]u8 = .{0} ** 4, //0.Zero, 1.Sign, 2.Overflow, 3.Carry
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
                const valA = self.registers[data.reg];

                const uAddition = @addWithOverflow(valA, valB);
                self.registers[data.reg] = uAddition[0];
                self.flags[3] = uAddition[1];

                const sValA: i32 = @bitCast(valA);
                const sValB: i32 = @bitCast(valB);

                const sAddition = @addWithOverflow(sValA, sValB);
                self.flags[2] = sAddition[1];

                self.flags[0] = if (self.registers[data.reg] == 0) 1 else 0;
                self.flags[1] = if (@as(i32, @bitCast(self.registers[data.reg])) < 0) 1 else 0;
            },
            .sub => |data| {
                const valB = try self.parseOperandValue(data.val);
                const valA = self.registers[data.reg];

                const uSubtraction = @subWithOverflow(valA, valB);
                self.registers[data.reg] = uSubtraction[0];

                self.flags[3] = uSubtraction[1];

                const sValA: i32 = @bitCast(valA);
                const sValB: i32 = @bitCast(valB);

                const sSubtraction = @subWithOverflow(sValA, sValB);
                self.flags[2] = sSubtraction[1];

                self.flags[0] = if (self.registers[data.reg] == 0) 1 else 0;
                self.flags[1] = if (@as(i32, @bitCast(self.registers[data.reg])) < 0) 1 else 0;
            },
            .mov => |data| {
                switch (data.valA) {
                    .register => |reg| {
                        const valB = try self.parseOperandValue(data.valB);
                        self.registers[reg] = valB;
                        self.flags[0] = if (valB == 0) 1 else 0;
                        self.flags[1] = if (@as(i32, @bitCast(valB)) < 0) 1 else 0;
                    },
                    else => {
                        const valA = try self.parseOperandDestination(data.valA);

                        try self.WriteToRam(data.valB, valA);
                    },
                }
                // self.registers[data.valA] = valB;
            },
            .cmp => |data| {
                const valA = try self.parseOperandValue(data.valA);
                const valB = try self.parseOperandValue(data.valB);

                const uResult = @subWithOverflow(valA, valB);
                self.flags[3] = uResult[1];

                const sValA: i32 = @bitCast(valA);
                const sValB: i32 = @bitCast(valB);

                const sResult = @subWithOverflow(sValA, sValB);
                self.flags[2] = sResult[1];

                self.flags[0] = if (uResult[0] == 0) 1 else 0;
                self.flags[1] = if (@as(i32, @bitCast(uResult[0])) < 0) 1 else 0;
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
            .MovRam => |data| {
                const dataPointer = try self.parseOperandDestination(data.dataPointer);
                // std.debug.print("\n\nDataPointer: {d}\n\n", .{dataPointer});

                const destination = self.parseOperandDestination(data.destination) catch {
                    std.debug.print("Unable to find destination to read to", .{});
                    return error.InvalidDestination;
                };

                switch (data.variable.dataType) {
                    .string => {
                        if (data.variable.len == 0) return error.InvalidStringLength;
                        @memmove(self.ram[destination..][0..data.variable.len], self.ram[dataPointer..][0..data.variable.len]);
                    },
                    .db => {
                        const value: u8 = std.mem.readInt(u8, self.ram[dataPointer..][0..1], .little);
                        std.mem.writeInt(u8, self.ram[destination..][0..1], value, .little);
                    },
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
            .read => |data| {
                const dataPointer = try self.parseOperandDestination(data.dataPointer);

                switch (data.dataType) {
                    .db => self.registers[data.register] = @as(u32, std.mem.readInt(u8, self.ram[dataPointer..][0..1], .little)),
                    .dw => self.registers[data.register] = @as(u32, std.mem.readInt(u16, self.ram[dataPointer..][0..2], .little)),
                    .dd => self.registers[data.register] = std.mem.readInt(u32, self.ram[dataPointer..][0..4], .little),
                    else => return error.InvalidDataType,
                }
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
            // .input => |data| {
            //     const destination = self.parseOperandDestination(data.destination) catch {
            //         std.debug.print("Unable to find destination to read to", .{});
            //         return error.InvalidDestination;
            //     };

            //     const stdin = std.fs.File.stdin();
            //     _ = try stdin.read(self.ram[destination .. destination + data.maxLength]);
            // },
            .input => |data| {
                const destination = self.parseOperandDestination(data.destination) catch {
                    std.debug.print("Unable to find destination to read to", .{});
                    return error.InvalidDestination;
                };
                const stdin = std.fs.File.stdin();

                switch (data.variable.dataType) {
                    .string => {
                        _ = try stdin.read(self.ram[destination .. destination + data.variable.len]);
                    },
                    else => {
                        var buffer: [10]u8 = undefined;
                        const readBytes = try stdin.read(&buffer);

                        switch (data.variable.dataType) {
                            .db => {
                                const input = std.mem.trim(u8, buffer[0..readBytes], " \n\r\t");
                                const value: u8 = std.fmt.parseInt(u8, input, 10) catch {
                                    return error.CantConvertStringToInt;
                                };
                                std.mem.writeInt(u8, self.ram[destination..][0..1], value, .little);
                            },
                            .dw => {
                                const input = std.mem.trim(u8, buffer[0..readBytes], " \n\r\t");
                                const value: u16 = std.fmt.parseInt(u16, input, 10) catch {
                                    return error.CantConvertStringToInt;
                                };
                                std.mem.writeInt(u16, self.ram[destination..][0..2], value, .little);
                            },
                            .dd => {
                                const input = std.mem.trim(u8, buffer[0..readBytes], " \n\r\t");
                                const value: u32 = std.fmt.parseInt(u32, input, 10) catch {
                                    return error.CantConvertStringToInt;
                                };
                                std.mem.writeInt(u32, self.ram[destination..][0..4], value, .little);
                            },
                            else => return error.InvalidDataType,
                        }
                    },
                }
            },
            .mul => |data| {
                const valB = try self.parseOperandValue(data.val);
                const valA = self.registers[data.reg];

                const uMultiplication = @mulWithOverflow(valA, valB);
                self.registers[data.reg] = uMultiplication[0];
                self.flags[3] = uMultiplication[1];

                const sValA: i32 = @bitCast(valA);
                const sValB: i32 = @bitCast(valB);

                const sMultiplication = @mulWithOverflow(sValA, sValB);
                self.flags[2] = sMultiplication[1];

                self.flags[0] = if (self.registers[data.reg] == 0) 1 else 0;
                self.flags[1] = if (@as(i32, @bitCast(self.registers[data.reg])) < 0) 1 else 0;
            },
            .div => |data| {
                const valB = try self.parseOperandValue(data.val);

                if (valB == 0) {
                    return error.DivisionByZero;
                }

                self.registers[data.reg] /= valB;

                self.flags[0] = if (self.registers[data.reg] == 0) 1 else 0;
                self.flags[1] = if (@as(i32, @bitCast(self.registers[data.reg])) < 0) 1 else 0;
            },
            .mod => |data| {
                const valB = try self.parseOperandValue(data.val);

                if (valB == 0) {
                    return error.DivisionByZero;
                }

                self.registers[data.reg] %= valB;

                self.flags[3] = 0;
                self.flags[2] = 0;
                self.flags[0] = if (self.registers[data.reg] == 0) 1 else 0;
                self.flags[1] = if (@as(i32, @bitCast(self.registers[data.reg])) < 0) 1 else 0;
            },
            .printNum => |data| {
                self.printNum(data) catch {
                    return error.UnableToPrintData;
                };
                // std.debug.print("{d}", .{self.registers[reg]});
            },
            .@"and" => |data| {
                const valB = try self.parseOperandValue(data.val);

                self.registers[data.reg] &= valB;

                self.flags[3] = 0;
                self.flags[2] = 0;
                self.flags[0] = if (self.registers[data.reg] == 0) 1 else 0;
                self.flags[1] = if (@as(i32, @bitCast(self.registers[data.reg])) < 0) 1 else 0;
            },
            .@"or" => |data| {
                const valB = try self.parseOperandValue(data.val);

                self.registers[data.reg] |= valB;

                self.flags[3] = 0;
                self.flags[2] = 0;
                self.flags[0] = if (self.registers[data.reg] == 0) 1 else 0;
                self.flags[1] = if (@as(i32, @bitCast(self.registers[data.reg])) < 0) 1 else 0;
            },
            .xor => |data| {
                const valB = try self.parseOperandValue(data.val);

                self.registers[data.reg] ^= valB;

                self.flags[3] = 0;
                self.flags[2] = 0;
                self.flags[0] = if (self.registers[data.reg] == 0) 1 else 0;
                self.flags[1] = if (@as(i32, @bitCast(self.registers[data.reg])) < 0) 1 else 0;
            },
            .shl => |data| {
                const valB: u5 = @intCast(try self.parseOperandValue(data.val) % 32);
                if (valB == 0) return;

                const valA = self.registers[data.reg];

                self.registers[data.reg] <<= @intCast(valB);

                const shift: u5 = @intCast(32 - @as(u32, valB));
                self.flags[3] = @intCast((valA >> shift) % 2);
                self.flags[2] = if (valA >> 31 == self.registers[data.reg] >> 31) 0 else 1;
                self.flags[0] = if (self.registers[data.reg] == 0) 1 else 0;
                self.flags[1] = @intCast(self.registers[data.reg] >> 31);
            },
            .shr => |data| {
                const valB: u5 = @intCast(try self.parseOperandValue(data.val) % 32);
                if (valB == 0) return;

                const valA = self.registers[data.reg];

                self.registers[data.reg] >>= @intCast(valB);

                self.flags[3] = @intCast((valA >> (valB - 1)) % 2);
                self.flags[2] = @intCast(valA >> 31);

                self.flags[0] = if (self.registers[data.reg] == 0) 1 else 0;
                self.flags[1] = if (@as(i32, @bitCast(self.registers[data.reg])) < 0) 1 else 0;
            },
            else => {},
        }
    }

    fn printNum(self: *Cpu, op: Operand) !void {
        switch (op) {
            .register => |reg| {
                std.debug.print("{d}", .{self.registers[reg]});
            },
            .value => |value| {
                std.debug.print("{d}", .{value});
            },
            .string => {
                std.debug.print("Use a normal print to print a string\n", .{});
                return error.UnableToPrintTheString;
            },
            .label => |label| if (self.dataTable.get(label)) |variable| {
                return switch (variable.dataType) {
                    .db => {
                        const value = std.mem.readInt(u8, self.ram[variable.pointer..][0..1], .little);
                        std.debug.print("{d}", .{value});
                    },
                    .dw => {
                        const value = std.mem.readInt(u16, self.ram[variable.pointer..][0..2], .little);
                        std.debug.print("{d}", .{value});
                    },
                    .dd => {
                        const value = std.mem.readInt(u32, self.ram[variable.pointer..][0..4], .little);
                        std.debug.print("{d}", .{value});
                    },
                    .string => {
                        std.debug.print("Use a normal print to print a string\n", .{});
                        return error.UnableToPrintTheString;
                    },
                };
            } else {
                std.debug.print("Vairable: {s} doesn't exist\n", .{label});
                return error.InvalidVairableName;
            },
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
            .string => |string| {
                // std.debug.print("{s}", .{string});
                var index: usize = 0;

                while (index < string.len) : (index += 1) {
                    if (string[index] == '\\' and index + 1 < string.len) {
                        switch (string[index + 1]) {
                            'n' => {
                                std.debug.print("\n", .{});
                                index += 1;
                                continue;
                            },
                            't' => {
                                std.debug.print("\t", .{});
                                index += 1;
                                continue;
                            },
                            else => {},
                        }
                    }

                    std.debug.print("{c}", .{string[index]});
                }
            },
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
                        const string: []const u8 = self.ram[variable.pointer .. variable.pointer + variable.len];
                        var index: usize = 0;

                        while (index < string.len) : (index += 1) {
                            if (string[index] == '\\' and index + 1 < string.len) {
                                switch (string[index + 1]) {
                                    'n' => {
                                        std.debug.print("\n", .{});
                                        index += 1;
                                        continue;
                                    },
                                    't' => {
                                        std.debug.print("\t", .{});
                                        index += 1;
                                        continue;
                                    },
                                    else => {},
                                }
                            }

                            std.debug.print("{c}", .{string[index]});
                        }
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
            .register => |regIndex| self.registers[regIndex],
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
            var i: u32 = self.codeTable.get("main") orelse return error.MainNotFound;
            var depth: u32 = 0;

            while (i < instructions.len) {
                const instruction = instructions[i];

                switch (instruction) {
                    .jmp => |label| {
                        i = self.parseLabel(label) catch {
                            std.debug.print("Unable to parse the label\n", .{});
                            return;
                        };
                        if (i == 0) continue;
                        i -= 1;
                    },
                    .je => |label| {
                        if (self.flags[0] == 1) {
                            i = self.parseLabel(label) catch {
                                std.debug.print("Unable to parse the label\n", .{});
                                return;
                            };
                            if (i == 0) continue;
                            i -= 1;
                        }
                    },
                    .jne => |label| {
                        if (self.flags[0] == 0) {
                            i = self.parseLabel(label) catch {
                                std.debug.print("Unable to parse the label\n", .{});
                                return;
                            };
                            if (i == 0) continue;
                            i -= 1;
                        }
                    },
                    .jg => |label| {
                        if (self.flags[0] == 0 and (self.flags[1] == self.flags[2])) {
                            i = self.parseLabel(label) catch {
                                std.debug.print("Unable to parse the label\n", .{});
                                return;
                            };
                            if (i == 0) continue;
                            i -= 1;
                        }
                    },
                    .jl => |label| {
                        if (self.flags[1] != self.flags[2]) {
                            i = self.parseLabel(label) catch {
                                std.debug.print("Unable to parse the label\n", .{});
                                return;
                            };
                            if (i == 0) continue;
                            i -= 1;
                        }
                    },
                    .jge => |label| {
                        if (self.flags[1] == self.flags[2]) {
                            i = self.parseLabel(label) catch {
                                std.debug.print("Unable to parse the label\n", .{});
                                return;
                            };
                            if (i == 0) continue;
                            i -= 1;
                        }
                    },
                    .jle => |label| {
                        if (self.flags[0] != self.flags[2] or self.flags[1] == 0) {
                            i = self.parseLabel(label) catch {
                                std.debug.print("Unable to parse the label\n", .{});
                                return;
                            };
                            if (i == 0) continue;
                            i -= 1;
                        }
                    },
                    .jc => |label| {
                        if (self.flags[2] == 1) {
                            i = self.parseLabel(label) catch {
                                std.debug.print("Unable to parse the label\n", .{});
                                return;
                            };
                            if (i == 0) continue;
                            i -= 1;
                        }
                    },
                    .call => |name| {
                        const variable: u32 = self.registers[0];

                        const line: u32 = self.codeTable.get(name) orelse return error.InvalidProcName;
                        try self.executeInstruction(Instructions{ .push = 0 });
                        self.registers[0] = @bitCast(i);
                        try self.executeInstruction(Instructions{ .push = 0 });
                        depth += 1;
                        i = line - 1;

                        self.registers[0] = variable;
                    },
                    .ret => {
                        if (depth == 0) break;

                        try self.executeInstruction(Instructions{ .pop = 0 });
                        i = self.registers[0];
                        try self.executeInstruction(Instructions{ .pop = 0 });
                        depth -= 1;
                    },
                    else => {
                        try self.executeInstruction(instruction);
                    },
                }

                i += 1;
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
