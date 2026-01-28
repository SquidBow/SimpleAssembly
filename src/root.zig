const std = @import("std");

pub const Instructions = union(enum) {
    add: struct { regA: u8, valB: Operator },
    sub: struct { regA: u8, valB: Operator },
    mov: struct { regA: u8, valB: Operator },
};

pub const Operator = union(enum) {
    register: u8,
    value: i32,
};

pub const Cpu = struct {
    registers: [4]i32,
    flags: [8]u8,

    pub fn init() Cpu {
        return Cpu{
            .registers = [_]i32{0} ** 4,
            .flags = [_]u8{0} ** 8,
        };
    }

    pub fn executeInstruction(self: *Cpu, instruction: Instructions) !void {
        switch (instruction) {
            .add => |data| {
                const valB = switch (data.valB) {
                    .register => |regIndex| self.registers[regIndex],
                    .value => |value| value,
                };

                self.registers[data.regA] += valB;
            },
            .sub => |data| {
                const valB = switch (data.valB) {
                    .register => |regIndex| self.registers[regIndex],
                    .value => |value| value,
                };

                self.registers[data.regA] -= valB;
            },
            .mov => |data| {
                const valB = switch (data.valB) {
                    .register => |regIndex| self.registers[regIndex],
                    .value => |value| value,
                };

                self.registers[data.regA] = valB;
            },
        }
    }
};
