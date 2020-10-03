// /*
//  *  The following functions define the column width of an ISO 10646
//  *  character as follows:
//  *  - The null character (U+0000) has a column width of 0.
//  *  - Other C0/C1 control characters and DEL will lead to a return value
//  *    of -1.
//  *  - Non-spacing and enclosing combining characters (general category
//  *    code Mn or Me in the
//  *    Unicode database) have a column width of 0.
//  *  - SOFT HYPHEN (U+00AD) has a column width of 1.
//  *  - Other format characters (general category code Cf in the Unicode
//  *    database) and ZERO WIDTH
//  *    SPACE (U+200B) have a column width of 0.
//  *  - Hangul Jamo medial vowels and final consonants (U+1160-U+11FF)
//  *    have a column width of 0.
//  *  - Spacing characters in the East Asian Wide (W) or East Asian
//  *    Full-width (F) category as
//  *    defined in Unicode Technical Report #11 have a column width of 2.
//  *  - All remaining characters (including all printable ISO 8859-1 and
//  *    WGL4 characters, Unicode control characters, etc.) have a column
//  *    width of 1.
//  *  This implementation assumes that characters are encoded in ISO 10646.
// */

const std = @import("std");

/// Return the column width of a utf8 encoded string
pub fn wcswidth(str: []const u8) usize {
    var view = (std.unicode.Utf8View.init(str) catch return str.len).iterator();
    var res: usize = 0;
    while (view.nextCodepoint()) |codepoint| res += wcwidth(codepoint);
    return res;
}

pub fn wcwidth(char: u21) u2 {
    // control chars
    if (char == 0) return 0;
    if (char < 32 or (char >= 0x7f and char < 0xa0)) return 0; // control characters
    // maybe return error.ControlChar or something?

    // non-spacing chars
    if (bisearch(char, combining_characters_map)) return 0;

    // others
    if (char >= 0x1100) {
        if (char <= 0x115f) return 2; // Hangul Jamo init. consonants
        if (char == 0x2329 or char == 0x232a) return 2;
        if (char >= 0x2e80 and char <= 0xa4cf and
            char != 0x303f) return 2; // CJK ... Yi
        if ((char >= 0xac00 and char <= 0xd7a3) or // Hangul Syllables
            (char >= 0xf900 and char <= 0xfaff) or // CJK Compatibility Ideographs
            (char >= 0xfe10 and char <= 0xfe19) or // Vertical forms
            (char >= 0xfe30 and char <= 0xfe6f) or // CJK Compatibility Forms
            (char >= 0xff00 and char <= 0xff60) or // Fullwidth Forms
            (char >= 0xffe0 and char <= 0xffe6) or
            (char >= 0x20000 and char <= 0x2fffd) or
            (char >= 0x30000 and char <= 0x3fffd)) return 2;
    }

    return 1;
}

test "string width" {
    std.testing.expectEqual(@as(usize, 2), wcswidth("何"));
    std.testing.expectEqual(@as(usize, 2), wcwidth('何'));
    std.testing.expectEqual(@as(usize, 4), wcswidth("→何←"));
    std.testing.expectEqual(@as(usize, 28), wcswidth("Hi there!→This is my string←"));
}

// std.binarySearch is intended for knowing
// a value in the table and finding the index.
// all it would take to fix is removing
// (key: T) from the args list and instead
// letting the user provide the expected value
// in context and compare it themselves.
// I guess I could make that change in std
fn bisearch(char: u21, table: []const [2]u21) bool {
    var min: usize = 0;
    var max: usize = table.len - 1;

    if (char < table[0][0] or char > table[max][1]) return false;

    while (max >= min) {
        const mid = min + (max - min) / 2;
        if (char > table[mid][1]) min = mid + 1 //
        else if (char < table[mid][0]) max = mid - 1 //
        else return true;
    }

    return false;
}

fn ur(a: u21, b: u21) [2]u21 {
    return [2]u21{ a, b };
}

