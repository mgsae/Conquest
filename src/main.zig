const rl = @import("raylib");
const std: type = @import("std");
const utils = @import("utils.zig");
const entity = @import("entity.zig");

// Camera movement
pub var screenWidth: i16 = 1920;
pub var screenHeight: i16 = 1080;
pub var canvasOffsetX: f32 = 0.0;
pub var canvasOffsetY: f32 = 0.0;
pub const scrollSpeed: f16 = 30.0;
pub var canvasZoom: f32 = 1.0;
pub var maxZoomOut: f32 = 1.0; // Recalculated in setMapSize() for max map visibility

// Game map
const startingMapWidth = 1920 * 4;
const startingMapHeight = 1080 * 4;
pub var mapWidth: i32 = 0;
pub var mapHeight: i32 = 0;
pub var gameGrid: entity.Grid = undefined;
pub var gamePlayer: *entity.Player = undefined;

// Config
pub const entityCollisionLimit = 400;
const logicFps = 60;
const updateInterval: f64 = 1.0 / @as(f64, @floatFromInt(logicFps));
var lastUpdateTime: f64 = 0.0;
var intervalUpdated: bool = false;

pub fn main() anyerror!void {

    // Memory initialization
    //--------------------------------------------------------------------------------------
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // Initialize window
    //--------------------------------------------------------------------------------------
    rl.initWindow(screenWidth, screenHeight, "Conquest");
    defer rl.closeWindow(); // Close window and OpenGL context
    rl.toggleFullscreen();
    rl.setTargetFPS(1000);

    // Initialize utility
    //--------------------------------------------------------------------------------------
    utils.rngInit();
    var accumulatedMouseWheel: f32 = 0.0;
    var accumulatedKeyInput: u32 = 0;

    // Initialize map
    //--------------------------------------------------------------------------------------
    setMapSize(startingMapWidth, startingMapHeight);
    // Define grid dimensions
    const gridWidth: usize = @intCast(utils.ceilDiv(mapWidth, utils.Grid.CellSize));
    const gridHeight: usize = @intCast(utils.ceilDiv(mapHeight, utils.Grid.CellSize));

    std.debug.print("Grid Width: {}, Grid Height: {}\n", .{ gridWidth, gridHeight });
    std.debug.print("Map Width: {}, Map Height: {}, Cell Size: {}\n", .{ mapWidth, mapHeight, utils.Grid.CellSize });

    // Initialize the grid
    try gameGrid.init(gridWidth, gridHeight, @constCast(&allocator));
    defer gameGrid.deinit();

    // Initialize entities
    //--------------------------------------------------------------------------------------
    entity.players = std.ArrayList(*entity.Player).init(allocator);
    entity.units = std.ArrayList(*entity.Unit).init(allocator);
    entity.structures = std.ArrayList(*entity.Structure).init(allocator);

    const startCoords = try startingLocations(allocator, 3); // 3 players
    for (startCoords, 0..) |coord, i| {
        std.debug.print("Player starting at: ({}, {})\n", .{ coord.x, coord.y });
        if (i == 0) {
            const player = try entity.Player.createLocal(coord.x, coord.y);
            try entity.players.append(player);
            gamePlayer = player; // Sets gamePlayer to local player pointer
        } else {
            const player = try entity.Player.createRemote(coord.x, coord.y);
            try entity.players.append(player);
        }
    }
    allocator.free(startCoords); // Freeing starting positions

    // try entity.structures.append(try entity.Structure.create(2500, 1500, 0));
    // try entity.units.append(try entity.Unit.create(2500, 1500, 0));

    defer entity.players.deinit();
    defer entity.units.deinit();
    defer entity.structures.deinit();

    var count: i32 = 0; // debugging, for longer interval
    // Main game loop
    //--------------------------------------------------------------------------------------
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key

        // Input
        //----------------------------------------------------------------------------------
        processInput(&accumulatedMouseWheel, &accumulatedKeyInput);

        // Logic
        //----------------------------------------------------------------------------------
        const currentTime: f64 = rl.getTime(); // Get current time in seconds
        const updatesNeeded: usize = @intFromFloat((currentTime - lastUpdateTime) / updateInterval);
        if (updatesNeeded > 0) { // If interval passed since previous update
            if (updatesNeeded > 1) std.debug.print("Time lapse detected, applying {} updates.\n", .{updatesNeeded});
            for (0..updatesNeeded) |_| {
                try updateLogic(accumulatedMouseWheel, accumulatedKeyInput);
                accumulatedMouseWheel = 0.0;
                accumulatedKeyInput = 0;
            } // Increment the last update time
            lastUpdateTime += updateInterval * @as(f64, @floatFromInt(updatesNeeded));
            const grid = &gameGrid;
            if (@mod(count, 100) == 0) utils.printTotalEntitiesOnGrid(grid);
            count += 1;
        }

        // Drawing
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.white);
        drawMap();
        drawEntities();
        drawUI();
    }
}

