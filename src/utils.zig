const rl = @import("raylib");
const std: type = @import("std");
const main = @import("main.zig");
const entity = @import("entity.zig");
const math = @import("std").math;
var rng: std.Random.DefaultPrng = undefined;

// Debug/analysis
//----------------------------------------------------------------------------------
pub fn assert(condition: bool, failureMsg: []const u8) void {
    if (!condition) {
        @panic(failureMsg);
    }
}

/// Prints the number of key-value pairs stored across all grid cells.
pub fn printGridEntities(grid: *entity.Grid) void {
    var total_entities: usize = 0;
    var it = grid.cells.iterator();
    while (it.next()) |entry| {
        total_entities += entry.value_ptr.items.len;
    }
    std.debug.print("Total entities on the grid: {}.\n", .{total_entities});
}

/// Prints the number of cells currently stored in the grid hash map, corresponding to the
/// number of distinct cells that contain one or more entities.
pub fn printGridCells(grid: *entity.Grid) void {
    std.debug.print("Currently active cells on the grid: {}.\n", .{grid.cells.count()});
}

pub fn perFrame(frequency: i64) bool {
    return @mod(main.frameCount, frequency) == 0;
}

pub fn scaleToTickRate(float: f32) f32 { // Delta time capped to tickrate
    return (float * (@max(@as(f32, @floatCast(main.TICK_DURATION)), rl.getFrameTime()))) * main.TICKRATE;
}

// Data structures
//----------------------------------------------------------------------------------
/// Iterate over the items in the ArrayList to find the index of the item matching ptr,
/// swap with the last indexed item, then remove it from the last index.
pub fn findAndSwapRemove(comptime T: type, list: *std.ArrayList(*T), ptr: *T) !void {
    var foundIndex: ?usize = null;

    for (list.items, 0..) |item, i| {
        if (item == ptr) { // Compare the pointer addresses
            foundIndex = i;
            break;
        }
    }

    if (foundIndex) |index| {
        _ = list.swapRemove(index);
    } else {
        return error.ItemNotFound;
    }
}

pub fn ticksFromSecs(seconds: f16) u16 {
    return @as(u16, @intFromFloat(seconds * main.TICKRATE));
}

// RNG
//----------------------------------------------------------------------------------
pub fn rngInit() void {
    rng = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.milliTimestamp()))); // Initialize rng
}

pub fn randomInt(max: i32) i32 {
    if (max < 0) {
        std.debug.panic("randomInt called with a negative max: {}", .{max});
    }
    const random_value = rng.next() % @as(u64, @intCast(max + 1));
    return @as(i32, @intCast(random_value));
}

// Math
//----------------------------------------------------------------------------------
pub fn angleToVector(angle: f16) [2]f16 {
    const radians = angle * math.pi / 180.0;
    return [2]f16{ math.cos(radians), math.sin(radians) };
}

/// Equivalent to std.math.clamp
pub fn clamp(val: anytype, lower: anytype, upper: anytype) @TypeOf(val, lower, upper) {
    return @max(lower, @min(val, upper));
}

pub fn i32AddFloat(comptime T: type, int: i32, floatValue: T) i32 {
    return int + @as(i32, @intFromFloat(floatValue));
}

pub fn i32SubFloat(comptime T: type, int: i32, floatValue: T) i32 {
    return int - @as(i32, @intFromFloat(floatValue));
}

pub fn i32TimesFloat(comptime T: type, int: i32, floatValue: T) i32 {
    return @as(i32, @intFromFloat(@as(T, @floatFromInt(int)) * floatValue));
}

pub fn ceilDiv(numerator: i32, denominator: i32) i32 {
    const divResult = @divTrunc(numerator, denominator);
    const remainder = @rem(numerator, denominator);
    return if (remainder != 0) divResult + 1 else divResult;
}

// Geometry
//----------------------------------------------------------------------------------
pub fn dirDelta(dir: u8) [2]i8 {
    var x: i8 = 0;
    var y: i8 = 0;
    switch (dir) {
        2 => y += 1,
        4 => x -= 1,
        6 => x += 1,
        8 => y -= 1,
        else => return [2]i8{ 0, 0 },
    }
    return [2]i8{ x, y };
}

pub fn isHorz(dir: u8) bool {
    return dir == 4 or dir == 6;
}

// Grid/spatial hashmap
//----------------------------------------------------------------------------------
pub const Point = struct {
    x: i32,
    y: i32,
};

pub const Grid = struct {
    pub const CellSize = main.GRID_CELL_SIZE;

    pub const GridCoord = struct {
        x: usize,
        y: usize,
    };

    pub fn toGridCoord(x: i32, y: i32, gridWidth: usize, gridHeight: usize) GridCoord {
        const iX = @divFloor(x, CellSize);
        const iY = @divFloor(y, CellSize);
        const maxGridWidth = @as(i32, @intCast(gridWidth - 1));
        const maxGridHeight = @as(i32, @intCast(gridHeight - 1));
        return GridCoord{
            .x = @as(usize, @max(0, @min(iX, maxGridWidth))),
            .y = @as(usize, @max(0, @min(iY, maxGridHeight))),
        };
    }
};

