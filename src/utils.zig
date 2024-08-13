const rl = @import("raylib");
const std: type = @import("std");
const main = @import("main.zig");
const entity = @import("entity.zig");
const math = @import("std").math;
var rng: std.Random.DefaultPrng = undefined;

// Debug/analysis
//----------------------------------------------------------------------------------

/// Sets `main.profileTimer[timer]` and prints a message. Stop the timer with `utils.endTimer()`.
pub fn startTimer(timer: usize, comptime startMsg: []const u8) void {
    const msg = if (startMsg.len > 0 and startMsg[startMsg.len - 1] != '\n') startMsg ++ " " else startMsg;
    std.debug.print(msg, .{});
    main.profileTimer[timer] = rl.getTime();
}

/// Stops `main.profileTimer[timer]` and prints a message. Must write `{}` to add the result argument.
pub fn endTimer(timer: usize, comptime endMsg: []const u8) void {
    const result = rl.getTime() - main.profileTimer[timer];
    std.debug.print(endMsg ++ " \n", .{result});
    main.profileTimer[timer] = 0;
}

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

/// Prints the number of cells currently stored in the hashmap, corresponding to the
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

pub const Key = struct {
    pub const InputValue = enum(u32) {
        One = 1 << 1,
        Two = 1 << 2,
        Three = 1 << 3,
        Four = 1 << 4,
        Up = 1 << 5,
        Left = 1 << 6,
        Down = 1 << 7,
        Right = 1 << 8,
        Space = 1 << 9,
        Ctrl = 1 << 10,
        Enter = 1 << 11,
    };

    pub const Action = enum {
        BuildOne,
        BuildTwo,
        BuildThree,
        BuildFour,
        MoveUp,
        MoveLeft,
        MoveDown,
        MoveRight,
        SpecialSpace,
        SpecialCtrl,
        SpecialEnter,
    };

    pub const HashContext = struct {
        pub fn hash(self: Key.HashContext, action: Action) u64 {
            _ = self;
            return @intCast(@intFromEnum(action));
        }

        pub fn eql(self: Key.HashContext, a: Key.Action, b: Key.Action) bool {
            _ = self;
            return @intFromEnum(a) == @intFromEnum(b);
        }
    };

    const KeyBinding = std.HashMap(Action, InputValue, Key.HashContext, 80);
    bindings: KeyBinding,

    pub fn init(self: *Key, allocator: *std.mem.Allocator) !void {
        self.bindings = KeyBinding.init(allocator.*);

        // Initialize with default bindings
        try self.bindings.put(Action.BuildOne, InputValue.One);
        try self.bindings.put(Action.BuildTwo, InputValue.Two);
        try self.bindings.put(Action.BuildThree, InputValue.Three);
        try self.bindings.put(Action.BuildFour, InputValue.Four);
        try self.bindings.put(Action.MoveUp, InputValue.Up);
        try self.bindings.put(Action.MoveLeft, InputValue.Left);
        try self.bindings.put(Action.MoveDown, InputValue.Down);
        try self.bindings.put(Action.MoveRight, InputValue.Right);
        try self.bindings.put(Action.SpecialSpace, InputValue.Space);
        try self.bindings.put(Action.SpecialCtrl, InputValue.Ctrl);
        try self.bindings.put(Action.SpecialEnter, InputValue.Enter);
    }

    pub fn rebind(self: *Key, action: Action, newInput: InputValue) void {
        try self.bindings.put(action, newInput);
    }

    /// Takes `Key.InputValue` and `Key.Action.codeword` arguments. Returns whether the key corresponding to `action` is registered as active.
    /// Allows for rebindings with `Key.rebind` by changing links between `InputValue` and `Action`.
    pub fn actionActive(self: *Key, keyInput: u32, action: Action) bool {
        const inputValue = self.bindings.get(action);
        if (inputValue) |input| {
            return (keyInput & @intFromEnum(input)) != 0;
        } else {
            return false;
        }
    }
};

// RNG
//----------------------------------------------------------------------------------
pub fn rngInit() void {
    rng = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.milliTimestamp()))); // Initialize rng
}

pub fn randomU16(max: u16) u16 {
    const random_value = rng.next() % @as(u64, @intCast(max + 1));
    return @as(u16, @truncate(random_value));
}

pub fn randomI16(max: u16) i16 {
    const random_value = rng.next() % @as(u64, @intCast(max + 1));
    return @as(i16, @intCast(random_value));
}

// Math
//----------------------------------------------------------------------------------
pub fn angleToVector(angle: f32, magnitude: f32) [2]f32 {
    const radians = angle * std.math.pi / 180.0;
    return [2]f32{ magnitude * std.math.cos(radians), magnitude * std.math.sin(radians) };
}

