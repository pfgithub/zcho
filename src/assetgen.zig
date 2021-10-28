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
    fn rgbHex(color: u24) Color {
        // this is where a packed struct would be better but it's not allowed
        // or an unpacking thing like unpackBits(color, 8*2, 8*3) or unpackBits(color, 0xFF0000) even
        const unpacked_r = @intCast(u8, color & 0xFF0000 >> (2 * 8));
        const unpacked_g = @intCast(u8, color & 0x00FF00 >> (1 * 8));
        const unpacked_b = @intCast(u8, color & 0x0000FF >> (0 * 8));
        return Color{ .r = unpacked_r, .g = unpacked_g, .b = unpacked_b, .a = 255 };
    }
};

// unpackBits(number: u{T}, start: comptime_int, end: comptime_int): u{end - start}

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
        for (range(image.h)) |_, y| for (range(image.w)) |_, x| {
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

fn mixint(start: u8, end: u8, distance: u8) u8 {
    const low = std.math.min(start, end);
    const high = std.math.max(start, end);
    const scale = high - low;
    const mixer = @as(u16, scale) * distance;
    const mixed = @intCast(u8, mixer / 256); // u16 / comptime_int(256) should return u8
    if (start == low) return low + mixed;
    return high - mixed;
}

const transparency_colors = [_]Color{ Color.rgbHex(0xFDFDFD), Color.rgbHex(0xCACACC) };
fn printImage(img: Image) void {
    const stdout = std.io.getStdOut().writer();
    for (range(img.h)) |_, y| {
        for (range(img.w)) |_, x| {
            const color = img.get(x, y);
            const transparency_color_idx: u1 = @intCast(u1, (x +% y) % 2); // usize % comptime_int(2) should return u1
            const transparency_color = transparency_colors[transparency_color_idx];
            const mixed = Color{
                .r = mixint(transparency_color.r, color.r, color.a),
                .g = mixint(transparency_color.g, color.g, color.a),
                .b = mixint(transparency_color.b, color.b, color.a),
                .a = 255,
            };
            stdout.print("\x1b[48;2;{};{};{}m  ", .{ mixed.r, mixed.g, mixed.b }) catch @panic("failed to print");
        }
        stdout.print("\x1b(B\x1b[m\n", .{}) catch @panic("failed to print");
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
    const @"-fill" = .{ filterFill, "Fill the image with a color" };
    const @"-print" = .{ filterPrint, "Print the image to the command line" };
    const @"-text3x3" = .{ filterText, "Add 3x3 text from the specified file" };
    const @"-vertical-scroll" = .{ filterVerticalScroll, "Make the image scroll vertically" };
    const @"-wave-function-collapse" = .{ filterWaveFunctionCollapse, "Wave function collapse (overlapping)" };
    const @"-dev" = .{ filterDev, "Dev" };
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
fn filterHelp(_: *FilterCtx) !void {
    std.debug.warn("Usage:\n", .{});
    std.debug.warn("    assetgen [filters]\n", .{});
    std.debug.warn("Example:\n", .{});
    std.debug.warn("    assetgen -read in.png -resize 10x10 -write out.png\n", .{});
    std.debug.warn("Options:\n", .{});
    inline for (@typeInfo(Filters).Struct.decls) |decl| {
        std.debug.warn("    {s}", .{decl.name});
        const fopts = @field(Filters, decl.name);
        if (@hasField(@TypeOf(fopts), "1")) std.debug.warn(": {s}", .{fopts.@"1"});
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
fn filterNew(fctx: *FilterCtx) !void {
    const size = fctx.ai.next() orelse return fctx.ai.err("Expected size eg 10x10", .{});
    var tknzd = std.mem.tokenize(u8, size.text, "x,");

    const width_str = tknzd.next() orelse return size.err(fctx.ai, "Expected size eg 10x10", .{});
    const height_str = tknzd.next() orelse return size.err(fctx.ai, "Expected size eg 10x10", .{});
    if (!std.mem.eql(u8, tknzd.rest(), "")) return size.err(fctx.ai, "Expected size eg 10x10", .{});
    // TODO __{number}__x{number} eg size.select(0, tknzd.len) or size.select(tknzd[0])   .err(…)
    const width = std.fmt.parseInt(usize, width_str, 10) catch return size.err(fctx.ai, "Expected number", .{});
    const height = std.fmt.parseInt(usize, height_str, 10) catch return size.err(fctx.ai, "Expected number", .{});

    fctx.setImage().* = blk: {
        var img = try Image.create(fctx.alloc, width, height);
        img.fill(Color{ .r = 255, .g = 255, .b = 255, .a = 0 });
        break :blk img;
    };
}
fn parseFillColor(text: []const u8) !Color {
    if (text.len == "#FFFFFF".len and text[0] == '#') { // if(text.match("#[a-fA-F0-9]{6}")) |value|
        const num_parsed = try std.fmt.parseInt(u24, text[1..], 16);
        return Color.rgbHex(num_parsed);
    } else {
        return error.UnsupportedFormat;
    }
}
fn filterFill(fctx: *FilterCtx) !void {
    if (fctx.image == null) return fctx.ai.err("No image is loaded. Try -new 10x10 before this.", .{});
    const image = &fctx.image.?;

    const fill_color = fctx.ai.next() orelse return fctx.ai.err("Expected color eg #FFFFFF", .{});

    const fill_color_parsed = parseFillColor(fill_color.text) catch |e| return fill_color.err(fctx.ai, "Expected color eg #FFFFFF ({})", .{e});

    image.fill(fill_color_parsed);
}
fn filterDev(fctx: *FilterCtx) !void {
    if (fctx.image == null) return fctx.ai.err("No image is loaded. Try -new 10x10 before this.", .{});
    const image = &fctx.image.?;
    if (image.w != 63 or image.h != 23) return fctx.ai.err("not font", .{});
    const stdout = std.io.getStdOut().writer();

    for (range(6)) |_, y| for (range(16)) |_, x| {
        var outv: u9 = 0;
        for (range(3)) |_, py| for (range(3)) |_, px| {
            const pixel = image.get(x * 4 + px, y * 4 + py);
            const value: u1 = if (std.meta.eql(pixel, Color.rgbHex(0x000000))) blk: {
                break :blk 1;
            } else if (pixel.a == 0) blk: {
                break :blk 0;
            } else {
                return fctx.ai.err("not font (bad color {})", .{pixel});
            };
            outv |= @as(u9, value) << @intCast(u4, py * 3 + px);
        };
        // write to 0b0100 xxxx 0b010x xxxx
        try stdout.writeByte(0b0100_0000 | @intCast(u8, (outv & 0b111100000) >> 5));
        try stdout.writeByte(0b010_00000 | @intCast(u8, (outv & 0b11111)));
    };
}
const Font3x3 = struct {
    const font_data = @embedFile("lib/assetgen/font");
    fn bconv(v: u8) bool {
        return v > 0;
    }
    fn get(char: u8) [9]bool {
        if (char < 0x20 or char > 0x7F) return [_]bool{true} ** 9;
        const index: usize = (@as(usize, char) - 0x20) * 2;
        const b0 = font_data[index];
        const b1 = font_data[index + 1];
        return [9]bool{
            bconv(b1 & 0b00001),
            bconv(b1 & 0b00010),
            bconv(b1 & 0b00100),
            bconv(b1 & 0b01000),
            bconv(b1 & 0b10000),
            bconv(b0 & 0b0001),
            bconv(b0 & 0b0010),
            bconv(b0 & 0b0100),
            bconv(b0 & 0b1000),
        };
    }
};
fn filterText(fctx: *FilterCtx) !void {
    if (fctx.image == null) return fctx.ai.err("No image is loaded. Try -new 10x10 before this.", .{});
    const image = &fctx.image.?;

    const fill_color_unparsed = fctx.ai.next() orelse return fctx.ai.err("Expected color eg #FFFFFF", .{});
    const fill_color = parseFillColor(fill_color_unparsed.text) catch |e| return fill_color_unparsed.err(fctx.ai, "Expected color eg #FFFFFF ({})", .{e});

    const file_path_user = fctx.ai.next() orelse return fctx.ai.err("Expected file path or `-` for stdin", .{});
    const file_path = if (std.mem.eql(u8, file_path_user.text, "-")) "/dev/stdin" else file_path_user.text;

    var file_v = std.fs.cwd().openFile(file_path, .{}) catch |e| return file_path_user.err(fctx.ai, "File error: {}", .{e});
    defer file_v.close();

    const in = file_v.reader();

    var x: usize = 1;
    var y: usize = 1;

    const remaining: bool = while (true) {
        const byte = in.readByte() catch |e| switch (e) {
            error.EndOfStream => break false,
            else => return file_path_user.err(fctx.ai, "File error: {}", .{e}),
        };
        if (byte == '\n') {
            y += 4;
            x = 1;
        } else if (byte == '.') {
            if (x + 1 >= image.w) {
                x = 1;
                y += 4;
            }
            if (y + 3 >= image.h) break true;
            image.set(x, y + 2, fill_color);
            x += 1;
        } else {
            if (x + 3 >= image.w) {
                x = 1;
                y += 4;
            }
            if (y + 3 >= image.h) break true;
            const glyph = Font3x3.get(byte);
            // what if character widths? might be interesting
            // eg '.' would take 1px
            for (range(3)) |_, oy| for (range(3)) |_, ox| {
                if (glyph[oy * 3 + ox]) image.set(x + ox, y + oy, fill_color);
            };
            x += 4;
        }
    } else unreachable;

    if (remaining and image.w >= 3 and image.h >= 1) {
        for (range(image.w - 2)) |_, i| {
            if (i % 2 == 0) image.set(i + 1, std.math.min(y, image.h - 1), fill_color);
        }
    }
}
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
            for (colors) |col|
                if (std.meta.eql(col, color)) {
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
    _ = out;

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
