const std = @import("std");

const maxIgnorePatternLength: u32 = 1024;
const maxIgnoreFilenameLength: u32 = 1024;

fn trim(str: []u8) []u8 {
    var first: u64 = 0;

    while (first < str.len and str[first] == ' ') {
        first += 1;
    }

    var last: u64 = str.len;

    while (last > 0 and str[last - 1] == ' ') {
        last -= 1;
    }

    return str[first..last];
}

pub fn main() anyerror!u8 {
    const fs = std.fs;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = &arena.allocator;

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(&arena.allocator, args);

    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    if (args.len != 2) {
        try stderr.print("Usage: {s} <root of path to sync>\n", .{args[0]});
        return 1;
    }

    const rootPath = args[1];

    const stdin = std.io.getStdIn().reader();
    var buffer: [maxIgnoreFilenameLength]u8 = undefined;

    while (try stdin.readUntilDelimiterOrEof(&buffer, '\n')) |arg| {
        const realPath = fs.realpathAlloc(allocator, arg) catch |err| switch (err) {
            error.FileNotFound => {
                try stderr.print("Failed to find file {s}\n", .{arg});
                return err;
            },
            else => {
                return err;
            },
        };
        defer allocator.free(realPath);

        const absDir = fs.path.dirname(realPath) orelse {
            try stderr.print("Could not get directory of file {s}\n", .{realPath});
            return error.DirNotFound;
        };

        const file = fs.openFileAbsolute(realPath, .{ .read = true }) catch |err| switch (err) {
            error.FileNotFound => {
                try stderr.print("Failed to read file {s}\n", .{realPath});
                return err;
            },
            else => {
                return err;
            },
        };
        defer file.close();

        const reader = file.reader();

        while (true) {
            var line: []u8 = reader.readUntilDelimiterOrEofAlloc(allocator, '\n', maxIgnorePatternLength) catch |err| switch (err) {
                error.StreamTooLong => {
                    try stderr.print("File '{s}'' has lines which are too long\n", .{realPath});
                    break;
                },
                else => {
                    try stdout.print("Error during read of file '{s}'\n", .{err});
                    return err;
                },
            } orelse {
                break;
            };

            if (line.len == 0) {
                continue;
            }

            line = trim(line);

            // .gitignore comment or inverted pattern
            if (line[0] == '#' or line[0] == '!') {
                continue;
            }

            var joined: []u8 = &.{};

            if (line[0] == '/') {
                joined = try fs.path.join(allocator, &.{ absDir, line });
            } else {
                joined = try fs.path.join(allocator, &.{ absDir, "**", line });
            }
            defer allocator.free(joined);

            const relative = try fs.path.relative(allocator, rootPath, joined);
            defer allocator.free(relative);

            if (joined[joined.len - 1] != '/') {
                try stdout.print("{s}\n", .{relative});
            }

            const globJoined = try fs.path.join(allocator, &.{ relative, "**" });
            defer allocator.free(globJoined);

            try stdout.print("{s}\n", .{globJoined});
        }
    }

    return 0;
}
