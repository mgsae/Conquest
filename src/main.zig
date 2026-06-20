const rl = @import("raylib");
const std: type = @import("std");
const u = @import("utils.zig");
const e = @import("entity.zig");
const m = @import("map.zig");

/// The local game config properties. Const values are universal, var values vary with play session.
pub const Config = struct {
    pub const TICKRATE = 60; // Target logical fps
    pub const TICK_DURATION: f64 = 1.0 / @as(f64, @floatFromInt(TICKRATE));
    pub const MAX_TICKS_PER_FRAME = 1;
    pub const MAX_PLAYERS = 8;
    pub const PLAYER_SEARCH_LIMIT = 2056; // Player collision search limit, must exceed #entities in 3x3 cells
    pub const UNIT_SEARCH_LIMIT = 1028; // Unit collision search limit
    pub const BUFFERSIZE = 65536; // Limit to number of entities updated via sectionSearch per tick
    pub const MAX_COMPLEX_SIZE = 256; // Limit to connected buildings
    pub const DASHBOARD_HEIGHT = 200;
    pub var last_tick_time: f64 = 0.0;
    pub var profile_mode = false;
    pub var profile_timer = [4]f64{ 0, 0, 0, 0 };
    pub var keys: u.Key = undefined; // Keybindings
    pub var game_active = true;
    var textureManager: TextureManager = undefined;
};

/// The local game camera properties. Const values are universal, var values vary with play session.
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
    pub var selected: [256]?*e.Entity = [_]?*e.Entity{null} ** 256;
    pub var selection_origin: ?rl.Vector2 = null;
    pub var selection_nodes: [2]?u.Point = [_]?u.Point{ null, null }; // Selection node x,y, target node x,y
    pub var selection_path: ?std.ArrayList(u.Point) = null;
    pub var changed_x: ?u16 = null;
    pub var changed_y: ?u16 = null;
    pub var build_guide: ?u8 = null;
    pub var build_index: ?u8 = null;
    pub var build_order: ?u8 = null;
    pub var id_unit_count: [Config.MAX_PLAYERS]u16 = [_]u16{0} ** Config.MAX_PLAYERS;
    pub var id_structure_count: [Config.MAX_PLAYERS]u16 = [_]u16{0} ** Config.MAX_PLAYERS;
    pub var id_player: [Config.MAX_PLAYERS]?*e.Player = [_]?*e.Player{null} ** Config.MAX_PLAYERS;
};

/// World properties, shared state initialized by initializeMap.
pub const World = struct {
    const DEFAULT_WIDTH = 15000; // 1920 * 8; // Limit for u16 coordinates: 65535
    const DEFAULT_HEIGHT = 9000; // 1080 * 8; // Limit for u16 coordinates: 65535
    pub const GRID_CELL_SIZE = 1024;
    pub const GRID_SUBCELL_DIVISIONS = 16;
    pub const MOVEMENT_DIVISIONS = 10; // Modulus base for unit movement updates
    pub var tick_number: u64 = 0; // Set on map initialization
    pub var width: u16 = 0;
    pub var height: u16 = 0;
    pub var terrain_width: u16 = 0;
    pub var terrain_height: u16 = 0;
    pub var terrain: []u8 = undefined;
    pub var grid: e.Grid = undefined;
    pub var rng: std.Random.DefaultPrng = undefined;
    var dead_players: std.ArrayList(*e.Player) = undefined;
    var dead_structures: std.ArrayList(*e.Structure) = undefined;
    var dead_units: std.ArrayList(*e.Unit) = undefined;
    var dead_resources: std.ArrayList(*e.Resource) = undefined;
    var dead_projectiles: std.ArrayList(*e.Projectile) = undefined;
    pub var new_players: std.ArrayList(*e.Player) = undefined;
    pub var new_structures: std.ArrayList(*e.Structure) = undefined;
    pub var new_units: std.ArrayList(*e.Unit) = undefined;
    pub var new_resources: std.ArrayList(*e.Resource) = undefined;
    pub var new_projectiles: std.ArrayList(*e.Projectile) = undefined;

    fn initializeMap(allocator: *std.mem.Allocator, map_id: u32, map_file: m.MapFile) !void {
        width = map_file.width;
        height = map_file.height;

        terrain_width = @divTrunc(width, u.Subcell.size) + 1;
        terrain_height = @divTrunc(height, u.Subcell.size) + 1;
        terrain = map_file.terrain;

        Camera.canvas_max = u.maxCanvasSize(rl.getScreenWidth(), rl.getScreenHeight(), width, height); // Updates camera zoom out limit

        // Initialize grid with derived dimensions
        const gridWidth: usize = @intCast(u.ceilDiv(width, u.Grid.cell_size));
        const gridHeight: usize = @intCast(u.ceilDiv(height, u.Grid.cell_size));
        std.debug.print("Grid Width: {}, Grid Height: {}\n", .{ gridWidth, gridHeight });
        std.debug.print("Map Width: {}, Map Height: {}, Cell Size: {}\n", .{ World.width, World.height, u.Grid.cell_size });
        grid.init(allocator, gridWidth, gridHeight, Config.BUFFERSIZE) catch return error.GridInitializationFailed;

        const subcells_blocked = try map_file.getTerrainBlockedSubcells(allocator);
        for (subcells_blocked) |subcell| {
            try grid.blocked_subcells.put(subcell.node, {});
        }

        u.rngInit(map_id + width + height); // Initializes the RNG with the map id + width + height as the seed
        tick_number = 0; // Starts the shared tick counter

    }

    fn initializeEntities(allocator: std.mem.Allocator, map_file: m.MapFile) !void {
        e.players = std.ArrayList(*e.Player).init(allocator);
        e.structures = std.ArrayList(*e.Structure).init(allocator);
        e.units = std.ArrayList(*e.Unit).init(allocator);
        e.resources = std.ArrayList(*e.Resource).init(allocator);
        e.projectiles = std.ArrayList(*e.Projectile).init(allocator);
        World.dead_players = std.ArrayList(*e.Player).init(allocator);
        World.dead_structures = std.ArrayList(*e.Structure).init(allocator);
        World.dead_units = std.ArrayList(*e.Unit).init(allocator);
        World.dead_resources = std.ArrayList(*e.Resource).init(allocator);
        World.dead_projectiles = std.ArrayList(*e.Projectile).init(allocator);
        World.new_players = std.ArrayList(*e.Player).init(allocator);
        World.new_structures = std.ArrayList(*e.Structure).init(allocator);
        World.new_units = std.ArrayList(*e.Unit).init(allocator);
        World.new_resources = std.ArrayList(*e.Resource).init(allocator);
        World.new_projectiles = std.ArrayList(*e.Projectile).init(allocator);

        for (map_file.resources) |res_spawn| {
            const resource = try e.Resource.create(res_spawn.x, res_spawn.y, res_spawn.class);
            try e.resources.append(resource);
        }
    }

    fn initializePlayers(map_file: m.MapFile, self_id: u8) !void {
        var player: *e.Player = undefined;
        for (map_file.start_locations, 1..) |loc, i| {
            if (i == self_id) {
                player = try e.Player.createLocal(loc.x, loc.y, u.asU8(usize, i));
                Player.self = player; // Sets player to local pointer
            } else {
                player = try e.Player.createRemote(loc.x, loc.y, u.asU8(usize, i));
            }
            try e.players.append(player);
        }
    }
};

