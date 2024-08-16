const rl = @import("raylib");
const std: type = @import("std");
const utils = @import("utils.zig");
const entity = @import("entity.zig");

// Config
pub const TICKRATE = 60;
pub const TICK_DURATION: f64 = 1.0 / @as(f64, @floatFromInt(TICKRATE));
pub const MAX_TICKS_PER_FRAME = 1;
pub const PLAYER_SEARCH_LIMIT = 512; // Player collision limit, must exceed #entities in 3x3 cells
pub const UNIT_SEARCH_LIMIT = 256; // Unit collision limit
pub const BUFFERSIZE = 1600; // Limit to number of entities updated via sectionSearch per tick
pub var last_tick_time: f64 = 0.0;
pub var frame_count: u64 = 0;
pub var profile_mode = false;
pub var profile_timer = [4]f64{ 0, 0, 0, 0 };
pub var keys: utils.Key = undefined; // Keybindings

// Camera
pub const SCROLL_SPEED: f16 = 25.0;
pub var screen_width: i16 = 1920;
pub var screen_height: i16 = 1080;
pub var canvas_offset_x: f32 = 0.0;
pub var canvas_offset_y: f32 = 0.0;
pub var canvas_zoom: f32 = 1.0;
pub var canvas_max: f32 = 1.0; // Recalculated in setMapSize() for max map visibility

// World
const STARTING_MAP_WIDTH = 1920 * 8; // Limit for u16 coordinates: 65535
const STARTING_MAP_HEIGHT = 1080 * 8; // Limit for u16 coordinates: 65535
pub const GRID_CELL_SIZE = 400; //512;
pub var map_width: u16 = 0;
pub var map_height: u16 = 0;
pub var grid: entity.Grid = undefined;
pub var player: *entity.Player = undefined;

