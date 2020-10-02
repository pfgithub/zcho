const std = @import("std");

const help = @import("main.zig");
const cli = @import("lib/cli.zig");

fn renderJsonNode(out: anytype, key: []const u8, value: *const std.json.Value, indent: u32) @TypeOf(out).Error!void {
    const collapsible = switch (value.*) {
        .Object => true,
        .Array => true,
        .Float => false,
        .String => false,
        .Integer => false,
        .Bool => false,
        .Null => false,
    };
    var i: u32 = 0;
    while (i < indent) : (i += 1) {
        try out.print("│", .{}); // ╵ todo
    }
    try out.print("{} {}", .{ if (collapsible) @as([]const u8, "-") else "▾", key });
    switch (value.*) {
        .Object => |obj| {
            std.debug.warn("\n", .{});
            var iter = obj.iterator();
            while (iter.next()) |kv| {
                try renderJsonNode(out, kv.key, &kv.value, indent + 1);
            }
        },
        .Array => |arr| {
            std.debug.warn("\n", .{});
            for (arr.items) |itm| {
                try renderJsonNode(out, "0:", &itm, indent + 1);
            }
        },
        .String => |str| {
            try out.print(" \"{}\"\n", .{str});
        },
        .Float => |f| try out.print(" {d}\n", .{f}),
        .Integer => |f| try out.print(" {d}\n", .{f}),
        .Bool => |f| try out.print(" {}\n", .{f}),
        .Null => try out.print(" null\n", .{}),
    }
}
const Themes = [_]Theme{
    Theme.from(.{ .brred, .bryellow, .brgreen, .brcyan, .brblue, .brmagenta }),
    Theme.from(.{ .brmagenta, .bryellow, .brblue }),
    Theme.from(.{ .bryellow, .brwhite, .magenta }),
    Theme.from(.{ .brblue, .brmagenta, .brwhite, .brmagenta }),
    Theme.from(.{ .brmagenta, .brwhite, .brgreen }),
};
const Theme = struct {
    colors: []const cli.Color,
    pub fn from(comptime items: anytype) Theme {
        var res: []const cli.Color = &[_]cli.Color{};
        for (items) |item| {
            res = res ++ &[_]cli.Color{cli.Color.from(item)};
        }
        return Theme{ .colors = res };
    }
};

const Point = struct { x: u32, y: u32 };
const Selection = struct {
    hover: ?Point,
    mouseup: bool,
    rerender: bool,
};
const Path = struct {
    const ALEntry = struct {
        index: usize,
    };
    al: std.ArrayList(ALEntry),
    fn init(alloc: *std.mem.Allocator) !Path {
        var al = std.ArrayList(ALEntry).init(alloc);
        errdefer al.deinit();
        try al.append(.{ .index = 0 });
        return Path{
            .al = al,
        };
    }
    fn deinit(path: *Path) void {
        path.al.deinit();
        path.* = undefined;
    }
    fn last(path: Path) *ALEntry {
        return &path.al.items[path.al.items.len - 1];
    }
    fn fixClosed(path: *Path, root: *JsonRender) void {
        var res = root;
        for (path.al.items) |itm, i| {
            if (res.childNodes.len == 0) return;
            res = &res.childNodes[itm.index].value;
            if (!res.open) {
                path.al.items.len = i + 1;
                return;
            }
        }
    }
    fn getNode(path: Path, root: *JsonRender) *JsonRender {
        var res = root;
        for (path.al.items) |itm| {
            res = &res.childNodes[itm.index].value;
        }
        return res;
    }
    fn getNodeMinusOne(path: Path, root: *JsonRender) *JsonRender {
        var res = root;
        for (path.al.items[0 .. path.al.items.len - 1]) |itm| {
            res = &res.childNodes[itm.index].value;
        }
        return res;
    }
    pub fn advance(path: *Path, root: *JsonRender) !void {
        // get the node
        var thisNode = path.getNode(root);
        if (thisNode.childNodes.len > 0 and thisNode.open) {
            try path.al.append(.{ .index = 0 });
            return;
        }
        var last_ = path.last();
        var node = path.getNodeMinusOne(root);
        while (last_.index + 1 >= node.childNodes.len) {
            if (path.al.items.len <= 1) return; // cannot advance
            _ = path.al.pop();
            last_ = path.last();
            node = path.getNodeMinusOne(root);
        }
        last_.index += 1;
    }
    pub fn devance(path: *Path, root: *JsonRender) !void {
        var last_ = path.last();
        if (last_.index == 0) {
            if (path.al.items.len <= 1) return; // cannot devance
            _ = path.al.pop();
            return;
        }
        last_.index -= 1;
        var lastDeepest = path.getNode(root);
        while (lastDeepest.childNodes.len > 0 and lastDeepest.open) {
            try path.al.append(.{ .index = lastDeepest.childNodes.len - 1 });
            if (lastDeepest.childNodes.len > 0) lastDeepest = &lastDeepest.childNodes[lastDeepest.childNodes.len - 1].value;
        }
    }
    fn forDepth(path: Path, depth: usize) ?ALEntry {
        if (depth >= path.al.items.len) return null;
        return path.al.items[depth];
    }
};

