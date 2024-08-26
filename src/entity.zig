const std: type = @import("std");
const rl = @import("raylib");
const main = @import("main.zig");
const u = @import("utils.zig");

// Setting up entities
pub var players: std.ArrayList(*Player) = undefined;
pub var units: std.ArrayList(*Unit) = undefined;
pub var structures: std.ArrayList(*Structure) = undefined;
pub var resources: std.ArrayList(*Resource) = undefined;

pub const Kind = enum {
    Player,
    Unit,
    Structure,
    Resource,
};

pub const Entity = struct {
    kind: Kind,
    ref: union(Kind) { // Stores pointer to the actual attributes
        Player: *Player,
        Unit: *Unit,
        Structure: *Structure,
        Resource: *Resource,
    },

    pub fn width(self: *Entity) u16 {
        return switch (self.kind) {
            Kind.Player => self.ref.Player.width,
            Kind.Unit => self.ref.Unit.width(),
            Kind.Structure => self.ref.Structure.width(),
            Kind.Resource => self.ref.Resource.width(),
        };
    }

    pub fn height(self: *Entity) u16 {
        return switch (self.kind) {
            Kind.Player => self.ref.Player.height,
            Kind.Unit => self.ref.Unit.height(),
            Kind.Structure => self.ref.Structure.height(),
            Kind.Resource => self.ref.Resource.height(),
        };
    }

    pub fn x(self: *Entity) u16 {
        return switch (self.kind) {
            Kind.Player => self.ref.Player.x,
            Kind.Unit => self.ref.Unit.x,
            Kind.Structure => self.ref.Structure.x,
            Kind.Resource => self.ref.Resource.x,
        };
    }

    pub fn y(self: *Entity) u16 {
        return switch (self.kind) {
            Kind.Player => self.ref.Player.y,
            Kind.Unit => self.ref.Unit.y,
            Kind.Structure => self.ref.Structure.y,
            Kind.Resource => self.ref.Resource.y,
        };
    }

    pub fn life(self: *Entity) i16 {
        return switch (self.kind) {
            Kind.Player => self.ref.Player.life,
            Kind.Unit => self.ref.Unit.life,
            Kind.Structure => self.ref.Structure.life,
            Kind.Resource => self.ref.Resource.capacity, // Counting capacity as life for resource
        };
    }

    pub fn setLife(self: *Entity, new_life: i16) void {
        switch (self.kind) {
            Kind.Player => self.ref.Player.life = new_life,
            Kind.Unit => self.ref.Unit.life = new_life,
            Kind.Structure => self.ref.Structure.life = new_life,
            Kind.Resource => self.ref.Resource.capacity = new_life, // Counting capacity as life for resource
        }
    }

    pub fn color(self: *Entity, alpha: f32) rl.Color {
        return switch (self.kind) {
            Kind.Player => u.idToColor(self.ref.Player.id, alpha),
            Kind.Unit => u.idToColor(self.ref.Unit.owner, alpha),
            Kind.Structure => u.idToColor(self.ref.Structure.owner, alpha),
            Kind.Resource => u.opacity(rl.Color.dark_brown, alpha),
        };
    }

    pub fn owner(self: *Entity) u8 {
        return switch (self.kind) {
            Kind.Player => self.ref.Player.id,
            Kind.Unit => self.ref.Unit.owner,
            Kind.Structure => self.ref.Structure.owner,
            Kind.Resource => 0, // Let's say resource owner is 0 (neutral)
        };
    }

    pub fn speed(self: *Entity) f16 {
        return switch (self.kind) {
            Kind.Player => self.ref.Player.speed,
            Kind.Unit => self.ref.Unit.speed(),
            else => 0,
        };
    }

    pub fn inRangeOf(self: *Entity, target: *Entity, range: f32) bool {
        return u.isInRange(self, target, range);
    }

    pub fn reach(self: *Entity) u16 {
        return u.reachFromRect(self.width(), self.height());
    }

    /// Returns the bigger of two entities, or null if same size.
    pub fn bigger(e1: *Entity, e2: *Entity) ?*Entity {
        switch (u.bigger(e1.width(), e1.height(), e2.width(), e2.height())) {
            0 => return e1,
            1 => return e2,
            2, 3 => return null,
        }
    }

    pub fn isTouching(self: *Entity, other: *Entity) bool {
        const delta = u.deltaXy(self.x(), self.y(), other.x(), other.y());

        const buffer = u.asU16(f16, @round(self.speed()));

        return (@abs(delta[0]) <= (self.width() / 2) + (other.width() / 2) + buffer) and
            (@abs(delta[1]) <= (self.height() / 2) + (other.height() / 2) + buffer);
    }

    pub fn isAvailableResource(entity: *Entity) bool {
        if (entity.kind == Kind.Resource) return entity.ref.Resource.state != Resource.State.Depleted;
        return false;
    }

    pub fn isOwnStructure(self: *Entity, other: *Entity) bool {
        if (other.kind == Kind.Structure) return other.ref.Structure.owner == self.owner();
        return false;
    }

    pub fn isEnemy(self: *Entity, other: *Entity) bool {
        return switch (other.kind) {
            Kind.Unit => other.ref.Unit.owner != self.owner(),
            Kind.Structure => other.ref.Structure.owner != self.owner(),
            Kind.Player => other.ref.Player.id != self.owner(),
            else => false, // Resources are not enemies
        };
    }

    pub fn playerFromId(id: u8) ?*Player {
        for (players.items) |player| {
            if (player.id == id) return player;
        }
        return null;
    }
};

