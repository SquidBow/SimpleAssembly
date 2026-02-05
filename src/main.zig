const std = @import("std");
const root = @import("root.zig");

const Section = enum {
    data,
    code,
    none,
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

    var instructions = try std.ArrayList(root.Instructions).initCapacity(allocator, 0);
    defer instructions.deinit(allocator);

    var ramPointer: usize = 0;
    var section: Section = Section.none;
    var lines = std.mem.tokenizeSequence(u8, code, "\n");
    var cpu = root.Cpu.init(allocator);

    var instructionCount: u32 = 0;

    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "//") or std.mem.startsWith(u8, line, "#")) {
            continue;
        } else if (line[line.len - 1] == ':') {
            try cpu.codeTable.put(line[0 .. line.len - 1], instructionCount);
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

                    const instruction = switchInstructionCode(instrCode, &tokens, line) catch {
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

                    if (std.meta.stringToEnum(root.DataTypes, typeOrString)) |dataType| {
                        const data = tokens.next() orelse "0";

                        try writeDataToRam(&cpu.ram, &cpu.dataTable, dataType, data, token, &ramPointer);
                    } else {
                        const firstDoubleQuote = std.mem.indexOf(u8, line, "\"") orelse {
                            std.debug.print("Cannot find the start of the string\n", .{});
                            return error.InvalidString;
                        };

                        const lastDoubleQuote = std.mem.lastIndexOf(u8, line, "\"") orelse {
                            std.debug.print("Cannot find the end of the string\n", .{});
                            return error.InvalidString;
                        };

                        const fullString = line[firstDoubleQuote + 1 .. lastDoubleQuote];

                        const ramPointerForVar: u32 = @intCast(ramPointer);
                        @memcpy(cpu.ram[ramPointerForVar .. ramPointerForVar + fullString.len], fullString);
                        cpu.dataTable.put(token, .{ .dataType = root.DataTypes.string, .pointer = ramPointerForVar, .len = fullString.len }) catch {
                            std.debug.print("Unable to add string to memory\n", .{});
                            return error.OutOfMemory;
                        };
                        ramPointer += @intCast(fullString.len);
                    }
                },
            }
        }
    }

    cpu.executeCode(instructions.items) catch {
        std.debug.print("Failed while executing code", .{});
        return error.RuntimeError;
    };
    cpu.deinit();
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

fn parseOperator(operand: []const u8) root.Operator {
    if (std.fmt.parseInt(u32, operand, 10)) |value| {
        return root.Operator{ .value = value };
    } else |_| {
        if (operand[0] == 'r') {
            return root.Operator{ .register = std.fmt.parseInt(u8, operand[1..], 10) catch {
                return root.Operator{ .string = operand };
            } };
        } else {
            return root.Operator{ .string = operand };
        }
    }
}
fn getVariableUInt(ram: []const u8, variable: root.Variable) u32 {
    return switch (variable.dataType) {
        .db => std.mem.readInt(u8, ram[variable.pointer..][0..1], .little),
        .dw => std.mem.readInt(u16, ram[variable.pointer..][0..2], .little),
        .dd => std.mem.readInt(u32, ram[variable.pointer..][0..4], .little),
        else => 0,
    };
}

fn switchInstructionCode(instrCode: std.meta.Tag(root.Instructions), tokens: *std.mem.TokenIterator(u8, .sequence), line: []const u8) !root.Instructions {
    return switch (instrCode) {
        .add => root.Instructions{ .add = .{ .regA = try std.fmt.parseInt(u8, tokens.next().?[1..], 10), .valB = parseOperator(tokens.next().?) } },
        .sub => root.Instructions{ .sub = .{ .regA = try std.fmt.parseInt(u8, tokens.next().?[1..], 10), .valB = parseOperator(tokens.next().?) } },
        .mov => root.Instructions{ .mov = .{ .regA = try std.fmt.parseInt(u8, tokens.next().?[1..], 10), .valB = parseOperator(tokens.next().?) } },
        .cmp => root.Instructions{ .cmp = .{ .valA = parseOperator(tokens.next().?), .valB = parseOperator(tokens.next().?) } },
        .jmp => root.Instructions{
            .jmp = try parseLabel(tokens.next()),
        },
        .je => root.Instructions{
            .je = try parseLabel(tokens.next()),
        },
        .print => root.Instructions{
            .print = isntr: {
                const token = tokens.next() orelse return error.TokenNotFound;
                if (token[0] == '\"') {
                    const firstDoubleQuote = std.mem.indexOf(u8, line, "\"") orelse {
                        std.debug.print("Cannot find the start of the string\n", .{});
                        return error.InvalidString;
                    };

                    const lastDoubleQuote = std.mem.lastIndexOf(u8, line, "\"") orelse {
                        std.debug.print("Cannot find the end of the string\n", .{});
                        return error.InvalidString;
                    };

                    break :isntr parseOperator(line[firstDoubleQuote + 1 .. lastDoubleQuote]);
                    // const fullString = line[firstDoubleQuote + 1 .. lastDoubleQuote];
                } else {
                    break :isntr parseOperator(token);
                }
            },
        },
    };
}

fn writeDataToRam(ram: []u8, dataTable: *std.StringHashMap(root.Variable), dataType: root.DataTypes, data: []const u8, token: []const u8, ramPointer: *usize) !void {
    switch (dataType) {
        .db => {
            const value: u8 = std.fmt.parseInt(u8, data, 10) catch {
                std.debug.print("Wasn't able to parse data u8: {any}\n", .{data});
                return error.InvalidDataValue;
            };
            ram[ramPointer.*] = value;

            const ramPointerForVar: u32 = @intCast(ramPointer.*);
            dataTable.put(token, root.Variable{ .dataType = root.DataTypes.db, .pointer = ramPointerForVar, .len = 0 }) catch {
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
            dataTable.put(token, root.Variable{ .dataType = root.DataTypes.dw, .pointer = ramPointerForVar, .len = 0 }) catch {
                std.debug.print("Unable to put the value into the data table\n", .{});
                return error.OutOfMemory;
            };

            ramPointer.* += 2;
        },
        .dd => {
            const value: u32 = std.fmt.parseInt(u32, data, 10) catch {
                std.debug.print("Wasn't able to parse data u32: {any}\n", .{data});
                return error.InvalidDataValue;
            };
            std.mem.writeInt(u32, ram[ramPointer.*..][0..4], value, .little);
            const ramPointerForVar: u32 = @intCast(ramPointer.*);
            dataTable.put(token, root.Variable{ .dataType = root.DataTypes.dd, .pointer = ramPointerForVar, .len = 0 }) catch {
                std.debug.print("Unable to put the value into the data table\n", .{});
                return error.OutOfMemory;
            };
            ramPointer.* += 4;
        },
        else => {},
    }
}
