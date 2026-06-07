const std = @import("std");
const si = @import("si");

test "power iteration finds eigenvalues" {
    const allocator = std.testing.allocator;
    const matrix = [_][]const f64{
        &[_]f64{ 2.0, 0.0 },
        &[_]f64{ 0.0, 1.0 },
    };
    const result = try si.spectral.powerIteration(allocator, &matrix, 100);
    defer result.deinit();
    try std.testing.expect(result.eigenvalues.len == 2);
    // Should find eigenvalues 2.0 and 1.0
    var found_two = false;
    var found_one = false;
    for (result.eigenvalues) |ev| {
        if (std.math.approxEqAbs(f64, @abs(ev), 2.0, 0.1)) found_two = true;
        if (std.math.approxEqAbs(f64, @abs(ev), 1.0, 0.1)) found_one = true;
    }
    try std.testing.expect(found_two);
    try std.testing.expect(found_one);
}

test "rank sorts by eigenvalue magnitude" {
    const allocator = std.testing.allocator;
    const matrix = [_][]const f64{
        &[_]f64{ 5.0, 0.0, 0.0 },
        &[_]f64{ 0.0, 2.0, 0.0 },
        &[_]f64{ 0.0, 0.0, 1.0 },
    };
    const ranked = try si.spectral.rank(allocator, &matrix, 200);
    defer allocator.free(ranked);
    try std.testing.expect(ranked[0] == 0); // largest eigenvalue first
}

test "topK returns top k indices" {
    const allocator = std.testing.allocator;
    const matrix = [_][]const f64{
        &[_]f64{ 4.0, 0.0 },
        &[_]f64{ 0.0, 1.0 },
    };
    const top = try si.spectral.topK(allocator, &matrix, 1, 100);
    defer allocator.free(top);
    try std.testing.expect(top.len == 1);
    try std.testing.expect(top[0] == 0);
}

test "condition number diagonal" {
    const allocator = std.testing.allocator;
    const matrix = [_][]const f64{
        &[_]f64{ 10.0, 0.0 },
        &[_]f64{ 0.0, 2.0 },
    };
    const cn = try si.spectral.conditionNumber(allocator, &matrix, 200);
    try std.testing.expect(std.math.approxEqAbs(f64, cn, 5.0, 0.2));
}

test "condition number identity" {
    const allocator = std.testing.allocator;
    const matrix = [_][]const f64{
        &[_]f64{ 1.0, 0.0 },
        &[_]f64{ 0.0, 1.0 },
    };
    const cn = try si.spectral.conditionNumber(allocator, &matrix, 200);
    try std.testing.expect(std.math.approxEqAbs(f64, cn, 1.0, 0.1));
}
