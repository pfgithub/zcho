const std = @import("std");
const c = @cImport({
    @cInclude("stb_image.h");
    @cInclude("stb_image_write.h");
});

const Color = packed struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
    fn toArray(color: Color) [4]u8 {
        return [4]u8{ color.r, color.g, color.b, color.a };
    }
    fn fromArray(array: [4]u8) Color {
        return Color{ .r = array[0], .g = array[1], .b = array[2], .a = array[3] };
    }
};

const Image = struct {
    alloc: *std.mem.Allocator,
    data: []u8,
    w: usize,
    h: usize,
    fn load(cont: []const u8) !Image {
        const calloc = std.heap.c_allocator;

        var w: c_int = undefined;
        var h: c_int = undefined;
        var unused: c_int = undefined;

        const data = c.stbi_load_from_memory(cont.ptr, @intCast(c_int, cont.len), &w, &h, &unused, 4);
        if (data == null) return error.LoadFailed;

        return Image{
            .w = @intCast(usize, w),
            .h = @intCast(usize, h),
            .data = data[0..@intCast(usize, w * h * 4)],
            .alloc = calloc,
        };
    }
    fn write(image: Image, os: anytype) !void {
        const Data = struct { write_error: ?@TypeOf(os).Error, out_stream: *const @TypeOf(os) };
        var data: Data = .{ .write_error = null, .out_stream = &os };
        const write_func = struct {
            fn write_func(context: ?*c_void, write_data: ?*c_void, size: c_int) callconv(.C) void {
                const data_ = @intToPtr(*Data, @ptrToInt(context));
                if (data_.write_error) |_| return;
                const to_write = @ptrCast([*]const u8, write_data)[0..@intCast(usize, size)];
                data_.out_stream.*.writeAll(to_write) catch |e| {
                    data_.write_error = e;
                };
            }
        }.write_func;
        const err = c.stbi_write_png_to_func(
            write_func,
            @intToPtr(*c_void, @ptrToInt(&data)),
            @intCast(c_int, image.w),
            @intCast(c_int, image.h),
            4,
            image.data.ptr,
            @intCast(c_int, image.w * 4),
        );
        if (data.write_error) |we| return we;
        if (err == 0) return error.WriteFailed;
    }
    fn create(alloc: *std.mem.Allocator, w: usize, h: usize) !Image {
        const av = try alloc.alloc(u8, w * h * 4);
        return Image{ .alloc = alloc, .w = w, .h = h, .data = av };
    }
    fn fill(image: *Image, color: Color) void {
        for (range(image.h)) |_, y| for (range(image.w)) |x| {
            image.set(x, y, color);
        };
    }
    fn deinit(image: *Image) void {
        image.alloc.free(image.data);
        image.* = undefined;
    }
    fn get(image: Image, x: usize, y: usize) Color {
        const resv = image.data[(y * image.w + x) * 4 ..][0..4];
        return Color.fromArray(resv.*);
    }
    fn set(image: *Image, x: usize, y: usize, color: Color) void {
        std.mem.copy(u8, image.data[(y * image.w + x) * 4 ..][0..4], &color.toArray());
    }
};

fn printImage(img: Image) void {
    for (range(img.h)) |_, y| {
        for (range(img.w)) |_, x| {
            const color = img.get(x, y);
            std.debug.warn("\x1b[48;2;{};{};{}m  ", .{ color.r, color.g, color.b });
        }
        std.debug.warn("\x1b(B\x1b[m\n", .{});
    }
}

// zig should have for(0..4) or something idk
// or like at least, c-style for loops
fn range(max: usize) []const void {
    return @as([]const void, &[_]void{}).ptr[0..max];
}

