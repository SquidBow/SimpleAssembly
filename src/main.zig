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
                    const valB = try std.fmt.parseInt(i32, tokens.next().?, 10);

                    break :instr root.Instructions{ .add = .{ .regA = regA, .valB = .{ .value = valB } } };
                },
                .sub => instr: {
                    const regA = try std.fmt.parseInt(u8, tokens.next().?, 10);
                    const valB = try std.fmt.parseInt(i32, tokens.next().?, 10);

                    break :instr root.Instructions{ .sub = .{ .regA = regA, .valB = .{ .value = valB } } };
                },
                .mov => instr: {
                    const regA = try std.fmt.parseInt(u8, tokens.next().?, 10);
                    const valB = try std.fmt.parseInt(i32, tokens.next().?, 10);

                    break :instr root.Instructions{ .mov = .{ .regA = regA, .valB = .{ .value = valB } } };
                },
                // else => continue,
            };

            try cpu.executeInstruction(instruction);

            std.debug.print("Reg 0: {d}\n", .{cpu.registers[0]});
        }
    }
}
