const std = @import("std");
const si = @import("si");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const stdout = std.io.getStdOut().writer();

    try stdout.print("=== SuperInstance Runtime Demo ===\n\n", .{});

    // 1. Conservation budget
    try stdout.print("[Conservation Budget]\n", .{});
    var budget = si.ConservationBudget.init(100.0);
    try budget.allocate(40.0, 60.0);
    const report = try budget.audit();
    try stdout.print("  gamma={d:.1} eta={d:.1} total={d:.1}\n\n", .{ report.gamma, report.eta, report.total });

    // 2. Agent lifecycle
    try stdout.print("[Agent Lifecycle]\n", .{});
    const caps = [_][]const u8{ "planner", "executor", "learner", "observer" };
    var agent = try si.Agent.init(allocator, 200.0, &caps);
    defer agent.deinit();
    try stdout.print("  initial state: {s}\n", .{@tagName(agent.state)});

    try agent.transition(.thinking);
    try stdout.print("  -> thinking\n", .{});

    // Decide with task features
    const features = [_]f64{ 0.8, 0.3, 0.5, 0.1 };
    const action = try agent.decide(&features);
    try stdout.print("  decided: capability[{d}] = \"{s}\" (confidence={d:.3})\n", .{
        action.capability_index,
        caps[action.capability_index],
        action.confidence,
    });

    try agent.transition(.executing);
    try agent.transition(.learning);
    agent.learn(1.0, 0.2);
    try agent.transition(.idle);
    try stdout.print("  back to idle. weights: ", .{});
    for (agent.weights, 0..) |w, i| {
        if (i > 0) try stdout.print(", ", .{});
        try stdout.print("{s}={d:.3}", .{ caps[i], w });
    }
    try stdout.print("\n\n", .{});

    // 3. Cell execution
    try stdout.print("[Cell Execution]\n", .{});
    const testHandler = struct {
        pub fn handler(input: []const u8) []const u8 {
            return input;
        }
    }.handler;
    var cell = si.Cell.init(allocator, "demo_cell", 50.0, testHandler);
    defer cell.deinit();
    try cell.addDep("planner");

    const result = try cell.execute("hello world");
    try stdout.print("  cell \"{s}\" executed: output=\"{s}\" cost={d:.4} remaining={d:.4}\n\n", .{
        cell.name,
        result.output,
        result.cost,
        result.budget_remaining,
    });

    // 4. Spectral ranking
    try stdout.print("[Spectral Ranking]\n", .{});
    const matrix = [_][]const f64{
        &[_]f64{ 4.0, 1.0, 0.0 },
        &[_]f64{ 1.0, 3.0, 1.0 },
        &[_]f64{ 0.0, 1.0, 2.0 },
    };
    const ranked = try si.spectral.rank(allocator, &matrix, 200);
    defer allocator.free(ranked);
    try stdout.print("  ranked indices: ", .{});
    for (ranked, 0..) |idx, i| {
        if (i > 0) try stdout.print(", ", .{});
        try stdout.print("{d}", .{idx});
    }
    try stdout.print("\n", .{});

    const cn = try si.spectral.conditionNumber(allocator, &matrix, 200);
    try stdout.print("  condition number: {d:.3}\n", .{cn});

    try stdout.print("\n=== Demo Complete ===\n", .{});
}
