// the main initial goal of zigsh is to have really good support for tab completion with other z programs
// like
//    z s|pinner
//    z progress |[1 / 10]
// and stuff like that
// brackets would be examples
// and then also another goal is like async support
//   during (curl "url.com"); echo (terminfo cursor_start_of_line)(spinner)" Loading…"(terminfo clr_eol); sleep 0.1; end
// and stream stuff
//   for (tree /) |file|; echo file; end
// (that wouldn't have to wait until tree / is done before running echo file)
// and other stuff like that
// mainly good tab completion and error underlining and whatever to start though

// https://man7.org/linux/man-pages/man5/terminfo.5.html
