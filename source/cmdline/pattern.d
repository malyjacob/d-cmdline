module cmdline.pattern;

import std.regex;

package:
__gshared Regex!char PTN_SHORT;
__gshared Regex!char PTN_LONG;
__gshared Regex!char PTN_VALUE;
__gshared Regex!char PTN_SP;
__gshared Regex!char PTN_NEGATE;

shared static this() {
    PTN_SHORT = regex(`^-\w$`);
    PTN_LONG = regex(`^--[(\w\-)\w]+\w$`);
    PTN_NEGATE = regex(`^--no-[(\w\-)\w]+\w$`);
    PTN_VALUE = regex(`(<[(\w\-)\w]+\w(\.{3})?>$)|(\[[(\w\-)\w]+\w(\.{3})?\]$)`);
    PTN_SP = regex(`[ |,]+`);
}