// Player //
//----------------------------------------------------------------------------------
pub const Player = struct {
    entity: *Entity,
    id: u8,
    life: i16,
    width: u16,
    height: u16,
    x: u16,
    y: u16,
    speed: f16 = 5,
    state: State,
    local: bool = false,

    pub const State = enum {
        Default,
        Dead,
    };

    pub fn draw(self: Player, alpha: f32) void {
        if (main.Player.selected == self.entity) { // If selected by local player, draws circle
            u.drawCircle(self.x, self.y, u.Grid.cell_half, self.entity.color(alpha * 0.125));
        }
        u.drawPlayer(self.x, self.y, self.width, self.height, self.entity.color(alpha));
    }

    pub fn update(self: *Player) anyerror!void {
        if (self.local) { // Local player
            if (main.Player.changed_x != null or main.Player.changed_y != null) { // Input processed in main
                try self.executeMovement(main.Player.changed_x, main.Player.changed_y, self.speed);
                main.Player.changed_x = null;
                main.Player.changed_y = null;
            }
            if (main.Player.build_order != null) { // Input processed in main
                main.executeBuild(main.Player.build_order.?);
                main.Player.build_order = null;
            }
        } else { // If AI or remote player
            // Check if remote or AI here, for now only AI
            main.EnemyPlayerAI.fetchAction(self, main.World.tick_number);
        }
        if (self.life <= 0) self.lose();
    }

    pub fn executeMovement(self: *Player, changed_x: ?u16, changed_y: ?u16, speed: f32) !void {
        const old_x = self.x;
        const old_y = self.y;
        var obstacleX: ?*Entity = null;
        var obstacleY: ?*Entity = null;
        const delta = u.deltaXy(self.x, self.y, changed_x orelse self.x, changed_y orelse self.y);
        const angle = u.deltaToAngle(delta[0], delta[1]);
        // const deltaXy = u.deltaXy(old_x, old_y, new_x orelse old_x, new_y orelse old_y);
        // std.debug.print("Player movement direction: {}. Delta to angle: {}. Angle from dir: {}. Vector to delta: {any}.\n", .{ self.direction, @as(i64, @intFromFloat(u.deltaToAngle(deltaXy[0], deltaXy[1]))), u.angleFromDir(self.direction), u.vectorToDelta(u.deltaToAngle(deltaXy[0], deltaXy[1]), speed) });

        // Gets potential obstacle entities on both axes
        if (changed_x != null) obstacleX = main.World.grid.collidesWith(changed_x.?, self.y, self.width, self.height, self.entity) catch null;
        if (changed_y != null) obstacleY = main.World.grid.collidesWith(self.x, changed_y.?, self.width, self.height, self.entity) catch null;

        if (changed_x != null and changed_y != null) { // Executes diagonal movement
            const diagonal_obstacle = main.World.grid.collidesWith(changed_x.?, changed_y.?, self.width, self.height, self.entity) catch null;
            if (diagonal_obstacle == null) {
                self.x = changed_x.?;
                self.y = changed_y.?;
            } else {
                if (obstacleX == null) self.x = changed_x.?;
                if (obstacleY == null) self.y = changed_y.?;

                if (obstacleX != null and obstacleX.?.kind == Kind.Unit) handleHorizontalCollision(self, old_x, changed_x.?, speed, angle, obstacleX.?);
                if (obstacleY != null and obstacleY.?.kind == Kind.Unit) handleVerticalCollision(self, old_y, changed_y.?, speed, angle, obstacleY.?);
            }
        } else if (changed_x != null) { // Executes horizontal movement
            if (obstacleX == null) {
                self.x = changed_x.?;
            } else if (obstacleX.?.kind == Kind.Unit) { // If unit obstacle, try horizontal push
                handleHorizontalCollision(self, old_x, changed_x.?, speed, angle, obstacleX.?);
            }
        } else if (changed_y != null) { // Executes vertical movement
            if (obstacleY == null) {
                self.y = changed_y.?;
            } else if (obstacleY.?.kind == Kind.Unit) { // If unit collider, try vertical push
                handleVerticalCollision(self, old_y, changed_y.?, speed, angle, obstacleY.?);
            }
        }

        // If new movement, updates game grid
        if ((changed_x != null and changed_x.? != old_x) or (changed_y != null and changed_y.? != old_y)) {
            main.World.grid.updateCellMembership(self.entity, old_x, old_y);
        }
    }

    fn handleHorizontalCollision(self: *Player, old_x: u16, new_x: u16, speed: f32, angle: f32, obstacle: *Entity) void {
        const resistance = 0.1; // maybe depend on size relation
        const force = (1.0 - resistance);
        const difference = @as(f64, @floatFromInt(@as(i32, new_x) - @as(i32, old_x)));
        var pushed_x = u.asU16(f64, u.asF64(u16, old_x) + @round(difference * force));
        var second_obstacle: ?*Entity = null;

        // Pushes obstacle, and checks whether push was unhindered, or if pushed obstacle in turn ran into a further obstacle
        const push_distance = obstacle.ref.Unit.pushed(angle, speed * force);
        //std.debug.print("Pushing horizontally, angle: {}, distance: {}", .{ angle, speed * force });
        if (push_distance >= speed * force) {
            second_obstacle = main.World.grid.collidesWith(pushed_x, self.y, self.width, self.height, self.entity) catch null;
        } else {
            pushed_x = @as(u16, @intCast(@as(i32, old_x) + @as(i32, @intFromFloat(push_distance)))); // Moves effective push distance and re-checks collision
            second_obstacle = main.World.grid.collidesWith(pushed_x, self.y, self.width, self.height, self.entity) catch null;
        }
        //std.debug.print("self.x was {}, pushed x now: {}. but second obstacle? {any}\n", .{ self.x, pushed_x, second_obstacle });
        if (second_obstacle == null) self.x = pushed_x; // If no collision now, repositions x
    }

    fn handleVerticalCollision(self: *Player, old_y: u16, new_y: u16, speed: f32, angle: f32, obstacle: *Entity) void {
        const resistance = 0.1; // maybe depend on size relation
        const force = (1.0 - resistance);
        const difference = @as(f64, @floatFromInt(@as(i32, new_y) - @as(i32, old_y)));
        var pushed_y = u.asU16(f64, u.asF64(u16, old_y) + @round(difference * force));
        var second_obstacle: ?*Entity = null;

        // Pushes obstacle, and checks whether push was unhindered, or if pushed obstacle in turn ran into a further obstacle
        const push_distance = obstacle.ref.Unit.pushed(angle, speed * force);
        //std.debug.print("Pushing vertically, angle: {}, distance: {}\n", .{ angle, speed * force });
        if (push_distance >= speed * force) {
            second_obstacle = main.World.grid.collidesWith(self.x, pushed_y, self.width, self.height, self.entity) catch null;
        } else {
            pushed_y = @as(u16, @intCast(@as(i32, old_y) + @as(i32, @intFromFloat(push_distance)))); // Moves effective push distance and re-checks collision
            second_obstacle = main.World.grid.collidesWith(self.x, pushed_y, self.width, self.height, self.entity) catch null;
        }
        //std.debug.print("self.y was {}, pushed y now: {}. but second obstacle? {any}\n", .{ self.y, pushed_y, second_obstacle });
        if (second_obstacle == null) self.y = pushed_y; // If no collision now, repositions x
    }

    pub fn createLocal(x: u16, y: u16, id: u8) !*Player {
        const entity = try main.World.grid.allocator.create(Entity); // Allocate memory for the parent entity
        const player = try main.World.grid.allocator.create(Player); // Allocate memory for Player and get a pointer

        player.* = Player{
            .entity = entity,
            .id = id,
            .life = 10000,
            .x = x,
            .y = y,
            .width = 100,
            .height = 100,
            .speed = 5,
            .state = State.Default,
            .local = true,
        };
        entity.* = Entity{
            .kind = Kind.Player,
            .ref = .{ .Player = player },
        };

        std.debug.print("Created local player at ({}, {}) with entity pointer {}\n", .{ x, y, @intFromPtr(entity) });
        try main.World.grid.addToCell(entity, null, null);
        return player;
    }

    pub fn createRemote(x: u16, y: u16, id: u8) !*Player {
        const entity = try main.World.grid.allocator.create(Entity); // Allocate memory for the parent entity
        const player = try main.World.grid.allocator.create(Player); // Allocate memory for Player and get a pointer

        player.* = Player{
            .entity = entity,
            .id = id,
            .life = 10000,
            .x = x,
            .y = y,
            .width = 100,
            .height = 100,
            .speed = 5,
            .state = State.Default,
            .local = false,
        };
        entity.* = Entity{
            .kind = Kind.Player,
            .ref = .{ .Player = player },
        };

        std.debug.print("Created remote player at ({}, {}) with entity pointer {}\n", .{ x, y, @intFromPtr(entity) });
        try main.World.grid.addToCell(entity, null, null);
        return player;
    }

    pub fn lose(self: *Player) void {
        // effect here
        self.state = State.Dead;
    }

    pub fn remove(self: *Player) !void {
        std.debug.print("Attempting to remove player: {}", .{self});

        if (self.local == true) {
            main.Config.game_active = false;
            std.debug.print("\n\nYou lost! Exiting game, better luck next time.\n\n", .{});
        } else { // Goes through owned structures/units and converts owner to id 0 (neutral)
            for (structures.items) |structure| {
                if (structure.owner == self.id) structure.owner = 0;
            }
            for (units.items) |unit| {
                if (unit.owner == self.id) unit.owner = 0;
            }
        }

        try main.World.grid.removeFromCell(self.entity, null, null); // Removes entity from grid
        try main.World.grid.removeFromAllSections(self.entity);
        try u.findAndSwapRemove(Player, &players, self); // Removes unit from the units collection
        for (players.items) |p| {
            std.debug.assert(p != self); // For debugging, player must be removed at this point
        }
        //self.model.destroy(main.World.grid.allocator); // Deallocates memory for the model
        main.World.grid.allocator.destroy(self.entity); // Deallocates memory for the Entity
        main.World.grid.allocator.destroy(self); // Deallocates memory for the Player
    }
};

