const rl = @import("raylib");
const std: type = @import("std");
const main = @import("main.zig");
const e = @import("entity.zig");
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
pub fn printGridEntities(grid: *e.Grid) void {
    var total_entities: usize = 0;
    var it = grid.cells.iterator();
    while (it.next()) |entry| {
        total_entities += entry.value_ptr.items.len;
    }
    const players = e.players.items.len;
    const structures = e.structures.items.len;
    const units = e.units.items.len;
    std.debug.print("Total entities on the grid: {} ({} players, {} structures, {} units).\n", .{ total_entities, players, structures, units });
    if (total_entities != players + structures + units) {
        std.log.err("DISCREPANCY DETECTED! Number of entities does not match the combined number of players, structures, and units.\n", .{});
    }
}

/// Prints the number of cells currently stored in the hashmap, corresponding to the
/// number of distinct cells that contain one or more entities.
pub fn printGridCells(grid: *e.Grid) void {
    std.debug.print("Currently active cells on the grid: {} (out of {} cells, {} rows, {} columns).\n", .{ grid.cells.count(), grid.rows * grid.columns, grid.rows, grid.columns });
}

pub fn perFrame(frequency: u64) bool {
    return @mod(main.frame_number, frequency) == 0;
}

pub fn scaleToTickRate(float: f32) f32 { // Delta time capped to tickrate
    return (float * (@max(@as(f32, @floatCast(main.TICK_DURATION)), rl.getFrameTime()))) * main.TICKRATE;
}

// Metaprogramming
//----------------------------------------------------------------------------------
const Predicate = fn (entity: *e.Entity) bool; // Function pointer to an entity

// Value types and conversions
//----------------------------------------------------------------------------------
pub const u8max: u8 = std.math.maxInt(u8); // 255
pub const i8max: i8 = std.math.maxInt(i8); // (-128 to) 127
pub const u16max: u16 = std.math.maxInt(u16); // 65535
pub const i16max: i16 = std.math.maxInt(i16); // (-32768 to) 32767
pub const f16max: f16 = std.math.floatMax(f16); // (−65504.0 to) 65504.0
pub const u32max: u32 = std.math.maxInt(u32); // 4294967295
pub const i32max: i32 = std.math.maxInt(i32); // (-2147483648 to) 2147483647
pub const f32max: f32 = std.math.floatMax(f32); // (-3.4028235e+38 to) 3.4028235e+38
pub const u64max: u64 = std.math.maxInt(u64); // 18446744073709551615
pub const i64max: i64 = std.math.maxInt(i64); // (-9223372036854775807 to) 9223372036854775807
pub const f64max: f64 = std.math.floatMax(f64); // (-1.7976931348623157e+308 to) 1.7976931348623157e+308

/// Casts `v` from the type `T1` to the type `T2`. Types must be numerical. Clamps the value to the range of `T2`.
pub fn as(comptime T1: type, v: T1, comptime T2: type) T2 {
    if ((@typeInfo(T1) != .Float and @typeInfo(T1) != .Int) or (@typeInfo(T2) != .Float and @typeInfo(T2) != .Int)) {
        std.debug.panic("Attempted to cast to/from a non-numerical type. Type of value: {}. Type of return: {}.", .{ T1, T2 });
    }
    // Delegate to the appropriate casting function based on which type T2 is
    switch (T2) {
        u8 => return asU8(T1, v),
        i8 => return asI8(T1, v),
        u16 => return asU16(T1, v),
        i16 => return asI16(T1, v),
        u32 => return asU32(T1, v),
        i32 => return asI32(T1, v),
        u64 => return asU64(T1, v),
        i64 => return asI64(T1, v),
        f16 => return asF16(T1, v),
        f32 => return asF32(T1, v),
        f64 => return asF64(T1, v),
        else => std.debug.panic("Unsupported target type: {}", .{T2}),
    }
}

/// Casts numerical value `v` to type `u8`. Clamps the value range of `T`.
pub fn asU8(comptime T: type, v: T) u8 {
    return @max(0, @min(if (@typeInfo(T) == .Float) @as(u8, @intFromFloat(v)) else @as(u8, @intCast(v)), u8max));
}