fn processInput(accumulatedMouseWheel: *f32, accumulatedKeyInput: *u32) void {
    accumulatedMouseWheel.* += rl.getMouseWheelMove();
    // Move keys
    if (rl.isKeyDown(rl.KeyboardKey.key_w) or rl.isKeyDown(rl.KeyboardKey.key_up)) accumulatedKeyInput.* |= 1 << 0;
    if (rl.isKeyDown(rl.KeyboardKey.key_a) or rl.isKeyDown(rl.KeyboardKey.key_left)) accumulatedKeyInput.* |= 1 << 1;
    if (rl.isKeyDown(rl.KeyboardKey.key_s) or rl.isKeyDown(rl.KeyboardKey.key_down)) accumulatedKeyInput.* |= 1 << 2;
    if (rl.isKeyDown(rl.KeyboardKey.key_d) or rl.isKeyDown(rl.KeyboardKey.key_right)) accumulatedKeyInput.* |= 1 << 3;
    // Build keys
    if (rl.isKeyDown(rl.KeyboardKey.key_one)) accumulatedKeyInput.* |= 1 << 4;
    if (rl.isKeyDown(rl.KeyboardKey.key_two)) accumulatedKeyInput.* |= 1 << 5;
    if (rl.isKeyDown(rl.KeyboardKey.key_three)) accumulatedKeyInput.* |= 1 << 6;
    if (rl.isKeyDown(rl.KeyboardKey.key_four)) accumulatedKeyInput.* |= 1 << 7;
    // Special keys
    if (rl.isKeyDown(rl.KeyboardKey.key_space)) accumulatedKeyInput.* |= 1 << 9;
}

fn updateLogic(mouseWheelDelta: f32, keyInput: u32) !void {

    //Camera
    //----------------------------------------------------------------------------------
    updateCanvasZoom(mouseWheelDelta);
    updateCanvasPosition(keyInput);

    // Entities
    //----------------------------------------------------------------------------------
    for (entity.structures.items) |structure| {
        structure.update();
    }
    for (entity.units.items) |unit| {
        unit.update();
    }
    for (entity.players.items) |player| {
        if (player == gamePlayer) {
            try player.update(keyInput);
        } else {
            try player.update(null);
        }
    }
}

pub fn updateCanvasZoom(mouseWheelDelta: f32) void {
    const i = mouseWheelDelta;
    if (i != 0) {
        const oldZoom: f32 = canvasZoom;

        const zoomChange: f32 = 1 + (0.025 * i);
        canvasZoom = @min(@max(maxZoomOut, canvasZoom * zoomChange), 10.0); // From <1 (full map) to 10 (zoomed in)

        // Adjust offsets to zoom around the mouse position
        const mouseX = @as(f32, @floatFromInt(rl.getMouseX()));
        const mouseY = @as(f32, @floatFromInt(rl.getMouseY()));

        // Calculate the position of the mouse in canvas coordinates before zoom
        const canvasMouseXBeforeZoom = (mouseX - canvasOffsetX) / oldZoom;
        const canvasMouseYBeforeZoom = (mouseY - canvasOffsetY) / oldZoom;

        // Calculate the position of the mouse in canvas coordinates after zoom
        const canvasMouseXAfterZoom = (mouseX - canvasOffsetX) / canvasZoom;
        const canvasMouseYAfterZoom = (mouseY - canvasOffsetY) / canvasZoom;

        // Adjust offsets to keep the mouse position consistent
        canvasOffsetX += @floatCast((canvasMouseXAfterZoom - canvasMouseXBeforeZoom) * canvasZoom);
        canvasOffsetY += @floatCast((canvasMouseYAfterZoom - canvasMouseYBeforeZoom) * canvasZoom);
    }
}