const JsonRender = struct {
    const JsonKey = union(enum) { int: usize, str: []const u8, root };
    const ChildNode = struct { key: JsonKey, value: JsonRender };

    childNodes: []ChildNode,
    content: std.json.Value,
    index: usize,
    open: bool,
    // parent: *JsonRender,

    pub fn init(alloc: *std.mem.Allocator, jsonv: std.json.Value, index: usize) std.mem.Allocator.Error!JsonRender {
        const childNodes = switch (jsonv) {
            .Array => |arr| blk: {
                var childNodesL = try alloc.alloc(ChildNode, arr.items.len);
                errdefer alloc.free(childNodesL);

                for (arr.items) |itm, i| {
                    childNodesL[i] = .{ .key = .{ .int = i }, .value = try JsonRender.init(alloc, itm, i) };
                }

                break :blk childNodesL;
            },
            .Object => |hm| blk: {
                // apparently I should be using a std.ArrayHashMap
                // oh also I need a custom json parser because the stdlib one doesn't preserve order
                var childNodesAL = std.ArrayList(ChildNode).init(alloc);
                errdefer childNodesAL.deinit();

                var iter = hm.iterator();
                var i: usize = 0;
                while (iter.next()) |itm| : (i += 1) {
                    try childNodesAL.append(.{ .key = .{ .str = itm.key }, .value = try JsonRender.init(alloc, itm.value, i) });
                }

                break :blk childNodesAL.toOwnedSlice();
            },
            else => &[_]ChildNode{},
        };
        errdefer alloc.free(childNodes);
        return JsonRender{
            .open = false,
            .childNodes = childNodes,
            .content = jsonv,
            .index = index,
        };
    }
    pub fn deinit(jr: *JsonRender, alloc: *std.mem.Allocator) void {
        alloc.free(jr.childNodes);
    }
    // todo rename JsonRender and move the render fn out of this so it actually holds data rather than
    // being a gui component type thing
};
pub fn renderJson(
    me: *JsonRender,
    out: anytype,
    key: JsonRender.JsonKey,
    x: u32,
    y: u32,
    h: u32,
    theme: Theme,
    themeIndex: usize,
    selection: *Selection,
    startAt: Path,
    depth: ?usize,
) @TypeOf(out).Error!u32 {
    if (y >= h) return 0;

    const pathv = if (depth) |d| if (startAt.forDepth(d)) |v| v.index else 0 else 0;

    const hovering = if (selection.hover) |hov| hov.x >= x and hov.y == y else false;
    const focused = false;
    const bgstyl: ?cli.Color = if (hovering) cli.Color.from(.brblack) else null;

    if (hovering and selection.mouseup) me.open = !me.open;

    try cli.moveCursor(out, x, y);

    const themeStyle: cli.Style = .{ .fg = theme.colors[themeIndex % theme.colors.len], .bg = bgstyl };

    var cy = y;

    // TODO only show the header if startAt < header
    if (true) {
        try cli.setTextStyle(out, themeStyle, null);

        if (me.childNodes.len == 0)
            try out.writeAll("-")
        else if (me.open)
            try out.writeAll("▾")
        else
            try out.writeAll("▸");

        try cli.setTextStyle(out, .{ .bg = bgstyl }, null);

        switch (key) {
            .str => |str| {
                try cli.setTextStyle(out, .{ .fg = cli.Color.from(.white), .bg = bgstyl }, null);
                try out.print(" \"", .{});
                try cli.setTextStyle(out, themeStyle, null);
                try out.print("{}", .{str});
                try cli.setTextStyle(out, .{ .fg = cli.Color.from(.white), .bg = bgstyl }, null);
                try out.print("\"", .{});
                try cli.setTextStyle(out, .{ .bg = bgstyl }, null);
                try out.writeAll(":");
            },
            .int => |int| {
                try cli.setTextStyle(out, themeStyle, null);
                try out.print(" {}", .{int});
                try cli.setTextStyle(out, .{ .bg = bgstyl }, null);
                try out.writeAll(":");
            },
            .root => {},
        }

        switch (me.content) {
            .Array => if (me.childNodes.len == 0) try out.writeAll(" []") else if (!me.open) try out.writeAll(" […]"),
            .Object => if (me.childNodes.len == 0) try out.writeAll(" {}") else if (!me.open) try out.writeAll(" {…}"),
            .String => |str| try out.print(" \"{}\"", .{str}),
            .Float => |f| try out.print(" {d}", .{f}),
            .Integer => |f| try out.print(" {d}", .{f}),
            .Bool => |f| try out.print(" {}", .{f}),
            .Null => try out.print(" null", .{}),
        }

        try cli.clearToEol(out);

        cy += 1;
    }

    try cli.setTextStyle(out, .{}, null);

    if (me.open) for (me.childNodes[pathv..]) |*node, i| {
        if (cy == h) break;
        // check if the next item is on the path
        const onpath = if (depth) |d| i == 0 else false;
        cy += try renderJson(&node.value, out, node.key, x + 2, cy, h, theme, themeIndex + 1, selection, startAt, if (onpath) depth.? + 1 else null);
        if (cy > h) unreachable; // rendered out of screen
    };

    const barhov = if (selection.hover) |hov| hov.x == x and hov.y > y and hov.y < cy else false;
    if (barhov and selection.mouseup) {
        me.open = !me.open;
        selection.rerender = true;
    }

    const fgcolr: cli.Color = if (barhov) cli.Color.from(.brwhite) else cli.Color.from(.brblack);

    try cli.setTextStyle(out, .{ .fg = fgcolr }, null);
    var cyy: u32 = y + 1;
    while (cyy < cy) : (cyy += 1) {
        try cli.moveCursor(out, x, cyy);

        if (cyy + 1 < cy or cyy + 1 == h) try out.writeAll("│")
        // zig-fmt
        else try out.writeAll("╵");
    }

    return cy - y;
}