pub fn deltaToAngle(dx: i32, dy: i32) f32 { // Supports fractional degrees
    const dxF = @as(f32, @floatFromInt(dx));
    const dyF = @as(f32, @floatFromInt(dy));
    const angle_radians = @as(f32, std.math.atan2(dxF, dyF));
    const angle_degrees = angle_radians * (180.0 / std.math.pi);
    return if (angle_degrees < 0) angle_degrees + 360.0 else angle_degrees;
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

pub fn u16AddFloat(comptime T: type, int: u16, floatValue: T) u16 {
    const floatyboy = @as(T, @floatFromInt(int));
    const resultFloat = floatyboy + floatValue;
    const clampedResult = @max(@as(T, 0), @min(@as(T, 65535), resultFloat));
    return @as(u16, @intFromFloat(clampedResult));
}

pub fn u16SubFloat(comptime T: type, int: u16, floatValue: T) u16 {
    const subValue = @as(u16, @intFromFloat(floatValue));
    return if (int >= subValue) int - subValue else return 0; // Minimum 0
}

pub fn u16TimesFloat(comptime T: type, int: u16, floatValue: T) u16 {
    return @as(u16, @intFromFloat(@as(T, @floatFromInt(int)) * floatValue));
}

pub fn ceilDiv(numerator: i32, denominator: i32) i32 {
    const divResult = @divTrunc(numerator, denominator);
    const remainder = @rem(numerator, denominator);
    return if (remainder != 0) divResult + 1 else divResult;
}

// Geometry
//----------------------------------------------------------------------------------
pub const Point = struct {
    x: u16,
    y: u16,
};

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

pub fn dirOffset(x: u16, y: u16, dir: u8, offset: u16) [2]u16 {
    var oX = x;
    var oY = y;
    switch (dir) {
        2 => oY += offset,
        4 => oX -= offset,
        6 => oX += offset,
        8 => oY -= offset,
        else => return [2]u16{ x, y },
    }
    return [2]u16{ oX, oY };
}

pub fn isHorz(dir: u8) bool {
    return dir == 4 or dir == 6;
}

/// Returns 0 if size of area1 > area2. Returns 1 if size of area1 < area2. Otherwise returns 2.
pub fn bigger(w1: u16, h1: u16, w2: u16, h2: u16) u2 {
    if (w1 * h1 > w2 * h2) return 0 else if (w1 * h1 < w2 * h2) return 1 else return 2;
}

/// Compares area sizes, returning the factor of `w1` * `h1` and `w2` * `h2`.
pub fn sizeFactor(w1: u16, h1: u16, w2: u16, h2: u16) f32 {
    const area1 = @as(f32, w1) * @as(f32, h1);
    const area2 = @as(f32, w2) * @as(f32, h2);
    return area1 / area2;
}

// Hashmap
//----------------------------------------------------------------------------------

pub const Grid = struct {
    pub const CellSize = main.GRID_CELL_SIZE;
    pub const HalfCell: comptime_int = CellSize / 2;

    pub inline fn getNeighborhood() [9][2]i16 {
        return [_][2]i16{
            [_]i16{ 0, 0 }, // Central cell
            [_]i16{ -CellSize, 0 }, // Left neighbor
            [_]i16{ CellSize, 0 }, // Right neighbor
            [_]i16{ 0, -CellSize }, // Top neighbor
            [_]i16{ 0, CellSize }, // Bottom neighbor
            [_]i16{ -CellSize, -CellSize }, // Top-left
            [_]i16{ CellSize, CellSize }, // Bottom-right
            [_]i16{ -CellSize, CellSize }, // Bottom-left
            [_]i16{ CellSize, -CellSize }, // Top-right
        };
    }

    pub inline fn getValidNeighbors(x: u16, y: u16, mapWidth: u16, mapHeight: u16) []const [2]u16 {
        var neighbors: [9][2]u16 = undefined;
        var count: usize = 0;
        neighbors[count] = [2]u16{ x, y }; // Always include the central cell
        count += 1;

        // Check and add left neighbors
        if (x >= CellSize) {
            neighbors[count] = [2]u16{ x - CellSize, y };
            count += 1;
            if (y >= CellSize) {
                neighbors[count] = [2]u16{ x - CellSize, y - CellSize }; // Top-left
                count += 1;
            }
            if (y + CellSize <= mapHeight) {
                neighbors[count] = [2]u16{ x - CellSize, y + CellSize }; // Bottom-left
                count += 1;
            }
        }
        // Check and add right neighbors
        if (x + CellSize <= mapWidth) {
            neighbors[count] = [2]u16{ x + CellSize, y };
            count += 1;
            if (y >= CellSize) {
                neighbors[count] = [2]u16{ x + CellSize, y - CellSize }; // Top-right
                count += 1;
            }
            if (y + CellSize <= mapHeight) {
                neighbors[count] = [2]u16{ x + CellSize, y + CellSize }; // Bottom-right
                count += 1;
            }
        }
        if (y >= CellSize) { // Check and add top neighbor
            neighbors[count] = [2]u16{ x, y - CellSize };
            count += 1;
        }
        if (y + CellSize <= mapHeight) { // Check and add bottom neighbor
            neighbors[count] = [2]u16{ x, y + CellSize };
            count += 1;
        }
        return neighbors[0..count];
    }

    pub fn gridX(x: u16) u16 {
        return @divFloor(x, CellSize);
    }

    pub fn gridY(y: u16) u16 {
        return @divFloor(y, CellSize);
    }

    pub fn closestNode(x: u16, y: u16) [2]u16 {
        const closestX = @divTrunc((x + HalfCell), CellSize) * CellSize;
        const closestY = @divTrunc((y + HalfCell), CellSize) * CellSize;
        return [2]u16{ closestX, closestY };
    }

    pub fn closestNodeOffset(x: u16, y: u16, dir: u8, width: u16, height: u16) [2]u16 {
        const delta = if (isHorz(dir)) width else height;
        const offsetXy = dirOffset(x, y, dir, delta);
        return closestNode(offsetXy[0], offsetXy[1]);
    }
};

pub const SpatialHash = struct {
    pub fn hash(x: u16, y: u16) u64 {
        const gridX = @divFloor(@as(u64, @intCast(x)), Grid.CellSize); // Left cell edge
        const gridY = @divFloor(@as(u64, @intCast(y)), Grid.CellSize); // Top cell edge
        const hashValue = (gridX << 32) | gridY;

        return hashValue;
    }
    pub const Context = struct {
        pub fn hash(self: Context, key: u64) u64 {
            _ = self;
            return key;
        }

        pub fn eql(self: Context, a: u64, b: u64) bool {
            _ = self;
            return a == b;
        }
    };
};

pub fn testHashFunction() void {
    const min_x: u16 = 0;
    const max_x: u16 = main.mapWidth;
    const min_y: u16 = 0;
    const max_y: u16 = main.mapHeight;
    const step: u16 = 1;

    std.log.info("\nTesting hash function. Checking hash values for positions between {}, {} and {}, {}, with an increment of {}.", .{ min_x, min_y, max_x, max_y, step });

    var seenHashes = std.hash_map.HashMap(u64, bool, SpatialHash.Context, 80).init(std.heap.page_allocator);
    defer seenHashes.deinit();
    var collisionCount: usize = 0;

    var x: u16 = min_x;
    while (x <= max_x) : (x += step * Grid.CellSize) {
        var y: u16 = min_y; // Reset y for each new x
        while (y <= max_y) : (y += step * Grid.CellSize) {
            const hashValue = SpatialHash.hash(x, y);

            if (seenHashes.getOrPut(hashValue)) |existing| {
                if (existing.found_existing) {
                    collisionCount += 1;
                    std.debug.print("Collision detected at ({}, {}) with hash value {}.\n", .{ x, y, hashValue });
                }
            } else |err| {
                std.log.err("Error adding hash value {} to hashmap: {}.", .{ hashValue, err });
            }
        }
    }

    if (collisionCount == 0) {
        std.log.info("No collisions detected.\n", .{});
    } else {
        std.log.warn("Detected {} collisions in the hash function.\n", .{collisionCount});
    }
}

// Map Coordinates
//----------------------------------------------------------------------------------
pub fn isOnMap(x: u16, y: u16) bool {
    return x >= 0 and x < main.mapWidth and y >= 0 and y <= main.mapHeight;
}

pub fn isInMap(x: u16, y: u16, width: u16, height: u16) bool {
    return x - @divTrunc(width, 2) >= 0 and x + @divTrunc(width, 2) < main.mapWidth and y - @divTrunc(height, 2) >= 0 and y + @divTrunc(height, 2) <= main.mapHeight;
}

pub fn mapClampX(x: i16, width: u16) u16 {
    const halfWidth = @as(i16, @intCast(@divTrunc(width, 2)));
    const clampedX = @max(halfWidth, @min(x, @as(i16, @intCast(main.mapWidth)) - halfWidth));
    return @as(u16, @intCast(clampedX));
}

pub fn mapClampY(y: i16, height: u16) u16 {
    const halfHeight = @as(i16, @intCast(@divTrunc(height, 2)));
    const clampedY = @max(halfHeight, @min(y, @as(i16, @intCast(main.mapHeight)) - halfHeight));
    return @as(u16, @intCast(clampedY));
}

pub fn closestNexus(x: u16, y: u16) [2]u16 {
    const quadSize = main.GRID_CELL_SIZE / 2;
    const nexLength = quadSize / 2;
    const closestX = @divTrunc(x, quadSize) * quadSize + nexLength;
    const closestY = @divTrunc(y, quadSize) * quadSize + nexLength;
    return [2]u16{ closestX, closestY };
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

pub fn canvasOnPlayer() void {
    const screenWidthF = @as(f32, @floatFromInt(main.screenWidth));
    const screenHeightF = @as(f32, @floatFromInt(main.screenHeight));
    main.canvasOffsetX = -(@as(f32, @floatFromInt(main.gamePlayer.x)) * main.canvasZoom) + (screenWidthF / 2);
    main.canvasOffsetY = -(@as(f32, @floatFromInt(main.gamePlayer.y)) * main.canvasZoom) + (screenHeightF / 2);
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
