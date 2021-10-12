const std = @import("std");

const maxIgnorePatternLength: u32 = 1024;

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

pub fn main() anyerror!void {
    const fs = std.fs;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = &arena.allocator;

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(&arena.allocator, args);

    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    for (args[1..]) |arg| {
        const absPath = try fs.path.resolve(allocator, &.{arg});
        defer allocator.free(absPath);

        const basePath = fs.path.dirname(absPath) orelse {
            try stderr.print("Could not get directory of file {s}\n", .{absPath});
            return error.DirNotFound;
        };

        const file = fs.openFileAbsolute(arg, .{ .read = true }) catch |err| switch (err) {
            error.FileNotFound => {
                try stderr.print("Failed to read file {s}\n", .{arg});
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
                    try stderr.print("File '{s}'' has lines which are too long\n", .{arg});
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

            var terminator: u8 = 0;

            if (line[0] == '/') {
                const joined = try fs.path.join(allocator, &.{ basePath, line });
                terminator = joined[joined.len - 1];
                try stdout.print("{s}", .{joined});
            } else {
                const joined = try fs.path.join(allocator, &.{ basePath, "**", line });
                terminator = joined[joined.len - 1];
                try stdout.print("{s}", .{joined});
            }

            if (terminator == '/') {
                try stdout.print("**", .{});
            }

            try stdout.print("\n", .{});
        }
    }
}