pub fn main() anyerror!void {

    // Memory initialization
    //--------------------------------------------------------------------------------------
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();

    // Initialize window
    //--------------------------------------------------------------------------------------
    rl.initWindow(screen_width, screen_height, "Conquest");
    defer rl.closeWindow(); // Close window and OpenGL context

    const flags = rl.ConfigFlags{
        .fullscreen_mode = false,
        .window_resizable = true,
        .window_undecorated = false, // Removes window border
        .window_transparent = false,
        .msaa_4x_hint = false,
        .vsync_hint = false,
        .window_hidden = false,
        .window_always_run = false,
        .window_minimized = false,
        .window_maximized = false,
        .window_unfocused = false,
        .window_topmost = false,
        .window_highdpi = false,
        .window_mouse_passthrough = false,
        .borderless_windowed_mode = false,
        .interlaced_hint = false,
    };
    rl.setWindowState(flags);
    //rl.setWindowSize(screen_width, screen_height);
    //rl.setTargetFPS(60);
    //rl.toggleFullscreen();

    // Initialize utility
    //--------------------------------------------------------------------------------------
    utils.rngInit();
    var stored_mousewheel: f32 = 0.0;
    var stored_key_input: u32 = 0;

    // Initialize map
    //--------------------------------------------------------------------------------------
    setMapSize(STARTING_MAP_WIDTH, STARTING_MAP_HEIGHT);
    // Define grid dimensions
    const gridWidth: usize = @intCast(utils.ceilDiv(map_width, utils.Grid.cell_size));
    const gridHeight: usize = @intCast(utils.ceilDiv(map_height, utils.Grid.cell_size));

    std.debug.print("Grid Width: {}, Grid Height: {}\n", .{ gridWidth, gridHeight });
    std.debug.print("Map Width: {}, Map Height: {}, Cell Size: {}\n", .{ map_width, map_height, utils.Grid.cell_size });

    // Initialize the grid
    try grid.init(&allocator, gridWidth, gridHeight, BUFFERSIZE);
    const cellsigns_cache = try allocator.alloc(u32, grid.columns * grid.rows);
    defer grid.deinit(&allocator);

    // Initialize entities
    //--------------------------------------------------------------------------------------
    entity.players = std.ArrayList(*entity.Player).init(allocator);
    entity.structures = std.ArrayList(*entity.Structure).init(allocator);
    entity.units = std.ArrayList(*entity.Unit).init(allocator);

    const startCoords = try startingLocations(&allocator, 1); // 1 player
    for (startCoords, 0..) |coord, i| {
        std.debug.print("Player starting at: ({}, {})\n", .{ coord.x, coord.y });
        if (i == 0) {
            const local = try entity.Player.createLocal(coord.x, coord.y);
            try entity.players.append(local);
            player = local; // Sets player to local player pointer
        } else {
            const remote = try entity.Player.createRemote(coord.x, coord.y);
            try entity.players.append(remote);
        }
    }
    allocator.free(startCoords); // Freeing starting positions

    // Testing/debugging
    const SPREAD = 75; // PERCENTAGE
    const rangeX: u16 = @intCast(@divTrunc(@as(i32, @intCast(map_width)) * SPREAD, 100));
    const rangeY: u16 = @intCast(@divTrunc(@as(i32, @intCast(map_height)) * SPREAD, 100));

    //try entity.structures.append(try entity.Structure.create(1225, 1225, 0));
    //try entity.units.append(try entity.Unit.create(2500, 1500, 0));
    //for (0..5000) |_| {
    //    try entity.units.append(try entity.Unit.create(utils.randomU16(rangeX) + @divTrunc(map_width - rangeX, 2), utils.randomU16(rangeY) + @divTrunc(map_height - rangeY, 2), @as(u8, @intCast(utils.randomU16(3)))));
    //}
    for (0..0) |_| {
        _ = entity.Structure.build(utils.randomU16(rangeX) + @divTrunc(map_width - rangeX, 2), utils.randomU16(rangeY) + @divTrunc(map_height - rangeY, 2), @as(u8, @intCast(utils.randomU16(3))));
    }

    defer entity.units.deinit();
    defer entity.structures.deinit();
    defer entity.players.deinit();

    // Initialize user interface
    //--------------------------------------------------------------------------------------
    try keys.init(&allocator); // Initializes and activates default keybindings
    utils.canvasOnPlayer(); // Centers camera

    // Main game loop
    //--------------------------------------------------------------------------------------
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key

        // Profiling
        //----------------------------------------------------------------------------------
        const profile_frame = (profile_mode and utils.perFrame(45));
        if (profile_frame) {
            utils.startTimer(3, "\nSTART OF FRAME :::");
            std.debug.print("{}.\n\n", .{frame_count});
        }

        // Input
        //----------------------------------------------------------------------------------
        if (profile_frame) utils.startTimer(0, "INPUT PHASE.\n");
        if (profile_frame) utils.startTimer(1, "- Processing input.");
        processInput(&stored_mousewheel, &stored_key_input);
        if (profile_frame) utils.endTimer(1, "Processing input took {} seconds.");
        if (profile_frame) utils.endTimer(0, "Input phase took {} seconds in total.\n");

        // Logic
        //----------------------------------------------------------------------------------
        if (profile_frame) utils.startTimer(0, "LOGIC PHASE.\n");

        const currentTime: f64 = rl.getTime();
        var elapsedTime: f64 = currentTime - last_tick_time;
        var updatesPerformed: usize = 0;

        if (profile_frame and elapsedTime < TICK_DURATION) std.debug.print("- Elapsed time < tick duration, skipping logic update this frame.\n", .{});

        // Perform updates if enough time has elapsed
        while (elapsedTime >= TICK_DURATION) {
            if (profile_frame) utils.startTimer(1, "- Updating cell signatures.");
            grid.updateCellsigns(); // Updates Grid.cellsigns array
            if (profile_frame) utils.endTimer(1, "Updating cell signatures took {} seconds.");
            if (profile_frame) utils.startTimer(1, "- Updating grid sections.");
            grid.updateSections(cellsigns_cache); // Updates Grid.sections array by cellsign comparison
            if (profile_frame) utils.endTimer(1, "Updating grid sections took {} seconds.");

            try updateLogic(stored_key_input, profile_frame);

            updateControls(stored_mousewheel, stored_key_input, profile_frame);

            stored_mousewheel = 0.0;
            stored_key_input = 0;

            elapsedTime -= TICK_DURATION;
            updatesPerformed += 1;

            if (updatesPerformed >= MAX_TICKS_PER_FRAME) {
                break; // Prevent too much work per frame
            }
        }

        last_tick_time += @as(f64, @floatFromInt(updatesPerformed)) * TICK_DURATION;
        frame_count += 1;

        if (profile_frame) utils.endTimer(0, "Logic phase took {} seconds in total.\n");

        // Drawing
        //----------------------------------------------------------------------------------
        if (profile_frame) utils.startTimer(0, "DRAWING PHASE.\n");

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.white);
        draw(profile_frame);
        if (profile_frame) utils.endTimer(0, "Drawing phase took {} seconds in total.\n");

        // Profiling
        if (profile_frame) {
            utils.endTimer(3, "END OF FRAME ::: {} seconds in total.\n");
            std.debug.print("Current FPS: {}.\n", .{rl.getFPS()});
            utils.printGridEntities(&grid);
            utils.printGridCells(&grid);
        }
    }
}

