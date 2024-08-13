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

const Entity = struct {
    entityType: EntityType,
    entity: union(EntityType) { // Stores pointer to the actual data
        Player: *Player,
        Unit: *Unit,
        Structure: *Structure,
    },
};

fn entityWidth(entity: *Entity) u16 {
    return switch (entity.entityType) {
        EntityType.Player => entity.entity.Player.width,
        EntityType.Unit => entity.entity.Unit.width,
        EntityType.Structure => entity.entity.Structure.width,
    };
}

fn entityHeight(entity: *Entity) u16 {
    return switch (entity.entityType) {
        EntityType.Player => entity.entity.Player.height,
        EntityType.Unit => entity.entity.Unit.height,
        EntityType.Structure => entity.entity.Structure.height,
    };
}

fn entityX(entity: *Entity) u16 {
    return switch (entity.entityType) {
        EntityType.Player => entity.entity.Player.x,
        EntityType.Unit => entity.entity.Unit.x,
        EntityType.Structure => entity.entity.Structure.x,
    };
}

fn entityY(entity: *Entity) u16 {
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
                try self.updateMoveInput(input);
                try self.updateActionInput(input);
            }
        } else { // If AI or remote player
            // updateMoveEvent, determine movement based on network or AI logic
            // updateActionEvent, determine ability use based on network or AI logic
        }
    }

    fn updateMoveInput(self: *Player, keyInput: u32) !void {
        const oldX = self.x;
        const oldY = self.y;
        const speed = utils.scaleToTickRate(self.speed);
        var newX: ?u16 = null;
        var newY: ?u16 = null;
        var obstacleX: ?*Entity = null;
        var obstacleY: ?*Entity = null;

        if (main.keys.actionActive(keyInput, utils.Key.Action.MoveUp)) {
            newY = utils.mapClampY(@truncate(utils.i32SubFloat(f32, self.y, speed)), self.height);
            self.direction = 8; // Numpad direction
        }
        if (main.keys.actionActive(keyInput, utils.Key.Action.MoveLeft)) {
            newX = utils.mapClampX(@truncate(utils.i32SubFloat(f32, self.x, speed)), self.width);
            self.direction = 4; // Numpad direction
        }
        if (main.keys.actionActive(keyInput, utils.Key.Action.MoveDown)) {
            newY = utils.mapClampY(@truncate(utils.i32AddFloat(f32, self.y, speed)), self.height);
            self.direction = 2; // Numpad direction
        }
        if (main.keys.actionActive(keyInput, utils.Key.Action.MoveRight)) {
            newX = utils.mapClampX(@truncate(utils.i32AddFloat(f32, self.x, speed)), self.width);
            self.direction = 6; // Numpad direction
        }

        if (newX != null)
            obstacleX = main.gameGrid.collidesWith(newX.?, self.y, self.width, self.height, Player.getEntity(self)) catch null;

        if (newY != null)
            obstacleY = main.gameGrid.collidesWith(self.x, newY.?, self.width, self.height, Player.getEntity(self)) catch null;

        if (newX != null) {
            if (obstacleX == null) {
                self.x = newX.?;
            } else if (newY == null and obstacleX.?.entityType == EntityType.Unit) { // If unit obstacle, try pushing horizontally

                const resistance = 0.1; // maybe depend on size relation
                const force = (1.0 - resistance);
                const difference = @as(f64, @floatFromInt(@as(i32, newX.?) - @as(i32, oldX)));
                newX = @as(u16, @intCast(@as(i32, oldX) + @as(i32, @intFromFloat(difference * force))));

                if (obstacleX.?.entity.Unit.moved(self.direction, speed * force)) { // True if push went through
                    obstacleX = main.gameGrid.collidesWith(newX.?, self.y, self.width, self.height, Player.getEntity(self)) catch null;
                    if (obstacleX == null) self.x = newX.?;
                }
            }
        }

        if (newY != null) {
            if (obstacleY == null) {
                self.y = newY.?;
            } else if (newX == null and obstacleY.?.entityType == EntityType.Unit) { // If unit collider, try pushing vertically

                const resistance = 0.1; // maybe depend on size relation
                const force = (1.0 - resistance);
                const difference = @as(f64, @floatFromInt(@as(i32, newY.?) - @as(i32, oldY)));
                newY = @as(u16, @intCast(@as(i32, oldY) + @as(i32, @intFromFloat(difference * force))));

                if (obstacleY.?.entity.Unit.moved(self.direction, speed * force)) { // True if push went through
                    obstacleY = main.gameGrid.collidesWith(self.x, newY.?, self.width, self.height, Player.getEntity(self)) catch null;
                    if (obstacleY == null) self.y = newY.?;
                }
            }
        }

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
    cellSignature: ?Grid.CellSignature,

    pub fn draw(self: *Unit) void {
        utils.drawEntity(self.x, self.y, self.width, self.height, self.color());
    }

    pub fn update(self: *Unit) void {
        const dx = @as(f16, @floatFromInt(utils.randomI16(2) - 1)) * 0.2; // Test
        const dy = @as(f16, @floatFromInt(utils.randomI16(2) - 1)) * 0.2; // Test
        _ = self.move(dx, dy);

        // move, determine movement based on AI logic
        // act, determine based on AI logic

        self.life -= 1;
        if (self.life <= 0) self.die(null);
    }

    /// Unit moving of its own accord. Searches for collision. If no obstacle is found, unit moves. If obstacle is found, unit moves away if equal to or smaller than the obstacle.
    pub fn move(self: *Unit, dx: f16, dy: f16) void {
        const oldX = self.x;
        const oldY = self.y;
        const newX = utils.u16AddFloat(f16, oldX, (dx * self.speed()));
        const newY = utils.u16AddFloat(f16, oldY, (dy * self.speed()));

        if (utils.isInMap(newX, newY, self.width, self.height)) {

            // Idea: Have unit favor moving along halfgrid. Only do "collidesWithGeneral" if unit x,y is NOT on halfgrid
            // Otherwise, do a more performant (1-dimensional?) grid collision detection or similar
            const obstacle = main.gameGrid.collidesWith(newX, newY, self.width, self.height, Unit.getEntity(self)) catch null;

            if (obstacle == null) {
                self.x = newX;
                self.y = newY;

                main.gameGrid.updateEntity(getEntity(self), oldX, oldY);
            } else if (biggerEntity(getEntity(self), obstacle.?) != getEntity(self)) { // Obstacle is bigger or equal
                const diffX = @as(i32, self.x) - @as(i32, entityX(obstacle.?));
                const diffY = @as(i32, self.y) - @as(i32, entityY(obstacle.?));
                const angle = utils.deltaToAngle(diffX, diffY);
                const vector = utils.angleToVector(angle, self.speed());
                self.x = utils.u16AddFloat(f32, oldX, vector[0]);
                self.y = utils.u16AddFloat(f32, oldY, vector[1]);
                main.gameGrid.updateEntity(getEntity(self), oldX, oldY);
            }
        }
    }

    /// Unit is pushed by another entity. Searches for collision. If no obstacle is found, unit moves and returns `true`. Otherwise, returns `false`.
    pub fn moved(self: *Unit, dir: u8, distance: f32) bool {
        const oldX = self.x;
        const oldY = self.y;
        const deltaXy = utils.dirDelta(dir);
        const newX = @as(u16, @intFromFloat(@as(f32, @floatFromInt(self.x)) + distance * @as(f32, @floatFromInt(deltaXy[0]))));
        const newY = @as(u16, @intFromFloat(@as(f32, @floatFromInt(self.y)) + distance * @as(f32, @floatFromInt(deltaXy[1]))));

        if (utils.isInMap(newX, newY, self.width, self.height)) {
            const obstacle = main.gameGrid.collidesWith(newX, newY, self.width, self.height, Unit.getEntity(self)) catch null;

            if (obstacle == null) {
                self.x = newX;
                self.y = newY;
                main.gameGrid.updateEntity(getEntity(self), oldX, oldY);
                return true;
            }
        }
        return false;
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
            .cellSignature = main.gameGrid.getCellSignature(utils.Grid.gridX(x), utils.Grid.gridX(y)),
        };

        entityUnit.* = Entity{
            .entityType = EntityType.Unit,
            .entity = .{ .Unit = unit }, // Store the pointer to the Unit
        };

        try main.gameGrid.addEntity(entityUnit, null, null);
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

    /// Unit property fields.
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
            0 => Properties{ .speed = 5, .color = rl.Color.sky_blue, .width = 44, .height = 44, .life = 2000 },
            1 => Properties{ .speed = 6, .color = rl.Color.blue, .width = 28, .height = 28, .life = 3000 },
            2 => Properties{ .speed = 4, .color = rl.Color.dark_blue, .width = 64, .height = 64, .life = 4000 },
            3 => Properties{ .speed = 6, .color = rl.Color.violet, .width = 32, .height = 32, .life = 5000 },
            else => @panic("Invalid unit class"),
        };
    }

    pub fn updateCellSignature(self: *Unit) void {
        self.cellSignature = main.gameGrid.getCellSignature(utils.Grid.gridX(self.x), utils.Grid.gridY(self.y));
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
        const delta = utils.angleToVector(self.angle, self.speed);
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
    cells: std.hash_map.HashMap(u64, std.ArrayList(*Entity), utils.SpatialHash.Context, 80) = undefined,
    allocator: *std.mem.Allocator,

    const CellSignature = u32;

    pub fn init(self: *Grid, allocator: *std.mem.Allocator) !void {
        self.allocator = allocator;
        self.cells = std.hash_map.HashMap(u64, std.ArrayList(*Entity), utils.SpatialHash.Context, 80).init(allocator.*);
    }

    pub fn deinit(self: *Grid) void {
        var it = self.cells.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit(); // Dereference value_ptr to access and deinitialize the value
        }
        self.cells.deinit();
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
                //entity.entity.Unit.updateCellSignature();
            }

            // std.debug.print("(Grid update end) After adding/removing entity: \n", .{});
            // var it2 = self.cells.iterator();
            // while (it2.next()) |entry| {
            //     std.debug.print("Cell {any} contains entities: {any}\n", .{ entry.key_ptr, entry.value_ptr.items });
            // }
        }
    }

    pub fn getCellSignature(self: *Grid, cellX: u16, cellY: u16) ?CellSignature {
        const key = utils.SpatialHash.hash(cellX, cellY);

        // Retrieve the list of entities in the cell
        if (self.cells.get(key)) |entityList| {
            var signature: CellSignature = 0;

            // Encode the number of entities in the lowest 8 bits
            const entityCount = @as(u32, @intCast(entityList.items.len));
            signature |= entityCount & 0xFF;

            // Optionally, encode entity type information in the higher bits
            for (entityList.items) |entity| {
                const entityTypeShift = @as(u32, @intFromEnum(entity.entityType)) + 16;
                signature |= (@as(u32, 1) << @as(u5, @intCast(entityTypeShift)));
            }

            return signature;
        }
        // If the cell is empty or doesn't exist, return null
        return null;
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

    /// Finds entities in a 3x3 cell radius, then performs a bounding box check. Returns first colliding entity.
    pub fn collidesWith(self: *Grid, x: u16, y: u16, width: u16, height: u16, currentEntity: ?*Entity) !?*Entity {
        const halfWidth = @divTrunc(width, 2);
        const halfHeight = @divTrunc(height, 2);
        const left = x - halfWidth;
        const right = x + halfWidth;
        const top = y - halfHeight;
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

            const entityLeft = entityX(entity) - entityHalfWidth;
            const entityRight = entityX(entity) + entityHalfWidth;
            const entityTop = entityY(entity) - entityHalfHeight;
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
