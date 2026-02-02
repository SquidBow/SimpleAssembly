const std = @import("std");
const root = @import("root.zig");

const Section = enum {
    data,
    code,
    none,
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

    var jumpTable = std.StringHashMap(u32).init(allocator);
    defer jumpTable.deinit();

    var instructions = try std.ArrayList(root.Instructions).initCapacity(allocator, 0);
    defer instructions.deinit(allocator);

    // std.debug.print("{s}", .{code});

    var section: Section = Section.none;

    var lines = std.mem.tokenizeSequence(u8, code, "\n");

    var cpu = root.Cpu.init();

    {
        var instructionCount: u32 = 0;

        while (lines.next()) |line| {
            if (line[line.len - 1] == ':') {
                try jumpTable.put(line[0 .. line.len - 1], instructionCount);
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

            instructionCount += 1;
            var tokens = std.mem.tokenizeSequence(u8, line, " ");
            while (tokens.next()) |token| {
                const instrCode = std.meta.stringToEnum(std.meta.Tag(root.Instructions), token) orelse continue;
                var instruction: root.Instructions = undefined;

                switch (section) {
                    .none => continue,
                    .code => {
                        instruction = switch (instrCode) {
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
                            .jmp => root.Instructions{ .jmp = instr: {
                                const jmp = tokens.next().?;
                                if (std.fmt.parseInt(u32, jmp, 10)) |lineNumber| {
                                    break :instr root.JumpLabel{ .value = lineNumber };
                                } else |_| {
                                    break :instr root.JumpLabel{ .label = jmp };
                                }
                            } },
                            .je => root.Instructions{ .je = instr: {
                                const jmp = tokens.next().?;
                                if (std.fmt.parseInt(u32, jmp, 10)) |lineNumber| {
                                    break :instr root.JumpLabel{ .value = lineNumber };
                                } else |_| {
                                    break :instr root.JumpLabel{ .label = jmp };
                                }
                            } },
                            .print => root.Instructions{ .print = try std.fmt.parseInt(u8, tokens.next().?[1..], 10) },
                            // else => continue,
                        };
                    },
                    .data => {},
                }

                try instructions.append(allocator, instruction);
            }
        }
    }

    {
        for (instructions.items) |*instruction| {
            switch (instruction.*) {
                .jmp => |*target| {
                    if (target.* == .label) target.* = root.JumpLabel{ .value = jumpTable.get(target.*.label).? };
                },
                .je => |*target| {
                    if (target.* == .label) target.* = root.JumpLabel{ .value = jumpTable.get(target.*.label).? };
                },
                else => {},
            }
        }
    }

    cpu.executeCode(instructions.items);
}

fn parseOperator(op: ?[]const u8) !root.Operator {
    return if (op) |operand|
        if (operand[0] == 'r')
            root.Operator{ .register = try std.fmt.parseUnsigned(u8, operand[1..], 10) }
        else
            root.Operator{ .value = try std.fmt.parseInt(i32, operand, 10) }
    else
        error.MissingOperand;
}