fn processInput(stored_mousewheel: *f32, stored_key_input: *u32) void {
    stored_mousewheel.* += rl.getMouseWheelMove();

    // Build keys bitmasking
    if (rl.isKeyPressed(rl.KeyboardKey.key_one)) stored_key_input.* |= @intFromEnum(utils.Key.InputValue.One);
    if (rl.isKeyPressed(rl.KeyboardKey.key_two)) stored_key_input.* |= @intFromEnum(utils.Key.InputValue.Two);
    if (rl.isKeyPressed(rl.KeyboardKey.key_three)) stored_key_input.* |= @intFromEnum(utils.Key.InputValue.Three);
    if (rl.isKeyPressed(rl.KeyboardKey.key_four)) stored_key_input.* |= @intFromEnum(utils.Key.InputValue.Four);

    // Move keys bitmasking
    if (rl.isKeyDown(rl.KeyboardKey.key_w) or rl.isKeyDown(rl.KeyboardKey.key_up)) stored_key_input.* |= @intFromEnum(utils.Key.InputValue.Up);
    if (rl.isKeyDown(rl.KeyboardKey.key_a) or rl.isKeyDown(rl.KeyboardKey.key_left)) stored_key_input.* |= @intFromEnum(utils.Key.InputValue.Left);
    if (rl.isKeyDown(rl.KeyboardKey.key_s) or rl.isKeyDown(rl.KeyboardKey.key_down)) stored_key_input.* |= @intFromEnum(utils.Key.InputValue.Down);
    if (rl.isKeyDown(rl.KeyboardKey.key_d) or rl.isKeyDown(rl.KeyboardKey.key_right)) stored_key_input.* |= @intFromEnum(utils.Key.InputValue.Right);

    // Special keys bitmasking
    if (rl.isKeyDown(rl.KeyboardKey.key_space)) stored_key_input.* |= @intFromEnum(utils.Key.InputValue.Space);
    if (rl.isKeyPressed(rl.KeyboardKey.key_left_control) or rl.isKeyPressed(rl.KeyboardKey.key_right_control)) stored_key_input.* |= @intFromEnum(utils.Key.InputValue.Ctrl);
    if (rl.isKeyPressed(rl.KeyboardKey.key_enter) or rl.isKeyPressed(rl.KeyboardKey.key_kp_enter)) stored_key_input.* |= @intFromEnum(utils.Key.InputValue.Enter);
}

fn updateControls(mousewheel_delta: f32, key_input: u32, profile_frame: bool) void {
    if (profile_frame) utils.startTimer(1, "- Updating controls.");
    updateCanvasZoom(mousewheel_delta);
    updateCanvasPosition(key_input);
    if (keys.actionActive(key_input, utils.Key.Action.SpecialEnter)) profile_mode = !profile_mode; // Enter toggles profile mode (verbose logs) for now
    if (profile_frame) utils.endTimer(1, "Updating controls took {} seconds.");
}

