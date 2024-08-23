const rl = @import("raylib");
const std: type = @import("std");
const u = @import("utils.zig");
const e = @import("entity.zig");

/// The local player's game config properties. Const values are universal, var values vary with play session.
pub const Config = struct {
    pub const TICKRATE = 60; // Target logical fps
    pub const TICK_DURATION: f64 = 1.0 / @as(f64, @floatFromInt(TICKRATE));
    pub const MAX_TICKS_PER_FRAME = 1;
    pub const PLAYER_SEARCH_LIMIT = 2056; // Player collision search limit, must exceed #entities in 3x3 cells
    pub const UNIT_SEARCH_LIMIT = 1028; // Unit collision search limit
    pub const BUFFERSIZE = 65536; // Limit to number of entities updated via sectionSearch per tick
    pub var last_tick_time: f64 = 0.0;
    pub var profile_mode = false;
    pub var profile_timer = [4]f64{ 0, 0, 0, 0 };
    pub var keys: u.Key = undefined; // Keybindings
    pub var game_active = true;
};

/// The local player's camera properties. Const values are universal, var values vary with play session.
pub const Camera = struct {
    pub const SCROLL_RATE: f16 = 25.0; // Camera move effect size
    pub const SCROLL_SPEED: f16 = 0.25; // Camera move interpolation speed
    pub const ZOOM_RATE: f16 = 0.25; // Camera zoom effect size
    pub const ZOOM_SPEED: f16 = 0.25; // Camera zoom interpolation speed
    pub const ZOOM_MAX = 10.0; // Maximum zoom-in level
    pub var frame_number: u64 = 0;
    pub var width: i32 = 1920 * 2;
    pub var height: i32 = 1080 * 2;
    pub var canvas_max: f32 = 1.0; // Recalculated in setMapSize for max map visibility
    pub var canvas_zoom: f32 = 1.0;
    pub var canvas_zoom_target: f32 = 1.0;
    pub var canvas_offset_x: f32 = 0.0;
    pub var canvas_offset_y: f32 = 0.0;
    pub var canvas_offset_x_target: f32 = 0.0;
    pub var canvas_offset_y_target: f32 = 0.0;

    /// Sets camera `x` offset and target `x` offset.
    pub fn setX(x: f32) void {
        canvas_offset_x_target = x;
        canvas_offset_x = x;
    }
    /// Sets camera `y` offset and target `y` offset.
    pub fn setY(y: f32) void {
        canvas_offset_y_target = y;
        canvas_offset_y = y;
    }
};

/// The local player data. Delivers varying properties from the client to the shared world state.
pub const Player = struct {
    pub var self: ?*e.Player = null;
    pub var id: ?u8 = null;
    pub var selected: ?*e.Entity = null;
    pub var changed_x: ?u16 = null;
    pub var changed_y: ?u16 = null;
    pub var build_guide: ?u8 = null;
    pub var build_index: ?u8 = null;
    pub var build_order: ?u8 = null;
};

/// World properties, shared state initialized by initializeMap.
pub const World = struct {
    const DEFAULT_WIDTH = 16000 / 2; // 1920 * 8; // Limit for u16 coordinates: 65535
    const DEFAULT_HEIGHT = 16000 / 2; // 1080 * 8; // Limit for u16 coordinates: 65535
    pub const GRID_CELL_SIZE = 1000;
    pub const MOVEMENT_DIVISIONS = 10; // Modulus base for unit movement updates
    pub var tick_number: u64 = undefined; // Set upon map initialization
    pub var width: u16 = 0;
    pub var height: u16 = 0;
    pub var grid: e.Grid = undefined;
    pub var rng: std.Random.DefaultPrng = undefined;
    var dead_players: std.ArrayList(*e.Player) = undefined;
    var dead_structures: std.ArrayList(*e.Structure) = undefined;
    var dead_units: std.ArrayList(*e.Unit) = undefined;
    var dead_resources: std.ArrayList(*e.Resource) = undefined;

    fn initializeMap(allocator: *std.mem.Allocator, map: Map) !void {
        width = map.width;
        height = map.height;
        Camera.canvas_max = u.maxCanvasSize(rl.getScreenWidth(), rl.getScreenHeight(), width, height); // Updates camera zoom out limit

        // Initialize grid with derived dimensions
        const gridWidth: usize = @intCast(u.ceilDiv(width, u.Grid.cell_size));
        const gridHeight: usize = @intCast(u.ceilDiv(height, u.Grid.cell_size));
        std.debug.print("Grid Width: {}, Grid Height: {}\n", .{ gridWidth, gridHeight });
        std.debug.print("Map Width: {}, Map Height: {}, Cell Size: {}\n", .{ World.width, World.height, u.Grid.cell_size });
        grid.init(allocator, gridWidth, gridHeight, Config.BUFFERSIZE) catch return error.GridInitializationFailed;

        u.rngInit(map.id + width + height); // Initializes the RNG with the map id + width + height as the seed
        tick_number = 0; // Starts the shared tick counter

    }

    fn initializeEntities(allocator: std.mem.Allocator, map: Map) !void {
        e.players = std.ArrayList(*e.Player).init(allocator);
        e.structures = std.ArrayList(*e.Structure).init(allocator);
        e.units = std.ArrayList(*e.Unit).init(allocator);
        e.resources = std.ArrayList(*e.Resource).init(allocator);
        World.dead_players = std.ArrayList(*e.Player).init(allocator);
        World.dead_structures = std.ArrayList(*e.Structure).init(allocator);
        World.dead_units = std.ArrayList(*e.Unit).init(allocator);
        World.dead_resources = std.ArrayList(*e.Resource).init(allocator);

        const resource_coords = map.resource_locations;
        var resource: *e.Resource = undefined;
        defer allocator.free(resource_coords);
        for (resource_coords) |coord| {
            resource = try e.Resource.create(coord.x, coord.y, 0); // Creates class 0 resource
            try e.resources.append(resource);
        }
    }

    fn initializePlayers(allocator: *std.mem.Allocator, map: Map, self_id: u8) !void {
        const start_coords = map.start_locations;
        defer allocator.free(start_coords);
        var player: *e.Player = undefined;
        for (start_coords, 1..) |coord, i| { // IDs start at 1 (0 is neutral)
            if (i == self_id) {
                player = try e.Player.createLocal(coord.x, coord.y, u.asU8(usize, i));
                Player.self = player; // Sets player to local pointer
            } else {
                player = try e.Player.createRemote(coord.x, coord.y, u.asU8(usize, i));
            }

            try e.players.append(player);
            std.debug.print("Player {} starting at: ({}, {})\n", .{ i, coord.x, coord.y });
        }
    }
};

