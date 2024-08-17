const rl = @import("raylib");
const std: type = @import("std");
const main = @import("main.zig");
const entity = @import("entity.zig");
const math = @import("std").math;
var rng: std.Random.DefaultPrng = undefined;

// Debug/analysis
//----------------------------------------------------------------------------------

/// Sets `main.profile_timer[timer]` and prints a message. Stop the timer with `utils.endTimer()`.
pub fn startTimer(timer: usize, comptime startMsg: []const u8) void {
    const msg = if (startMsg.len > 0 and startMsg[startMsg.len - 1] != '\n') startMsg ++ " " else startMsg;
    std.debug.print(msg, .{});
    main.profile_timer[timer] = rl.getTime();
}

/// Stops `main.profile_timer[timer]` and prints a message. Must write `{}` to add the result argument.
pub fn endTimer(timer: usize, comptime endMsg: []const u8) void {
    const result = rl.getTime() - main.profile_timer[timer];
    std.debug.print(endMsg ++ " \n", .{result});
    main.profile_timer[timer] = 0;
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
    const players = entity.players.items.len;
    const structures = entity.structures.items.len;
    const units = entity.units.items.len;
    std.debug.print("Total entities on the grid: {} ({} players, {} structures, {} units).\n", .{ total_entities, players, structures, units });
    if (total_entities != players + structures + units) {
        std.log.err("DISCREPANCY DETECTED! Number of entities does not match the combined number of players, structures, and units.\n", .{});
    }
}

/// Prints the number of cells currently stored in the hashmap, corresponding to the
/// number of distinct cells that contain one or more entities.
pub fn printGridCells(grid: *entity.Grid) void {
    std.debug.print("Currently active cells on the grid: {}.\n", .{grid.cells.count()});
}

pub fn perFrame(frequency: u64) bool {
    return @mod(main.frame_number, frequency) == 0;
}

pub fn scaleToTickRate(float: f32) f32 { // Delta time capped to tickrate
    return (float * (@max(@as(f32, @floatCast(main.TICK_DURATION)), rl.getFrameTime()))) * main.TICKRATE;
}

// Value types and conversions
//----------------------------------------------------------------------------------
pub const u16max: u16 = std.math.maxInt(u16); // 65535
pub const i16max: i16 = std.math.maxInt(i16); // 32767
pub const u32max: u32 = std.math.maxInt(u32); // 4294967295
pub const i32max: i32 = std.math.maxInt(i32); // 2147483647

pub fn u16Clamped(comptime T: type, value: T) T {
    const lower_bound: T = @as(T, 0);
    var upper_bound: T = undefined;

    if (@typeInfo(T) == .Int and u16max <= std.math.maxInt(T)) {
        upper_bound = @as(T, u16max);
    } else if (@typeInfo(T) == .Int) {
        const max_value: T = @as(T, @intCast(std.math.maxInt(T)));
        const clamped_max: u16 = @as(u16, max_value);
        upper_bound = @as(T, clamped_max);
    } else if (@typeInfo(T) == .Float) {
        upper_bound = @as(T, @floatFromInt(u16max));
    } else {
        upper_bound = @as(T, u16max); // Fallback for other types.
    }

    return @max(lower_bound, @min(value, upper_bound));
}

pub fn i16Clamped(comptime T: type, value: T) T {
    return @max(-i16max, @min(value, i16max));
}

pub fn u32Clamped(comptime T: type, value: T) T {
    return @max(0, @min(value, u32max));
}

pub fn i32Clamped(comptime T: type, value: T) T {
    return @max(-i32max, @min(value, i32max));
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
        Z = 1 << 12,
    };

    pub const Action = enum {
        BuildOne,
        BuildTwo,
        BuildThree,
        BuildFour,
        BuildConfirm,
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
        try self.bindings.put(Action.BuildConfirm, InputValue.Z);
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

/// Fisher-Yates shuffle: iterates over the array and swaps each element with a randomly chosen element that comes after it (or itself).
pub fn shuffleArray(comptime T: type, array: []T) void {
    const len = u16Clamped(usize, array.len);
    for (array, 0..) |_, i| {
        const j = @as(usize, randomU16(@as(u16, @intCast(len - 1))));
        const temp = array[i];
        array[i] = array[j];
        array[j] = temp;
    }
}

// Math
//----------------------------------------------------------------------------------

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

    pub fn at(x: u16, y: u16) Point {
        return Point{
            .x = x,
            .y = y,
        };
    }
};