pub fn main() anyerror!void {

    // Memory initialization
    //--------------------------------------------------------------------------------------
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    // Catch memory leaks
    // defer {
    //     const leaked = gpa.detectLeaks();
    //     std.debug.print("Has memory leak: {any}", .{leaked});
    // }

    // Initialize window
    //--------------------------------------------------------------------------------------
    var flags = rl.ConfigFlags{};
    flags.window_highdpi = true;
    //flags.vsync_hint = false;
    flags.borderless_windowed_mode = false;
    flags.fullscreen_mode = false;
    flags.window_undecorated = false;

    rl.setConfigFlags(flags);

    // Initialize window
    Camera.width = 1920 * 1.5;
    Camera.height = 1080 * 1.5;
    rl.initWindow(Camera.width, Camera.height, "Conquest");
    rl.setTargetFPS(120);
    rl.setWindowSize(Camera.width, Camera.height);
    defer rl.closeWindow(); // Close window and OpenGL context

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
    // This will be handled by a map selection process. For now, straight in.
    const map = try Map.open(&allocator, 1); // Opens default map and initializes world
    const cellsigns_cache = try allocator.alloc(u32, World.grid.cols * World.grid.rows);
    defer allocator.free(cellsigns_cache);
    defer World.grid.deinit(&allocator);
    try World.initializeEntities(allocator, map.file);
    try World.initializePlayers(map.file, Player.id.?);

    // Initialize graphics
    //--------------------------------------------------------------------------------------
    Config.textureManager.init(&allocator);
    Config.textureManager.loadAllTextures() catch std.debug.print("Failed to load textures.\n", .{});
    defer Config.textureManager.unloadAllTextures();

    // Cleanup
    //--------------------------------------------------------------------------------------
    defer e.units.deinit();
    defer e.structures.deinit();
    defer e.players.deinit();
    defer e.resources.deinit();
    defer e.projectiles.deinit();
    defer World.dead_units.deinit();
    defer World.dead_structures.deinit();
    defer World.dead_players.deinit();
    defer World.dead_resources.deinit();
    defer World.dead_projectiles.deinit();
    defer World.new_units.deinit();
    defer World.new_structures.deinit();
    defer World.new_players.deinit();
    defer World.new_resources.deinit();
    defer World.new_projectiles.deinit();

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
            // if (profile_frame) u.startTimer(1, "- Removing dead entities.");
            try removeEntities();
            // if (profile_frame) u.endTimer(1, "Removing dead entities took {} seconds.");

            // if (profile_frame) u.startTimer(1, "- Updating cell signatures.");
            World.grid.updateCellsigns(); // Updates Grid.cellsigns array
            // if (profile_frame) u.endTimer(1, "Updating cell signatures took {} seconds.");
            // if (profile_frame) u.startTimer(1, "- Updating grid sections.");
            World.grid.updateSections(cellsigns_cache); // Updates Grid.sections array by cellsign comparison
            // if (profile_frame) u.endTimer(1, "Updating grid sections took {} seconds.");

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

        rl.clearBackground(rl.Color.init(0, 0, 0, 255)); // Background color
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
    if (rl.isKeyPressed(rl.KeyboardKey.key_backspace)) stored_key_input.* |= @intFromEnum(u.Key.InputValue.Backspace);
}

