const rl = @import("raylib");
const std: type = @import("std");
const main = @import("main.zig");
const u = @import("utils.zig");
const e = @import("entity.zig");

pub const MapFile = struct {
    version: u8,
    width: u16,
    height: u16,
    player_count: u8,
    // Variable length data
    terrain: []u8, // Flat array: terrain_width * terrain_height
    start_locations: []StartLocation,
    resources: []ResourceSpawn,

    pub const StartLocation = packed struct {
        x: u16,
        y: u16,
    };

    pub const ResourceSpawn = packed struct {
        x: u16,
        y: u16,
        class: u8,
    };

    /// Takes subcell col and row and returns its map terrain type.
    pub fn terrainAtSubcell(self: MapFile, tx: usize, ty: usize) TerrainType {
        const tw = @divTrunc(self.width, u.Subcell.size) + 1;
        if (tx >= tw) return .Ground;
        const index = ty * tw + tx;
        return @enumFromInt(self.terrain[index]);
    }

    /// Takes world coordinates and returns the terrain type of the containing subcell.
    pub fn terrainAt(self: MapFile, world_x: i32, world_y: i32) TerrainType {
        const tx = @as(i32, @intCast(world_x / u.Subcell.size));
        const ty = @as(i32, @intCast(world_y / u.Subcell.size));

        if (tx < 0 or ty < 0 or tx >= self.terrain_width or ty >= self.terrain_height) {
            return .Ground;
        }
        const index = ty * self.terrain_width + tx;
        return @enumFromInt(self.terrain[index]);
    }

    /// Returns the subcells that block movement due to terrain.
    pub fn getTerrainBlockedSubcells(self: MapFile, allocator: *std.mem.Allocator) ![]u.Subcell {
        const tw = @divTrunc(self.width, u.Subcell.size) + 1;
        const th = @divTrunc(self.height, u.Subcell.size) + 1;

        var subcells = std.ArrayList(u.Subcell).init(allocator.*);
        defer subcells.deinit();

        for (0..th) |y| {
            for (0..tw) |x| {
                const terrain_type = self.terrainAtSubcell(x, y);
                if (terrain_type.isBlocking()) {
                    const nx = @as(u16, @intCast(x * u.Subcell.size + u.Subcell.half));
                    const ny = @as(u16, @intCast(y * u.Subcell.size + u.Subcell.half));
                    const subcell = u.Subcell.fromNode(u.Point.at(nx, ny));
                    try subcells.append(subcell);
                }
            }
        }
        return subcells.toOwnedSlice();
    }

    pub fn save(self: MapFile, path: []const u8) !void {
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        var writer = file.writer();

        // Write header
        try writer.writeByte(self.version);
        try writer.writeInt(u16, self.width, .little);
        try writer.writeInt(u16, self.height, .little);
        try writer.writeByte(self.player_count);

        // Write terrain dimensions
        const terrain_width: u16 = @intCast(@divTrunc(self.width, u.Subcell.size) + 1);
        const terrain_height: u16 = @intCast(@divTrunc(self.height, u.Subcell.size) + 1);
        try writer.writeInt(u16, terrain_width, .little);
        try writer.writeInt(u16, terrain_height, .little);

        // Write terrain data (run-length encoded for compression)
        try writeTerrainRLE(writer, self.terrain);

        // Write start locations
        try writer.writeInt(u16, @intCast(self.start_locations.len), .little);
        for (self.start_locations) |loc| {
            try writer.writeInt(u16, loc.x, .little);
            try writer.writeInt(u16, loc.y, .little);
        }

        // Write resources
        try writer.writeInt(u16, @intCast(self.resources.len), .little);
        for (self.resources) |res| {
            try writer.writeInt(u16, res.x, .little);
            try writer.writeInt(u16, res.y, .little);
            try writer.writeByte(res.class);
        }
    }

    pub fn load(path: []const u8, allocator: std.mem.Allocator) !MapFile {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        var reader = file.reader();

        // Read header
        const version = try reader.readByte();
        const width = try reader.readInt(u16, .little);
        const height = try reader.readInt(u16, .little);
        const player_count = try reader.readByte();

        // Read terrain dimensions
        const terrain_width = try reader.readInt(u16, .little);
        const terrain_height = try reader.readInt(u16, .little);

        // Read terrain (RLE decoded)
        const terrain = try readTerrainRLE(reader, allocator, terrain_width, terrain_height);

        // Read start locations
        const start_count = try reader.readInt(u16, .little);
        const start_locations = try allocator.alloc(StartLocation, start_count);
        for (start_locations) |*loc| {
            loc.x = try reader.readInt(u16, .little);
            loc.y = try reader.readInt(u16, .little);
        }

        // Read resources
        const resource_count = try reader.readInt(u16, .little);
        const resources = try allocator.alloc(ResourceSpawn, resource_count);
        for (resources) |*res| {
            res.x = try reader.readInt(u16, .little);
            res.y = try reader.readInt(u16, .little);
            res.class = try reader.readByte();
        }

        return MapFile{
            .version = version,
            .width = width,
            .height = height,
            .player_count = player_count,
            .terrain = terrain,
            .start_locations = start_locations,
            .resources = resources,
        };
    }

    // Simple run-length encoding for terrain
    fn writeTerrainRLE(writer: anytype, terrain: []u8) !void {
        if (terrain.len == 0) return;

        var current_type = terrain[0];
        var run_length: u16 = 1;

        for (terrain[1..]) |tile| {
            if (tile == current_type and run_length < 65535) {
                run_length += 1;
            } else {
                // Write run
                try writer.writeByte(current_type);
                try writer.writeInt(u16, run_length, .little);

                current_type = tile;
                run_length = 1;
            }
        }

        // Write final run
        try writer.writeByte(current_type);
        try writer.writeInt(u16, run_length, .little);
    }

    fn readTerrainRLE(reader: anytype, allocator: std.mem.Allocator, width: u16, height: u16) ![]u8 {
        const total_size = @as(usize, width) * @as(usize, height);
        var terrain = try allocator.alloc(u8, total_size);
        var index: usize = 0;

        while (index < total_size) {
            const tile_type = try reader.readByte();
            const run_length = try reader.readInt(u16, .little);

            var i: u16 = 0;
            while (i < run_length and index < total_size) : (i += 1) {
                terrain[index] = tile_type;
                index += 1;
            }
        }

        return terrain;
    }

    pub fn deinit(self: *MapFile, allocator: std.mem.Allocator) void {
        allocator.free(self.terrain);
        allocator.free(self.start_locations);
        allocator.free(self.resources);
    }
};

pub const TerrainType = enum(u8) {
    Ground = 0,
    Mountain = 1,
    Water = 2,
    Forest = 3,

    pub fn isBlocking(self: TerrainType) bool {
        return switch (self) {
            .Mountain, .Water => true,
            .Ground, .Forest => false,
        };
    }

    pub fn movementCost(self: TerrainType) u8 {
        return switch (self) {
            .Ground => 1,
            .Forest => 2,
            .Mountain, .Water => 255, // Effectively impassable
        };
    }

    pub fn color(self: TerrainType) rl.Color {
        return switch (self) {
            .Ground => rl.Color.init(50, 50, 50, 255), // Dark
            .Mountain => rl.Color.init(100, 100, 100, 255), // Gray
            .Water => rl.Color.init(50, 50, 150, 255), // Blue
            .Forest => rl.Color.init(40, 100, 40, 255), // Green
        };
    }
};