fn updateLogic(key_input: u32, profile_frame: bool) !void {
    if (profile_frame) utils.startTimer(1, "- Updating units.");
    for (entity.units.items) |unit| {
        try unit.update();
    }
    if (profile_frame) utils.endTimer(1, "Updating units took {} seconds.");
    if (profile_frame) utils.startTimer(1, "- Updating structures.");
    for (entity.structures.items) |structure| {
        structure.update();
    }
    if (profile_frame) utils.endTimer(1, "Updating structures took {} seconds.");
    if (profile_frame) utils.startTimer(1, "- Updating players.");
    for (entity.players.items) |p| {
        if (p == player) {
            try p.update(key_input);
        } else {
            try p.update(null);
        }
    }
    if (profile_frame) utils.endTimer(1, "Updating players took {} seconds.");
}

fn draw(profile_frame: bool) void {
    if (profile_frame) utils.startTimer(1, "- Drawing map.");
    drawMap();
    if (profile_frame) utils.endTimer(1, "Drawing map took {} seconds.");
    if (profile_frame) utils.startTimer(1, "- Drawing entities.");
    drawEntities();
    if (profile_frame) utils.endTimer(1, "Drawing entities took {} seconds.");
    if (profile_frame) utils.startTimer(1, "- Drawing UI.");
    drawUI();
    if (profile_frame) utils.endTimer(1, "Drawing UI took {} seconds.");
}

pub fn updateCanvasZoom(mousewheel_delta: f32) void {
    canvas_max = utils.maxCanvasSize(rl.getScreenWidth(), rl.getScreenHeight(), map_width, map_height); // For window resizing
    if (mousewheel_delta != 0) {
        const old_zoom: f32 = canvas_zoom;
        const zoom_change: f32 = 1 + (0.025 * mousewheel_delta); // zoom rate
        canvas_zoom = @min(@max(canvas_max, canvas_zoom * zoom_change), 10.0); // From <1 (full map) to 10 (zoomed in)

        // Adjust offsets to zoom around the mouse position
        const mouse_x = @as(f32, @floatFromInt(rl.getMouseX()));
        const mouse_y = @as(f32, @floatFromInt(rl.getMouseY()));
        const canvas_mouse_x_old_zoom = (mouse_x - canvas_offset_x) / old_zoom;
        const canvas_mouse_y_old_zoom = (mouse_y - canvas_offset_y) / old_zoom;
        const canvas_mouse_x_new_zoom = (mouse_x - canvas_offset_x) / canvas_zoom;
        const canvas_mouse_y_new_zoom = (mouse_y - canvas_offset_y) / canvas_zoom;

        // Adjust offsets to keep the mouse position consistent
        canvas_offset_x += @floatCast((canvas_mouse_x_new_zoom - canvas_mouse_x_old_zoom) * canvas_zoom);
        canvas_offset_y += @floatCast((canvas_mouse_y_new_zoom - canvas_mouse_y_old_zoom) * canvas_zoom);
    }
}

