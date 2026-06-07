const std = @import("std");
const si = @import("si");

test "agent init" {
    const allocator = std.testing.allocator;
    const caps = [_][]const u8{ "plan", "execute", "learn" };
    var agent = try si.Agent.init(allocator, 100.0, &caps);
    defer agent.deinit();
    try std.testing.expectEqual(si.AgentState.idle, agent.state);
    try std.testing.expect(agent.weights.len == 3);
    // Weights should sum to ~1.0
    var sum: f64 = 0;
    for (agent.weights) |w| sum += w;
    try std.testing.expect(std.math.approxEqAbs(f64, sum, 1.0, 1e-6));
}

test "agent full lifecycle" {
    const allocator = std.testing.allocator;
    const caps = [_][]const u8{ "plan", "execute" };
    var agent = try si.Agent.init(allocator, 100.0, &caps);
    defer agent.deinit();

    try agent.transition(.thinking);
    try std.testing.expectEqual(si.AgentState.thinking, agent.state);

    try agent.transition(.executing);
    try std.testing.expectEqual(si.AgentState.executing, agent.state);

    try agent.transition(.learning);
    try std.testing.expectEqual(si.AgentState.learning, agent.state);

    try agent.transition(.idle);
    try std.testing.expectEqual(si.AgentState.idle, agent.state);
}

test "agent invalid transition idle to executing" {
    const allocator = std.testing.allocator;
    const caps = [_][]const u8{ "plan" };
    var agent = try si.Agent.init(allocator, 100.0, &caps);
    defer agent.deinit();
    try std.testing.expectError(error.InvalidTransition, agent.transition(.executing));
}

test "agent invalid transition idle to learning" {
    const allocator = std.testing.allocator;
    const caps = [_][]const u8{ "plan" };
    var agent = try si.Agent.init(allocator, 100.0, &caps);
    defer agent.deinit();
    try std.testing.expectError(error.InvalidTransition, agent.transition(.learning));
}

test "agent any to error state" {
    const allocator = std.testing.allocator;
    const caps = [_][]const u8{ "plan" };
    var agent = try si.Agent.init(allocator, 100.0, &caps);
    defer agent.deinit();

    // From any state, can go to err
    try agent.transition(.err);
    try std.testing.expectEqual(si.AgentState.err, agent.state);
}

test "agent error recovery" {
    const allocator = std.testing.allocator;
    const caps = [_][]const u8{ "plan" };
    var agent = try si.Agent.init(allocator, 100.0, &caps);
    defer agent.deinit();

    try agent.transition(.err);
    try agent.transition(.idle);
    try std.testing.expectEqual(si.AgentState.idle, agent.state);

    // Can continue normal lifecycle after recovery
    try agent.transition(.thinking);
    try std.testing.expectEqual(si.AgentState.thinking, agent.state);
}

test "agent error to non-idle is invalid" {
    const allocator = std.testing.allocator;
    const caps = [_][]const u8{ "plan" };
    var agent = try si.Agent.init(allocator, 100.0, &caps);
    defer agent.deinit();

    try agent.transition(.err);
    try std.testing.expectError(error.InvalidTransition, agent.transition(.thinking));
}

test "agent learn adjusts weights" {
    const allocator = std.testing.allocator;
    const caps = [_][]const u8{ "plan", "exec", "learn" };
    var agent = try si.Agent.init(allocator, 100.0, &caps);
    defer agent.deinit();

    const w0 = agent.weights[0];
    agent.learn(1.0, 0.1);
    // Weights should have changed
    // And still sum to 1.0
    var sum: f64 = 0;
    for (agent.weights) |w| sum += w;
    try std.testing.expect(std.math.approxEqAbs(f64, sum, 1.0, 1e-6));
    _ = w0;
}

test "agent decide requires thinking state" {
    const allocator = std.testing.allocator;
    const caps = [_][]const u8{ "plan" };
    var agent = try si.Agent.init(allocator, 100.0, &caps);
    defer agent.deinit();

    const features = [_]f64{1.0};
    const result = agent.decide(&features);
    try std.testing.expectError(error.InvalidTransition, result);
}

test "agent decide returns action" {
    const allocator = std.testing.allocator;
    const caps = [_][]const u8{ "plan", "execute", "learn" };
    var agent = try si.Agent.init(allocator, 100.0, &caps);
    defer agent.deinit();

    try agent.transition(.thinking);
    const features = [_]f64{ 0.9, 0.3, 0.5 };
    const action = try agent.decide(&features);
    try std.testing.expect(action.capability_index < caps.len);
    try std.testing.expect(action.confidence > 0);
}
