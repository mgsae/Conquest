const std: type = @import("std");
const rl = @import("raylib");
const utils = @import("utils.zig");
const main = @import("main.zig");

// Setting up entities
pub var players: std.ArrayList(*Player) = undefined;
pub var units: std.ArrayList(*Unit) = undefined;
pub var structures: std.ArrayList(*Structure) = undefined;

const Kind = enum {
    Player,
    Unit,
    Structure,
};

pub const Entity = struct {
    kind: Kind,
    content: union(Kind) { // Stores pointer to the actual data
        Player: *Player,
        Unit: *Unit,
        Structure: *Structure,
    },

    pub fn width(self: *Entity) u16 {
        return switch (self.kind) {
            Kind.Player => self.content.Player.width,
            Kind.Unit => self.content.Unit.width,
            Kind.Structure => self.content.Structure.width,
        };
    }

    pub fn height(self: *Entity) u16 {
        return switch (self.kind) {
            Kind.Player => self.content.Player.height,
            Kind.Unit => self.content.Unit.height,
            Kind.Structure => self.content.Structure.height,
        };
    }

    pub fn x(self: *Entity) u16 {
        return switch (self.kind) {
            Kind.Player => self.content.Player.x,
            Kind.Unit => self.content.Unit.x,
            Kind.Structure => self.content.Structure.x,
        };
    }

    pub fn y(self: *Entity) u16 {
        return switch (self.kind) {
            Kind.Player => self.content.Player.y,
            Kind.Unit => self.content.Unit.y,
            Kind.Structure => self.content.Structure.y,
        };
    }

    /// Returns the bigger of two entities, or null if same size.
    pub fn bigger(e1: *Entity, e2: *Entity) ?*Entity {
        switch (utils.bigger(e1.width(), e1.height(), e2.width(), e2.height())) {
            0 => return e1,
            1 => return e2,
            2, 3 => return null,
        }
    }
};