/// Casts numerical value `v` to type `i8`. Clamps the value range of `T`.
pub fn asI8(comptime T: type, v: T) i8 {
    return @max(-i8max - 1, @min(if (@typeInfo(T) == .Float) @as(i8, @intFromFloat(v)) else @as(i8, @intCast(v)), i8max));
}

/// Casts numerical value `v` to type `u16`. Clamps the value range of `T`.
pub fn asU16(comptime T: type, v: T) u16 {
    return @max(0, @min(if (@typeInfo(T) == .Float) @as(u16, @intFromFloat(v)) else @as(u16, @intCast(v)), u16max));
}

/// Casts numerical value `v` to type `i16`. Clamps the value range of `T`.
pub fn asI16(comptime T: type, v: T) i16 {
    return @max(-i16max - 1, @min(if (@typeInfo(T) == .Float) @as(i16, @intFromFloat(v)) else @as(i16, @intCast(v)), i16max));
}

/// Casts numerical value `v` to type `f16`. Clamps the value range of `T`.
pub fn asF16(comptime T: type, v: T) f16 {
    return @max(-f16max, @min(if (@typeInfo(T) == .Float) @as(f16, @floatCast(v)) else @as(f16, @floatFromInt(v)), f16max));
}

/// Casts numerical value `v` to type `u32`. Clamps the value range of `T`.
pub fn asU32(comptime T: type, v: T) u32 {
    return @max(0, @min(if (@typeInfo(T) == .Float) @as(u32, @intFromFloat(v)) else @as(u32, @intCast(v)), u32max));
}

/// Casts numerical value `v` to type `i32`. Clamps the value range of `T`.
pub fn asI32(comptime T: type, v: T) i32 {
    return @max(-i32max - 1, @min(if (@typeInfo(T) == .Float) @as(i32, @intFromFloat(v)) else @as(i32, @intCast(v)), i32max));
}

/// Casts numerical value `v` to type `f32`. Clamps the value range of `T`.
pub fn asF32(comptime T: type, v: T) f32 {
    return @max(-f32max, @min(if (@typeInfo(T) == .Float) @as(f32, @floatCast(v)) else @as(f32, @floatFromInt(v)), f32max));
}

/// Casts numerical value `v` to type `u64`.
pub fn asU64(comptime T: type, v: T) u64 {
    return @max(0, @min(if (@typeInfo(T) == .Float) @as(u64, @intFromFloat(v)) else @as(u64, @intCast(v)), u64max));
}

/// Casts numerical value `v` to type `i64`.
pub fn asI64(comptime T: type, v: T) i64 {
    return @max(-i64max - 1, @min(if (@typeInfo(T) == .Float) @as(i64, @intFromFloat(v)) else @as(i64, @intCast(v)), i64max));
}

/// Casts numerical value `v` to type `f64`.
pub fn asF64(comptime T: type, v: T) f64 {
    return @max(-f64max, @min(if (@typeInfo(T) == .Float) @as(f64, @floatCast(v)) else @as(f64, @floatFromInt(v)), f64max));
}

// Clamping value ranges
pub fn u8Clamp(comptime T: type, v: T) T {
    return @max(0, @min(v, u8max));
}

pub fn i8Clamp(comptime T: type, v: T) T {
    return @max(std.math.minInt(i8), @min(v, i8max));
}

pub fn u16Clamp(comptime T: type, v: T) T {
    return @max(@as(T, 0), @min(v, if (@typeInfo(T) == .Int) @as(T, if (u16max <= std.math.maxInt(T)) u16max else @as(u16, std.math.maxInt(T))) else @as(T, @floatFromInt(u16max))));
}

pub fn i16Clamp(comptime T: type, v: T) T {
    return @max(std.math.minInt(i16), @min(v, i16max));
}

pub fn f16Clamp(comptime T: type, v: T) T {
    const f16_v = if (@typeInfo(T) == .Float) v else @as(f16, @floatFromInt(v));
    const clamped = @max(-f16max, @min(f16_v, f16max));
    return if (@typeInfo(T) == .Float) clamped else @as(T, @intFromFloat(clamped));
}

pub fn u32Clamp(comptime T: type, v: T) T {
    return @max(@as(T, 0), @min(v, if (@typeInfo(T) == .Int) @as(T, if (u32max <= std.math.maxInt(T)) u32max else @as(u32, std.math.maxInt(T))) else @as(T, @floatFromInt(u32max))));
}

