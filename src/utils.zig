const rl = @import("raylib");
const std: type = @import("std");
const main = @import("main.zig");
const entity = @import("entity.zig");
const math = @import("std").math;
var rng: std.Random.DefaultPrng = undefined;

// Debug/analysis
//----------------------------------------------------------------------------------
pub fn printTotalEntitiesOnGrid(grid: *entity.Grid) void {
    var totalEntities: usize = 0;

    for (grid.cells) |row| {
        for (row) |cell| {
            totalEntities += cell.entities.items.len;
        }
    }

    std.debug.print("Entities on grid: {}\n", .{totalEntities});
}

// Data structures
//----------------------------------------------------------------------------------
pub fn findAndSwapRemove(comptime T: type, list: *std.ArrayList(*T), ptr: *T) !void {
    var foundIndex: ?usize = null;

    // Iterate over the items in the list to find the index of the item matching ptr
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

// RNG
//----------------------------------------------------------------------------------
pub fn rngInit() void {
    rng = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.milliTimestamp()))); // Initialize rng
}

pub fn randomInt(max: i32) i32 {
    const random_value = rng.next() % @as(u64, @intCast(max + 1));
    return @as(i32, @intCast(random_value));
}

// Math
//----------------------------------------------------------------------------------
pub fn angleToVector(angle: f16) [2]f16 {
    const radians = angle * math.pi / 180.0;
    return [2]f16{ math.cos(radians), math.sin(radians) };
}

pub fn iAddF16(int: i32, float: f16) i32 {
    return int + @as(i32, @intFromFloat(float));
}

pub fn iSubF16(int: i32, float: f16) i32 {
    return int - @as(i32, @intFromFloat(float));
}

pub fn iTimesF16(int: i32, float: f16) i32 {
    return @as(i32, @intFromFloat(@as(f16, @floatFromInt(int)) * float));
}

pub fn ceilDiv(numerator: i32, denominator: i32) i32 {
    const divResult = @divTrunc(numerator, denominator);
    const remainder = @rem(numerator, denominator);
    return if (remainder != 0) divResult + 1 else divResult;
}

// Map Coordinates
//----------------------------------------------------------------------------------
pub const Point = struct {
    x: i32,
    y: i32,
};

pub const Grid = struct {
    pub const CellSize = 128;

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