// Player //
//----------------------------------------------------------------------------------
pub const Player = struct {
    entity: *Entity,
    x: u16,
    y: u16,
    width: u16,
    height: u16,
    color: rl.Color,
    speed: f16 = 5,
    direction: u8 = 2,
    local: bool = false,

    pub fn draw(self: Player) void {
        utils.drawEntity(self.x, self.y, self.width, self.height, self.color);
    }

    pub fn update(self: *Player, key_input: ?u32) anyerror!void {
        if (self.local) { // Local player
            if (key_input) |input| {
                if (input > 0) {
                    // std.debug.print("Key input!\n", .{});
                    try self.updateMoveInput(input);
                    self.updateActionInput(input);
                } else {
                    // std.debug.print("No key input.\n", .{});
                }
            }
        } else { // If AI or remote player
            // updateMoveEvent, determine movement based on network or AI logic
            // updateActionEvent, determine ability use based on network or AI logic
        }
    }

    fn updateMoveInput(self: *Player, key_input: u32) !void {
        const speed = utils.scaleToTickRate(self.speed);
        var changed_x: ?u16 = null;
        var changed_y: ?u16 = null;

        // Processes movement input
        if (main.keys.actionActive(key_input, utils.Key.Action.MoveUp)) {
            changed_y = utils.mapClampY(@truncate(utils.i32SubFloat(f32, self.y, speed)), self.height);
            self.direction = 8; // Numpad direction
        }
        if (main.keys.actionActive(key_input, utils.Key.Action.MoveLeft)) {
            changed_x = utils.mapClampX(@truncate(utils.i32SubFloat(f32, self.x, speed)), self.width);
            self.direction = 4; // Numpad direction
        }
        if (main.keys.actionActive(key_input, utils.Key.Action.MoveDown)) {
            changed_y = utils.mapClampY(@truncate(utils.i32AddFloat(f32, self.y, speed)), self.height);
            self.direction = 2; // Numpad direction
        }
        if (main.keys.actionActive(key_input, utils.Key.Action.MoveRight)) {
            changed_x = utils.mapClampX(@truncate(utils.i32AddFloat(f32, self.x, speed)), self.width);
            self.direction = 6; // Numpad direction
        }

        if (changed_x != null or changed_y != null) try executeMovement(self, changed_x, changed_y, speed);
    }

    fn executeMovement(self: *Player, changed_x: ?u16, changed_y: ?u16, speed: f32) !void {
        const old_x = self.x;
        const old_y = self.y;
        var new_x: ?u16 = changed_x;
        var new_y: ?u16 = changed_y;
        var obstacleX: ?*Entity = null;
        var obstacleY: ?*Entity = null;
        // const deltaXy = utils.deltaXy(old_x, old_y, new_x orelse old_x, new_y orelse old_y);
        // std.debug.print("Player movement direction: {}. Delta to angle: {}. Angle from dir: {}. Vector to delta: {any}.\n", .{ self.direction, @as(i64, @intFromFloat(utils.deltaToAngle(deltaXy[0], deltaXy[1]))), utils.angleFromDir(self.direction), utils.vectorToDelta(utils.deltaToAngle(deltaXy[0], deltaXy[1]), speed) });

        // Gets potential obstacle entities on both axes
        if (new_x != null) obstacleX = main.grid.collidesWith(new_x.?, self.y, self.width, self.height, self.entity) catch null;
        if (new_y != null) obstacleY = main.grid.collidesWith(self.x, new_y.?, self.width, self.height, self.entity) catch null;

        // Executes horizontal movement
        if (new_x != null) {
            if (obstacleX == null) {
                self.x = new_x.?;
            } else if (new_y == null and (obstacleX.?.kind == Kind.Unit)) { // If unit obstacle, try pushing horizontally
                const resistance = 0.1; // maybe depend on size relation
                const force = (1.0 - resistance);
                const difference = @as(f64, @floatFromInt(@as(i32, new_x.?) - @as(i32, old_x)));
                new_x = @as(u16, @intCast(@as(i32, old_x) + @as(i32, @intFromFloat(@round(difference * force)))));

                // Pushes obstacle, and checks whether push was unhindered, or if pushed obstacle in turn ran into a further obstacle
                std.debug.print("Pushing horizontally, angle: {}, distance: {}\n", .{ utils.angleFromDir(self.direction), speed * force });
                const push_distance = obstacleX.?.content.Unit.pushed(utils.angleFromDir(self.direction), speed * force);
                std.debug.print("Horizontal push distance: {}\n", .{push_distance});
                if (push_distance >= speed * force) {
                    obstacleX = main.grid.collidesWith(new_x.?, self.y, self.width, self.height, self.entity) catch null;
                } else {
                    new_x = @as(u16, @intCast(@as(i32, old_x) + @as(i32, @intFromFloat(push_distance)))); // Moves effective push distance and re-checks collision
                    obstacleX = main.grid.collidesWith(new_x.?, self.y, self.width, self.height, self.entity) catch null;
                }
                if (obstacleX == null) self.x = new_x.?; // If no collision now, repositions x
            }
        }

        // Executes vertical movement
        if (new_y != null) {
            if (obstacleY == null) {
                self.y = new_y.?;
            } else if (new_x == null and (obstacleY.?.kind == Kind.Unit)) { // If unit collider, try pushing vertically
                const resistance = 0.1; // maybe depend on size relation
                const force = (1.0 - resistance);
                const difference = @as(f64, @floatFromInt(@as(i32, new_y.?) - @as(i32, old_y)));
                new_y = @as(u16, @intCast(@as(i32, old_y) + @as(i32, @intFromFloat(@round(difference * force)))));

                // Pushes obstacle, and checks whether push was unhindered, or if pushed obstacle in turn ran into a further obstacle
                std.debug.print("Pushing vertically, angle: {}, distance: {}\n", .{ utils.angleFromDir(self.direction), speed * force });
                const push_distance = obstacleY.?.content.Unit.pushed(utils.angleFromDir(self.direction), speed * force);
                std.debug.print("Vertical push distance: {}\n", .{push_distance});
                if (push_distance >= speed * force) {
                    obstacleY = main.grid.collidesWith(self.x, new_y.?, self.width, self.height, self.entity) catch null;
                } else {
                    new_y = @as(u16, @intCast(@as(i32, old_y) + @as(i32, @intFromFloat(push_distance)))); // Moves effective push distance and re-checks collision
                    obstacleY = main.grid.collidesWith(self.x, new_y.?, self.width, self.height, self.entity) catch null;
                }
                if (obstacleY == null) self.y = new_y.?; // If no collision now, repositions y
            }
        }

        // If new movement, updates game grid
        if ((new_x != null and new_x.? != old_x) or (new_y != null and new_y.? != old_y)) {
            main.grid.updateCellPosition(self.entity, old_x, old_y);
        }
    }

    fn updateActionInput(self: *Player, key_input: u32) void {
        if (main.keys.actionActive(key_input, utils.Key.Action.BuildConfirm)) {
            if (main.build_guide != null) {
                executeBuild(self, main.build_guide.?);
                main.build_guide = null;
            }
            return;
        }

        var build_index: ?u8 = null;
        if (main.keys.actionActive(key_input, utils.Key.Action.BuildOne)) {
            build_index = 0;
        } else if (main.keys.actionActive(key_input, utils.Key.Action.BuildTwo)) {
            build_index = 1;
        } else if (main.keys.actionActive(key_input, utils.Key.Action.BuildThree)) {
            build_index = 2;
        } else if (main.keys.actionActive(key_input, utils.Key.Action.BuildFour)) {
            build_index = 3;
        }

        if (build_index != null) { // Sets build guide
            if (main.build_guide == null or main.build_guide.? != build_index.?) {
                main.build_guide = build_index;
            } else {
                main.build_guide = null;
            }
        }
    }

    // Maybe refactor to abstract the build_index/class relation, to support tech trees
    fn executeBuild(self: *Player, build_index: u8) void {
        const xy = findBuildPosition(self, build_index);
        const built = Structure.construct(xy[0], xy[1], build_index);
        if (built) |building| {
            std.debug.print("Structure built successfully: \n{}.\nPointer address of structure is: {}.\n", .{ building, @intFromPtr(building) });
            // Do something with the structure
        } else {
            std.debug.print("Failed to build structure\n", .{});
            // Handle the failure case, e.g., notify the player or log the error
        }
    }

    fn findBuildPosition(self: *Player, class: u8) [2]u16 {
        const building = Structure.preset(class);
        const min_distance = if (utils.isHorz(self.direction)) (self.width / 2) + (building.width / 2) else (self.height / 2) + (building.height / 2);
        const sc_size = utils.subcell.size;
        const compensation: [2]i16 = switch (self.direction) {
            2 => [2]i16{ sc_size / 2, sc_size },
            4 => [2]i16{ 0, sc_size / 2 },
            6 => [2]i16{ sc_size, sc_size / 2 },
            else => [2]i16{ sc_size / 2, 0 },
        };
        const compensated_x = utils.u16Clamped(i16, @as(i16, @intCast(@as(i16, @intCast(self.x)) + compensation[0])));
        const compensated_y = utils.u16Clamped(i16, @as(i16, @intCast(@as(i16, @intCast(self.y)) + compensation[1])));
        const shifted_xy = utils.dirOffset(@as(u16, @intCast(compensated_x)), @as(u16, @intCast(compensated_y)), self.direction, min_distance);
        const map_x = utils.mapClampX(@as(i16, @intCast(shifted_xy[0])), building.width);
        const map_y = utils.mapClampY(@as(i16, @intCast(shifted_xy[1])), building.height);
        const subcell_xy = utils.subcell.snapPosition(map_x, map_y, building.width, building.height);
        return subcell_xy;
    }

    pub fn createLocal(x: u16, y: u16) !*Player {
        const entity = try main.grid.allocator.create(Entity); // Allocate memory for the parent entity
        const player = try main.grid.allocator.create(Player); // Allocate memory for Player and get a pointer

        player.* = Player{
            .entity = entity,
            .x = x,
            .y = y,
            .width = 100,
            .height = 100,
            .speed = 5,
            .color = rl.Color.green,
            .local = true,
        };
        entity.* = Entity{
            .kind = Kind.Player,
            .content = .{ .Player = player },
        };

        std.debug.print("Created local player at ({}, {}) with entity pointer {}\n", .{ x, y, @intFromPtr(entity) });
        try main.grid.addToCell(entity, null, null);
        return player;
    }

    pub fn createRemote(x: u16, y: u16) !*Player {
        const entity = try main.grid.allocator.create(Entity); // Allocate memory for the parent entity
        const player = try main.grid.allocator.create(Player); // Allocate memory for Player and get a pointer

        player.* = Player{
            .entity = entity,
            .x = x,
            .y = y,
            .width = 100,
            .height = 100,
            .speed = 5,
            .color = rl.Color.red,
            .local = false,
        };
        entity.* = Entity{
            .kind = Kind.Player,
            .content = .{ .Player = player },
        };

        std.debug.print("Created remote player at ({}, {}) with entity pointer {}\n", .{ x, y, @intFromPtr(entity) });
        try main.grid.addToCell(entity, null, null);
        return player;
    }

    pub fn drawGuide(self: *Player, class: u8) void {
        const xy = self.findBuildPosition(class);
        const building = Structure.preset(class);
        const collides = main.grid.collidesWith(xy[0], xy[1], building.width, building.height, null) catch null;
        if (collides != null or !utils.isInMap(xy[0], xy[1], building.width, building.height)) {
            utils.drawGuideFail(xy[0], xy[1], building.width, building.height, building.color);
        } else {
            utils.drawGuide(xy[0], xy[1], building.width, building.height, building.color);
        }
    }
};