pub const SpatialHash = struct {
    pub const CellSize = main.GRID_CELL_SIZE;

    pub fn hash(x: i32, y: i32) u64 {
        const gridX = @divFloor(x, CellSize);
        const gridY = @divFloor(y, CellSize);
        const hashValue = @as(u64, @intCast(gridX)) << 32 | @as(u64, @intCast(gridY));

        return hashValue;
    }
};

pub const HashContext = struct {
    pub fn hash(self: HashContext, key: u64) u64 {
        _ = self;
        return key;
    }

    pub fn eql(self: HashContext, a: u64, b: u64) bool {
        _ = self;
        return a == b;
    }
};

pub fn testHashFunction() void {
    const min_x: i32 = 0;
    const max_x: i32 = main.mapWidth;
    const min_y: i32 = 0;
    const max_y: i32 = main.mapHeight;
    const step: i32 = 953; // Adjust step for more or less granularity

    std.log.info("Printing hash values for positions between min_x {}, max_x {}, min_y {}, max_y {}, with an increment of {}.\n", .{ min_x, max_x, min_y, max_y, step });

    var x: i32 = min_x;
    while (x <= max_x) : (x += step) {
        var y: i32 = min_y; // Reset y for each new x
        while (y <= max_y) : (y += step) {
            const hash_value = SpatialHash.hash(x, y);
            std.debug.print("({}, {}) = {}. ", .{ x, y, hash_value });
        }
    }
    std.log.info("\n Done printing hash values.\n", .{});
}

// Map Coordinates
//----------------------------------------------------------------------------------
pub fn isOnMap(x: i32, y: i32) bool {
    return x >= 0 and x < main.mapWidth and y >= 0 and y <= main.mapHeight;
}

pub fn isInMap(x: i32, y: i32, width: i32, height: i32) bool {
    return x - @divTrunc(width, 2) >= 0 and x + @divTrunc(width, 2) < main.mapWidth and y - @divTrunc(height, 2) >= 0 and y + @divTrunc(height, 2) <= main.mapHeight;
}

pub fn mapClampX(x: i32, width: i32) i32 {
    return @min(main.mapWidth - @divTrunc(width, 2), @max(x, @divTrunc(width, 2)));
}

pub fn mapClampY(y: i32, height: i32) i32 {
    return @min(main.mapHeight - @divTrunc(height, 2), @max(y, @divTrunc(height, 2)));
}

pub fn dirOffset(x: i32, y: i32, dir: u8, offset: i32) [2]i32 {
    var oX = x;
    var oY = y;
    switch (dir) {
        2 => oY += offset,
        4 => oX -= offset,
        6 => oX += offset,
        8 => oY -= offset,
        else => return [2]i32{ x, y },
    }
    return [2]i32{ oX, oY };
}

pub fn closestNode(x: i32, y: i32) [2]i32 {
    const closestX = @divTrunc((x + @divTrunc(main.GRID_CELL_SIZE, 2)), main.GRID_CELL_SIZE) * main.GRID_CELL_SIZE;
    const closestY = @divTrunc((y + @divTrunc(main.GRID_CELL_SIZE, 2)), main.GRID_CELL_SIZE) * main.GRID_CELL_SIZE;
    return [2]i32{ closestX, closestY };
}

pub fn closestNodeOffset(x: i32, y: i32, dir: u8, width: u16, height: u16) [2]i32 {
    const delta = if (isHorz(dir)) width else height;
    const offsetXy = dirOffset(x, y, dir, delta);
    return closestNode(offsetXy[0], offsetXy[1]);
}

// Canvas
//----------------------------------------------------------------------------------
/// Returns drawing position from posX given camera offsetX and zoom
pub fn canvasX(posX: i32, offsetX: f32, zoom: f32) i32 {
    const zoomedPosX = @as(f32, @floatFromInt(posX)) * zoom;
    return @as(i32, @intFromFloat(zoomedPosX + offsetX));
}

/// Returns drawing position from posY given camera offsetY and zoom
pub fn canvasY(posY: i32, offsetY: f32, zoom: f32) i32 {
    const zoomedPosY = @as(f32, @floatFromInt(posY)) * zoom;
    return @as(i32, @intFromFloat(zoomedPosY + offsetY));
}

/// Returns drawing scale given object scale and camera zoom
pub fn canvasScale(scale: i32, zoom: f32) i32 {
    const scaledValue = zoom * @as(f32, @floatFromInt(scale));
    return @as(i32, @intFromFloat(scaledValue));
}

// Drawing
//----------------------------------------------------------------------------------
/// Uses raylib to draw rectangle scaled and positioned to canvas
pub fn drawRect(x: i32, y: i32, width: i32, height: i32, col: rl.Color) void {
    rl.drawRectangle(canvasX(x, main.canvasOffsetX, main.canvasZoom), canvasY(y, main.canvasOffsetY, main.canvasZoom), canvasScale(width, main.canvasZoom), canvasScale(height, main.canvasZoom), col);
}

/// Draws rectangle centered on the x, y coordinates, scaled and positioned to canvas
pub fn drawEntity(x: i32, y: i32, width: i32, height: i32, col: rl.Color) void {
    rl.drawRectangle(canvasX(x - @divTrunc(width, 2), main.canvasOffsetX, main.canvasZoom), canvasY(y - @divTrunc(height, 2), main.canvasOffsetY, main.canvasZoom), canvasScale(width, main.canvasZoom), canvasScale(height, main.canvasZoom), col);
}