// Game loop: Controls
//----------------------------------------------------------------------------------
/// Updates responding to registered player input.
fn updateControls(stored_mouse_input_l: rl.Vector2, stored_mouse_input_r: rl.Vector2, mousewheel_delta: f32, key_input: u32, changed_x: *?u16, changed_y: *?u16, profile_frame: bool) void {
    if (profile_frame) u.startTimer(1, "- Updating controls.");

    // Build guide is active, i.e. player is placing a structure
    if (Player.build_guide != null) {
        if (stored_mouse_input_r.equals(rl.Vector2.zero()) == 0) {
            Player.build_guide = null; // If mouse right is pressed, cancels build guide
        } else if (Config.keys.actionActive(key_input, u.Key.Action.BuildConfirm)) {
            // std.debug.print("Set player order!\n", .{});
            Player.build_order = Player.build_guide.?;
        }
    } else { // Build guide is inactive
        if (stored_mouse_input_l.equals(rl.Vector2.zero()) == 0) { // Mouse left pressed, checks/stores selection
            const map_coords = u.screenToMap(stored_mouse_input_l);
            const at_mouse = World.grid.collidesWith(map_coords[0], map_coords[1], 1, 1, null) catch null;

            if (at_mouse) |entity| { // Direct click selection
                setSelection(if (entity == Player.selected[0]) null else entity);
                // std.debug.print("Selected entity {}.\n", .{@intFromPtr(entity)});
            } else if (Player.selection_origin == null) { // Start selection box
                Player.selection_origin = stored_mouse_input_l; // Saves mouse position as box origin
                // std.debug.print("Mouse pressed not on entity, starting selection box.\n", .{});
            }
            // Making area selection, but mouse left not down
        } else if (Player.selection_origin != null and !(rl.isMouseButtonDown(rl.MouseButton.mouse_button_left))) {
            // std.debug.print("Mouse released while selection started, finding selection.\n", .{});
            const start = Player.selection_origin.?;
            const end = rl.getMousePosition();
            Player.selection_origin = null; // Reset selection box
            setSelection(null); // Clears selection

            const min_x = @min(start.x, end.x);
            const max_x = @max(start.x, end.x);
            const min_y = @min(start.y, end.y);
            const max_y = @max(start.y, end.y);

            if (max_x > min_x and max_y > min_y) {
                const map_min = u.screenToMap(rl.Vector2.init(min_x, min_y));
                const map_max = u.screenToMap(rl.Vector2.init(max_x, max_y));

                if (Player.id != null) {
                    const own_units = World.grid.ownUnitsInArea(Player.id.?, map_min[0], map_min[1], map_max[0], map_max[1]) catch |err| {
                        std.debug.print("ownUnitsInArea error: {}\n", .{err});
                        return;
                    };
                    defer own_units.deinit();
                    for (own_units.items) |unit| {
                        addSelection(unit);
                    }
                }
                if (Player.selected[0] == null) { // If no own units selected
                    const biggest = World.grid.biggestInArea(map_min[0], map_min[1], map_max[0], map_max[1]) catch null;
                    setSelection(biggest); // Sets to biggest entity or clears
                    if (biggest != null) {
                        std.debug.print("Selected entity {} via area selection.\n", .{@intFromPtr(biggest.?)});
                    } else {
                        std.debug.print("Deselected entity (no entity found in selection box).\n", .{});
                    }
                }
            }
        }
    }

    updateCanvasZoom(mousewheel_delta);
    updateCanvasPosition(stored_mouse_input_r, key_input);

    if (key_input != 0) { // Sets player build/movement orders from key input
        try processMoveInput(key_input, changed_x, changed_y);
        if (Config.keys.actionActive(key_input, u.Key.Action.BuildOne) or Config.keys.actionActive(key_input, u.Key.Action.BuildTwo) or
            Config.keys.actionActive(key_input, u.Key.Action.BuildThree) or Config.keys.actionActive(key_input, u.Key.Action.BuildFour) or Config.keys.actionActive(key_input, u.Key.Action.BuildRemove))
        {
            processActionInput(key_input);
        }
    }

    if (Config.keys.actionActive(key_input, u.Key.Action.SpecialEnter)) Config.profile_mode = !Config.profile_mode; // Enter toggles profile mode (verbose logs)
    if (profile_frame) u.endTimer(1, "Updating controls took {} seconds.");
}

/// Clears `Player.selected` and sets slot 0 to the `target` *Entity or null.
fn setSelection(target: ?*e.Entity) void {
    for (Player.selected) |prev_selected| { // Sets previously selected entities property to false
        if (prev_selected != null) prev_selected.?.setSelected(false);
    }
    Player.selected = [_]?*e.Entity{null} ** 256; // Clears selection
    Player.selected[0] = target; // null or entity
    if (target == null) return;
    target.?.setSelected(true); // Sets flag on entity
    // Adding derived secondary selected
    if (target.?.kind == e.Kind.Structure) {
        if (target.?.ref.Structure.complex) |complex| {
            for (complex.members) |maybe_connected| {
                if (maybe_connected) |connected| {
                    addSelection(connected.entity);
                }
            }
        }
    }
}

/// Finds the first null slot in `Player.selected` and sets it to the `target` *Entity.
fn addSelection(target: *e.Entity) void {
    for (Player.selected, 0..) |slot, i| {
        if (slot == null) {
            Player.selected[i] = target;
            target.setSelected(true);
            break;
        }
    }
}

fn removeSelection(target: *e.Entity) void {
    if (Player.selected[0] != null and Player.selected[0].? == target) {
        setSelection(null); // Clears all
    } else {
        const index = for (Player.selected, 0..) |slot, i| {
            if (slot != null and slot.? == target) {
                break i;
            }
        } else return;
        var i = index;
        while (i + 1 < Player.selected.len) : (i += 1) {
            Player.selected[i] = Player.selected[i + 1];
        }
        Player.selected[Player.selected.len - 1] = null;
    }
}

