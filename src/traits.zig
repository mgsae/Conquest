const std = @import("std");
const main = @import("main.zig");
const e = @import("entity.zig");
const u = @import("utils.zig");

const Metric = enum {
    Width,
    Height,
    Speed,
    Health,
    Hunger,
    Reach,
    Tempo,
    Carry,
};

pub const Genome = struct {
    traits: [@typeInfo(Metric).Enum.fields.len]Trait,
    sex: Sex,

    pub const Sex = enum {
        Male,
        Female,
    };

    pub fn applyToUnit(self: *const Genome, unit: *e.Unit) void {
        // Base values
        var width: f32 = 20.0;
        var height: f32 = 20.0;
        var speed: f32 = 30.0;
        var health: f32 = 100.0;
        var hunger: f32 = 20.0;
        var reach: f32 = 5.0;
        var tempo: f32 = 20.0;
        var carry: f32 = 3.0;

        for (self.traits) |trait| {
            switch (trait.metric) {
                .Width => width *= trait.value,
                .Height => height *= trait.value,
                .Speed => speed *= trait.value,
                .Health => health *= trait.value,
                .Hunger => hunger *= trait.value,
                .Reach => reach *= trait.value,
                .Tempo => tempo *= trait.value,
                .Carry => carry *= trait.value,
            }
        }

        unit.width = @intFromFloat(width);
        unit.height = @intFromFloat(height);
        unit.speed = @as(f16, @floatCast(speed));
        unit.health = @intFromFloat(health);
        unit.hunger = @intFromFloat(hunger);
        unit.tempo = @intFromFloat(tempo);
        unit.carry = @intFromFloat(carry);
        unit.life = unit.health;
        unit.reach = ((width + height) / 2) + reach;
    }

    /// Create offspring genome from two parents with mutation
    pub fn reproduce(self: *const Genome, other: *const Genome, allocator: *std.mem.Allocator) !Genome {
        var offspring_traits: [@typeInfo(Metric).Enum.fields.len]Trait = undefined;
        var rng = std.rand.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
        var random = rng.random();

        // Inherit traits from both parents with crossover
        for (0..offspring_traits.len) |i| {
            const parent_trait = if (random.boolean()) self.traits[i] else other.traits[i];
            offspring_traits[i] = Trait{
                .metric = parent_trait.metric,
                .value = parent_trait.value,
            };

            // Apply mutation with 20% chance
            if (random.float(f32) < 0.2) {
                offspring_traits[i].mutate(&random, 0.1);
            }
        }

        // Randomly determine sex
        const offspring_sex: Sex = if (random.boolean()) .Male else .Female;

        _ = allocator; // Suppress unused warning
        return Genome{
            .traits = offspring_traits,
            .sex = offspring_sex,
        };
    }

    /// Randomly mutate all traits
    pub fn mutateAll(self: *Genome, strength: f32) void {
        var random = main.World.rng.random();

        for (&self.traits) |*trait| {
            trait.mutate(&random, strength);
        }
    }

    pub fn preset(source: u8) Genome {
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
                traits[@intFromEnum(Metric.Carry)] = .{ .metric = .Carry, .value = 1.0 };
            },
            1 => { // Soldier
                traits[@intFromEnum(Metric.Width)] = .{ .metric = .Width, .value = 1.25 };
                traits[@intFromEnum(Metric.Height)] = .{ .metric = .Height, .value = 1.25 };
                traits[@intFromEnum(Metric.Speed)] = .{ .metric = .Speed, .value = 1.1 };
                traits[@intFromEnum(Metric.Health)] = .{ .metric = .Health, .value = 1.125 };
                traits[@intFromEnum(Metric.Hunger)] = .{ .metric = .Hunger, .value = 1.0 };
                traits[@intFromEnum(Metric.Reach)] = .{ .metric = .Reach, .value = 2.0 };
                traits[@intFromEnum(Metric.Tempo)] = .{ .metric = .Tempo, .value = 1.0 };
                traits[@intFromEnum(Metric.Carry)] = .{ .metric = .Carry, .value = 1.0 };
            },
            2 => { // Trebuchet
                traits[@intFromEnum(Metric.Width)] = .{ .metric = .Width, .value = 2.25 };
                traits[@intFromEnum(Metric.Height)] = .{ .metric = .Height, .value = 2.25 };
                traits[@intFromEnum(Metric.Speed)] = .{ .metric = .Speed, .value = 0.66 };
                traits[@intFromEnum(Metric.Health)] = .{ .metric = .Health, .value = 2.0 };
                traits[@intFromEnum(Metric.Hunger)] = .{ .metric = .Hunger, .value = 1.0 };
                traits[@intFromEnum(Metric.Reach)] = .{ .metric = .Reach, .value = 4.0 };
                traits[@intFromEnum(Metric.Tempo)] = .{ .metric = .Tempo, .value = 1.0 };
                traits[@intFromEnum(Metric.Carry)] = .{ .metric = .Carry, .value = 1.0 };
            },
            3 => { // Cavalry
                traits[@intFromEnum(Metric.Width)] = .{ .metric = .Width, .value = 1.75 };
                traits[@intFromEnum(Metric.Height)] = .{ .metric = .Height, .value = 1.75 };
                traits[@intFromEnum(Metric.Speed)] = .{ .metric = .Speed, .value = 2.0 };
                traits[@intFromEnum(Metric.Health)] = .{ .metric = .Health, .value = 1.0 };
                traits[@intFromEnum(Metric.Hunger)] = .{ .metric = .Hunger, .value = 1.0 };
                traits[@intFromEnum(Metric.Reach)] = .{ .metric = .Reach, .value = 2.5 };
                traits[@intFromEnum(Metric.Tempo)] = .{ .metric = .Tempo, .value = 1.0 };
                traits[@intFromEnum(Metric.Carry)] = .{ .metric = .Carry, .value = 1.0 };
            },
            else => @panic("invalid spawn source"),
        }

        // Randomly assign sex for initial units
        const sex: Sex = if (u.randomBool()) .Male else .Female;

        return Genome{
            .traits = traits,
            .sex = sex,
        };
    }
};

pub const Trait = struct {
    metric: Metric,
    value: f32,

    fn mutate(self: *Trait, random: *std.Random, strength: f32) void {
        // Gaussian mutation
        const mutation = u.randomGaussian(random, f32) * strength;
        var v = self.value + mutation;

        // Apply metric-specific constraints
        v = switch (self.metric) {
            .Width, .Height => @max(0.5, v), // Minimum size
            .Speed => @max(0.3, @min(3.0, v)), // Speed bounds
            .Health => @max(0.5, v), // Minimum health
            .Reach => @max(0.5, v), // Minimum reach
            .Tempo => @max(0.5, v), // Minimum tempo
            .Hunger => @max(0.3, @min(3.0, v)), // Hunger rate bounds
            .Carry => @max(0, v), // Minimum carry capacity
        };

        self.value = v;
    }
};
