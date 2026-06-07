const std = @import("std");
const Allocator = std.mem.Allocator;

pub const PowerIterationResult = struct {
    eigenvalues: []f64,
    eigenvectors: [][]f64,
    allocator: Allocator,

    pub fn deinit(self: *const PowerIterationResult) void {
        self.allocator.free(self.eigenvalues);
        for (self.eigenvectors) |vec| {
            self.allocator.free(vec);
        }
        self.allocator.free(self.eigenvectors);
    }
};

fn matVecMul(allocator: Allocator, matrix: []const []const f64, vec: []const f64) ![]f64 {
    const n = matrix.len;
    var result = try allocator.alloc(f64, n);
    @memset(result, 0);
    for (matrix, 0..) |row, i| {
        for (row, 0..) |val, j| {
            result[i] += val * vec[j];
        }
    }
    return result;
}

fn normalize(vec: []f64) f64 {
    var norm: f64 = 0;
    for (vec) |v| norm += v * v;
    norm = std.math.sqrt(norm);
    if (norm > 1e-12) {
        for (vec) |*v| v.* /= norm;
    }
    return norm;
}

pub fn powerIteration(allocator: Allocator, matrix: []const []const f64, iterations: u32) !PowerIterationResult {
    const n = matrix.len;
    const eigenvalues = try allocator.alloc(f64, n);
    const eigenvectors = try allocator.alloc([]f64, n);

    // Track which dimensions we've found
    const found = try allocator.alloc(bool, n);
    defer allocator.free(found);
    @memset(@constCast(found), false);

    // Residual matrix for deflation
    const residual = try allocator.alloc([]f64, n);
    for (0..n) |i| {
        residual[i] = try allocator.alloc(f64, n);
        @memcpy(residual[i], matrix[i]);
    }
    defer {
        for (residual) |row| allocator.free(row);
        allocator.free(residual);
    }

    const buf = try allocator.alloc(f64, n);
    defer allocator.free(buf);

    for (0..n) |k| {
        // Initialize with random-ish seed based on index
        var v = try allocator.alloc(f64, n);
        for (0..n) |j| v[j] = @sin(@as(f64, @floatFromInt(j + k * 7 + 1)) * 1.23456);
        _ = normalize(v);

        var eigenval: f64 = 0;
        var mu: [2]f64 = .{ 0, 0 };

        for (0..iterations) |_| {
            const Av = try matVecMul(allocator, residual, v);
            defer allocator.free(Av);
            @memcpy(buf, Av);

            // Rayleigh quotient
            eigenval = 0;
            for (0..n) |j| eigenval += v[j] * buf[j];

            _ = normalize(buf);
            @memcpy(v, buf);

            // Convergence check
            const new_mu: f64 = eigenval;
            if (@abs(new_mu - mu[1]) < 1e-10 and @abs(mu[1] - mu[0]) < 1e-10) break;
            mu[0] = mu[1];
            mu[1] = new_mu;
        }

        eigenvalues[k] = eigenval;
        eigenvectors[k] = v;

        // Deflate: R = R - lambda * v * v^T
        for (0..n) |i| {
            for (0..n) |j| {
                residual[i][j] -= eigenval * v[i] * v[j];
            }
        }
    }

    return .{
        .eigenvalues = eigenvalues,
        .eigenvectors = eigenvectors,
        .allocator = allocator,
    };
}

pub fn rank(allocator: Allocator, matrix: []const []const f64, iterations: u32) ![]usize {
    const result = try powerIteration(allocator, matrix, iterations);
    defer result.deinit();
    const n = result.eigenvalues.len;

    const indices = try allocator.alloc(usize, n);
    for (indices, 0..) |*idx, i| idx.* = i;

    // Sort by eigenvalue magnitude descending
    const SortCtx = struct {
        eigenvalues: []const f64,
        pub fn lessThan(ctx: @This(), a: usize, b: usize) bool {
            return @abs(ctx.eigenvalues[a]) > @abs(ctx.eigenvalues[b]);
        }
    };
    std.sort.insertion(usize, @constCast(indices), SortCtx{ .eigenvalues = result.eigenvalues }, SortCtx.lessThan);

    return indices;
}

pub fn topK(allocator: Allocator, matrix: []const []const f64, k: usize, iterations: u32) ![]usize {
    const ranked = try rank(allocator, matrix, iterations);
    const count = @min(k, ranked.len);
    const result = try allocator.alloc(usize, count);
    @memcpy(@constCast(result), ranked[0..count]);
    allocator.free(ranked);
    return result;
}

pub fn conditionNumber(allocator: Allocator, matrix: []const []const f64, iterations: u32) !f64 {
    const result = try powerIteration(allocator, matrix, iterations);
    defer result.deinit();

    var max_abs: f64 = 0;
    var min_abs: f64 = std.math.floatMax(f64);
    for (result.eigenvalues) |ev| {
        const mag = @abs(ev);
        if (mag > max_abs) max_abs = mag;
        if (mag < min_abs and mag > 1e-15) min_abs = mag;
    }
    if (min_abs < 1e-15) return std.math.inf(f64);
    return max_abs / min_abs;
}

test "power iteration basic" {
    const allocator = std.testing.allocator;
    const matrix = &[_][]const f64{
        &[_]f64{ 4.0, 1.0 },
        &[_]f64{ 1.0, 3.0 },
    };
    const result = try powerIteration(allocator, &matrix, 200);
    defer result.deinit();
    try std.testing.expect(result.eigenvalues.len == 2);
    // Largest eigenvalue should be ~4.618
    var max_ev: f64 = 0;
    for (result.eigenvalues) |ev| {
        if (@abs(ev) > @abs(max_ev)) max_ev = ev;
    }
    try std.testing.expect(std.math.approxEqAbs(f64, @abs(max_ev), 4.618, 0.1));
}

test "rank" {
    const allocator = std.testing.allocator;
    const matrix = &[_][]const f64{
        &[_]f64{ 4.0, 1.0 },
        &[_]f64{ 1.0, 3.0 },
    };
    const ranked = try rank(allocator, &matrix, 200);
    defer allocator.free(ranked);
    try std.testing.expect(ranked.len == 2);
}

test "condition number" {
    const allocator = std.testing.allocator;
    const matrix = &[_][]const f64{
        &[_]f64{ 4.0, 0.0 },
        &[_]f64{ 0.0, 2.0 },
    };
    const cn = try conditionNumber(allocator, &matrix, 200);
    try std.testing.expect(std.math.approxEqAbs(f64, cn, 2.0, 0.1));
}

test "topK" {
    const allocator = std.testing.allocator;
    const matrix = &[_][]const f64{
        &[_]f64{ 4.0, 1.0 },
        &[_]f64{ 1.0, 3.0 },
    };
    const top = try topK(allocator, &matrix, 1, 200);
    defer allocator.free(top);
    try std.testing.expect(top.len == 1);
}