pub fn updateCanvasPosition(key_input: u32) void {
    const mouse_x = @as(f32, @floatFromInt(rl.getMouseX()));
    const mouse_y = @as(f32, @floatFromInt(rl.getMouseY()));
    const screen_width_float = @as(f32, @floatFromInt(rl.getScreenWidth()));
    const screen_height_float = @as(f32, @floatFromInt(rl.getScreenHeight()));
    const margin_w: f32 = screen_width_float / 10.0;
    const margin_h: f32 = screen_height_float / 10.0;
    const effective_speed: f32 = @as(f32, @floatCast(SCROLL_SPEED)) / @max(1, canvas_zoom * 0.1);

    if ((key_input & (1 << 9)) != 0) {
        // Space key centers camera on player
        utils.canvasOnPlayer();
        //canvas_offset_x = -(@as(f32, @floatFromInt(player.x)) * canvas_zoom) + (screen_width_float / 2);
        //canvas_offset_y = -(@as(f32, @floatFromInt(player.y)) * canvas_zoom) + (screen_height_float / 2);
    } else {
        // Mouse edge scrolls camera
        if (mouse_x < margin_w) {
            const factor = 1.0 - (mouse_x / margin_w);
            canvas_offset_x += effective_speed * factor;
        }
        if (mouse_x > screen_width_float - margin_w) {
            const factor = 1.0 - ((screen_width_float - mouse_x) / margin_w);
            canvas_offset_x -= effective_speed * factor;
        }
        if (mouse_y < margin_h) {
            const factor = 1.0 - (mouse_y / margin_h);
            canvas_offset_y += effective_speed * factor;
        }
        if (mouse_y > screen_height_float - margin_h) {
            const factor = 1.0 - ((screen_height_float - mouse_y) / margin_h);
            canvas_offset_y -= effective_speed * factor;
        }
    }

    // Restrict canvas to map bounds
    const min_offset_x: f32 = screen_width_float - @as(f32, @floatFromInt(map_width)) * canvas_zoom;
    const min_offset_y: f32 = screen_height_float - @as(f32, @floatFromInt(map_height)) * canvas_zoom;

    if (canvas_offset_x > 0) canvas_offset_x = 0;
    if (canvas_offset_y > 0) canvas_offset_y = 0;
    if (canvas_offset_x < min_offset_x) canvas_offset_x = min_offset_x;
    if (canvas_offset_y < min_offset_y) canvas_offset_y = min_offset_y;
}

/// Draws map and grid markers relative to current canvas
pub fn drawMap() void {
    // Draw the map area
    utils.drawRect(0, 0, map_width, map_height, rl.Color.dark_gray);
    // Draw grid lines
    var rowIndex: i32 = 1;
    while (rowIndex * utils.Grid.cell_size < map_height) : (rowIndex += 1) {
        utils.drawRect(0, @as(i32, @intCast(utils.Grid.cell_size * rowIndex)), map_width, 5, rl.Color.light_gray);
    }
    var colIndex: i32 = 1;
    while (colIndex * utils.Grid.cell_size < map_width) : (colIndex += 1) {
        utils.drawRect(@as(i32, @intCast(utils.Grid.cell_size * colIndex)), 0, 5, map_height, rl.Color.light_gray);
    }
    // Draw the edges of the map
    utils.drawRect(0, -10, map_width, 20, rl.Color.dark_gray); // Top edge
    utils.drawRect(0, map_height - 10, map_width, 20, rl.Color.dark_gray); // Bottom edge
    utils.drawRect(-10, 0, 20, map_height, rl.Color.dark_gray); // Left edge
    utils.drawRect(map_width - 10, 0, 20, map_height, rl.Color.dark_gray); // Right edge

}

fn drawEntities() void {
    for (entity.units.items) |u| u.draw();
    for (entity.structures.items) |s| s.draw();
    for (entity.players.items) |p| p.draw();
}

/// Draws user interface
pub fn drawUI() void {
    rl.drawFPS(40, 40);
}

/// Sets map dimensions and updates the camera zoom out limit.
pub fn setMapSize(width: u16, height: u16) void {
    map_width = width;
    map_height = height;
    canvas_max = utils.maxCanvasSize(rl.getScreenWidth(), rl.getScreenHeight(), map_width, map_height);
}

// Game conditions
//----------------------------------------------------------------------------------
pub fn startingLocations(allocator: *std.mem.Allocator, player_count: u8) ![]utils.Point {
    const offset = utils.Grid.cell_size * 3;
    const coordinates: [4]utils.Point = [_]utils.Point{
        utils.Point{ .x = offset, .y = offset },
        utils.Point{ .x = map_width - offset, .y = map_height - offset },
        utils.Point{ .x = map_width - offset, .y = offset },
        utils.Point{ .x = offset, .y = map_height - offset },
    };

    // Allocate memory for the slice
    const slice = try allocator.alloc(utils.Point, player_count);
    for (slice, 0..) |*coord, i| {
        coord.* = coordinates[i];
    }

    // Debug prints to verify slice before returning
    std.debug.print("Returning coordinates for {} players\n", .{player_count});
    for (slice) |coord| {
        std.debug.print("({}, {})\n", .{ coord.x, coord.y });
    }

    return slice;
}