var globalOT: ?std.os.termios = null;

pub fn panic(msg: []const u8, stack_trace: ?*std.builtin.StackTrace) noreturn {
    const stdinF = std.io.getStdIn();

    cli.stopCaptureMouse() catch {};
    cli.exitFullscreen() catch {};
    if (globalOT) |ot| cli.exitRawMode(stdinF, ot) catch {};

    var out = std.io.getStdOut().writer();
    cli.setTextStyle(out, .{ .fg = cli.Color.from(.brred) }, null) catch {};
    out.print("Panic: {}\n", .{msg}) catch {};

    if (stack_trace) |trace|
        std.debug.dumpStackTrace(trace.*);

    out.print("Consider posting a bug report: https://github.com/pfgithub/jsonexplorer/issues/new\n", .{}) catch {};

    std.os.exit(1);
}

pub const main = help.anyMain(exec);

pub fn exec(exec_args: help.MainFnArgs) !void {
    const alloc = exec_args.allocator;
    const ai = exec_args.args_iter;

    if (ai.next()) |arg| return ai.err("Usage: jsonexplorer < file.json");

    const stdinf = std.io.getStdIn();

    if (std.os.isatty(stdinf.handle)) {
        std.debug.warn("Usage: echo '{{}}' | jsonexplorer\n", .{});
        return;
    }

    std.debug.warn("\r\x1b[KReading File...", .{});

    const jsonTxt = try stdinf.reader().readAllAlloc(alloc, 1000 * 1000 * 1000);
    defer alloc.free(jsonTxt);

    std.debug.warn("\r\x1b[KParsing JSON...", .{});

    var jsonParser = std.json.Parser.init(alloc, false); // copy_strings = false;
    defer jsonParser.deinit();
    var jsonRes = jsonParser.parse(jsonTxt) catch |e| {
        std.debug.warn("\nJSON parsing error: {e}\n", .{e});
        return;
    };
    defer jsonRes.deinit();

    var jsonRoot = &jsonRes.root;

    std.debug.warn("\r\x1b[K", .{});

    var stdin2file = try std.fs.openFileAbsolute("/dev/tty", .{ .read = true });
    defer stdin2file.close();
    var stdin2 = stdin2file.reader();

    const rawMode = try cli.enterRawMode(stdin2file);
    defer cli.exitRawMode(stdin2file, rawMode) catch {};
    globalOT = rawMode;

    cli.enterFullscreen() catch {};
    defer cli.exitFullscreen() catch {};

    cli.startCaptureMouse() catch {};
    defer cli.stopCaptureMouse() catch {};

    var stdoutf = std.io.getStdOut();
    var stdout_buffered = std.io.bufferedWriter(stdoutf.writer());
    const stdout = stdout_buffered.writer();

    var jr = try JsonRender.init(alloc, jsonRoot.*, 0);
    defer jr.deinit(alloc);

    jr.open = true;

    var mousePoint: Point = .{ .x = 0, .y = 0 };
    var mouseVisible = false;

    var startAt = try Path.init(alloc);
    defer startAt.deinit();

    var rerender = false;

    while (if (rerender) @as(?cli.Event, cli.Event.none) else (cli.nextEvent(stdin2file)) catch @as(?cli.Event, cli.Event.none)) |ev| : (try stdout_buffered.flush()) {
        if (ev.is("ctrl+c")) break;
        if (ev.is("ctrl+p")) @panic("panic test");

        try cli.clearScreen(stdout);
        try cli.moveCursor(stdout, 0, 0);

        var selxn = Selection{ .hover = if (mouseVisible) mousePoint else null, .mouseup = false, .rerender = false };
        defer rerender = selxn.rerender;

        startAt.fixClosed(&jr);
        switch (ev) {
            .mouse => |mev| {
                mousePoint.x = mev.x;
                mousePoint.y = mev.y;
                if (mev.button == .left and mev.direction == .up) selxn.mouseup = true;
            },
            .blur => mouseVisible = false,
            .focus => mouseVisible = true,
            .scroll => |sev| {
                mousePoint.x = sev.x;
                mousePoint.y = sev.y;
                // var px: i32 = if (sev.pixels == 3) 1 else -1;
                var px = sev.pixels;
                while (px > 0) : (px -= 1) {
                    try startAt.advance(&jr);
                }
                while (px < 0) : (px += 1) {
                    try startAt.devance(&jr);
                }
            },
            else => {},
        }

        const ss = try cli.winSize(stdoutf);
        _ = try renderJson(&jr, stdout, .root, 0, 0, ss.h, Themes[0], 0, &selxn, startAt, 0);
        try stdout_buffered.flush();
    }
}