// Unit
//----------------------------------------------------------------------------------
pub const Unit = struct {
    entity: *Entity,
    class: u8,
    x: u16,
    y: u16,
    width: u16,
    height: u16,
    life: i16,
    target: utils.Point,
    last_step: utils.Point,
    cached_cellsigns: [9]u32, // Last known cellsigns of relevant cells

    pub fn draw(self: *Unit) void {
        utils.drawEntity(self.x, self.y, self.width, self.height, self.color());
    }

    pub fn update(self: *Unit) !void {
        if (self.life <= 0) {
            try self.die(null);
            return;
        }
        if (main.moveDivison(self.life)) {
            self.last_step = utils.Point.at(self.x, self.y);
            const step = self.getStep();
            try self.move(step.x, step.y);
        }
        self.life -= 1;
    }

    /// Searches for collision at `new_x`,`new_y`. If no obstacle is found, sets position to `x`, `y`. If obstacle is found, tries moving along edge.
    fn move(self: *Unit, new_x: u16, new_y: u16) !void {
        const old_x = self.x;
        const old_y = self.y;

        // If step is out of bounds, clamps to map (ignoring collision) if needed, and retargets
        if (!utils.isInMap(new_x, new_y, self.width, self.height)) {
            if (!utils.isInMap(old_x, old_y, self.width, self.height)) {
                const clamped_x = utils.mapClampX(@as(i16, @intCast(new_x)), self.width);
                const clamped_y = utils.mapClampY(@as(i16, @intCast(new_y)), self.height);
                _ = self.tryMove(clamped_x, clamped_y, old_x, old_y);
            }
            _ = self.retarget(utils.randomU16(main.map_width), utils.randomU16(main.map_height)); // <--- just testing
            return;
        }

        if (!self.tryMove(new_x, new_y, old_x, old_y)) { // Tries executing regular move
            _ = self.moveAlongAxis(new_x, new_y, old_x, old_y); // If collided, tries moving along either axis
        }

        if (old_x == self.x and old_y == self.y) { // If no change after moving, retarget
            _ = self.retarget(utils.randomU16(main.map_width), utils.randomU16(main.map_height)); // <--- just testing
            return;
        }
    }

    /// Searches for collision at `new_x`,`new_y`. If unhindered, executes the movement, updates the grid, and returns `true`. If hindered, returns `false`.
    fn tryMove(self: *Unit, new_x: u16, new_y: u16, old_x: u16, old_y: u16) bool {
        // Causes entities to stop at "undiscovered" cells:
        //if (entities == null or entities.?.items.len == 0) {
        //    std.debug.print("Entities list is empty.\n", .{});
        //    return true;
        //}
        //std.debug.print("Entities list retrieved: length = {any}, address = {}\n", .{ entities.?.items.len, @intFromPtr(entities) });

        const collision = self.checkCollision(new_x, new_y);
        if (collision == null) { // No obstacle, move
            self.x = new_x;
            self.y = new_y;
            main.grid.updateCellPosition(self.entity, old_x, old_y);
            return true;
        }
        return false;
    }

    /// Compares `new_x`,`new_y` and `old_x`,`old_y` to find largest difference. Tries `tryMove()` along either dimension, prioritizing the dominant axis.
    /// Executes move if collision check passes, returning `true`.
    fn moveAlongAxis(self: *Unit, new_x: u16, new_y: u16, old_x: u16, old_y: u16) bool {
        const diffX: i32 = @as(i32, @intCast(new_x)) - @as(i32, @intCast(old_x));
        const diffY: i32 = @as(i32, @intCast(new_y)) - @as(i32, @intCast(old_y));

        if (@abs(diffX) > @abs(diffY)) { // Horizontal axis dominant
            if (!self.tryMove(new_x, old_y, old_x, old_y)) {
                return self.tryMove(old_x, new_y, old_x, old_y);
            }
        } else { // Vertical axis dominant
            if (!self.tryMove(old_x, new_y, old_x, old_y)) {
                return self.tryMove(new_x, old_y, old_x, old_y);
            }
        }
        return true; // Moved along dominant axis
    }

    /// Iterates through entities from current cell's index of `Grid.sections`. Checks for AABB collisions. Returns the first colliding `*Entity`, otherwise null.
    fn checkCollision(self: *Unit, x: u16, y: u16) ?*Entity {
        const entities = main.grid.sectionEntities(utils.Grid.x(x), utils.Grid.y(y));
        if (entities != null) {
            const half_width = @divTrunc(self.width, 2);
            const half_height = @divTrunc(self.height, 2);
            const left = @max(half_width, x) - half_width;
            const right = x + half_width;
            const top = @max(half_height, y) - half_height;
            const bottom = y + half_height;

            for (entities.?.items) |entity| {
                if (entity == self.entity) {
                    continue;
                }

                const entity_x = entity.x();
                const entity_y = entity.y();
                const entity_half_width = @divTrunc(entity.width(), 2);
                const entity_half_height = @divTrunc(entity.height(), 2);

                const entity_left = @max(entity_half_width, entity_x) - entity_half_width;
                const entity_right = entity_x + entity_half_width;
                const entity_top = @max(entity_half_height, entity_y) - entity_half_height;
                const entity_bottom = entity_y + entity_half_height;

                if ((left < entity_right) and (right > entity_left) and
                    (top < entity_bottom) and (bottom > entity_top))
                {
                    //std.debug.print("Colliding with entity {}.\n", .{i});
                    return entity; // Return the first colliding entity
                }
            }
        }
        return null;
    }

    /// Unit is an obstacle pushed by another entity. Searches for collision. If no new obstacle is found, unit moves `distance`.
    /// If new obstacle is another unit, pushes it a size-factored distance, then moves the same distance. Returns the effective distance moved.
    pub fn pushed(self: *Unit, angle: f32, distance: f32) f32 {
        const old_x = self.x;
        const old_y = self.y;
        const new_x: u16, const new_y: u16 = calculatePushPosition(self, angle, distance);

        var moved_distance: f32 = distance;

        // Squeeze to flag unit as a pushee, preventing circularity from recursive call -- need a different way to do this
        self.width = preset(self.class).width - 1;
        self.height = preset(self.class).height - 1;

        if (!utils.isInMap(new_x, new_y, self.width, self.height)) return moved_distance;

        const obstacle = main.grid.collidesWith(new_x, new_y, self.width, self.height, self.entity) catch null;

        if (obstacle == null) { // Pushing doesn't collide with another obstacle
            self.x = new_x;
            self.y = new_y;
            main.grid.updateCellPosition(self.entity, old_x, old_y);
        } else if (obstacle.?.kind == Kind.Unit) { // Pushed unit collides with another unit

            const obstacle_unit = obstacle.?.content.Unit;

            // Checks that obstacle_unit isn't already a pushee
            if (obstacle_unit.width != preset(obstacle_unit.class).width or obstacle_unit.height != preset(obstacle_unit.class).height) {
                moved_distance = moved_distance / 2;
            } else {
                moved_distance = pushed(obstacle_unit, angle, @min(distance, distance * utils.sizeFactor(self.width, self.height, obstacle_unit.width, obstacle_unit.height)));

                const push_delta_xy = utils.vectorToDelta(angle, moved_distance);
                const push_new_x = @as(u16, @intFromFloat(@as(f32, @floatFromInt(self.x)) + push_delta_xy[0]));
                const push_new_yY = @as(u16, @intFromFloat(@as(f32, @floatFromInt(self.y)) + push_delta_xy[1]));

                self.move(push_new_x, push_new_yY) catch return 0; // Re-checks for collision and updates grid here
            }
        }

        // Resets dimensions to flag as ready for future pushing
        self.width = preset(self.class).width;
        self.height = preset(self.class).height;
        return moved_distance; // Returns effective moved distance
    }

    fn calculatePushPosition(self: *Unit, angle: f32, distance: f32) [2]u16 {
        const delta_xy = utils.vectorToDelta(angle, distance);
        const new_x_float: f32 = @round(@as(f32, @floatFromInt(self.x)) + delta_xy[0]);
        const new_y_float: f32 = @round(@as(f32, @floatFromInt(self.y)) + delta_xy[1]);

        const new_x = @as(u16, @intFromFloat(utils.u16Clamped(f32, new_x_float)));
        const new_y = @as(u16, @intFromFloat(utils.u16Clamped(f32, new_y_float)));

        return [2]u16{ new_x, new_y };
    }

    /// Sets unit's target destination while taking into account its current `cellsign`. Returns `true` if setting new target, returns `false` if target remains the same.
    pub fn retarget(self: *Unit, x: u16, y: u16) bool {
        // do more stuff here for pathing
        const prev_target = self.target;

        self.target = utils.Point.at(x, y);
        return prev_target.x != self.target.x or prev_target.y != self.target.y;
    }

    /// Calculates and returns the unit's immediate destination based on its current `target` and `cellsign`.
    fn getStep(self: *Unit) utils.Point {
        // do more stuff here for pathing
        const dx = @as(i32, @intCast(self.x)) - @as(i32, @intCast(self.target.x));
        const dy = @as(i32, @intCast(self.y)) - @as(i32, @intCast(self.target.y));
        if (@abs(dx + dy) < @as(i32, @intFromFloat(self.speed()))) {
            _ = self.retarget(utils.randomU16(main.map_width), utils.randomU16(main.map_height)); // <--- just testing
        }
        const angle = utils.deltaToAngle(dx, dy);
        const vector = utils.vectorToDelta(angle, self.speed());
        return utils.deltaPoint(self.x, self.y, vector[0], vector[1]);
    }

    pub fn create(x: u16, y: u16, class: u8) !*Unit {
        const entity = try main.grid.allocator.create(Entity); // Memory for the parent entity
        const unit = try main.grid.allocator.create(Unit); // Memory for Unit
        const from_class = Unit.preset(class);

        unit.* = Unit{
            .entity = entity,
            .class = class,
            .width = from_class.width,
            .height = from_class.height,
            .life = from_class.life,
            .x = x,
            .y = y,
            .target = utils.Point.at(utils.randomU16(main.map_width), utils.randomU16(main.map_height)), // <--- just testing
            .last_step = utils.Point.at(x, y),
            .cached_cellsigns = [_]u32{0} ** 9,
        };

        entity.* = Entity{
            .kind = Kind.Unit,
            .content = .{ .Unit = unit }, // Store the pointer to the Unit
        };

        try main.grid.addToCell(entity, null, null);
        return unit;
    }

    pub fn die(self: *Unit, cause: ?u8) !void {
        // Death effect
        if (cause) |c| {
            switch (c) {
                else => {}, // Catch-all for now; expand this later with specific cases
            }
        } else { // Unknown cause of death, very sad

        }
        self.life = -utils.i16max; // Flagged for destruction in main update
    }

    pub fn remove(self: *Unit) !void {
        try main.grid.removeFromCell(self.entity, null, null); // Removes entity from grid
        try main.grid.removeFromAllSections(self.entity);
        try utils.findAndSwapRemove(Unit, &units, self); // Removes unit from the units collection
        for (units.items) |unit| {
            std.debug.assert(unit != self); // For debugging, unit must be removed at this point
        }
        main.grid.allocator.destroy(self.entity); // Deallocates memory for the Entity
        main.grid.allocator.destroy(self); // Deallocates memory for the Unit
    }

    /// `Unit` property template fields determined by `class`.
    pub const Properties = struct {
        speed: f16,
        color: rl.Color,
        width: u16,
        height: u16,
        life: i16,
    };

    /// Returns a `Properties` template determined by `class`.
    pub fn preset(class: u8) Properties {
        return switch (class) {
            0 => Properties{ .speed = 3, .color = rl.Color.sky_blue, .width = 30, .height = 30, .life = 3000 },
            1 => Properties{ .speed = 3.5, .color = rl.Color.blue, .width = 25, .height = 25, .life = 4000 },
            2 => Properties{ .speed = 2, .color = rl.Color.dark_blue, .width = 45, .height = 45, .life = 5000 },
            3 => Properties{ .speed = 4, .color = rl.Color.violet, .width = 35, .height = 35, .life = 6000 },
            else => @panic("Invalid unit class"),
        };
    }

    pub fn speed(self: *Unit) f16 {
        return Unit.preset(self.class).speed;
    }

    pub fn color(self: *Unit) rl.Color {
        return Unit.preset(self.class).color;
    }
};

