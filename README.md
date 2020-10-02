# zcho

## building

`zig build`

the `z` executable is now in `zig-cache/bin/z`

TODO
- support building just one tool with like `zig build -Dtool=zcho` or something

## tools

### `z spinner`

[![asciicast](https://asciinema.org/a/rH3sGcNv79whXNmFnssrzMwaA.svg)](https://asciinema.org/a/rH3sGcNv79whXNmFnssrzMwaA)

has a few options, see `z spinner --help`

### `z progress`

[![asciicast](https://asciinema.org/a/HEx3YQLEKwpLkYQYg2kKS32mY.svg)](https://asciinema.org/a/HEx3YQLEKwpLkYQYg2kKS32mY)

has a few options, see `z progress --help`

### `z jsonexplorer`

`zig targets | z jsonexplorer`

![screenshot of the above thing](https://media.discordapp.net/attachments/605572611539206171/747581462777299104/Peek_2020-08-24_15-21.gif)

Issues:
- fix the memory leak (more likely just use an arena allocator for init allocations)
- fix when scrolling down off the bottom of the screen with things open like `v\n  v\n   - item` make it work correctly
- support displaying very long strings that go off the screen (do it like firefox probably, make them collapsable)

### `z echo`

it's like echo but written in zig and it has a few more options

`zig build -Drelease-fast` outputs the binary `zig-cache/bin/zcho`

`zcho -p $(tput setaf 1)`  
→ `\x1b[31m`

`zcho -e "\x1b[31mHi!"`  
→ `Hi!` (in red)

`zcho -h`
```
Usage:
    zcho [options] [message]
Options:
    -E: Set print mode: raw (default)
    -e: Set print mode: backslash escape interpolation
    -p: Set print mode: escaped printing
    -n: Do not output a newline
    -s: Do not seperate message with spaces
    -h: Print this message
    --: Stop parsing options
Escape Sequences (for -e):
    \\, \a, \b, \c, \d, \e, \f, \n, \r, \t, \v
    \0NNN with octal value NNN (1-3 digits)
    \xHH with hex value HH (1-2 digits)
```
