const std = @import("std");
const MapFile = @import("map.zig").MapFile;

// To update maps:
// zig run src/map_gen.zig

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.fs.cwd().makeDir("maps") catch {};

    // Generate "Open Plains" map
    try generateOpenPlains(allocator, "maps/default.map");

    // Generate "Mini Test" map
    try generateMiniTest(allocator, "maps/mini.map");

    // Generate "Three Lanes" map
    try generateThreeLanes(allocator, "maps/three_lanes.map");

    std.debug.print("Maps generated successfully\n", .{});
}

fn generateThreeLanes(allocator: std.mem.Allocator, path: []const u8) !void {
    const width: u16 = 15000;
    const height: u16 = 9000;
    const terrain_width = @divTrunc(width, 64) + 1;
    const terrain_height = @divTrunc(height, 64) + 1;

    // Initialize terrain to ground
    const terrain = try allocator.alloc(u8, terrain_width * terrain_height);
    defer allocator.free(terrain);
    @memset(terrain, 0); // 0 = Ground

    // Draw two mountain dividers
    const divider1_x = terrain_width / 3;
    const divider2_x = terrain_width * 2 / 3;
    const gap_size = 5; // subcells
    const gap1 = terrain_height / 3;
    const gap2 = terrain_height * 2 / 3;

    for (0..terrain_height) |y| {
        // Skip gaps
        const in_gap = (y > gap1 - gap_size and y < gap1 + gap_size) or
            (y > gap2 - gap_size and y < gap2 + gap_size);
        if (in_gap) continue;

        // Draw dividers
        for (0..3) |offset| { // 3 subcells wide
            if (divider1_x + offset < terrain_width) {
                terrain[y * terrain_width + divider1_x + offset] = 1; // 1 = Mountain
            }
            if (divider2_x + offset < terrain_width) {
                terrain[y * terrain_width + divider2_x + offset] = 1;
            }
        }
    }

    // Start locations
    const starts = try allocator.alloc(MapFile.StartLocation, 2);
    defer allocator.free(starts);
    starts[0] = .{ .x = 1000, .y = height / 2 };
    starts[1] = .{ .x = width - 1000, .y = height / 2 };

    // Resources - place along lanes
    var resources = std.ArrayList(MapFile.ResourceSpawn).init(allocator);
    defer resources.deinit();

    // Left lane
    for (0..20) |i| {
        const y = 1000 + i * (height - 2000) / 20;
        try resources.append(.{ .x = width / 6, .y = @intCast(y), .class = 0 });
    }
    // Middle lane
    for (0..20) |i| {
        const y = 1000 + i * (height - 2000) / 20;
        try resources.append(.{ .x = width / 2, .y = @intCast(y), .class = 0 });
    }
    // Right lane
    for (0..20) |i| {
        const y = 1000 + i * (height - 2000) / 20;
        try resources.append(.{ .x = width / 6 * 5, .y = @intCast(y), .class = 0 });
    }

    const map = MapFile{
        .version = 1,
        .width = width,
        .height = height,
        .player_count = 2,
        .terrain = terrain,
        .start_locations = starts,
        .resources = try resources.toOwnedSlice(),
    };

    try map.save(path);
}

fn generateOpenPlains(allocator: std.mem.Allocator, path: []const u8) !void {
    const width: u16 = 15000;
    const height: u16 = 9000;
    const terrain_width = @divTrunc(width, 64) + 1;
    const terrain_height = @divTrunc(height, 64) + 1;

    const terrain = try allocator.alloc(u8, terrain_width * terrain_height);
    defer allocator.free(terrain);
    @memset(terrain, 0);

    // Scatter some mountain clusters
    var prng = std.rand.DefaultPrng.init(42);
    const random = prng.random();

    for (0..15) |_| {
        const cx = random.intRangeAtMost(usize, 10, terrain_width - 10);
        const cy = random.intRangeAtMost(usize, 10, terrain_height - 10);

        // Small cluster
        for (0..random.intRangeAtMost(usize, 3, 8)) |_| {
            const ox = random.intRangeAtMost(isize, -5, 5);
            const oy = random.intRangeAtMost(isize, -5, 5);
            const x = @as(usize, @intCast(@max(0, @min(@as(isize, @intCast(cx)) + ox, terrain_width - 1))));
            const y = @as(usize, @intCast(@max(0, @min(@as(isize, @intCast(cy)) + oy, terrain_height - 1))));

            terrain[y * terrain_width + x] = 1;
        }
    }

    const starts = try allocator.alloc(MapFile.StartLocation, 2);
    defer allocator.free(starts);
    starts[0] = .{ .x = 1500, .y = 1500 };
    starts[1] = .{ .x = width - 1500, .y = height - 1500 };

    // Random resources
    var resources = std.ArrayList(MapFile.ResourceSpawn).init(allocator);
    defer resources.deinit();

    for (0..100) |_| {
        try resources.append(.{
            .x = @intCast(random.intRangeAtMost(u16, 1000, width - 1000)),
            .y = @intCast(random.intRangeAtMost(u16, 1000, height - 1000)),
            .class = 0,
        });
    }

    const map = MapFile{
        .version = 1,
        .width = width,
        .height = height,
        .player_count = 2,
        .terrain = terrain,
        .start_locations = starts,
        .resources = try resources.toOwnedSlice(),
    };

    try map.save(path);
}

fn generateMiniTest(allocator: std.mem.Allocator, path: []const u8) !void {
    const width: u16 = 1024 * 3;
    const height: u16 = 1024 * 2;
    const terrain_width = @divTrunc(width, 64) + 1;
    const terrain_height = @divTrunc(height, 64) + 1;

    const terrain = try allocator.alloc(u8, terrain_width * terrain_height);
    defer allocator.free(terrain);
    @memset(terrain, 0);

    // Scatter some mountain clusters
    var prng = std.rand.DefaultPrng.init(42);
    const random = prng.random();

    for (0..8) |_| {
        const cx = random.intRangeAtMost(usize, 10, terrain_width - 10);
        const cy = random.intRangeAtMost(usize, 10, terrain_height - 10);

        // Small cluster
        for (0..random.intRangeAtMost(usize, 3, 8)) |_| {
            const ox = random.intRangeAtMost(isize, -5, 5);
            const oy = random.intRangeAtMost(isize, -5, 5);
            const x = @as(usize, @intCast(@max(0, @min(@as(isize, @intCast(cx)) + ox, terrain_width - 1))));
            const y = @as(usize, @intCast(@max(0, @min(@as(isize, @intCast(cy)) + oy, terrain_height - 1))));

            terrain[y * terrain_width + x] = 1;
        }
    }

    const starts = try allocator.alloc(MapFile.StartLocation, 1);
    defer allocator.free(starts);
    starts[0] = .{ .x = 500, .y = 500 };

    // Random resources
    var resources = std.ArrayList(MapFile.ResourceSpawn).init(allocator);
    defer resources.deinit();

    for (0..40) |_| {
        try resources.append(.{
            .x = @intCast(random.intRangeAtMost(u16, 300, width - 300)),
            .y = @intCast(random.intRangeAtMost(u16, 300, height - 300)),
            .class = random.intRangeAtMost(u8, 0, 1),
        });
    }

    const map = MapFile{
        .version = 1,
        .width = width,
        .height = height,
        .player_count = 1,
        .terrain = terrain,
        .start_locations = starts,
        .resources = try resources.toOwnedSlice(),
    };

    try map.save(path);
}