// Structure
//----------------------------------------------------------------------------------
pub const Structure = struct {
    entity: *Entity,
    x: u16,
    y: u16,
    width: u16,
    height: u16,
    class: u8,
    color: rl.Color,
    life: u16,
    tempo: f16,
    elapsed: u16 = 0,

    /// `Structure` property fields determined by `class`.
    pub const Properties = struct {
        color: rl.Color,
        width: u16,
        height: u16,
        life: u16,
        tempo: f16,
    };

    /// Returns a `Properties` template determined by `class`.
    pub fn preset(class: u8) Properties {
        return switch (class) {
            0 => Properties{ .color = rl.Color.sky_blue, .width = 150, .height = 150, .life = 5000, .tempo = 3.2 },
            1 => Properties{ .color = rl.Color.blue, .width = 100, .height = 100, .life = 6000, .tempo = 5.5 },
            2 => Properties{ .color = rl.Color.dark_blue, .width = 200, .height = 200, .life = 7000, .tempo = 4.0 },
            3 => Properties{ .color = rl.Color.violet, .width = 150, .height = 150, .life = 8000, .tempo = 2.0 },
            else => @panic("Invalid structure class"),
        };
    }

    pub fn draw(self: *const Structure) void {
        utils.drawEntity(self.x, self.y, self.width, self.height, self.color);
    }

    pub fn update(self: *Structure) void {
        self.elapsed += 1;
        const tempo_ticks = utils.ticksFromSecs(self.tempo);
        if (self.elapsed >= tempo_ticks) {
            self.elapsed -= tempo_ticks; // Subtracting interval accounts for possible overshoot
            self.spawnUnit() catch return;
        }
    }

    pub fn spawnUnit(self: *Structure) !void {
        const spawn_class = self.spawnClass();
        const spawn_point = self.spawnPoint(Unit.preset(spawn_class).width, Unit.preset(spawn_class).height) catch null;
        if (spawn_point) |sp| { // If spawn_point is not null, unwrap it
            try units.append(try Unit.create(sp[0], sp[1], spawn_class));
        }
    }

    pub fn create(x: u16, y: u16, class: u8) !*Structure {
        const entity: *Entity = try main.grid.allocator.create(Entity);
        const structure: *Structure = try main.grid.allocator.create(Structure);
        const from_class = Structure.preset(class);

        structure.* = Structure{
            .entity = entity,
            .class = class,
            .width = from_class.width,
            .height = from_class.height,
            .color = from_class.color,
            .life = from_class.life,
            .tempo = from_class.tempo,
            .x = x,
            .y = y,
        };
        entity.* = Entity{
            .kind = Kind.Structure,
            .content = .{ .Structure = structure },
        };

        try main.grid.addToCell(entity, null, null);
        return structure;
    }

    pub fn construct(x: u16, y: u16, class: u8) ?*Structure {
        const collides = main.grid.collidesWith(x, y, preset(class).width, preset(class).height, null) catch return null;
        if (collides != null or !utils.isInMap(x, y, preset(class).width, preset(class).height)) {
            return null;
        }
        const structure = Structure.create(x, y, class) catch return null;
        structures.append(structure) catch return null;
        return structure;
    }

    pub fn spawnClass(self: *Structure) u8 {
        return switch (self.class) {
            0 => 0, // Not very useful now, but may want to change values here
            1 => 1, // To change what units different buildings spawn
            2 => 2,
            3 => 3,
            else => @panic("Invalid structure class"),
        };
    }

    pub fn spawnPoint(self: *Structure, unit_width: u16, unit_height: u16) ![2]u16 {
        var side_indices = [_]usize{ 0, 1, 2, 3 }; // Indices representing the 4 sides
        utils.shuffleArray(usize, &side_indices); // Shuffles indices to randomize check order

        const offset_x = @divTrunc(self.width, 2) + @divTrunc(unit_width, 2);
        const offset_y = @divTrunc(self.height, 2) + @divTrunc(unit_height, 2);

        // Checking side availability
        for (side_indices) |side_index| {
            var spawn_x: u16 = 0;
            var spawn_y: u16 = 0;

            switch (side_index) {
                0 => { // Bottom side
                    spawn_x = self.x;
                    spawn_y = if (self.y + offset_y < main.map_height) self.y + offset_y else self.y - offset_y;
                },
                1 => { // Left side
                    spawn_x = if (self.x >= offset_x) self.x - offset_x else self.x + offset_x;
                    spawn_y = self.y;
                },
                2 => { // Right side
                    spawn_x = if (self.x + offset_x < main.map_width) self.x + offset_x else self.x - offset_x;
                    spawn_y = self.y;
                },
                3 => { // Top side
                    spawn_x = self.x;
                    spawn_y = if (self.y >= offset_y) self.y - offset_y else self.y + offset_y;
                },
                else => @panic("Unrecognized side"),
            }
            // Check if the calculated spawn point is valid
            if (try main.grid.collidesWith(spawn_x, spawn_y, unit_width, unit_height, null) == null and utils.isInMap(spawn_x, spawn_y, unit_width, unit_height)) {
                return [2]u16{ spawn_x, spawn_y };
            }
        }
        return error.NoValidSpawnPoint;
    }
};

