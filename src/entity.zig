const std: type = @import("std");
const rl = @import("raylib");
const utils = @import("utils.zig");
const main = @import("main.zig");

// Setting up entities
pub var players: std.ArrayList(*Player) = undefined;
pub var units: std.ArrayList(*Unit) = undefined;
pub var structures: std.ArrayList(*Structure) = undefined;

const EntityType = enum {
    Player,
    Unit,
    Structure,
};

pub const Entity = struct {
    entityType: EntityType,
    entity: union(EntityType) { // Stores pointer to the actual data
        Player: *Player,
        Unit: *Unit,
        Structure: *Structure,
    },
};

pub fn entityWidth(entity: *Entity) u16 {
    return switch (entity.entityType) {
        EntityType.Player => entity.entity.Player.width,
        EntityType.Unit => entity.entity.Unit.width,
        EntityType.Structure => entity.entity.Structure.width,
    };
}

pub fn entityHeight(entity: *Entity) u16 {
    return switch (entity.entityType) {
        EntityType.Player => entity.entity.Player.height,
        EntityType.Unit => entity.entity.Unit.height,
        EntityType.Structure => entity.entity.Structure.height,
    };
}

pub fn entityX(entity: *Entity) u16 {
    return switch (entity.entityType) {
        EntityType.Player => entity.entity.Player.x,
        EntityType.Unit => entity.entity.Unit.x,
        EntityType.Structure => entity.entity.Structure.x,
    };
}

pub fn entityY(entity: *Entity) u16 {
    return switch (entity.entityType) {
        EntityType.Player => entity.entity.Player.y,
        EntityType.Unit => entity.entity.Unit.y,
        EntityType.Structure => entity.entity.Structure.y,
    };
}