pub fn deltaXy(x1: u16, y1: u16, x2: u16, y2: u16) [2]i16 {
    return [2]i16{ @as(i16, @intCast(x1)) - @as(i16, @intCast(x2)), @as(i16, @intCast(y1)) - @as(i16, @intCast(y2)) };
}

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

/// Takes `x`,`y` and `dir`, and returns the new `x`,`y` after offsetting by `distance`. Return values are `>= 0`.
pub fn dirOffset(oX: u16, oY: u16, direction: u8, distance: u16) [2]u16 {
    var newX = oX;
    var newY = oY;
    switch (direction) {
        2 => newY += distance,
        4 => newX = if (newX > distance) newX - distance else 0,
        6 => newX += distance,
        8 => newY = if (newY > distance) newY - distance else 0,
        else => {}, // Handle other directions if needed
    }
    return [2]u16{ newX, newY };
}

pub fn angleFromDir(dir: u8) f32 {
    return switch (dir) {
        1 => 225.0, ///// Down-Left
        2 => 270.0, ///// Down
        3 => 315.0, ///// Down-Right
        4 => 180.0, ///// Left
        6 => 0.0, ///// Right
        7 => 135.0, ///// Up-Left
        8 => 90.0, ///// Up
        9 => 45.0, ///// Up-Right
        else => 0.0, //// Defaults to up for invalid input
    };
}

pub fn isHorz(dir: u8) bool {
    return dir == 4 or dir == 6;
}

/// Takes `angle` and `magnitude`, and returns the corresponding `x`,`y` coordinate offset from origin.
pub fn vectorToDelta(angle: f32, magnitude: f32) [2]f32 {
    const radians = angle * std.math.pi / 180.0;
    return [2]f32{ magnitude * std.math.cos(radians), -magnitude * std.math.sin(radians) };
}

/// Takes an `x`,`y` offset from origin, and returns the corresponding angle as a float value (`0.0` - `360.0`).
pub fn deltaToAngle(dx: i32, dy: i32) f32 {
    const dxF = @as(f32, @floatFromInt(dx));
    const dyF = @as(f32, @floatFromInt(dy));
    const angle_radians = @as(f32, std.math.atan2(dxF, dyF));
    const angle_degrees = angle_radians * (180.0 / std.math.pi) + 90; // 0 right, 90 up, 180 left, 270 down
    return if (angle_degrees < 0) angle_degrees + 360.0 else angle_degrees;
}

/// Takes an `x`,`y` origin coordinate and a `dX`,`dY` displacement. Returns the `Point` after translation.
pub fn deltaPoint(x: u16, y: u16, dX: f32, dY: f32) Point {
    const endX: f32 = @max(0, @as(f32, @floatFromInt(x)) + dX);
    const endY: f32 = @max(0, @as(f32, @floatFromInt(y)) + dY);
    return Point.at(@as(u16, @intFromFloat(@round(endX))), @as(u16, @intFromFloat(@round(endY)))); // Ah, sweet zig syntax
}

pub fn angleFromTo(x1: u16, y1: u16, x2: u16, y2: u16) f32 {
    const delta = deltaXy(x1, y1, x2, y2);
    return deltaToAngle(delta[0], delta[1]);
}

/// Returns 0 if size of area1 > area2. Returns 1 if size of area1 < area2. Otherwise returns 2.
pub fn bigger(w1: u16, h1: u16, w2: u16, h2: u16) u2 {
    if (w1 * h1 > w2 * h2) return 0 else if (w1 * h1 < w2 * h2) return 1 else return 2;
}

/// Compares area sizes, returning the factor of `w1` * `h1` and `w2` * `h2`.
pub fn sizeFactor(w1: u16, h1: u16, w2: u16, h2: u16) f32 {
    const area1 = @as(f32, @floatFromInt(w1)) * @as(f32, @floatFromInt(h1));
    const area2 = @as(f32, @floatFromInt(w2)) * @as(f32, @floatFromInt(h2));
    return area1 / area2;
}

// Hashmap
//----------------------------------------------------------------------------------