// Projectile
//----------------------------------------------------------------------------------
pub const Projectile = struct {
    entity: *Entity,
    x: u16,
    y: u16,
    angle: f16,
    life: u16,
    width: u16 = 1,
    height: u16 = 1,
    class: u8,

    pub fn update(self: Projectile) void {
        const delta = utils.vectorToDelta(self.angle, self.speed);
        self.x = utils.u16AddFloat(f32, self.x, delta[0]);
        self.y = utils.u16AddFloat(f32, self.y, delta[1]);
        self.life -= 1;
        if (self.life <= 0) {
            self.destroy();
        }
    }

    /// `Projectile` property fields determined by `class`.
    pub const Properties = struct {
        width: u16 = 1,
        height: u16 = 1,
        life: u16,
        speed: f16,
        color: rl.Color,
    };

    /// Returns a `Properties` template determined by `class`.
    pub fn preset(class: u8) Properties {
        return switch (class) {
            0 => Properties{ .life = 30, .speed = 25, .color = rl.Color.red, .width = 4, .height = 4 },
            else => @panic("Invalid projectile class"),
        };
    }

    pub fn draw(self: *Projectile) void {
        utils.drawEntity(self.x, self.y, self.width, self.height, preset(self.class).color);
    }

    pub fn impact(self: *Projectile) void {
        // Effect when projectile hits entity; subtract life
        self.destroy();
    }

    pub fn destroy(self: *Projectile) !void {
        try main.grid.removeFromCell(self.entity, null, null);
        // no array list of Projectiles, otherwise: try utils.findAndSwapRemove(Projectile, &projectiles, @constCast(&self));
    }
};

