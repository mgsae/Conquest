const std: type = @import("std");
const rl = @import("raylib");
const main = @import("main.zig");
const u = @import("utils.zig");
const Genome = @import("traits.zig").Genome;

// Setting up entities and effects
pub var players: std.ArrayList(*Player) = undefined;
pub var units: std.ArrayList(*Unit) = undefined;
pub var structures: std.ArrayList(*Structure) = undefined;
pub var resources: std.ArrayList(*Resource) = undefined;
pub var projectiles: std.ArrayList(*Projectile) = undefined;

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
            Kind.Unit => self.ref.Unit.width,
            Kind.Structure => self.ref.Structure.width(),
            Kind.Resource => self.ref.Resource.width(),
        };
    }

    pub fn height(self: *Entity) u16 {
        return switch (self.kind) {
            Kind.Player => self.ref.Player.height,
            Kind.Unit => self.ref.Unit.height,
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
            Kind.Resource => @intCast(self.ref.Resource.capacity), // Counting capacity as life for resource
        };
    }

    pub fn setLife(self: *Entity, new_life: i16) void {
        switch (self.kind) {
            Kind.Player => self.ref.Player.life = new_life,
            Kind.Unit => self.ref.Unit.life = new_life,
            Kind.Structure => self.ref.Structure.life = new_life,
            Kind.Resource => self.ref.Resource.capacity = u.asU16(i16, new_life), // Counting capacity as life for resource
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
            Kind.Unit => self.ref.Unit.speed,
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

    /// Checks if side of self touches side of other. Use `u.closestContact` to find self's nearest such point.
    pub fn isTouching(self: *Entity, other: *Entity, distance: u16) bool {
        const delta = u.deltaXy(self.x(), self.y(), other.x(), other.y());
        const buffer = u.asU16(f16, @round(self.speed())) + distance;
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

    pub fn setSelected(self: *Entity, value: bool) void {
        switch (self.kind) {
            Kind.Player => self.ref.Player.selected = value,
            Kind.Unit => self.ref.Unit.selected = value,
            Kind.Structure => self.ref.Structure.selected = value,
            Kind.Resource => self.ref.Resource.selected = value,
        }
    }
};

// Player
//----------------------------------------------------------------------------------
pub const Player = struct {
    entity: *Entity,
    id: u8,
    life: i16,
    width: u16,
    height: u16,
    x: u16,
    y: u16,
    speed: f16 = 0,
    state: State,
    local: bool = false,
    selected: bool = false,

    pub const State = enum {
        Default,
        Dead,
    };

    pub fn draw(self: Player, alpha: f32) void {
        if (main.Player.selected[0] == self.entity) { // If selected by local player, draws circle
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
        var obstacle_x: ?*Entity = null;
        var obstacle_y: ?*Entity = null;
        const delta = u.deltaXy(self.x, self.y, changed_x orelse self.x, changed_y orelse self.y);
        const angle = u.deltaToAngle(delta[0], delta[1]);
        // const deltaXy = u.deltaXy(old_x, old_y, new_x orelse old_x, new_y orelse old_y);
        // std.debug.print("Player movement direction: {}. Delta to angle: {}. Angle from dir: {}. Vector to delta: {any}.\n", .{ self.direction, @as(i64, @intFromFloat(u.deltaToAngle(deltaXy[0], deltaXy[1]))), u.angleFromDir(self.direction), u.vectorToDelta(u.deltaToAngle(deltaXy[0], deltaXy[1]), speed) });

        // Gets potential obstacle entities on both axes
        if (changed_x != null) obstacle_x = main.World.grid.collidesWith(changed_x.?, self.y, self.width, self.height, self.entity) catch null;
        if (changed_y != null) obstacle_y = main.World.grid.collidesWith(self.x, changed_y.?, self.width, self.height, self.entity) catch null;

        if (changed_x != null and changed_y != null) { // Executes diagonal movement
            const diagonal_obstacle = main.World.grid.collidesWith(changed_x.?, changed_y.?, self.width, self.height, self.entity) catch null;
            if (diagonal_obstacle == null) {
                self.x = changed_x.?;
                self.y = changed_y.?;
            } else { // Blocked diagonal movement
                if (obstacle_x == null) self.x = changed_x.?;
                if (obstacle_y == null) self.y = changed_y.?;
                if (obstacle_x != null and obstacle_x.?.kind == Kind.Unit) handleHorizontalCollision(self, old_x, changed_x.?, speed, angle, obstacle_x.?);
                if (obstacle_y != null and obstacle_y.?.kind == Kind.Unit) handleVerticalCollision(self, old_y, changed_y.?, speed, angle, obstacle_y.?);
            }
        } else if (changed_x != null) { // Executes horizontal movement
            if (obstacle_x == null) {
                self.x = changed_x.?;
            } else if (obstacle_x.?.kind == Kind.Unit) { // If unit obstacle, try horizontal push
                handleHorizontalCollision(self, old_x, changed_x.?, speed, angle, obstacle_x.?);
            } else { // If non-unit obstacle, move up to
                self.x = if (delta[0] < 0) obstacle_x.?.x() - (self.width / 2 + obstacle_x.?.width() / 2) else obstacle_x.?.x() + (self.width / 2 + obstacle_x.?.width() / 2);
            }
        } else if (changed_y != null) { // Executes vertical movement
            if (obstacle_y == null) {
                self.y = changed_y.?;
            } else if (obstacle_y.?.kind == Kind.Unit) { // If unit obstacle, try vertical push
                handleVerticalCollision(self, old_y, changed_y.?, speed, angle, obstacle_y.?);
            } else { // If non-unit obstacle, move up to
                self.y = if (delta[1] < 0) obstacle_y.?.y() - (self.height / 2 + obstacle_y.?.height() / 2) else obstacle_y.?.y() + (self.height / 2 + obstacle_y.?.height() / 2);
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
            .width = u.Subcell.half * 3,
            .height = u.Subcell.half * 3,
            .speed = 0,
            .state = State.Default,
            .local = true,
        };
        entity.* = Entity{
            .kind = Kind.Player,
            .ref = .{ .Player = player },
        };
        u.markSubcellsBlocked(x, y, u.Subcell.half * 3, u.Subcell.half * 3, true);
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
            .width = u.Subcell.half * 3,
            .height = u.Subcell.half * 3,
            .speed = 0,
            .state = State.Default,
            .local = false,
        };
        entity.* = Entity{
            .kind = Kind.Player,
            .ref = .{ .Player = player },
        };
        u.markSubcellsBlocked(x, y, u.Subcell.half * 3, u.Subcell.half * 3, true);
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

    genome: Genome,
    owner: u8,
    x: u16,
    y: u16,
    life: i16,

    // Phenotype - derived from genome
    width: u16,
    height: u16,
    speed: f16,
    health: i16,
    reach: f32,
    tempo: i16,
    carry: u16,

    // Behavioral state
    target: u.Circle,
    immediate_target: u.Circle,
    last_step: u.Point,
    stored_extrema: [2]?u.Point,
    cached_cellsigns: [9]u32,
    model: *u.Model,
    state: State,

    // Resources and reproduction
    resources: [4]u16,
    energy: u16, // Energy for mating (gained from food)
    selectivity: u16 = 1, // Threshold for mating (own & other's energy must exceed)
    mate_target: ?*Unit, // Current mate if in mating process
    // projectiles: *std.ArrayList(*Projectile),

    elapsed: i16 = 0,
    experience: i16 = 0,
    selected: bool = false,

    pub const State = enum {
        Default,
        Attacking,
        Incapacitated,
        Gathering,
        Delivering,
        Storing, // Delivering resource at building
        Seeking, // Looking for resources/mates
        Mating,
        Dead,
    };

    pub fn draw(self: *Unit, alpha: f32) void {
        if (self.state == State.Dead) return;
        const m: u16 = if (self.state == State.Mating) 2 else 1; // Doubling size when mating
        u.drawModel(self.model, self.width * m, self.height * m, self.entity.color(alpha), self.entity.color(alpha));
        if (self.selected) u.drawCircumference(self.target, self.entity.color(alpha / 2));
        u.drawLifeInterpolated(self.x, self.y, self.width, self.life, self.health, self.last_step, self.elapsed);
        // for (self.projectiles.items) |projectile| projectile.draw(alpha);
    }

    pub fn update(self: *Unit) !void {
        // Life depletion
        if (main.moveDivMultiple(self.elapsed, 6)) {
            self.life -= 1;
        }

        if (self.life <= 0) {
            try self.die(null); // Sets State.Dead
            return;
        }

        if (self.mate_target != null and self.mate_target.?.state == State.Dead) {
            self.mate_target = null; // Clears outdated mate
        }

        // Update every 10 ticks
        if (main.moveDivision(self.elapsed)) {
            self.last_step = u.Point.at(self.x, self.y);

            // Execute actions at tempo rate
            if (main.moveDivMultiple(self.elapsed, self.tempo)) {
                try self.executeAction(); // Updates state, behavior
            }

            // Movement (unless incapacitated, attacking, gathering, or mating)
            if (self.state == State.Default or self.state == State.Seeking or self.state == State.Delivering) {
                const step = self.getStep(); // Finds next target
                try self.move(step.x, step.y); // Performs move
            }

            // Reset incapacitated state
            if (self.state == State.Incapacitated) {
                self.state = State.Default;
            }
        }

        // Update model interpolation
        const factor = u.Interpolation.getFactor(self.elapsed, main.World.MOVEMENT_DIVISIONS);
        self.model.updateRigidBodyInterpolated(0, u.Vector.fromPoint(self.last_step), u.Vector.fromCoords(self.x, self.y), factor);

        if (self.state == State.Incapacitated) {
            self.last_step = u.Point.at(self.x, self.y);
        }

        self.elapsed = (self.elapsed +% 1) & 0x7FFF; // Wraps at 32767
    }

    /// Execute the appropriate action based on current state and nearby entities.
    fn executeAction(self: *Unit) !void {
        // Combat if threatened
        if (self.getAttackTarget()) |target| {
            if (try self.attack(target)) {
                self.state = State.Attacking;
                self.experience += 1;
                return;
            }
        }

        // Not currently attacking, clears attacking state
        if (self.state == State.Attacking) {
            self.state = State.Default;
        }

        // If close, mates and clears mating state
        if (self.state == State.Mating) {
            std.debug.print("Attempting to mate at x/y: {}/{}.\n", .{ self.x, self.y });
            _ = self.tryMate() catch null;
            self.state = State.Default;
            self.mate_target = null;
        }

        // Seek mate if energy is high enough
        if (self.energy >= self.selectivity and self.state != State.Mating and self.mate_target == null) {
            if (self.findPotentialMate()) |mate| {
                self.mate_target = mate;
                mate.mate_target = self;
                self.state = State.Seeking;
                mate.state = State.Seeking;
                self.target = u.Circle.aroundEntity(mate.entity, self.reachU16());
                mate.target = u.Circle.aroundEntity(self.entity, mate.reachU16());
                return;
            }
        }

        // Deliver resources if carrying
        if (self.state == State.Storing) {
            if (self.deliverResources()) {
                self.state = State.Default;
                return;
            }
        }

        // Gather resources if nearby and close target
        if (self.state != State.Delivering and u.manhattanDistance(self.last_step, self.target.center) < u.Grid.cell_size) {
            if (self.getResourceTarget()) |target| {
                if (self.gather(target)) {
                    self.state = if (u.randomBool()) State.Gathering else State.Default;
                    self.experience += 1;

                    // Convert to carrying state if gathered enough
                    if (self.resources[0] + self.resources[1] >= self.carry) {
                        self.state = State.Delivering;
                    }
                    return;
                }
            }
        }

        // Not currently gathering, clears gathering state
        if (self.state == State.Gathering) {
            self.state = State.Default;
        }
    }

    /// Try to deliver resources to own structure
    fn deliverResources(self: *Unit) bool {
        if (u.concentricRelationalSearch(&main.World.grid, self.entity, Entity.isOwnStructure)) |building| {
            if (self.entity.isTouching(building, self.reachU16())) {
                // Transfer resources
                building.ref.Structure.capacity = @min(Structure.preset(building.ref.Structure.class).capacity, building.ref.Structure.capacity + self.resources[0]);
                building.ref.Structure.materials += self.resources[1];

                // Gain energy from delivered food
                self.energy += self.resources[0];

                self.resources[0] = 0;
                self.resources[1] = 0;
                return true;
            } else {
                // Not at building yet, set as target
                self.target = u.Circle.aroundEntity(building, self.reachU16());
            }
        }
        return false;
    }

    /// Find a potential mate (opposite sex, same owner, sufficient energy)
    fn findPotentialMate(self: *Unit) ?*Unit {
        const search_radius = 2; // Cells
        const my_cell_x = u.Grid.x(self.x);
        const my_cell_y = u.Grid.y(self.y);

        var dy: i32 = -search_radius;
        while (dy <= search_radius) : (dy += 1) {
            var dx: i32 = -search_radius;
            while (dx <= search_radius) : (dx += 1) {
                const cell_x = @as(i32, @intCast(my_cell_x)) + dx;
                const cell_y = @as(i32, @intCast(my_cell_y)) + dy;

                if (cell_x < 0 or cell_y < 0) continue;

                const entities = main.World.grid.sectionEntities(@intCast(cell_x), @intCast(cell_y));
                if (entities == null) continue;

                for (entities.?.items) |entity| {
                    if (entity.kind != Kind.Unit) continue;
                    const other = entity.ref.Unit;

                    // Check if valid mate
                    if (other != self and other.owner == self.owner and other.genome.sex != self.genome.sex and other.energy >= other.selectivity and other.state != State.Mating and other.state != State.Dead and other.mate_target == null) {
                        return other;
                    }
                }
            }
        }
        return null;
    }

    /// Attempt mating if conditions are met
    fn tryMate(self: *Unit) !bool {
        if (self.mate_target) |mate| {
            // Check if still valid and in range
            if (mate.state == State.Dead or mate.energy < mate.selectivity) {
                self.mate_target = null;
                self.state = State.Default;
                return false;
            }

            if (self.entity.isTouching(mate.entity, self.reachU16())) {
                // Both units consume energy and create offspring
                self.energy = u.u16Sub(self.energy, 1);
                mate.energy = u.u16Sub(mate.energy, 1);

                self.state = State.Mating;
                mate.state = State.Mating;

                // Create offspring with combined genome
                const offspring_genome = try self.genome.reproduce(&mate.genome, main.World.grid.allocator);
                const midpoint_x = @divTrunc(self.x + mate.x, 2);
                const midpoint_y = @divTrunc(self.y + mate.y, 2);

                _ = try Unit.createFromGenome(self.owner, midpoint_x, midpoint_y, offspring_genome);

                self.mate_target = null;
                mate.mate_target = null;
                // std.debug.print("Tried creating child via mating. Result:\n{any}\n", .{child});
                return true;
            }
        }
        return false;
    }

    fn move(self: *Unit, new_x: u16, new_y: u16) !void {
        const old_x = self.x;
        const old_y = self.y;

        if (self.state == State.Incapacitated) return;

        // Bounds check
        if (!u.isInMap(new_x, new_y, self.width, self.height)) {
            if (!u.isInMap(old_x, old_y, self.width, self.height)) {
                const clamped_x = u.mapClampX(@as(i16, @intCast(new_x)), self.width);
                const clamped_y = u.mapClampY(@as(i16, @intCast(new_y)), self.height);
                _ = self.tryMove(clamped_x, clamped_y, old_x, old_y);
            }
            _ = self.retarget();
            return;
        }

        if (!self.tryMove(new_x, new_y, old_x, old_y)) {
            _ = self.moveAlongAxis(new_x, new_y, old_x, old_y);
        }

        // If stuck, retarget
        if (old_x == self.x and old_y == self.y) {
            if (main.moveDivMultiple(self.elapsed, 2)) {
                self.target = u.Circle.at(offsetFromPosition(self.last_step), u.Subcell.size);
            } else {
                // Behavior based on state
                if (self.state == State.Delivering) {
                    if (u.concentricRelationalSearch(&main.World.grid, self.entity, Entity.isOwnStructure)) |b| {
                        self.target = u.Circle.aroundEntity(b, self.reachU16());
                    } else {
                        self.target = u.Circle.at(offsetFromPosition(self.last_step), u.Subcell.size);
                    }
                } else if (self.state == State.Seeking and self.mate_target != null) {
                    self.target = u.Circle.aroundEntity(self.mate_target.?.entity, self.reachU16());
                } else {
                    // Look for resources or wander
                    if (self.findNearestResource()) |r| {
                        self.target = u.Circle.aroundEntity(r, self.reachU16());
                    } else {
                        self.target = u.Circle.at(offsetFromPosition(self.last_step), u.Subcell.size);
                    }
                }
            }
        }
    }

    fn tryMove(self: *Unit, new_x: u16, new_y: u16, old_x: u16, old_y: u16) bool {
        const collision = self.checkCollision(new_x, new_y);
        if (collision == null) {
            self.x = new_x;
            self.y = new_y;
            main.World.grid.updateCellMembership(self.entity, old_x, old_y);
            return true;
        }
        return false;
    }

    fn moveAlongAxis(self: *Unit, new_x: u16, new_y: u16, old_x: u16, old_y: u16) bool {
        const diffX: i32 = @as(i32, @intCast(new_x)) - @as(i32, @intCast(old_x));
        const diffY: i32 = @as(i32, @intCast(new_y)) - @as(i32, @intCast(old_y));

        if (@abs(diffX) > @abs(diffY)) {
            if (!self.tryMove(new_x, old_y, old_x, old_y)) {
                return self.tryMove(old_x, new_y, old_x, old_y);
            }
        } else {
            if (!self.tryMove(old_x, new_y, old_x, old_y)) {
                return self.tryMove(new_x, old_y, old_x, old_y);
            }
        }
        return true;
    }

    fn checkCollision(self: *Unit, x: u16, y: u16) ?*Entity {
        const entities = main.World.grid.sectionEntities(u.Grid.x(x), u.Grid.y(y));
        if (entities == null) return null;

        const half_width = @divTrunc(self.width, 2);
        const half_height = @divTrunc(self.height, 2);
        const left = @max(half_width, x) - half_width;
        const right = x + half_width;
        const top = @max(half_height, y) - half_height;
        const bottom = y + half_height;

        for (entities.?.items) |entity| {
            if (entity == self.entity) continue;

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
                return entity;
            }
        }
        return null;
    }

    pub fn pushed(self: *Unit, angle: f32, distance: f32) f32 {
        const old_x = self.x;
        const old_y = self.y;
        const new_x: u16, const new_y: u16 = calculatePushPosition(self, angle, distance);
        self.state = State.Incapacitated;

        if (!u.isInMap(new_x, new_y, self.width, self.height)) return distance;
        var moved_distance: f32 = distance;

        const obstacle = main.World.grid.collidesWith(new_x, new_y, self.width, self.height, self.entity) catch null;
        if (obstacle == null) {
            self.x = new_x;
            self.y = new_y;
            main.World.grid.updateCellMembership(self.entity, old_x, old_y);
        } else if (obstacle.?.kind == Kind.Unit) {
            const obstacle_unit = obstacle.?.ref.Unit;
            if (obstacle_unit.state != State.Incapacitated) {
                moved_distance = moved_distance / 2;
            } else {
                moved_distance = pushed(obstacle_unit, angle, @min(distance, distance * u.sizeFactor(self.width, self.height, obstacle_unit.width, obstacle_unit.height)));
                const push_delta_xy = u.vectorToDelta(angle, moved_distance);
                const push_new_x = @as(u16, @intFromFloat(@as(f32, @floatFromInt(self.x)) + push_delta_xy[0]));
                const push_new_y = @as(u16, @intFromFloat(@as(f32, @floatFromInt(self.y)) + push_delta_xy[1]));
                self.move(push_new_x, push_new_y) catch return 0;
            }
        }

        return moved_distance;
    }

    fn calculatePushPosition(self: *Unit, angle: f32, distance: f32) [2]u16 {
        const delta_xy = u.vectorToDelta(angle, distance);
        const new_x_float: f32 = @round(@as(f32, @floatFromInt(self.x)) + delta_xy[0]);
        const new_y_float: f32 = @round(@as(f32, @floatFromInt(self.y)) + delta_xy[1]);

        const new_x = @as(u16, @intFromFloat(u.u16Clamp(f32, new_x_float)));
        const new_y = @as(u16, @intFromFloat(u.u16Clamp(f32, new_y_float)));

        return [2]u16{ new_x, new_y };
    }

    pub fn retarget(self: *Unit) bool {
        const prev_target = self.target;

        // Retarget based on state
        if (self.state == State.Delivering) {
            if (u.concentricRelationalSearch(&main.World.grid, self.entity, Entity.isOwnStructure)) |b| {
                self.target = u.Circle.aroundEntity(b, self.reachU16());
            } else {
                self.target = u.Circle.at(offsetFromPosition(u.Point.at(self.x, self.y)), u.Subcell.size);
            }
        } else if (self.state == State.Seeking and self.mate_target != null) {
            self.target = u.Circle.aroundEntity(self.mate_target.?.entity, self.reachU16());
        } else if (self.findNearestResource()) |r| {
            self.target = u.Circle.aroundEntity(r, self.reachU16());
        } else {
            self.target = u.Circle.at(offsetFromPosition(u.Point.at(self.x, self.y)), u.Subcell.size);
        }

        return prev_target.center.x != self.target.center.x or prev_target.center.y != self.target.center.y;
    }

    fn findNearestResource(self: *Unit) ?*Entity {
        return u.concentricSearch(&main.World.grid, u.Point.at(self.x, self.y), Entity.isAvailableResource);
    }

    fn offsetFromPosition(position: u.Point) u.Point {
        const x: i16 = @as(i16, @intCast(position.x)) + (u.randomI16(u.Grid.cell_quarter) - u.Grid.cell_quarter / 2);
        const y: i16 = @as(i16, @intCast(position.y)) + (u.randomI16(u.Grid.cell_quarter) - u.Grid.cell_quarter / 2);
        return u.Point.at(u.mapClampX(x, u.Grid.cell_quarter), u.mapClampY(y, u.Grid.cell_quarter));
    }

    fn getStep(self: *Unit) u.Point {
        const current = u.Point.at(self.x, self.y);
        if (self.state == State.Incapacitated or self.state == State.Gathering) {
            return current;
        }

        // Check if attempting to mate
        if (self.state == State.Seeking and self.mate_target != null) {
            if (self.entity.isTouching(self.mate_target.?.entity, self.reachU16())) {
                self.state = State.Mating; // Performs in executeAction
                return current;
            }
        }

        const distance_squared = u.distanceSquared(current, self.target.center);

        // Within target cell
        if (distance_squared <= u.Grid.cell_size_squared) {
            if (self.target.contains(current)) { // Reached target, decide next action
                if (self.state == State.Delivering) {
                    var structure: ?*Entity = u.concentricRelationalSearch(&main.World.grid, self.entity, Entity.isOwnStructure);
                    if (structure == null) { // No own structure within section, tries searching from another unit
                        for (units.items) |other_unit| {
                            if (other_unit.owner == self.owner and other_unit != self) {
                                structure = u.concentricRelationalSearch(&main.World.grid, other_unit.entity, Entity.isOwnStructure);
                                break;
                            }
                        }
                    }
                    if (structure != null) { // Found structure to deliver to
                        if (self.entity.isTouching(structure.?, self.reachU16())) {
                            self.state = State.Storing;
                            return current; // Will deliver in executeAction
                        } else {
                            self.target = u.Circle.aroundEntity(structure.?, self.reachU16());
                        }
                    } else { // Found no structure to deliver to, wanders
                        self.target = u.Circle.at(offsetFromPosition(current), u.Subcell.size);
                    }
                } else { // Not carrying, looks for new resource or wander
                    var resource: ?*Entity = self.getResourceTarget();
                    if (resource == null) {
                        for (units.items) |other_unit| {
                            if (other_unit.owner == self.owner and other_unit != self) {
                                resource = other_unit.getResourceTarget();
                                break;
                            }
                        }
                    }
                    if (resource != null) {
                        if (self.entity.isTouching(resource.?, self.reachU16())) {
                            self.state = State.Gathering;
                            return current; // Will gather in executeAction
                        } else {
                            self.target = u.Circle.at(u.Point.closestContact(self.entity, resource.?), @as(u16, @intFromFloat(self.reach / 2)));
                        }
                    } else { // Found no new resource, wanders
                        self.target = u.Circle.at(offsetFromPosition(current), u.Subcell.size);
                    }
                }
            }

            // A* pathfinding within cell
            const cur_node = u.Subcell.closestNodePoint(current.x, current.y);
            const tar_node = u.Subcell.closestNodePoint(self.target.center.x, self.target.center.y);
            const distance_to_center = u.asF16(u16, u.manhattanDistance(current, self.immediate_target.center)) - u.asF16(u16, (self.width + self.height) / 2);

            if (self.stored_extrema[0] == null or self.stored_extrema[1] == null or !self.stored_extrema[1].?.equals(tar_node) or self.target.contains(current) or distance_to_center <= self.speed) {
                const new_path = main.World.grid.findNodePath(cur_node, self.target) catch |err| switch (err) {
                    error.NoPath => null,
                    else => {
                        std.debug.print("Error: {}\n", .{err});
                        return current;
                    },
                };
                if (new_path) |path| {
                    defer path.deinit();
                    if (path.items.len > 1 and self.immediate_target.contains(path.items[0])) {
                        self.immediate_target = u.Circle.at(path.items[1], u.Subcell.size);
                    } else {
                        self.immediate_target = u.Circle.at(path.items[0], u.Subcell.size);
                    }
                }
            }
            self.stored_extrema[0] = cur_node;
            self.stored_extrema[1] = tar_node;
        } else { // Not within a cell of target
            // Waypoint pathfinding for distant targets
            const cur_wp = u.Waypoint.closest(current.x, current.y);
            const tar_wp = u.Waypoint.closest(self.target.center.x, self.target.center.y);

            if (self.stored_extrema[0] == null or self.stored_extrema[1] == null or self.stored_extrema[0].?.x != cur_wp.x or self.stored_extrema[0].?.y != cur_wp.y or self.stored_extrema[1].?.x != tar_wp.x or self.stored_extrema[1].?.y != tar_wp.y) {
                const new_path = main.World.grid.findWaypointPath(cur_wp, tar_wp) catch |err| switch (err) {
                    error.NoPath => null,
                    else => {
                        std.debug.print("Error: {}\n", .{err});
                        return current;
                    },
                };
                if (new_path) |path| {
                    defer path.deinit();
                    if (path.items.len > 1 and self.immediate_target.contains(path.items[0])) {
                        self.immediate_target = u.Circle.at(path.items[1], u.Grid.cell_quarter);
                    } else {
                        self.immediate_target = u.Circle.at(path.items[0], u.Grid.cell_quarter);
                    }
                }
            }
            self.stored_extrema[0] = cur_wp;
            self.stored_extrema[1] = tar_wp;
        }

        return self.stepTowardsTarget(current, self.immediate_target.center);
    }

    fn stepTowardsTarget(self: *Unit, current: u.Point, target: u.Point) u.Point {
        const magnitude = u.adjustToDistance(current, target, self.speed, self.speed);
        const dx = @as(i32, @intCast(current.x)) - @as(i32, @intCast(target.x));
        const dy = @as(i32, @intCast(current.y)) - @as(i32, @intCast(target.y));

        const angle = u.deltaToAngle(dx, dy);
        const vector = u.vectorToDelta(angle, magnitude);
        var next_point = u.deltaPoint(self.x, self.y, vector[0], vector[1]);

        // Lookahead collision avoidance
        const lookahead_vector = u.vectorToDelta(angle, magnitude * 3);
        const lookahead_point = u.deltaPoint(self.x, self.y, lookahead_vector[0], lookahead_vector[1]);

        if (!self.target.contains(lookahead_point)) {
            const obstacle = self.checkCollision(lookahead_point.x, lookahead_point.y);
            if (obstacle != null) {
                next_point = self.lookaheadDisplacement(angle, obstacle.?);
                //self.immediate_target.center = next_point;
                if (u.randomBool() and u.manhattanDistance(self.last_step, self.target.center) < u.Grid.cell_size) {
                    self.target = u.Circle.at(offsetFromPosition(u.Point.at(self.x, self.y)), u.Subcell.size);
                }
            }
        }
        return next_point;
    }

    fn lookaheadDisplacement(self: *Unit, base_angle: f32, collider: *Entity) u.Point {
        const obstacle = u.Point.atEntity(collider);
        const obs_dx = @as(i32, @intCast(obstacle.x)) - @as(i32, @intCast(self.x));
        const obs_dy = @as(i32, @intCast(obstacle.y)) - @as(i32, @intCast(self.y));
        const angle_to_obstacle = u.deltaToAngle(obs_dx, obs_dy);

        const targ_dx = @as(i32, @intCast(self.target.center.x)) - @as(i32, @intCast(self.x));
        const targ_dy = @as(i32, @intCast(self.target.center.y)) - @as(i32, @intCast(self.y));
        const angle_to_target = u.deltaToAngle(targ_dx, targ_dy);

        const angle_diff = angle_to_target - angle_to_obstacle;
        const bias = (@intFromPtr(&self) & 1) == 1;
        const deviation_angle: f32 = if ((angle_diff > 0) != bias) 45 else -45;

        const new_angle = base_angle + deviation_angle;
        const vector = u.vectorToDelta(new_angle, self.speed);
        return u.deltaPoint(self.x, self.y, vector[0], vector[1]);
    }

    fn getAttackTarget(self: *Unit) ?*Entity {
        const found_entity = u.concentricRelationalSearch(&main.World.grid, self.entity, Entity.isEnemy);
        if (found_entity != null and self.entity.inRangeOf(found_entity.?, self.reach)) {
            return found_entity;
        }
        return null;
    }

    fn getResourceTarget(self: *Unit) ?*Entity {
        return u.concentricSearch(&main.World.grid, u.Point.at(self.x, self.y), Entity.isAvailableResource);
    }

    fn attack(self: *Unit, target: *Entity) !bool {
        _ = Projectile.launch(self.entity, 0, target) catch |err| {
            std.debug.print("Attack failed: {}.\n", .{err});
            return false;
        };
        //try self.projectiles.append(projectile);
        return true;
    }

    /// Tries gathering from `target`. False if not a resource, capacity 0, or out of self's reach. Sets state to Delivering if reached carry threshold. Otherwise sets self's target to `target`.
    fn gather(self: *Unit, target: *Entity) bool {
        if (target.kind != Kind.Resource or target.ref.Resource.capacity == 0) return false;
        if (!self.entity.isTouching(target, self.reachU16())) return false;
        target.ref.Resource.capacity = u.u16Sub(target.ref.Resource.capacity, 1);
        self.resources[target.ref.Resource.class] += 1;

        // Check if carrying max, set to return
        if (self.resources[0] + self.resources[1] >= self.carry) {
            self.state = State.Delivering;
        } else {
            self.target = u.Circle.aroundEntity(target, self.reachU16());
        }
        return true;
    }

    fn reachU16(self: *Unit) u16 {
        return @as(u16, @intFromFloat(self.reach));
    }

    pub fn create(owner: u8, x: u16, y: u16, source: u8) !*Unit {
        const genome = Genome.preset(source);
        return createFromGenome(owner, x, y, genome);
    }

    pub fn createFromGenome(owner: u8, x: u16, y: u16, genome: Genome) !*Unit {
        const entity = try main.World.grid.allocator.create(Entity);
        const unit = try main.World.grid.allocator.create(Unit);
        //const projectiles = try main.World.grid.allocator.create(std.ArrayList(*Projectile));
        //projectiles.* = std.ArrayList(*Projectile).init(main.World.grid.allocator.*);

        const start_point = u.Point.at(x, y);

        // Initial target - look for resources nearby
        var initial_target: ?u.Circle = null;
        if (genome.sex == Genome.Sex.Male) {
            const enemy: ?*Entity = for (players.items) |p| { // Gets first non-owner player
                if (p.id != owner) break p.entity;
            } else null;
            if (enemy != null) initial_target = u.Circle.aroundEntity(enemy.?, u.Subcell.size);
        } else {
            const nearby_resource = u.concentricSearch(&main.World.grid, start_point, Entity.isAvailableResource);
            if (nearby_resource) |r| {
                initial_target = u.Circle.aroundEntity(r, 50);
            }
        }
        if (initial_target == null) initial_target = u.Circle.at(offsetFromPosition(start_point), u.Grid.cell_quarter);

        const model = try u.Model.createRectangle(main.World.grid.allocator, start_point);

        unit.* = Unit{
            .entity = entity,
            .owner = owner,
            .genome = genome,
            .model = model,
            .x = x,
            .y = y,
            .life = 0,
            .width = 0,
            .height = 0,
            .speed = 0,
            .health = 0,
            .reach = 0,
            .tempo = 0,
            .carry = 0,
            .target = initial_target.?,
            .immediate_target = initial_target.?,
            .last_step = start_point,
            .stored_extrema = [2]?u.Point{ null, null },
            .cached_cellsigns = [_]u32{0} ** 9,
            //.projectiles = projectiles,
            .state = State.Default,
            .resources = [_]u16{ 0, 0, 0, 0 },
            .energy = 0,
            .mate_target = null,
        };

        entity.* = Entity{
            .kind = Kind.Unit,
            .ref = .{ .Unit = unit },
        };

        unit.genome.applyToUnit(unit);

        try main.World.new_units.append(unit);
        try main.World.grid.addToCell(entity, null, null);
        return unit;
    }

    pub fn die(self: *Unit, cause: ?u8) !void {
        _ = cause;
        try main.World.grid.removeFromAllSections(self.entity);
        self.state = State.Dead;
    }

    pub fn remove(self: *Unit) !void {
        try main.World.grid.removeFromCell(self.entity, null, null);
        try main.World.grid.removeFromAllSections(self.entity);
        try u.findAndSwapRemove(Unit, &units, self);

        for (units.items) |unit| {
            std.debug.assert(unit != self);
        }

        //self.projectiles.deinit();
        //main.World.grid.allocator.destroy(self.projectiles);
        self.model.destroy(main.World.grid.allocator);
        main.World.grid.allocator.destroy(self.entity);
        main.World.grid.allocator.destroy(self);
    }

    pub fn effectiveSpeed(self: *Unit) f16 {
        return self.speed * main.World.MOVEMENT_DIVISIONS;
    }
};

// Structure
//----------------------------------------------------------------------------------
pub const Structure = struct {
    entity: *Entity,
    state: State,
    owner: u8,
    class: u8,
    x: u16,
    y: u16,
    life: i16,
    restitution: f16,
    capacity: u16,
    connected: ?[]*Structure,
    materials: u16 = 0,
    elapsed: u16 = 0,
    selected: bool = false,

    pub const State = enum {
        Default,
        Destroyed,
    };

    pub fn draw(self: *Structure, alpha: f32) void {
        if (self.state == State.Destroyed) return;
        u.drawEntity(self.x, self.y, preset(self.class).width, preset(self.class).height, self.entity.color(alpha));

        u.drawLife(self.x, self.y, preset(self.class).width, self.life, preset(self.class).life);
        u.drawCapacity(self.x, self.y, preset(self.class).width, preset(self.class).height, self.capacity, preset(self.class).capacity);
    }

    /// `Structure` property fields determined by `class`.
    pub const Properties = struct {
        width: u16,
        height: u16,
        life: i16,
        restitution: f16,
        capacity: u16,
        start_capacity: u16,
    };

    /// Returns a `Properties` template determined by `class`.
    pub fn preset(class: u8) Properties {
        return switch (class) {
            0 => Properties{ .width = u.Subcell.half * 5, .height = u.Subcell.half * 5, .life = 12000, .restitution = 8.6, .capacity = 3, .start_capacity = 3 }, // Farm
            1 => Properties{ .width = u.Subcell.half * 3, .height = u.Subcell.half * 3, .life = 8000, .restitution = 4.0, .capacity = 1, .start_capacity = 0 }, // Home
            2 => Properties{ .width = u.Subcell.half * 6, .height = u.Subcell.half * 4, .life = 14000, .restitution = 14.0, .capacity = 6, .start_capacity = 0 }, // Yard
            3 => Properties{ .width = u.Subcell.half * 3, .height = u.Subcell.half * 5, .life = 9000, .restitution = 11.0, .capacity = 4, .start_capacity = 0 }, // Keep
            else => @panic("Invalid structure class"),
        };
    }

    pub fn update(self: *Structure) void {
        self.elapsed += 1;
        const rest_ticks = u.ticksFromSecs(self.restitution);
        if (self.elapsed >= rest_ticks) {
            self.elapsed -= rest_ticks; // Subtracting interval accounts for possible overshoot
            if (self.capacity > 0) {
                if (self.spawnUnit()) |unit| { // Spawns unit
                    _ = unit;
                    self.capacity = self.capacity - 1;
                } else |err| {
                    std.debug.print("Failed to spawn unit: {}. May want some sort of indication.\n", .{err});
                }
            }
            if (self.connected) |old_connected| main.World.grid.allocator.free(old_connected);
            self.connected = u.findConnectedStructures(&main.World.grid, self) catch |err| {
                std.debug.print("Failed to update connections: {}\n", .{err});
                return;
            }; // Updates array
        }
        if (self.capacity > 0) { // Propagates capacity to connected buildings with lower capacity
            if (self.connected) |buildings| {
                for (buildings) |building| {
                    if (self.capacity > building.capacity and building.capacity < Structure.preset(building.class).capacity) {
                        building.capacity = @min(building.capacity + 1, Structure.preset(building.class).capacity);
                        self.capacity -= 1;
                    }
                    if (self.capacity <= 0) break;
                }
            }
        }

        if (self.life <= 0) self.destroy();
    }

    pub fn spawnUnit(self: *Structure) !*Unit {
        const spawn_class = self.spawnClass();
        const spawn_point = self.spawnPoint(50, 50) catch null;
        if (spawn_point) |sp| { // If spawn_point is not null, unwrap it
            const unit = try Unit.create(self.owner, sp[0], sp[1], spawn_class);
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
            .capacity = from_class.start_capacity,
            .x = x,
            .y = y,
            .connected = null,
        };
        entity.* = Entity{
            .kind = Kind.Structure,
            .ref = .{ .Structure = structure },
        };

        u.markSubcellsBlocked(x, y, from_class.width, from_class.height, true);

        try main.World.grid.addToCell(entity, null, null);
        return structure;
    }

    pub fn construct(owner: u8, x: u16, y: u16, class: u8) ?*Structure {
        const open = u.isOpenGround(x, y, preset(class).width, preset(class).height) catch false;
        if (!open or !u.isInMap(x, y, preset(class).width, preset(class).height)) {
            return null;
        }
        const structure = Structure.create(owner, x, y, class) catch return null;
        main.World.new_structures.append(structure) catch return null;
        structure.connected = u.findConnectedStructures(&main.World.grid, structure) catch |err| {
            std.debug.print("Failed to initialize connections: {}\n", .{err});
            return null;
        }; // Initial connections array
        return structure;
    }

    pub fn destroy(self: *Structure) void {
        // Effect here
        main.World.grid.removeFromAllSections(self.entity) catch {}; // Immediate removal
        self.state = State.Destroyed;
    }

    pub fn remove(self: *Structure) !void {
        try main.World.grid.removeFromCell(self.entity, null, null); // Removes entity from grid
        try main.World.grid.removeFromAllSections(self.entity);
        try u.findAndSwapRemove(Structure, &structures, self); // Removes structure from the structures collection
        for (structures.items) |structure| {
            std.debug.assert(structure != self); // For debugging, structure must be removed at this point
        }

        u.markSubcellsBlocked(self.x, self.y, self.width(), self.height(), false);

        if (self.connected) |connected| main.World.grid.allocator.free(connected); // Frees connection array
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
        return try u.Grid.findSpawnLocation(self.x, self.y, self.width(), self.height(), unit_width, unit_height);
    }

    fn width(self: *Structure) u16 {
        return preset(self.class).width;
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
    capacity: u16,
    growth: f16,
    yield: u16 = 0,
    selected: bool = false,

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
        self.yield = u.u16Add(self.yield, 1); // Adds 1 to yield every update
        if (self.capacity < preset(self.class).capacity and self.growth > 0) { // When growing resource is in use
            const max_yield = u.ticksFromSecs(self.growth); // Checks if growth update cycle has been reached
            if (self.yield >= max_yield) { // When above `growth` updates, can spawn copy and resets counter
                var copy: ?*Resource = null;
                if (u.randomU16(100) < @as(u16, @intFromFloat(@round(self.growth)))) {
                    if (self.spawnResource()) |result| {
                        copy = result;
                        // std.debug.print("Spawned resource: {s} at {}/{}.\n", .{ u.resourceTypeFromClass(result.class), result.x, result.y });
                    } else |err| {
                        std.debug.print("Failed to spawn resource {s}: {}.\n", .{ u.resourceTypeFromClass(self.class), err });
                    }
                }
                if (copy == null) { // If didn't spawn copy, ticks capacity towards inactivity
                    self.capacity = @min(preset(self.class).capacity, self.capacity + 1);
                }
                self.yield = u.u16Sub(self.yield, max_yield); // Resets update counter
            }
        }
        if (self.capacity <= 0) {
            main.World.grid.removeFromAllSections(self.entity) catch {}; // Immediate removal
            self.state = State.Depleted;
        }
    }

    /// `Resource` property fields determined by `class`.
    pub const Properties = struct {
        width: u16,
        height: u16,
        capacity: u16,
        growth: f16,
    };

    /// Returns a `Properties` template determined by `class`.
    pub fn preset(class: u8) Properties {
        return switch (class) {
            0 => Properties{ .width = u.Subcell.size, .height = u.Subcell.size, .capacity = 100, .growth = 8.0 },
            1 => Properties{ .width = u.Subcell.size / 2, .height = u.Subcell.size / 2, .capacity = 50, .growth = 60.0 },
            2 => Properties{ .width = u.Subcell.size / 2, .height = u.Subcell.size / 2, .capacity = 800, .growth = 0 },
            3 => Properties{ .width = u.Subcell.size / 4, .height = u.Subcell.size / 4, .capacity = 20, .growth = 0 },
            else => @panic("Invalid resource class"),
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
            .growth = from_class.growth,
            .x = x,
            .y = y,
        };
        entity.* = Entity{
            .kind = Kind.Resource,
            .ref = .{ .Resource = resource },
        };

        u.markSubcellsBlocked(x, y, from_class.width, from_class.height, true);

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
        u.markSubcellsBlocked(self.x, self.y, self.width(), self.height(), false);
        main.World.grid.allocator.destroy(self.entity); // Deallocates memory for the Entity
        main.World.grid.allocator.destroy(self); // Deallocates memory for the Resource
    }

    /// Returns carried resource index (i.e. food/wood/iron/gold) from resource entity's class.
    fn typeFromClass(self: *Resource) usize {
        return switch (self.class) {
            0 => 0,
            1 => 1,
            2 => 2,
            3 => 3,
        };
    }

    pub fn spawnClass(self: *Resource) u8 {
        return switch (self.class) {
            0 => 0, // Not very useful now, but may want to change values here
            1 => 1, // To change what resources get spawned from what
            2 => 2,
            3 => 3,
            else => @panic("Invalid resource class"),
        };
    }

    pub fn spawnResource(self: *Resource) !*Resource {
        const spawn_class = self.spawnClass();
        const spawn_point = self.spawnPoint(Resource.preset(spawn_class).width, Resource.preset(spawn_class).height) catch null;
        if (spawn_point) |sp| { // If spawn_point is not null, unwrap it
            const resource = try Resource.create(sp[0], sp[1], spawn_class);
            try main.World.new_resources.append(resource);
            return resource;
        }
        return error.NoAvailableSpawnPoint;
    }

    pub fn spawnPoint(self: *Resource, resource_width: u16, resource_height: u16) ![2]u16 {
        return try u.Grid.findSpawnLocation(self.x, self.y, self.width(), self.height(), resource_width, resource_height);
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
    state: State,
    x: u16,
    y: u16,
    angle: f32,
    life: i16,
    color: rl.Color,
    targets: ?*std.ArrayList(*Entity), // Populated upon launch

    pub const State = enum {
        Default,
        Destroyed,
    };

    pub fn draw(self: *Projectile, alpha: f32) void {
        u.drawEntity(self.x, self.y, self.width(), self.height(), u.opacity(self.color, alpha));
    }

    pub fn update(self: *Projectile) void {
        self.life -= 1;
        if (self.life <= 0) {
            self.state = State.Destroyed; // Cleared in main
            return;
        }
        // Checks radius for targets, returns true if found
        if (self.checkImpact()) |target| {
            self.impact(target); // Deals damage and does effect
            return;
        }
        const delta = u.vectorToDelta(self.angle, self.speed());
        self.x = u.mapClampFloatX(u.asF32(u16, self.x) + delta[0], self.width());
        self.y = u.mapClampFloatY(u.asF32(u16, self.y) + delta[1], self.height());
    }

    /// `Projectile` property fields determined by `class`.
    pub const Properties = struct {
        width: u16 = 1,
        height: u16 = 1,
        life: i16,
        damage: i16,
        speed: f16,
    };

    /// Returns a `Properties` template determined by `class`.
    pub fn preset(class: u8) Properties {
        return switch (class) {
            0 => Properties{ .life = 32, .speed = 8, .width = 4, .height = 4, .damage = 6 },
            1 => Properties{ .life = 32, .speed = 14, .width = 4, .height = 4, .damage = 16 },
            2 => Properties{ .life = 128, .speed = 6, .width = 8, .height = 8, .damage = 56 },
            3 => Properties{ .life = 36, .speed = 12, .width = 6, .height = 6, .damage = 32 },
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
        // Gets valid targets
        const near = Grid.sectionEntities(&main.World.grid, u.Grid.x(source.x()), u.Grid.x(source.y()));
        var filtered_near: ?*std.ArrayList(*Entity) = null;
        if (near != null) {
            const list_ptr = try main.World.grid.allocator.create(std.ArrayList(*Entity));
            list_ptr.* = std.ArrayList(*Entity).init(main.World.grid.allocator.*);
            for (near.?.items) |e| {
                if (source.isEnemy(e)) {
                    try list_ptr.append(e);
                }
            }
            filtered_near = list_ptr;
        }

        projectile.* = Projectile{
            .class = class,
            .state = State.Default,
            .x = delta.mapOffsetX(source.x()),
            .y = delta.mapOffsetY(source.y()),
            .life = from_class.life,
            .angle = angle,
            .color = source.color(1),
            .targets = filtered_near,
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
            var i: usize = 0;
            while (i < target_list.items.len) {
                const target = target_list.items[i];
                if (target.life() <= 0) {
                    _ = target_list.swapRemove(i); // Remove dead from list
                    continue;
                }
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
                i += 1;
            }
        }
        return null;
    }

    pub fn impact(self: *Projectile, target: *Entity) void {
        const damage = preset(self.class).damage;
        target.setLife(if (target.life() > damage) target.life() - damage else 0);
        self.life -= 100; // Should be enough to kill projectile unless multi targets are wanted
    }

    pub fn remove(self: *Projectile) !void {
        try u.findAndSwapRemove(Projectile, &projectiles, self);
        for (projectiles.items) |projectile| {
            std.debug.assert(projectile != self);
        }
        if (self.targets != null) main.World.grid.allocator.destroy(self.targets.?);
        main.World.grid.allocator.destroy(self);
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
    cellsigns: []u32,
    entity_buffer: []*Entity, // Allocated once, rewritten each tick
    buffer_offset: usize, // Tracks the current usage of the buffer
    sections: []std.ArrayList(*Entity), // Array of dynamic lists of pointers to entities (each section is 3x3 around a given cell)
    cols: usize,
    rows: usize,
    blocked_subcells: std.AutoHashMap(u.Point, void) = undefined, // Stores nodes of blocked subcells

    const Cellsign = u32;

    pub fn init(self: *Grid, allocator: *std.mem.Allocator, columns: usize, rows: usize, buffer_size: usize) !void {
        self.allocator = allocator;
        self.cells = std.hash_map.HashMap(u64, std.ArrayList(*Entity), u.SpatialHash.Context, 80).init(allocator.*);
        self.blocked_subcells = std.AutoHashMap(u.Point, void).init(allocator.*);

        self.cols = columns;
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
        self.blocked_subcells.deinit();

        allocator.free(self.cellsigns);

        for (self.sections) |section| {
            section.deinit();
        }
        allocator.free(self.sections);
        allocator.free(self.entity_buffer);
    }

    /// Takes a grid cell `x`,`y` and returns the list of entities stored in `sections` for that cell.
    pub fn sectionEntities(self: *Grid, x: usize, y: usize) ?*std.ArrayList(*Entity) {
        if (x >= self.cols or y >= self.rows) {
            return null;
        }
        const index = y * self.cols + x;
        return &self.sections[index];
    }

    fn addToSection(self: *Grid, x: usize, y: usize, entity: *Entity) !void {
        if (x < self.cols and y < self.rows) {
            const index = y * self.cols + x;
            try self.sections[index].append(entity);
        }
    }

    fn removeFromSection(self: *Grid, x: usize, y: usize, entity: *Entity) !void {
        if (x < self.cols and y < self.rows) {
            const index = y * self.cols + x;
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

            if (nx >= 0 and nx < self.cols and ny >= 0 and ny < self.rows) {
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
        for (0..self.cols) |x| {
            for (0..self.rows) |y| {
                const sign = cellsigns_cache[y * self.cols + x];
                if (self.getCellsign(x, y) != sign) { // Cellsign changed from previous tick
                    cellsigns_cache[y * self.cols + x] = self.getCellsign(x, y); // Cache is changed in place
                    self.updateSection(x, y) catch |err| {
                        std.log.err("Failed to update section at ({}, {}): {}\n", .{ x, y, err });
                    };
                }
            }
        }
    }

    fn updateSection(self: *Grid, x: usize, y: usize) !void {
        const index = y * self.cols + x;
        const entities = try self.sectionSearch(@as(u16, @intCast(x * u.Grid.cell_size)), @as(u16, @intCast(y * u.Grid.cell_size)), main.Config.UNIT_SEARCH_LIMIT);
        self.sections[index].clearAndFree();

        for (entities) |entity| {
            try self.sections[index].append(entity);
        }
    }

    /// Retrieves current `Cellsign` of cell. Expects `x`,`y` grid coordinates, not world coordinates.
    pub fn getCellsign(self: *Grid, x: usize, y: usize) u32 {
        return self.cellsigns[y * self.cols + x];
    }

    /// Sets `Cellsign` of cell to `value`. Expects `x`,`y` grid coordinates, not world coordinates.
    pub fn setCellsign(self: *Grid, x: usize, y: usize, value: u32) void {
        self.cellsigns[y * self.cols + x] = value;
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
            std.debug.print("PANIC: Entity {} attempted to remove from non-existent cell (x={}, y={}, hash={})\nFor comparison, player is at x={}, y={}.\n", .{ @intFromPtr(entity), x, y, key, players.items[1].x, players.items[1].y });
            std.debug.print("Entity last known position: (x={}, y={})\n", .{ entity.x(), entity.y() });
            std.debug.print("Is entity still in grid?: {}\n", .{self.cells.contains(key)});
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
                std.log.err("Failed to remove entity {} ({}) from old cell (x={}, y={}, hash={}). Error: {}\n", .{ @intFromPtr(entity), entity.kind, old_x, old_y, oldKey, err });
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

    /// Iterates over the entire grid and generates a fresh `Cellsign` for each cell. Each sign is stored at `[y * self.cols + x]` in the `cellsigns` array.
    pub fn updateCellsigns(self: *Grid) void {
        for (0..self.rows) |y| {
            for (0..self.cols) |x| {
                const key = u.SpatialHash.hash(@truncate(x * u.Grid.cell_size), @truncate(y * u.Grid.cell_size));
                if (self.cells.get(key)) |entity_list| {
                    const sign = generateCellsign(@constCast(&entity_list));
                    self.cellsigns[y * self.cols + x] = sign;
                } else {
                    self.cellsigns[y * self.cols + x] = 0; // Clears the cellsign if the cell is empty
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
        const nearby_entities = if (current_entity != null and current_entity.?.kind == Kind.Unit) try self.sectionSearch(x, y, main.Config.UNIT_SEARCH_LIMIT) else try self.sectionSearch(x, y, main.Config.PLAYER_SEARCH_LIMIT);
        for (nearby_entities) |entity| { // Checks each entity to compare with
            if (current_entity) |cur| {
                if (cur == entity) continue; // Skips self entity, if specified
            }
            if (u.entityWithinSquare(entity, left, top, right, bottom)) return entity; // Returns colliding entity
        }
        return null;
    }

    /// Searches for entities in area and returns biggest one, if any.
    pub fn biggestInArea(self: *Grid, min_x: u16, min_y: u16, max_x: u16, max_y: u16) !?*Entity {
        const nearby_entities = try self.sectionSearch((min_x + max_x) / 2, // Search at center of selection box
            (min_y + max_y) / 2, main.Config.PLAYER_SEARCH_LIMIT);
        var biggest_entity: ?*Entity = null;
        for (nearby_entities) |entity| {
            if (u.entityWithinSquare(entity, min_x, min_y, max_x, max_y)) {
                if (biggest_entity == null or u.bigger(entity.width(), entity.height(), biggest_entity.?.width(), biggest_entity.?.height()) == 0) biggest_entity = entity;
            }
        }
        return biggest_entity;
    }

    pub fn ownUnitsInArea(self: *Grid, player_id: u8, min_x: u16, min_y: u16, max_x: u16, max_y: u16) !std.ArrayList(*Entity) {
        const allocator = self.allocator.*;
        var own_units = std.ArrayList(*Entity).init(allocator);
        const nearby_entities = try self.sectionSearch((min_x + max_x) / 2, (min_y + max_y) / 2, main.Config.PLAYER_SEARCH_LIMIT);
        for (nearby_entities) |entity| {
            if (u.entityWithinSquare(entity, min_x, min_y, max_x, max_y)) {
                if (entity.owner() == player_id and entity.kind == Kind.Unit) {
                    try own_units.append(entity);
                }
            }
        }
        return own_units;
    }

    pub fn entityCount(self: *Grid) usize {
        var total_entities: usize = 0;
        var it = self.cells.iterator();
        while (it.next()) |entry| {
            total_entities += entry.value_ptr.items.len;
        }
        return total_entities;
    }

    pub fn findNodePath(self: *Grid, start_point: u.Point, end_circle: u.Circle) !std.ArrayList(u.Point) {
        const allocator = self.allocator.*;

        const start_node = u.Subcell.closestNodePoint(start_point.x, start_point.y);
        const end_node = u.Subcell.closestNodePoint(end_circle.center.x, end_circle.center.y);

        var open_set = std.PriorityQueue(u.PriorityNode, u16, u.lessThan).init(allocator, 0);

        var g_score = std.AutoHashMap(u.Point, u16).init(allocator); // Cost of reaching node from start
        var f_score = std.AutoHashMap(u.Point, u16).init(allocator); // Cost of reaching end via node
        var came_from = std.AutoHashMap(u.Point, u.Point).init(allocator); // Previous node of node
        //std.debug.print("findNodePath: set up prio queue and hashmaps.\n", .{});
        defer open_set.deinit();
        defer g_score.deinit();
        defer f_score.deinit();
        defer came_from.deinit();

        // Initialize start node
        try g_score.put(start_node, 0);
        try f_score.put(start_node, u.manhattanDistance(start_node, end_node));
        try open_set.add(u.PriorityNode.init(start_node, u.manhattanDistance(start_node, end_node)));

        //std.debug.print("findNodePath: initialized start node at {}/{}, end node at {}/{}.\n", .{ start_node.x, start_node.y, end_point.x, end_point.y });

        const MAX_ITERATIONS: usize = 1000;
        var iterations: usize = 0;

        while (open_set.count() > 0) { // Find node with lowest f_score
            iterations += 1;
            if (iterations >= MAX_ITERATIONS) return error.NoPath;
            //std.debug.print("open_set count: {d}.\n", .{open_set.count()});
            const current_node = open_set.remove().point; // Gets node with the lowest f_score
            if (current_node.equals(end_node)) { // Success, reached end
                return self.reconstructPath(came_from, end_node);
            }

            // Check neighbors (up, down, left, right)
            const neighbors = [_]u.Point{
                u.Point.at(u.u16Add(current_node.x, u.Subcell.size), current_node.y),
                u.Point.at(u.u16Sub(current_node.x, u.Subcell.size), current_node.y),
                u.Point.at(current_node.x, u.u16Add(current_node.y, u.Subcell.size)),
                u.Point.at(current_node.x, u.u16Sub(current_node.y, u.Subcell.size)),
            };
            for (neighbors) |neighbor| {
                if (self.blocked_subcells.contains(neighbor) and !end_circle.contains(neighbor) and !neighbor.equals(end_node)) continue;

                const tentative_g_score = u.u16Add((g_score.get(current_node) orelse u.u16max), u.Subcell.size);
                if (tentative_g_score < (g_score.get(neighbor) orelse u.u16max)) {
                    try g_score.put(neighbor, tentative_g_score);
                    try f_score.put(neighbor, u.u16Add(tentative_g_score, u.manhattanDistance(neighbor, end_node)));
                    try came_from.put(neighbor, current_node);

                    try open_set.add(u.PriorityNode.init(neighbor, f_score.get(neighbor).?));
                }
            }
        }
        //std.debug.print("findNodePath: Failed to find end point.\n", .{});
        return error.NoPath;
    }

    pub fn findWaypointPath(self: *Grid, start_point: u.Point, end_point: u.Point) !std.ArrayList(u.Point) {
        const allocator = self.allocator.*;
        const start_wp = u.Waypoint.closest(start_point.x, start_point.y);
        const end_wp = u.Waypoint.closest(end_point.x, end_point.y);
        var open_set = std.PriorityQueue(u.PriorityNode, u16, u.lessThan).init(allocator, 0);
        var g_score = std.AutoHashMap(u.Point, u16).init(allocator); // Cost of reaching node from start
        var f_score = std.AutoHashMap(u.Point, u16).init(allocator); // Cost of reaching end via node
        var came_from = std.AutoHashMap(u.Point, u.Point).init(allocator); // Previous node of node
        //std.debug.print("findWaypointPath: set up prio queue and hashmaps.\n", .{});
        defer open_set.deinit();
        defer g_score.deinit();
        defer f_score.deinit();
        defer came_from.deinit();

        // Initialize start node
        try g_score.put(start_wp, 0);
        try f_score.put(start_wp, u.manhattanDistance(start_wp, end_wp));
        try open_set.add(u.PriorityNode.init(start_wp, u.manhattanDistance(start_wp, end_wp)));

        //std.debug.print("findWaypointPath: initialized start node at {}/{}, end node at {}/{}.\n", .{ start_point.x, start_point.y, end_point.x, end_point.y });

        const MAX_ITERATIONS: usize = 500;
        var iterations: usize = 0;

        while (open_set.count() > 0) { // Find node with lowest f_score
            iterations += 1;
            if (iterations >= MAX_ITERATIONS) return error.NoPath;
            //std.debug.print("open_set count: {d}.\n", .{open_set.count()});
            const current_wp = open_set.remove().point; // Gets node with the lowest f_score
            if (current_wp.equals(end_wp)) { // Success, reached end
                return self.reconstructPath(came_from, end_wp);
            }

            // Check neighbors (up, down, left, right)
            const neighbors = [_]u.Point{
                u.Point.at(u.u16Add(current_wp.x, u.Grid.cell_size), current_wp.y),
                u.Point.at(u.u16Sub(current_wp.x, u.Grid.cell_size), current_wp.y),
                u.Point.at(current_wp.x, u.u16Add(current_wp.y, u.Grid.cell_size)),
                u.Point.at(current_wp.x, u.u16Sub(current_wp.y, u.Grid.cell_size)),
            };
            for (neighbors) |neighbor| {
                if (neighbor.x < u.Grid.cell_half or neighbor.y < u.Grid.cell_half or neighbor.x > main.World.width - u.Grid.cell_half or neighbor.y > main.World.height - u.Grid.cell_half) continue;
                if (self.blocked_subcells.contains(neighbor) and !neighbor.equals(end_wp)) continue;

                const tentative_g_score = u.u16Add((g_score.get(current_wp) orelse u.u16max), u.Grid.cell_size);
                if (tentative_g_score < (g_score.get(neighbor) orelse u.u16max)) {
                    try g_score.put(neighbor, tentative_g_score);
                    try f_score.put(neighbor, u.u16Add(tentative_g_score, u.manhattanDistance(neighbor, end_wp)));
                    try came_from.put(neighbor, current_wp);

                    try open_set.add(u.PriorityNode.init(neighbor, f_score.get(neighbor).?));
                }
            }
        }
        //std.debug.print("findWaypointPath: Failed to find end point.\n", .{});
        return error.NoPath;
    }

    // Reconstructs the path from end to start
    fn reconstructPath(self: *Grid, came_from: std.AutoHashMap(u.Point, u.Point), end_point: u.Point) !std.ArrayList(u.Point) {
        const allocator = self.allocator.*;
        var path = std.ArrayList(u.Point).init(allocator);
        var current = end_point;
        //std.debug.print("reconstructPath: set up path arraylist, starting appending loop.\n", .{});

        while (came_from.get(current)) |prev| {
            try path.append(current);
            current = prev;
        }
        try path.append(current); // Add start node
        //std.debug.print("reconstructPath: reversing items in memory.\n", .{});
        std.mem.reverse(u.Point, path.items); // Reverse to get correct order

        return path;
    }
};
