const rl = @import("raylib");
const std: type = @import("std");
const main = @import("main.zig");
const e = @import("entity.zig");
const math = @import("std").math;

// Debug/analysis
//----------------------------------------------------------------------------------

/// Sets `main.profile_timer[timer]` and prints a message. Stop the timer with `utils.endTimer()`.
pub fn startTimer(timer: usize, comptime startMsg: []const u8) void {
    const msg = if (startMsg.len > 0 and startMsg[startMsg.len - 1] != '\n') startMsg ++ " " else startMsg;
    std.debug.print(msg, .{});
    main.Config.profile_timer[timer] = rl.getTime();
}

/// Stops `main.profile_timer[timer]` and prints a message. Must write `{}` to add the result argument.
pub fn endTimer(timer: usize, comptime endMsg: []const u8) void {
    const result = rl.getTime() - main.Config.profile_timer[timer];
    std.debug.print(endMsg ++ " \n", .{result});
    main.Config.profile_timer[timer] = 0;
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
    return @mod(main.Camera.frame_number, frequency) == 0;
}

/// Limits per-frame value down to tickrate-relative value.
pub fn limitToTickRate(float: f32) f32 { // Delta time capped to tickrate
    return (float * (@max(@as(f32, @floatCast(main.Config.TICK_DURATION)), rl.getFrameTime()))) * main.Config.TICKRATE;
}

/// Scales tickrate-relative value up to per-frame value.
pub fn scaleToFPS(float: f32) f32 {
    return float * (main.Config.TICKRATE / (1.0 / rl.getFrameTime()));
}

/// Both scales float up to tickrate-relative value, and limits value to tickrate-relative value.
/// At 30 FPS, frameAdjusted(100) returns 400. At 60 FPS, frameAdjusted(100) returns 100. At 120 FPS, frameAdjusted(100) returns 50. At 1000 FPS, frameAdjusted(100) returns 6.
pub fn frameAdjusted(float: f32) f32 {
    return scaleToFPS(limitToTickRate(float));
}

// Metaprogramming
//----------------------------------------------------------------------------------
pub const Predicate = fn (entity: *e.Entity) bool; // Function pointer to an entity

pub const Relation = fn (self: *e.Entity, other: *e.Entity) bool; // Function pointer to entity, entity

pub fn isUnit(entity: *e.Entity) bool {
    return entity.kind == e.Kind.Unit;
}

pub fn isStructure(entity: *e.Entity) bool {
    return entity.kind == e.Kind.Structure;
}

pub fn isPlayer(entity: *e.Entity) bool {
    return entity.kind == e.Kind.Player;
}

pub fn isInRange(e1: *e.Entity, e2: *e.Entity, max_range: f32) bool {
    return entityDistance(e1, e2) <= max_range;
}

pub fn isEntityUnitInRange(self_entity: *e.Entity, target_entity: *e.Entity, maxRange: f32) bool {
    return isUnit(target_entity) and isInRange(self_entity, target_entity, maxRange);
}

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
    return @as(u16, @intFromFloat(seconds * main.Config.TICKRATE));
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

// World RNG
//----------------------------------------------------------------------------------
pub fn rngInit(seed: u64) void { // Initialized as map id + map width + map height
    main.World.rng = std.Random.DefaultPrng.init(seed);
}

pub fn randomU16(max: u16) u16 {
    const random_value = main.World.rng.next() % @as(u64, @intCast(max + 1));
    return @as(u16, @truncate(random_value));
}

pub fn randomI16(max: u16) i16 {
    const random_value = main.World.rng.next() % @as(u64, @intCast(max + 1));
    return @as(i16, @intCast(random_value));
}