// Map Geometry
//----------------------------------------------------------------------------------

pub const Grid = struct {
    allocator: *std.mem.Allocator,
    cells: std.hash_map.HashMap(u64, std.ArrayList(*Entity), utils.SpatialHash.Context, 80) = undefined,
    cellsigns: []u32, // A slice into a contiguous block of memory
    entity_buffer: []*Entity, // Allocated once, rewritten each tick
    buffer_offset: usize, // Tracks the current usage of the buffer
    sections: []std.ArrayList(*Entity), // Array of dynamic lists of pointers to entities (each section is 3x3 around a given cell)
    columns: usize,
    rows: usize,

    const Cellsign = u32;

    pub fn init(self: *Grid, allocator: *std.mem.Allocator, columns: usize, rows: usize, buffer_size: usize) !void {
        self.allocator = allocator;
        self.cells = std.hash_map.HashMap(u64, std.ArrayList(*Entity), utils.SpatialHash.Context, 80).init(allocator.*);

        self.columns = columns;
        self.rows = rows;
        self.cellsigns = try allocator.alloc(u32, columns * rows);
        self.entity_buffer = try allocator.alloc(*Entity, buffer_size);
        self.buffer_offset = 0;

        const total_cells = columns * rows;
        self.sections = try allocator.alloc(std.ArrayList(*Entity), total_cells);
        for (self.sections) |*section| {
            section.* = std.ArrayList(*Entity).init(allocator.*);
        }
    }

    pub fn deinit(self: *Grid, allocator: *std.mem.Allocator) void {
        var it = self.cells.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit(); // Dereference value_ptr to access and deinitialize the value
        }
        self.cells.deinit();

        allocator.free(self.cellsigns);

        for (self.sections) |section| {
            section.deinit();
        }
        allocator.free(self.sections);
        allocator.free(self.entity_buffer);
    }

    /// Takes a grid cell `x`,`y` and returns the list of entities stored in `sections` for that cell.
    fn sectionEntities(self: *Grid, x: usize, y: usize) ?*std.ArrayList(*Entity) {
        if (x >= self.columns or y >= self.rows) {
            return null;
        }
        const index = y * self.columns + x;
        return &self.sections[index];
    }

    fn addToSection(self: *Grid, x: usize, y: usize, entity: *Entity) !void {
        if (x < self.columns and y < self.rows) {
            const index = y * self.columns + x;
            try self.sections[index].append(entity);
        }
    }

    fn removeFromSection(self: *Grid, x: usize, y: usize, entity: *Entity) !void {
        if (x < self.columns and y < self.rows) {
            const index = y * self.columns + x;
            var section = &self.sections[index];
            var found_index: ?usize = null;
            for (section.items, 0..) |e, i| {
                if (e == entity) {
                    found_index = i;
                    break;
                }
            }
            if (found_index) |idx| {
                _ = section.swapRemove(idx);
            }
        }
    }

    /// Sections are lists of entities within 3x3 cells. An entity is referenced in the grid.section of any cell falling within its own grid.section. Even though sections overlap, cellsigns are
    /// cell-specific, so updating one section does not automatically trigger an update of overlapping sections. This function removes an entity from the central section as well as all overlapping sections.
    fn removeFromNearbySections(self: *Grid, x: usize, y: usize, entity: *Entity) !void {
        const neighbor_offsets = utils.Grid.section();
        for (neighbor_offsets) |offset| {
            const nx = @as(isize, @intCast(x)) + offset[0];
            const ny = @as(isize, @intCast(y)) + offset[1];

            if (nx >= 0 and nx < self.columns and ny >= 0 and ny < self.rows) {
                try self.removeFromSection(@as(usize, @intCast(nx)), @as(usize, @intCast(ny)), entity);
            }
        }
    }

    pub fn removeFromAllSections(self: *Grid, entity: *Entity) !void {
        var count: usize = 0;
        for (0..self.sections.len) |i| {
            var section = &self.sections[i];
            var found_index: ?usize = null;
            for (section.items, 0..) |e, idx| {
                count += 1;
                if (e == entity) {
                    found_index = idx;
                    break;
                }
            }
            if (found_index) |idx| {
                _ = section.swapRemove(idx);
                std.debug.print("Entity {} removed from section {}.\n", .{ @intFromPtr(entity), i });
                std.debug.print("By the way, there are {} sections in total, and searched through {} items in them.\n", .{ self.sections.len, count });
            }
        }
    }

    pub fn updateSections(self: *Grid, cellsigns_cache: []u32) void {
        self.buffer_offset = 0; // Resets at the start of each frame
        for (0..self.columns) |x| {
            for (0..self.rows) |y| {
                const sign = cellsigns_cache[y * self.columns + x];
                if (self.getCellsign(x, y) != sign) { // Cellsign changed from previous tick
                    cellsigns_cache[y * self.columns + x] = self.getCellsign(x, y); // Cache is changed in place
                    self.updateSection(x, y) catch |err| {
                        std.log.err("Failed to update section at ({}, {}): {}\n", .{ x, y, err });
                    };
                }
            }
        }
    }

    fn updateSection(self: *Grid, x: usize, y: usize) !void {
        const index = y * self.columns + x;
        const entities = try self.sectionSearch(@as(u16, @intCast(x * utils.Grid.cell_size)), @as(u16, @intCast(y * utils.Grid.cell_size)), main.UNIT_SEARCH_LIMIT);
        self.sections[index].clearAndFree();

        for (entities) |entity| {
            try self.sections[index].append(entity);
        }
    }

    /// Retrieves current `Cellsign` of cell. Expects `x`,`y` grid coordinates, not world coordinates.
    pub fn getCellsign(self: *Grid, x: usize, y: usize) u32 {
        return self.cellsigns[y * self.columns + x];
    }

    /// Sets `Cellsign` of cell to `value`. Expects `x`,`y` grid coordinates, not world coordinates.
    pub fn setCellsign(self: *Grid, x: usize, y: usize, value: u32) void {
        self.cellsigns[y * self.columns + x] = value;
    }

    pub fn addToCell(self: *Grid, entity: *Entity, new_x: ?u16, new_y: ?u16) !void {
        const x = new_x orelse entity.x();
        const y = new_y orelse entity.y();
        const key = utils.SpatialHash.hash(x, y);

        //std.log.info("Adding entity {} to grid cell at {},{}, using key: {}.\n", .{ @intFromPtr(entity), x, y, key });

        const result = try self.cells.getOrPut(key);
        if (!result.found_existing) {
            result.value_ptr.* = std.ArrayList(*Entity).init(self.allocator.*);
        } else {
            for (result.value_ptr.*.items) |existing_entity| {
                if (@intFromPtr(existing_entity) == @intFromPtr(entity)) {
                    std.log.err("Entity {} already exists in cell with hash {}, skipping add\n", .{ @intFromPtr(existing_entity), key });
                    return;
                }
            }
        }
        //std.debug.print("Added entity {} to cell {}\n", .{ @intFromPtr(entity), key });
        try result.value_ptr.*.append(entity);
    }

    pub fn removeFromCell(self: *Grid, entity: *Entity, old_x: ?u16, old_y: ?u16) !void {
        const x = std.math.clamp(old_x orelse entity.x(), 0, main.map_width);
        const y = std.math.clamp(old_y orelse entity.y(), 0, main.map_height);
        const key = utils.SpatialHash.hash(x, y);

        //std.log.info("Removing entity {} from grid cell at {},{} (hash {}).", .{ @intFromPtr(entity), x, y, key });

        if (self.cells.get(key)) |*listConst| {
            const list = @constCast(listConst);
            try utils.findAndSwapRemove(Entity, list, entity);

            if (list.items.len == 0) {
                std.debug.print("Cell {} is now empty, removing cell from grid.\n", .{key});
                _ = self.cells.remove(key);
            } else {
                // Update the hashmap with the modified list
                self.cells.put(key, list.*) catch unreachable;
                // std.debug.print("Entities in cell {} after removal of entity {}: {any}\n", .{ key, @intFromPtr(entity), list.items });
            }

            // For debugging duplicates
            for (list.items) |remaining_entity| {
                if (remaining_entity == entity) {
                    std.log.err("Entity {} still present in cell {} after supposed removal!", .{ @intFromPtr(entity), key });
                    @panic("Failed to properly remove entity from cell!");
                }
            }
        } else {
            std.debug.print("Error: Attempted to remove entity {} from non-existent cell {}.\n", .{ @intFromPtr(entity), key });
            @panic("Attempted to remove entity from non-existent cell!");
        }

        // Reminder: Entity is at this point still listed in corresponding and neighboring grid.sections addresses.
    }

    pub fn updateCellPosition(self: *Grid, entity: *Entity, old_x: u16, old_y: u16) void {
        const oldKey = utils.SpatialHash.hash(old_x, old_y);
        const curX = entity.x();
        const curY = entity.y();
        const newKey = utils.SpatialHash.hash(curX, curY);

        if (oldKey != newKey) {
            // std.debug.print("(Grid update start) Moving entity with ptr {} from cell hash {} to cell hash {}.\n", .{ @intFromPtr(entity), oldKey, newKey });

            self.removeFromCell(entity, old_x, old_y) catch |err| {
                std.log.err("Failed to remove entity {} from old cell {}, error: {}\n", .{ @intFromPtr(entity), oldKey, err });
                return;
            };

            self.addToCell(entity, null, null) catch |err| {
                std.log.err("Failed to add entity {} to new cell {}, error: {}\n", .{ @intFromPtr(entity), newKey, err });
            };
        }
    }

    /// Removes entity from
    pub fn removeFromGrid() void {}

    /// Generates a fresh `Cellsign` from `x`,`y` coordinates. Returns a `Cellsign` if hashmap value is found for location, otherwise `null`.
    pub fn getFreshCellsign(self: *Grid, x: u16, y: u16) ?Cellsign {
        const key = utils.SpatialHash.hash(x, y);
        if (self.cells.get(key)) |entity_list| {
            return generateCellsign(@constCast(&entity_list));
        }
        return null;
    }

    /// Iterates over the entire grid and generates a fresh `Cellsign` for each cell. Each sign is stored at `[y * self.columns + x]` in the `cellsigns` array.
    pub fn updateCellsigns(self: *Grid) void {
        for (0..self.rows) |y| {
            for (0..self.columns) |x| {
                const key = utils.SpatialHash.hash(@truncate(x * utils.Grid.cell_size), @truncate(y * utils.Grid.cell_size));
                if (self.cells.get(key)) |entity_list| {
                    const sign = generateCellsign(@constCast(&entity_list));
                    self.cellsigns[y * self.columns + x] = sign;
                } else {
                    self.cellsigns[y * self.columns + x] = 0; // Clears the cellsign if the cell is empty
                }
            }
        }
    }

    /// Generates a `Cellsign` (`u32`) for a given entity list. Does not update the grid's `cellsigns` array.
    pub fn generateCellsign(entity_list: *std.ArrayList(*Entity)) Cellsign {
        var sign: Cellsign = 0;
        const entity_count = @as(u32, @intCast(entity_list.items.len)); // Encodes the number of entities in the lowest 8 bits
        sign |= entity_count & 0xFF;

        for (entity_list.items) |entity| { // Encodes entity type information in the higher bits
            const entity_type_shift = @as(u5, @intFromEnum(entity.kind)) + 16;
            sign |= (@as(u32, 1) << entity_type_shift);
        }

        return sign;
    }

    /// Looks up spatial hash and returns slice of entities within a 3x3 section around given x, y coordinates.
    /// Returns error if buffer_offset exceeds the buffersize or the number of entities exceeds `limit`.
    pub fn sectionSearch(self: *Grid, x: u16, y: u16, limit: comptime_int) ![]*Entity {
        const buffer = self.entity_buffer;
        var count: usize = 0;

        if (self.buffer_offset >= buffer.len) { // Check if there is enough space in the buffer
            std.log.err("Buffer offset ({}) has exceeded buffer size ({}). Cannot add more entities.\n", .{ self.buffer_offset, buffer.len });
            return error.BufferOverflow;
        }

        const offsets = utils.Grid.sectionFromPoint(x, y, main.map_width, main.map_height);

        for (offsets) |offset| {
            const neighbor_x = offset[0];
            const neighbor_y = offset[1];
            const neighbor_key = utils.SpatialHash.hash(neighbor_x, neighbor_y);

            if (self.cells.get(neighbor_key)) |list| {
                for (list.items) |entity| {
                    // Ensure we do not exceed the buffer or the limit
                    if (count >= limit or self.buffer_offset + count >= buffer.len) {
                        //std.debug.print("Entity limit reached or buffer full: {} entities collected, limit is {}. Total entities collected: {}, buffer limit is {}.\n", .{ count, limit, self.buffer_offset + count, buffer.len });
                        return error.EntityAmountExceedsLimit;
                    }
                    const entity_ptr_value = @intFromPtr(entity);
                    if (entity_ptr_value < 1024) {
                        std.debug.print("Error: Suspicious entity pointer found: ptr={}, skipping\n", .{entity_ptr_value});
                        continue; // Skips sussy pointers, indicates memory problem
                    }
                    buffer[self.buffer_offset + count] = entity; // Adds to buffer with offset
                    count += 1;
                }
            }
        }

        self.buffer_offset += count; // Update the buffer_offset by the number of entities added
        return buffer[self.buffer_offset - count .. self.buffer_offset];
    }

    /// Returns a slice of nearby entities within a 3x3 grid centered around the given x, y coordinates.
    /// Returns an error if the number of nearby entities exceeds `limit`.
    pub fn entitiesNearOLD(self: *Grid, x: u16, y: u16, limit: comptime_int) ![]*Entity {
        std.debug.print("Calling entitiesNear with a limit of {}.\n", .{limit});
        var nearby_entities: [limit]*Entity = undefined;
        var count: usize = 0;
        //std.debug.print("nearby_entities should be undefined {any}.\n", .{nearby_entities});
        // Gets a 3x3 section of the grid
        const offsets = utils.Grid.sectionFromPoint(x, y, main.map_width, main.map_height);

        // Prioritizes player if in central cell
        if (utils.Grid.x(main.player.x) == offsets[0][0] and utils.Grid.y(main.player.y) == offsets[0][1]) {
            nearby_entities[count] = main.player.entity;
            count += 1;
        }

        for (offsets) |offset| { // For each neighboring cell
            const neighbor_x = offset[0];
            const neighbor_y = offset[1];
            const neighbor_key = utils.SpatialHash.hash(neighbor_x, neighbor_y);

            if (self.cells.get(neighbor_key)) |list| { // Lists the cell contents
                for (list.items) |entity| { // For each entity in the cell
                    if (count >= limit) return error.EntityAmountExceedsLimit;
                    nearby_entities[count] = entity;
                    count += 1;
                }
            }
        }
        std.debug.print("By the time entitiesNear is done, count is: {}.\n", .{count});
        //std.debug.print("Searching for entities near {any}. Found {} entities within area.\n", .{ offsets[0], count });
        return nearby_entities[0..count];
    }

    /// Finds entities in a 3x3 cell radius, then performs an axis-aligned bounding box check. Returns first colliding entity or null.
    pub fn collidesWith(self: *Grid, x: u16, y: u16, width: u16, height: u16, current_entity: ?*Entity) !?*Entity {
        const half_width = @divTrunc(width, 2);
        const half_height = @divTrunc(height, 2);
        const left = @max(half_height, x) - half_width;
        const right = x + half_width;
        const top = @max(half_height, y) - half_height;
        const bottom = y + half_height;
        const nearby_entities = if (current_entity != null and current_entity.?.kind == Kind.Unit)
            try self.sectionSearch(x, y, main.UNIT_SEARCH_LIMIT)
        else
            try self.sectionSearch(x, y, main.PLAYER_SEARCH_LIMIT);
        for (nearby_entities) |entity| {
            if (current_entity) |cur| {
                if (cur == entity) {
                    continue; // Skip current entity
                }
            }

            const entity_half_width = @divTrunc(entity.width(), 2);
            const entity_half_height = @divTrunc(entity.height(), 2);

            const entity_left = @max(entity_half_width, entity.x()) - entity_half_width;
            const entity_right = entity.x() + entity_half_width;
            const entity_top = @max(entity_half_height, entity.y()) - entity_half_height;
            const entity_bottom = entity.y() + entity_half_height;

            if ((left < entity_right) and (right > entity_left) and
                (top < entity_bottom) and (bottom > entity_top))
            {
                return entity; // Returns colliding entity
            }
        }
        return null;
    }
};
