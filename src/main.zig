const std = @import("std");
const root = @import("root.zig");

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

    // std.debug.print("{s}", .{code});

    var lines = std.mem.tokenizeSequence(u8, code, "\n");

    var cpu = root.Cpu.init();

    while (lines.next()) |line| {
        var tokens = std.mem.tokenizeSequence(u8, line, " ");
        while (tokens.next()) |token| {
            const instrCode = std.meta.stringToEnum(std.meta.Tag(root.Instructions), token) orelse continue;

            const instruction = switch (instrCode) {
                .add => instr: {
                    const regA = try std.fmt.parseInt(u8, tokens.next().?, 10);

                    break :instr root.Instructions{ .add = .{ .regA = regA, .valB = try parseOperator(tokens.next()) } };
                },
                .sub => instr: {
                    const regA = try std.fmt.parseInt(u8, tokens.next().?, 10);

                    break :instr root.Instructions{ .sub = .{ .regA = regA, .valB = try parseOperator(tokens.next()) } };
                },
                .mov => instr: {
                    const regA = try std.fmt.parseInt(u8, tokens.next().?, 10);

                    break :instr root.Instructions{ .mov = .{ .regA = regA, .valB = try parseOperator(tokens.next()) } };
                },
                // else => continue,
            };

            try cpu.executeInstruction(instruction);

            for (0.., cpu.registers) |index, register| {
                std.debug.print("Reg {d}: {d}\t", .{ index, register });
            }
            std.debug.print("\n", .{});
        }
    }
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
