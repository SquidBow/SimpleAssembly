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
    string,
};

const Variable = struct {
    pointer: u32,
    dataType: DataTypes,
    len: usize,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
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
    var dataTable = std.StringHashMap(Variable).init(allocator);
    defer dataTable.deinit();

    var instructions = try std.ArrayList(root.Instructions).initCapacity(allocator, 0);
    defer instructions.deinit(allocator);

    var ram: [1024]u8 = undefined;
    // defer ;
    var ramPointer: usize = 0;

    // std.debug.print("{s}", .{code});

    var section: Section = Section.none;

    var lines = std.mem.tokenizeSequence(u8, code, "\n");

    var cpu = root.Cpu{};

    var instructionCount: u32 = 0;

    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "//") or std.mem.startsWith(u8, line, "#")) {
            continue;
        } else if (line[line.len - 1] == ':') {
            try codeTable.put(line[0 .. line.len - 1], instructionCount);
            continue;
        } else if (line[0] == '.') {
            const stateString = line[1..];

            if (std.mem.eql(u8, stateString, "data")) {
                section = Section.data;
            } else if (std.mem.eql(u8, stateString, "code")) {
                section = Section.code;
            } else {
                std.debug.print("Could not determen the state given: {any}\n", .{stateString});
                return error.InvalidState;
            }
            continue;
        }

        var tokens = std.mem.tokenizeSequence(u8, line, " ");

        if (tokens.next()) |token| {
            switch (section) {
                .none => continue,
                .code => {
                    instructionCount += 1;
                    const instrCode = std.meta.stringToEnum(std.meta.Tag(root.Instructions), token) orelse continue;

                    const instruction = switchInstructionCode(instrCode, &tokens) catch {
                        std.debug.print("Failed to parse instruction: {}\n", .{instrCode});
                        return error.InvalidInstruction;
                    };

                    instructions.append(allocator, instruction) catch {
                        std.debug.print("Unable to add instruction to memory: {}\n", .{instruction});
                        return error.OutOfMemory;
                    };
                },
                .data => {
                    //token = name of the variable
                    const typeOrString = tokens.next() orelse {
                        std.debug.print("Not found token for type\n", .{});
                        return error.InvalidTypeToken;
                    };

                    if (std.meta.stringToEnum(DataTypes, typeOrString)) |dataType| {
                        const data = tokens.next() orelse "0";

                        try writeDataToRam(&ram, &dataTable, dataType, data, token, &ramPointer);
                    } else {
                        if (typeOrString[0] != '\"') {
                            std.debug.print("Unable to identify type of the variable: {s}\n", .{typeOrString});
                            return error.InvalidTypeToken;
                        }

                        const rest = tokens.rest();
                        var inner: []const u8 = "";
                        if (rest.len > 0) {
                            inner = rest[0..rest.len];
                        } else {
                            inner = rest;
                        }
                        const lastDoubleQuote = std.mem.lastIndexOf(u8, rest, "\"") orelse {
                            std.debug.print("Cannot find the end of the string\n", .{});
                            return error.InvalidString;
                        };

                        const fullString = std.mem.concat(allocator, u8, &.{ typeOrString[1..], " ", inner[0..lastDoubleQuote] }) catch {
                            std.debug.print("Unable to add string to memory\n", .{});
                            return error.OutOfMemory;
                        };

                        defer allocator.free(fullString);

                        const ramPointerForVar: u32 = @intCast(ramPointer);
                        @memcpy(ram[ramPointerForVar .. ramPointerForVar + fullString.len], fullString);
                        dataTable.put(token, .{ .dataType = DataTypes.string, .pointer = ramPointerForVar, .len = fullString.len }) catch {
                            std.debug.print("Unable to add string to memory\n", .{});
                            return error.OutOfMemory;
                        };
                        ramPointer += @intCast(fullString.len);
                    }
                },
            }
        }
    }

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
                    target.*.valB.value = root.Label{
                        .value = getVariableUInt(&ram, dataTable.get(target.*.valB.value.label).?),
                    };
                }
            },
            .sub => |*target| {
                if (target.*.valB == .value and target.*.valB.value == .label) {
                    target.*.valB.value = root.Label{
                        .value = getVariableUInt(&ram, dataTable.get(target.*.valB.value.label).?),
                    };
                }
            },
            .mov => |*target| {
                if (target.*.valB == .value and target.*.valB.value == .label) {
                    target.*.valB.value = root.Label{
                        .value = getVariableUInt(&ram, dataTable.get(target.*.valB.value.label).?),
                    };
                }
            },
            .cmp => |*target| {
                if (target.*.valA == .value and target.*.valA.value == .label) {
                    target.*.valA.value = root.Label{
                        .value = getVariableUInt(&ram, dataTable.get(target.*.valA.value.label).?),
                    };
                }

                if (target.*.valB == .value and target.*.valB.value == .label) {
                    // target.*.valB.value = root.Label{ .value = ram[dataTable.get(target.*.valB.value.label).?] };
                    target.*.valB.value = root.Label{
                        .value = getVariableUInt(&ram, dataTable.get(target.*.valB.value.label).?),
                    };
                }
            },
            .print => |*target| {
                if (target.* == .value and target.*.value == .label) {
                    const variable: Variable = dataTable.get(target.*.value.label) orelse {
                        std.debug.print("Unable to find replacement for value: {s}\n", .{target.*.value.label});
                        return error.InvalidReplacement;
                    };
                    target.*.value = switch (variable.dataType) {
                        .string => root.Label{ .label = ram[variable.pointer .. variable.pointer + variable.len] },
                        else => root.Label{
                            .value = getVariableUInt(&ram, variable),
                        },
                    };
                }
            },
            // else => {},
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
    } else return error.InvalidLabel;
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

