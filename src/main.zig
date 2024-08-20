const rl = @import("raylib");
const std: type = @import("std");
const u = @import("utils.zig");
const e = @import("entity.zig");

// Config
pub const Config = struct {
    pub const TICKRATE = 60;
    pub const TICK_DURATION: f64 = 1.0 / @as(f64, @floatFromInt(TICKRATE));
    pub const MAX_TICKS_PER_FRAME = 1;
    pub const PLAYER_SEARCH_LIMIT = 2056; // Player collision search limit, must exceed #entities in 3x3 cells
    pub const UNIT_SEARCH_LIMIT = 1028; // Unit collision search limit
    pub const BUFFERSIZE = 65536; // Limit to number of entities updated via sectionSearch per tick
    pub var last_tick_time: f64 = 0.0;
    pub var frame_number: u64 = 0;
    pub var profile_mode = false;
    pub var profile_timer = [4]f64{ 0, 0, 0, 0 };
    pub var keys: u.Key = undefined; // Keybindings
    pub var tick_number: u64 = undefined; // Ersatz server tick
};

// Camera
pub const SCROLL_SPEED: f16 = 25.0;
pub const SCROLL_RATE: f16 = 25.0; // use when setting canvas_offset_x/y target
pub const ZOOM_MAX = 10.0; // Larger number = further zoomed in
pub const ZOOM_SPEED: f16 = 0.25;
pub const ZOOM_RATE: f16 = 0.25;
pub var screen_width: i16 = 1920;
pub var screen_height: i16 = 1080;
pub var canvas_offset_x: f32 = 0.0;
pub var canvas_offset_y: f32 = 0.0;
pub var canvas_max: f32 = 1.0; // Recalculated in setMapSize for max map visibility
pub var canvas_zoom: f32 = 1.0;
var canvas_offset_x_target: f32 = 0.0;
var canvas_offset_y_target: f32 = 0.0;
var canvas_zoom_target: f32 = 1.0;

// Interface
pub var build_guide: ?u8 = null;
pub var selected: ?*e.Entity = null;

