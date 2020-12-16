const std = @import("std");
const help = @import("main.zig");
const ArgsIter = help.PositionalIter;
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
    const @"-read" = .{ filterRead, "Read a png file in" };
    const @"-write" = .{ filterWrite, "Write to a png file" };
    const @"-new" = .{ filterNew, "Create a new image" };
    const @"-print" = .{ filterPrint, "Print the image to the command line" };
    const @"-vertical-scroll" = .{ filterVerticalScroll, "Make the image scroll vertically" };
    const @"-wave-function-collapse" = .{ filterWaveFunctionCollapse, "Wave function collapse (overlapping)" };
};
const FilterCtx = struct {
    ai: *ArgsIter,
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
    std.debug.warn("    assetgen [filters]\n", .{});
    std.debug.warn("Example:\n", .{});
    std.debug.warn("    assetgen -read in.png -resize 10x10 -write out.png\n", .{});
    std.debug.warn("Options:\n", .{});
    inline for (@typeInfo(Filters).Struct.decls) |decl| {
        std.debug.warn("    {}", .{decl.name});
        const fopts = @field(Filters, decl.name);
        if (@hasField(@TypeOf(fopts), "1")) std.debug.warn(": {}", .{fopts.@"1"});
        std.debug.warn("\n", .{});
    }
    return error.ReportedError;
}
fn filterPrint(fctx: *FilterCtx) !void {
    if (fctx.image == null) return fctx.ai.err("No image was loaded yet. Try -read image.png before this.", .{});
    printImage(fctx.image.?);
}
fn filterRead(fctx: *FilterCtx) !void {
    const infile = fctx.ai.next() orelse return fctx.ai.err("Expected png file", .{});

    if (fctx.image) |*img| img.deinit(); // maybe warn if the image is never used
    fctx.setImage().* = blk: {
        const imgfile = try std.fs.cwd().readFileAlloc(fctx.alloc, infile.text, std.math.maxInt(usize));
        defer fctx.alloc.free(imgfile);
        break :blk try Image.load(imgfile);
    };
}
fn filterWrite(fctx: *FilterCtx) !void {
    if (fctx.image == null) return fctx.ai.err("No image was loaded yet. Try -read image.png before this.", .{});
    const filename = fctx.ai.next() orelse return fctx.ai.err("Expected output file name", .{});

    const outfile = try std.fs.cwd().createFile(filename.text, .{});
    defer outfile.close();

    try fctx.image.?.write(outfile.writer());
}
// -new 10x10 -fill #FFF
fn filterNew(fctx: *FilterCtx) !void {}
fn filterVerticalScroll(fctx: *FilterCtx) !void {
    if (fctx.image == null) return fctx.ai.err("No image was loaded yet. Try -load image.png before this.", .{});
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
// -setvar @var1 -load image2.png -overlay @var1
// -wave-function-collapse [ @var1 ( -load b.png ) ( -load c.png ) ]
fn filterWaveFunctionCollapse(fctx: *FilterCtx) !void {
    if (fctx.image == null) return fctx.ai.err("No image was loaded yet. Try -load image.png before this.", .{});
    const image = &fctx.image.?;

    var pattern_width: usize = 3; // these don't change, this is just to simulate it not being comptime-known
    var pattern_height: usize = 3;
    const max_color_count = 64; // required for the packedintarray(max_color_count, u1)

    var colors_array = [_]Color{undefined} ** max_color_count;
    var colors: []Color = colors_array[0..0];
    const ColorIndexInt = std.math.IntFittingRange(0, max_color_count);

    for (range(image.h)) |_, y| {
        flp: for (range(image.w)) |_, x| {
            const color = image.get(x, y);
            // r, g, b, a
            for (colors) |col| if (std.meta.eql(col, color)) {
                continue :flp;
            };
            colors.len += 1;
            if (colors.len >= max_color_count) return fctx.ai.err("More than {} colors were used.", .{max_color_count});
            colors[colors.len - 1] = color;
        }
    }

    // Each element of this array represents a state of an NxN region in the output. A state of an NxN region is a superposition of NxN patterns
    //   of the input with boolean coefficients
    // wait how does that make sense

    // ok yeah
    // make an array of all the colors
    // make an array of all the patterns
    // keep the weights of the patterns (which are used more)
    //
    // ok so how "symmetry" worked in the original
    // 1 is no symmetry, 2 is horizontal reflection
    // that's kind of a little bit really dumb

    var patterns = std.ArrayList(ColorIndexInt).init(fctx.alloc);
    // to get pattern[i], get pattern[i + (pattern_width * pattern_height)]
    const pattern_size = pattern_width * pattern_height;

    for (range(image.h)) |_, y| {
        flp: for (range(image.w)) |_, x| {
            // since there is no addManyAsSlice
            // TODO add addManyAsSlice/addManyAsSliceAssumeCapacity to the stdlib
            // (here we are allocating rather than recreating addManyAsSlice because
            //  idk why there was smoe reason it was better but I forgot
            //  oh right to make sure patterns aren't duplicated and to increase weight
            //  instead of duplication)
            const added_slice = try fctx.alloc.alloc(ColorIndexInt, pattern_size);
            for (range(pattern_width)) |_, py| {
                for (range(pattern_height)) |_, px| {
                    // in the future, we will load a 3x3 grid of tiles and use the center
                    // one. this way, wrapping won't be needed.
                    const pixel = image.get((x + px) % image.w, (y + py) % image.h);
                    const color_index = for (colors) |col, i| {
                        if (std.meta.eql(pixel, col)) break @intCast(ColorIndexInt, i); // won't fail
                    } else unreachable;
                    added_slice[py * pattern_height + px] = color_index;
                }
            }
            // TODO symmetries? (be careful to not use an invalidated added_slice pointer)
            for (range(patterns.items.len / pattern_size)) |_, pattern_index| {
                const i = pattern_index * pattern_size;
                if (std.mem.eql(ColorIndexInt, patterns.items[i .. i + pattern_size], added_slice)) continue :flp; // pattern already added
            }
            try patterns.appendSlice(added_slice);
        }
    }

    // ok I think this isn't right
    // it is supposed to be able to go leftup and downright instead of just downright
    // and also it's like completely wrong idk

    std.debug.warn("Unique color count: {}\n", .{colors.len});
    std.debug.warn("Unique pattern count: {}\n", .{patterns.items.len / pattern_size});

    // count all the pattern_width x pattern_width patterns (wrapping) (todo instead of wrapping, load a larger image)
}

pub const main = help.anyMain(exec);

const Config = struct {
    parsing_args: bool = true,
    _: []const Positional = &[_]Positional{},
};
const Positional = struct { text: []const u8, pos: usize, epos: usize = 0 };

pub fn exec(exec_args: help.MainFnArgs) !void {
    const ai = exec_args.args_iter;
    const alloc = exec_args.arena_allocator;
    const out = std.io.getStdOut().writer();

    var fctx: FilterCtx = .{
        .ai = exec_args.args_iter,
        .alloc = alloc,
        .image = null,
    };
    defer if (fctx.image) |*img| img.deinit();

    var cfg = Config{};
    var positionals = std.ArrayList(Positional).init(alloc);
    var ran_one_filter = false;
    whlp: while (ai.next()) |arg| {
        if (cfg.parsing_args and std.mem.startsWith(u8, arg.text, "-")) {
            if (std.mem.eql(u8, arg.text, "--")) {
                cfg.parsing_args = false;
                continue;
            }
            inline for (@typeInfo(Filters).Struct.decls) |decl| {
                if (std.mem.eql(u8, decl.name, arg.text)) {
                    @field(Filters, decl.name)[0](&fctx) catch |e| switch (@as(anyerror, e)) {
                        error.ReportedError => return e,
                        else => return ai.err("Got error: {}", .{e}),
                    };
                    ran_one_filter = true;
                    continue :whlp;
                }
            }
            return ai.err("Bad arg. See --help", .{});
        }
        return ai.err("Bad arg. See --help", .{});
    }
    cfg._ = positionals.toOwnedSlice();

    if (!ran_one_filter) try filterHelp(&fctx);
}