pub fn i32Clamp(comptime T: type, v: T) T {
    return @max(std.math.minInt(i32), @min(v, i32max));
}

pub fn f32Clamp(comptime T: type, v: T) T {
    const f32_v = if (@typeInfo(T) == .Float) v else @as(f32, @floatFromInt(v));
    const clamped = @max(-f32max, @min(f32_v, f32max));
    return if (@typeInfo(T) == .Float) clamped else @as(T, @intFromFloat(clamped));
}

pub fn u64Clamp(comptime T: type, v: T) T {
    return @max(0, @min(v, @as(T, u64max)));
}

pub fn i64Clamp(comptime T: type, v: T) T {
    return @max(std.math.minInt(i64), @min(v, @as(T, i64max)));
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

    pub fn inputFromAction(self: *Key, action: Key.Action) u32 {
        const inputValue = self.bindings.get(action);
        if (inputValue) |input| {
            return @intFromEnum(input);
        } else {
            return 0;
        }
    }
};

pub fn mouseMoved(vector: rl.Vector2) bool {
    return vector.x < -0.5 or vector.x > 0.5 or vector.y < -0.5 or vector.y > 0.5;
}

// RNG
//----------------------------------------------------------------------------------
pub fn rngInit() void { // Must be deterministic/objective, so to some extent a placeholder
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
    const len = u16Clamp(usize, array.len);
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
    const clampedResult = @max(@as(T, 0), @min(@as(T, u16max), resultFloat));
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

    /// Moves the point by a horizontal and/or vertical offset. Clamped to map limits.
    pub fn shift(self: *Point, x_shift: i32, y_shift: i32) void {
        const cur_x = @as(i32, @intCast(self.x));
        const cur_y = @as(i32, @intCast(self.y));
        const shifted_x = @as(u16, @intCast(u16Clamp(i32, cur_x + x_shift)));
        const shifted_y = @as(u16, @intCast(u16Clamp(i32, cur_y + y_shift)));
        self.x = mapClampX(shifted_x, 1);
        self.y = mapClampY(shifted_y, 1);
    }

    /// Returns the Grid columns and rows in which the point is located.
    pub fn getCellCoordinates(self: *Point) [2]usize {
        return [2]usize{ Grid.x(self.x), Grid.y(self.y) };
    }

    /// Returns the Subcell in which the point is located.
    pub fn getSubcell(self: *Point) Subcell {
        return Subcell.at(self.x, self.y);
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

/// Returns 2,4,6,8 depending on the dominant vector axis and direction.
pub fn vectorToDir(vector: rl.Vector2) u8 {
    if (@abs(vector.x) > @abs(vector.y)) {
        if (vector.x > 0) return 6;
        return 4;
    } else {
        if (vector.y > 0) return 2;
        return 8;
    }
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

/// Takes an `x`,`y` origin coordinate and a `dx`,`dy` displacement. Returns the `Point` after translation.
pub fn deltaPoint(x: u16, y: u16, dx: f32, dy: f32) Point {
    const end_x: f32 = @max(0, @as(f32, @floatFromInt(x)) + dx);
    const end_y: f32 = @max(0, @as(f32, @floatFromInt(y)) + dy);
    return Point.at(@as(u16, @intFromFloat(@round(end_x))), @as(u16, @intFromFloat(@round(end_y)))); // Ah, sweet zig syntax
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

pub fn interpolateStep(last_x: u16, last_y: u16, x: i32, y: i32, frame: i16, interval: comptime_int) [2]i32 {
    const steps_since_last_move = interval - @rem(frame, interval); // Number of steps since the last move
    const interpolation_factor = @as(f32, @floatFromInt(steps_since_last_move)) / @as(f32, @floatFromInt(interval));

    const interp_x = @as(i32, last_x) + @as(i32, @intFromFloat(interpolation_factor * @as(f32, @floatFromInt(x - @as(i32, last_x)))));
    const interp_y = @as(i32, last_y) + @as(i32, @intFromFloat(interpolation_factor * @as(f32, @floatFromInt(y - @as(i32, last_y)))));

    return [2]i32{ interp_x, interp_y };
}

/// Squares the `x`,`y` distance between `a` and `b`. Allows for accurate distance comparisons, but does not represent the actual distance.
pub fn distanceSquared(a: Point, b: Point) u32 {
    const dx = @as(i32, a.x) - @as(i32, b.x);
    const dy = @as(i32, a.y) - @as(i32, b.y);
    return @as(u32, @intCast(dx * dx)) + @as(u32, @intCast(dy * dy));
}

/// Compares `a` and `b` coordinates and checks whether both differences are lower than `distance`.
pub fn withinSquare(a: Point, b: Point, distance: f16) bool {
    const dx = asF32(u16, a.x) - asF32(u16, b.x);
    const dy = asF32(u16, a.y) - asF32(u16, b.y);
    return dx < distance and dy < distance;
}

/// Compares `a` and `b` coordinates. Returns `max` if outside `threshold` square, returns remaining distance (clamping < 0.1) if within. Useful for adjusting speed when arriving at target.
pub fn adjustToDistance(a: Point, b: Point, threshold: f16, max: f16) f16 {
    const dx = asF32(u16, a.x) - asF32(u16, b.x);
    const dy = asF32(u16, a.y) - asF32(u16, b.y);
    const dist_squared = dx * dx + dy * dy;
    const dist_threshold_squared = threshold * threshold;
    if (dist_squared > dist_threshold_squared) {
        return max;
    } else {
        const sqrt = @as(f16, @floatCast(fastSqrt(dist_squared)));
        return if (sqrt < 0.1) 0.0 else sqrt;
    }
}

/// Takes the square root of the distance squared between `a` and `b`. Use for exact representation, prefer `distanceSquared` for comparisons.
pub fn euclideanDistance(a: Point, b: Point) f32 {
    const dist_squared = distanceSquared(a, b);
    return @sqrt(@as(f32, dist_squared));
}

/// Squares the `x`,`y` distance between `e1` and `e2`. Allows for accurate distance comparisons, but does not represent the actual distance.
pub fn entityDistance(e1: *e.Entity, e2: *e.Entity) u32 {
    const a = Point.at(e1.x(), e1.y());
    const b = Point.at(e2.x(), e2.y());
    return distanceSquared(a, b);
}

/// Fast inverse square root (Quake III algorithm)
pub fn qRsqrt(number: f32) f32 {
    var i: i32 = @as(i32, @bitCast(number));
    const x2: f32 = number * 0.5;
    var y: f32 = number;
    const threehalfs: f32 = 1.5;

    i = 0x5f3759df - (i >> 1);
    y = @as(f32, @bitCast(i));
    y = y * (threehalfs - (x2 * y * y));

    return y;
}

/// Computes the square root using the Quake III inverse square root algorithm.
pub fn fastSqrt(number: f32) f32 {
    return 1.0 / qRsqrt(number);
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

    /// Converts a world coordinate `x` to the grid column it falls into.
    pub fn x(world_x: u16) usize {
        return @divFloor(world_x, cell_size);
    }

    /// Converts a world coordinate `y` to the grid row it falls into.
    pub fn y(world_y: u16) usize {
        return @divFloor(world_y, cell_size);
    }

    /// Converts world coordinates to the center position of the containing cell.
    pub fn cellCenter(world_x: u16, world_y: u16) Point {
        const node = cellNode(world_x, world_y);
        return Point.at(node.x + cell_half, node.y + cell_half);
    }

    /// Converts world coordinates to the top left node position of the containing cell.
    pub fn cellNode(world_x: u16, world_y: u16) Point {
        return Point.at(@as(u16, @intCast(x(world_x))) * cell_size, @as(u16, @intCast(y(world_y))) * cell_size);
    }

    /// Takes world `x`,`y` and returns the world `x`,`y` of the closest cell node. Not always the node of the containing cell.
    pub fn closestNode(world_x: u16, world_y: u16) Point {
        const closest_x = @divTrunc((world_x + cell_half), cell_size) * cell_size;
        const closest_y = @divTrunc((world_y + cell_half), cell_size) * cell_size;
        return Point.at(closest_x, closest_y);
    }

    pub fn closestNodeOffset(world_x: u16, world_y: u16, dir: u8, width: u16, height: u16) Point {
        const delta = if (isHorz(dir)) width else height;
        const offset_xy = dirOffset(world_x, world_y, dir, delta);
        return closestNode(offset_xy[0], offset_xy[1]);
    }

    pub fn entityCount(self: *e.Grid) usize {
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
pub const Subcell = struct {
    node: Point,

    pub const size = Grid.cell_size / 10;

    /// Returns the subcell corresponding to the `x`,`y` coordinates.
    pub fn at(x: u16, y: u16) Subcell {
        return Subcell{
            .node = nodePoint(x, y),
        };
    }

    pub fn nodeCoordinates(self: Subcell) [2]u16 {
        return [2]u16{ self.node.x, self.node.y };
    }

    pub fn center(self: Subcell) [2]u16 {
        return [2]u16{ self.node.x + (size / 2), self.node.y + (size / 2) };
    }

    /// Returns the top left `x`,`y` of the closest 10th part of a cell to `x`,`y`.
    pub fn nodeFromCoordinates(x: u16, y: u16) [2]u16 {
        const closest_x = @divTrunc(x, Subcell.size) * Subcell.size;
        const closest_y = @divTrunc(y, Subcell.size) * Subcell.size;
        return [2]u16{ closest_x, closest_y };
    }

    pub fn pointNode(point: Point) [2]u16 {
        return nodeFromCoordinates(point.x, point.y)[0];
    }

    pub fn nodePoint(x: u16, y: u16) Point {
        const xy = nodeFromCoordinates(x, y);
        return Point.at(xy[0], xy[1]);
    }

    /// Aligns the top left of the rectangle centered on `x`,`y` with the top left of its closest subcell.
    pub fn snapToNode(x: u16, y: u16, width: u16, height: u16) [2]u16 {
        const snapped_center = Subcell.nodeFromCoordinates(x - width / 2, y - height / 2);
        return [2]u16{ snapped_center[0] + width / 2, snapped_center[1] + height / 2 };
    }

    /// Takes a world `x` coordinate and converts it to the corresponding subcell column number.
    pub fn subGridX(x: u16) usize {
        return @divTrunc(x, Subcell.size);
    }

    /// Takes a world `x` coordinate and converts it to the corresponding subcell row number.
    pub fn subGridY(y: u16) usize {
        return @divTrunc(y, Subcell.size);
    }
};

pub const waypoint: type = struct {
    /// Takes the grid column/row of a given cell and returns the 4 waypoints along its edges. Order: left mid, top mid, right mid, bottom mid.
    pub fn cellSides(grid_x: usize, grid_y: usize) [4]Point {
        const node_x = @as(u16, @intCast(grid_x * Grid.cell_size));
        const node_y = @as(u16, @intCast(grid_y * Grid.cell_size));
        return [4]Point{
            Point.at(node_x, node_y + Grid.cell_half), // left mid
            Point.at(node_x + Grid.cell_half, node_y), // top mid
            Point.at(node_x + Grid.cell_size, node_y + Grid.cell_half), // Right mid
            Point.at(node_x + Grid.cell_half, node_y + Grid.cell_size), // Bottom mid
        };
    }
    /// Takes world `x`,`y` cordinates and returns the closest waypoint.
    pub fn closest(x: u16, y: u16) Point {
        const waypoints = cellSides(Grid.x(x), Grid.y(y));
        const mid_x_diff: i32 = @as(i32, x) - (waypoints[1].x + Grid.cell_half);
        const mid_y_diff: i32 = @as(i32, y) - (waypoints[0].y) + Grid.cell_half;

        if (mid_x_diff < 0) { // On left side of cell
            if (@abs(mid_x_diff) > @abs(mid_y_diff)) return waypoints[0];
            return if (mid_y_diff < 0) waypoints[1] else waypoints[3];
        } else { // On right side of cell
            if (@abs(mid_x_diff) > @abs(mid_y_diff)) return waypoints[2];
            return if (mid_y_diff < 0) waypoints[1] else waypoints[3];
        }
    }

    pub fn closestTowards(current: Point, target: Point, total_distance: u32, previous_step: Point) Point {
        const current_cell_center = Grid.cellCenter(current.x, current.y);
        const closest_grid_x = Grid.x(current_cell_center.x);
        const closest_grid_y = Grid.y(current_cell_center.y);
        const waypoints = cellSides(closest_grid_x, closest_grid_y);

        // Overall vector from current to target
        const dx = @as(i32, target.x) - @as(i32, current.x);
        const dy = @as(i32, target.y) - @as(i32, current.y);

        var best_waypoint: ?Point = null;
        var best_distance = total_distance;
        var best_biased_alignment: f32 = 0;

        // Bias factor to discourage oscillation
        const bias_factor = 0.5; // The lower, the stronger bias away from previous_step

        for (waypoints) |wp| {
            // Vector from current to the waypoint under consideration
            const wp_dx = @as(i32, wp.x) - @as(i32, current.x);
            const wp_dy = @as(i32, wp.y) - @as(i32, current.y);

            // Dot product, degree of alignment with the overall vector
            const alignment: f32 = asF32(i32, dx * wp_dx + dy * wp_dy);

            // Vector from previous step to current waypoint
            const prev_dx = @as(i32, wp.x) - @as(i32, previous_step.x);
            const prev_dy = @as(i32, wp.y) - @as(i32, previous_step.y);
            const prev_alignment = dx * prev_dx + dy * prev_dy;

            // Apply bias if waypoint is in the direction of the previous step
            const biased_alignment = if (prev_alignment > 0) alignment * bias_factor else alignment;

            if (biased_alignment >= 0) {
                const wp_to_target = distanceSquared(wp, target);
                const current_to_wp = distanceSquared(current, wp);
                const new_distance = current_to_wp + wp_to_target;

                // Compare both distance and biased alignment
                if (best_waypoint == null or (new_distance < best_distance) or (new_distance == best_distance and biased_alignment > best_biased_alignment)) {
                    best_distance = new_distance;
                    best_biased_alignment = biased_alignment;
                    best_waypoint = wp;
                } else if (new_distance == best_distance and biased_alignment == best_biased_alignment) {
                    // Tie-breaking using lexicographical ordering if distance and alignment are the same
                    if (wp.x < best_waypoint.?.x or (wp.x == best_waypoint.?.x and wp.y < best_waypoint.?.y)) {
                        best_waypoint = wp;
                    }
                }
            }
        }

        // Return the waypoint closest to the target, otherwise center of current cell
        if (best_waypoint) |point| {
            return point;
        } else {
            std.debug.print("No best waypoint found.\n", .{});
            return Point.at(randomU16(main.map_width), randomU16(main.map_height));
        }
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
    const clamped_x = @max(half_width, @min(x, @as(i32, @intCast(main.map_width)) - half_width));
    return @as(u16, @intCast(clamped_x));
}

pub fn mapClampY(y: i16, height: u16) u16 {
    const half_height = @as(i16, @intCast(@divTrunc(height, 2)));
    const clamped_y = @max(half_height, @min(y, @as(i32, @intCast(main.map_height)) - half_height));
    return @as(u16, @intCast(clamped_y));
}

/// Searches for `Entity` that satisfies the `condition`, starting with the section at the `origin` point.
pub fn concentricSearch(grid: *e.Grid, origin: Point, condition: Predicate) ?*e.Entity {
    const origin_col = Grid.x(origin.x);
    const origin_row = Grid.y(origin.y);
    var closest_entity: ?*e.Entity = null;
    var closest_distance = std.math.inf(f32);

    var radius: i32 = 0;
    while (true) {
        var found_any_entity = false;

        for (-radius..radius) |d| {
            // Check the four sides of the square at this radius
            const offsets = [4]Point{
                Point{ .x = origin_col + d, .y = origin_row - radius }, // Top
                Point{ .x = origin_col + d, .y = origin_row + radius }, // Bottom
                Point{ .x = origin_col - radius, .y = origin_row + d }, // Left
                Point{ .x = origin_col + radius, .y = origin_row + d }, // Right
            };

            for (&offsets) |offset| {
                if (offset.x >= 0 and offset.y >= 0 and offset.x < grid.cols and offset.y < grid.rows) {
                    const entities: ?*std.ArrayList(*e.Entity) = grid.sectionEntities(offset.x, offset.y);
                    if (entities != null) {
                        found_any_entity = true;
                        for (entities.?.items) |entity| {
                            if (condition(entity)) {
                                const distance = distanceSquared(origin, Point.at(entity.x(), entity.y()));
                                if (distance < closest_distance) {
                                    closest_entity = entity;
                                    closest_distance = distance;
                                }
                            }
                        }
                    }
                }
            }
        }
        if (closest_entity != null) return closest_entity; // If found entity in this radius, return the closest one
        if (!found_any_entity) break; // If no entities were found overall, stop searching

        radius += 2; // Increases radius by 2 since each section covers 3x3 cells, thus overlaps by one on each side
    }
    return null; // If no entity was found after the entire search
}

// AI
//----------------------------------------------------------------------------------

// Canvas
//----------------------------------------------------------------------------------
/// Returns the drawn position of world-coordinate `x` given camera `offset_x` and `zoom`.
pub fn canvasX(x: i32, offset_x: f32, zoom: f32) i32 {
    const zoomed_x = @as(f32, @floatFromInt(x)) * zoom;
    return @as(i32, @intFromFloat(zoomed_x + offset_x));
}

/// Returns the drawn position of world-coordinate `y` given camera `offset_y` and `zoom`.
pub fn canvasY(y: i32, offset_y: f32, zoom: f32) i32 {
    const zoomed_y = @as(f32, @floatFromInt(y)) * zoom;
    return @as(i32, @intFromFloat(zoomed_y + offset_y));
}

/// Returns drawing scale given object `scale` and camera `zoom`.
pub fn canvasScale(scale: i32, zoom: f32) i32 {
    const scaled_value = zoom * @as(f32, @floatFromInt(scale));
    return @as(i32, @intFromFloat(scaled_value));
}

/// Returns the drawn screen-coordinates of world-coordinates `x`,`y` given current camera.
pub fn mapToCanvas(x: i32, y: i32) [2]i32 {
    return [2]i32{ canvasX(x, main.canvas_offset_x, main.canvas_zoom), canvasY(y, main.canvas_offset_y, main.canvas_zoom) };
}

/// Sets canvas offset values to center on the player position.
pub fn canvasOnPlayer() void {
    const screen_width_f = @as(f32, @floatFromInt(rl.getScreenWidth()));
    const screen_height_f = @as(f32, @floatFromInt(rl.getScreenHeight()));
    main.canvas_offset_x = -(@as(f32, @floatFromInt(main.player.x)) * main.canvas_zoom) + (screen_width_f / 2);
    main.canvas_offset_y = -(@as(f32, @floatFromInt(main.player.y)) * main.canvas_zoom) + (screen_height_f / 2);
}

/// Sets canvas offset values to center on the position of `entity`.
pub fn canvasOnEntity(entity: *e.Entity) void {
    const screen_width_f = @as(f32, @floatFromInt(rl.getScreenWidth()));
    const screen_height_f = @as(f32, @floatFromInt(rl.getScreenHeight()));
    if (entity.kind == e.Kind.Unit) { // If entity is unit, movement is interpolated
        const unit = entity.ref.Unit;
        const xy = interpolateStep(unit.last_step.x, unit.last_step.y, unit.x, unit.y, unit.life, main.MOVEMENT_DIVISIONS);
        main.canvas_offset_x = -(@as(f32, @floatFromInt(xy[0])) * main.canvas_zoom) + (screen_width_f / 2);
        main.canvas_offset_y = -(@as(f32, @floatFromInt(xy[1])) * main.canvas_zoom) + (screen_height_f / 2);
    } else {
        main.canvas_offset_x = -(@as(f32, @floatFromInt(entity.x())) * main.canvas_zoom) + (screen_width_f / 2);
        main.canvas_offset_y = -(@as(f32, @floatFromInt(entity.y())) * main.canvas_zoom) + (screen_height_f / 2);
    }
}

/// Calculates and returns the maximum zoom out possible while remaining within the given map dimensions.
pub fn maxCanvasSize(screen_width: i32, screen_height: i32, map_width: u16, map_height: u16) f32 {
    if (screen_width > screen_height) {
        return @as(f32, @floatFromInt(screen_width)) / @as(f32, @floatFromInt(map_width));
    } else {
        return @as(f32, @floatFromInt(screen_height)) / @as(f32, @floatFromInt(map_height));
    }
}

/// Returns the `x`,`y` map coordinates currently corresponding to what's drawn to the canvas at `screen_position` (e.g. mouse) in the viewport.
pub fn screenToMap(screen_position: rl.Vector2) [2]u16 {
    const x = u16Clamp(f32, screen_position.x - main.canvas_offset_x);
    const y = u16Clamp(f32, screen_position.y - main.canvas_offset_y);
    const zoomed_x = @as(u16, @intFromFloat(x / main.canvas_zoom));
    const zoomed_y = @as(u16, @intFromFloat(y / main.canvas_zoom));
    return [2]u16{ zoomed_x, zoomed_y };
}

/// Returns vector distance from `screen_position` to the current canvas position of the local player.
pub fn screenToPlayer(screen_position: rl.Vector2) rl.Vector2 {
    const player_x = canvasX(main.player.x - @divTrunc(main.player.width, 2), main.canvas_offset_x, main.canvas_zoom);
    const player_y = canvasY(main.player.y - @divTrunc(main.player.height, 2), main.canvas_offset_y, main.canvas_zoom);
    return rl.Vector2.init(screen_position.x - @as(f32, @floatFromInt(player_x)), screen_position.y - @as(f32, @floatFromInt(player_y)));
}

/// Returns the subcell corresponding to `screen_position` given the current zoom and canvas offset.
pub fn screenToSubcell(screen_position: rl.Vector2) Subcell {
    const map_coords = screenToMap(screen_position);
    return Subcell.at(map_coords[0], map_coords[1]);
}

// Drawing
//----------------------------------------------------------------------------------
pub fn opacity(color: rl.Color, alpha: f32) rl.Color {
    return rl.Color{
        .r = color.r,
        .g = color.g,
        .b = color.b,
        .a = asU8(f32, asF32(u8, color.a) * alpha),
    };
}

pub fn drawGuide(x: i32, y: i32, width: i32, height: i32, col: rl.Color) void {
    drawEntity(x, y, width, height, opacity(col, 0.4));
}

pub fn drawGuideFail(x: i32, y: i32, width: i32, height: i32, col: rl.Color) void {
    drawEntity(x, y, width, height, opacity(col, 0.125));
}

/// Uses raylib to draw rectangle scaled and positioned to canvas.
pub fn drawRect(x: i32, y: i32, width: i32, height: i32, col: rl.Color) void {
    rl.drawRectangle(canvasX(x, main.canvas_offset_x, main.canvas_zoom), canvasY(y, main.canvas_offset_y, main.canvas_zoom), canvasScale(width, main.canvas_zoom), canvasScale(height, main.canvas_zoom), col);
}

/// Draws rectangle centered on `x`,`y` coordinates, scaled and positioned to canvas.
pub fn drawEntity(x: i32, y: i32, width: i32, height: i32, col: rl.Color) void {
    rl.drawRectangle(canvasX(x - @divTrunc(width, 2), main.canvas_offset_x, main.canvas_zoom), canvasY(y - @divTrunc(height, 2), main.canvas_offset_y, main.canvas_zoom), canvasScale(width, main.canvas_zoom), canvasScale(height, main.canvas_zoom), col);
}

/// Draws rectangle centered on `x`,`y` coordinates, scaled and positioned to canvas, interpolated by `frame` since `last_step`. The full interpolation interval is determined by `MOVEMENT_DIVISIONS`.
pub fn drawEntityInterpolated(x: i32, y: i32, width: i32, height: i32, col: rl.Color, last_step: Point, frame: i16) void {
    const interp_xy = interpolateStep(last_step.x, last_step.y, x, y, frame, main.MOVEMENT_DIVISIONS);
    drawEntity(interp_xy[0], interp_xy[1], width, height, col);
}

/// Draws rectangle and build radius centered on `x`,`y` coordinates, scaled and positioned to canvas.
pub fn drawPlayer(x: i32, y: i32, width: i32, height: i32, col: rl.Color) void {
    drawEntity(x, y, width, height, col);
    rl.drawCircleLines(canvasX(x, main.canvas_offset_x, main.canvas_zoom), canvasY(y, main.canvas_offset_y, main.canvas_zoom), Grid.cell_half * main.canvas_zoom, opacity(col, 0.25));
}
