const rl = @import("raylib");
const std: type = @import("std");
const utils = @import("utils.zig");
const entity = @import("entity.zig");

// Config
pub const ENTITY_SEARCH_LIMIT = 400;
pub const TICKRATE = 60;
pub const TICK_DURATION: f64 = 1.0 / @as(f64, @floatFromInt(TICKRATE));
pub const MAX_TICKS_PER_FRAME = 4;
pub var prevTickTime: f64 = 0.0;
pub var frameCount: i64 = 0;

// Camera movement
pub const SCROLL_SPEED: f16 = 25.0;
pub var screenWidth: i16 = 1920;
pub var screenHeight: i16 = 1080;
pub var canvasOffsetX: f32 = 0.0;
pub var canvasOffsetY: f32 = 0.0;
pub var canvasZoom: f32 = 1.0;
pub var maxZoomOut: f32 = 1.0; // Recalculated in setMapSize() for max map visibility

// Game map
const STARTING_MAP_WIDTH = 1920 * 8;
const STARTING_MAP_HEIGHT = 1080 * 8;
pub const GRID_CELL_SIZE = 256;
pub var mapWidth: i32 = 0;
pub var mapHeight: i32 = 0;
pub var gameGrid: entity.Grid = undefined;
pub var gamePlayer: *entity.Player = undefined;

pub fn main() anyerror!void {

    // Memory initialization
    //--------------------------------------------------------------------------------------
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // Initialize window
    //--------------------------------------------------------------------------------------
    rl.initWindow(screenWidth, screenHeight, "Conquest");
    defer rl.closeWindow(); // Close window and OpenGL context
    // rl.toggleFullscreen();
    rl.setTargetFPS(120);

    // Initialize utility
    //--------------------------------------------------------------------------------------
    utils.rngInit();
    var accumulatedMouseWheel: f32 = 0.0;
    var accumulatedKeyInput: u32 = 0;

    // Initialize map
    //--------------------------------------------------------------------------------------
    setMapSize(STARTING_MAP_WIDTH, STARTING_MAP_HEIGHT);
    // Define grid dimensions
    const gridWidth: usize = @intCast(utils.ceilDiv(mapWidth, utils.Grid.CellSize));
    const gridHeight: usize = @intCast(utils.ceilDiv(mapHeight, utils.Grid.CellSize));

    std.debug.print("Grid Width: {}, Grid Height: {}\n", .{ gridWidth, gridHeight });
    std.debug.print("Map Width: {}, Map Height: {}, Cell Size: {}\n", .{ mapWidth, mapHeight, utils.Grid.CellSize });

    // Initialize the grid
    try gameGrid.init(allocator);
    defer gameGrid.deinit();

    // Initialize entities
    //--------------------------------------------------------------------------------------
    entity.players = std.ArrayList(*entity.Player).init(allocator);
    entity.units = std.ArrayList(*entity.Unit).init(allocator);
    entity.structures = std.ArrayList(*entity.Structure).init(allocator);

    const startCoords = try startingLocations(allocator, 1); // 1 player
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

    // Testing/debugging
    try entity.structures.append(try entity.Structure.create(1225, 1225, 0));
    //try entity.units.append(try entity.Unit.create(2500, 1500, 0));
    //for (0..1000) |_| {
    //    try entity.structures.append(try entity.Structure.create(utils.randomInt(mapWidth), utils.randomInt(mapHeight), @as(u8, @intCast(utils.randomInt(3)))));
    //}

    utils.testHashFunction();

    defer entity.players.deinit();
    defer entity.units.deinit();
    defer entity.structures.deinit();

    // Main game loop
    //--------------------------------------------------------------------------------------
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key

        // Input
        //----------------------------------------------------------------------------------
        processInput(&accumulatedMouseWheel, &accumulatedKeyInput);

        // Logic
        //----------------------------------------------------------------------------------

        const currentTime: f64 = rl.getTime();
        var elapsedTime: f64 = currentTime - prevTickTime;

        var updatesPerformed: usize = 0;

        // Perform updates if enough time has elapsed
        while (elapsedTime >= TICK_DURATION) {
            try updateLogic(accumulatedMouseWheel, accumulatedKeyInput);
            accumulatedMouseWheel = 0.0;
            accumulatedKeyInput = 0;

            elapsedTime -= TICK_DURATION;
            updatesPerformed += 1;

            if (updatesPerformed >= MAX_TICKS_PER_FRAME) {
                break; // Prevent too much work per frame
            }
        }

        prevTickTime += @as(f64, @floatFromInt(updatesPerformed)) * TICK_DURATION;
        frameCount += 1;

        // Debugging/testing
        if (utils.perFrame(120)) {
            utils.printGridEntities(&gameGrid);
            utils.printGridCells(&gameGrid);
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
    if (rl.isKeyPressed(rl.KeyboardKey.key_one)) accumulatedKeyInput.* |= 1 << 4;
    if (rl.isKeyPressed(rl.KeyboardKey.key_two)) accumulatedKeyInput.* |= 1 << 5;
    if (rl.isKeyPressed(rl.KeyboardKey.key_three)) accumulatedKeyInput.* |= 1 << 6;
    if (rl.isKeyPressed(rl.KeyboardKey.key_four)) accumulatedKeyInput.* |= 1 << 7;
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
        const canvasMouseXBeforeZoom = (mouseX - canvasOffsetX) / oldZoom;
        const canvasMouseYBeforeZoom = (mouseY - canvasOffsetY) / oldZoom;
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
    const effectiveScrollSpeed: f32 = @as(f32, @floatCast(SCROLL_SPEED)) / @max(1, canvasZoom * 0.1);

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
}

/// Draws map and grid markers relative to current canvas
pub fn drawMap() void {
    // Draw the map area
    utils.drawRect(0, 0, mapWidth, mapHeight, rl.Color.ray_white);
    // Draw grid lines
    var rowIndex: i32 = 1;
    while (rowIndex * utils.Grid.CellSize < mapHeight) : (rowIndex += 1) {
        utils.drawRect(0, @as(i32, @intCast(utils.Grid.CellSize * rowIndex)), mapWidth, 5, rl.Color.light_gray);
    }
    var colIndex: i32 = 1;
    while (colIndex * utils.Grid.CellSize < mapWidth) : (colIndex += 1) {
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
    const offset = utils.Grid.CellSize * 3;
    const coordinates: [4]utils.Point = [_]utils.Point{
        utils.Point{ .x = offset, .y = offset },
        utils.Point{ .x = mapWidth - offset, .y = mapHeight - offset },
        utils.Point{ .x = mapWidth - offset, .y = offset },
        utils.Point{ .x = offset, .y = mapHeight - offset },
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