pub fn main() anyerror!void {

    // Memory initialization
    //--------------------------------------------------------------------------------------
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();

    // Initialize window
    //--------------------------------------------------------------------------------------
    Camera.width = rl.getMonitorWidth(0); // Sets window to (1st) monitor dimensions
    Camera.height = rl.getMonitorHeight(0); // Sets window to (1st) monitor dimensions
    rl.initWindow(Camera.width, Camera.height, "Conquest");
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

    //--------------------------------------------------------------------------------------
    // Game initialization (move to its own function/context)
    //--------------------------------------------------------------------------------------
    // Initialize player
    //--------------------------------------------------------------------------------------
    Player.id = 1; // obtain from server! u8 value corresponding to map's starting location

    // Initialize controls
    //--------------------------------------------------------------------------------------
    var stored_mouse_input: [2]rl.Vector2 = [2]rl.Vector2{ rl.Vector2.zero(), rl.Vector2.zero() };
    var stored_mousewheel: f32 = 0.0;
    var stored_key_input: u32 = 0;

    // Initialize map
    //--------------------------------------------------------------------------------------
    const map = try Map.open(&allocator, 0); // Opens default map and initializes world
    const cellsigns_cache = try allocator.alloc(u32, World.grid.columns * World.grid.rows);
    defer allocator.free(cellsigns_cache);
    defer World.grid.deinit(&allocator);
    try World.initializeEntities(allocator, map);
    try World.initializePlayers(&allocator, map, Player.id.?);

    // Testing/debugging
    //--------------------------------------------------------------------------------------
    const SPREAD = 50; // PERCENTAGE
    const rangeX: u16 = @intCast(@divTrunc(@as(i32, @intCast(World.width)) * SPREAD, 100));
    const rangeY: u16 = @intCast(@divTrunc(@as(i32, @intCast(World.height)) * SPREAD, 100));

    //try e.structures.append(try e.Structure.create(1225, 1225, 0));
    //try e.units.append(try e.Unit.create(2500, 1500, 0));
    //for (0..5000) |_| {
    //    try e.units.append(try e.Unit.create(u.randomU16(rangeX) + @divTrunc(World.width - rangeX, 2), u.randomU16(rangeY) + @divTrunc(World.height - rangeY, 2), @as(u8, @intCast(u.randomU16(3)))));
    //}
    for (0..1) |_| {
        const class = @as(u8, @intCast(u.randomU16(3)));
        const xy = u.Subcell.snapToNode(u.randomU16(rangeX) + @divTrunc(World.width - rangeX, 2), u.randomU16(rangeY) + @divTrunc(World.height - rangeY, 2), e.Structure.preset(class).width, e.Structure.preset(class).height);
        _ = e.Structure.construct(3, xy[0], xy[1], class);
    }

    defer e.units.deinit();
    defer e.structures.deinit();
    defer e.players.deinit();
    defer e.resources.deinit();
    defer World.dead_units.deinit();
    defer World.dead_structures.deinit();
    defer World.dead_players.deinit();
    defer World.dead_resources.deinit();

    // Initialize user interface
    //--------------------------------------------------------------------------------------
    try Config.keys.init(&allocator); // Initializes and activates default keybindings
    u.canvasOnPlayer(); // Centers camera

    // Main game loop
    //--------------------------------------------------------------------------------------
    while (!rl.windowShouldClose() and Config.game_active) { // Detect window close button or ESC key

        // Profiling
        //----------------------------------------------------------------------------------
        const profile_frame = (Config.profile_mode and u.perFrame(45));
        if (profile_frame) {
            u.startTimer(3, "\nSTART OF FRAME :::");
            std.debug.print("{} (TICK {}).\n\n", .{ Camera.frame_number, World.tick_number });
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

        // Tick loop updates if time for tick duration
        while (elapsed_time >= Config.TICK_DURATION) {
            try updateEntities(profile_frame);
            if (profile_frame) u.startTimer(1, "- Removing dead entities.");
            try removeEntities();
            if (profile_frame) u.endTimer(1, "Removing dead entities took {} seconds.");

            if (profile_frame) u.startTimer(1, "- Updating cell signatures.");
            World.grid.updateCellsigns(); // Updates Grid.cellsigns array
            if (profile_frame) u.endTimer(1, "Updating cell signatures took {} seconds.");
            if (profile_frame) u.startTimer(1, "- Updating grid sections.");
            World.grid.updateSections(cellsigns_cache); // Updates Grid.sections array by cellsign comparison
            if (profile_frame) u.endTimer(1, "Updating grid sections took {} seconds.");

            elapsed_time -= Config.TICK_DURATION;
            updates_performed += 1;

            if (updates_performed >= Config.MAX_TICKS_PER_FRAME) {
                break; // Prevent too much work per frame, requires sync with server
            }
        }
        if (profile_frame) u.endTimer(0, "Logic phase took {} seconds in total.\n");

        // Controls
        //----------------------------------------------------------------------------------
        if (profile_frame) u.startTimer(0, "CONTROLS PHASE.\n");
        updateControls(stored_mouse_input[0], stored_mouse_input[1], stored_mousewheel, stored_key_input, &Player.changed_x, &Player.changed_y, profile_frame);
        stored_mousewheel = 0.0;
        stored_key_input = 0;
        stored_mouse_input = [2]rl.Vector2{ rl.Vector2.zero(), rl.Vector2.zero() };
        if (profile_frame) u.endTimer(0, "Controls phase took {} seconds in total.\n");

        // Drawing
        //----------------------------------------------------------------------------------
        if (profile_frame) u.startTimer(0, "DRAWING PHASE.\n");

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.white);
        draw(profile_frame);
        if (profile_frame) u.endTimer(0, "Drawing phase took {} seconds in total.\n");

        // End of frame
        //----------------------------------------------------------------------------------

        World.tick_number += updates_performed; // <-- Should be checked against server-side tick_number
        Config.last_tick_time += @as(f64, @floatFromInt(updates_performed)) * Config.TICK_DURATION;
        Camera.frame_number += 1;

        if (profile_frame) {
            u.endTimer(3, "END OF FRAME ::: {} seconds in total.\n");
            std.debug.print("Current FPS: {}.\n", .{rl.getFPS()});
            u.printGridEntities(&World.grid);
            u.printGridCells(&World.grid);
        }
    }
}

