# zcho

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
    --: Stop parsing options
Escape Sequences (for -e):
    \a, \b, \c, \d, \e, \f, \n, \r, \t, \v
    \0NNN with octal value NNN (1-3 digits)
    \xHH with hex value HH (1-2 digits)
```