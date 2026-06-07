const std = @import("std");
const Allocator = std.mem.Allocator;

pub const CapabilityManifest = struct {
    name: []const u8,
    layer: []const u8,
    provides: []const []const u8,
    requires: []const []const u8,
};

pub const IntegrationSuggestion = struct {
    from: []const u8,
    to: []const u8,
    reason: []const u8,
    priority: f64,
};

pub const ParseError = error{
    InvalidToml,
    MissingField,
    OutOfMemory,
};

pub fn parseCapabilityToml(allocator: Allocator, content: []const u8) ParseError!CapabilityManifest {
    var name: ?[]const u8 = null;
    var layer: ?[]const u8 = null;
    var provides = std.ArrayList([]const u8).init(allocator);
    var requires = std.ArrayList([]const u8).init(allocator);
    defer {
        for (provides.items) |p| allocator.free(p);
        provides.deinit();
        for (requires.items) |p| allocator.free(p);
        requires.deinit();
    }

    var lines = std.mem.splitSequence(u8, content, "\n");
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        if (std.mem.startsWith(u8, line, "[")) continue; // skip section headers

        const eq_pos = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = std.mem.trim(u8, line[0..eq_pos], " \t");
        const val = std.mem.trim(u8, line[eq_pos + 1 ..], " \t");

        // Strip quotes
        const v = if (val.len >= 2 and val[0] == '"' and val[val.len - 1] == '"')
            val[1 .. val.len - 1]
        else
            val;

        if (std.mem.eql(u8, key, "name")) {
            name = v;
        } else if (std.mem.eql(u8, key, "layer")) {
            layer = v;
        } else if (std.mem.eql(u8, key, "provides")) {
            // Parse comma-separated list
            var items = std.mem.splitSequence(u8, v, ",");
            while (items.next()) |item| {
                const trimmed = std.mem.trim(u8, item, " \"\t");
                const owned = try allocator.dupe(u8, trimmed);
                try provides.append(owned);
            }
        } else if (std.mem.eql(u8, key, "requires")) {
            var items = std.mem.splitSequence(u8, v, ",");
            while (items.next()) |item| {
                const trimmed = std.mem.trim(u8, item, " \"\t");
                const owned = try allocator.dupe(u8, trimmed);
                try requires.append(owned);
            }
        }
    }

    if (name == null) return error.MissingField;
    if (layer == null) return error.MissingField;

    const provides_owned = try allocator.dupe([]const u8, provides.items);
    const requires_owned = try allocator.dupe([]const u8, requires.items);

    return .{
        .name = name.?,
        .layer = layer.?,
        .provides = provides_owned,
        .requires = requires_owned,
    };
}

pub fn scanDirectory(allocator: Allocator, dir_path: []const u8) ![]CapabilityManifest {
    var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
    defer dir.close();

    var manifests = std.ArrayList(CapabilityManifest).init(allocator);
    errdefer manifests.deinit();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".toml")) continue;

        const file = try dir.openFile(entry.name, .{});
        defer file.close();

        const contents = try file.readToEndAlloc(allocator, 1024 * 1024);
        defer allocator.free(contents);

        const manifest = try parseCapabilityToml(allocator, contents);
        try manifests.append(manifest);
    }

    return manifests.toOwnedSlice();
}

pub fn suggestIntegrations(allocator: Allocator, manifests: []const CapabilityManifest) ![]IntegrationSuggestion {
    var suggestions = std.ArrayList(IntegrationSuggestion).init(allocator);
    errdefer suggestions.deinit();

    for (manifests, 0..) |a, i| {
        for (manifests[i + 1 ..]) |b| {
            // Check if a provides what b requires
            var match_count: f64 = 0;
            for (a.provides) |p| {
                for (b.requires) |r| {
                    if (std.mem.eql(u8, p, r)) match_count += 1.0;
                }
            }
            if (match_count > 0) {
                const reason = try std.fmt.allocPrint(allocator, "{s} provides capabilities needed by {s}", .{ a.name, b.name });
                try suggestions.append(.{
                    .from = a.name,
                    .to = b.name,
                    .reason = reason,
                    .priority = match_count,
                });
            }

            // Check reverse
            match_count = 0;
            for (b.provides) |p| {
                for (a.requires) |r| {
                    if (std.mem.eql(u8, p, r)) match_count += 1.0;
                }
            }
            if (match_count > 0) {
                const reason = try std.fmt.allocPrint(allocator, "{s} provides capabilities needed by {s}", .{ b.name, a.name });
                try suggestions.append(.{
                    .from = b.name,
                    .to = a.name,
                    .reason = reason,
                    .priority = match_count,
                });
            }
        }
    }

    return suggestions.toOwnedSlice();
}

test "parse basic toml" {
    const allocator = std.testing.allocator;
    const content =
        \\[capability]
        \\name = "planner"
        \\layer = "L2"
        \\provides = "plan, schedule"
        \\requires = "context"
    ;
    const m = try parseCapabilityToml(allocator, content);
    try std.testing.expectEqualStrings("planner", m.name);
    try std.testing.expectEqualStrings("L2", m.layer);
}

test "parse missing name" {
    const allocator = std.testing.allocator;
    const content =
        \\[capability]
        \\layer = "L1"
    ;
    const result = parseCapabilityToml(allocator, content);
    try std.testing.expectError(error.MissingField, result);
}

test "suggest integrations" {
    const allocator = std.testing.allocator;
    const manifests = [_]CapabilityManifest{
        .{ .name = "ctx", .layer = "L1", .provides = &.{"context"}, .requires = &.{} },
        .{ .name = "planner", .layer = "L2", .provides = &.{"plan"}, .requires = &.{"context"} },
    };
    const suggestions = try suggestIntegrations(allocator, &manifests);
    defer allocator.free(suggestions);
    try std.testing.expect(suggestions.len >= 1);
}