pub const Grid = struct {
    pub const cell_size = main.GRID_CELL_SIZE;
    pub const cell_half: comptime_int = cell_size / 2;

    pub inline fn section() [9][2]i16 {
        return [_][2]i16{
            [_]i16{ 0, 0 }, // Central cell
            [_]i16{ -1, 0 }, // Left neighbor
            [_]i16{ 1, 0 }, // Right neighbor
            [_]i16{ 0, -1 }, // Top neighbor
            [_]i16{ 0, 1 }, // Bottom neighbor
            [_]i16{ -1, -1 }, // Top-left
            [_]i16{ 1, 1 }, // Bottom-right
            [_]i16{ -1, 1 }, // Bottom-left
            [_]i16{ 1, -1 }, // Top-right
        };
    }

    pub inline fn sectionOffsets() [9][2]i16 {
        return [_][2]i16{
            [_]i16{ 0, 0 }, // Central cell
            [_]i16{ -cell_size, 0 }, // Left neighbor
            [_]i16{ cell_size, 0 }, // Right neighbor
            [_]i16{ 0, -cell_size }, // Top neighbor
            [_]i16{ 0, cell_size }, // Bottom neighbor
            [_]i16{ -cell_size, -cell_size }, // Top-left
            [_]i16{ cell_size, cell_size }, // Bottom-right
            [_]i16{ -cell_size, cell_size }, // Bottom-left
            [_]i16{ cell_size, -cell_size }, // Top-right
        };
    }

    /// Returns an array of 3x3 (up to 9) valid map `x`,`y` coordinates offset by grid `cell_size` from `world_x`,`world_y`.
    pub inline fn sectionFromPoint(world_x: u16, world_y: u16, map_width: u16, map_height: u16) []const [2]u16 {
        var neighbors: [9][2]u16 = undefined;
        var count: usize = 0;
        neighbors[count] = [2]u16{ world_x, world_y }; // Always include the central cell
        count += 1;

        // Check and add left neighbors
        if (world_x >= cell_size) {
            neighbors[count] = [2]u16{ world_x - cell_size, world_y };
            count += 1;
            if (world_y >= cell_size) {
                neighbors[count] = [2]u16{ world_x - cell_size, world_y - cell_size }; // Top-left
                count += 1;
            }
            if (world_y + cell_size <= map_height) {
                neighbors[count] = [2]u16{ world_x - cell_size, world_y + cell_size }; // Bottom-left
                count += 1;
            }
        }
        // Check and add right neighbors
        if (world_x + cell_size <= map_width) {
            neighbors[count] = [2]u16{ world_x + cell_size, world_y };
            count += 1;
            if (world_y >= cell_size) {
                neighbors[count] = [2]u16{ world_x + cell_size, world_y - cell_size }; // Top-right
                count += 1;
            }
            if (world_y + cell_size <= map_height) {
                neighbors[count] = [2]u16{ world_x + cell_size, world_y + cell_size }; // Bottom-right
                count += 1;
            }
        }
        if (world_y >= cell_size) { // Check and add top neighbor
            neighbors[count] = [2]u16{ world_x, world_y - cell_size };
            count += 1;
        }
        if (world_y + cell_size <= map_height) { // Check and add bottom neighbor
            neighbors[count] = [2]u16{ world_x, world_y + cell_size };
            count += 1;
        }
        return neighbors[0..count];
    }

    /// Converts a world coordinate `x` to the horizontal grid coordinate it falls into.
    /// #### Parameters
    /// - `world_x`: The `x` coordinate in the world space.
    /// #### Returns
    /// - The corresponding grid coordinate on the horizontal axis.
    pub fn x(world_x: u16) u16 {
        return @divFloor(world_x, cell_size);
    }

    /// Converts a world coordinate `y` to the vertical grid coordinate it falls into.
    /// #### Parameters
    /// - `world_y`: The `y` coordinate in the world space.
    /// #### Returns
    /// - The corresponding grid coordinate on the vertical axis.
    pub fn y(world_y: u16) u16 {
        return @divFloor(world_y, cell_size);
    }

    pub fn closestNode(world_x: u16, world_y: u16) [2]u16 {
        const closest_x = @divTrunc((world_x + cell_half), cell_size) * cell_size;
        const closest_y = @divTrunc((world_y + cell_half), cell_size) * cell_size;
        return [2]u16{ closest_x, closest_y };
    }

    pub fn closestNodeOffset(world_x: u16, world_y: u16, dir: u8, width: u16, height: u16) [2]u16 {
        const delta = if (isHorz(dir)) width else height;
        const offset_xy = dirOffset(world_x, world_y, dir, delta);
        return closestNode(offset_xy[0], offset_xy[1]);
    }

    pub fn entityCount(self: *entity.Grid) usize {
        var total_entities: usize = 0;
        var it = self.cells.iterator();
        while (it.next()) |entry| {
            total_entities += entry.value_ptr.items.len;
        }
        return total_entities;
    }
};