// World
const STARTING_MAP_WIDTH = 16000; // 1920 * 8; // Limit for u16 coordinates: 65535
const STARTING_MAP_HEIGHT = 16000; // 1080 * 8; // Limit for u16 coordinates: 65535
pub const GRID_CELL_SIZE = 1000;
pub const MOVEMENT_DIVISIONS = 10; // Modulus base for unit movement updates
pub var map_width: u16 = 0;
pub var map_height: u16 = 0;
pub var grid: e.Grid = undefined;
pub var player: *e.Player = undefined;
var dead_players: std.ArrayList(*e.Player) = undefined;
var dead_structures: std.ArrayList(*e.Structure) = undefined;
var dead_units: std.ArrayList(*e.Unit) = undefined;
var dead_resources: std.ArrayList(*e.Resource) = undefined;

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
    rl.setTargetFPS(120);

    // Initialize utility
    //--------------------------------------------------------------------------------------
    u.rngInit();
    Config.tick_number = 0; // <-- Here, would fetch value from server
    var stored_mouse_input: [2]rl.Vector2 = [2]rl.Vector2{ rl.Vector2.zero(), rl.Vector2.zero() };
    var stored_mousewheel: f32 = 0.0;
    var stored_key_input: u32 = 0;

    // Initialize map
    //--------------------------------------------------------------------------------------
    setMapSize(STARTING_MAP_WIDTH, STARTING_MAP_HEIGHT);
    // Define grid dimensions
    const gridWidth: usize = @intCast(u.ceilDiv(map_width, u.Grid.cell_size));
    const gridHeight: usize = @intCast(u.ceilDiv(map_height, u.Grid.cell_size));

    std.debug.print("Grid Width: {}, Grid Height: {}\n", .{ gridWidth, gridHeight });
    std.debug.print("Map Width: {}, Map Height: {}, Cell Size: {}\n", .{ map_width, map_height, u.Grid.cell_size });

    // Initialize the grid
    try grid.init(&allocator, gridWidth, gridHeight, Config.BUFFERSIZE);
    const cellsigns_cache = try allocator.alloc(u32, grid.columns * grid.rows);
    defer allocator.free(cellsigns_cache);
    defer grid.deinit(&allocator);

    // Initialize entities
    //--------------------------------------------------------------------------------------
    e.players = std.ArrayList(*e.Player).init(allocator);
    e.structures = std.ArrayList(*e.Structure).init(allocator);
    e.units = std.ArrayList(*e.Unit).init(allocator);
    e.resources = std.ArrayList(*e.Resource).init(allocator);
    dead_players = std.ArrayList(*e.Player).init(allocator);
    dead_structures = std.ArrayList(*e.Structure).init(allocator);
    dead_units = std.ArrayList(*e.Unit).init(allocator);
    dead_resources = std.ArrayList(*e.Resource).init(allocator);

    const startCoords = try startingLocations(&allocator, 2); // players
    for (startCoords, 0..) |coord, i| {
        std.debug.print("Player starting at: ({}, {})\n", .{ coord.x, coord.y });
        if (i == 0) {
            const local = try e.Player.createLocal(coord.x, coord.y);
            try e.players.append(local);
            player = local; // Sets player to local player pointer
        } else {
            const remote = try e.Player.createRemote(coord.x, coord.y);
            try e.players.append(remote);
        }
    }
    allocator.free(startCoords); // Freeing starting positions

    // Testing/debugging
    //--------------------------------------------------------------------------------------
    const SPREAD = 50; // PERCENTAGE
    const rangeX: u16 = @intCast(@divTrunc(@as(i32, @intCast(map_width)) * SPREAD, 100));
    const rangeY: u16 = @intCast(@divTrunc(@as(i32, @intCast(map_height)) * SPREAD, 100));

    //try e.structures.append(try e.Structure.create(1225, 1225, 0));
    //try e.units.append(try e.Unit.create(2500, 1500, 0));
    //for (0..5000) |_| {
    //    try e.units.append(try e.Unit.create(u.randomU16(rangeX) + @divTrunc(map_width - rangeX, 2), u.randomU16(rangeY) + @divTrunc(map_height - rangeY, 2), @as(u8, @intCast(u.randomU16(3)))));
    //}
    for (0..0) |_| {
        const class = @as(u8, @intCast(u.randomU16(3)));
        const xy = u.subcell.snapPosition(u.randomU16(rangeX) + @divTrunc(map_width - rangeX, 2), u.randomU16(rangeY) + @divTrunc(map_height - rangeY, 2), e.Structure.preset(class).width, e.Structure.preset(class).height);
        _ = e.Structure.construct(xy[0], xy[1], class);
    }

    defer e.units.deinit();
    defer e.structures.deinit();
    defer e.players.deinit();
    defer e.resources.deinit();
    defer dead_units.deinit();
    defer dead_structures.deinit();
    defer dead_players.deinit();
    defer dead_resources.deinit();

    // Initialize user interface
    //--------------------------------------------------------------------------------------
    try Config.keys.init(&allocator); // Initializes and activates default keybindings
    u.canvasOnPlayer(); // Centers camera

    // Main game loop
    //--------------------------------------------------------------------------------------
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key

        // Profiling
        //----------------------------------------------------------------------------------
        const profile_frame = (Config.profile_mode and u.perFrame(45));
        if (profile_frame) {
            u.startTimer(3, "\nSTART OF FRAME :::");
            std.debug.print("{} (TICK {}).\n\n", .{ Config.frame_number, Config.tick_number });
        }

        // Input
        //----------------------------------------------------------------------------------
        if (profile_frame) u.startTimer(0, "INPUT PHASE.\n");
        if (profile_frame) u.startTimer(1, "- Processing input.");
        processInput(&stored_mouse_input[0], &stored_mouse_input[1], &stored_mousewheel, &stored_key_input);
        if (profile_frame) u.endTimer(1, "Processing input took {} seconds.");
        if (profile_frame) u.endTimer(0, "Input phase took {} seconds in total.\n");

        // Logic
        //----------------------------------------------------------------------------------
        if (profile_frame) u.startTimer(0, "LOGIC PHASE.\n");

        var elapsed_time: f64 = rl.getTime() - Config.last_tick_time;
        var updates_performed: usize = 0;

        if (profile_frame and elapsed_time < Config.TICK_DURATION) std.debug.print("- Elapsed time < tick duration, skipping logic update this frame.\n", .{});

        // Perform updates if enough time has elapsed
        while (elapsed_time >= Config.TICK_DURATION) {
            try updateEntities(stored_key_input, profile_frame);
            if (profile_frame) u.startTimer(1, "- Removing dead entities.");
            try removeEntities();
            if (profile_frame) u.endTimer(1, "Removing dead entities took {} seconds.");

            if (profile_frame) u.startTimer(1, "- Updating cell signatures.");
            grid.updateCellsigns(); // Updates Grid.cellsigns array
            if (profile_frame) u.endTimer(1, "Updating cell signatures took {} seconds.");
            if (profile_frame) u.startTimer(1, "- Updating grid sections.");
            grid.updateSections(cellsigns_cache); // Updates Grid.sections array by cellsign comparison
            if (profile_frame) u.endTimer(1, "Updating grid sections took {} seconds.");

            updateControls(stored_mouse_input[0], stored_mouse_input[1], stored_mousewheel, stored_key_input, profile_frame);

            // Resetting input
            stored_mouse_input = [2]rl.Vector2{ rl.Vector2.zero(), rl.Vector2.zero() };
            stored_mousewheel = 0.0;
            stored_key_input = 0;

            elapsed_time -= Config.TICK_DURATION;
            updates_performed += 1;

            if (updates_performed >= Config.MAX_TICKS_PER_FRAME) {
                break; // Prevent too much work per frame
            }
        }

        Config.tick_number += updates_performed; // <-- tick_number is meant to be server side
        Config.last_tick_time += @as(f64, @floatFromInt(updates_performed)) * Config.TICK_DURATION;
        Config.frame_number += 1;

        if (profile_frame) u.endTimer(0, "Logic phase took {} seconds in total.\n");

        // Drawing
        //----------------------------------------------------------------------------------
        if (profile_frame) u.startTimer(0, "DRAWING PHASE.\n");

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.white);
        draw(profile_frame);
        if (profile_frame) u.endTimer(0, "Drawing phase took {} seconds in total.\n");

        // Profiling
        //----------------------------------------------------------------------------------
        if (profile_frame) {
            u.endTimer(3, "END OF FRAME ::: {} seconds in total.\n");
            std.debug.print("Current FPS: {}.\n", .{rl.getFPS()});
            u.printGridEntities(&grid);
            u.printGridCells(&grid);
        }
    }
}