pub fn updateCanvasPosition(keyInput: u32) void {
    const mouseX = @as(f32, @floatFromInt(rl.getMouseX()));
    const mouseY = @as(f32, @floatFromInt(rl.getMouseY()));
    const screenWidthF = @as(f32, @floatFromInt(screenWidth));
    const screenHeightF = @as(f32, @floatFromInt(screenHeight));
    const edgeMarginW: f32 = screenWidthF / 10.0;
    const edgeMarginH: f32 = screenHeightF / 10.0;
    const effectiveScrollSpeed: f32 = @as(f32, @floatCast(scrollSpeed)) / @max(1, canvasZoom * 0.1);

    if ((keyInput & (1 << 9)) != 0) {
        // Space key centers camera on player
        canvasOffsetX = -(@as(f32, @floatFromInt(gamePlayer.x)) * canvasZoom) + (screenWidthF / 2);
        canvasOffsetY = -(@as(f32, @floatFromInt(gamePlayer.y)) * canvasZoom) + (screenHeightF / 2);
    } else {
        // Mouse edge scrolls camera
        if (mouseX < edgeMarginW) {
            const factor = 1.0 - (mouseX / edgeMarginW);
            canvasOffsetX += effectiveScrollSpeed * factor;
        }
        if (mouseX > screenWidthF - edgeMarginW) {
            const factor = 1.0 - ((screenWidthF - mouseX) / edgeMarginW);
            canvasOffsetX -= effectiveScrollSpeed * factor;
        }
        if (mouseY < edgeMarginH) {
            const factor = 1.0 - (mouseY / edgeMarginH);
            canvasOffsetY += effectiveScrollSpeed * factor;
        }
        if (mouseY > screenHeightF - edgeMarginH) {
            const factor = 1.0 - ((screenHeightF - mouseY) / edgeMarginH);
            canvasOffsetY -= effectiveScrollSpeed * factor;
        }
    }

    // Restrict canvas to map bounds
    const minMapOffsetX: f32 = screenWidthF - @as(f32, @floatFromInt(mapWidth)) * canvasZoom;
    const minMapOffsetY: f32 = screenHeightF - @as(f32, @floatFromInt(mapHeight)) * canvasZoom;

    if (canvasOffsetX > 0) canvasOffsetX = 0;
    if (canvasOffsetY > 0) canvasOffsetY = 0;
    if (canvasOffsetX < minMapOffsetX) canvasOffsetX = minMapOffsetX;
    if (canvasOffsetY < minMapOffsetY) canvasOffsetY = minMapOffsetY;

    // Just for debugging
    if ((keyInput & (1 << 9)) != 0) {
        std.debug.print("minMapOffsetX {}, minMapOffsetY {}, canvasOffsetX {}, canvasOffsetY {}.\n", .{ minMapOffsetX, minMapOffsetY, canvasOffsetX, canvasOffsetY });
    }
}

/// Draws map and grid markers relative to current canvas
pub fn drawMap() void {
    // Draw the entire map area
    utils.drawRect(0, 0, mapWidth, mapHeight, rl.Color.ray_white);

    // Draw grid
    for (1..gameGrid.cells.len) |rowIndex| {
        utils.drawRect(0, @as(i32, @intCast(utils.Grid.CellSize * rowIndex)), mapWidth, 5, rl.Color.light_gray);
    }
    for (1..gameGrid.cells[0].len) |colIndex| {
        utils.drawRect(@as(i32, @intCast(utils.Grid.CellSize * colIndex)), 0, 5, mapHeight, rl.Color.light_gray);
    }

    // Draw the edges of the map
    utils.drawRect(0, -10, mapWidth, 20, rl.Color.dark_gray); // Top edge
    utils.drawRect(0, mapHeight - 10, mapWidth, 20, rl.Color.dark_gray); // Bottom edge
    utils.drawRect(-10, 0, 20, mapHeight, rl.Color.dark_gray); // Left edge
    utils.drawRect(mapWidth - 10, 0, 20, mapHeight, rl.Color.dark_gray); // Right edge

}

fn drawEntities() void {
    for (entity.players.items) |player| player.draw();
    for (entity.units.items) |unit| unit.draw();
    for (entity.structures.items) |structure| structure.draw();
}

/// Draws user interface
pub fn drawUI() void {
    rl.drawFPS(40, 40);
}

pub fn setMapSize(width: i32, height: i32) void {
    mapWidth = width;
    mapHeight = height;
    // Calculates max zoom out allowed without visibility transgressing map
    maxZoomOut = if (screenWidth > screenHeight) @as(f32, @floatFromInt(screenWidth)) / @as(f32, @floatFromInt(mapWidth)) else @as(f32, @floatFromInt(screenHeight)) / @as(f32, @floatFromInt(mapHeight));
}

// Game conditions
//----------------------------------------------------------------------------------
pub fn startingLocations(allocator: std.mem.Allocator, playerAmount: u8) ![]utils.Point {
    const coordinates: [4]utils.Point = [_]utils.Point{
        utils.Point{ .x = 100, .y = 100 },
        utils.Point{ .x = mapWidth - 100, .y = mapHeight - 100 },
        utils.Point{ .x = mapWidth - 100, .y = 100 },
        utils.Point{ .x = 100, .y = mapHeight - 100 },
    };

    // Allocate memory for the slice
    const slice = try allocator.alloc(utils.Point, playerAmount);
    for (slice, 0..) |*coord, i| {
        coord.* = coordinates[i];
    }

    // Debug prints to verify slice before returning
    std.debug.print("Returning coordinates for {} players\n", .{playerAmount});
    for (slice) |coord| {
        std.debug.print("({}, {})\n", .{ coord.x, coord.y });
    }

    return slice;
}