pub const SpatialHash = struct {
    pub fn hash(x: u16, y: u16) u64 {
        const grid_x = @divFloor(@as(u64, @intCast(x)), Grid.cell_size); // Left cell edge
        const grid_y = @divFloor(@as(u64, @intCast(y)), Grid.cell_size); // Top cell edge
        const hashValue = (grid_x << 32) | grid_y;

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
    const max_x: u16 = main.map_width;
    const min_y: u16 = 0;
    const max_y: u16 = main.map_height;
    const step: u16 = 1;

    std.log.info("\nTesting hash function. Checking hash values for positions between {}, {} and {}, {}, with an increment of {}.", .{ min_x, min_y, max_x, max_y, step });

    var seenHashes = std.hash_map.HashMap(u64, bool, SpatialHash.Context, 80).init(std.heap.page_allocator);
    defer seenHashes.deinit();
    var collisionCount: usize = 0;

    var x: u16 = min_x;
    while (x <= max_x) : (x += step * Grid.cell_size) {
        var y: u16 = min_y; // Reset y for each new x
        while (y <= max_y) : (y += step * Grid.cell_size) {
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
pub const subcell = struct {
    pub const size = main.GRID_CELL_SIZE / 10;

    /// Returns the top-left point of the closest 10th part of a cell to `x`,`y`.
    pub fn closest(x: u16, y: u16) [2]u16 {
        const closest_x = @divTrunc(x, subcell.size) * subcell.size;
        const closest_y = @divTrunc(y, subcell.size) * subcell.size;
        return [2]u16{ closest_x, closest_y };
    }

    /// Aligns the top-left point of the rectangle centered on `x`,`y` with the top-left of its closest subcell.
    pub fn snapPosition(x: u16, y: u16, width: u16, height: u16) [2]u16 {
        const snapped_center = subcell.closest(x - width / 2, y - height / 2);
        return [2]u16{ snapped_center[0] + width / 2, snapped_center[1] + height / 2 };
    }
};

pub fn isOnMap(x: u16, y: u16) bool {
    return x >= 0 and x < main.map_width and y >= 0 and y <= main.map_height;
}

pub fn isInMap(x: u16, y: u16, width: u16, height: u16) bool {
    const half_width = @divTrunc(width, 2);
    const half_height = @divTrunc(height, 2);

    const x_signed = @as(i32, @intCast(x));
    const y_signed = @as(i32, @intCast(y));

    return x_signed - half_width >= 0 and x_signed + half_width < @as(i32, @intCast(main.map_width)) and y_signed - half_height >= 0 and y_signed + half_height <= @as(i32, @intCast(main.map_height));
}

pub fn mapClampX(x: i16, width: u16) u16 {
    const half_width = @as(i16, @intCast(@divTrunc(width, 2)));
    const clamped_x = @max(half_width, @min(x, @as(i16, @intCast(main.map_width)) - half_width));
    return @as(u16, @intCast(clamped_x));
}

pub fn mapClampY(y: i16, height: u16) u16 {
    const half_height = @as(i16, @intCast(@divTrunc(height, 2)));
    const clamped_y = @max(half_height, @min(y, @as(i16, @intCast(main.map_height)) - half_height));
    return @as(u16, @intCast(clamped_y));
}

/// Returns the midpoint of the closest 4th part of a cell to `x`,`y`.
pub fn closestNexus(x: u16, y: u16) [2]u16 {
    const area_size = main.GRID_CELL_SIZE / 2;
    const nexus_offset = area_size / 2;
    const closest_x = @divTrunc(x, area_size) * area_size + nexus_offset;
    const closest_y = @divTrunc(y, area_size) * area_size + nexus_offset;
    return [2]u16{ closest_x, closest_y };
}

// Canvas
//----------------------------------------------------------------------------------
/// Returns drawing position from world `x` given camera `offset_x` and `zoom`.
pub fn canvasX(x: i32, offset_x: f32, zoom: f32) i32 {
    const zoomed_x = @as(f32, @floatFromInt(x)) * zoom;
    return @as(i32, @intFromFloat(zoomed_x + offset_x));
}

/// Returns drawing position from world `y` given camera `offset_y` and `zoom`.
pub fn canvasY(y: i32, offset_y: f32, zoom: f32) i32 {
    const zoomed_y = @as(f32, @floatFromInt(y)) * zoom;
    return @as(i32, @intFromFloat(zoomed_y + offset_y));
}

/// Returns drawing scale given object `scale` and camera `zoom`.
pub fn canvasScale(scale: i32, zoom: f32) i32 {
    const scaled_value = zoom * @as(f32, @floatFromInt(scale));
    return @as(i32, @intFromFloat(scaled_value));
}

/// Sets canvas offset values to center on the player position.
pub fn canvasOnPlayer() void {
    const screen_width_f = @as(f32, @floatFromInt(rl.getScreenWidth()));
    const screen_height_f = @as(f32, @floatFromInt(rl.getScreenHeight()));
    main.canvas_offset_x = -(@as(f32, @floatFromInt(main.player.x)) * main.canvas_zoom) + (screen_width_f / 2);
    main.canvas_offset_y = -(@as(f32, @floatFromInt(main.player.y)) * main.canvas_zoom) + (screen_height_f / 2);
}

/// Calculates and returns the maximum zoom out possible while remaining within the given map dimensions.
pub fn maxCanvasSize(screen_width: i32, screen_height: i32, map_width: u16, map_height: u16) f32 {
    if (screen_width > screen_height) {
        return @as(f32, @floatFromInt(screen_width)) / @as(f32, @floatFromInt(map_width));
    } else {
        return @as(f32, @floatFromInt(screen_height)) / @as(f32, @floatFromInt(map_height));
    }
}

// Drawing
//----------------------------------------------------------------------------------

pub fn drawGuide(x: i32, y: i32, width: i32, height: i32, col: rl.Color) void {
    const semiTransparent = rl.Color{
        .r = col.r,
        .g = col.g,
        .b = col.b,
        .a = col.a / 3,
    };

    drawEntity(x, y, width, height, semiTransparent);
}

pub fn drawGuideFail(x: i32, y: i32, width: i32, height: i32, col: rl.Color) void {
    const semiTransparent = rl.Color{
        .r = col.r,
        .g = col.g,
        .b = col.b,
        .a = col.a / 9,
    };

    drawEntity(x, y, width, height, semiTransparent);
}

/// Uses raylib to draw rectangle scaled and positioned to canvas.
pub fn drawRect(x: i32, y: i32, width: i32, height: i32, col: rl.Color) void {
    rl.drawRectangle(canvasX(x, main.canvas_offset_x, main.canvas_zoom), canvasY(y, main.canvas_offset_y, main.canvas_zoom), canvasScale(width, main.canvas_zoom), canvasScale(height, main.canvas_zoom), col);
}

/// Draws rectangle centered on `x`,`y` coordinates, scaled and positioned to canvas.
pub fn drawEntity(x: i32, y: i32, width: i32, height: i32, col: rl.Color) void {
    rl.drawRectangle(canvasX(x - @divTrunc(width, 2), main.canvas_offset_x, main.canvas_zoom), canvasY(y - @divTrunc(height, 2), main.canvas_offset_y, main.canvas_zoom), canvasScale(width, main.canvas_zoom), canvasScale(height, main.canvas_zoom), col);
}

pub fn interpolateStep(last_x: u16, last_y: u16, new_x: u16, new_y: u16, timer: u16, interval: u16) [2]u16 {
    const steps_since_last_move = timer % interval;
    const interpolation_factor = steps_since_last_move / interval;

    // Interpolated position
    const interp_x = last_x + interpolation_factor * (new_x - last_x);
    const interp_y = last_y + interpolation_factor * (new_y - last_y);

    return [2]u16{ interp_x, interp_y };
}