fn processInput(stored_mouse_input_l: *rl.Vector2, stored_mouse_input_r: *rl.Vector2, stored_mousewheel: *f32, stored_key_input: *u32) void {
    if (build_guide != null) { // While build guide is active
        stored_mouse_input_l.* = rl.getMousePosition(); // Sets stored_mouse_input[0] to mouse position
        if (rl.isMouseButtonPressed(rl.MouseButton.mouse_button_left)) stored_key_input.* |= u.Key.inputFromAction(&Config.keys, u.Key.Action.BuildConfirm); // L mouse-click confirms build
        if (rl.isMouseButtonPressed(rl.MouseButton.mouse_button_right)) stored_mouse_input_r.y = 0.01; // R mouse-click cancels build
    } else { // Whenever build guide is not active
        if (rl.isMouseButtonPressed(rl.MouseButton.mouse_button_left)) stored_mouse_input_l.* = rl.getMousePosition(); // Sets stored_mouse_input[0] to position on left-click
        if (rl.isMouseButtonDown(rl.MouseButton.mouse_button_right)) stored_mouse_input_r.* = rl.getMouseDelta(); // Sets stored_mouse_input[1] to right-mouse down delta
    }
    stored_mousewheel.* += rl.getMouseWheelMove();

    // Number keys bitmasking
    if (rl.isKeyPressed(rl.KeyboardKey.key_z)) stored_key_input.* |= @intFromEnum(u.Key.InputValue.Z);
    if (rl.isKeyPressed(rl.KeyboardKey.key_one)) stored_key_input.* |= @intFromEnum(u.Key.InputValue.One);
    if (rl.isKeyPressed(rl.KeyboardKey.key_two)) stored_key_input.* |= @intFromEnum(u.Key.InputValue.Two);
    if (rl.isKeyPressed(rl.KeyboardKey.key_three)) stored_key_input.* |= @intFromEnum(u.Key.InputValue.Three);
    if (rl.isKeyPressed(rl.KeyboardKey.key_four)) stored_key_input.* |= @intFromEnum(u.Key.InputValue.Four);

    // Direction keys bitmasking
    if (rl.isKeyDown(rl.KeyboardKey.key_w) or rl.isKeyDown(rl.KeyboardKey.key_up)) stored_key_input.* |= @intFromEnum(u.Key.InputValue.Up);
    if (rl.isKeyDown(rl.KeyboardKey.key_a) or rl.isKeyDown(rl.KeyboardKey.key_left)) stored_key_input.* |= @intFromEnum(u.Key.InputValue.Left);
    if (rl.isKeyDown(rl.KeyboardKey.key_s) or rl.isKeyDown(rl.KeyboardKey.key_down)) stored_key_input.* |= @intFromEnum(u.Key.InputValue.Down);
    if (rl.isKeyDown(rl.KeyboardKey.key_d) or rl.isKeyDown(rl.KeyboardKey.key_right)) stored_key_input.* |= @intFromEnum(u.Key.InputValue.Right);

    // Special keys bitmasking
    if (rl.isKeyDown(rl.KeyboardKey.key_space)) stored_key_input.* |= @intFromEnum(u.Key.InputValue.Space);
    if (rl.isKeyPressed(rl.KeyboardKey.key_left_control) or rl.isKeyPressed(rl.KeyboardKey.key_right_control)) stored_key_input.* |= @intFromEnum(u.Key.InputValue.Ctrl);
    if (rl.isKeyPressed(rl.KeyboardKey.key_enter) or rl.isKeyPressed(rl.KeyboardKey.key_kp_enter)) stored_key_input.* |= @intFromEnum(u.Key.InputValue.Enter);
}

