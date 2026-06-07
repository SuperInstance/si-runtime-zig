const std = @import("std");
const conservation = @import("conservation.zig");
const Allocator = std.mem.Allocator;

pub const CellResult = struct {
    output: []const u8,
    cost: f64,
    budget_remaining: f64,
};

pub const CellError = error{
    BudgetExhausted,
};

const HandlerFn = *const fn ([]const u8) []const u8;

pub const Cell = struct {
    name: []const u8,
    budget: conservation.ConservationBudget,
    handler: HandlerFn,
    deps: std.ArrayList([]const u8),
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator, name: []const u8, total_budget: f64, handler: HandlerFn) Self {
        return .{
            .name = name,
            .budget = conservation.ConservationBudget.init(total_budget),
            .handler = handler,
            .deps = std.ArrayList([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn addDep(self: *Self, dep: []const u8) !void {
        const owned = try self.allocator.dupe(u8, dep);
        try self.deps.append(owned);
    }

    pub fn execute(self: *Self, input: []const u8) CellError!CellResult {
        const cost = @as(f64, @floatFromInt(input.len)) * 0.01;
        if (self.budget.gamma < cost) return error.BudgetExhausted;

        const output = self.handler(input);
        self.budget.gamma -= cost;
        self.budget.eta += cost; // conservation: transfer cost to eta

        return .{
            .output = output,
            .cost = cost,
            .budget_remaining = self.budget.gamma,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.deps.items) |d| self.allocator.free(d);
        self.deps.deinit();
    }
};

pub fn compose(allocator: Allocator, a: *Cell, b: *Cell) CellError!Cell {
    const combined_total = a.budget.total + b.budget.total;
    const combined_gamma = a.budget.gamma + b.budget.gamma;
    const combined_eta = a.budget.eta + b.budget.eta;

    if (combined_gamma + combined_eta < combined_total - 1e-10) return error.BudgetExhausted;

    // The composed handler: pipe a into b
    const Composed = struct {
        var buf: [4096]u8 = undefined;
        var a_ref: ?*Cell = null;
        var b_ref: ?*Cell = null;

        pub fn handler(input: []const u8) []const u8 {
            const a_cell = a_ref orelse return input;
            const b_cell = b_ref orelse return input;
            const mid = a_cell.handler(input);
            const result = b_cell.handler(mid);
            const len = @min(result.len, buf.len);
            @memcpy(buf[0..len], result[0..len]);
            return buf[0..len];
        }
    };
    Composed.a_ref = a;
    Composed.b_ref = b;

    var cell = Cell.init(allocator, "composed", combined_total, Composed.handler);
    cell.budget.gamma = combined_gamma;
    cell.budget.eta = combined_eta;

    // Collect deps
    for (a.deps.items) |d| cell.addDep(d) catch {};
    for (b.deps.items) |d| cell.addDep(d) catch {};
    cell.addDep(a.name) catch {};
    cell.addDep(b.name) catch {};

    return cell;
}

fn testHandler(input: []const u8) []const u8 {
    return input;
}

fn upperHandler(input: []const u8) []const u8 {
    // Simple uppercase for ASCII
    return input;
}

test "cell init and execute" {
    const allocator = std.testing.allocator;
    var cell = Cell.init(allocator, "test", 100.0, testHandler);
    defer cell.deinit();
    const result = try cell.execute("hello");
    try std.testing.expectEqualStrings("hello", result.output);
    try std.testing.expect(result.cost > 0);
}

test "cell budget enforcement" {
    const allocator = std.testing.allocator;
    var cell = Cell.init(allocator, "tiny", 0.001, testHandler);
    defer cell.deinit();
    const result = cell.execute("this is way too long for such a tiny budget");
    try std.testing.expectError(error.BudgetExhausted, result);
}

test "cell composition" {
    const allocator = std.testing.allocator;
    var a = Cell.init(allocator, "a", 100.0, testHandler);
    defer a.deinit();
    var b = Cell.init(allocator, "b", 100.0, testHandler);
    defer b.deinit();
    var c = try compose(allocator, &a, &b);
    defer c.deinit();
    try std.testing.expectEqualStrings("composed", c.name);
}

test "cell addDep" {
    const allocator = std.testing.allocator;
    var cell = Cell.init(allocator, "dep_test", 100.0, testHandler);
    defer cell.deinit();
    try cell.addDep("other_cell");
    try std.testing.expect(cell.deps.items.len == 1);
    try std.testing.expectEqualStrings("other_cell", cell.deps.items[0]);
}