// zig fmt bug
// if you take these out of columns and try to format,
// zig fmt ooms
const combining_characters_map = &[_][2]u21{
    ur(0x0300, 0x036f),   ur(0x0483, 0x0486),   ur(0x0488, 0x0489),
    ur(0x0591, 0x05bd),   ur(0x05bf, 0x05bf),   ur(0x05c1, 0x05c2),
    ur(0x05c4, 0x05c5),   ur(0x05c7, 0x05c7),   ur(0x0600, 0x0603),
    ur(0x0610, 0x0615),   ur(0x064b, 0x065e),   ur(0x0670, 0x0670),
    ur(0x06d6, 0x06e4),   ur(0x06e7, 0x06e8),   ur(0x06ea, 0x06ed),
    ur(0x070f, 0x070f),   ur(0x0711, 0x0711),   ur(0x0730, 0x074a),
    ur(0x07a6, 0x07b0),   ur(0x07eb, 0x07f3),   ur(0x0901, 0x0902),
    ur(0x093c, 0x093c),   ur(0x0941, 0x0948),   ur(0x094d, 0x094d),
    ur(0x0951, 0x0954),   ur(0x0962, 0x0963),   ur(0x0981, 0x0981),
    ur(0x09bc, 0x09bc),   ur(0x09c1, 0x09c4),   ur(0x09cd, 0x09cd),
    ur(0x09e2, 0x09e3),   ur(0x0a01, 0x0a02),   ur(0x0a3c, 0x0a3c),
    ur(0x0a41, 0x0a42),   ur(0x0a47, 0x0a48),   ur(0x0a4b, 0x0a4d),
    ur(0x0a70, 0x0a71),   ur(0x0a81, 0x0a82),   ur(0x0abc, 0x0abc),
    ur(0x0ac1, 0x0ac5),   ur(0x0ac7, 0x0ac8),   ur(0x0acd, 0x0acd),
    ur(0x0ae2, 0x0ae3),   ur(0x0b01, 0x0b01),   ur(0x0b3c, 0x0b3c),
    ur(0x0b3f, 0x0b3f),   ur(0x0b41, 0x0b43),   ur(0x0b4d, 0x0b4d),
    ur(0x0b56, 0x0b56),   ur(0x0b82, 0x0b82),   ur(0x0bc0, 0x0bc0),
    ur(0x0bcd, 0x0bcd),   ur(0x0c3e, 0x0c40),   ur(0x0c46, 0x0c48),
    ur(0x0c4a, 0x0c4d),   ur(0x0c55, 0x0c56),   ur(0x0cbc, 0x0cbc),
    ur(0x0cbf, 0x0cbf),   ur(0x0cc6, 0x0cc6),   ur(0x0ccc, 0x0ccd),
    ur(0x0ce2, 0x0ce3),   ur(0x0d41, 0x0d43),   ur(0x0d4d, 0x0d4d),
    ur(0x0dca, 0x0dca),   ur(0x0dd2, 0x0dd4),   ur(0x0dd6, 0x0dd6),
    ur(0x0e31, 0x0e31),   ur(0x0e34, 0x0e3a),   ur(0x0e47, 0x0e4e),
    ur(0x0eb1, 0x0eb1),   ur(0x0eb4, 0x0eb9),   ur(0x0ebb, 0x0ebc),
    ur(0x0ec8, 0x0ecd),   ur(0x0f18, 0x0f19),   ur(0x0f35, 0x0f35),
    ur(0x0f37, 0x0f37),   ur(0x0f39, 0x0f39),   ur(0x0f71, 0x0f7e),
    ur(0x0f80, 0x0f84),   ur(0x0f86, 0x0f87),   ur(0x0f90, 0x0f97),
    ur(0x0f99, 0x0fbc),   ur(0x0fc6, 0x0fc6),   ur(0x102d, 0x1030),
    ur(0x1032, 0x1032),   ur(0x1036, 0x1037),   ur(0x1039, 0x1039),
    ur(0x1058, 0x1059),   ur(0x1160, 0x11ff),   ur(0x135f, 0x135f),
    ur(0x1712, 0x1714),   ur(0x1732, 0x1734),   ur(0x1752, 0x1753),
    ur(0x1772, 0x1773),   ur(0x17b4, 0x17b5),   ur(0x17b7, 0x17bd),
    ur(0x17c6, 0x17c6),   ur(0x17c9, 0x17d3),   ur(0x17dd, 0x17dd),
    ur(0x180b, 0x180d),   ur(0x18a9, 0x18a9),   ur(0x1920, 0x1922),
    ur(0x1927, 0x1928),   ur(0x1932, 0x1932),   ur(0x1939, 0x193b),
    ur(0x1a17, 0x1a18),   ur(0x1b00, 0x1b03),   ur(0x1b34, 0x1b34),
    ur(0x1b36, 0x1b3a),   ur(0x1b3c, 0x1b3c),   ur(0x1b42, 0x1b42),
    ur(0x1b6b, 0x1b73),   ur(0x1dc0, 0x1dca),   ur(0x1dfe, 0x1dff),
    ur(0x200b, 0x200f),   ur(0x202a, 0x202e),   ur(0x2060, 0x2063),
    ur(0x206a, 0x206f),   ur(0x20d0, 0x20ef),   ur(0x302a, 0x302f),
    ur(0x3099, 0x309a),   ur(0xa806, 0xa806),   ur(0xa80b, 0xa80b),
    ur(0xa825, 0xa826),   ur(0xfb1e, 0xfb1e),   ur(0xfe00, 0xfe0f),
    ur(0xfe20, 0xfe23),   ur(0xfeff, 0xfeff),   ur(0xfff9, 0xfffb),
    ur(0x10a01, 0x10a03), ur(0x10a05, 0x10a06), ur(0x10a0c, 0x10a0f),
    ur(0x10a38, 0x10a3a), ur(0x10a3f, 0x10a3f), ur(0x1d167, 0x1d169),
    ur(0x1d173, 0x1d182), ur(0x1d185, 0x1d18b), ur(0x1d1aa, 0x1d1ad),
    ur(0x1d242, 0x1d244), ur(0xe0001, 0xe0001), ur(0xe0020, 0xe007f),
    ur(0xe0100, 0xe01ef),
};
