const std = @import("std");
const root = @import("root.zig");

const Section = enum {
    data,
    code,
    none,
};

const DataTypes = enum {
    db,
    dw,
    dd,
    dq,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} *filename*\n", .{args[0]});
        return;
    }

    const maxSize = 1024 * 1024;
    const code = try std.fs.cwd().readFileAlloc(allocator, args[1], maxSize);
    defer allocator.free(code);

    var codeTable = std.StringHashMap(u32).init(allocator);
    defer codeTable.deinit();
    var dataTable = std.StringHashMap(u32).init(allocator);
    defer dataTable.deinit();

    var instructions = try std.ArrayList(root.Instructions).initCapacity(allocator, 0);
    defer instructions.deinit(allocator);

    var ram: [1024]u8 = undefined;
    // defer ;
    var ramPointer: u16 = 0;

    // std.debug.print("{s}", .{code});

    var section: Section = Section.none;

    var lines = std.mem.tokenizeSequence(u8, code, "\n");

    var cpu = root.Cpu.init();

    {
        var instructionCount: u32 = 0;

        while (lines.next()) |line| {
            if (line[line.len - 1] == ':') {
                try codeTable.put(line[0 .. line.len - 1], instructionCount);
                continue;
            }
            if (line[0] == '.') {
                const stateString = line[1..];

                if (std.mem.eql(u8, stateString, "data")) {
                    section = Section.data;
                } else if (std.mem.eql(u8, stateString, "code")) {
                    section = Section.code;
                } else {
                    std.debug.print("Could not determen the state given: {any}", .{stateString});
                    return error.UndetermenedState;
                }
                continue;
            }

            if (section == .code) instructionCount += 1;
            var tokens = std.mem.tokenizeSequence(u8, line, " ");

            if (tokens.next()) |token| {
                switch (section) {
                    .none => continue,
                    .code => {
                        const instrCode = std.meta.stringToEnum(std.meta.Tag(root.Instructions), token) orelse continue;

                        const instruction = switch (instrCode) {
                            .add => instr: {
                                const regA = try std.fmt.parseInt(u8, tokens.next().?[1..], 10);

                                break :instr root.Instructions{ .add = .{ .regA = regA, .valB = try parseOperator(tokens.next()) } };
                            },
                            .sub => instr: {
                                const regA = try std.fmt.parseInt(u8, tokens.next().?[1..], 10);

                                break :instr root.Instructions{ .sub = .{ .regA = regA, .valB = try parseOperator(tokens.next().?) } };
                            },
                            .mov => instr: {
                                const regA = try std.fmt.parseInt(u8, tokens.next().?[1..], 10);

                                break :instr root.Instructions{ .mov = .{ .regA = regA, .valB = try parseOperator(tokens.next().?) } };
                            },
                            .cmp => instr: {
                                break :instr root.Instructions{ .cmp = .{ .valA = try parseOperator(tokens.next().?), .valB = try parseOperator(tokens.next().?) } };
                            },
                            .jmp => root.Instructions{
                                .jmp = try parseLabel(tokens.next()),
                            },
                            .je => root.Instructions{
                                .je = try parseLabel(tokens.next()),
                            },
                            .print => root.Instructions{ .print = try std.fmt.parseInt(u8, tokens.next().?[1..], 10) },
                            // else => continue,
                        };

                        try instructions.append(allocator, instruction);
                    },
                    .data => {
                        //token = name of the variable
                        if (std.meta.stringToEnum(DataTypes, tokens.next().?)) |dataType| {
                            const data = tokens.next() orelse return error.UndefinedDataToken;
                            dataTable.put(token, ramPointer) catch {
                                std.debug.print("Unable to put the value into the data table", .{});
                                return error.OutOfMemory;
                            };

                            switch (dataType) {
                                .db => {
                                    const value: u8 = std.fmt.parseInt(u8, data, 10) catch {
                                        std.debug.print("Wasn't able to parse data u8: {any}", .{data});
                                        return error.InvalidDataValue;
                                    };
                                    ram[ramPointer] = value;
                                    ramPointer += 1;
                                },
                                .dw => {
                                    const value: u16 = std.fmt.parseInt(u16, data, 10) catch {
                                        std.debug.print("Wasn't able to parse data u16: {any}", .{data});
                                        return error.InvalidDataValue;
                                    };
                                    std.mem.writeInt(u16, ram[ramPointer..][0..2], value, .little);
                                    ramPointer += 2;

                                    // std.debug.print("Added: {d} to memory\n", .{value});
                                },
                                .dd => {
                                    const value: u32 = std.fmt.parseInt(u32, data, 10) catch {
                                        std.debug.print("Wasn't able to parse data u32: {any}", .{data});
                                        return error.InvalidDataValue;
                                    };
                                    std.mem.writeInt(u32, ram[ramPointer..][0..4], value, .little);
                                    ramPointer += 4;
                                },
                                .dq => {
                                    const value: u64 = std.fmt.parseInt(u64, data, 10) catch {
                                        std.debug.print("Wasn't able to parse data u64: {any}", .{data});
                                        return error.InvalidDataValue;
                                    };
                                    std.mem.writeInt(u64, ram[ramPointer..][0..8], value, .little);
                                    ramPointer += 8;
                                },
                            }
                        } else {
                            std.debug.print("Unable to identify datatype", .{});
                            return error.InvalidDataType;
                        }
                    },
                }
            }
        }
    }

    {
        for (instructions.items) |*instruction| {
            switch (instruction.*) {
                .jmp => |*target| {
                    if (target.* == .label) target.* = root.Label{ .value = codeTable.get(target.*.label).? };
                },
                .je => |*target| {
                    if (target.* == .label) target.* = root.Label{ .value = codeTable.get(target.*.label).? };
                },
                .add => |*target| {
                    if (target.*.valB == .value and target.*.valB.value == .label) {
                        target.*.valB.value = root.Label{ .value = ram[dataTable.get(target.*.valB.value.label).?] };
                    }
                },
                .sub => |*target| {
                    if (target.*.valB == .value and target.*.valB.value == .label) {
                        target.*.valB.value = root.Label{ .value = ram[dataTable.get(target.*.valB.value.label).?] };
                    }
                },
                .mov => |*target| {
                    if (target.*.valB == .value and target.*.valB.value == .label) {
                        target.*.valB.value = root.Label{ .value = ram[dataTable.get(target.*.valB.value.label).?] };
                    }
                },
                .cmp => |*target| {
                    if (target.*.valA == .value and target.*.valA.value == .label) {
                        target.*.valA.value = root.Label{ .value = dataTable.get(target.*.valA.value.label).? };
                    }
                    if (target.*.valB == .value and target.*.valB.value == .label) {
                        // std.debug.print("Replaced {any} with {}\n", .{ target.*.valB.value.label, ram[dataTable.get(target.*.valB.value.label).?] });
                        target.*.valB.value = root.Label{ .value = ram[dataTable.get(target.*.valB.value.label).?] };
                    }
                },
                else => {},
            }
        }
    }

    cpu.executeCode(instructions.items);
    // cpu.printRegisters();
}

fn parseLabel(token: ?[]const u8) !root.Label {
    if (token) |value| {
        if (std.fmt.parseInt(u32, value, 10)) |lineNumber| {
            return root.Label{ .value = lineNumber };
        } else |_| {
            return root.Label{ .label = value };
        }
    } else return error.UndefindLabel;
}

fn parseOperator(op: ?[]const u8) !root.Operator {
    if (op) |operand| {
        if (operand[0] == 'r') {
            return root.Operator{ .register = try std.fmt.parseUnsigned(u8, operand[1..], 10) };
        } else {
            return root.Operator{ .value = try parseLabel(operand) };
        }
    } else return error.MissingOperand;
}