// fn getVariableString(ram: []const u8, variable: Variable) u32 {

fn getVariableUInt(ram: []const u8, variable: Variable) u32 {
    return switch (variable.dataType) {
        .db => std.mem.readInt(u8, ram[variable.pointer..][0..1], .little),
        .dw => std.mem.readInt(u16, ram[variable.pointer..][0..2], .little),
        .dd => std.mem.readInt(u32, ram[variable.pointer..][0..4], .little),
        else => 0,
    };
}

fn switchInstructionCode(instrCode: std.meta.Tag(root.Instructions), tokens: *std.mem.TokenIterator(u8, .sequence)) !root.Instructions {
    return switch (instrCode) {
        .add => root.Instructions{ .add = .{ .regA = try std.fmt.parseInt(u8, tokens.next().?[1..], 10), .valB = try parseOperator(tokens.next()) } },
        .sub => root.Instructions{ .sub = .{ .regA = try std.fmt.parseInt(u8, tokens.next().?[1..], 10), .valB = try parseOperator(tokens.next()) } },
        .mov => root.Instructions{ .mov = .{ .regA = try std.fmt.parseInt(u8, tokens.next().?[1..], 10), .valB = try parseOperator(tokens.next()) } },
        .cmp => root.Instructions{ .cmp = .{ .valA = try parseOperator(tokens.next().?), .valB = try parseOperator(tokens.next().?) } },
        .jmp => root.Instructions{
            .jmp = try parseLabel(tokens.next()),
        },
        .je => root.Instructions{
            .je = try parseLabel(tokens.next()),
        },
        .print => root.Instructions{ .print = try parseOperator(tokens.next()) },
        // try std.fmt.parseInt(u8, tokens.next().?[1..], 10) },
    };
}

fn writeDataToRam(ram: []u8, dataTable: *std.StringHashMap(Variable), dataType: DataTypes, data: []const u8, token: []const u8, ramPointer: *usize) !void {
    switch (dataType) {
        .db => {
            const value: u8 = std.fmt.parseInt(u8, data, 10) catch {
                std.debug.print("Wasn't able to parse data u8: {any}\n", .{data});
                return error.InvalidDataValue;
            };
            ram[ramPointer.*] = value;

            const ramPointerForVar: u32 = @intCast(ramPointer.*);
            dataTable.put(token, Variable{ .dataType = DataTypes.db, .pointer = ramPointerForVar, .len = 0 }) catch {
                std.debug.print("Unable to put the value into the data table\n", .{});
                return error.OutOfMemory;
            };

            ramPointer.* += 1;
        },
        .dw => {
            const value: u16 = std.fmt.parseInt(u16, data, 10) catch {
                std.debug.print("Wasn't able to parse data u16: {any}\n", .{data});
                return error.InvalidDataValue;
            };
            std.mem.writeInt(u16, ram[ramPointer.*..][0..2], value, .little);

            const ramPointerForVar: u32 = @intCast(ramPointer.*);
            dataTable.put(token, Variable{ .dataType = DataTypes.dw, .pointer = ramPointerForVar, .len = 0 }) catch {
                std.debug.print("Unable to put the value into the data table\n", .{});
                return error.OutOfMemory;
            };

            ramPointer.* += 2;

            // std.debug.print("Added: {d} to memory\n", .{value});
        },
        .dd => {
            const value: u32 = std.fmt.parseInt(u32, data, 10) catch {
                std.debug.print("Wasn't able to parse data u32: {any}\n", .{data});
                return error.InvalidDataValue;
            };
            std.mem.writeInt(u32, ram[ramPointer.*..][0..4], value, .little);
            const ramPointerForVar: u32 = @intCast(ramPointer.*);
            dataTable.put(token, Variable{ .dataType = DataTypes.dd, .pointer = ramPointerForVar, .len = 0 }) catch {
                std.debug.print("Unable to put the value into the data table\n", .{});
                return error.OutOfMemory;
            };
            ramPointer.* += 4;
        },
        else => {},
    }
}