pub fn updateCanvasZoom(mousewheel_delta: f32) void {
    Camera.canvas_max = u.maxCanvasSize(rl.getScreenWidth(), rl.getScreenHeight(), World.width, World.height); // For window resizing
    Camera.canvas_zoom_target = std.math.clamp(Camera.canvas_zoom_target, Camera.canvas_max, Camera.ZOOM_MAX); // Re-sizes canvas to current window size
    if (mousewheel_delta != 0) {
        const zoom_input: f32 = u.clamp(u.limitToTickRate(Camera.ZOOM_RATE * mousewheel_delta), -0.25, 0.25);
        const new_target: f32 = @min(@max(Camera.canvas_max, Camera.canvas_zoom_target * (1 + zoom_input)), Camera.ZOOM_MAX);
        Camera.canvas_zoom_target = Camera.canvas_zoom_target + 0.2 * (new_target - Camera.canvas_zoom_target);
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
    // std.debug.print("Zoom: {d}. Target: {d}.\n", .{ Camera.canvas_zoom, Camera.canvas_zoom_target });
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
        if (Player.selected[0] == null) u.canvasOnPlayer() else u.canvasOnEntity(Player.selected[0].?);
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
    const min_offset_y: f32 = (screen_height_float - Config.DASHBOARD_HEIGHT) - @as(f32, @floatFromInt(World.height)) * Camera.canvas_zoom;
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
    @memset(&Player.id_player, null); // Resets player trackers
    for (e.players.items) |p| {
        if (p.state == e.Player.State.Dead) {
            try World.dead_players.append(p); // To be destroyed in removeEntities
            Player.id_player[p.id] = null;
        } else {
            try p.update();
            Player.id_player[p.id] = p; // Adds to player tracker
        }
    }
    if (profile_frame) u.endTimer(1, "Updating players took {} seconds.");

    // Structures
    if (profile_frame) u.startTimer(1, "- Updating structures.");
    @memset(&Player.id_structure_count, 0); // Resets structure counters
    for (e.structures.items) |structure| {
        if (structure.state == e.Structure.State.Destroyed) {
            try World.dead_structures.append(structure); // To be destroyed in removeEntities
        } else {
            structure.update();
            Player.id_structure_count[structure.owner] += 1; // Adds to structure counter
        }
    }
    if (profile_frame) u.endTimer(1, "Updating structures took {} seconds.");

    // Units
    if (profile_frame) u.startTimer(1, "- Updating units.");
    @memset(&Player.id_unit_count, 0); // Resets unit counters
    for (e.units.items) |unit| {
        if (unit.state == e.Unit.State.Dead) {
            try World.dead_units.append(unit); // To be destroyed in removeEntities
        } else {
            try unit.update();
            Player.id_unit_count[unit.owner] += 1; // Adds to unit counter
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

    // Projectiles
    if (profile_frame) u.startTimer(1, "- Updating projectiles.");
    for (e.projectiles.items) |projectile| {
        if (projectile.state == e.Projectile.State.Destroyed) {
            try World.dead_projectiles.append(projectile); // To be destroyed in removeEntities
        } else {
            projectile.update();
        }
    }
    if (profile_frame) u.endTimer(1, "Updating projectiles took {} seconds.");

    // Adding freshly added to main lists, then clearing new lists
    for (World.new_players.items) |fresh| { // Not sure this will ever be used
        try e.players.append(fresh);
    }
    for (World.new_structures.items) |fresh| {
        try e.structures.append(fresh);
    }
    for (World.new_units.items) |fresh| {
        try e.units.append(fresh);
    }
    for (World.new_resources.items) |fresh| {
        try e.resources.append(fresh);
    }
    for (World.new_projectiles.items) |fresh| {
        try e.projectiles.append(fresh);
    }
    World.new_players.clearRetainingCapacity();
    World.new_structures.clearRetainingCapacity();
    World.new_units.clearRetainingCapacity();
    World.new_resources.clearRetainingCapacity();
    World.new_projectiles.clearRetainingCapacity();
}

fn removeEntities() !void {
    for (World.dead_projectiles.items) |projectile| {
        try projectile.remove();
    }
    for (World.dead_resources.items) |resource| {
        if (resource.selected) removeSelection(resource.entity);
        try resource.remove();
    }
    for (World.dead_units.items) |unit| {
        if (unit.selected) removeSelection(unit.entity);
        try unit.remove();
    }
    for (World.dead_structures.items) |structure| {
        if (structure.selected) removeSelection(structure.entity);
        try structure.remove();
    }
    for (World.dead_players.items) |player| {
        if (player.selected) removeSelection(player.entity);
        try player.remove();
    }
    World.dead_projectiles.clearAndFree();
    World.dead_resources.clearAndFree();
    World.dead_units.clearAndFree();
    World.dead_structures.clearAndFree();
    World.dead_players.clearAndFree();
}

// Game loop: Drawing
//----------------------------------------------------------------------------------

pub const Texture = struct {
    texture: rl.Texture2D,

    pub fn init(self: *Texture, filename: []const u8) void {
        self.texture = rl.loadTexture(filename[0..]);
    }

    pub fn draw(self: *Texture, x: i32, y: i32, tint: rl.Color) void {
        rl.drawTexture(self.texture, x, y, tint);
    }

    pub fn unload(self: *Texture) void {
        rl.unloadTexture(self.texture);
    }
};

pub const TextureManager = struct {
    textures: std.StringHashMap(*rl.Texture2D),
    allocator: *std.mem.Allocator, // Add the allocator field

    pub fn init(self: *TextureManager, allocator: *std.mem.Allocator) void {
        self.allocator = allocator; // Initialize the allocator
        self.textures = std.StringHashMap(*rl.Texture2D).init(allocator.*);
    }

    pub fn loadAllTextures(self: *TextureManager) !void {
        try self.load("land", "img/land.png");
        // Add other textures here...
    }

    pub fn load(self: *TextureManager, name: []const u8, filename: [*:0]const u8) !void {
        const texture = try self.allocator.create(rl.Texture2D);
        const loaded_texture = rl.loadTexture(filename);
        if (loaded_texture.id == 0) {
            return error.FailedToLoadTexture;
        }
        texture.* = loaded_texture; // Copy the loaded texture into the allocated memory
        rl.setTextureFilter(texture.*, rl.TextureFilter.texture_filter_point);
        try self.textures.put(name, texture); // Store the pointer to the texture in the hashmap
    }

    pub fn get(self: *TextureManager, name: []const u8) !*rl.Texture2D {
        const texture_ptr = self.textures.get(name) orelse return error.TextureNotFound;
        return texture_ptr;
    }

    pub fn unloadAllTextures(self: *TextureManager) void {
        var it = self.textures.iterator();
        while (it.next()) |entry| {
            rl.unloadTexture(entry.value_ptr.*.*);
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.textures.deinit();
    }
};

fn draw(profile_frame: bool) void {
    if (profile_frame) u.startTimer(1, "- Drawing map.");
    drawMap();
    if (profile_frame) u.endTimer(1, "Drawing map took {} seconds.");
    if (profile_frame) u.startTimer(1, "- Drawing entities.");
    drawEntities(profile_frame);
    if (profile_frame) u.endTimer(1, "Drawing entities took {} seconds.");
    if (profile_frame) u.startTimer(1, "- Drawing UI.");
    drawInterface();
    if (profile_frame) u.endTimer(1, "Drawing UI took {} seconds.");
}

/// Draws map and grid markers relative to current canvas
pub fn drawMap() void {

    // // Draws colors for now, textures needed
    // const landTexture = Config.textureManager.get("land") catch null;
    // if (landTexture == null) {
    //     std.debug.print("Warning: 'land' texture not found!\n", .{});
    //     return;
    // }
    const terrain = World.terrain;
    const tw = World.terrain_width;
    const th = World.terrain_height;
    const subcell = u.Subcell.size;
    const subhalf = u.Subcell.half;
    for (0..th) |y| {
        for (0..tw) |x| {
            const index = y * tw + x;
            const terrain_type = @as(m.TerrainType, @enumFromInt(terrain[index]));
            const color = terrain_type.color();
            u.drawRect(@as(i32, @intCast(x * subcell)) - 4, @as(i32, @intCast(y * subcell)) - 4, subcell + 4, subcell + 4, color);
        }
    }

    if (Player.build_guide != null and Player.self != null) { // Move to drawGuide
        // While building, 2d subgrid loop near player
        var x: usize = u.Subcell.toCornerX(u.u16Sub(Player.self.?.x, u.Grid.cell_half));
        var y: usize = u.Subcell.toCornerY(u.u16Sub(Player.self.?.y, u.Grid.cell_half));
        while (y <= u.u16Add(Player.self.?.y, u.Grid.cell_half)) : (y += subcell) {
            while (x <= u.u16Add(Player.self.?.x, u.Grid.cell_half)) : (x += subcell) {
                //u.drawTexture(landTexture.?.*, @as(i32, @intCast(x)), @as(i32, @intCast(y)), rl.Color.white);
                if (isInBuildDistance(@intCast(x + subcell / 2), @intCast(y + subcell / 2))) {
                    const nodex: u16 = @intCast(x + subhalf);
                    const nodey: u16 = @intCast(y + subhalf);
                    const color = if (World.grid.blocked_subcells.contains(u.Point.at(nodex, nodey))) u.opacity(rl.Color.red, 0.1) else u.opacity(rl.Color.white, 0.1);
                    u.drawRect(@as(i32, @intCast(x)), @as(i32, @intCast(y)), subcell, subcell, color);
                }
            }
            x = u.Subcell.toCornerX(u.u16Sub(Player.self.?.x, u.Grid.cell_half));
        }
    }

    // While building/selecting, 1d subgrid loops along entire map
    if ((Player.build_guide != null and Player.self != null) or Player.selected[0] != null) {
        var colIndex: usize = 1;
        var rowIndex: usize = 1;
        const thinLine = 4;
        const thickLine = 4;
        // std.debug.print("current Camera.canvas_zoom: {}\n", .{Camera.canvas_zoom});

        while (rowIndex * subcell < World.height) : (rowIndex += 1) {
            rl.drawRectangle(0, u.canvasY(@intCast(subcell * rowIndex), Camera.canvas_offset_y, Camera.canvas_zoom), World.width, thinLine, u.opacity(rl.Color.white, 0.1));
        }
        while (colIndex * subcell < World.width) : (colIndex += 1) {
            rl.drawRectangle(u.canvasX(@as(i32, @intCast(subcell * colIndex)), Camera.canvas_offset_x, Camera.canvas_zoom), 0, thinLine, World.height, u.opacity(rl.Color.white, 0.1));
        }
        rowIndex = 1;
        while (rowIndex * u.Grid.cell_size < World.height) : (rowIndex += 1) {
            rl.drawRectangle(0, u.canvasY(@as(i32, @intCast(u.Grid.cell_size * rowIndex)), Camera.canvas_offset_y, Camera.canvas_zoom), World.width, thickLine, u.opacity(rl.Color.white, 0.2));
        }
        colIndex = 1;
        while (colIndex * u.Grid.cell_size < World.width) : (colIndex += 1) {
            rl.drawRectangle(u.canvasX(@as(i32, @intCast(u.Grid.cell_size * colIndex)), Camera.canvas_offset_x, Camera.canvas_zoom), 0, thickLine, World.height, u.opacity(rl.Color.white, 0.2));
        }
        if (Player.selected[0]) |selected| {
            if (selected.kind == e.Kind.Unit) {
                const unit = selected.ref.Unit;
                const cur = u.Point.atEntity(selected);
                const tar = unit.target.center;
                if (u.manhattanDistance(cur, tar) > World.GRID_CELL_SIZE) { // Macro pathing
                    const start_wp = u.Waypoint.closest(cur.x, tar.y);
                    const end_wp = u.Waypoint.closest(tar.x, tar.y);
                    // If no selection data or selected unit's position/target updated, finds waypoint path and sets Player.selection data
                    if (Player.selection_nodes[0] == null or Player.selection_nodes[1] == null or !Player.selection_nodes[0].?.equals(start_wp) or !Player.selection_nodes[1].?.equals(end_wp)) {
                        const new_path = World.grid.findWaypointPath(start_wp, end_wp) catch |err| switch (err) {
                            error.NoPath => null,
                            else => {
                                std.debug.print("Error: {}.\n", .{err});
                                return;
                            },
                        };
                        if (Player.selection_path) |*old| {
                            old.deinit(); // Frees previous
                        }
                        Player.selection_path = new_path;
                    }
                    Player.selection_nodes[0] = start_wp;
                    Player.selection_nodes[1] = end_wp;
                } else { // Micro pathing
                    const start_node = u.Subcell.closestNodePoint(cur.x, cur.y);
                    const end_node = u.Subcell.closestNodePoint(tar.x, tar.y);
                    // If no selection data or selected unit's position/target updated, finds node path and sets Player.selection data
                    if (Player.selection_nodes[0] == null or Player.selection_nodes[1] == null or !Player.selection_nodes[0].?.equals(start_node) or !Player.selection_nodes[1].?.equals(end_node)) {
                        const new_path = World.grid.findNodePath(start_node, unit.target) catch |err| switch (err) {
                            error.NoPath => null,
                            else => {
                                std.debug.print("Error: {}\n", .{err});
                                return;
                            },
                        };
                        if (Player.selection_path) |*old| {
                            old.deinit(); // Frees previous
                        }
                        Player.selection_path = new_path;
                    }
                    Player.selection_nodes[0] = start_node;
                    Player.selection_nodes[1] = end_node;
                }
                // Draws selection path
                if (Player.selection_path) |path| {
                    var i: usize = 0;
                    var j: usize = 1;
                    const col_filled = unit.entity.color(0.8);
                    const col_faded = unit.entity.color(0.4);
                    u.drawLineEx(u.Vector.fromCoords(unit.x, unit.y), u.Vector.fromCoords(path.items[i].x, path.items[i].y), 8, col_filled);
                    while (j < path.items.len) : (j += 1) {
                        const v1 = u.Vector.fromCoords(path.items[i].x, path.items[i].y);
                        const v2 = u.Vector.fromCoords(path.items[j].x, path.items[j].y);
                        u.drawLineEx(v1, v2, 4, col_faded);
                        if (path.items[i].equals(unit.immediate_target.center)) {
                            u.drawCircle(path.items[i].x, path.items[i].y, 8, col_faded);
                        } else {
                            u.drawCircle(path.items[i].x, path.items[i].y, 4, col_faded);
                        }
                        i += 1;
                    }
                    u.drawCircle(unit.target.center.x, unit.target.center.y, 8, col_filled);
                }
            }
        }
    }
}

fn drawEntities(profile_frame: bool) void {
    if (Player.selected[0] == null) {
        if (profile_frame) u.startTimer(2, "\n- - Drawing projectiles.");
        for (e.projectiles.items) |x| x.draw(1);
        if (profile_frame) u.endTimer(2, "Drawing projectiles took {} seconds.");
        if (profile_frame) u.startTimer(2, "\n- - Drawing resources.");
        for (e.resources.items) |x| x.draw(1);
        if (profile_frame) u.endTimer(2, "Drawing resources took {} seconds.");
        if (profile_frame) u.startTimer(2, "- - Drawing units.");
        for (e.units.items) |x| x.draw(1);
        if (profile_frame) u.endTimer(2, "Drawing units took {} seconds.");
        if (profile_frame) u.startTimer(2, "- - Drawing structures.");
        for (e.structures.items) |x| x.draw(1);
        if (profile_frame) u.endTimer(2, "Drawing structures took {} seconds.");
        if (profile_frame) u.startTimer(2, "- - Drawing players.");
        for (e.players.items) |x| x.draw(1);
        if (profile_frame) u.endTimer(2, "Drawing players took {} seconds.");
    } else { // Entity is selected
        for (e.projectiles.items) |x| x.draw(0.5);
        for (e.resources.items) |x| if (x.selected) x.draw(1) else x.draw(0.5);
        for (e.units.items) |x| if (x.selected) x.draw(1) else x.draw(0.5);
        for (e.structures.items) |x| if (x.selected) x.draw(1) else x.draw(0.5);
        for (e.players.items) |x| if (x.selected) x.draw(1) else x.draw(0.5);
    }
}

/// Draws user interface
pub fn drawInterface() void {
    if (Player.build_guide != null) drawGuide(Player.build_guide.?);
    if (Player.selection_origin != null) drawSelection(Player.selection_origin.?);

    // Bottom dashboard
    const dash_y: i32 = rl.getScreenHeight() - Config.DASHBOARD_HEIGHT;
    rl.drawRectangle(0, dash_y, rl.getScreenWidth(), Config.DASHBOARD_HEIGHT, rl.Color.init(255, 255, 255, 85));

    // Sets id to selected's owner, otherwise client's player id
    const id = if (Player.selected[0] != null) Player.selected[0].?.owner() else Player.id orelse 0;
    var x: u16 = 50;
    var fsize: i32 = 28; // Fontsize
    var buffer: [64]u8 = undefined;

    // Writes column 1 : Player
    var text = std.fmt.bufPrintZ(&buffer, "Player: {?}", .{id}) catch "Error";
    rl.drawText(text, x, dash_y + 20, fsize, rl.Color.black);
    text = std.fmt.bufPrintZ(&buffer, "Units: {}", .{Player.id_unit_count[id]}) catch "Error";
    rl.drawText(text, x, dash_y + 60, fsize, rl.Color.black);
    text = std.fmt.bufPrintZ(&buffer, "Structures: {}", .{Player.id_structure_count[id]}) catch "Error";
    rl.drawText(text, x, dash_y + 100, fsize, rl.Color.black);
    if (Player.build_guide != null) {
        text = std.fmt.bufPrintZ(&buffer, "Creating: {any}", .{Player.build_guide.?}) catch "Error";
        rl.drawText(text, x, dash_y + 140, fsize, rl.Color.black);
    } else if (Player.id_player[id]) |player| {
        text = std.fmt.bufPrintZ(&buffer, "Life: {}", .{player.life}) catch "Error";
        rl.drawText(text, x, dash_y + 140, fsize, rl.Color.black);
    }

    x = 400;
    // Writes column 2 : Primary selection
    if (Player.selected[0] != null) {
        const target: *e.Entity = Player.selected[0].?;
        const kind: e.Kind = target.kind;
        const ref = target.ref;
        var y: i32 = dash_y + 20;
        for (0..4) |field| {
            defer y += 40; // 20, 60, 100, 140
            text = std.fmt.bufPrintZ(&buffer, "", .{}) catch "Error";
            if (kind == e.Kind.Player) {
                switch (field) {
                    0 => text = std.fmt.bufPrintZ(&buffer, "Player", .{}) catch "Error",
                    1 => text = std.fmt.bufPrintZ(&buffer, "Life: {}", .{target.life()}) catch "Error",
                    else => {},
                }
            } else if (kind == e.Kind.Unit) {
                //const unit = ref.Unit;
                switch (field) {
                    0 => text = std.fmt.bufPrintZ(&buffer, "{s} {s} ({s})", .{ @tagName(target.ref.Unit.genome.sex), target.ref.Unit.genome.code, @tagName(ref.Unit.state) }) catch "Error",
                    1 => text = std.fmt.bufPrintZ(&buffer, "Life: {}, Energy: {}", .{ target.ref.Unit.life, target.ref.Unit.energy }) catch "Error",
                    2 => // Checks for carried resources
                    {
                        const carry = ref.Unit.resources;
                        text = std.fmt.bufPrintZ(&buffer, "{s}: {d}, {s}: {d}, {s}: {d}, {s}: {d}", .{ u.resourceTypeFromClass(0), carry[0], u.resourceTypeFromClass(1), carry[1], u.resourceTypeFromClass(2), carry[2], u.resourceTypeFromClass(3), carry[3] }) catch "Error";
                    },
                    3 => text = std.fmt.bufPrintZ(&buffer, "Experience: {}", .{target.ref.Unit.experience}) catch "Error",
                    else => {},
                }
            } else if (kind == e.Kind.Structure) {
                switch (field) {
                    0 => text = std.fmt.bufPrintZ(&buffer, "{c} ({s})", .{ target.ref.Structure.class, @tagName(e.Kind.Structure) }) catch "Error",
                    1 => text = std.fmt.bufPrintZ(&buffer, "Life: {}", .{target.life()}) catch "Error",
                    2 => text = std.fmt.bufPrintZ(&buffer, "Capacity: {}/{}", .{ target.ref.Structure.capacity, e.Structure.preset(target.ref.Structure.class).capacity }) catch "Error",
                    3 => text = std.fmt.bufPrintZ(&buffer, "Materials: {}", .{target.ref.Structure.materials}) catch "Error",
                    else => {},
                }
            } else if (kind == e.Kind.Resource) {
                switch (field) {
                    0 => text = std.fmt.bufPrintZ(&buffer, "{c} ({s})", .{ target.ref.Resource.class, @tagName(e.Kind.Resource) }) catch "Error",
                    1 => text = std.fmt.bufPrintZ(&buffer, "Remaining: {}", .{target.life()}) catch "Error",
                    2 => text = std.fmt.bufPrintZ(&buffer, "Yield: {d}", .{target.ref.Resource.yield / Config.TICKRATE}) catch "Error",
                    3 => text = std.fmt.bufPrintZ(&buffer, "Growth: {d}", .{target.ref.Resource.growth}) catch "Error",
                    else => {},
                }
            }
            rl.drawText(text, x, y, fsize, rl.Color.black); // Draws field data or ""
        }

        fsize = 15;
        var target_count: usize = 1;
        // Writes columns 3 - 18 : Secondary selections
        for (Player.selected, 0..) |selected, i| {
            if (selected == null or i <= 0) continue;
            const index = @as(u16, @intCast(i - 1));
            x = 750 + (65 * @divFloor(index, 8));
            y = dash_y + 20 + (20 * (index % 8));
            const label: [8]u8 = switch (kind) {
                e.Kind.Player => "Player  ".*,
                e.Kind.Resource => .{selected.?.ref.Resource.class} ++ .{' '} ** 7,
                e.Kind.Structure => .{selected.?.ref.Structure.class} ++ .{' '} ** 7,
                e.Kind.Unit => selected.?.ref.Unit.genome.code,
            };
            text = std.fmt.bufPrintZ(&buffer, "{s}", .{label}) catch "Error";
            rl.drawText(text, x, y, fsize, rl.Color.black);
            target_count += 1;
        }
        fsize = 28;
        if (target_count > 1) { // Draws secondary target count
            text = std.fmt.bufPrintZ(&buffer, "{}", .{target_count}) catch "Error";
            rl.drawText(text, 750 + (65 * 31), dash_y + 20 + (20 * 7), fsize, rl.Color.black);
        } else if (kind == e.Kind.Unit) { // Primary selection properties
            x = 750;
            for (ref.Unit.genome.traits, 0..) |trait, i| {
                const index = @as(u16, @intCast(i));
                x = 750 + (260 * @divFloor(index, 4));
                y = dash_y + 20 + (40 * (index % 4));
                text = std.fmt.bufPrintZ(&buffer, "{s}:", .{@tagName(trait.metric)}) catch "Error";
                rl.drawText(text, x, y, fsize, rl.Color.black);
                text = std.fmt.bufPrintZ(&buffer, "{d:.2}", .{trait.value}) catch "Error";
                rl.drawText(text, x + 130, y, fsize, rl.Color.black);
            }
        }
    }

    // Development tools
    rl.drawFPS(40, 40);
}

// Game conditions
//----------------------------------------------------------------------------
// May want to move into a separate module, `world` or `map`
const Map = struct {
    file: m.MapFile,

    pub fn open(allocator: *std.mem.Allocator, id: u32) !Map {
        const filename = switch (id) {
            0 => "maps/mini.map",
            1 => "maps/default.map",
            2 => "maps/three_lanes.map",
            3 => "maps/islands.map",
            else => return error.MapNotFound,
        };

        const map_file = try m.MapFile.load(filename, allocator.*);

        // Initialize world with loaded data
        try World.initializeMap(allocator, id, map_file);

        std.debug.print("Loaded map: {} ({}x{})\n", .{ id, map_file.width, map_file.height });
        return Map{ .file = map_file };
    }

    pub fn close(self: *Map, allocator: *std.mem.Allocator) void {
        self.file.deinit(allocator.*);
    }
};

/// Returns true when `tick` is an exact divisor of the world's `MOVEMENT_DIVISIONS`.
pub fn moveDivision(tick: i16) bool {
    return @rem(tick, World.MOVEMENT_DIVISIONS) == 0;
}

/// Returns true if `tick` is an exact divisor of the specified `multiple` of the world's `MOVEMENT_DIVISIONS`.
pub fn moveDivMultiple(tick: i16, multiple: i16) bool {
    return @rem(tick, World.MOVEMENT_DIVISIONS * multiple) == 0;
}

// AI Player
//----------------------------------------------------------------------------
pub const EnemyPlayerAI = struct {
    player: *e.Player,

    var directions = [8]u8{ 1, 2, 3, 4, 6, 7, 8, 9 };

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
        if (tick % move_all < move_all / 2) // half the time
            continuousMove(ai, tick, move_duration) catch return null;
        if (tick % 180 == 0) {
            // Shuffles direction array
            u.shuffleArray(u8, &directions);

            // Generate a "random" structure class value between 0 and 3 (0 at 50%)
            const build_index = if (tick % move_all < move_all / 2) 0 else u.asU8(u64, tick / 300 % 4);
            constructBuilding(ai, u.classFromIndexStructure(build_index), tick);
        }
    }

    pub fn constructBuilding(ai: *e.Player, class: u8, tick: u64) void {
        const building = e.Structure.preset(class);

        const dx: i32 = @rem(@as(i32, @intCast(tick)), 600) - 300;
        const dy: i32 = @rem(@as(i32, @intCast(tick / 2)), 600) - 300;

        const map_x: u16 = @intCast(@as(i32, ai.x) + dx);
        const map_y: u16 = @intCast(@as(i32, ai.y) + dy);

        const subcell = u.mapToSubcell(map_x, map_y);

        const snapped = u.Subcell.snapToCorner(
            subcell.corner()[0],
            subcell.corner()[1],
            building.width,
            building.height,
        );

        _ = e.Structure.construct(ai.id, snapped[0], snapped[1], class);
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
//-----------------------------------------------------------------------------
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
    } else if (Config.keys.actionActive(key_input, u.Key.Action.BuildRemove)) {
        Player.build_index = null;
        Player.build_guide = null;
        std.debug.print("noting the backspace action", .{});
        if (Player.selected[0]) |selected| {
            std.debug.print("finding selected", .{});
            if (Player.id != null and selected.owner() == Player.id.? and selected.kind == e.Kind.Structure) {
                std.debug.print("trying to destroy", .{});
                selected.ref.Structure.destroy();
            }
        }
    }

    if (Player.build_index != null) { // Sets build guide
        if (Player.build_guide == null or Player.build_guide.? != Player.build_index.?) {
            std.debug.print("Set a build guide!\n", .{});
            Player.build_guide = u.classFromIndexStructure(Player.build_index.?);
        } else {
            std.debug.print("Removed build guide!\n", .{});
            Player.build_guide = null;
        }
        setSelection(null); // Clears selection
    }
}

pub fn executeBuild(class: u8) void {
    const mouse_position = rl.getMousePosition();
    const xy = findBuildPosition(class, mouse_position);
    // const mouse_closest_center = u.screenToSubcell(mouse_position).node;
    //if (!isInBuildDistance(mouse_closest_center.x, mouse_closest_center.y) or Player.id == null) return;
    if (Player.id == null or !canBuildOn(xy[0], xy[1], e.Structure.preset(class).width, e.Structure.preset(class).height)) return;
    const built = e.Structure.construct(Player.id.?, xy[0], xy[1], class);
    if (built) |building| {
        std.debug.print("Structure built successfully: \n{}.\nPointer address of structure is: {}.\n", .{ building, @intFromPtr(building) });
        setSelection(building.entity); // set Player.selected to building entity here as a "hack" to deselect
    } else {
        std.debug.print("Failed to build structure\n", .{});
        // Handle the failure case, e.g., notify the player
    }
    Player.build_guide = null;
}

fn findBuildPosition(class: u8, mouse_position: rl.Vector2) [2]u16 {
    const building = e.Structure.preset(class);
    const x_offset = u.asF32(u16, u.Subcell.size) * Camera.canvas_zoom;
    const y_offset = u.asF32(u16, u.Subcell.size) * Camera.canvas_zoom;

    const adjusted_position = mouse_position.add(rl.Vector2.init(x_offset, y_offset));
    const subcell = u.screenToSubcell(adjusted_position);

    var snapped = u.Subcell.snapToCorner(subcell.corner()[0], subcell.corner()[1], building.width, building.height);

    //if (@rem(@divTrunc((building.width + building.height), 2), u.Subcell.size) != 0) { // If not subcell multiple
    const mouse_map_pos = u.screenToMap(mouse_position);
    if (mouse_map_pos[0] > subcell.node.x - u.Subcell.size) snapped[0] += (u.Subcell.half);
    if (mouse_map_pos[1] > subcell.node.y - u.Subcell.size) snapped[1] += (u.Subcell.half);

    //std.debug.print("Found build position at {}, {}. \n", .{ snapped[0], snapped[1] });
    return [2]u16{ snapped[0], snapped[1] };
}

fn isInBuildDistance(x: u16, y: u16) bool {
    if (Player.self == null) return false;
    const distance_max = u.Grid.cell_half; //u.asU32(u16, e.Structure.preset(class).width + e.Structure.preset(class).height);
    //const distance = std.math.sqrt(u.distanceSquared(u.Point.at(Player.self.?.x, Player.self.?.y), u.Point.at(x, y)));
    const px: i32 = @intCast(Player.self.?.x);
    const py: i32 = @intCast(Player.self.?.y);
    const distance = @max(@abs(px - @as(i32, x)), @abs(py - @as(i32, y)));
    return distance <= distance_max;
}

fn canBuildOn(x: u16, y: u16, width: u16, height: u16) bool {
    const in_map = u.isInMap(x, y, width, height);
    const in_range = u.Subcell.forEachBlockedSubcell(
        x,
        y,
        width,
        height,
        struct {
            fn f(subcell: u.Subcell) bool {
                const node = subcell.node;
                return isInBuildDistance(node.x, node.y);
            }
        }.f,
    );
    const open = if (in_map) (u.isOpenGround(x, y, width, height) catch false) else false;
    return open and in_range;
}

// Interface
//----------------------------------------------------------------------------
pub fn drawGuide(class: u8) void {
    if (Player.self == null) return;
    const mouse_position = rl.getMousePosition();
    const xy = findBuildPosition(class, mouse_position);
    const building = e.Structure.preset(class);
    if (!canBuildOn(xy[0], xy[1], building.width, building.height)) {
        u.drawGuideFail(xy[0], xy[1], building.width, building.height, Player.self.?.entity.color(1));
    } else {
        u.drawGuide(xy[0], xy[1], building.width, building.height, Player.self.?.entity.color(1));
    }
}

pub fn drawSelection(origin: rl.Vector2) void { // Selection box
    if (Player.self == null) return;
    const col = u.idToColor(Player.id orelse 0, 0.5);
    const mouse_pos = rl.getMousePosition();
    const min_x = @min(origin.x, mouse_pos.x);
    const max_x = @max(origin.x, mouse_pos.x);
    const min_y = @min(origin.y, mouse_pos.y);
    const max_y = @max(origin.y, mouse_pos.y);
    const rect = rl.Rectangle.init(min_x, min_y, max_x - min_x, max_y - min_y);
    rl.drawRectangleRounded(rect, 0.1, 4, col);
}
