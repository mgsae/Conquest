const std = @import("std");
const main = @import("main.zig");
const e = @import("entity.zig");
const u = @import("utils.zig");

const Metric = enum {
    Width, // Physical width
    Height, // Physical height
    Speed, // Movement speed
    Health, // Start life
    Hunger, // Life depletion rate
    Reach, // Attack and gather range
    Tempo, // Attack and gather rate
};

pub const Genome = struct {
    traits: [@typeInfo(Metric).Enum.fields.len]Trait,
    sex: Sex,

    pub fn applyToUnit(self: *const Genome, unit: *e.Unit) void {
        // Base values
        var width: f32 = 20.0;
        var height: f32 = 20.0;
        var speed: f32 = 5.0;
        var health: f32 = 200.0;
        var reach: f32 = 10.0;
        var tempo: f32 = 50.0;

        for (self.traits) |trait| {
            switch (trait.metric) {
                .Width => width *= trait.value,
                .Height => height *= trait.value,
                .Speed => speed *= trait.value,
                .Health => health *= trait.value,
                .Reach => reach *= trait.value,
                .Tempo => tempo *= trait.value,
                else => {},
            }
        }

        unit.width = @intFromFloat(width);
        unit.height = @intFromFloat(height);
        unit.speed = @as(f16, @floatCast(speed));
        unit.health = @intFromFloat(health);
        unit.life = unit.health; // Maximizes life
        // hunger
        unit.reach = reach;
        unit.tempo = @intFromFloat(tempo);
    }

    pub fn preset(source: u8) Genome { // Multiplier templates applied to base
        var traits: [@typeInfo(Metric).Enum.fields.len]Trait = undefined;

        switch (source) {
            0 => { // Gatherer
                traits[@intFromEnum(Metric.Width)] = .{ .metric = .Width, .value = 1.0 };
                traits[@intFromEnum(Metric.Height)] = .{ .metric = .Height, .value = 1.0 };
                traits[@intFromEnum(Metric.Speed)] = .{ .metric = .Speed, .value = 1.0 };
                traits[@intFromEnum(Metric.Health)] = .{ .metric = .Health, .value = 1.0 };
                traits[@intFromEnum(Metric.Hunger)] = .{ .metric = .Hunger, .value = 1.0 };
                traits[@intFromEnum(Metric.Reach)] = .{ .metric = .Reach, .value = 1.0 };
                traits[@intFromEnum(Metric.Tempo)] = .{ .metric = .Tempo, .value = 1.0 };
            },
            1 => { // Soldier
                traits[@intFromEnum(Metric.Width)] = .{ .metric = .Width, .value = 1.25 };
                traits[@intFromEnum(Metric.Height)] = .{ .metric = .Height, .value = 1.25 };
                traits[@intFromEnum(Metric.Speed)] = .{ .metric = .Speed, .value = 1.1 };
                traits[@intFromEnum(Metric.Health)] = .{ .metric = .Health, .value = 1.125 };
                traits[@intFromEnum(Metric.Hunger)] = .{ .metric = .Hunger, .value = 1.0 };
                traits[@intFromEnum(Metric.Reach)] = .{ .metric = .Reach, .value = 1.0 };
                traits[@intFromEnum(Metric.Tempo)] = .{ .metric = .Tempo, .value = 1.0 };
            },
            2 => { // Trebuchet
                traits[@intFromEnum(Metric.Width)] = .{ .metric = .Width, .value = 2.25 };
                traits[@intFromEnum(Metric.Height)] = .{ .metric = .Height, .value = 2.25 };
                traits[@intFromEnum(Metric.Speed)] = .{ .metric = .Speed, .value = 0.66 };
                traits[@intFromEnum(Metric.Health)] = .{ .metric = .Health, .value = 2.0 };
                traits[@intFromEnum(Metric.Hunger)] = .{ .metric = .Hunger, .value = 1.0 };
                traits[@intFromEnum(Metric.Reach)] = .{ .metric = .Reach, .value = 1.0 };
                traits[@intFromEnum(Metric.Tempo)] = .{ .metric = .Tempo, .value = 1.0 };
            },
            3 => { // Cavalry
                traits[@intFromEnum(Metric.Width)] = .{ .metric = .Width, .value = 1.75 };
                traits[@intFromEnum(Metric.Height)] = .{ .metric = .Height, .value = 1.75 };
                traits[@intFromEnum(Metric.Speed)] = .{ .metric = .Speed, .value = 2.0 };
                traits[@intFromEnum(Metric.Health)] = .{ .metric = .Health, .value = 1.0 };
                traits[@intFromEnum(Metric.Hunger)] = .{ .metric = .Hunger, .value = 1.0 };
                traits[@intFromEnum(Metric.Reach)] = .{ .metric = .Reach, .value = 1.0 };
                traits[@intFromEnum(Metric.Tempo)] = .{ .metric = .Tempo, .value = 1.0 };
            },
            else => @panic("invalid spawn source"),
        }

        return Genome{
            .traits = traits,
            .sex = .Male,
        };
    }
};

const Sex = enum {
    Male,
    Female,
};

pub const Trait = struct {
    metric: Metric,
    value: f32,

    fn mutate(self: *Trait, rand: *std.Random, strength: f32) void {
        var v = self.value + u.randomGaussian(rand, f32) * strength;
        v = switch (self.metric) { // Mutation constraints
            .Width, .Height => if (v < 1.0) 1.0 else v,
            else => v,
        };
        self.value = v;
    }
};