fn processInput(stored_mouse_input_l: *rl.Vector2, stored_mouse_input_r: *rl.Vector2, stored_mousewheel: *f32, stored_key_input: *u32) void {
    if (Player.build_guide != null) { // While build guide is active
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

// Game loop: Controls
//----------------------------------------------------------------------------------
fn updateControls(stored_mouse_input_l: rl.Vector2, stored_mouse_input_r: rl.Vector2, mousewheel_delta: f32, key_input: u32, changed_x: *?u16, changed_y: *?u16, profile_frame: bool) void {
    if (profile_frame) u.startTimer(1, "- Updating controls.");
    // While build guide is active
    if (Player.build_guide != null) {
        Player.selected = null; // No selection
        if (stored_mouse_input_r.equals(rl.Vector2.zero()) == 0) Player.build_guide = null; // If mouse right is pressed, cancels build guide
        if (Config.keys.actionActive(key_input, u.Key.Action.BuildConfirm)) {
            std.debug.print("Set player order!\n", .{});
            Player.build_order = Player.build_guide.?;
        }
    } else { // Whenever build guide is inactive
        if (stored_mouse_input_l.equals(rl.Vector2.zero()) == 0) { // If mouse left is clicked, checks/stores selection
            const map_coords = u.screenToMap(stored_mouse_input_l);
            const at_mouse = World.grid.collidesWith(map_coords[0], map_coords[1], 1, 1, null) catch null;
            // Sets variable directly to entity or null
            if (at_mouse) |entity| {
                Player.selected = if (entity != Player.selected) entity else null;
                std.debug.print("Selected entity {}.\n", .{@intFromPtr(entity)});
            } else {
                Player.selected = null;
                std.debug.print("Deselected entity.\n", .{});
            }
        }
    }
    updateCanvasZoom(mousewheel_delta);
    updateCanvasPosition(stored_mouse_input_r, key_input);

    if (key_input != 0) { // Sets player build/movement orders from key input
        try processMoveInput(key_input, changed_x, changed_y);
        if (Config.keys.actionActive(key_input, u.Key.Action.BuildOne) or Config.keys.actionActive(key_input, u.Key.Action.BuildTwo) or
            Config.keys.actionActive(key_input, u.Key.Action.BuildThree) or Config.keys.actionActive(key_input, u.Key.Action.BuildFour))
        {
            processActionInput(key_input);
        }
    }

    if (Config.keys.actionActive(key_input, u.Key.Action.SpecialEnter)) Config.profile_mode = !Config.profile_mode; // Enter toggles profile mode (verbose logs) for now
    if (profile_frame) u.endTimer(1, "Updating controls took {} seconds.");
}

pub fn updateCanvasZoom(mousewheel_delta: f32) void {
    Camera.canvas_max = u.maxCanvasSize(rl.getScreenWidth(), rl.getScreenHeight(), World.width, World.height); // For window resizing
    Camera.canvas_zoom_target = std.math.clamp(Camera.canvas_zoom_target, Camera.canvas_max, Camera.ZOOM_MAX); // Re-sizes canvas to current window size
    if (mousewheel_delta != 0) {
        const zoom_change: f32 = 1 + u.clamp(u.limitToTickRate(Camera.ZOOM_RATE * mousewheel_delta), -0.25, 0.25); // Zoom rate
        Camera.canvas_zoom_target = @min(@max(Camera.canvas_max, Camera.canvas_zoom * zoom_change), Camera.ZOOM_MAX); // From <1 (full map) to 10 (zoomed in)
    }
    if (Camera.canvas_zoom != Camera.canvas_zoom_target) {
        const old_zoom: f32 = Camera.canvas_zoom;
        const lerp_factor: f32 = u.frameAdjusted(Camera.ZOOM_SPEED);
        Camera.canvas_zoom = Camera.canvas_zoom + lerp_factor * (Camera.canvas_zoom_target - Camera.canvas_zoom);
        // If difference is tiny, snaps to target to avoid perpetual adjustments
        if (@abs(Camera.canvas_zoom - Camera.canvas_zoom_target) < 0.001) Camera.canvas_zoom = Camera.canvas_zoom_target;

        // Adjust offsets to zoom around the mouse position
        const mouse_x = @as(f32, @floatFromInt(rl.getMouseX()));
        const mouse_y = @as(f32, @floatFromInt(rl.getMouseY()));
        const canvas_mouse_x_old_zoom = (mouse_x - Camera.canvas_offset_x) / old_zoom;
        const canvas_mouse_y_old_zoom = (mouse_y - Camera.canvas_offset_y) / old_zoom;
        const canvas_mouse_x_new_zoom = (mouse_x - Camera.canvas_offset_x) / Camera.canvas_zoom;
        const canvas_mouse_y_new_zoom = (mouse_y - Camera.canvas_offset_y) / Camera.canvas_zoom;

        // Adjust offsets to keep the mouse position consistent
        Camera.setX(Camera.canvas_offset_x_target + (canvas_mouse_x_new_zoom - canvas_mouse_x_old_zoom) * Camera.canvas_zoom);
        Camera.setY(Camera.canvas_offset_y_target + (canvas_mouse_y_new_zoom - canvas_mouse_y_old_zoom) * Camera.canvas_zoom);
    }
}

pub fn updateCanvasPosition(mouse_input_r: rl.Vector2, key_input: u32) void {
    const mouse_x = @as(f32, @floatFromInt(rl.getMouseX()));
    const mouse_y = @as(f32, @floatFromInt(rl.getMouseY()));
    const screen_width_float = @as(f32, @floatFromInt(rl.getScreenWidth()));
    const screen_height_float = @as(f32, @floatFromInt(rl.getScreenHeight()));
    const margin_w: f32 = screen_width_float / 10.0;
    const margin_h: f32 = screen_height_float / 10.0;
    const effective_speed: f32 = u.frameAdjusted(@as(f32, @floatCast(Camera.SCROLL_RATE)) / @max(1, Camera.canvas_zoom * 0.1));

    if ((key_input & (1 << 9)) != 0) { // Space key centers camera on player/selected
        if (Player.selected == null) u.canvasOnPlayer() else u.canvasOnEntity(Player.selected.?);
    } else if (mouse_input_r.x != 0 or mouse_input_r.y != 0) { // Right-button drags canvas target
        Camera.canvas_offset_x_target += mouse_input_r.x * u.limitToTickRate(1);
        Camera.canvas_offset_y_target += mouse_input_r.y * u.limitToTickRate(1);
    } else { // Mouse edge scrolls camera
        if (mouse_x < margin_w) {
            const factor = 1.0 - (mouse_x / margin_w);
            Camera.canvas_offset_x_target += effective_speed * factor;
        }
        if (mouse_x > screen_width_float - margin_w) {
            const factor = 1.0 - ((screen_width_float - mouse_x) / margin_w);
            Camera.canvas_offset_x_target -= effective_speed * factor;
        }
        if (mouse_y < margin_h) {
            const factor = 1.0 - (mouse_y / margin_h);
            Camera.canvas_offset_y_target += effective_speed * factor;
        }
        if (mouse_y > screen_height_float - margin_h) {
            const factor = 1.0 - ((screen_height_float - mouse_y) / margin_h);
            Camera.canvas_offset_y_target -= effective_speed * factor;
        }
    }

    // Restrict target canvas to map bounds
    const min_offset_x: f32 = screen_width_float - @as(f32, @floatFromInt(World.width)) * Camera.canvas_zoom;
    const min_offset_y: f32 = screen_height_float - @as(f32, @floatFromInt(World.height)) * Camera.canvas_zoom;
    if (Camera.canvas_offset_x_target > 0) Camera.canvas_offset_x_target = 0;
    if (Camera.canvas_offset_y_target > 0) Camera.canvas_offset_y_target = 0;
    if (Camera.canvas_offset_x_target < min_offset_x) Camera.canvas_offset_x_target = min_offset_x;
    if (Camera.canvas_offset_y_target < min_offset_y) Camera.canvas_offset_y_target = min_offset_y;

    // Update actual canvas offsets to approach target
    if (Camera.canvas_offset_x != Camera.canvas_offset_x_target) {
        const lerp_factor: f32 = u.frameAdjusted(Camera.SCROLL_SPEED);
        Camera.canvas_offset_x = Camera.canvas_offset_x + lerp_factor * (Camera.canvas_offset_x_target - Camera.canvas_offset_x);
        // If difference is tiny, snaps to target to avoid perpetual adjustments
        if (@abs(Camera.canvas_offset_x - Camera.canvas_offset_x_target) < 0.001) Camera.canvas_offset_x = Camera.canvas_offset_x_target;
    }
    if (Camera.canvas_offset_y != Camera.canvas_offset_y_target) {
        const lerp_factor: f32 = u.frameAdjusted(Camera.SCROLL_SPEED);
        Camera.canvas_offset_y = Camera.canvas_offset_y + lerp_factor * (Camera.canvas_offset_y_target - Camera.canvas_offset_y);
        // If difference is tiny, snaps to target to avoid perpetual adjustments
        if (@abs(Camera.canvas_offset_y - Camera.canvas_offset_y_target) < 0.001) Camera.canvas_offset_y = Camera.canvas_offset_y_target;
    }

    // Restrict canvas to map bounds
    if (Camera.canvas_offset_x > 0) Camera.canvas_offset_x = 0;
    if (Camera.canvas_offset_y > 0) Camera.canvas_offset_y = 0;
    if (Camera.canvas_offset_x < min_offset_x) Camera.canvas_offset_x = min_offset_x;
    if (Camera.canvas_offset_y < min_offset_y) Camera.canvas_offset_y = min_offset_y;
}

// Game loop: Entities
//----------------------------------------------------------------------------------
// Reminder:
// Entities rely on sectionSearch for collision, which retrieves a list from grid.sections.
// The updateSections function is responsible for regenerating grid.sections based on the current state of grid.cells.
// This means that any entity removed from grid.cells (e.g. removeEntities -> unit.remove -> grid.removeFromCell)
// should no longer appear in grid.sections ***after*** updateSections has run. But have now added removeFromAllSections
// to unit.remove, which ***should*** ensure that any reference is removed from the grid after removeEntities runs.

fn updateEntities(profile_frame: bool) !void {
    // Players
    if (profile_frame) u.startTimer(1, "- Updating players.");
    for (e.players.items) |p| {
        if (p.state == e.Player.State.Dead) {
            try World.dead_players.append(p); // To be destroyed in removeEntities
        } else {
            try p.update();
        }
    }
    if (profile_frame) u.endTimer(1, "Updating players took {} seconds.");

    // Structures
    if (profile_frame) u.startTimer(1, "- Updating structures.");
    for (e.structures.items) |structure| {
        if (structure.state == e.Structure.State.Destroyed) {
            try World.dead_structures.append(structure); // To be destroyed in removeEntities
        } else {
            structure.update();
        }
    }
    if (profile_frame) u.endTimer(1, "Updating structures took {} seconds.");

    // Units (and projectiles)
    if (profile_frame) u.startTimer(1, "- Updating units.");
    for (e.units.items) |unit| {
        if (unit.state == e.Unit.State.Dead) {
            try World.dead_units.append(unit); // To be destroyed in removeEntities
        } else {
            try unit.update();
        }
    }
    if (profile_frame) u.endTimer(1, "Updating units took {} seconds.");

    // Resources
    if (profile_frame) u.startTimer(1, "- Updating resources.");
    for (e.resources.items) |resource| {
        if (resource.state == e.Resource.State.Depleted) {
            try World.dead_resources.append(resource); // To be destroyed in removeEntities
        } else {
            resource.update();
        }
    }
    if (profile_frame) u.endTimer(1, "Updating resources took {} seconds.");
}

fn removeEntities() !void {
    for (World.dead_resources.items) |resources| { // Second: Removes resources that were marked for destruction
        //std.debug.print("Removing unit at address {}. Entity address {}.\n", .{ @intFromPtr(unit), @intFromPtr(unit.entity) });
        try resources.remove();
    }
    for (World.dead_units.items) |unit| { // Second: Removes units that were marked for destruction
        //std.debug.print("Removing unit at address {}. Entity address {}.\n", .{ @intFromPtr(unit), @intFromPtr(unit.entity) });
        try unit.remove();
    }
    for (World.dead_structures.items) |structure| { // Second: Removes structures that were marked for destruction
        //std.debug.print("Removing unit at address {}. Entity address {}.\n", .{ @intFromPtr(unit), @intFromPtr(unit.entity) });
        try structure.remove();
    }
    for (World.dead_players.items) |p| { // Second: Removes players that were marked for destruction
        //std.debug.print("Removing unit at address {}. Entity address {}.\n", .{ @intFromPtr(unit), @intFromPtr(unit.entity) });
        try p.remove();
    }
    World.dead_resources.clearAndFree();
    World.dead_units.clearAndFree();
    World.dead_structures.clearAndFree();
    World.dead_players.clearAndFree();
}

// Game loop: Drawing
//----------------------------------------------------------------------------------

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

/// Draws map and grid markers relative to current canvas
pub fn drawMap() void {
    // Draw the map area
    u.drawRect(0, 0, World.width, World.height, rl.Color.ray_white);

    // Draw subgrid lines
    var rowIndex: i32 = 1;
    while (rowIndex * u.Subcell.size < World.height) : (rowIndex += 1) {
        u.drawRect(0, @as(i32, @intCast(u.Subcell.size * rowIndex)), World.width, 2, rl.Color.light_gray);
    }
    var colIndex: i32 = 1;
    while (colIndex * u.Subcell.size < World.width) : (colIndex += 1) {
        u.drawRect(@as(i32, @intCast(u.Subcell.size * colIndex)), 0, 2, World.height, rl.Color.light_gray);
    }

    // Draw grid lines
    rowIndex = 1;
    while (rowIndex * u.Grid.cell_size < World.height) : (rowIndex += 1) {
        u.drawRect(0, @as(i32, @intCast(u.Grid.cell_size * rowIndex)), World.width, 5, rl.Color.light_gray);
    }
    colIndex = 1;
    while (colIndex * u.Grid.cell_size < World.width) : (colIndex += 1) {
        u.drawRect(@as(i32, @intCast(u.Grid.cell_size * colIndex)), 0, 5, World.height, rl.Color.light_gray);
    }

    // Draw the edges of the map
    u.drawRect(0, -10, World.width, 20, rl.Color.dark_gray); // Top edge
    u.drawRect(0, World.height - 10, World.width, 20, rl.Color.dark_gray); // Bottom edge
    u.drawRect(-10, 0, 20, World.height, rl.Color.dark_gray); // Left edge
    u.drawRect(World.width - 10, 0, 20, World.height, rl.Color.dark_gray); // Right edge

}

fn drawEntities() void {
    if (Player.selected == null) {
        for (e.resources.items) |x| x.draw(1);
        for (e.units.items) |x| x.draw(1);
        for (e.structures.items) |x| x.draw(1);
        for (e.players.items) |x| x.draw(1);
    } else {
        for (e.resources.items) |x| if (x.entity == Player.selected) x.draw(1) else x.draw(0.5);
        for (e.units.items) |x| if (x.entity == Player.selected) x.draw(1) else x.draw(0.5);
        for (e.structures.items) |x| if (x.entity == Player.selected) x.draw(1) else x.draw(0.5);
        for (e.players.items) |x| if (x.entity == Player.selected) x.draw(1) else x.draw(0.5);
    }
}

/// Draws user interface
pub fn drawInterface() void {
    if (Player.build_guide != null) drawGuide(Player.build_guide.?);

    // Development tools
    rl.drawFPS(40, 40);
}

// Game conditions
//----------------------------------------------------------------------------------
// May want to move into a separate module, `world` or `map`
const Map = struct { // Encapsulates map properties; see World for currently active map
    id: u32,
    name: []const u8,
    width: u16,
    height: u16,
    start_locations: []u.Point,
    resource_locations: []u.Point,

    /// Finds map from `id` and initializes the `World` with the new properties. Returns the opened `Map` or error if invalid `id`.
    pub fn open(allocator: *std.mem.Allocator, id: u32) !Map {
        var opened_map: Map = undefined;
        opened_map = try get(allocator, id);
        // Setting game world properties from opened map
        try World.initializeMap(allocator, opened_map);
        std.debug.print("Opening map ID {}, name: {s}.\n", .{ id, opened_map.name });
        return opened_map;
    }

    /// Finds map in the database from `id`. Returns error if not found.
    fn get(allocator: *std.mem.Allocator, id: u32) !Map {
        return switch (id) {
            0 => Map{
                .id = id,
                .name = "Default Map",
                .width = World.DEFAULT_WIDTH,
                .height = World.DEFAULT_HEIGHT,
                .start_locations = try defaultStartLocations(allocator, World.DEFAULT_WIDTH, World.DEFAULT_HEIGHT, 2),
                .resource_locations = try defaultResourceLocations(allocator, World.DEFAULT_WIDTH, World.DEFAULT_HEIGHT),
            },
            else => error.MapNotFound,
        };
    }

    fn defaultStartLocations(allocator: *std.mem.Allocator, width: u16, height: u16, player_count: u8) ![]u.Point {
        const offset = u.Grid.cell_half * 3;
        const coordinates: [4]u.Point = [_]u.Point{
            u.Point{ .x = offset, .y = offset },
            u.Point{ .x = width - offset, .y = height - offset },
            u.Point{ .x = width - offset, .y = offset },
            u.Point{ .x = offset, .y = height - offset },
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

    fn defaultResourceLocations(allocator: *std.mem.Allocator, width: u16, height: u16) ![]u.Point {
        const cols = @divTrunc(width, u.Grid.cell_size);
        const rows = @divTrunc(height, u.Grid.cell_size);
        const total = (cols * rows) * 4;
        var slice = try allocator.alloc(u.Point, total);
        var index: usize = 0;

        // Base subcell positions (unrotated base pattern)
        const subcell_positions = [_]u.Point{
            u.Point{ .x = 2, .y = 3 },
            u.Point{ .x = 2, .y = 5 },
            u.Point{ .x = 9, .y = 3 },
            u.Point{ .x = 9, .y = 5 },
        };

        for (0..cols) |col| {
            const base_x = u.asU16(usize, col * u.Grid.cell_size);
            for (0..rows) |row| {
                const base_y = u.asU16(usize, row * u.Grid.cell_size);

                // Determine the rotation based on the cell position
                const rotation = (col + row) % 4;

                // Rotate or reflect the base positions based on the rotation value
                for (0..4) |i| {
                    const rotated_pos = switch (rotation) {
                        0 => subcell_positions[i], // No rotation
                        1 => u.Point{ .x = subcell_positions[i].y, .y = 10 - subcell_positions[i].x }, // 90 degrees
                        2 => u.Point{ .x = 10 - subcell_positions[i].x, .y = 10 - subcell_positions[i].y }, // 180 degrees
                        3 => u.Point{ .x = 10 - subcell_positions[i].y, .y = subcell_positions[i].x }, // 270 degrees
                        else => unreachable,
                    };

                    // Multiply by u.Subcell.size to correctly position within the subcells, and snap
                    const final = u.Subcell.snapToNode(base_x + rotated_pos.x * u.Subcell.size, base_y + rotated_pos.y * u.Subcell.size, u.Subcell.size, u.Subcell.size);
                    slice[index] = u.Point.at(final[0], final[1]);
                    index += 1; // Increment by 1 for each resource
                }
            }
        }

        return slice;
    }
};

/// Returns true when `life` is an exact divisor of the world's `MOVEMENT_DIVISIONS`.
pub fn moveDivision(life: i16) bool {
    return @rem(life, World.MOVEMENT_DIVISIONS) == 0;
}

/// Returns true if `life` is an exact divisor of the specified `multiple` of the world's `MOVEMENT_DIVISIONS`.
pub fn moveDivMultiple(life: i16, multiple: i16) bool {
    return @rem(life, World.MOVEMENT_DIVISIONS * multiple) == 0;
}

// AI Player
//----------------------------------------------------------------------------------
pub const EnemyPlayerAI = struct {
    player: *e.Player,

    const directions = [8]u8{ 1, 2, 3, 4, 6, 7, 8, 9 };

    pub fn initialize(ai: *e.Player) EnemyPlayerAI {
        return EnemyPlayerAI{ .player = ai };
    }

    pub fn fetchAction(ai: *e.Player, tick: u64) void {
        const move_duration = 60;
        const move_all = move_duration * directions.len;

        // ... Special patterns, e.g. defense, attack
        // ... Special patterns, e.g. defense, attack
        // ... Special patterns, e.g. defense, attack
        // Default pattern
        if (tick % move_all < move_all)
            continuousMove(ai, tick, move_duration) catch return null;
        if (tick % 300 == 0) {
            // Generate a "random" structure class value between 0 and 3
            const class_value = u.asU8(u64, tick / 300 % 4);
            constructBuilding(ai, class_value, tick);
        }
    }

    pub fn constructBuilding(ai: *e.Player, class: u8, tick: u64) void {
        // Convert to i32 and calculate x and y, clamping to prevent underflow
        const x_raw = @max(@rem(@as(i32, @intCast(tick)), 500) - 250, 0);
        const y_raw = @max(@rem(@divTrunc(@as(i32, @intCast(tick)), 2), 500) - 250, 0);

        // Convert to u16 after clamping
        const x = @as(u16, @intCast(x_raw));
        const y = @as(u16, @intCast(y_raw));

        // Construct the building at the calculated position
        _ = e.Structure.construct(ai.id, ai.x + x, ai.y + y, class);
    }

    /// Moves continuously in a tick-determined direction for up to `duration` ticks.
    fn continuousMove(player: *e.Player, tick: u64, duration: u16) !void {
        const direction_index = u.asU8(u64, (tick / duration) % 8); // Change direction every `duration` ticks
        const direction = directions[direction_index];

        const changed = u.dirOffset(player.x, player.y, direction, u.asU16(f32, player.speed));
        const clamped_x = u.mapClamp(u16, changed[0], player.width, 0);
        const clamped_y = u.mapClamp(u16, changed[1], player.height, 1);

        try player.executeMovement(clamped_x, clamped_y, player.speed);
    }
};

// Game controls interaction
//----------------------------------------------------------------------------------
fn processMoveInput(key_input: u32, changed_x: *?u16, changed_y: *?u16) !void { // Called in processInput
    if (Player.self == null) return;
    const speed = u.limitToTickRate(Player.self.?.speed);
    if (Config.keys.actionActive(key_input, u.Key.Action.MoveUp)) {
        changed_y.* = u.mapClampY(@truncate(u.i32SubFloat(f32, Player.self.?.y, speed)), Player.self.?.height);
    }
    if (Config.keys.actionActive(key_input, u.Key.Action.MoveLeft)) {
        changed_x.* = u.mapClampX(@truncate(u.i32SubFloat(f32, Player.self.?.x, speed)), Player.self.?.width);
    }
    if (Config.keys.actionActive(key_input, u.Key.Action.MoveDown)) {
        changed_y.* = u.mapClampY(@truncate(u.i32AddFloat(f32, Player.self.?.y, speed)), Player.self.?.height);
    }
    if (Config.keys.actionActive(key_input, u.Key.Action.MoveRight)) {
        changed_x.* = u.mapClampX(@truncate(u.i32AddFloat(f32, Player.self.?.x, speed)), Player.self.?.width);
    }
}

fn processActionInput(key_input: u32) void { // Called in processInput
    if (Player.self == null) return;
    if (Config.keys.actionActive(key_input, u.Key.Action.BuildOne)) {
        Player.build_index = 0;
    } else if (Config.keys.actionActive(key_input, u.Key.Action.BuildTwo)) {
        Player.build_index = 1;
    } else if (Config.keys.actionActive(key_input, u.Key.Action.BuildThree)) {
        Player.build_index = 2;
    } else if (Config.keys.actionActive(key_input, u.Key.Action.BuildFour)) {
        Player.build_index = 3;
    }

    if (Player.build_index != null) { // Sets build guide
        if (Player.build_guide == null or Player.build_guide.? != Player.build_index.?) {
            std.debug.print("Set a build guide!\n", .{});
            Player.build_guide = Player.build_index;
        } else {
            std.debug.print("Removed build guide!\n", .{});
            Player.build_guide = null;
        }
    }
}

pub fn executeBuild(class: u8) void {
    if (!isInBuildDistance() or Player.id == null) return;
    const xy = findBuildPosition(class);
    const built = e.Structure.construct(Player.id.?, xy[0], xy[1], class);
    if (built) |building| {
        std.debug.print("Structure built successfully: \n{}.\nPointer address of structure is: {}.\n", .{ building, @intFromPtr(building) });
        Player.selected = building.entity; // Hack, sets selected to building to instantly deselect it (in updateControls) by the same click
    } else {
        std.debug.print("Failed to build structure\n", .{});
        // Handle the failure case, e.g., notify the player
    }
    Player.build_guide = null;
}

fn findBuildPosition(class: u8) [2]u16 {
    const building = e.Structure.preset(class);
    const x_offset = u.asF32(u16, u.Subcell.size) * Camera.canvas_zoom;
    const y_offset = u.asF32(u16, u.Subcell.size) * Camera.canvas_zoom;
    const mouse_position = rl.getMousePosition();

    const adjusted_position = mouse_position.add(rl.Vector2.init(x_offset, y_offset));
    const subcell = u.screenToSubcell(adjusted_position);
    const snapped = u.Subcell.snapToNode(subcell.node.x, subcell.node.y, building.width, building.height);

    return [2]u16{ snapped[0], snapped[1] };
}

fn isInBuildDistance() bool {
    if (Player.self == null) return false;
    const subcell_center = u.screenToSubcell(rl.getMousePosition()).center();
    const distance_max = u.Grid.cell_half; //u.asU32(u16, e.Structure.preset(class).width + e.Structure.preset(class).height);
    const distance = std.math.sqrt(u.distanceSquared(u.Point.at(Player.self.?.x, Player.self.?.y), u.Point.at(subcell_center[0], subcell_center[1])));
    return distance <= distance_max;
}

// Interface
//----------------------------------------------------------------------------------
pub fn drawGuide(class: u8) void {
    if (Player.self == null) return;
    const xy = findBuildPosition(class);
    const building = e.Structure.preset(class);
    const collides = World.grid.collidesWith(xy[0], xy[1], building.width, building.height, null) catch null;
    if (collides != null or !isInBuildDistance() or !u.isInMap(xy[0], xy[1], building.width, building.height)) {
        u.drawGuideFail(xy[0], xy[1], building.width, building.height, Player.self.?.entity.color(1));
    } else {
        u.drawGuide(xy[0], xy[1], building.width, building.height, Player.self.?.entity.color(1));
    }
}
