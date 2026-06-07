const std = @import("std");
const conservation = @import("conservation.zig");
const spectral = @import("spectral.zig");
const Allocator = std.mem.Allocator;

pub const AgentState = enum {
    idle,
    thinking,
    executing,
    learning,
    err,
};

pub const AgentError = error{
    InvalidTransition,
    NoCapabilities,
    DecideFailed,
    OutOfMemory,
};

pub const Action = struct {
    capability_index: usize,
    confidence: f64,
};

pub const Agent = struct {
    state: AgentState,
    budget: conservation.ConservationBudget,
    capabilities: []const []const u8,
    weights: []f64,
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator, total_budget: f64, capabilities: []const []const u8) !Self {
        const weights = try allocator.alloc(f64, capabilities.len);
        @memset(weights, 1.0 / @as(f64, @floatFromInt(capabilities.len)));

        return .{
            .state = .idle,
            .budget = conservation.ConservationBudget.init(total_budget),
            .capabilities = capabilities,
            .weights = weights,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.weights);
    }

    pub fn transition(self: *Self, new_state: AgentState) AgentError!void {
        if (self.state == new_state) return; // no-op allowed

        // any -> err is always valid
        if (new_state == .err) {
            self.state = new_state;
            return;
        }

        // err -> idle is valid
        if (self.state == .err and new_state == .idle) {
            self.state = new_state;
            return;
        }

        // Check valid transitions
        const ok = switch (self.state) {
            .idle => new_state == .thinking,
            .thinking => new_state == .executing,
            .executing => new_state == .learning,
            .learning => new_state == .idle,
            .err => new_state == .idle,
        };
        if (ok) {
            self.state = new_state;
            return;
        }
        return error.InvalidTransition;
    }

    pub fn decide(self: *Self, task_features: []const f64) AgentError!Action {
        if (self.capabilities.len == 0) return error.NoCapabilities;
        if (self.state != .thinking) return error.InvalidTransition;

        const n = self.capabilities.len;
        const allocator = self.allocator;

        // Build simple preference matrix from weights
        var matrix = try allocator.alloc([]f64, n);
        defer {
            for (matrix) |row| allocator.free(row);
            allocator.free(matrix);
        }
        for (0..n) |i| {
            matrix[i] = try allocator.alloc(f64, n);
            @memset(matrix[i], 0);
            for (0..n) |j| {
                if (i == j) {
                    matrix[i][j] = self.weights[i];
                    if (i < task_features.len) matrix[i][j] *= task_features[i];
                } else {
                    // Small coupling
                    matrix[i][j] = 0.01 * self.weights[i] * self.weights[j];
                }
            }
        }

        // Build const matrix for spectral
        var const_matrix = try allocator.alloc([]const f64, n);
        defer allocator.free(const_matrix);
        for (0..n) |i| {
            const_matrix[i] = matrix[i];
        }

        const ranked = spectral.rank(allocator, const_matrix, 50) catch return error.DecideFailed;
        defer allocator.free(ranked);

        return .{
            .capability_index = ranked[0],
            .confidence = self.weights[ranked[0]],
        };
    }

    pub fn learn(self: *Self, reward: f64, cost: f64) void {
        const n = self.weights.len;
        if (n == 0) return;

        // Simple weight update: boost high-reward, penalize high-cost
        for (self.weights) |*w| {
            const signal = reward * 0.1 - cost * 0.05;
            w.* = @max(0.001, w.* + signal);
        }

        // Normalize weights to sum to 1.0
        var sum: f64 = 0;
        for (self.weights) |w| sum += w;
        if (sum > 1e-12) {
            for (self.weights) |*w| w.* /= sum;
        }
    }
};

test "agent init" {
    const allocator = std.testing.allocator;
    const caps = &[_][]const u8{ "plan", "execute" };
    var agent = try Agent.init(allocator, 100.0, caps);
    defer agent.deinit();
    try std.testing.expectEqual(AgentState.idle, agent.state);
    try std.testing.expect(agent.weights.len == 2);
}

test "agent valid transition" {
    const allocator = std.testing.allocator;
    const caps = &[_][]const u8{ "plan" };
    var agent = try Agent.init(allocator, 100.0, caps);
    defer agent.deinit();
    try agent.transition(.thinking);
    try std.testing.expectEqual(AgentState.thinking, agent.state);
    try agent.transition(.executing);
    try std.testing.expectEqual(AgentState.executing, agent.state);
}

test "agent invalid transition" {
    const allocator = std.testing.allocator;
    const caps = &[_][]const u8{ "plan" };
    var agent = try Agent.init(allocator, 100.0, caps);
    defer agent.deinit();
    const result = agent.transition(.executing); // idle -> executing is invalid
    try std.testing.expectError(error.InvalidTransition, result);
}

test "agent error recovery" {
    const allocator = std.testing.allocator;
    const caps = &[_][]const u8{ "plan" };
    var agent = try Agent.init(allocator, 100.0, caps);
    defer agent.deinit();
    try agent.transition(.err);
    try std.testing.expectEqual(AgentState.err, agent.state);
    try agent.transition(.idle);
    try std.testing.expectEqual(AgentState.idle, agent.state);
}

test "agent learn" {
    const allocator = std.testing.allocator;
    const caps = &[_][]const u8{ "plan", "exec" };
    var agent = try Agent.init(allocator, 100.0, caps);
    defer agent.deinit();
    agent.learn(1.0, 0.1);
    // Weights should still sum to ~1.0
    var sum: f64 = 0;
    for (agent.weights) |w| sum += w;
    try std.testing.expect(std.math.approxEqAbs(f64, sum, 1.0, 1e-6));
}
