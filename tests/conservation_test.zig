const std = @import("std");
const si = @import("si");

test "conservation init splits evenly" {
    const b = si.ConservationBudget.init(200.0);
    try std.testing.expectEqual(@as(f64, 200.0), b.total);
    try std.testing.expect(std.math.approxEqAbs(f64, b.gamma + b.eta, b.total, 1e-10));
}

test "conservation allocate valid" {
    var b = si.ConservationBudget.init(100.0);
    try b.allocate(30.0, 70.0);
    try std.testing.expectEqual(@as(f64, 30.0), b.gamma);
    try std.testing.expectEqual(@as(f64, 70.0), b.eta);
}

test "conservation allocate overflow" {
    var b = si.ConservationBudget.init(100.0);
    try std.testing.expectError(error.ConservationViolation, b.allocate(60.0, 60.0));
}

test "conservation allocate negative" {
    var b = si.ConservationBudget.init(100.0);
    try std.testing.expectError(error.ConservationViolation, b.allocate(-10.0, 50.0));
}

test "conservation transfer gamma to eta" {
    var b = si.ConservationBudget.init(100.0);
    try b.transfer(true, 10.0);
    try std.testing.expectEqual(@as(f64, 40.0), b.gamma);
    try std.testing.expectEqual(@as(f64, 60.0), b.eta);
}

test "conservation transfer eta to gamma" {
    var b = si.ConservationBudget.init(100.0);
    try b.transfer(false, 10.0);
    try std.testing.expectEqual(@as(f64, 60.0), b.gamma);
    try std.testing.expectEqual(@as(f64, 40.0), b.eta);
}

test "conservation transfer too much" {
    var b = si.ConservationBudget.init(100.0);
    try std.testing.expectError(error.ConservationViolation, b.transfer(true, 100.0));
}

test "conservation audit report" {
    var b = si.ConservationBudget.init(100.0);
    try b.allocate(40.0, 60.0);
    const report = try b.audit();
    try std.testing.expectEqual(@as(f64, 40.0), report.gamma);
    try std.testing.expectEqual(@as(f64, 60.0), report.eta);
    try std.testing.expectEqual(@as(f64, 100.0), report.total);
}
