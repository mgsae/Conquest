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
    entity: union(EntityType) { // Stores the actual entity data
        Player: *Player,
        Unit: *Unit,
        Structure: *Structure,
    },
};

fn entityWidth(entity: *Entity) i32 {
    return switch (entity.entityType) {
        EntityType.Player => entity.entity.Player.width,
        EntityType.Unit => entity.entity.Unit.width,
        EntityType.Structure => entity.entity.Structure.width,
    };
}

fn entityHeight(entity: *const Entity) i32 {
    return switch (entity.entityType) {
        EntityType.Player => entity.entity.Player.height,
        EntityType.Unit => entity.entity.Unit.height,
        EntityType.Structure => entity.entity.Structure.height,
    };
}

fn entityX(entity: *const Entity) i32 {
    return switch (entity.entityType) {
        EntityType.Player => entity.entity.Player.x,
        EntityType.Unit => entity.entity.Unit.x,
        EntityType.Structure => entity.entity.Structure.x,
    };
}

fn entityY(entity: *const Entity) i32 {
    return switch (entity.entityType) {
        EntityType.Player => entity.entity.Player.y,
        EntityType.Unit => entity.entity.Unit.y,
        EntityType.Structure => entity.entity.Structure.y,
    };
}

// Player //
//----------------------------------------------------------------------------------
pub const Player = struct {
    entity: *Entity,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
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

    fn updateMoveInput(self: *Player, keyInput: u32) anyerror!void {
        var newX: ?i32 = null;
        var newY: ?i32 = null;
        const oldX = self.x;
        const oldY = self.y;
        var canMoveX = true;
        var canMoveY = true;
        const speed = utils.scaleToFrameRate(self.speed);

        if ((keyInput & (1 << 0)) != 0) { // key_w
            newY = utils.mapClampY(utils.i32SubFloat(f32, self.y, speed), self.height);
            self.direction = 8; // Numpad direction
        }
        if ((keyInput & (1 << 1)) != 0) { // key_a
            newX = utils.mapClampX(utils.i32SubFloat(f32, self.x, speed), self.width);
            self.direction = 4; // Numpad direction
        }
        if ((keyInput & (1 << 2)) != 0) { // key_s
            newY = utils.mapClampY(utils.i32AddFloat(f32, self.y, speed), self.height);
            self.direction = 2; // Numpad direction
        }
        if ((keyInput & (1 << 3)) != 0) { // key_d
            newX = utils.mapClampX(utils.i32AddFloat(f32, self.x, speed), self.width);
            self.direction = 6; // Numpad direction
        }

        if (newX != null) {
            canMoveX = !try main.gameGrid.entityCollision(newX.?, self.y, self.width, self.height, Player.getEntity(self));
            if (canMoveX) self.x = newX.?;
        }
        if (newY != null) {
            canMoveY = !try main.gameGrid.entityCollision(self.x, newY.?, self.width, self.height, Player.getEntity(self));
            if (canMoveY) self.y = newY.?;
        }

        if ((newX != null and canMoveX) or (newY != null and canMoveY)) {
            std.debug.print("Updating player entity with oldX, oldY: {},{} to newX, newY: {},{} )\n", .{ oldX, oldY, self.x, self.y });
            main.gameGrid.updateEntity(getEntity(self), oldX, oldY);
        }
    }

    fn updateActionInput(self: *Player, keyInput: u32) anyerror!void {
        var built: ?*Structure = undefined;
        var buildAttempted: bool = false;
        const dir = self.direction;

        if ((keyInput & (1 << 4)) != 0) { // key_one
            const class = Structure.classProperties(0);
            const clearX = if (dir == 4 or dir == 6) @divTrunc(class.width, 2) + @divTrunc(self.width, 2) else 0;
            const clearY = if (dir == 2 or dir == 8) @divTrunc(class.height, 2) + @divTrunc(self.height, 2) else 0;
            built = Structure.build(if (dir == 4) self.x - clearX else self.x + clearX, if (dir == 8) self.y - clearY else self.y + clearY, 0);
            buildAttempted = true;
        }
        if ((keyInput & (1 << 5)) != 0) { // key_two
            const class = Structure.classProperties(1);
            const clearX = if (dir == 4 or dir == 6) @divTrunc(class.width, 2) + @divTrunc(self.width, 2) else 0;
            const clearY = if (dir == 2 or dir == 8) @divTrunc(class.height, 2) + @divTrunc(self.height, 2) else 0;
            built = Structure.build(if (dir == 4) self.x - clearX else self.x + clearX, if (dir == 8) self.y - clearY else self.y + clearY, 1);
            buildAttempted = true;
        }
        if ((keyInput & (1 << 6)) != 0) { // key_three
            const class = Structure.classProperties(2);
            const clearX = if (dir == 4 or dir == 6) @divTrunc(class.width, 2) + @divTrunc(self.width, 2) else 0;
            const clearY = if (dir == 2 or dir == 8) @divTrunc(class.height, 2) + @divTrunc(self.height, 2) else 0;
            built = Structure.build(if (dir == 4) self.x - clearX else self.x + clearX, if (dir == 8) self.y - clearY else self.y + clearY, 2);
            buildAttempted = true;
        }
        if ((keyInput & (1 << 7)) != 0) { // key_four
            const class = Structure.classProperties(3);
            const clearX = if (dir == 4 or dir == 6) @divTrunc(class.width, 2) + @divTrunc(self.width, 2) else 0;
            const clearY = if (dir == 2 or dir == 8) @divTrunc(class.height, 2) + @divTrunc(self.height, 2) else 0;
            built = Structure.build(if (dir == 4) self.x - clearX else self.x + clearX, if (dir == 8) self.y - clearY else self.y + clearY, 3);
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

    pub fn createLocal(x: i32, y: i32) !*Player {
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

    pub fn createRemote(x: i32, y: i32) !*Player {
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
    speed: f16,
    color: rl.Color,
    x: i32,
    y: i32,
    width: u16,
    height: u16,
    life: u16,

    pub fn draw(self: *const Unit) void {
        utils.drawEntity(self.x, self.y, self.width, self.height, self.color);
    }

    pub fn update(self: *Unit) void {
        const dx = @as(f16, @floatFromInt(utils.randomInt(2) - 1)); // Test
        const dy = @as(f16, @floatFromInt(utils.randomInt(2) - 1)); // Test
        self.move(dx, dy);

        // move, determine movement based on AI logic
        // act, determine ability use based on AI logic

        self.life -= 1;
        if (self.life <= 0) self.die(null);
    }

    pub fn move(self: *Unit, dx: f16, dy: f16) void {
        const oldX = self.x;
        const oldY = self.y;
        const newX = utils.i32AddFloat(f16, oldX, (dx * self.speed));
        const newY = utils.i32AddFloat(f16, oldY, (dy * self.speed));

        // Check collisions in nearby grid cells
        const collides = false; // main.gameGrid.entityCollision(newX, newY, self.width, self.height, Unit.getEntity(self)) catch true;

        // Apply movement
        if (!collides) {
            self.x = utils.mapClampX(newX, self.width);
            self.y = utils.mapClampY(newY, self.height);
            main.gameGrid.updateEntity(getEntity(self), oldX, oldY);
        }
    }

    pub fn create(x: i32, y: i32, class: u8) !*Unit {
        const entityUnit = try main.gameGrid.allocator.create(Entity); // Memory for the parent entity
        const fromClass = Unit.classProperties(class);
        const unit = try main.gameGrid.allocator.create(Unit); // Allocate memory for Unit and get a pointer

        unit.* = Unit{
            .entity = entityUnit,
            .class = class,
            .speed = fromClass.speed,
            .color = fromClass.color,
            .width = fromClass.width,
            .height = fromClass.height,
            .life = fromClass.life,
            .x = x,
            .y = y,
        };

        entityUnit.* = Entity{
            .entityType = EntityType.Unit,
            .entity = .{ .Unit = unit }, // Store the pointer to the Unit
        };

        // std.debug.print("Created unit at ({}, {}) with entity pointer {}\n", .{ x, y, @intFromPtr(entityUnit) });
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

    pub const UnitProperties = struct {
        speed: f16,
        color: rl.Color,
        width: u16,
        height: u16,
        life: u16,
    };

    pub fn classProperties(class: u8) UnitProperties {
        return switch (class) {
            0 => UnitProperties{ .speed = 5, .color = rl.Color.sky_blue, .width = 25, .height = 25, .life = 2000 },
            1 => UnitProperties{ .speed = 6, .color = rl.Color.blue, .width = 40, .height = 40, .life = 3000 },
            2 => UnitProperties{ .speed = 4, .color = rl.Color.dark_blue, .width = 50, .height = 50, .life = 4000 },
            3 => UnitProperties{ .speed = 6, .color = rl.Color.violet, .width = 35, .height = 35, .life = 5000 },
            else => @panic("Invalid unit class"),
        };
    }

    pub fn getEntity(unit: *Unit) *Entity {
        return unit.entity;
    }
};

// Structure
//----------------------------------------------------------------------------------
pub const Structure = struct {
    entity: *Entity,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    class: u8,
    color: rl.Color,
    life: u16,
    pulse: u16,
    elapsed: u16 = 0,

    pub fn draw(self: *const Structure) void {
        utils.drawEntity(self.x, self.y, self.width, self.height, self.color);
    }

    pub fn update(self: *Structure) void {
        self.elapsed += 1;
        if (self.elapsed >= self.pulse) {
            self.elapsed -= self.pulse; // Subtracting interval accounts for possible overshoot
            self.spawnUnit() catch return;
        }
    }

    pub fn spawnUnit(self: *Structure) !void {
        const unitClass = Structure.classToSpawnClass(self.class);
        const spawnPoint = getSpawnPoint(self.x, self.y, self.width, self.height, Unit.classProperties(unitClass).width, Unit.classProperties(unitClass).width) catch null;
        if (spawnPoint) |sp| { // If spawnPoint is not null, unwrap it
            try units.append(try Unit.create(sp[0], sp[1], unitClass));
        } else {
            // std.debug.print("Failed to find a spawn point.\n", .{});
        }
    }

    pub fn create(x: i32, y: i32, class: u8) !*Structure {
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

    pub fn build(x: i32, y: i32, class: u8) ?*Structure {
        const collision = main.gameGrid.entityCollision(x, y, 150, 150, Player.getEntity(main.gamePlayer)) catch return null;
        if (collision or !utils.isInMap(x, y, classProperties(class).width, classProperties(class).height)) {
            return null;
        }
        const structure = Structure.create(x, y, class) catch return null;
        structures.append(structure) catch return null;
        return structure;
    }

    pub const StructureProperties = struct {
        color: rl.Color,
        width: u16,
        height: u16,
        life: u16,
        pulse: u16,
    };

    pub fn classProperties(class: u8) StructureProperties {
        return switch (class) {
            0 => StructureProperties{ .color = rl.Color.sky_blue, .width = 150, .height = 150, .life = 5000, .pulse = 180 },
            1 => StructureProperties{ .color = rl.Color.blue, .width = 175, .height = 175, .life = 6000, .pulse = 320 },
            2 => StructureProperties{ .color = rl.Color.dark_blue, .width = 150, .height = 150, .life = 7000, .pulse = 240 },
            3 => StructureProperties{ .color = rl.Color.violet, .width = 125, .height = 125, .life = 8000, .pulse = 120 },
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

    pub fn getSpawnPoint(x: i32, y: i32, structureWidth: i32, structureHeight: i32, unitWidth: i32, unitHeight: i32) ![2]i32 {
        var attempts: usize = 0;
        var sidesChecked = [_]bool{ false, false, false, false }; // Track which sides have been checked
        while (attempts < 4) {
            const sideIndex = @as(usize, @intCast(utils.randomInt(3)));
            if (sidesChecked[sideIndex]) {
                continue; // Skip already checked sides
            }
            sidesChecked[sideIndex] = true;
            attempts += 1;

            var spawnX: i32 = 0;
            var spawnY: i32 = 0;

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

            if (!try main.gameGrid.entityCollision(spawnX, spawnY, unitWidth, unitHeight, null) and utils.isInMap(spawnX, spawnY, unitWidth, unitHeight)) {
                return [2]i32{ spawnX, spawnY };
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
    x: i32,
    y: i32,
    width: i32 = 1,
    height: i32 = 1,
    speed: f16,
    angle: f16,
    color: rl.Color,

    pub fn update(self: Projectile) void {
        const delta = utils.angleToVector(self.angle);
        self.x += delta[0] * self.speed;
        self.y += delta[1] * self.speed;
        self.speed -= 0.4; // loses 24.0 speed per second
        if (self.speed < 1.0) {
            self.destroy();
        }
    }

    pub fn draw(self: Projectile) void {
        utils.drawEntity(self.x, self.y, self.width, self.height, self.color);
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

const HashMap = std.hash_map.HashMap(u64, std.ArrayList(*Entity), utils.HashContext, 80);

const GridCell = struct {
    entities: std.ArrayList(*Entity) = undefined,
};

pub const Grid = struct {
    cells: HashMap = undefined,
    allocator: std.mem.Allocator,

    pub fn init(self: *Grid, allocator: std.mem.Allocator) !void {
        self.allocator = allocator;
        self.cells = HashMap.init(allocator);
    }

    pub fn deinit(self: *Grid) void {
        var it = self.cells.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit(); // Dereference value_ptr to access and deinitialize the value
        }
        self.cells.deinit();
    }

    pub fn addEntity(self: *Grid, entity: *Entity, newX: ?i32, newY: ?i32) !void {
        const x = newX orelse entityX(entity);
        const y = newY orelse entityY(entity);
        const key = utils.SpatialHash.hash(x, y);

        //std.debug.print("Adding entity to cell with hash {}\n", .{key});

        const result = try self.cells.getOrPut(key);
        if (!result.found_existing) {
            result.value_ptr.* = std.ArrayList(*Entity).init(self.allocator);
        } else {
            // Ensure the entity is not already in the cell to avoid duplicates
            for (result.value_ptr.*.items) |existing_entity| {
                if (existing_entity == entity) {
                    std.log.err("Entity already exists in cell with hash {}, skipping add\n", .{key});
                    return;
                }
            }
        }
        try result.value_ptr.*.append(entity);
    }

    pub fn removeEntity(self: *Grid, entity: *Entity, oldX: ?i32, oldY: ?i32) !void {
        const x = std.math.clamp(oldX orelse entityX(entity), 0, main.mapWidth);
        const y = std.math.clamp(oldY orelse entityY(entity), 0, main.mapHeight);
        const key = utils.SpatialHash.hash(x, y);

        //std.debug.print("Attempting to remove entity from cell with hash {} at position ({}, {})\n", .{ key, x, y });

        if (self.cells.get(key)) |list| {
            var removed = false;
            for (list.items, 0..) |e, index| {
                if (e == entity) {
                    _ = @constCast(&list).swapRemove(index);
                    removed = true;
                    //std.debug.print("Entity successfully removed from cell with hash {}\n", .{key});
                    if (list.items.len == 0) {
                        _ = self.cells.remove(key); // Safely remove the entry from the map
                    }
                    break;
                }
            }
            if (!removed) {
                //std.log.err("Failed to find entity in cell with hash {} for removal\n", .{key});
            }
        } else {
            //std.debug.print("Cell with hash {} not found for entity removal\n", .{key});
        }
    }

    pub fn updateEntity(self: *Grid, entity: *Entity, oldX: i32, oldY: i32) void {
        const oldKey = utils.SpatialHash.hash(std.math.clamp(oldX, 0, main.mapWidth), std.math.clamp(oldY, 0, main.mapHeight));
        const newKey = utils.SpatialHash.hash(std.math.clamp(entityX(entity), 0, main.mapWidth), std.math.clamp(entityY(entity), 0, main.mapHeight));

        if (oldKey != newKey) {
            //std.debug.print("Entity is moving from cell {} to cell {}\n", .{ oldKey, newKey });
            //std.debug.print("Cell {} before removal: {?}\n", .{ oldKey, self.cells.get(oldKey) });
            self.removeEntity(entity, oldX, oldY) catch @panic("Failed to remove entity from grid");
            //std.debug.print("Cell {} after removal: {?}\n", .{ oldKey, self.cells.get(oldKey) });
            self.addEntity(entity, null, null) catch @panic("Failed to add entity to grid");
        } else {
            //std.debug.print("Entity remains in the same cell {}\n", .{oldKey});
        }
    }

    pub fn getNearbyEntities(self: *Grid, x: i32, y: i32) ![]*Entity {
        var nearbyEntities: [main.ENTITY_COLLISION_LIMIT]*Entity = undefined;
        var count: usize = 0;

        const offsets = [_][2]i32{
            [_]i32{ 0, 0 },
            [_]i32{ -utils.SpatialHash.CellSize, 0 },
            [_]i32{ utils.SpatialHash.CellSize, 0 },
            [_]i32{ 0, -utils.SpatialHash.CellSize },
            [_]i32{ 0, utils.SpatialHash.CellSize },
            [_]i32{ -utils.SpatialHash.CellSize, -utils.SpatialHash.CellSize },
            [_]i32{ utils.SpatialHash.CellSize, utils.SpatialHash.CellSize },
            [_]i32{ -utils.SpatialHash.CellSize, utils.SpatialHash.CellSize },
            [_]i32{ utils.SpatialHash.CellSize, -utils.SpatialHash.CellSize },
        };

        for (offsets) |offset| {
            const offsetX = std.math.clamp(x + offset[0], 0, main.mapWidth);
            const offsetY = std.math.clamp(y + offset[1], 0, main.mapHeight);
            const neighborKey = utils.SpatialHash.hash(offsetX, offsetY);
            if (self.cells.get(neighborKey)) |list| {
                for (list.items) |entity| {
                    if (count < main.ENTITY_COLLISION_LIMIT) {
                        nearbyEntities[count] = entity;
                        count += 1;
                    } else {
                        return error.TooManyEntities;
                    }
                }
            }
        }
        return nearbyEntities[0..count];
    }

    pub fn entityCollision(self: *Grid, x: i32, y: i32, width: i32, height: i32, currentEntity: ?*Entity) !bool {
        const halfWidth = @divTrunc(width, 2);
        const halfHeight = @divTrunc(height, 2);

        const left = x - halfWidth;
        const right = x + halfWidth;
        const top = y - halfHeight;
        const bottom = y + halfHeight;

        const nearbyEntities = try self.getNearbyEntities(x, y);

        for (nearbyEntities) |entity| {
            if (currentEntity) |cur| {
                if (@intFromPtr(cur) == @intFromPtr(entity)) {
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
                return true;
            }
        }
        return false;
    }
};
