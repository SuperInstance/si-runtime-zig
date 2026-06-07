const std = @import("std");

pub const ConservationError = error{ConservationViolation};

pub const AuditReport = struct {
    gamma: f64,
    eta: f64,
    total: f64,
    utilization: f64,

    pub fn format(self: AuditReport, writer: anytype) !void {
        try writer.print("AuditReport{{ .gamma = {d:.4}, .eta = {d:.4}, .total = {d:.4}, .utilization = {d:.2}% }}", .{
            self.gamma, self.eta, self.total, self.utilization * 100.0,
        });
    }
};

pub const ConservationBudget = struct {
    gamma: f64,
    eta: f64,
    total: f64,

    const Self = @This();

    pub fn init(total: f64) Self {
        return .{
            .gamma = total / 2.0,
            .eta = total / 2.0,
            .total = total,
        };
    }

    pub fn allocate(self: *Self, gamma: f64, eta: f64) ConservationError!void {
        if (gamma < 0 or eta < 0) return error.ConservationViolation;
        if (gamma + eta > self.total) return error.ConservationViolation;
        self.gamma = gamma;
        self.eta = eta;
    }

    pub fn transfer(self: *Self, from_gamma: bool, amount: f64) ConservationError!void {
        if (amount < 0) return error.ConservationViolation;
        if (from_gamma) {
            if (self.gamma < amount) return error.ConservationViolation;
            self.gamma -= amount;
            self.eta += amount;
        } else {
            if (self.eta < amount) return error.ConservationViolation;
            self.eta -= amount;
            self.gamma += amount;
        }
        if (std.math.approxEqAbs(f64, self.gamma + self.eta, self.total, 1e-10) == false) {
            return error.ConservationViolation;
        }
    }

    pub fn audit(self: *const Self) ConservationError!AuditReport {
        if (!std.math.approxEqAbs(f64, self.gamma + self.eta, self.total, 1e-10))
            return error.ConservationViolation;
        return .{
            .gamma = self.gamma,
            .eta = self.eta,
            .total = self.total,
            .utilization = if (self.total > 0) 1.0 - (self.gamma + self.eta - @abs(self.gamma - self.eta)) / (2.0 * self.total) else 0,
        };
    }
};

test "conservation init" {
    const b = ConservationBudget.init(100.0);
    try std.testing.expectEqual(@as(f64, 100.0), b.total);
    try std.testing.expect(std.math.approxEqAbs(f64, b.gamma + b.eta, b.total, 1e-10));
}

test "conservation allocate" {
    var b = ConservationBudget.init(100.0);
    try b.allocate(30.0, 70.0);
    try std.testing.expectEqual(@as(f64, 30.0), b.gamma);
    try std.testing.expectEqual(@as(f64, 70.0), b.eta);
}

test "conservation violation" {
    var b = ConservationBudget.init(100.0);
    const result = b.allocate(60.0, 60.0);
    try std.testing.expectError(error.ConservationViolation, result);
}

test "conservation transfer" {
    var b = ConservationBudget.init(100.0);
    try b.transfer(true, 10.0);
    try std.testing.expectEqual(@as(f64, 40.0), b.gamma);
    try std.testing.expectEqual(@as(f64, 60.0), b.eta);
}

test "conservation audit" {
    var b = ConservationBudget.init(100.0);
    const report = try b.audit();
    try std.testing.expectEqual(@as(f64, 100.0), report.total);
}