const Filters = struct {
    const @"--help" = .{ filterHelp, helpHelp };
    const @"-read" = .{filterRead};
    const @"-write" = .{filterWrite};
    const @"-new" = .{filterNew};
    const @"-print" = .{filterPrint};
    const @"-vertical-scroll" = .{filterVerticalScroll};
};
const FilterCtx = struct {
    argsIter: std.process.ArgIterator,
    alloc: *std.mem.Allocator,
    image: ?Image,
    fn setImage(fctx: *FilterCtx) *?Image {
        if (fctx.image) |*img| img.deinit();
        return &fctx.image;
    }
};
const helpHelp = "Print this message";
fn filterHelp(fctx: *FilterCtx) !void {
    std.debug.warn("Usage:\n", .{});
    std.debug.warn("    animate [filters]\n", .{});
    std.debug.warn("Example:\n", .{});
    std.debug.warn("    animate -read in.png -resize 10x10 -write out.png\n", .{});
    std.debug.warn("Options:\n", .{});
    inline for (@typeInfo(Filters).Struct.decls) |decl| {
        std.debug.warn("    {}", .{decl.name});
        const fopts = @field(Filters, decl.name);
        if (@hasField(@TypeOf(fopts), "1")) std.debug.warn(": {}", .{fopts.@"1"});
        std.debug.warn("\n", .{});
    }
    return error.Helped;
}
fn filterPrint(fctx: *FilterCtx) !void {
    if (fctx.image == null) return error.NoImage;
    printImage(fctx.image.?);
}
fn filterRead(fctx: *FilterCtx) !void {
    const infile = fctx.argsIter.nextPosix() orelse return error.BadArgs;

    if (fctx.image) |*img| img.deinit(); // maybe warn if the image is never used
    fctx.setImage().* = blk: {
        const imgfile = try std.fs.cwd().readFileAlloc(fctx.alloc, infile, std.math.maxInt(usize));
        defer fctx.alloc.free(imgfile);
        break :blk try Image.load(imgfile);
    };
}
fn filterWrite(fctx: *FilterCtx) !void {
    if (fctx.image == null) return error.NoImage;
    const filename = fctx.argsIter.nextPosix() orelse return error.BadArgs;

    const outfile = try std.fs.cwd().createFile(filename, .{});
    defer outfile.close();

    try fctx.image.?.write(outfile.writer());
}
// -new 10x10 -fill #FFF
fn filterNew(fctx: *FilterCtx) !void {}
fn filterVerticalScroll(fctx: *FilterCtx) !void {
    if (fctx.image == null) return error.NoImage;
    const img = &fctx.image.?;
    const alloc = fctx.alloc;

    var outimg = try Image.create(alloc, img.w, img.h * img.h);
    errdefer outimg.deinit();

    for (range(img.h)) |_, offset| {
        for (range(img.h)) |_, y| for (range(img.w)) |_, x| {
            const src_color = img.get(x, (y + offset) % img.h);
            outimg.set(x, y + offset * img.h, src_color);
        };
    }

    fctx.setImage().* = outimg;
}

pub fn main() !void {
    main_main() catch |e| switch (e) {
        error.Helped => {},
        else => return e,
    };
}

fn main_main() !void {
    var gpalloc = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.testing.expect(!gpalloc.deinit());
    const alloc = &gpalloc.allocator;

    // usage: animate -read in.png -print -vertical-scroll -write out.png

    var fctx: FilterCtx = .{
        .argsIter = std.process.ArgIterator.init(),
        .alloc = alloc,
        .image = undefined,
    };
    defer if (fctx.image) |*img| img.deinit();

    _ = fctx.argsIter.nextPosix() orelse return error.BadArgs;

    var oneIter = false;
    whlp: while (fctx.argsIter.nextPosix()) |arg| {
        oneIter = true;
        inline for (@typeInfo(Filters).Struct.decls) |decl| {
            if (std.mem.eql(u8, decl.name, arg)) {
                try @field(Filters, decl.name)[0](&fctx);
                continue :whlp;
            }
        }
        if (!std.mem.startsWith(u8, arg, "-")) {
            std.debug.warn("Did you mean -read/-write {}", .{arg});
        } else {
            std.debug.warn("Unknown arg: {}\n", .{arg});
        }
        return error.BadArgs;
    }

    if (!oneIter) try filterHelp(&fctx);
}