fn updateControls(stored_mouse_input_l: rl.Vector2, stored_mouse_input_r: rl.Vector2, mousewheel_delta: f32, key_input: u32, profile_frame: bool) void {
    if (profile_frame) u.startTimer(1, "- Updating controls.");
    if (build_guide != null) { // While build guide is active
        selected = null; // No selection
        if (stored_mouse_input_r.equals(rl.Vector2.zero()) == 0) { // If mouse right is pressed, cancels build guide
            build_guide = null;
        }
    } else { // Whenever build guide is inactive
        if (stored_mouse_input_l.equals(rl.Vector2.zero()) == 0) { // If mouse left is clicked, checks/stores selection
            const map_coords = u.screenToMap(stored_mouse_input_l);
            const at_mouse = grid.collidesWith(map_coords[0], map_coords[1], 1, 1, null) catch null;
            // Sets variable directly to entity or null
            if (at_mouse) |entity| {
                selected = if (entity != selected) entity else null;
                std.debug.print("Selected entity {}.\n", .{@intFromPtr(entity)});
            } else {
                selected = null;
                std.debug.print("Deselected entity.\n", .{});
            }
        }
    }
    updateCanvasZoom(mousewheel_delta);
    updateCanvasPosition(stored_mouse_input_r, key_input);
    if (Config.keys.actionActive(key_input, u.Key.Action.SpecialEnter)) Config.profile_mode = !Config.profile_mode; // Enter toggles profile mode (verbose logs) for now
    if (profile_frame) u.endTimer(1, "Updating controls took {} seconds.");
}

fn updateEntities(key_input: u32, profile_frame: bool) !void {
    // Reminder:
    // Entities rely on sectionSearch for collision, which retrieves a list from grid.sections.
    // The updateSections function is responsible for regenerating grid.sections based on the current state of grid.cells.
    // This means that any entity removed from grid.cells via grid.removeFromCell (e.g. removeEntities -> unit.remove -> grid.removeFromCell)
    // should no longer appear in grid.sections ***after*** updateSections has run. But have now added removeFromAllSections to unit.remove,
    // which ***should*** ensure that any reference is removed from the grid after removeEntities runs.

    // Players
    if (profile_frame) u.startTimer(1, "- Updating players.");
    for (e.players.items) |p| {
        // Life / lifecycle ?
        if (p == player) {
            try p.update(key_input);
        } else {
            try p.update(null);
        }
    }
    if (profile_frame) u.endTimer(1, "Updating players took {} seconds.");

    // Structures
    if (profile_frame) u.startTimer(1, "- Updating structures.");
    for (e.structures.items) |structure| {
        if (structure.life == -u.i16max) {
            try dead_structures.append(structure); // To be destroyed in removeEntities
        } else {
            structure.update();
        }
    }
    if (profile_frame) u.endTimer(1, "Updating structures took {} seconds.");

    // Units
    if (profile_frame) u.startTimer(1, "- Updating units.");
    for (e.units.items) |unit| {
        if (unit.life == -u.i16max) {
            try dead_units.append(unit); // To be destroyed in removeEntities
        } else {
            try unit.update();
        }
    }
    if (profile_frame) u.endTimer(1, "Updating units took {} seconds.");
}

