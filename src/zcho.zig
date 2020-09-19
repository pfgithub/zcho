const std = @import("std");

pub fn main() !u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = &arena.allocator;
    var args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const stdout_stream = std.io.getStdOut().writer();
    var buffered_out_stream = std.io.bufferedWriter(stdout_stream);
    const out = buffered_out_stream.writer();

    const EscapeMode = enum { raw, escape, unescape }; // urlencode option? might be neat
    var opts: struct {
        escape: EscapeMode = .raw, // -e, -E, -p
        newline: bool = true, // -n sets it false
        spaces: bool = true, // -s sets it false
        options: bool = true, // false after the first non-option
    } = .{};
    var first = true;

    for (args[1..]) |arg, i| {
        if (opts.options) ifblk: {
            if (arg.len < 2) {
                opts.options = false;
                break :ifblk;
            }
            if (arg[0] != '-') break :ifblk;
            if(std.mem.eql(u8, arg, "--")) {
                opts.options = false;
                continue;
            }
            // if(std.mem.eql(u8, arg, "--print-mode"))
            //    :: read next arg (not easy to do, requires making ArgIter)
            // if(std.mem.startsWith(u8, arg, "--print-mode="))
            //    :: same as above, but arg["--print-mode=".len..]
            if(for(arg[1..]) |char| switch(char) {'e', 'E', 'p', 'n', 's', 'h' => {}, else => break true} else false) {
                opts.options = false;
                continue;
            }
            for (arg[1..]) |char| switch (char) {
                'e' => opts.escape = .unescape,
                'E' => opts.escape = .raw,
                'p' => opts.escape = .escape,
                'n' => opts.newline = false,
                's' => opts.spaces = false,
                'h' => {try printHelp(out); break;},
                else => unreachable, // caught above
            };
            continue;
        }
        opts.options = false;
        if (opts.spaces and !first) try out.writeByte(' ');
        first = false;
        switch (opts.escape) {
            .escape => try writeEscape(out, arg),
            .unescape => if (try writeUnescape(out, arg)) break,
            .raw => try out.writeAll(arg),
        }
    }
    if (opts.newline) try out.writeByte('\n');
    try buffered_out_stream.flush();
    return 0;
}

fn printHelp(out: anytype) @TypeOf(out).Error!void {
    try out.writeAll(
        \\Usage:
        \\    zcho [options] [message]
        \\Options:
        \\    -E: Set print mode: raw (default)
        \\    -e: Set print mode: backslash escape interpolation
        \\    -p: Set print mode: escaped printing
        \\    -n: Do not output a newline
        \\    -s: Do not seperate message with spaces
        \\    -h: Print this message
        \\    --: Stop parsing options
        \\Escape Sequences (for -e):
        \\    \\, \a, \b, \c, \d, \e, \f, \n, \r, \t, \v
        \\    \0NNN with octal value NNN (1-3 digits)
        \\    \xHH with hex value HH (1-2 digits)
    );
}

fn writeEscape(out: anytype, arg: []const u8) @TypeOf(out).Error!void {
    for (arg) |char| switch (char) {
        ' '...'[', ']'...'~' => try out.writeByte(char),
        '\\' => try out.writeAll("\\\\"),
        else => {
            try out.print("\\x{x:0<2}", .{char});
        },
    };
}

const StringIter = struct {
    string: []const u8,
    idx: usize = 0,
    fn nextByte(si: *StringIter) ?u8 {
        defer si.idx += 1;
        return si.peekByte();
    }
    fn peekByte(si: *StringIter) ?u8 {
        if(si.idx < si.string.len) return si.string[si.idx];
        return null;
    }
};

// use charToDigit
fn readNum(si: *StringIter, comptime max: usize, radix: u8) ?u8 {
    var buf = [1]u8{undefined} ** max;
    const valslice = blk: {
        var i: usize = 0;
        while(i < max) : (i += 1) {
            const dechar = si.peekByte() orelse break :blk buf[0..i];
            _ = std.fmt.charToDigit(dechar, radix) catch break :blk buf[0..i];
            buf[i] = si.nextByte().?;
        }
        break :blk buf[0..max];
    };
    const parsed = std.fmt.parseInt(u8, valslice, radix) catch return null;
    return parsed;
}

fn writeUnescape(out: anytype, arg: []const u8) @TypeOf(out).Error!bool {
    var escape = false;
    var si = StringIter{.string = arg};
    while (si.nextByte()) |char| {
        if (!escape and char == '\\') {
            escape = true;
            continue;
        }
        if (escape) switch (char) {
            '\\' => try out.writeByte('\\'),
            'a' => try out.writeByte('\x07'),
            'b' => try out.writeByte('\x08'),
            'c' => return true,
            'e' => try out.writeByte('\x1b'),
            'f' => try out.writeByte('\x0c'),
            'n' => try out.writeByte('\n'),
            'r' => try out.writeByte('\r'),
            't' => try out.writeByte('\t'),
            'v' => try out.writeByte('\x0b'),
            '0' => blk: {
                const sb = si.idx;
                const parsed = readNum(&si, 3, 8) orelse {
                    si.idx = sb;
                    try out.writeAll("\\0");
                    break :blk;
                };
                try out.writeByte(parsed);
            },
            'x' => blk: {
                const sb = si.idx;
                const parsed = readNum(&si, 2, 16) orelse {
                    si.idx = sb;
                    try out.writeAll("\\x");
                    break :blk;
                };
                try out.writeByte(parsed);
            },
            else => try out.writeAll(&[_]u8{ '\\', char }),
        } else try out.writeByte(char);
        escape = false;
    }
    if (escape) try out.writeByte('\\');
    return false;
}