pub fn randomI32(max: u16) i32 {
    const random_value = main.World.rng.next() % @as(u64, @intCast(max + 1));
    return @as(i32, @intCast(random_value));
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
pub const Vector = struct {
    x: f32,
    y: f32,

    pub fn add(self: Vector, other: Vector) Vector {
        return Vector{
            .x = self.x + other.x,
            .y = self.y + other.y,
        };
    }

    pub fn subtract(self: Vector, other: Vector) Vector {
        return Vector{
            .x = self.x - other.x,
            .y = self.y - other.y,
        };
    }

    pub fn length(self: Vector) f32 {
        return std.math.sqrt(self.x * self.x + self.y * self.y);
    }

    pub fn normalize(self: Vector) Vector {
        const len = self.length();
        if (len == 0.0) return Vector{ .x = 0.0, .y = 0.0 };
        return Vector{
            .x = self.x / len,
            .y = self.y / len,
        };
    }

    pub fn scale(self: Vector, factor: f32) Vector {
        return Vector{
            .x = self.x * factor,
            .y = self.y * factor,
        };
    }

    pub fn shift(self: Vector, x_delta: f32, y_delta: f32) Vector {
        return Vector{ .x = self.x + x_delta, .y = self.y + y_delta };
    }

    pub fn toPoint(self: Vector) Point {
        return Point{ mapClampX(asI16(f32, self.x), 1), mapClampY(asI16(f32, self.y), 1) };
    }

    pub fn fromPoint(point: Point) Vector {
        return Vector{ .x = asF32(u16, point.x), .y = asF32(u16, point.y) };
    }

    pub fn toCoords(vector: Vector) [2]u16 {
        return [2]u16{ mapClampX(asI16(f32, vector.x), 1), mapClampY(asI16(f32, vector.y), 1) };
    }

    pub fn fromCoords(x: u16, y: u16) Vector {
        return Vector{ .x = asF32(u16, x), .y = asF32(u16, y) };
    }

    pub fn toIntegers(vector: Vector) [2]i32 {
        return [2]i32{ asI32(f32, vector.x), asI32(f32, vector.y) };
    }

    pub fn fromIntegers(x: i32, y: i32) Vector {
        return Vector{ .x = asF32(i32, x), .y = asF32(i32, y) };
    }

    pub fn toFloats(vector: Vector) [2]f32 {
        return [2]f32{ vector.x, vector.y };
    }

    pub fn fromFloats(x: f32, y: f32) Vector {
        return Vector{ .x = x, .y = y };
    }

    pub fn toScreen(self: Vector) Vector {
        return fromIntegers(canvasX(asI32(f32, self.x), main.Camera.canvas_offset_x, main.Camera.canvas_zoom), canvasY(asI32(f32, self.y), main.Camera.canvas_offset_y, main.Camera.canvas_zoom));
    }

    pub fn fromScreen(screen_vector: Vector) Vector {
        const map_xy = screenToMap(toRaylib(screen_vector));
        return fromCoords(map_xy[0], map_xy[1]);
    }

    pub fn toRaylib(vector: Vector) rl.Vector2 {
        return rl.Vector2.init(vector.x, vector.y);
    }

    pub fn fromRaylib(rl_vector: rl.Vector2) Vector {
        return fromCoords(rl_vector.x, rl_vector.y);
    }

    pub fn mapOffsetX(self: Vector, x_value: u16) u16 {
        const float = mapClamp(f32, asF32(u16, x_value) + self.x, 1, 0);
        return asU16(f32, float);
    }

    pub fn mapOffsetY(self: Vector, y_value: u16) u16 {
        const float = mapClamp(f32, asF32(u16, y_value) + self.y, 1, 1);
        return asU16(f32, float);
    }

    pub fn angle(self: Vector) f32 {
        return deltaToAngle(asI32(f32, self.x), asI32(f32, self.y));
    }
};

pub const Point = struct {
    x: u16,
    y: u16,

    pub fn at(x: u16, y: u16) Point {
        return Point{
            .x = x,
            .y = y,
        };
    }

    pub fn atEntity(entity: *e.Entity) Point {
        return Point{
            .x = entity.x(),
            .y = entity.y(),
        };
    }

    pub fn equals(self: Point, other: Point) bool {
        return self.x == other.x and self.y == other.y;
    }

    pub fn toVector(self: *Point) Vector {
        return Vector{ .x = asF32(u16, self.x), .y = asF32(u16, self.y) };
    }

    pub fn fromVector(vector: Vector) Point {
        return Point{ asU16(f32, vector.x), asU16(f32, vector.y) };
    }

    pub fn fromIntegers(x: i32, y: i32) Point {
        return Point.at(mapClampX(asU16(i32, @max(0, x)), 1), mapClampY(asU16(i32, @max(0, y)), 1));
    }

    pub fn toIntegers(point: Point) [2]i32 {
        return [2]i32{ asI32(u16, point.x), asI32(u16, point.y) };
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

    pub fn getCircumference(self: Point, radius: u8) Circle {
        return Circle{
            .center = self,
            .radius = radius,
        };
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

pub const Circle = struct {
    center: Point,
    radius: u16,

    pub fn at(center: Point, radius: u16) Circle {
        return Circle{
            .center = center,
            .radius = radius,
        };
    }

    pub fn atCoords(x: u16, y: u16, radius: u16) Circle {
        return Circle{
            .center = Point.at(x, y),
            .radius = radius,
        };
    }

    pub fn atIntegers(x: i32, y: i32, radius: u16) Circle {
        return Circle{
            .center = Point.fromIntegers(x, y),
            .radius = radius,
        };
    }

    pub fn contains(self: Circle, point: Point) bool {
        return distanceSquared(self.center, point) <= (self.radius * self.radius);
    }

    /// Returns a circle centered on a rectangle whose radius represents the average distance from the rectangle's center to its edges.
    pub fn atRect(center: Point, width: u16, height: u16) Circle {
        return Circle{
            .center = center,
            .radius = if (width > u16max - height) u16max else (width + height) / 4,
        };
    }

    /// Returns a circle centered on `x`,`y` whose diameter equals the rectangle diagonal.
    pub fn encompass(x: u16, y: u16, width: u16, height: u16) Circle {
        const width_sq = if (width > u16max / width) u16max else width * width;
        const height_sq = if (height > u16max / height) u16max else height * height;
        const sum_squares = if (width_sq > u16max - height_sq) u16max else width_sq + height_sq;
        const diagonal = fastSqrt(asF32(u16, sum_squares));
        return Circle{
            .center = Point.at(x, y),
            .radius = asU16(f32, diagonal / 2.0),
        };
    }

    /// Returns a circle centered on `x`,`y` whose diameter equals the rectangle diagonal, plus buffer.
    pub fn around(x: u16, y: u16, width: u16, height: u16, buffer: u16) Circle {
        const width_sq = if (width > u16max / width) u16max else width * width;
        const height_sq = if (height > u16max / height) u16max else height * height;
        const sum_squares = if (width_sq > u16max - height_sq) u16max else width_sq + height_sq;
        const diagonal = fastSqrt(asF32(u16, sum_squares));
        return Circle{
            .center = Point.at(x, y),
            .radius = asU16(f32, diagonal / 2.0) + buffer,
        };
    }

    /// Returns a circle centered on an entity whose radius represents the average distance from the entity's center to its edges.
    pub fn atEntity(entity: *e.Entity) Circle {
        return atRect(Point.atEntity(entity), entity.width(), entity.height());
    }

    /// Returns a circle centered on an entity whose diameter equals the rectangle diagonal.
    pub fn encompassEntity(entity: *e.Entity) Circle {
        return encompass(entity.x(), entity.y(), entity.width(), entity.height());
    }

    /// Returns a circle centered on an entity whose radius equals the distance from the entity's center to its corners, plus buffer.
    pub fn aroundEntity(entity: *e.Entity, buffer: u16) Circle {
        return around(entity.x(), entity.y(), entity.width(), entity.height(), buffer);
    }
};

// Returns half the diagonal length, which is the "reach" from the center to the furthest point (corner).
pub fn reachFromRect(width: u16, height: u16) u16 {
    const width_sq = if (width > u16max / width) u16max else width * width;
    const height_sq = if (height > u16max / height) u16max else height * height;
    const sum_squares = if (width_sq > u16max - height_sq) u16max else width_sq + height_sq;
    return asU16(f32, fastSqrt(asF32(u16, sum_squares)) / 2);
}

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
        1 => {
            newX = if (newX > distance) newX - distance else 0;
            newY += distance;
        },
        2 => newY += distance,
        3 => {
            newX += distance;
            newY += distance;
        },
        4 => newX = if (newX > distance) newX - distance else 0,
        6 => newX += distance,
        7 => {
            newX = if (newX > distance) newX - distance else 0;
            newY = if (newY > distance) newY - distance else 0;
        },
        8 => newY = if (newY > distance) newY - distance else 0,
        9 => {
            newX += distance;
            newY = if (newY > distance) newY - distance else 0;
        },
        else => {},
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

pub fn cardinalDirFromAngle(angle: f32) u8 {
    return switch (@as(i32, @intFromFloat(@round(angle)))) {
        225...314 => 2, ///// Down
        135...224 => 4, ///// Left
        0...44 => 6, ///// Right
        315...360 => 6, ///// Right
        45...134 => 8, ///// Up
        else => 6, //// Defaults to right
    };
}

pub fn angleToSquareOffset(angle: f32, width: u16, height: u16) Vector {
    const dir = cardinalDirFromAngle(angle);
    return switch (dir) {
        2 => Vector{ .x = 0, .y = @divTrunc(asF32(u16, height), 2) }, // Down (positive y-offset)
        4 => Vector{ .x = -@divTrunc(asF32(u16, width), 2), .y = 0 }, // Left (negative x-offset)
        6 => Vector{ .x = @divTrunc(asF32(u16, width), 2), .y = 0 }, // Right (positive x-offset)
        8 => Vector{ .x = 0, .y = -@divTrunc(asF32(u16, height), 2) }, // Up (negative y-offset)
        else => Vector{ .x = @divTrunc(asF32(u16, width), 2), .y = 0 }, // Defaults to right
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

/// Rough check of whether current position differs from previous + speed (within 0.5), in which case was otherwise moved.
pub fn moveDeviationCheck(current: Point, previous: Point, speed: f16) bool {
    if (current.equals(previous)) return false; // Was stationary already
    const distance = fastSqrt(asF32(u32, distanceSquared(current, previous)));
    return (distance < speed - 0.25 or distance > speed + 0.25);
}

pub fn interpolateStep(last_x: u16, last_y: u16, x: i32, y: i32, frame: i16, interval: comptime_int) [2]i32 {
    const steps_since_last_move = interval - @rem(frame, interval); // Number of steps since the last move
    const interpolation_factor = @as(f32, @floatFromInt(steps_since_last_move)) / @as(f32, @floatFromInt(interval));

    const interp_x = @as(i32, last_x) + @as(i32, @intFromFloat(interpolation_factor * @as(f32, @floatFromInt(x - @as(i32, last_x)))));
    const interp_y = @as(i32, last_y) + @as(i32, @intFromFloat(interpolation_factor * @as(f32, @floatFromInt(y - @as(i32, last_y)))));

    return [2]i32{ interp_x, interp_y };
}

/// Gets `frame`'s offset from base `x`,`y` values that results from interpolating between `last_x`,`last_y` and `x`,`y` over `interval`.
pub fn interpolateStepOffsets(last_x: u16, last_y: u16, x: i32, y: i32, frame: i16, interval: comptime_int) [2]f32 {
    const steps_since_last_move = interval - @rem(frame, interval); // Number of steps since the last move
    const interpolation_factor = @as(f32, @floatFromInt(steps_since_last_move)) / @as(f32, @floatFromInt(interval));

    // Calculate the interpolation offsets
    const offset_x = interpolation_factor * @as(f32, @floatFromInt(x - @as(i32, last_x)));
    const offset_y = interpolation_factor * @as(f32, @floatFromInt(y - @as(i32, last_y)));

    return [2]f32{ offset_x, offset_y };
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

/// Takes the square root of the distance squared from `e1` to `e2`.
pub fn entityDistance(e1: *e.Entity, e2: *e.Entity) f32 {
    const a = Point.at(e1.x(), e1.y());
    const b = Point.at(e2.x(), e2.y());
    return fastSqrt(asF32(u32, distanceSquared(a, b)));
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
    pub const cell_size = main.World.GRID_CELL_SIZE;
    pub const cell_half: comptime_int = cell_size / 2;
    pub const cell_size_squared = Grid.cell_size * Grid.cell_size;

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
    const max_x: u16 = main.World.width;
    const min_y: u16 = 0;
    const max_y: u16 = main.World.height;
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
        const snapped_center = Subcell.nodeFromCoordinates(if (x > width / 2) x - width / 2 else 0, if (y > height / 2) y - height / 2 else 0);
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

pub const Waypoint: type = struct {
    /// Returns whether the coordinates are closer to the horizontal than the vertical center.
    fn goHorz(x: i32, y: i32) bool {
        const center_x = main.World.width / 2;
        const center_y = main.World.height / 2;
        return (@abs(x - center_x) < @abs(y - center_y));
    }

    /// Takes the grid column/row of a given cell and returns the 4 waypoints along its edges. Order: left mid, top mid, right mid, bottom mid.
    pub fn cellSides(grid_x: usize, grid_y: usize) [4]?Point {
        const node_x = @as(u16, @intCast(grid_x * Grid.cell_size));
        const node_y = @as(u16, @intCast(grid_y * Grid.cell_size));

        // Determine whether the movement should be horizontal or vertical
        const horizontal = goHorz(node_x, node_y);

        return [4]?Point{
            if (horizontal) Point.at(node_x, node_y + Grid.cell_half) else null, // left mid
            if (!horizontal) Point.at(node_x + Grid.cell_half, node_y) else null, // top mid
            if (horizontal) Point.at(node_x + Grid.cell_size, node_y + Grid.cell_half) else null, // right mid
            if (!horizontal) Point.at(node_x + Grid.cell_half, node_y + Grid.cell_size) else null, // bottom mid
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

    /// Finds the waypoint most aligned with `target` from the `current` point.
    pub fn closestTowards(current: Point, target: Point, total_distance_squared: u32, previous_step: Point) Point {
        const current_cell_center = Grid.cellCenter(current.x, current.y);
        var closest_grid_x = Grid.x(current_cell_center.x);
        var closest_grid_y = Grid.y(current_cell_center.y);
        // Shifts current cell if near edge
        if (current.x > current_cell_center.x and (current_cell_center.x + Grid.cell_half) < target.x) closest_grid_x += 1;
        if (current.x < current_cell_center.x and (current_cell_center.x - Grid.cell_half) > target.x) closest_grid_x -= 1;
        if (current.y > current_cell_center.y and (current_cell_center.y + Grid.cell_half) < target.y) closest_grid_y += 1;
        if (current.y < current_cell_center.y and (current_cell_center.y - Grid.cell_half) > target.y) closest_grid_y -= 1;

        const waypoints = cellSides(closest_grid_x, closest_grid_y);

        // Overall vector from current to target
        const dx = @as(i32, target.x) - @as(i32, current.x);
        const dy = @as(i32, target.y) - @as(i32, current.y);

        var best_waypoint: ?Point = null;
        var best_distance_squared = total_distance_squared; // Using squared since only comparison is needed
        var best_biased_alignment: f32 = 0;

        // Bias factor to discourage oscillation
        const bias_factor = 0.5; // The lower, the stronger bias away from previous_step

        for (waypoints) |wp| {
            if (wp == null) continue;
            // Vector from current to the waypoint under consideration
            const wp_dx = @as(i32, wp.?.x) - @as(i32, current.x);
            const wp_dy = @as(i32, wp.?.y) - @as(i32, current.y);

            // Dot product, degree of alignment with the overall vector
            const alignment: f32 = asF32(i32, dx * wp_dx + dy * wp_dy);

            // Vector from previous step to current waypoint
            const prev_dx = @as(i32, wp.?.x) - @as(i32, previous_step.x);
            const prev_dy = @as(i32, wp.?.y) - @as(i32, previous_step.y);
            const prev_alignment = dx * prev_dx + dy * prev_dy;

            // Apply bias if waypoint is in the direction of the previous step
            const biased_alignment = if (prev_alignment > 0) alignment * bias_factor else alignment;

            if (biased_alignment >= 0) {
                const wp_to_target_squared = distanceSquared(wp.?, target);
                const current_to_wp_squared = distanceSquared(current, wp.?);
                const new_distance_squared = current_to_wp_squared + wp_to_target_squared;

                // Compare both distance and biased alignment
                if (best_waypoint == null or (new_distance_squared < best_distance_squared) or (new_distance_squared == best_distance_squared and biased_alignment > best_biased_alignment)) {
                    best_distance_squared = new_distance_squared;
                    best_biased_alignment = biased_alignment;
                    best_waypoint = wp.?;
                } else if (new_distance_squared == best_distance_squared and biased_alignment == best_biased_alignment) {
                    // If distance and alignment are the same, tie-breaks using lexicographical ordering
                    if (wp.?.x < best_waypoint.?.x or (wp.?.x == best_waypoint.?.x and wp.?.y < best_waypoint.?.y)) {
                        best_waypoint = wp.?;
                    }
                }
            }
        }

        // Return the waypoint closest to the target, otherwise center of current cell
        if (best_waypoint) |point| {
            return point;
        } else {
            // Setting point to a pseudorandom based on last step position and target
            const random = @rem(previous_step.x + target.y, 4);

            std.debug.print("No best waypoint found. Pseudorandom waypoint chosen. Current: {}, Previous Step: {}, Chose waypoint: {}, at {any}.\n", .{ current, previous_step, random, waypoints[random] });
            return waypoints[random] orelse current;
        }
    }
};

pub fn isOnMap(x: u16, y: u16) bool {
    return x >= 0 and x < main.World.width and y >= 0 and y <= main.World.height;
}

pub fn isInMap(x: u16, y: u16, width: u16, height: u16) bool {
    const half_width = @divTrunc(width, 2);
    const half_height = @divTrunc(height, 2);

    const x_signed = @as(i32, @intCast(x));
    const y_signed = @as(i32, @intCast(y));

    return x_signed - half_width >= 0 and x_signed + half_width < @as(i32, @intCast(main.World.width)) and y_signed - half_height >= 0 and y_signed + half_height <= @as(i32, @intCast(main.World.height));
}

/// Clamps `coordinate` of type `T` to the map's dimensions and returns as same type. Set axis 0 for map width and 1 for map height.
pub fn mapClamp(T: type, coordinate: T, diameter: T, axis: u8) T {
    const radius = as(T, @divTrunc(diameter, 2), i32);
    const pos = as(T, coordinate, i32);
    const clamped = if (axis == 0)
        @max(radius, @min(pos, @as(i32, @intCast(main.World.width)) - radius))
    else
        @max(radius, @min(pos, @as(i32, @intCast(main.World.height)) - radius));
    return as(i32, clamped, T);
}

pub fn mapClampX(x: i32, width: u16) u16 {
    const half_width = @as(i16, @intCast(@divTrunc(width, 2)));
    const clamped_x = @max(half_width, @min(x, @as(i32, @intCast(main.World.width)) - half_width));
    return @as(u16, @intCast(clamped_x));
}

pub fn mapClampY(y: i32, height: u16) u16 {
    const half_height = @as(i16, @intCast(@divTrunc(height, 2)));
    const clamped_y = @max(half_height, @min(y, @as(i32, @intCast(main.World.height)) - half_height));
    return @as(u16, @intCast(clamped_y));
}

/// Produces a world coordinate from float `x` by clamping to map dimensions and rounding to a u16.
pub fn mapClampFloatX(x: f32, width: u16) u16 {
    const half_width = @as(f32, @floatFromInt(@divTrunc(width, 2)));
    const clamped_x = @max(half_width, @min(x, @as(f32, @floatFromInt(main.World.width)) - half_width));
    return @as(u16, @intFromFloat(@round(clamped_x)));
}

/// Produces a world coordinate from float `y` by clamping to map dimensions and rounding to a u16.
pub fn mapClampFloatY(y: f32, height: u16) u16 {
    const half_height = @as(f32, @floatFromInt(@divTrunc(height, 2)));
    const clamped_y = @max(half_height, @min(y, @as(f32, @floatFromInt(main.World.height)) - half_height));
    return @as(u16, @intFromFloat(@round(clamped_y)));
}

/// Searches for `Entity` that satisfies the `condition`, starting with the section at the `origin` point.
pub fn concentricSearch(grid: *e.Grid, origin: Point, condition: Predicate) ?*e.Entity {
    const origin_col = asI32(usize, Grid.x(origin.x));
    const origin_row = asI32(usize, Grid.y(origin.y));
    var closest_entity: ?*e.Entity = null;
    var closest_distance = std.math.inf(f32);

    var radius: i32 = 0;
    while (true) {
        var found_any_entity = false;
        var d: i32 = -radius;

        while (d <= radius) { // Check the four sides of the square at this radius
            const offsets = [4]Point{
                Point.fromIntegers(origin_col + d, origin_row - radius), // Top
                Point.fromIntegers(origin_col + d, origin_row + radius), // Bottom
                Point.fromIntegers(origin_col - radius, origin_row + d), // Left
                Point.fromIntegers(origin_col + radius, origin_row + d), // Right
            };

            for (&offsets) |offset| {
                if (offset.x >= 0 and offset.y >= 0 and offset.x < grid.columns and offset.y < grid.rows) {
                    const entities: ?*std.ArrayList(*e.Entity) = grid.sectionEntities(offset.x, offset.y);
                    if (entities != null) {
                        found_any_entity = true;
                        for (entities.?.items) |entity| {
                            if (condition(entity)) {
                                const distance = asF32(u32, distanceSquared(Point.at(origin.x, origin.y), Point.at(entity.x(), entity.y())));
                                if (distance < closest_distance) {
                                    closest_entity = entity;
                                    closest_distance = distance;
                                }
                            }
                        }
                    }
                }
            }
            d += 1;
        }
        if (closest_entity != null) return closest_entity; // If found entity in this radius, return the closest one
        if (!found_any_entity) break; // If no entities were found overall, stop searching

        radius += 2; // Increases radius by 2 since each section covers 3x3 cells, thus overlaps by one on each side
    }
    return null; // If no entity was found after the entire search
}

/// Searches for `Entity` that satisfies the `relation` to `origin` `Entity`. Returns pointer to nearest `Entity` found, or `null`.
pub fn concentricRelationalSearch(grid: *e.Grid, origin: *e.Entity, relation: Relation) ?*e.Entity {
    const origin_col = asI32(usize, Grid.x(origin.x()));
    const origin_row = asI32(usize, Grid.y(origin.y()));
    var closest_entity: ?*e.Entity = null;
    var closest_distance = std.math.inf(f32);

    var radius: i32 = 0;
    while (true) {
        var found_any_entity = false;
        var d: i32 = -radius;

        while (d <= radius) {
            // Check the four sides of the square at this radius
            const offsets = [4]Point{
                Point.fromIntegers(origin_col + d, origin_row - radius), // Top
                Point.fromIntegers(origin_col + d, origin_row + radius), // Bottom
                Point.fromIntegers(origin_col - radius, origin_row + d), // Left
                Point.fromIntegers(origin_col + radius, origin_row + d), // Right
            };

            for (&offsets) |offset| {
                if (offset.x >= 0 and offset.y >= 0 and offset.x < grid.columns and offset.y < grid.rows) {
                    const entities: ?*std.ArrayList(*e.Entity) = grid.sectionEntities(offset.x, offset.y);
                    if (entities != null) {
                        found_any_entity = true;
                        for (entities.?.items) |entity| {
                            if (relation(origin, entity)) { // Check if relation holds
                                const distance = asF32(u32, distanceSquared(Point.at(origin.x(), origin.y()), Point.at(entity.x(), entity.y())));
                                if (distance < closest_distance) {
                                    closest_entity = entity;
                                    closest_distance = distance;
                                }
                            }
                        }
                    }
                }
            }
            d += 1;
        }
        if (closest_entity != null) return closest_entity; // If found entity in this radius, return the closest one
        if (!found_any_entity) break; // If no entities were found overall, stop searching

        radius += 2; // Increases radius by 2 since each section covers 3x3 cells, thus overlaps by one on each side
    }

    return null; // If no entity was found after the entire search
}

/// Searches for `Structure` connected to `origin` `Structure`. Returns slice of any `Structure` found, or `null`.
pub fn findConnectedStructures(grid: *e.Grid, origin: *e.Structure) !?[]*e.Structure {
    const origin_col = Grid.x(origin.x);
    const origin_row = Grid.y(origin.y);
    const entities: ?*std.ArrayList(*e.Entity) = grid.sectionEntities(origin_col, origin_row);
    var structures = std.ArrayList(*e.Structure).init(grid.allocator.*);
    defer structures.deinit();

    if (entities) |entitylist| {
        for (entitylist.items) |entity| {
            if (entity.kind == e.Kind.Structure and e.Entity.isTouching(origin.entity, entity)) {
                try structures.append(entity.ref.Structure);
            }
        }
    }
    if (structures.items.len > 0) {
        return try structures.toOwnedSlice(); // Converts the ArrayList to a slice
    } else {
        return null;
    }
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
    return [2]i32{ canvasX(x, main.Camera.canvas_offset_x, main.Camera.canvas_zoom), canvasY(y, main.Camera.canvas_offset_y, main.Camera.canvas_zoom) };
}

/// Sets canvas offset values to center on the player position.
pub fn canvasOnPlayer() void {
    if (main.Player.self == null) return;
    const screen_width_f = @as(f32, @floatFromInt(rl.getScreenWidth()));
    const screen_height_f = @as(f32, @floatFromInt(rl.getScreenHeight()));
    main.Camera.canvas_offset_x_target = -(@as(f32, @floatFromInt(main.Player.self.?.x)) * main.Camera.canvas_zoom) + (screen_width_f / 2);
    main.Camera.canvas_offset_y_target = -(@as(f32, @floatFromInt(main.Player.self.?.y)) * main.Camera.canvas_zoom) + (screen_height_f / 2);
}

/// Sets canvas offset values to center on the position of `entity`.
pub fn canvasOnEntity(entity: *e.Entity) void {
    const screen_width_f = @as(f32, @floatFromInt(rl.getScreenWidth()));
    const screen_height_f = @as(f32, @floatFromInt(rl.getScreenHeight()));
    if (entity.kind == e.Kind.Unit) { // If entity is unit, movement is interpolated
        const unit = entity.ref.Unit;
        const xy = interpolateStep(unit.last_step.x, unit.last_step.y, unit.x, unit.y, unit.life, main.World.MOVEMENT_DIVISIONS);
        main.Camera.canvas_offset_x_target = -(@as(f32, @floatFromInt(xy[0])) * main.Camera.canvas_zoom) + (screen_width_f / 2);
        main.Camera.canvas_offset_y_target = -(@as(f32, @floatFromInt(xy[1])) * main.Camera.canvas_zoom) + (screen_height_f / 2);
    } else {
        main.Camera.canvas_offset_x_target = -(@as(f32, @floatFromInt(entity.x())) * main.Camera.canvas_zoom) + (screen_width_f / 2);
        main.Camera.canvas_offset_y_target = -(@as(f32, @floatFromInt(entity.y())) * main.Camera.canvas_zoom) + (screen_height_f / 2);
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

/// Returns the `x`,`y` map coordinates currently corresponding to what's drawn to the canvas at `screen_position` (e.g. mouse) in the viewport. Clamps to 0.
pub fn screenToMap(screen_position: rl.Vector2) [2]u16 {
    const x = u16Clamp(f32, screen_position.x - main.Camera.canvas_offset_x);
    const y = u16Clamp(f32, screen_position.y - main.Camera.canvas_offset_y);
    const zoomed_x = @as(u16, @intFromFloat(x / main.Camera.canvas_zoom));
    const zoomed_y = @as(u16, @intFromFloat(y / main.Camera.canvas_zoom));
    return [2]u16{ zoomed_x, zoomed_y };
}

/// Returns the subcell corresponding to `screen_position` given the current zoom and canvas offset.
pub fn screenToSubcell(screen_position: rl.Vector2) Subcell {
    const map_coords = screenToMap(screen_position);
    return Subcell.at(map_coords[0], map_coords[1]);
}

/// Returns vector distance from `screen_position` to the current canvas position of the local player.
pub fn screenToPlayerVector(screen_position: rl.Vector2) rl.Vector2 {
    if (main.Player.self == null) return rl.Vector2.init(0, 0);
    const player_x = canvasX(main.Player.self.?.x - @divTrunc(main.Player.self.?.width, 2), main.Camera.canvas_offset_x, main.Camera.canvas_zoom);
    const player_y = canvasY(main.Player.self.?.y - @divTrunc(main.Player.self.?.height, 2), main.Camera.canvas_offset_y, main.Camera.canvas_zoom);
    return rl.Vector2.init(screen_position.x - @as(f32, @floatFromInt(player_x)), screen_position.y - @as(f32, @floatFromInt(player_y)));
}

// Animation
//----------------------------------------------------------------------------------
pub const Interpolation = struct {
    pub fn framesToFactor(start_frame: u64, current_frame: u64, frame_duration: u64) f32 {
        return asF32(u64, (current_frame - start_frame)) / asF32(u64, frame_duration);
    }

    pub fn getFactor(current: i16, interval: i16) f32 {
        const remainder = @rem(current, interval);
        return asF32(i16, remainder) / asF32(i16, interval);
    }

    pub fn linear(t: f32, p0: Point, p1: Point) Point {
        const x = p0.x + (p1.x - p0.x) * t;
        const y = p0.y + (p1.y - p0.y) * t;
        return Point{ .x = x, .y = y };
    }

    pub fn quadratic(t: f32, p0: Point, p1: Point, p2: Point) Point {
        const one_minus_t = 1.0 - t;
        const x = one_minus_t * one_minus_t * p0.x + 2.0 * one_minus_t * t * p1.x + t * t * p2.x;
        const y = one_minus_t * one_minus_t * p0.y + 2.0 * one_minus_t * t * p1.y + t * t * p2.y;
        return Point{ .x = x, .y = y };
    }

    pub fn bezier(t: f32, p0: Point, p1: Point, p2: Point, p3: Point) Point {
        const one_minus_t = 1.0 - t;
        const x = one_minus_t * one_minus_t * one_minus_t * p0.x +
            3.0 * one_minus_t * one_minus_t * t * p1.x +
            3.0 * one_minus_t * t * t * p2.x +
            t * t * t * p3.x;
        const y = one_minus_t * one_minus_t * one_minus_t * p0.y +
            3.0 * one_minus_t * one_minus_t * t * p1.y +
            3.0 * one_minus_t * t * t * p2.y +
            t * t * t * p3.y;
        return Point{ .x = x, .y = y };
    }

    pub fn catmullrom(t: f32, p0: Point, p1: Point, p2: Point, p3: Point) Point {
        const t2 = t * t;
        const t3 = t2 * t;

        const x = 0.5 * ((2.0 * p1.x) +
            (-p0.x + p2.x) * t +
            (2.0 * p0.x - 5.0 * p1.x + 4.0 * p2.x - p3.x) * t2 +
            (-p0.x + 3.0 * p1.x - 3.0 * p2.x + p3.x) * t3);

        const y = 0.5 * ((2.0 * p1.y) +
            (-p0.y + p2.y) * t +
            (2.0 * p0.y - 5.0 * p1.y + 4.0 * p2.y - p3.y) * t2 +
            (-p0.y + 3.0 * p1.y - 3.0 * p2.y + p3.y) * t3);

        return Point{ .x = x, .y = y };
    }
};

const Joint = struct {
    position: Vector,
    connected_joints: []usize, // Array of indices pointing to connected joints
    distances: []f32, // Array of distances to each connected joint
};

const Leg = struct {
    upper_joint: Joint,
    lower_joint: Joint,
    is_moving_forward: bool,
};

pub const Model = struct {
    joints: []Joint, // Array of joints in the model
    legs: ?*Legs, // Optional pointer to legs

    pub fn new(joints: []Joint) Model {
        return Model{
            .joints = joints,
        };
    }

    pub fn destroy(self: *Model, allocator: *std.mem.Allocator) void {
        // Free all connected_joints and distances arrays
        for (self.joints) |joint| {
            allocator.free(joint.connected_joints);
            allocator.free(joint.distances);
        }
        // Free the joints array
        allocator.free(self.joints);
        // Free the Model itself
        allocator.destroy(self);
    }

    pub fn updateSoftBody(self: *Model, anchor_index: usize, new_anchor_position: Point) void {
        self.joints[anchor_index].position = Vector.fromPoint(new_anchor_position);
        for (self.joints, 0..) |*joint, i| {
            if (i == anchor_index) continue;

            for (joint.connected_joints, 0..) |connected_joint_index, j| {
                const connected_joint = &self.joints[connected_joint_index];
                const target_distance = joint.distances[j];

                var dx = connected_joint.position.x - joint.position.x;
                var dy = connected_joint.position.y - joint.position.y;
                const current_distance = fastSqrt(dx * dx + dy * dy);

                if (current_distance != target_distance) {
                    if (current_distance != 0) { // Normalize the direction vector
                        dx /= current_distance;
                        dy /= current_distance;
                    }

                    const correction_distance = (current_distance - target_distance);

                    // If the current joint is the anchor, adjust only the connected joint
                    if (i == anchor_index) {
                        connected_joint.position.x -= dx * correction_distance;
                        connected_joint.position.y -= dy * correction_distance;
                    } else if (connected_joint_index == anchor_index) {
                        joint.position.x += dx * correction_distance;
                        joint.position.y += dy * correction_distance;
                    } else {
                        joint.position.x += dx * correction_distance * 0.5;
                        joint.position.y += dy * correction_distance * 0.5;
                        connected_joint.position.x -= dx * correction_distance * 0.5;
                        connected_joint.position.y -= dy * correction_distance * 0.5;
                    }
                }
            }
        }
    }

    pub fn updateRigidBody(self: *Model, anchor_index: usize, new_anchor_position: Vector) void {
        self.joints[anchor_index].position = new_anchor_position;
        // Iterate over each joint, starting from the second one (index 1)
        for (self.joints[1..], 1..) |*joint, i| { // Start from the second joint since the first is the anchor
            const previous_joint = &self.joints[i - 1];
            const target_distance = joint.distances[0]; // Assuming each joint has one distance to the previous joint

            //std.debug.print("current joint: {}. previous joint: {}\n", .{ joint, previous_joint });
            // Calculate the direction from the previous joint to the current joint
            var dx = joint.position.x - previous_joint.position.x;
            var dy = joint.position.y - previous_joint.position.y;
            //std.debug.print("dx dy: {} {}\n", .{ dx, dy });

            const current_distance = fastSqrt(dx * dx + dy * dy);
            //std.debug.print("distance between joint and previous joint: {}\n", .{current_distance});
            // Normalize the direction vector if the distance is not zero
            if (current_distance != 0) {
                dx /= current_distance;
                dy /= current_distance;
            } else {
                // If the distance is zero, we assume a default direction (e.g., along the x-axis)
                dx = 1;
                dy = 0;
            }
            joint.position.x = previous_joint.position.x + dx * target_distance;
            joint.position.y = previous_joint.position.y + dy * target_distance;
            //std.debug.print("Joint {} moved to: {}\n", .{ i, joint.position });
        }
    }

    pub fn updateRigidBodyInterpolated(self: *Model, anchor_index: usize, previous_anchor_position: Vector, new_anchor_position: Vector, interpolation_factor: f32) void {
        const anchor_joint = &self.joints[anchor_index];
        const previous_position = previous_anchor_position;

        // Interpolates anchor position based on the provided interpolation factor
        anchor_joint.position.x = previous_position.x + ((1 - interpolation_factor) * (new_anchor_position.x - previous_position.x));
        anchor_joint.position.y = previous_position.y + ((1 - interpolation_factor) * (new_anchor_position.y - previous_position.y));

        // Update the rest of the model
        updateRigidBody(self, anchor_index, anchor_joint.position);

        // If model has legs, position them at the anchor
        if (self.legs) |legs| {
            legs.updateLegMovement(anchor_joint.position, interpolation_factor);
        }
    }

    /// Creates a snake-like model with the specified number of joints starting from an initial position and with a specified distance between joints.
    pub fn createChain(allocator: *std.mem.Allocator, joint_count: usize, initial_position: Point, distance: f32) !*Model {
        var joints = try allocator.alloc(Joint, joint_count);
        const dx = distance;

        for (0..joint_count) |i| {
            var connected_joints: []usize = &[_]usize{};
            var distances: []f32 = &[_]f32{};

            if (i == 0) {
                connected_joints = try allocator.alloc(usize, 1);
                connected_joints[0] = 1;
                distances = try allocator.alloc(f32, 1);
                distances[0] = distance;
            } else if (i == joint_count - 1) {
                connected_joints = try allocator.alloc(usize, 1);
                connected_joints[0] = i - 1;
                distances = try allocator.alloc(f32, 1);
                distances[0] = distance;
            } else {
                connected_joints = try allocator.alloc(usize, 2);
                connected_joints[0] = i - 1;
                connected_joints[1] = i + 1;
                distances = try allocator.alloc(f32, 2);
                distances[0] = distance;
                distances[1] = distance;
            }

            joints[i] = Joint{
                .position = Vector{
                    .x = asF32(u16, initial_position.x + asU16(f32, asF32(usize, i) * dx)), // Extends to the right
                    .y = asF32(u16, initial_position.y),
                },
                .connected_joints = connected_joints,
                .distances = distances,
            };
        }

        const model = try allocator.create(Model);
        model.* = Model{
            .joints = joints,
            .legs = null, // Has no legs
        };

        return model;
    }

    pub fn getElbowPosLocal(l1: f32, l2: f32, local_end_affector: Vector, elbow_direction_sign: *i32) Vector {
        const numerator: f32 = l1 * l1 + local_end_affector.x * local_end_affector.x + local_end_affector.y * local_end_affector.y - l2 * l2;
        const denominator: f32 = 2 * l1 * fastSqrt(local_end_affector.x * local_end_affector.x + local_end_affector.y * local_end_affector.y);

        const elbow_angle_relative = std.math.acos(numerator / denominator);
        if (elbow_direction_sign.* == 0) elbow_direction_sign.* = 1;

        return Vector.fromFloats(1 * elbow_angle_relative + local_end_affector.angle(), l1);
    }
};

pub const Legs = struct {
    legs: []Leg, // Array of legs

    pub fn updateLegMovement(self: *Legs, anchor_position: Vector, interpolation_factor: f32) void {
        const leg_swing_amplitude = 20.0; // Adjust this value for higher or lower leg swings
        const leg_swing_frequency = 2.0 * std.math.pi; // Full cycle for sine wave (0 to 1 to 0)

        for (self.legs, 0..) |*leg, j| {
            const phase_shift: f32 = if (leg.is_moving_forward) 0.0 else std.math.pi; // Phase shift for opposite legs

            // Calculate the swing position using a sine wave for smooth motion
            const swing_position = leg_swing_amplitude * @sin(interpolation_factor * leg_swing_frequency + phase_shift);

            leg.upper_joint.position = if (j % 2 == 0)
                anchor_position.shift(5, 0)
            else
                anchor_position.shift(-5, 0);

            // Calculate the target position for the lower joint
            leg.lower_joint.position.x = leg.upper_joint.position.x + swing_position;
            leg.lower_joint.position.y = leg.upper_joint.position.y - leg.lower_joint.distances[0]; // Keep leg length consistent

            if (leg.is_moving_forward and swing_position > 0) {
                // Foot is planted (approaching the ground)
                leg.lower_joint.position.y = leg.upper_joint.position.y - leg.lower_joint.distances[0];
            } else if (swing_position <= 0) {
                // Foot is lifting (moving backward)
                leg.lower_joint.position.y = leg.upper_joint.position.y - (leg.lower_joint.distances[0] - @abs(swing_position));
            }

            // Reverse direction if necessary (when the leg reaches its forward/backward limit)
            if (interpolation_factor >= 1.0) {
                leg.is_moving_forward = !leg.is_moving_forward;
            }
        }
    }

    pub fn attach(allocator: *std.mem.Allocator, model: *Model, leg_count: usize, leg_length: f32) !void {
        var legs = try allocator.alloc(Leg, leg_count);

        const joint_spacing = @divTrunc(model.joints.len, leg_count);

        for (0..leg_count) |i| {
            const upper_joint = model.joints[i * joint_spacing];

            var lower_joint_position = upper_joint.position;
            lower_joint_position.y -= leg_length; // Legs extend downwards

            // Allocate memory for connected_joints and distances
            var connected_joints = try allocator.alloc(usize, 1);
            connected_joints[0] = i * joint_spacing;

            var distances = try allocator.alloc(f32, 1);
            distances[0] = leg_length;

            legs[i] = Leg{
                .upper_joint = upper_joint, // Reference the upper joint directly
                .lower_joint = Joint{
                    .position = lower_joint_position,
                    .connected_joints = connected_joints, // Assign the allocated slice
                    .distances = distances, // Assign the allocated slice
                },
                .is_moving_forward = i % 2 == 0, // Alternate initial movement direction
            };
        }

        const legged_model = try allocator.create(Legs);
        legged_model.* = Legs{
            .legs = legs,
        };

        model.legs = legged_model; // Assign the legs to the model
    }
};

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

fn idToHue(id: u8) rl.Color {
    return switch (id) {
        0 => rl.Color.gray,
        1 => rl.Color.blue,
        2 => rl.Color.red,
        3 => rl.Color.green,
        4 => rl.Color.purple,
        else => rl.Color.brown,
    };
}

pub fn idToColor(id: u8, alpha: f32) rl.Color {
    return opacity(idToHue(id), alpha);
}

pub fn drawGuide(x: i32, y: i32, width: i32, height: i32, col: rl.Color) void {
    drawEntity(x, y, width, height, opacity(col, 0.4)); // Change to outline
}

pub fn drawGuideFail(x: i32, y: i32, width: i32, height: i32, col: rl.Color) void {
    drawEntity(x, y, width, height, opacity(col, 0.125)); // Change to outline
}

/// Uses raylib to draw rectangle scaled and positioned to canvas.
pub fn drawRect(x: i32, y: i32, width: i32, height: i32, col: rl.Color) void {
    rl.drawRectangle(canvasX(x, main.Camera.canvas_offset_x, main.Camera.canvas_zoom), canvasY(y, main.Camera.canvas_offset_y, main.Camera.canvas_zoom), canvasScale(width, main.Camera.canvas_zoom), canvasScale(height, main.Camera.canvas_zoom), col);
}

/// Uses raylib to draw line with thickness, scaled and positioned to canvas.
pub fn drawLineEx(start: Vector, end: Vector, thickness: i32, col: rl.Color) void {
    rl.drawLineEx(Vector.toRaylib(Vector.toScreen(start)), Vector.toRaylib(Vector.toScreen(end)), asF32(i32, canvasScale(thickness, main.Camera.canvas_zoom)), col);
}

/// Uses raylib to draw circle scaled and positioned to canvas.
pub fn drawCircle(x: i32, y: i32, radius: f32, col: rl.Color) void {
    const scale = asF32(i32, canvasScale(asI32(f32, radius), main.Camera.canvas_zoom));
    rl.drawCircle(canvasX(x, main.Camera.canvas_offset_x, main.Camera.canvas_zoom), canvasY(y, main.Camera.canvas_offset_y, main.Camera.canvas_zoom), scale, col);
}

/// Uses raylib to draw a circumference scaled and positioned to canvas.
pub fn drawCircumference(circle: Circle, col: rl.Color) void {
    const scale = asF32(i32, canvasScale(circle.radius, main.Camera.canvas_zoom));
    rl.drawCircleLines(canvasX(circle.center.x, main.Camera.canvas_offset_x, main.Camera.canvas_zoom), canvasY(circle.center.y, main.Camera.canvas_offset_y, main.Camera.canvas_zoom), scale, col);
}

/// Draws entity life-scaled rectangle centered on `x`,`y` coordinates, scaled and positioned to canvas.
pub fn drawLife(x: i32, y: i32, width: i32, life: i32, max_life: i32) void {
    if (life <= 0 or max_life <= 0) return; // Don't draw if life or max_life is invalid

    // Calculate portion based on life ratio
    const life_ratio = asF32(i32, life) / asF32(i32, max_life);
    const portion = asF32(i32, width) * life_ratio;

    // Calculate positions and scaling
    const draw_x = canvasX(x - @divTrunc(width, 2), main.Camera.canvas_offset_x, main.Camera.canvas_zoom);
    const draw_y = canvasY(y - 5, main.Camera.canvas_offset_y, main.Camera.canvas_zoom);
    const draw_width = canvasScale(asI32(f32, portion), main.Camera.canvas_zoom);
    const draw_height = canvasScale(10, main.Camera.canvas_zoom);

    rl.drawRectangle(draw_x, draw_y, draw_width, draw_height, rl.Color.green);
}

/// Draws entity life-scaled rectangle centered on `x`,`y` coordinates, scaled and positioned to canvas.
pub fn drawLifeInterpolated(x: i32, y: i32, width: i32, life: i32, max_life: i32, last_step: Point, frame: i16) void {
    const interp_xy = interpolateStep(last_step.x, last_step.y, x, y, frame, main.World.MOVEMENT_DIVISIONS);
    drawLife(interp_xy[0], interp_xy[1], width, life, max_life);
}

/// Draws structure capacity-scaled rectangle centered on `x`,`y` coordinates, scaled and positioned to canvas.
pub fn drawCapacity(x: i32, y: i32, width: i32, height: i32, capacity: i32, max_capacity: i32) void {
    if (capacity <= 0 or max_capacity <= 0) return; // Don't draw if capacity or max_capacity is invalid

    // Calculate portion based on life ratio
    const capacity_ratio = asF32(i32, @min(max_capacity, capacity)) / asF32(i32, max_capacity);
    const portion = asF32(i32, width) * capacity_ratio;

    // Calculate positions and scaling
    const draw_x = canvasX(x - @divTrunc(width, 2), main.Camera.canvas_offset_x, main.Camera.canvas_zoom);
    const draw_y = canvasY(y + (@divTrunc(height, 2) - 10), main.Camera.canvas_offset_y, main.Camera.canvas_zoom);
    const draw_width = canvasScale(asI32(f32, portion), main.Camera.canvas_zoom);
    const draw_height = canvasScale(10, main.Camera.canvas_zoom);

    rl.drawRectangle(draw_x, draw_y, draw_width, draw_height, rl.Color.dark_gray);
}

/// Draws rectangle centered on `x`,`y` coordinates, scaled and positioned to canvas.
pub fn drawEntity(x: i32, y: i32, width: i32, height: i32, col: rl.Color) void {
    rl.drawRectangle(canvasX(x - @divTrunc(width, 2), main.Camera.canvas_offset_x, main.Camera.canvas_zoom), canvasY(y - @divTrunc(height, 2), main.Camera.canvas_offset_y, main.Camera.canvas_zoom), canvasScale(width, main.Camera.canvas_zoom), canvasScale(height, main.Camera.canvas_zoom), col);
}

pub fn initTexture(filename: [*:0]const u8) rl.Texture2D {
    return rl.loadTexture(filename);
}

pub fn drawTexture(texture: rl.Texture2D, x: i32, y: i32, tint: rl.Color) void {
    const textureWidth = texture.width;
    const textureHeight = texture.height;
    const zoom = main.Camera.canvas_zoom;
    const centerX = x - @divTrunc(textureWidth, 2);
    const centerY = y - @divTrunc(textureHeight, 2);
    const canvasXPos = canvasX(centerX, main.Camera.canvas_offset_x, zoom);
    const canvasYPos = canvasY(centerY, main.Camera.canvas_offset_y, zoom);
    const position = Vector.fromIntegers(canvasXPos, canvasYPos);
    rl.drawTextureEx(texture, position.toRaylib(), 0.0, zoom, tint);
}

/// Draws rectangle centered on `x`,`y` coordinates, scaled and positioned to canvas, interpolated by `frame` since `last_step`. The full interpolation interval is determined by `MOVEMENT_DIVISIONS`.
pub fn drawEntityInterpolated(x: i32, y: i32, width: i32, height: i32, col: rl.Color, last_step: Point, frame: i16) void {
    const interp_xy = interpolateStep(last_step.x, last_step.y, x, y, frame, main.World.MOVEMENT_DIVISIONS);
    drawEntity(interp_xy[0], interp_xy[1], width, height, col);
}

/// Draws rectangle and build radius centered on `x`,`y` coordinates, scaled and positioned to canvas.
pub fn drawPlayer(x: i32, y: i32, width: i32, height: i32, col: rl.Color) void {
    drawEntity(x, y, width, height, col);
    drawCircumference(Circle.atIntegers(x, y, Grid.cell_half), opacity(col, 0.25));
}

pub fn drawModel(model: *Model, width: u16, height: u16, jointColor: rl.Color, boneColor: rl.Color) void {
    const max_thickness = @divTrunc(width + height, 4);
    for (model.joints, 0..) |joint, j| { // Draw bones between joints
        const thickness = asF32(u16, max_thickness) * (1 - 0.5 * (asF32(usize, j) / asF32(usize, model.joints.len - 1)));
        for (joint.connected_joints) |connected_joint_index| {
            const connected_joint = model.joints[connected_joint_index];
            drawLineEx(joint.position, connected_joint.position, asI32(f32, thickness), boneColor);
        }
    }
    for (model.joints, 0..) |joint, j| { // Draw each joint
        const w = asI32(usize, width / (j + 1));
        const h = asI32(usize, height / (j + 1));
        const x = asI32(f32, joint.position.x) - @divTrunc(w, 2);
        const y = asI32(f32, joint.position.y) - @divTrunc(h, 2);
        drawRect(x, y, w, h, jointColor);
    }

    // Draw legs if they exist
    if (model.legs) |legs| {
        for (legs.legs) |leg| {
            // Draw the bone of the leg (line between upper and lower joint)
            drawLineEx(leg.upper_joint.position, leg.lower_joint.position, max_thickness / 2, boneColor);

            // Optionally, draw the lower joint of the leg
            const w = asI32(usize, width / 2);
            const h = asI32(usize, height / 2);
            const x = asI32(f32, leg.lower_joint.position.x) - @divTrunc(w, 2);
            const y = asI32(f32, leg.lower_joint.position.y) - @divTrunc(h, 2);
            drawRect(x, y, w, h, jointColor);
        }
    }
}

/// Not accurate for joints on abrupt movement. Consider interpolating model, instead.
pub fn drawModelInterpolated(model: *Model, jointRadius: f32, jointColor: rl.Color, boneColor: rl.Color, last_step: Point, frame: i16) void {
    // Calculate the interpolated position for the first joint (anchor)
    const offset = interpolateStepOffsets(last_step.x, last_step.y, asI32(f32, model.joints[0].position.x), asI32(f32, model.joints[0].position.y), frame, main.World.MOVEMENT_DIVISIONS);

    for (model.joints) |joint| { // Draw bones between joints
        for (joint.connected_joints) |connected_joint_index| {
            const connected_joint = model.joints[connected_joint_index];
            const x1 = asI32(f32, joint.position.x + offset[0]);
            const y1 = asI32(f32, joint.position.y + offset[1]);
            const x2 = asI32(f32, connected_joint.position.x + offset[0]);
            const y2 = asI32(f32, connected_joint.position.y + offset[1]);
            rl.drawLineEx(canvasX(x1, main.Camera.canvas_offset_x, main.Camera.canvas_zoom), canvasY(y1, main.Camera.canvas_offset_y, main.Camera.canvas_zoom), canvasX(x2, main.Camera.canvas_offset_x, main.Camera.canvas_zoom), canvasY(y2, main.Camera.canvas_offset_y, main.Camera.canvas_zoom), 10, boneColor);
        }
    }
    for (model.joints) |joint| { // Draw joints
        const x = asI32(f32, joint.position.x + offset[0]);
        const y = asI32(f32, joint.position.y + offset[1]);
        drawRect(x, y, jointRadius, jointRadius, jointColor);
    }
}
