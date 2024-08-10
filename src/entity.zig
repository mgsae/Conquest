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

    pub fn update(self: *Player, keyPresses: ?u32) anyerror!void {
        if (self.local) { // Local player
            if (keyPresses) |presses| {
                try self.updateMoveInput(presses);
                try self.updateActionInput(presses);
            }
        } else { // If AI or remote player
            // updateMoveEvent, determine movement based on network or AI logic
            // updateActionEvent, determine ability use based on network or AI logic
        }
    }

    fn updateMoveInput(self: *Player, keyPresses: u32) anyerror!void {
        var newX: ?i32 = null;
        var newY: ?i32 = null;

        // Check bitwise keypress data to calculate new position
        if ((keyPresses & (1 << 0)) != 0) { // W
            newY = utils.mapClampY(utils.iSubF16(self.y, self.speed), self.height);
            self.direction = 8; // Numpad direction
        }
        if ((keyPresses & (1 << 1)) != 0) { // A
            newX = utils.mapClampX(utils.iSubF16(self.x, self.speed), self.width);
            self.direction = 4; // Numpad direction
        }
        if ((keyPresses & (1 << 2)) != 0) { // S
            newY = utils.mapClampY(utils.iAddF16(self.y, self.speed), self.height);
            self.direction = 2; // Numpad direction
        }
        if ((keyPresses & (1 << 3)) != 0) { // D
            newX = utils.mapClampX(utils.iAddF16(self.x, self.speed), self.width);
            self.direction = 6; // Numpad direction
        }

        // Check collisions
        const canMoveX: bool = if (newX != null) !try entityCollision(newX.?, self.y, self.width, self.height, Player.getEntity(self)) else true;
        const canMoveY: bool = if (newY != null) !try entityCollision(self.x, newY.?, self.width, self.height, Player.getEntity(self)) else true;

        // Apply movement
        if (canMoveX or canMoveY) {
            const oldX = self.x;
            const oldY = self.y;
            self.x = newX orelse oldX;
            self.y = newY orelse oldY;
            main.gameGrid.updateEntity(getEntity(self), oldX, oldY);
        }
    }

    fn updateActionInput(self: *Player, keyPresses: u32) anyerror!void {
        var built: ?*Structure = undefined;
        var buildAttempted: bool = false;
        const dir = self.direction;

        if ((keyPresses & (1 << 4)) != 0) {
            const class = Structure.classProperties(0);
            const clearX = if (dir == 4 or dir == 6) @divTrunc(class.width, 2) + @divTrunc(self.width, 2) else 0;
            const clearY = if (dir == 2 or dir == 8) @divTrunc(class.height, 2) + @divTrunc(self.height, 2) else 0;
            built = Structure.build(if (dir == 4) self.x - clearX else self.x + clearX, if (dir == 8) self.y - clearY else self.y + clearY, 0);
            buildAttempted = true;
        }
        if ((keyPresses & (1 << 5)) != 0) {
            const class = Structure.classProperties(1);
            const clearX = if (dir == 4 or dir == 6) @divTrunc(class.width, 2) + @divTrunc(self.width, 2) else 0;
            const clearY = if (dir == 2 or dir == 8) @divTrunc(class.height, 2) + @divTrunc(self.height, 2) else 0;
            built = Structure.build(if (dir == 4) self.x - clearX else self.x + clearX, if (dir == 8) self.y - clearY else self.y + clearY, 1);
            buildAttempted = true;
        }
        if ((keyPresses & (1 << 6)) != 0) {
            const class = Structure.classProperties(2);
            const clearX = if (dir == 4 or dir == 6) @divTrunc(class.width, 2) + @divTrunc(self.width, 2) else 0;
            const clearY = if (dir == 2 or dir == 8) @divTrunc(class.height, 2) + @divTrunc(self.height, 2) else 0;
            built = Structure.build(if (dir == 4) self.x - clearX else self.x + clearX, if (dir == 8) self.y - clearY else self.y + clearY, 2);
            buildAttempted = true;
        }
        if ((keyPresses & (1 << 7)) != 0) {
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
    hp: u16,

    pub fn draw(self: *const Unit) void {
        utils.drawEntity(self.x, self.y, self.width, self.height, self.color);
    }

    pub fn update(self: *Unit) void {
        const dx = @as(f16, @floatFromInt(utils.randomInt(2) - 1)); // Test
        const dy = @as(f16, @floatFromInt(utils.randomInt(2) - 1)); // Test
        self.move(dx, dy);
        // move, determine movement based on AI logic
        // act, determine ability use based on AI logic
    }

    pub fn move(self: *Unit, dx: f16, dy: f16) void {
        const oldX = self.x;
        const oldY = self.y;
        const newX = utils.iAddF16(oldX, (dx * self.speed));
        const newY = utils.iAddF16(oldY, (dy * self.speed));

        // Check collisions in nearby grid cells
        // This caused out of memory crash
        const collides = entityCollision(newX, newY, self.width, self.height, Unit.getEntity(self)) catch true;

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
            .hp = fromClass.hp,
            .x = x,
            .y = y,
        };

        entityUnit.* = Entity{
            .entityType = EntityType.Unit,
            .entity = .{ .Unit = unit }, // Store the pointer to the Unit
        };

        std.debug.print("Created unit at ({}, {}) with entity pointer {}\n", .{ x, y, @intFromPtr(entityUnit) });
        try main.gameGrid.addEntity(entityUnit, null, null);
        return unit;
    }

    pub const UnitProperties = struct {
        speed: f16,
        color: rl.Color,
        width: u16,
        height: u16,
        hp: u16,
    };

    pub fn classProperties(class: u8) UnitProperties {
        return switch (class) {
            0 => UnitProperties{ .speed = 5, .color = rl.Color.sky_blue, .width = 50, .height = 50, .hp = 100 },
            1 => UnitProperties{ .speed = 6, .color = rl.Color.blue, .width = 55, .height = 55, .hp = 90 },
            2 => UnitProperties{ .speed = 4, .color = rl.Color.dark_blue, .width = 70, .height = 70, .hp = 130 },
            3 => UnitProperties{ .speed = 6, .color = rl.Color.violet, .width = 50, .height = 50, .hp = 150 },
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
    interval: u32,
    elapsed: u32 = 0,

    pub fn draw(self: *const Structure) void {
        utils.drawEntity(self.x, self.y, self.width, self.height, self.color);
    }

    pub fn update(self: *Structure) void {
        self.elapsed += 1;
        if (self.elapsed >= self.interval) {
            std.debug.print("Elapsed time {} surpasses interval {}.\n", .{ self.elapsed, self.interval });
            self.elapsed -= self.interval; // Reset elapsed time, accounting for possible overshoot
            self.spawnUnit() catch return;
        }
    }

    pub fn spawnUnit(self: *Structure) !void {
        const unitClass = Structure.classToSpawnClass(self.class);
        const spawnPoint = getSpawnPoint(self.x, self.y, self.width, self.height, Unit.classProperties(unitClass).width, Unit.classProperties(unitClass).width) catch null;
        if (spawnPoint) |sp| { // If spawnPoint is not null, unwrap it
            try units.append(try Unit.create(sp[0], sp[1], unitClass));
        } else {
            std.debug.print("Failed to find a spawn point.\n", .{});
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
            .interval = fromClass.interval,
            .x = x,
            .y = y,
        };
        entityStructure.* = Entity{
            .entityType = EntityType.Structure,
            .entity = .{ .Structure = structure },
        };

        std.debug.print("Created structure at ({}, {}) with entity pointer {}\n", .{ x, y, @intFromPtr(entityStructure) });
        try main.gameGrid.addEntity(entityStructure, null, null);
        return structure;
    }

    pub fn build(x: i32, y: i32, class: u8) ?*Structure {
        const collision = entityCollision(x, y, 150, 150, Player.getEntity(main.gamePlayer)) catch return null;
        if (collision) {
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
        hp: u16,
        interval: u32,
    };

    pub fn classProperties(class: u8) StructureProperties {
        return switch (class) {
            0 => StructureProperties{ .color = rl.Color.sky_blue, .width = 150, .height = 150, .hp = 500, .interval = 180 },
            1 => StructureProperties{ .color = rl.Color.blue, .width = 175, .height = 175, .hp = 600, .interval = 320 },
            2 => StructureProperties{ .color = rl.Color.dark_blue, .width = 150, .height = 150, .hp = 700, .interval = 240 },
            3 => StructureProperties{ .color = rl.Color.violet, .width = 125, .height = 125, .hp = 800, .interval = 120 },
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

            if (!try entityCollision(spawnX, spawnY, unitWidth, unitHeight, null)) {
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
        // Effect when projectile hits entity; subtract hp
        self.destroy();
    }

    pub fn destroy(self: Projectile) void {
        main.gameGrid.removeEntity(main.gameGrid, self);
    }

    pub fn getEntity(projectile: *Projectile) *Entity {
        return projectile.entity;
    }
};

// Map Geometry
//----------------------------------------------------------------------------------

const GridCell = struct {
    entities: std.ArrayList(*Entity) = undefined,
};

pub const Grid = struct {
    cells: [][]GridCell = undefined,
    allocator: *std.mem.Allocator,

    pub fn init(self: *Grid, width: usize, height: usize, allocator: *std.mem.Allocator) !void {
        self.allocator = allocator; // Initialize allocator

        // Allocate for rows (height of the grid)
        self.cells = try allocator.alloc([]GridCell, height);

        // For each row, allocate columns (width of the grid)
        for (0..self.cells.len) |rowIndex| {
            self.cells[rowIndex] = try allocator.alloc(GridCell, width); // Each row has `width` columns

            // Initialize each GridCell in the 2D grid
            for (0..self.cells[rowIndex].len) |colIndex| {
                self.cells[rowIndex][colIndex] = GridCell{
                    .entities = std.ArrayList(*Entity).init(allocator.*),
                };
                // std.debug.print("Initialized cell ({}, {})\n", .{ rowIndex, colIndex });
            }
        }
    }

    pub fn deinit(self: *Grid) void {
        for (self.cells) |row| {
            for (row) |*cell| {
                cell.entities.deinit();
            }
            self.allocator.free(row);
        }
        self.allocator.free(self.cells);
        std.debug.print("Deinitialized grid\n", .{});
    }

    pub fn toGridCoord(self: *Grid, x: i32, y: i32) utils.Grid.GridCoord {
        const coord = utils.Grid.toGridCoord(x, y, self.cells.len, self.cells[0].len);
        return coord;
    }

    pub fn addEntity(self: *Grid, entity: *Entity, newX: ?i32, newY: ?i32) !void {
        const x = newX orelse entityX(entity);
        const y = newY orelse entityY(entity);
        const coord = self.toGridCoord(x, y);
        // std.debug.print("Adding entity at grid coordinates: ({}, {})\n", .{ coord.x, coord.y });
        if (coord.x >= self.cells.len or coord.y >= self.cells[coord.x].len) {
            return error.IndexOutOfBounds; // Define this error appropriately
        }
        try self.cells[coord.x][coord.y].entities.append(entity);
        // std.debug.print("Entity added at grid coordinates: ({}, {})\n", .{ coord.x, coord.y });
    }

    pub fn removeEntity(self: *Grid, entity: *Entity, oldX: ?i32, oldY: ?i32) !void {
        const x = oldX orelse entityX(entity);
        const y = oldY orelse entityY(entity);
        const coord = self.toGridCoord(x, y);
        const cell = &self.cells[coord.x][coord.y];
        for (cell.entities.items, 0..) |*e, index| {
            if (e.* == entity) {
                _ = cell.entities.swapRemove(index);
                return;
            }
        }
    }

    pub fn updateEntity(self: *Grid, entity: *Entity, oldX: i32, oldY: i32) void {
        const oldCoord = self.toGridCoord(oldX, oldY);
        const newCoord = self.toGridCoord(entityX(entity), entityY(entity));
        // std.debug.print("Updating entity from ({}, {}) to ({}, {})\n", .{ oldCoord.x, oldCoord.y, newCoord.x, newCoord.y });
        if (oldCoord.x != newCoord.x or oldCoord.y != newCoord.y) {
            self.removeEntity(entity, oldX, oldY) catch @panic("Grid removal failed");
            self.addEntity(entity, null, null) catch @panic("Grid addition failed");
        }
    }

    pub fn getNearbyEntities(self: *Grid, x: i32, y: i32) ![]*Entity {
        // var nearbyEntities = std.ArrayList(*Entity).init(self.allocator.*); // Dereference allocator
        var nearbyEntities: [main.entityCollisionLimit]*Entity = undefined;
        var count: usize = 0;

        // std.debug.print("Searching nearby entities at grid coordinates: ({}, {})\n", .{ coord.x, coord.y });

        const coord = self.toGridCoord(x, y);
        // Includes the cells to the left, right, above, and below the central cell
        const startX = if (coord.x == 0) 0 else coord.x - 1;
        const endX = if (coord.x + 1 >= self.cells.len) coord.x else coord.x + 1;
        const startY = if (coord.y == 0) 0 else coord.y - 1;
        const endY = if (coord.y + 1 >= self.cells[0].len) coord.y else coord.y + 1;

        // std.debug.print("Searching cells from ({}, {}) to ({}, {})\n", .{ startX, startY, endX, endY });

        for (startX..endX + 1) |i| {
            for (startY..endY + 1) |j| {
                if (i < self.cells.len and j < self.cells[i].len) {
                    for (self.cells[i][j].entities.items) |entity| {
                        if (count < main.entityCollisionLimit) {
                            nearbyEntities[count] = entity;
                            count += 1;
                        } else {
                            return error.TooManyEntities; // Handle overflow case
                        }
                    }
                }
            }
        }
        // std.debug.print("Found {} entities nearby.\n", .{count});
        // std.debug.print("Total units in the world: {}.\n", .{units.items.len});
        return nearbyEntities[0..count];
    }
};

pub fn entityCollision(x: i32, y: i32, width: i32, height: i32, currentEntity: ?*Entity) !bool {
    const halfWidth = @divTrunc(width, 2);
    const halfHeight = @divTrunc(height, 2);

    const left = x - halfWidth;
    const right = x + halfWidth;
    const top = y - halfHeight;
    const bottom = y + halfHeight;

    const nearbyEntities = try main.gameGrid.getNearbyEntities(x, y);

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