fn removeEntities() !void {
    for (dead_units.items) |unit| { // Second: Destroys units that were marked for destruction
        //std.debug.print("Removing unit at address {}. Entity address {}.\n", .{ @intFromPtr(unit), @intFromPtr(unit.entity) });
        try unit.remove();
    }
    dead_units.clearAndFree();
}

fn draw(profile_frame: bool) void {
    if (profile_frame) u.startTimer(1, "- Drawing map.");
    drawMap();
    if (profile_frame) u.endTimer(1, "Drawing map took {} seconds.");
    if (profile_frame) u.startTimer(1, "- Drawing entities.");
    drawEntities();
    if (profile_frame) u.endTimer(1, "Drawing entities took {} seconds.");
    if (profile_frame) u.startTimer(1, "- Drawing UI.");
    drawInterface();
    if (profile_frame) u.endTimer(1, "Drawing UI took {} seconds.");
}

pub fn updateCanvasZoom(mousewheel_delta: f32) void {
    canvas_max = u.maxCanvasSize(rl.getScreenWidth(), rl.getScreenHeight(), map_width, map_height); // For window resizing
    canvas_zoom_target = std.math.clamp(canvas_zoom_target, canvas_max, ZOOM_MAX); // Re-sizes canvas to current window size
    if (mousewheel_delta != 0) {
        const zoom_change: f32 = 1 + (ZOOM_RATE * mousewheel_delta); // Zoom rate
        canvas_zoom_target = @min(@max(canvas_max, canvas_zoom * zoom_change), ZOOM_MAX); // From <1 (full map) to 10 (zoomed in)
    }
    if (canvas_zoom != canvas_zoom_target) {
        const old_zoom: f32 = canvas_zoom;
        const lerp_factor: f32 = ZOOM_SPEED;
        canvas_zoom = canvas_zoom + lerp_factor * (canvas_zoom_target - canvas_zoom);
        // If difference is very small, snaps to the target to avoid perpetual adjustments
        if (@abs(canvas_zoom - canvas_zoom_target) < 0.001) canvas_zoom = canvas_zoom_target;

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

pub fn updateCanvasPosition(mouse_input_r: rl.Vector2, key_input: u32) void {
    const mouse_x = @as(f32, @floatFromInt(rl.getMouseX()));
    const mouse_y = @as(f32, @floatFromInt(rl.getMouseY()));
    const screen_width_float = @as(f32, @floatFromInt(rl.getScreenWidth()));
    const screen_height_float = @as(f32, @floatFromInt(rl.getScreenHeight()));
    const margin_w: f32 = screen_width_float / 10.0;
    const margin_h: f32 = screen_height_float / 10.0;
    const effective_speed: f32 = @as(f32, @floatCast(SCROLL_SPEED)) / @max(1, canvas_zoom * 0.1);

    if ((key_input & (1 << 9)) != 0) { // Space key centers camera on player/selected
        if (selected == null) u.canvasOnPlayer() else u.canvasOnEntity(selected.?);
    } else if (mouse_input_r.x != 0 or mouse_input_r.y != 0) { // Right-button drags canvas
        canvas_offset_x += mouse_input_r.x * 2;
        canvas_offset_y += mouse_input_r.y * 2;
    } else { // Mouse edge scrolls camera
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
    u.drawRect(0, 0, map_width, map_height, rl.Color.ray_white);

    // Draw subgrid lines
    var rowIndex: i32 = 1;
    while (rowIndex * u.Subcell.size < map_height) : (rowIndex += 1) {
        u.drawRect(0, @as(i32, @intCast(u.Subcell.size * rowIndex)), map_width, 2, rl.Color.light_gray);
    }
    var colIndex: i32 = 1;
    while (colIndex * u.Subcell.size < map_width) : (colIndex += 1) {
        u.drawRect(@as(i32, @intCast(u.Subcell.size * colIndex)), 0, 2, map_height, rl.Color.light_gray);
    }

    // Draw grid lines
    rowIndex = 1;
    while (rowIndex * u.Grid.cell_size < map_height) : (rowIndex += 1) {
        u.drawRect(0, @as(i32, @intCast(u.Grid.cell_size * rowIndex)), map_width, 5, rl.Color.light_gray);
    }
    colIndex = 1;
    while (colIndex * u.Grid.cell_size < map_width) : (colIndex += 1) {
        u.drawRect(@as(i32, @intCast(u.Grid.cell_size * colIndex)), 0, 5, map_height, rl.Color.light_gray);
    }
    // Draw the edges of the map
    u.drawRect(0, -10, map_width, 20, rl.Color.dark_gray); // Top edge
    u.drawRect(0, map_height - 10, map_width, 20, rl.Color.dark_gray); // Bottom edge
    u.drawRect(-10, 0, 20, map_height, rl.Color.dark_gray); // Left edge
    u.drawRect(map_width - 10, 0, 20, map_height, rl.Color.dark_gray); // Right edge

}

fn drawEntities() void {
    if (selected == null) {
        for (e.units.items) |x| x.draw(1); // Interpolates
        for (e.structures.items) |x| x.draw(1);
        for (e.players.items) |x| x.draw(1);
        // resources ...
    } else {
        for (e.units.items) |x| if (x.entity == selected) x.draw(1) else x.draw(0.5);
        for (e.structures.items) |x| if (x.entity == selected) x.draw(1) else x.draw(0.5);
        for (e.players.items) |x| if (x.entity == selected) x.draw(1) else x.draw(0.5);
        // resources ...
    }
}

/// Draws user interface
pub fn drawInterface() void {
    if (build_guide != null) drawGuide(build_guide.?);

    // Development tools
    rl.drawFPS(40, 40);
}

/// Sets map dimensions and updates the camera zoom out limit.
pub fn setMapSize(width: u16, height: u16) void {
    map_width = width;
    map_height = height;
    canvas_max = u.maxCanvasSize(rl.getScreenWidth(), rl.getScreenHeight(), map_width, map_height);
}

// Game conditions
//----------------------------------------------------------------------------------
pub fn startingLocations(allocator: *std.mem.Allocator, player_count: u8) ![]u.Point {
    const offset = u.Grid.cell_size * 3;
    const coordinates: [4]u.Point = [_]u.Point{
        u.Point{ .x = offset, .y = offset },
        u.Point{ .x = map_width - offset, .y = map_height - offset },
        u.Point{ .x = map_width - offset, .y = offset },
        u.Point{ .x = offset, .y = map_height - offset },
    };

    // Allocate memory for the slice
    const slice = try allocator.alloc(u.Point, player_count);
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

pub fn moveDivision(life: i16) bool {
    return @rem(life, MOVEMENT_DIVISIONS) == 0;
}

pub fn executeBuild(class: u8) void {
    if (!isInBuildDistance()) return;
    const xy = findBuildPosition(class);
    const built = e.Structure.construct(xy[0], xy[1], class);
    if (built) |building| {
        std.debug.print("Structure built successfully: \n{}.\nPointer address of structure is: {}.\n", .{ building, @intFromPtr(building) });
        selected = building.entity; // A hack: sets selected to building to instantly deselect it (in updateControls) by the same click
    } else {
        std.debug.print("Failed to build structure\n", .{});
        // Handle the failure case, e.g., notify the player
    }
    build_guide = null;
}

fn findBuildPosition(class: u8) [2]u16 {
    const building = e.Structure.preset(class);
    const x_offset = u.asF32(u16, u.Subcell.size) * canvas_zoom;
    const y_offset = u.asF32(u16, u.Subcell.size) * canvas_zoom;
    const mouse_position = rl.getMousePosition();

    const adjusted_position = mouse_position.add(rl.Vector2.init(x_offset, y_offset));
    const subcell = u.screenToSubcell(adjusted_position);
    const snapped = u.Subcell.snapToNode(subcell.node.x, subcell.node.y, building.width, building.height);

    return [2]u16{ snapped[0], snapped[1] };
}

fn isInBuildDistance() bool {
    const subcell_center = u.screenToSubcell(rl.getMousePosition()).center();
    const distance_max = u.Grid.cell_half; //u.asU32(u16, e.Structure.preset(class).width + e.Structure.preset(class).height);
    const distance = std.math.sqrt(u.distanceSquared(u.Point.at(player.x, player.y), u.Point.at(subcell_center[0], subcell_center[1])));
    return distance <= distance_max;
}

pub fn drawGuide(class: u8) void {
    const xy = findBuildPosition(class);
    const building = e.Structure.preset(class);
    const collides = grid.collidesWith(xy[0], xy[1], building.width, building.height, null) catch null;
    if (collides != null or !isInBuildDistance() or !u.isInMap(xy[0], xy[1], building.width, building.height)) {
        u.drawGuideFail(xy[0], xy[1], building.width, building.height, building.color);
    } else {
        u.drawGuide(xy[0], xy[1], building.width, building.height, building.color);
    }
}