// Unit
//----------------------------------------------------------------------------------
pub const Unit = struct {
    entity: *Entity,
    class: u8,
    owner: u8,
    x: u16,
    y: u16,
    life: i16,
    target: u.Circle,
    last_step: u.Point,
    cached_cellsigns: [9]u32, // Last known cellsigns of relevant cells
    model: *u.Model,
    state: State,
    projectiles: *std.ArrayList(*Projectile),

    pub const State = enum {
        Default,
        Attacking,
        Incapacitated,
        Carrying,
        Dead,
    };

    pub fn draw(self: *Unit, alpha: f32) void {
        if (self.state == State.Dead) return;
        // Draws model
        u.drawModel(self.model, self.width(), self.height(), self.entity.color(alpha), self.entity.color(alpha));

        //if (self.class == 0) { // Testing model for class 0, but expand to all
        //    if (self.state == State.Carrying) {
        //        u.drawModel(self.model, self.width(), self.height(), self.entity.color(alpha), self.entity.color(alpha));
        //    } else { // change model if carrying
        //        u.drawModel(self.model, self.width(), self.height(), self.entity.color(alpha), self.entity.color(alpha));
        //    }
        //} else { // Fallback to the previous method for other classes
        //    u.drawEntityInterpolated(self.x, self.y, self.width(), self.height(), self.entity.color(alpha), self.last_step, self.life);
        //}
        // If selected by player, draws target circumference with half alpha
        if (main.Player.selected == self.entity) {
            u.drawCircumference(self.target, self.entity.color(alpha / 2));
        }

        u.drawLifeInterpolated(self.x, self.y, preset(self.class).width, self.life, preset(self.class).life, self.last_step, self.life);

        // Draws projectiles with same alpha
        for (self.projectiles.items) |projectile| {
            projectile.draw(alpha);
        }
    }

    pub fn update(self: *Unit) !void {
        if (self.life <= 0) { // If dead, sets HP to min to flag for removal, and skips update
            try self.die(null);
            return;
        }

        // Updating model
        const factor = u.Interpolation.getFactor(self.life, main.World.MOVEMENT_DIVISIONS);
        self.model.updateRigidBodyInterpolated(0, u.Vector.fromPoint(self.last_step), u.Vector.fromCoords(self.x, self.y), factor);

        // Updating movement/action (every 10 ticks)
        if (main.moveDivision(self.life)) {
            self.last_step = u.Point.at(self.x, self.y); // Sets last_step to current position

            // Every attackrate * 10 ticks (unless carrying)
            if (main.moveDivMultiple(self.life, preset(self.class).attackrate) and self.state != State.Carrying) {
                if (self.state == State.Attacking) self.state = State.Default; // Clears attacking state
                if (self.getAttackTarget()) |target| {
                    if (try self.attack(target)) {
                        // Successfully launched projectile
                        self.state = State.Attacking; // Sets attacking state, pausing movement
                    }
                }
            }

            if (self.state != State.Attacking) { // If attacked, no move
                const step = self.getStep(); // Generates the next movement step
                try self.move(step.x, step.y); // Tries to execute the step, may fail/adjust due to collision
            }
            if (self.state == State.Incapacitated) self.state = State.Default; // If incapacitated, resets state
        }

        // Updating projectiles, from last to first, after all other logic
        var i: usize = self.projectiles.items.len;
        while (i > 0) {
            i -= 1;
            const projectile = self.projectiles.items[i];
            if (projectile.life <= 0) { // Clears up dead projectiles
                _ = self.projectiles.swapRemove(i);
                main.World.grid.allocator.destroy(projectile);
                continue;
            }
            projectile.update(); // Updates the projectile
        }

        // If incapacitated, resets last_step every frame to keep interpolation updated
        if (self.state == State.Incapacitated) self.last_step = u.Point.at(self.x, self.y);
        self.life -= 1;
    }

    /// Searches for collision at `new_x`,`new_y`. If no obstacle is found, sets position to `x`, `y`. If obstacle is found, tries moving along edge.
    fn move(self: *Unit, new_x: u16, new_y: u16) !void {
        const old_x = self.x;
        const old_y = self.y;

        if (self.state == State.Incapacitated) return;

        // If step is out of bounds, clamps to map if needed, and retargets
        if (!u.isInMap(new_x, new_y, self.width(), self.height())) {
            if (!u.isInMap(old_x, old_y, self.width(), self.height())) {
                const clamped_x = u.mapClampX(@as(i16, @intCast(new_x)), self.width());
                const clamped_y = u.mapClampY(@as(i16, @intCast(new_y)), self.height());
                _ = self.tryMove(clamped_x, clamped_y, old_x, old_y);
            }
            _ = self.retarget();
            return;
        }

        if (!self.tryMove(new_x, new_y, old_x, old_y)) { // Tries executing regular move
            _ = self.moveAlongAxis(new_x, new_y, old_x, old_y); // If collided, tries moving along either axis
        }

        if (old_x == self.x and old_y == self.y) { // If no change after moving, retargets
            if (main.moveDivMultiple(self.life, 2)) { // Alternating between random point and trying to head towards player again
                self.target = u.Circle.at(offsetFromPosition(self.last_step), u.Subcell.size); // Random nearby offset

            } else { // Tries heading towards player/resource again
                if (self.class != 0) { // Non-gatherers
                    self.target = findTarget(self.owner, self.last_step, self.entity.reach());
                }
            }
            return;
        }
    }

    /// Searches for collision at `new_x`,`new_y`. If unhindered, executes the movement, updates the grid, and returns `true`. If hindered, returns `false`.
    fn tryMove(self: *Unit, new_x: u16, new_y: u16, old_x: u16, old_y: u16) bool {
        //std.debug.print("Entities list retrieved: length = {any}, address = {}\n", .{ entities.?.items.len, @intFromPtr(entities) });
        const collision = self.checkCollision(new_x, new_y);
        if (collision == null) { // No obstacle, move
            self.x = new_x;
            self.y = new_y;
            main.World.grid.updateCellMembership(self.entity, old_x, old_y);
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
        const entities = main.World.grid.sectionEntities(u.Grid.x(x), u.Grid.y(y));
        if (entities != null) {
            const half_width = @divTrunc(self.width(), 2);
            const half_height = @divTrunc(self.height(), 2);
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
        self.state = State.Incapacitated; // Incapacitated while pushed
        //std.debug.print("Pushed towards angle {}.\n", .{angle});
        if (!u.isInMap(new_x, new_y, self.width(), self.height())) return distance;
        var moved_distance: f32 = distance;

        // Checking whether pushed unit in turn collides with another obstacle
        const obstacle = main.World.grid.collidesWith(new_x, new_y, self.width(), self.height(), self.entity) catch null;
        if (obstacle == null) {
            self.x = new_x;
            self.y = new_y;
            main.World.grid.updateCellMembership(self.entity, old_x, old_y);
        } else if (obstacle.?.kind == Kind.Unit) { // Pushed unit collides with another unit
            const obstacle_unit = obstacle.?.ref.Unit;
            //std.debug.print("Pushee collided with a unit: {}\n", .{obstacle_unit});

            // Checks that obstacle_unit isn't already being pushed
            if (obstacle_unit.state != State.Incapacitated) {
                moved_distance = moved_distance / 2; // Halves pushing distance for each additional obstacle
            } else {
                moved_distance = pushed(obstacle_unit, angle, @min(distance, distance * u.sizeFactor(self.width(), self.height(), obstacle_unit.width(), obstacle_unit.height())));
                const push_delta_xy = u.vectorToDelta(angle, moved_distance);
                const push_new_x = @as(u16, @intFromFloat(@as(f32, @floatFromInt(self.x)) + push_delta_xy[0]));
                const push_new_y = @as(u16, @intFromFloat(@as(f32, @floatFromInt(self.y)) + push_delta_xy[1]));

                self.move(push_new_x, push_new_y) catch return 0; // Re-checks for collision and updates grid here
            }
        } else {
            //std.debug.print("Pushee collided with a non-unit: {}\n", .{obstacle.?});
        }

        // Reset dimensions to flag pushability here, may want to reset State.Incapacitated here now?
        return moved_distance; // Returns effective moved distance
    }

    fn calculatePushPosition(self: *Unit, angle: f32, distance: f32) [2]u16 {
        const delta_xy = u.vectorToDelta(angle, distance);
        const new_x_float: f32 = @round(@as(f32, @floatFromInt(self.x)) + delta_xy[0]);
        const new_y_float: f32 = @round(@as(f32, @floatFromInt(self.y)) + delta_xy[1]);

        const new_x = @as(u16, @intFromFloat(u.u16Clamp(f32, new_x_float)));
        const new_y = @as(u16, @intFromFloat(u.u16Clamp(f32, new_y_float)));

        return [2]u16{ new_x, new_y };
    }

    /// Sets unit's target destination to closest target to the previous. Returns `true` if target has changed, returns `false` if target remains the same.
    pub fn retarget(self: *Unit) bool {
        const prev_target = self.target;

        self.target = findTarget(self.owner, self.target.center, self.entity.reach()); // Closest enemy player to its target, or random nearby point
        return prev_target.center.x != self.target.center.x or prev_target.center.y != self.target.center.y;
    }

    /// Returns the position of the closest enemy player. Returns random nearby point if none.
    pub fn findTarget(owner: u8, position: u.Point, reach: u16) u.Circle {
        var closest_player: ?*Player = null;
        var closest_distance: f32 = std.math.inf(f32);

        for (players.items) |player| {
            if (player.id == owner) continue;
            const distance = u.fastSqrt(u.asF32(u32, u.distanceSquared(position, u.Point.at(player.x, player.y))));
            if (closest_player == undefined or distance < closest_distance) {
                closest_player = player;
                closest_distance = distance;
            }
        }

        if (closest_player != null) return u.Circle.aroundEntity(closest_player.?.entity, reach);
        return u.Circle.at(offsetFromPosition(position), u.Subcell.size); // Returns random nearby circle
    }

    /// Returns the position of the closest non-depleted `Resource`. Returns random nearby point if none.
    pub fn findResource(position: u.Point, reach: u16) u.Circle {
        var closest_resource: ?*Resource = null;
        var closest_distance: f32 = std.math.inf(f32);

        for (resources.items) |resource| {
            if (resource.state == Resource.State.Depleted) continue;
            const distance = u.fastSqrt(u.asF32(u32, u.distanceSquared(position, u.Point.at(resource.x, resource.y))));
            if (closest_resource == undefined or distance < closest_distance) {
                closest_resource = resource;
                closest_distance = distance;
            }
        }

        if (closest_resource != null) return u.Circle.aroundEntity(closest_resource.?.entity, reach);
        return u.Circle.at(offsetFromPosition(position), u.Subcell.size); // Returns random nearby circle

    }

    /// Returns a world-randomized `Point` within half a cell's distance from `position`.
    fn offsetFromPosition(position: u.Point) u.Point {
        const x: i16 = @as(i16, @intCast(position.x)) + (u.randomI16(u.Grid.cell_half) - u.Grid.cell_half / 2);
        const y: i16 = @as(i16, @intCast(position.y)) + (u.randomI16(u.Grid.cell_half) - u.Grid.cell_half / 2);
        return u.Point.at(u.mapClampX(x, u.Grid.cell_half), u.mapClampX(y, u.Grid.cell_half));
    }

    /// Calculates and returns the unit's immediate move based on its current `target` and `class`.
    fn getStep(self: *Unit) u.Point {

        // Get the current position of unit and overall distance to target
        const current = u.Point.at(self.x, self.y);

        // If incapacitated, remain in place for tick
        if (self.state == State.Incapacitated) {
            return current;
        }

        var distance_squared = u.distanceSquared(current, self.target.center);

        // Check if within a cell's distance of target
        if (distance_squared <= u.Grid.cell_size_squared) {
            // std.debug.print("Within target cell at {},{}. Target is at {},{}.\n", .{ self.x, self.y, self.target.x, self.target.y });
            const dx = @as(i32, @intCast(current.x)) - @as(i32, @intCast(self.target.center.x));
            const dy = @as(i32, @intCast(current.y)) - @as(i32, @intCast(self.target.center.y));

            // If within perimeter of the target point, retarget
            if (self.target.contains(u.Point.at(self.x, self.y))) {
                if (self.class != 0) return current; // Non-gatherers, pause to trigger retarget

                // Gatherers, check whether pick up or deliver
                if (self.state != State.Carrying) { // Gatherers not carrying
                    //std.debug.print("Not carrying, will check for resource to target.\n", .{});
                    const resource = u.concentricSearch(&main.World.grid, self.last_step, Entity.isAvailableResource);
                    if (resource) |r| {
                        if (self.entity.isTouching(r)) { // Is at resource, drain it and set carry state
                            //std.debug.print("Is touching resource, will decrease its capacity and set own state to Carrying.\n", .{});
                            r.ref.Resource.capacity -= 1;
                            self.state = State.Carrying;
                        } else {
                            //std.debug.print("Is not touching resource, will set it to target.\n", .{});
                            self.target = u.Circle.aroundEntity(r, self.entity.reach()); // Not at resource, sets to target
                        }
                    } else { // Found no resource, so targets random nearby position
                        //std.debug.print("Found no resource,  so will target random nearby position.\n", .{});
                        self.target = u.Circle.at(offsetFromPosition(self.last_step), u.Subcell.size);
                    }
                } else { // Gatherers already carrying
                    //std.debug.print("Am carrying, will check for own building nearby.\n", .{});
                    const own_building = u.concentricRelationalSearch(&main.World.grid, self.entity, Entity.isOwnStructure);
                    if (own_building) |b| {
                        if (self.entity.isTouching(b)) { // Is at building, increases its capacity by 1
                            //std.debug.print("Is touching building, will increase its capacity and set own state to Default.\n", .{});
                            b.ref.Structure.capacity += 1;
                            self.state = State.Default;
                        } else {
                            //std.debug.print("Is not touching building, will set it to target.\n", .{});
                            self.target = u.Circle.aroundEntity(b, self.entity.reach()); // Not at building, sets to target
                        }
                    } else { // Found no own building, so targets random nearby position
                        //std.debug.print("Found no building,  so will target random nearby position.\n", .{});
                        self.target = u.Circle.at(offsetFromPosition(self.last_step), u.Subcell.size);
                    }
                }
                distance_squared = u.distanceSquared(current, self.target.center); // Recalculates
            }

            // Otherwise go directly towards the target
            const distance = u.fastSqrt(u.asF32(u32, distance_squared)); // Computes actual distance to ensure arrival
            const angle = u.deltaToAngle(dx, dy);
            const magnitude = @min(self.speed(), distance);
            const vector = u.vectorToDelta(angle, magnitude);
            return u.deltaPoint(self.x, self.y, vector[0], vector[1]);
            //
        } else { // If farther than a subcell away, move by waypoints towards the target

            const waypoint = u.Waypoint.closestTowards(current, self.target.center, distance_squared, self.last_step);
            const magnitude = u.adjustToDistance(current, waypoint, self.speed(), self.speed());
            // Get the offset from the upcoming waypoint
            const dx = @as(i32, @intCast(current.x)) - @as(i32, @intCast(waypoint.x));
            const dy = @as(i32, @intCast(current.y)) - @as(i32, @intCast(waypoint.y));

            // Translates it into vector to get the new step
            const angle = u.deltaToAngle(dx, dy);
            const vector = u.vectorToDelta(angle, magnitude);
            return u.deltaPoint(self.x, self.y, vector[0], vector[1]);
        }
    }

    /// Does a concentric search for an enemy.
    fn getAttackTarget(self: *Unit) ?*Entity {
        const found_entity = u.concentricRelationalSearch(&main.World.grid, self.entity, Entity.isEnemy);
        if (found_entity != null and self.entity.inRangeOf(found_entity.?, range(self))) return found_entity;
        return null;
    }

    /// Does a concentric search for a non-depleted resource nearby.
    fn getResourceTarget(self: *Unit) ?*Entity {
        const found_entity = u.concentricSearch(&main.World.grid, self.last_step, Entity.isAvailableResource);
        if (found_entity != null and self.entity.inRangeOf(found_entity.?, u.Subcell.size + 10)) return found_entity;
        return null;
    }

    fn attack(self: *Unit, target: *Entity) !bool {
        const projectile = Projectile.launch(self.entity, self.class, target) catch |err| {
            std.debug.print("Attack failed: {}.\n", .{err});
            return false;
        };
        try self.projectiles.append(projectile);
        return true;
    }

    pub fn create(owner: u8, x: u16, y: u16, class: u8) !*Unit {
        const entity = try main.World.grid.allocator.create(Entity); // Memory for the parent entity
        const unit = try main.World.grid.allocator.create(Unit); // Memory for unit
        const projectiles = try main.World.grid.allocator.create(std.ArrayList(*Projectile)); // Memory for projectiles
        projectiles.* = std.ArrayList(*Projectile).init(main.World.grid.allocator.*);
        const from_class = Unit.preset(class);
        const start_point = u.Point.at(x, y);

        var model: *u.Model = undefined;

        // Determine if this unit should have legs
        model = try u.Model.createChain(main.World.grid.allocator, 3 + class, start_point, 12 + u.asF32(u8, class));
        if (class > 0) {
            try u.Legs.attach(main.World.grid.allocator, model, 4, 10.0); // Assuming 4 legs with 10.0 length
        }

        unit.* = Unit{
            .entity = entity,
            .owner = owner,
            .class = class,
            .life = from_class.life,
            .model = model,
            .x = x,
            .y = y,
            .target = if (class == 0) findResource(start_point, u.reachFromRect(from_class.width, from_class.height)) else findTarget(owner, start_point, u.reachFromRect(from_class.width, from_class.height)),
            .last_step = start_point,
            .cached_cellsigns = [_]u32{0} ** 9,
            .projectiles = projectiles,
            .state = State.Default,
        };

        entity.* = Entity{
            .kind = Kind.Unit,
            .ref = .{ .Unit = unit }, // Store the pointer to the Unit
        };

        try main.World.grid.addToCell(entity, null, null);
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
        self.state = State.Dead;
    }

    pub fn remove(self: *Unit) !void {
        try main.World.grid.removeFromCell(self.entity, null, null); // Removes entity from grid
        try main.World.grid.removeFromAllSections(self.entity);
        try u.findAndSwapRemove(Unit, &units, self); // Removes unit from the units collection
        for (units.items) |unit| {
            std.debug.assert(unit != self); // For debugging, unit must be removed at this point
        }
        self.projectiles.deinit(); // Deinitializes the list of projectiles
        main.World.grid.allocator.destroy(self.projectiles); // Deallocate the memory for the ArrayList itself
        self.model.destroy(main.World.grid.allocator); // Deallocates memory for the model
        main.World.grid.allocator.destroy(self.entity); // Deallocates memory for the Entity
        main.World.grid.allocator.destroy(self); // Deallocates memory for the Unit
    }

    /// `Unit` property template fields determined by `class`.
    pub const Properties = struct {
        speed: f16,
        width: u16,
        height: u16,
        life: i16,
        range: f32,
        attackrate: u8,
    };

    /// Returns a `Properties` template determined by `class`.
    pub fn preset(class: u8) Properties { // Would set model here as well
        return switch (class) {
            0 => Properties{ .speed = 1.5, .width = 20, .height = 20, .life = 6000, .range = 150, .attackrate = 6 },
            1 => Properties{ .speed = 1.75, .width = 25, .height = 25, .life = 8000, .range = 300, .attackrate = 5 },
            2 => Properties{ .speed = 1, .width = 45, .height = 45, .life = 10000, .range = 500, .attackrate = 12 },
            3 => Properties{ .speed = 2, .width = 35, .height = 35, .life = 7000, .range = 250, .attackrate = 8 },
            else => @panic("Invalid unit class"),
        };
    }

    pub fn hasLegs(self: *Unit) bool {
        return self.class > 0;
    }

    pub fn speed(self: *Unit) f16 {
        return Unit.preset(self.class).speed * main.World.MOVEMENT_DIVISIONS;
    }

    fn range(self: *Unit) f32 {
        return preset(self.class).range;
    }

    fn width(self: *Unit) u16 {
        return preset(self.class).height;
    }

    fn height(self: *Unit) u16 {
        return preset(self.class).height;
    }
};

// Structure
//----------------------------------------------------------------------------------
pub const Structure = struct {
    entity: *Entity,
    owner: u8,
    x: u16,
    y: u16,
    class: u8,
    life: i16,
    state: State,
    restitution: f16,
    capacity: i16,
    elapsed: u16 = 0,

    pub const State = enum {
        Default,
        Destroyed,
    };

    pub fn draw(self: *Structure, alpha: f32) void {
        if (self.state == State.Destroyed) return;
        u.drawEntity(self.x, self.y, self.width(), self.height(), self.entity.color(alpha));

        u.drawLife(self.x, self.y, preset(self.class).width, self.life, preset(self.class).life);
        u.drawCapacity(self.x, self.y, preset(self.class).width, preset(self.class).height, self.capacity, preset(self.class).capacity);
    }

    /// `Structure` property fields determined by `class`.
    pub const Properties = struct {
        width: u16,
        height: u16,
        life: i16,
        restitution: f16,
        capacity: i16,
    };

    /// Returns a `Properties` template determined by `class`.
    pub fn preset(class: u8) Properties {
        return switch (class) {
            0 => Properties{ .width = 150, .height = 150, .life = 12000, .restitution = 8.6, .capacity = 3 },
            1 => Properties{ .width = 100, .height = 100, .life = 8000, .restitution = 4.0, .capacity = 1 },
            2 => Properties{ .width = 200, .height = 200, .life = 14000, .restitution = 14.0, .capacity = 6 },
            3 => Properties{ .width = 150, .height = 150, .life = 9000, .restitution = 11.0, .capacity = 4 },
            else => @panic("Invalid structure class"),
        };
    }

    pub fn update(self: *Structure) void {
        self.elapsed += 1;
        const rest_ticks = u.ticksFromSecs(self.restitution);
        if (self.elapsed >= rest_ticks) {
            self.elapsed -= rest_ticks; // Subtracting interval accounts for possible overshoot
            if (self.capacity > 0) {
                if (self.spawnUnit()) |unit| {
                    _ = unit;
                    self.capacity = self.capacity - 1;
                } else |err| {
                    std.debug.print("Failed to spawn unit: {}. May want some sort of indication.\n", .{err});
                }
                if (self.capacity > 0) { // Overflow capacity transfer to connected buildings
                    const connected = u.findConnectedStructures(&main.World.grid, self) catch null;
                    if (connected) |buildings| {
                        for (buildings) |building| {
                            if (self.capacity > building.capacity) {
                                building.capacity += 1;
                                self.capacity -= 1;
                            }
                            if (self.capacity <= 0) break;
                        }
                    }
                }
            }
        }
        if (self.life <= 0) self.destroy();
    }

    pub fn spawnUnit(self: *Structure) !*Unit {
        const spawn_class = self.spawnClass();
        const spawn_point = self.spawnPoint(Unit.preset(spawn_class).width, Unit.preset(spawn_class).height) catch null;
        if (spawn_point) |sp| { // If spawn_point is not null, unwrap it
            const unit = try Unit.create(self.owner, sp[0], sp[1], spawn_class);
            try units.append(unit);
            return unit;
        }
        return error.NoAvailableSpawnPoint;
    }

    pub fn create(owner: u8, x: u16, y: u16, class: u8) !*Structure {
        const entity: *Entity = try main.World.grid.allocator.create(Entity);
        const structure: *Structure = try main.World.grid.allocator.create(Structure);
        const from_class = Structure.preset(class);

        structure.* = Structure{
            .entity = entity,
            .owner = owner,
            .class = class,
            .life = from_class.life,
            .state = State.Default,
            .restitution = from_class.restitution,
            .capacity = from_class.capacity,
            .x = x,
            .y = y,
        };
        entity.* = Entity{
            .kind = Kind.Structure,
            .ref = .{ .Structure = structure },
        };

        try main.World.grid.addToCell(entity, null, null);
        return structure;
    }

    pub fn construct(owner: u8, x: u16, y: u16, class: u8) ?*Structure {
        const collides = main.World.grid.collidesWith(x, y, preset(class).width, preset(class).height, null) catch return null;
        if (collides != null or !u.isInMap(x, y, preset(class).width, preset(class).height)) {
            return null;
        }
        const structure = Structure.create(owner, x, y, class) catch return null;
        structures.append(structure) catch return null;
        return structure;
    }

    pub fn destroy(self: *Structure) void {
        // Effect here
        self.state = State.Destroyed;
    }

    pub fn remove(self: *Structure) !void {
        try main.World.grid.removeFromCell(self.entity, null, null); // Removes entity from grid
        try main.World.grid.removeFromAllSections(self.entity);
        try u.findAndSwapRemove(Structure, &structures, self); // Removes unit from the units collection
        for (structures.items) |structure| {
            std.debug.assert(structure != self); // For debugging, structure must be removed at this point
        }
        //self.model.destroy(main.World.grid.allocator); // Deallocates memory for the model
        main.World.grid.allocator.destroy(self.entity); // Deallocates memory for the Entity
        main.World.grid.allocator.destroy(self); // Deallocates memory for the Structure
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
        u.shuffleArray(usize, &side_indices); // Shuffles indices to randomize check order

        const offset_x = @divTrunc(self.width(), 2) + @divTrunc(unit_width, 2);
        const offset_y = @divTrunc(self.height(), 2) + @divTrunc(unit_height, 2);

        // Checking side availability
        for (side_indices) |side_index| {
            var spawn_x: u16 = 0;
            var spawn_y: u16 = 0;

            switch (side_index) {
                0 => { // Bottom side
                    spawn_x = self.x;
                    spawn_y = if (self.y + offset_y < main.World.height) self.y + offset_y else self.y - offset_y;
                },
                1 => { // Left side
                    spawn_x = if (self.x >= offset_x) self.x - offset_x else self.x + offset_x;
                    spawn_y = self.y;
                },
                2 => { // Right side
                    spawn_x = if (self.x + offset_x < main.World.width) self.x + offset_x else self.x - offset_x;
                    spawn_y = self.y;
                },
                3 => { // Top side
                    spawn_x = self.x;
                    spawn_y = if (self.y >= offset_y) self.y - offset_y else self.y + offset_y;
                },
                else => @panic("Unrecognized side"),
            }
            // Check if the calculated spawn point is valid
            if (try main.World.grid.collidesWith(spawn_x, spawn_y, unit_width, unit_height, null) == null and u.isInMap(spawn_x, spawn_y, unit_width, unit_height)) {
                return [2]u16{ spawn_x, spawn_y };
            }
        }
        return error.NoValidSpawnPoint;
    }

    fn width(self: *Structure) u16 {
        return preset(self.class).height;
    }

    fn height(self: *Structure) u16 {
        return preset(self.class).height;
    }
};

// Resource
//----------------------------------------------------------------------------------
pub const Resource = struct {
    entity: *Entity,
    class: u8,
    state: State,
    x: u16,
    y: u16,
    capacity: i16,

    pub const State = enum {
        Default,
        Depleted,
    };

    pub fn draw(self: *Resource, alpha: f32) void {
        u.drawEntity(self.x, self.y, self.width(), self.height(), self.entity.color(alpha));
        // Draws capacity portion as life
        u.drawLife(self.x, self.y, preset(self.class).width, self.capacity, preset(self.class).capacity);
    }

    pub fn update(self: *Resource) void {
        if (self.capacity <= 0) self.state = State.Depleted;
    }

    /// `Structure` property fields determined by `class`.
    pub const Properties = struct {
        width: u16,
        height: u16,
        capacity: i16,
    };

    /// Returns a `Properties` template determined by `class`.
    pub fn preset(class: u8) Properties {
        return switch (class) {
            0 => Properties{ .width = u.Subcell.size, .height = u.Subcell.size, .capacity = 100 },
            1 => Properties{ .width = u.Subcell.size / 2, .height = u.Subcell.size / 2, .capacity = 1000 },
            2 => Properties{ .width = u.Subcell.size / 2, .height = u.Subcell.size / 2, .capacity = 40 },
            3 => Properties{ .width = u.Subcell.size / 4, .height = u.Subcell.size / 4, .capacity = 40 },
            else => @panic("Invalid structure class"),
        };
    }

    pub fn create(x: u16, y: u16, class: u8) !*Resource {
        const entity: *Entity = try main.World.grid.allocator.create(Entity);
        const resource: *Resource = try main.World.grid.allocator.create(Resource);
        const from_class = Resource.preset(class);

        resource.* = Resource{
            .entity = entity,
            .class = class,
            .state = State.Default,
            .capacity = from_class.capacity,
            .x = x,
            .y = y,
        };
        entity.* = Entity{
            .kind = Kind.Resource,
            .ref = .{ .Resource = resource },
        };

        try main.World.grid.addToCell(entity, null, null);
        return resource;
    }

    pub fn remove(self: *Resource) !void {
        try main.World.grid.removeFromCell(self.entity, null, null); // Removes entity from grid
        try main.World.grid.removeFromAllSections(self.entity);
        try u.findAndSwapRemove(Resource, &resources, self); // Removes resource from the units collection
        for (resources.items) |resource| {
            std.debug.assert(resource != self); // For debugging, resource must be removed at this point
        }
        main.World.grid.allocator.destroy(self.entity); // Deallocates memory for the Entity
        main.World.grid.allocator.destroy(self); // Deallocates memory for the Resource
    }

    fn width(self: *Resource) u16 {
        return preset(self.class).height;
    }

    fn height(self: *Resource) u16 {
        return preset(self.class).height;
    }
};

// Projectile
//----------------------------------------------------------------------------------
pub const Projectile = struct {
    class: u8,
    x: u16,
    y: u16,
    angle: f32,
    life: i16,
    targets: ?*std.ArrayList(*Entity), // Populated upon launch

    pub fn draw(self: *Projectile, alpha: f32) void {
        u.drawEntity(self.x, self.y, self.width(), self.height(), u.opacity(preset(self.class).color, alpha));
    }

    pub fn update(self: *Projectile) void {
        // Checks radius for targets, returns true if found
        if (self.checkImpact()) |target| {
            self.impact(target); // Deals damage and does effect
            return;
        }
        const delta = u.vectorToDelta(self.angle, self.speed());
        self.x = u.mapClampFloatX(u.asF32(u16, self.x) + delta[0], self.width());
        self.y = u.mapClampFloatY(u.asF32(u16, self.y) + delta[1], self.height());
        self.life -= 1;
    }

    /// `Projectile` property fields determined by `class`.
    pub const Properties = struct {
        width: u16 = 1,
        height: u16 = 1,
        life: i16,
        damage: i16,
        speed: f16,
        color: rl.Color,
    };

    /// Returns a `Properties` template determined by `class`.
    pub fn preset(class: u8) Properties {
        return switch (class) {
            0 => Properties{ .life = 40, .speed = 8, .color = rl.Color.sky_blue, .width = 4, .height = 4, .damage = 250 },
            1 => Properties{ .life = 56, .speed = 14, .color = rl.Color.blue, .width = 4, .height = 4, .damage = 750 },
            2 => Properties{ .life = 128, .speed = 6, .color = rl.Color.dark_blue, .width = 8, .height = 8, .damage = 2000 },
            3 => Properties{ .life = 72, .speed = 12, .color = rl.Color.violet, .width = 6, .height = 6, .damage = 1250 },
            else => @panic("Invalid projectile class"),
        };
    }

    /// Creates projectile launching from source towards target and returns it.
    pub fn launch(source: *Entity, class: u8, target: *Entity) !*Projectile {
        const projectile = try main.World.grid.allocator.create(Projectile); // Memory for projectile
        const angle = u.angleFromTo(source.x(), source.y(), target.x(), target.y());
        const from_class = preset(class);
        // Launching from correct side of the source
        const delta = u.angleToSquareOffset(angle, source.width() + from_class.width, source.height() + from_class.height);

        projectile.* = Projectile{
            .class = class,
            .x = delta.mapOffsetX(source.x()),
            .y = delta.mapOffsetY(source.y()),
            .life = from_class.life,
            .angle = angle,
            .targets = Grid.sectionEntities(&main.World.grid, u.Grid.x(source.x()), u.Grid.x(source.y())),
        };
        return projectile;
    }

    /// Loops the projectile's target list doing a bounding box check for colliding entities. Returns first target found, else null.
    fn checkImpact(self: *Projectile) ?*Entity {
        // Calculate the projectile's bounding box (may be overkill, but useful for larger projectiles)
        const left = if (self.x > @divTrunc(self.width(), 2)) self.x - @divTrunc(self.width(), 2) else 0;
        const right = self.x + @divTrunc(self.width(), 2);
        const top = if (self.y > @divTrunc(self.height(), 2)) self.y - @divTrunc(self.height(), 2) else 0;
        const bottom = self.y + @divTrunc(self.height(), 2);

        if (self.targets) |target_list| {
            for (target_list.items) |target| {
                if (target.kind == Kind.Resource) continue; // Don't impact resources
                const target_half_width = @divTrunc(target.width(), 2);
                const target_half_height = @divTrunc(target.height(), 2);
                const target_left = if (target.x() > target_half_width) target.x() - target_half_width else 0;
                const target_right = target.x() + target_half_width;
                const target_top = if (target.y() > target_half_height) target.y() - target_half_height else 0;
                const target_bottom = target.y() + target_half_height;

                // Check if the projectile's bounding box intersects with the target's bounding box
                if (right > target_left and left < target_right and bottom > target_top and top < target_bottom) {
                    //std.debug.print("Projectile (class {}) impacted with target at position ({}, {})\n", .{ self.class, target.x(), target.y() });
                    return target;
                }
            }
        }
        return null;
    }

    pub fn impact(self: *Projectile, target: *Entity) void {
        const damage = preset(self.class).damage;
        target.setLife(if (target.life() >= damage) target.life() - damage else 0);
        self.life -= 100; // Should be enough to kill projectile unless multi targets are wanted
        std.debug.print("Projectile (class {}) hit target {}!\n", .{ self.class, target });
    }

    fn width(self: *Projectile) u16 {
        return preset(self.class).height;
    }

    fn height(self: *Projectile) u16 {
        return preset(self.class).height;
    }

    fn speed(self: *Projectile) f16 {
        return preset(self.class).speed;
    }
};

// Map Geometry
//----------------------------------------------------------------------------------

pub const Grid = struct {
    allocator: *std.mem.Allocator,
    cells: std.hash_map.HashMap(u64, std.ArrayList(*Entity), u.SpatialHash.Context, 80) = undefined,
    cellsigns: []u32, // A slice into a contiguous block of memory
    entity_buffer: []*Entity, // Allocated once, rewritten each tick
    buffer_offset: usize, // Tracks the current usage of the buffer
    sections: []std.ArrayList(*Entity), // Array of dynamic lists of pointers to entities (each section is 3x3 around a given cell)
    columns: usize,
    rows: usize,

    const Cellsign = u32;

    pub fn init(self: *Grid, allocator: *std.mem.Allocator, columns: usize, rows: usize, buffer_size: usize) !void {
        self.allocator = allocator;
        self.cells = std.hash_map.HashMap(u64, std.ArrayList(*Entity), u.SpatialHash.Context, 80).init(allocator.*);

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
    pub fn sectionEntities(self: *Grid, x: usize, y: usize) ?*std.ArrayList(*Entity) {
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
        const neighbor_offsets = u.Grid.section();
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
                //std.debug.print("Entity {} removed from section {}. ", .{ @intFromPtr(entity), i });
                //std.debug.print("There are {} sections in total. Searched through {} items before entity was found.\n", .{ self.sections.len, count });
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
        const entities = try self.sectionSearch(@as(u16, @intCast(x * u.Grid.cell_size)), @as(u16, @intCast(y * u.Grid.cell_size)), main.Config.UNIT_SEARCH_LIMIT);
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
        const key = u.SpatialHash.hash(x, y);

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
        const x = std.math.clamp(old_x orelse entity.x(), 0, main.World.width);
        const y = std.math.clamp(old_y orelse entity.y(), 0, main.World.height);
        const key = u.SpatialHash.hash(x, y);

        //std.log.info("Removing entity {} from grid cell at {},{} (hash {}).", .{ @intFromPtr(entity), x, y, key });

        if (self.cells.get(key)) |*listConst| {
            const list = @constCast(listConst);
            try u.findAndSwapRemove(Entity, list, entity);

            if (list.items.len == 0) {
                //std.debug.print("Cell {} is now empty, removing cell from grid.\n", .{key});
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

    pub fn updateCellMembership(self: *Grid, entity: *Entity, old_x: u16, old_y: u16) void {
        const oldKey = u.SpatialHash.hash(old_x, old_y);
        const curX = entity.x();
        const curY = entity.y();
        const newKey = u.SpatialHash.hash(curX, curY);

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
        const key = u.SpatialHash.hash(x, y);
        if (self.cells.get(key)) |entity_list| {
            return generateCellsign(@constCast(&entity_list));
        }
        return null;
    }

    /// Iterates over the entire grid and generates a fresh `Cellsign` for each cell. Each sign is stored at `[y * self.columns + x]` in the `cellsigns` array.
    pub fn updateCellsigns(self: *Grid) void {
        for (0..self.rows) |y| {
            for (0..self.columns) |x| {
                const key = u.SpatialHash.hash(@truncate(x * u.Grid.cell_size), @truncate(y * u.Grid.cell_size));
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

        const offsets = u.Grid.sectionFromPoint(x, y, main.World.width, main.World.height);

        for (offsets) |offset| {
            const neighbor_x = offset[0];
            const neighbor_y = offset[1];
            const neighbor_key = u.SpatialHash.hash(neighbor_x, neighbor_y);

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

    /// Finds entities in a 3x3 cell radius, then performs an axis-aligned bounding box check. Returns first colliding entity or null.
    pub fn collidesWith(self: *Grid, x: u16, y: u16, width: u16, height: u16, current_entity: ?*Entity) !?*Entity {
        const half_width = @divTrunc(width, 2);
        const half_height = @divTrunc(height, 2);
        const left = @max(half_height, x) - half_width;
        const right = x + half_width;
        const top = @max(half_height, y) - half_height;
        const bottom = y + half_height;
        const nearby_entities = if (current_entity != null and current_entity.?.kind == Kind.Unit)
            try self.sectionSearch(x, y, main.Config.UNIT_SEARCH_LIMIT)
        else
            try self.sectionSearch(x, y, main.Config.PLAYER_SEARCH_LIMIT);
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