/// Returns the bigger of two entities, or null if same size.
pub fn biggerEntity(e1: *Entity, e2: *Entity) ?*Entity {
    switch (utils.bigger(entityWidth(e1), entityHeight(e1), entityWidth(e2), entityHeight(e2))) {
        0 => return e1,
        1 => return e2,
        2, 3 => return null,
    }
}

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

    pub fn update(self: *Player, keyInput: ?u32) anyerror!void {
        if (self.local) { // Local player
            if (keyInput) |input| {
                if (input > 0) {
                    // std.debug.print("Key input!\n", .{});
                    try self.updateMoveInput(input);
                    try self.updateActionInput(input);
                } else {
                    // std.debug.print("No key input.\n", .{});
                }
            }
        } else { // If AI or remote player
            // updateMoveEvent, determine movement based on network or AI logic
            // updateActionEvent, determine ability use based on network or AI logic
        }
    }

    fn updateMoveInput(self: *Player, keyInput: u32) !void {
        const speed = utils.scaleToTickRate(self.speed);
        var changedX: ?u16 = null;
        var changedY: ?u16 = null;

        // Processes movement input
        if (main.keys.actionActive(keyInput, utils.Key.Action.MoveUp)) {
            changedY = utils.mapClampY(@truncate(utils.i32SubFloat(f32, self.y, speed)), self.height);
            self.direction = 8; // Numpad direction
        }
        if (main.keys.actionActive(keyInput, utils.Key.Action.MoveLeft)) {
            changedX = utils.mapClampX(@truncate(utils.i32SubFloat(f32, self.x, speed)), self.width);
            self.direction = 4; // Numpad direction
        }
        if (main.keys.actionActive(keyInput, utils.Key.Action.MoveDown)) {
            changedY = utils.mapClampY(@truncate(utils.i32AddFloat(f32, self.y, speed)), self.height);
            self.direction = 2; // Numpad direction
        }
        if (main.keys.actionActive(keyInput, utils.Key.Action.MoveRight)) {
            changedX = utils.mapClampX(@truncate(utils.i32AddFloat(f32, self.x, speed)), self.width);
            self.direction = 6; // Numpad direction
        }

        if (changedX != null or changedY != null) try executeMovement(self, changedX, changedY, speed);
    }

    fn executeMovement(self: *Player, changedX: ?u16, changedY: ?u16, speed: f32) !void {
        const oldX = self.x;
        const oldY = self.y;
        var newX: ?u16 = changedX;
        var newY: ?u16 = changedY;
        var obstacleX: ?*Entity = null;
        var obstacleY: ?*Entity = null;
        const deltaXy = utils.deltaXy(oldX, oldY, newX orelse oldX, newY orelse oldY);
        std.debug.print("Player movement direction: {}. Delta to angle: {}. Angle from dir: {}. Vector to delta: {any}.\n", .{ self.direction, @as(i64, @intFromFloat(utils.deltaToAngle(deltaXy[0], deltaXy[1]))), utils.angleFromDir(self.direction), utils.vectorToDelta(utils.deltaToAngle(deltaXy[0], deltaXy[1]), speed) });

        // Gets potential obstacle entities on both axes
        if (newX != null) obstacleX = main.gameGrid.collidesWith(newX.?, self.y, self.width, self.height, self.getEntity()) catch null;
        if (newY != null) obstacleY = main.gameGrid.collidesWith(self.x, newY.?, self.width, self.height, self.getEntity()) catch null;

        // Executes horizontal movement
        if (newX != null) {
            if (obstacleX == null) {
                self.x = newX.?;
            } else if (newY == null and (obstacleX.?.entityType == EntityType.Unit)) { // If unit obstacle, try pushing horizontally
                const resistance = 0.1; // maybe depend on size relation
                const force = (1.0 - resistance);
                const difference = @as(f64, @floatFromInt(@as(i32, newX.?) - @as(i32, oldX)));
                newX = @as(u16, @intCast(@as(i32, oldX) + @as(i32, @intFromFloat(@round(difference * force)))));

                // Pushes obstacle, and checks whether push was unhindered, or if pushed obstacle in turn ran into a further obstacle
                std.debug.print("Pushing horizontally, angle: {}, distance: {}\n", .{ utils.angleFromDir(self.direction), speed * force });
                const pushDistance = obstacleX.?.entity.Unit.pushed(utils.angleFromDir(self.direction), speed * force);
                std.debug.print("Horizontal push distance: {}\n", .{pushDistance});
                if (pushDistance >= speed * force) {
                    obstacleX = main.gameGrid.collidesWith(newX.?, self.y, self.width, self.height, self.getEntity()) catch null;
                } else {
                    newX = @as(u16, @intCast(@as(i32, oldX) + @as(i32, @intFromFloat(pushDistance)))); // Moves effective push distance and re-checks collision
                    obstacleX = main.gameGrid.collidesWith(newX.?, self.y, self.width, self.height, self.getEntity()) catch null;
                }
                if (obstacleX == null) self.x = newX.?; // If no collision now, repositions x
            }
        }

        // Executes vertical movement
        if (newY != null) {
            if (obstacleY == null) {
                self.y = newY.?;
            } else if (newX == null and (obstacleY.?.entityType == EntityType.Unit)) { // If unit collider, try pushing vertically
                const resistance = 0.1; // maybe depend on size relation
                const force = (1.0 - resistance);
                const difference = @as(f64, @floatFromInt(@as(i32, newY.?) - @as(i32, oldY)));
                newY = @as(u16, @intCast(@as(i32, oldY) + @as(i32, @intFromFloat(@round(difference * force)))));

                // Pushes obstacle, and checks whether push was unhindered, or if pushed obstacle in turn ran into a further obstacle
                std.debug.print("Pushing vertically, angle: {}, distance: {}\n", .{ utils.angleFromDir(self.direction), speed * force });
                const pushDistance = obstacleY.?.entity.Unit.pushed(utils.angleFromDir(self.direction), speed * force);
                std.debug.print("Vertical push distance: {}\n", .{pushDistance});
                if (pushDistance >= speed * force) {
                    obstacleY = main.gameGrid.collidesWith(self.x, newY.?, self.width, self.height, self.getEntity()) catch null;
                } else {
                    newY = @as(u16, @intCast(@as(i32, oldY) + @as(i32, @intFromFloat(pushDistance)))); // Moves effective push distance and re-checks collision
                    obstacleY = main.gameGrid.collidesWith(self.x, newY.?, self.width, self.height, self.getEntity()) catch null;
                }
                if (obstacleY == null) self.y = newY.?; // If no collision now, repositions y
            }
        }

        // If new movement, updates game grid
        if ((newX != null and newX.? != oldX) or (newY != null and newY.? != oldY)) {
            main.gameGrid.updateEntity(getEntity(self), oldX, oldY);
        }
    }

    fn updateActionInput(self: *Player, keyInput: u32) !void {
        var built: ?*Structure = undefined;
        var buildAttempted: bool = false;

        if (main.keys.actionActive(keyInput, utils.Key.Action.BuildOne)) {
            const class = Structure.classProperties(0);
            const delta = if (utils.isHorz(self.direction)) @divTrunc(class.width, 2) + @divTrunc(self.width, 2) else @divTrunc(class.height, 2) + @divTrunc(self.height, 2);
            const xy = utils.dirOffset(self.x, self.y, self.direction, delta);
            built = Structure.build(xy[0], xy[1], 0);
            buildAttempted = true;
        }
        if (main.keys.actionActive(keyInput, utils.Key.Action.BuildTwo)) {
            const class = Structure.classProperties(1);
            const delta = if (utils.isHorz(self.direction)) @divTrunc(class.width, 2) + @divTrunc(self.width, 2) else @divTrunc(class.height, 2) + @divTrunc(self.height, 2);
            const xy = utils.dirOffset(self.x, self.y, self.direction, delta);
            built = Structure.build(xy[0], xy[1], 1);
            buildAttempted = true;
        }
        if (main.keys.actionActive(keyInput, utils.Key.Action.BuildThree)) {
            const class = Structure.classProperties(2);
            const delta = if (utils.isHorz(self.direction)) @divTrunc(class.width, 2) + @divTrunc(self.width, 2) else @divTrunc(class.height, 2) + @divTrunc(self.height, 2);
            const xy = utils.dirOffset(self.x, self.y, self.direction, delta);
            built = Structure.build(xy[0], xy[1], 2);
            buildAttempted = true;
        }
        if (main.keys.actionActive(keyInput, utils.Key.Action.BuildFour)) {
            const class = Structure.classProperties(3);
            const delta = if (utils.isHorz(self.direction)) @divTrunc(class.width, 2) + @divTrunc(self.width, 2) else @divTrunc(class.height, 2) + @divTrunc(self.height, 2);
            const xy = utils.dirOffset(self.x, self.y, self.direction, delta);
            built = Structure.build(xy[0], xy[1], 3);
            buildAttempted = true;
        }

        if (buildAttempted) {
            if (built) |building| {
                std.debug.print("Structure built successfully: {}\n", .{building});
                // Do something with the structure
            } else {
                std.debug.print("Failed to build structure\n", .{});
                // Handle the failure case, e.g., notify the player or log the error
            }
        }
    }

    pub fn createLocal(x: u16, y: u16) !*Player {
        const entityPlayer = try main.gameGrid.allocator.create(Entity); // Allocate memory for the parent entity
        const player = try main.gameGrid.allocator.create(Player); // Allocate memory for Player and get a pointer

        player.* = Player{
            .entity = entityPlayer,
            .x = x,
            .y = y,
            .width = 100,
            .height = 100,
            .speed = 5,
            .color = rl.Color.green,
            .local = true,
        };
        entityPlayer.* = Entity{
            .entityType = EntityType.Player,
            .entity = .{ .Player = player },
        };

        std.debug.print("Created local player at ({}, {}) with entity pointer {}\n", .{ x, y, @intFromPtr(entityPlayer) });
        try main.gameGrid.addEntity(entityPlayer, null, null);
        return player;
    }

    pub fn createRemote(x: u16, y: u16) !*Player {
        const entityPlayer = try main.gameGrid.allocator.create(Entity); // Allocate memory for the parent entity
        const player = try main.gameGrid.allocator.create(Player); // Allocate memory for Player and get a pointer

        player.* = Player{
            .entity = entityPlayer,
            .x = x,
            .y = y,
            .width = 100,
            .height = 100,
            .speed = 5,
            .color = rl.Color.red,
            .local = false,
        };
        entityPlayer.* = Entity{
            .entityType = EntityType.Player,
            .entity = .{ .Player = player },
        };

        std.debug.print("Created remote player at ({}, {}) with entity pointer {}\n", .{ x, y, @intFromPtr(entityPlayer) });
        try main.gameGrid.addEntity(entityPlayer, null, null);
        return player;
    }

    pub fn getEntity(player: *Player) *Entity {
        return player.entity;
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
    life: u16,
    cellsign: Grid.CellSignature,
    target: utils.Point,

    pub fn draw(self: *Unit) void {
        utils.drawEntity(self.x, self.y, self.width, self.height, self.color());
    }

    pub fn update(self: *Unit) void {
        const step = self.getStep();
        self.move(step.x, step.y);

        // act, determine based on AI logic

        // move, determine movement based on AI logic
        self.updateCellSignature(); // Update after moving

        self.life -= 1;
        if (self.life <= 0) self.die(null);
    }

    /// Searches for collision at `newX`,`newY`. If no obstacle is found, sets position to `x`, `y`. If obstacle is found, moves along its edge.
    fn move(self: *Unit, newX: u16, newY: u16) void {
        const oldX = self.x;
        const oldY = self.y;

        if (utils.isInMap(newX, newY, self.width, self.height)) {

            // Idea: Have unit favor moving along halfgrid. Only do "collidesWithGeneral" if unit x,y is NOT on halfgrid
            // Other idea: Cell signatures for each hash map value update every frame, compare with entity's cached cell signature
            // Only add obstacles if difference in signature, but must then keep some sort of list...

            if (self.cellsign == main.gameGrid.getSignature(utils.Grid.gridX(self.x), utils.Grid.gridY(self.y))) {

                // Does nothing here for now . . . but should update cell "geometry" and feed that into collidesWith, make performant

            }

            var obstacle = main.gameGrid.collidesWith(newX, newY, self.width, self.height, self.getEntity()) catch null;

            if (obstacle == null) { // No obstacle, move
                self.x = newX;
                self.y = newY;
                main.gameGrid.updateEntity(getEntity(self), oldX, oldY);
            } else { // Obstacle, moves along its edge i.e. displacement along one axis only
                const diffX: i32 = @as(i32, @intCast(newX)) - @as(i32, @intCast(oldX));
                const diffY: i32 = @as(i32, @intCast(newY)) - @as(i32, @intCast(oldY));
                if (@abs(diffX) > @abs(diffY)) { // Horizontal axis dominant, checks if x is free first, otherwise checks if y is free
                    obstacle = main.gameGrid.collidesWith(newX, oldY, self.width, self.height, self.getEntity()) catch null;
                    if (obstacle == null) { // No obstacle, move
                        self.x = newX;
                        main.gameGrid.updateEntity(getEntity(self), oldX, oldY);
                    } else {
                        obstacle = main.gameGrid.collidesWith(oldX, newY, self.width, self.height, self.getEntity()) catch null;
                        if (obstacle == null) { // No obstacle, move
                            self.y = newY;
                            main.gameGrid.updateEntity(getEntity(self), oldX, oldY);
                        }
                    }
                } else { // Vertical axis dominant, checks if y is free first, otherwise checks if x is free
                    obstacle = main.gameGrid.collidesWith(oldX, newY, self.width, self.height, self.getEntity()) catch null;
                    if (obstacle == null) { // No obstacle, move
                        self.y = newY;
                        main.gameGrid.updateEntity(getEntity(self), oldX, oldY);
                    } else {
                        obstacle = main.gameGrid.collidesWith(newX, oldY, self.width, self.height, self.getEntity()) catch null;
                        if (obstacle == null) { // No obstacle, move
                            self.x = newX;
                            main.gameGrid.updateEntity(getEntity(self), oldX, oldY);
                        }
                    }
                }
            }
        }

        // else { Not inside map }
    }

    /// Unit is an obstacle pushed by another entity. Searches for collision. If no collateral obstacle is found, unit moves `distance`.
    /// If collateral obstacle is another unit, moved unit pushes on the obstacle unit, then moves size-factored distance. Returns the actual moved distance.
    pub fn pushed(self: *Unit, angle: f32, distance: f32) f32 {
        const oldX = self.x;
        const oldY = self.y;
        const newX: u16, const newY: u16 = calculatePushPosition(self, angle, distance);

        var movedDistance: f32 = distance;

        //std.debug.print("Unit {} is being moved.\n", .{@intFromPtr(self)});

        // Squeeze to flag unit as a pushee, preventing circularity from recursive call -- need a different way to do this
        self.width = classProperties(self.class).width - 1;
        self.height = classProperties(self.class).height - 1;

        if (!utils.isInMap(newX, newY, self.width, self.height)) return movedDistance;

        const obstacle = main.gameGrid.collidesWith(newX, newY, self.width, self.height, self.getEntity()) catch null;

        if (obstacle == null) { // Pushing doesn't collide with another obstacle
            //std.debug.print("Moved {} meets no obstacle.\n", .{@intFromPtr(self)});
            self.x = newX;
            self.y = newY;
            main.gameGrid.updateEntity(getEntity(self), oldX, oldY);
        } else if (obstacle.?.entityType == EntityType.Unit) { // Pushed unit collides with another unit

            const obstacleUnit = obstacle.?.entity.Unit;

            // Checks that obstacleUnit isn't already a pushee
            if (obstacleUnit.width != classProperties(obstacleUnit.class).width or obstacleUnit.height != classProperties(obstacleUnit.class).height) {
                //std.debug.print("Moved unit {} found an obstacle, unit {}. It is already being pushed, so stopping here.\n", .{ @intFromPtr(self), @intFromPtr(obstacleUnit) });
                movedDistance = movedDistance / 2;
            } else {
                movedDistance = pushed(obstacleUnit, angle, @min(distance, distance * utils.sizeFactor(self.width, self.height, obstacleUnit.width, obstacleUnit.height)));
                //std.debug.print("Moved unit {} found an obstacle, unit {}. Pushing it in turn, distance changed from {} to {}.\n", .{ @intFromPtr(self), @intFromPtr(obstacleUnit), distance, movedDistance });

                const pushDeltaXy = utils.vectorToDelta(angle, movedDistance);
                const pushNewX = @as(u16, @intFromFloat(@as(f32, @floatFromInt(self.x)) + pushDeltaXy[0]));
                const pushNewY = @as(u16, @intFromFloat(@as(f32, @floatFromInt(self.y)) + pushDeltaXy[1]));

                self.move(pushNewX, pushNewY);
                //std.debug.print("Pushing distance: {}.\n", .{movedDistance});
            }
        }

        // Resets dimensions to flag as ready for future pushing
        self.width = classProperties(self.class).width;
        self.height = classProperties(self.class).height;
        return movedDistance; // Returns effective moved distance
    }

    fn calculatePushPosition(self: *Unit, angle: f32, distance: f32) [2]u16 {
        const deltaXy = utils.vectorToDelta(angle, distance);
        const newXBroad: f32 = @round(@as(f32, @floatFromInt(self.x)) + deltaXy[0]);
        const newYBroad: f32 = @round(@as(f32, @floatFromInt(self.y)) + deltaXy[1]);

        const newX = @as(u16, @intFromFloat(utils.u16Clamped(f32, newXBroad)));
        const newY = @as(u16, @intFromFloat(utils.u16Clamped(f32, newYBroad)));

        return [2]u16{ newX, newY };
    }

    /// Sets unit's target destination while taking into account its current `cellsign`. Returns `true` if setting new target, returns `false` if target remains the same.
    pub fn retarget(self: *Unit, x: u16, y: u16) bool {
        // do more stuff here for pathing
        const prevTarget = self.target;

        self.target = utils.Point.at(x, y);
        return prevTarget.x != self.target.x or prevTarget.y != self.target.y;
    }

    /// Calculates and returns the unit's immediate destination based on its current `target` and `cellsign`.
    fn getStep(self: *Unit) utils.Point {
        // do more stuff here for pathing
        const dx = @as(i32, @intCast(self.x)) - @as(i32, @intCast(self.target.x));
        const dy = @as(i32, @intCast(self.y)) - @as(i32, @intCast(self.target.y));
        if (@abs(dx + dy) < @as(i32, @intFromFloat(self.speed()))) {
            _ = self.retarget(utils.randomU16(main.mapWidth), utils.randomU16(main.mapHeight)); // <--- just testing
        }
        const angle = utils.deltaToAngle(dx, dy);
        const vector = utils.vectorToDelta(angle, self.speed());
        return utils.deltaPoint(self.x, self.y, vector[0], vector[1]);
    }

    pub fn create(x: u16, y: u16, class: u8) !*Unit {
        const entityUnit = try main.gameGrid.allocator.create(Entity); // Memory for the parent entity
        const fromClass = Unit.classProperties(class);
        const unit = try main.gameGrid.allocator.create(Unit); // Allocate memory for Unit and get a pointer

        unit.* = Unit{
            .entity = entityUnit,
            .class = class,
            .width = fromClass.width,
            .height = fromClass.height,
            .life = fromClass.life,
            .x = x,
            .y = y,
            .cellsign = 0,
            .target = utils.Point.at(utils.randomU16(main.mapWidth), utils.randomU16(main.mapHeight)), // <--- just testing
        };

        entityUnit.* = Entity{
            .entityType = EntityType.Unit,
            .entity = .{ .Unit = unit }, // Store the pointer to the Unit
        };

        try main.gameGrid.addEntity(entityUnit, null, null);
        unit.updateCellSignature();
        return unit;
    }

    pub fn destroy(self: *Unit) !void {
        try main.gameGrid.removeEntity(getEntity(self), null, null);
        try utils.findAndSwapRemove(Unit, &units, self);
    }

    pub fn die(self: *Unit, cause: ?u8) void {
        // Death effect
        if (cause) |c| {
            //switch (c) {
            //    else => // Handle different death types differently
            // }
            self.destroy() catch std.debug.panic("Failed to destroy, cause {}.\n", .{c});
        } else { // Unknown cause of death, very sad
            self.destroy() catch std.debug.panic("Failed to destroy\n", .{});
        }
    }

    /// Unit property template fields.
    pub const Properties = struct {
        speed: f16,
        color: rl.Color,
        width: u16,
        height: u16,
        life: u16,
    };

    /// Unit property distribution templates.
    pub fn classProperties(class: u8) Properties {
        return switch (class) {
            0 => Properties{ .speed = 3, .color = rl.Color.sky_blue, .width = 30, .height = 30, .life = 3000 },
            1 => Properties{ .speed = 3.5, .color = rl.Color.blue, .width = 25, .height = 25, .life = 4000 },
            2 => Properties{ .speed = 2, .color = rl.Color.dark_blue, .width = 45, .height = 45, .life = 5000 },
            3 => Properties{ .speed = 4, .color = rl.Color.violet, .width = 35, .height = 35, .life = 6000 },
            else => @panic("Invalid unit class"),
        };
    }

    pub fn updateCellSignature(self: *Unit) void {
        self.cellsign = main.gameGrid.getFreshSignature(self.x, self.y) orelse 0;
    }

    pub fn speed(self: *Unit) f16 {
        return Unit.classProperties(self.class).speed;
    }

    pub fn color(self: *Unit) rl.Color {
        return Unit.classProperties(self.class).color;
    }

    pub fn getEntity(self: *Unit) *Entity {
        return self.entity;
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
    pulse: f16,
    elapsed: u16 = 0,

    pub fn draw(self: *const Structure) void {
        utils.drawEntity(self.x, self.y, self.width, self.height, self.color);
    }

    pub fn update(self: *Structure) void {
        self.elapsed += 1;
        const pulseTicks = utils.ticksFromSecs(self.pulse);
        if (self.elapsed >= pulseTicks) {
            self.elapsed -= pulseTicks; // Subtracting interval accounts for possible overshoot
            self.spawnUnit() catch return;
        }
    }

    pub fn spawnUnit(self: *Structure) !void {
        const unitClass = Structure.classToSpawnClass(self.class);
        const spawnPoint = getSpawnPoint(self.x, self.y, self.width, self.height, Unit.classProperties(unitClass).width, Unit.classProperties(unitClass).width) catch null;
        if (spawnPoint) |sp| { // If spawnPoint is not null, unwrap it
            try units.append(try Unit.create(sp[0], sp[1], unitClass));
        }
    }

    pub fn create(x: u16, y: u16, class: u8) !*Structure {
        const entityStructure = try main.gameGrid.allocator.create(Entity); // Allocate memory for the parent entity
        const structure = try main.gameGrid.allocator.create(Structure); // Allocate memory for Structure and get a pointer
        const fromClass = Structure.classProperties(class);

        structure.* = Structure{
            .entity = entityStructure,
            .class = class,
            .width = fromClass.width,
            .height = fromClass.height,
            .color = fromClass.color,
            .life = fromClass.life,
            .pulse = fromClass.pulse,
            .x = x,
            .y = y,
        };
        entityStructure.* = Entity{
            .entityType = EntityType.Structure,
            .entity = .{ .Structure = structure },
        };

        // std.debug.print("Created structure at ({}, {}) with entity pointer {}\n", .{ x, y, @intFromPtr(entityStructure) });
        try main.gameGrid.addEntity(entityStructure, null, null);
        return structure;
    }

    pub fn build(x: u16, y: u16, class: u8) ?*Structure {
        const nodeXy = utils.closestNexus(x, y);
        const collides = main.gameGrid.collidesWith(nodeXy[0], nodeXy[1], classProperties(class).width, classProperties(class).height, null) catch return null;
        if (collides != null or !utils.isInMap(nodeXy[0], nodeXy[1], classProperties(class).width, classProperties(class).height)) {
            return null;
        }
        const structure = Structure.create(nodeXy[0], nodeXy[1], class) catch return null;
        structures.append(structure) catch return null;
        return structure;
    }

    pub const StructureProperties = struct {
        color: rl.Color,
        width: u16,
        height: u16,
        life: u16,
        pulse: f16,
    };

    pub fn classProperties(class: u8) StructureProperties {
        return switch (class) {
            0 => StructureProperties{ .color = rl.Color.sky_blue, .width = 150, .height = 150, .life = 5000, .pulse = 3.2 },
            1 => StructureProperties{ .color = rl.Color.blue, .width = 100, .height = 100, .life = 6000, .pulse = 5.5 },
            2 => StructureProperties{ .color = rl.Color.dark_blue, .width = 200, .height = 200, .life = 7000, .pulse = 4.0 },
            3 => StructureProperties{ .color = rl.Color.violet, .width = 150, .height = 150, .life = 8000, .pulse = 2.0 },
            else => @panic("Invalid structure class"),
        };
    }

    pub fn classToSpawnClass(class: u8) u8 {
        return switch (class) {
            0 => 0, // Not very useful now, but may want to change values here
            1 => 1, // To change what units different buildings spawn
            2 => 2,
            3 => 3,
            else => @panic("Invalid structure class"),
        };
    }

    pub fn getSpawnPoint(x: u16, y: u16, structureWidth: u16, structureHeight: u16, unitWidth: u16, unitHeight: u16) ![2]u16 {
        var attempts: usize = 0;
        var sidesChecked = [_]bool{ false, false, false, false }; // Track which sides have been checked
        while (attempts < 4) {
            const sideIndex = @as(usize, @intCast(utils.randomU16(3)));
            if (sidesChecked[sideIndex]) {
                continue; // Skip already checked sides
            }
            sidesChecked[sideIndex] = true;
            attempts += 1;

            var spawnX: u16 = 0;
            var spawnY: u16 = 0;

            switch (sideIndex) {
                0 => { // Bottom side
                    spawnX = x;
                    spawnY = y + (@divTrunc(structureHeight, 2) + @divTrunc(unitHeight, 2));
                },
                1 => { // Left side
                    spawnX = x - (@divTrunc(structureWidth, 2) + @divTrunc(unitWidth, 2));
                    spawnY = y;
                },
                2 => { // Right side
                    spawnX = x + (@divTrunc(structureWidth, 2) + @divTrunc(unitWidth, 2));
                    spawnY = y;
                },
                3 => { // Top side
                    spawnX = x;
                    spawnY = y - (@divTrunc(structureHeight, 2) + @divTrunc(unitHeight, 2));
                },
                else => @panic("Unrecognized side"),
            }

            if (try main.gameGrid.collidesWith(spawnX, spawnY, unitWidth, unitHeight, null) == null and utils.isInMap(spawnX, spawnY, unitWidth, unitHeight)) {
                return [2]u16{ spawnX, spawnY };
            }
        }

        return error.NoValidSpawnPoint;
    }

    pub fn getEntity(structure: *Structure) *Entity {
        return structure.entity;
    }
};

// Projectile
//----------------------------------------------------------------------------------
pub const Projectile = struct {
    entity: *Projectile,
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

    /// Projectile property fields.
    pub const Properties = struct {
        width: u16 = 1,
        height: u16 = 1,
        life: u16,
        speed: f16,
        color: rl.Color,
    };

    /// Projectile property distribution templates.
    pub fn classProperties(class: u8) Properties {
        return switch (class) {
            0 => Properties{ .life = 30, .speed = 25, .color = rl.Color.red, .width = 4, .height = 4 },
            else => @panic("Invalid projectile class"),
        };
    }

    pub fn draw(self: Projectile) void {
        utils.drawEntity(self.x, self.y, self.width, self.height, classProperties(self.class).color);
    }

    pub fn impact(self: Projectile) void {
        // Effect when projectile hits entity; subtract life
        self.destroy();
    }

    pub fn destroy(self: Projectile) !void {
        try main.gameGrid.removeEntity(getEntity(@constCast(&self)), null, null);
        // no array list of Projectiles, otherwise: try utils.findAndSwapRemove(Projectile, &projectiles, @constCast(&self));
    }

    pub fn getEntity(projectile: *Projectile) *Entity {
        return projectile.entity;
    }
};

// Map Geometry
//----------------------------------------------------------------------------------

pub const Grid = struct {
    allocator: *std.mem.Allocator,
    cells: std.hash_map.HashMap(u64, std.ArrayList(*Entity), utils.SpatialHash.Context, 80) = undefined,
    signatures: []u32, // A slice into a contiguous block of memory
    columns: usize,
    rows: usize,

    const CellSignature = u32;

    pub fn init(self: *Grid, allocator: *std.mem.Allocator, columns: usize, rows: usize) !void {
        self.allocator = allocator;
        self.cells = std.hash_map.HashMap(u64, std.ArrayList(*Entity), utils.SpatialHash.Context, 80).init(allocator.*);

        self.columns = columns;
        self.rows = rows;
        self.signatures = try allocator.alloc(u32, columns * rows);
        // Not initializing values
    }

    pub fn deinit(self: *Grid, allocator: *std.mem.Allocator) void {
        var it = self.cells.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit(); // Dereference value_ptr to access and deinitialize the value
        }
        self.cells.deinit();
        allocator.free(self.signatures);
    }

    /// Retrieves `CellSignature` of cell. Expects `x`,`y` grid coordinates, not world coordinates.
    pub fn getSignature(self: *Grid, x: usize, y: usize) u32 {
        return self.signatures[y * self.columns + x];
    }

    /// Sets `CellSignature` of cell. Expects `x`,`y` grid coordinates, not world coordinates.
    pub fn setSignature(self: *Grid, x: usize, y: usize, value: u32) void {
        self.signatures[y * self.columns + x] = value;
    }

    pub fn addEntity(self: *Grid, entity: *Entity, newX: ?u16, newY: ?u16) !void {
        const x = newX orelse entityX(entity);
        const y = newY orelse entityY(entity);
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

    pub fn removeEntity(self: *Grid, entity: *Entity, oldX: ?u16, oldY: ?u16) !void {
        const x = std.math.clamp(oldX orelse entityX(entity), 0, main.mapWidth);
        const y = std.math.clamp(oldY orelse entityY(entity), 0, main.mapHeight);
        const key = utils.SpatialHash.hash(x, y);

        //std.log.info("Removing entity {} from grid cell at {},{} (hash {}).", .{ @intFromPtr(entity), x, y, key });

        if (self.cells.get(key)) |*listConst| {
            const list = @constCast(listConst);
            try utils.findAndSwapRemove(Entity, list, entity);

            if (list.items.len == 0) {
                //std.debug.print("Cell {} is now empty, removing cell from grid.\n", .{key});
                _ = self.cells.remove(key);
            } else {
                // Update the hashmap with the modified list
                self.cells.put(key, list.*) catch unreachable;
                //std.debug.print("Entities in cell {} after removal of entity {}: {any}\n", .{ key, @intFromPtr(entity), list.items });
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
    }

    pub fn updateEntity(self: *Grid, entity: *Entity, oldX: u16, oldY: u16) void {
        const oldKey = utils.SpatialHash.hash(oldX, oldY);
        const curX = entityX(entity);
        const curY = entityY(entity);
        const newKey = utils.SpatialHash.hash(curX, curY);

        if (oldKey != newKey) {
            // std.debug.print("(Grid update start) Moving entity with ptr {} from cell hash {} to cell hash {}.\n", .{ @intFromPtr(entity), oldKey, newKey });

            self.removeEntity(entity, oldX, oldY) catch |err| {
                std.log.err("Failed to remove entity {} from old cell {}, error: {}\n", .{ @intFromPtr(entity), oldKey, err });
                return;
            };

            self.addEntity(entity, null, null) catch |err| {
                std.log.err("Failed to add entity {} to new cell {}, error: {}\n", .{ @intFromPtr(entity), newKey, err });
            };

            if (entity.entityType == EntityType.Unit) {
                entity.entity.Unit.updateCellSignature();
            }

            // std.debug.print("(Grid update end) After adding/removing entity: \n", .{});
            // var it2 = self.cells.iterator();
            // while (it2.next()) |entry| {
            //     std.debug.print("Cell {any} contains entities: {any}\n", .{ entry.key_ptr, entry.value_ptr.items });
            // }
        }
    }

    /// Generates a fresh signature of the `x`,`y` coordinates. Returns `CellSignature` if cell value exists, otherwise returns `null`.
    pub fn getFreshSignature(self: *Grid, x: u16, y: u16) ?CellSignature {
        const key = utils.SpatialHash.hash(x, y);
        if (self.cells.get(key)) |entityList| {
            return generateSignature(@constCast(&entityList));
        }
        return null;
    }

    /// Iterates over the entire grid and generates a fresh `CellSignature` for each cell. Each signature is stored at `[y * self.columns + x]` in `signatures`.
    pub fn updateCellSignatures(self: *Grid) void {
        for (0..self.rows) |y| {
            for (0..self.columns) |x| {
                const key = utils.SpatialHash.hash(@truncate(x * utils.Grid.CellSize), @truncate(y * utils.Grid.CellSize));
                if (self.cells.get(key)) |entityList| {
                    const signature = generateSignature(@constCast(&entityList));
                    self.signatures[y * self.columns + x] = signature;
                } else {
                    self.signatures[y * self.columns + x] = 0; // Clears the signature if the cell is empty
                }
            }
        }
    }

    /// Generates a `CellSignature` (`u32`) for a given entity list.
    pub fn generateSignature(entityList: *std.ArrayList(*Entity)) CellSignature {
        var signature: CellSignature = 0;
        const entityCount = @as(u32, @intCast(entityList.items.len)); // Encodes the number of entities in the lowest 8 bits
        signature |= entityCount & 0xFF;

        for (entityList.items) |entity| { // Encodes entity type information in the higher bits
            const entityTypeShift = @as(u5, @intFromEnum(entity.entityType)) + 16;
            signature |= (@as(u32, 1) << entityTypeShift);
        }

        return signature;
    }

    /// Returns a slice of nearby entities within a 3x3 grid centered around the given x, y coordinates.
    /// Returns an error if the number of nearby entities exceeds `limit`.
    pub fn entitiesNear(self: *Grid, x: u16, y: u16, limit: comptime_int) ![]*Entity {
        var nearbyEntities: [limit]*Entity = undefined;
        var count: usize = 0;

        // Gets a 3x3 section of the grid
        const offsets = utils.Grid.getValidNeighbors(x, y, main.mapWidth, main.mapHeight);

        // Prioritizes player if in central cell
        if (utils.Grid.gridX(main.gamePlayer.x) == offsets[0][0] and utils.Grid.gridY(main.gamePlayer.y) == offsets[0][1]) {
            nearbyEntities[count] = main.gamePlayer.getEntity();
            count += 1;
        }

        for (offsets) |offset| { // For each neighboring cell
            const neighborX = offset[0];
            const neighborY = offset[1];
            const neighborKey = utils.SpatialHash.hash(neighborX, neighborY);

            if (self.cells.get(neighborKey)) |list| { // Lists the cell contents
                for (list.items) |entity| { // For each entity in the cell
                    if (count >= limit) return error.EntityAmountExceedsLimit;
                    nearbyEntities[count] = entity;
                    count += 1;
                }
            }
        }
        //if (utils.perFrame(60)) std.debug.print("Searching for entities near {}, {}. Found {} entities within area from {},{} to {},{}.\n", .{ x, y, count, (x - utils.SpatialHash.CellSize), (y - utils.SpatialHash.CellSize), (x + utils.SpatialHash.CellSize), (y + utils.SpatialHash.CellSize) });
        return nearbyEntities[0..count];
    }

    /// Finds entities in a 3x3 cell radius, then performs an axis-aligned bounding box check. Returns first colliding entity or null.
    pub fn collidesWith(self: *Grid, x: u16, y: u16, width: u16, height: u16, currentEntity: ?*Entity) !?*Entity {
        const halfWidth = @divTrunc(width, 2);
        const halfHeight = @divTrunc(height, 2);
        const left = @max(halfHeight, x) - halfWidth;
        const right = x + halfWidth;
        const top = @max(halfHeight, y) - halfHeight;
        const bottom = y + halfHeight;
        const nearbyEntities = if (currentEntity != null and currentEntity.?.entityType == EntityType.Unit) try self.entitiesNear(x, y, main.UNIT_SEARCH_LIMIT) else try self.entitiesNear(x, y, main.PLAYER_SEARCH_LIMIT);
        for (nearbyEntities) |entity| {
            if (currentEntity) |cur| {
                if (cur == entity) {
                    continue; // Skip current entity
                }
            }

            const entityHalfWidth = @divTrunc(entityWidth(entity), 2);
            const entityHalfHeight = @divTrunc(entityHeight(entity), 2);

            const entityLeft = @max(entityHalfWidth, entityX(entity)) - entityHalfWidth;
            const entityRight = entityX(entity) + entityHalfWidth;
            const entityTop = @max(entityHalfHeight, entityY(entity)) - entityHalfHeight;
            const entityBottom = entityY(entity) + entityHalfHeight;

            if ((left < entityRight) and (right > entityLeft) and
                (top < entityBottom) and (bottom > entityTop))
            {
                return entity; // Returns colliding entity
            }
        }
        return null;
    }
};
