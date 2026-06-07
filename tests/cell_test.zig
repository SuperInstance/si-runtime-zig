const std = @import("std");
const si = @import("si");

fn echoHandler(input: []const u8) []const u8 {
    return input;
}

test "cell init and execute" {
    const allocator = std.testing.allocator;
    var cell = si.Cell.init(allocator, "test_cell", 100.0, echoHandler);
    defer cell.deinit();
    const result = try cell.execute("hello");
    try std.testing.expectEqualStrings("hello", result.output);
    try std.testing.expect(result.cost > 0);
    try std.testing.expect(result.budget_remaining < 100.0);
}

test "cell budget enforcement" {
    const allocator = std.testing.allocator;
    var cell = si.Cell.init(allocator, "tiny", 0.001, echoHandler);
    defer cell.deinit();
    const result = cell.execute("this is a very long input string that should exceed the tiny budget");
    try std.testing.expectError(error.BudgetExhausted, result);
}

test "cell add dependency" {
    const allocator = std.testing.allocator;
    var cell = si.Cell.init(allocator, "dep_cell", 100.0, echoHandler);
    defer cell.deinit();
    try cell.addDep("other");
    try cell.addDep("another");
    try std.testing.expect(cell.deps.items.len == 2);
    try std.testing.expectEqualStrings("other", cell.deps.items[0]);
    try std.testing.expectEqualStrings("another", cell.deps.items[1]);
}

test "cell composition" {
    const allocator = std.testing.allocator;
    var a = si.Cell.init(allocator, "cell_a", 100.0, echoHandler);
    defer a.deinit();
    var b = si.Cell.init(allocator, "cell_b", 100.0, echoHandler);
    defer b.deinit();
    var composed = try si.cell.compose(allocator, &a, &b);
    defer composed.deinit();
    try std.testing.expectEqualStrings("composed", composed.name);
    // Should have deps from both cells
    try std.testing.expect(composed.deps.items.len >= 2);
}

test "cell multiple executions drain budget" {
    const allocator = std.testing.allocator;
    var cell = si.Cell.init(allocator, "drain", 1.0, echoHandler);
    defer cell.deinit();
    // Execute until budget exhausted
    var exhausted = false;
    for (0..1000) |_| {
        const result = cell.execute("test");
        if (result == error.BudgetExhausted) {
            exhausted = true;
            break;
        }
    }
    try std.testing.expect(exhausted);
}
