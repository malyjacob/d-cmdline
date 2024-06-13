module cmdline.pattern;

import std.regex;

package:
__gshared Regex!char PTN_SHORT;
__gshared Regex!char PTN_LONG;
__gshared Regex!char PTN_VALUE;
__gshared Regex!char PTN_SP;
__gshared Regex!char PTN_NEGATE;
__gshared Regex!char PTN_CMDNAMEANDARGS;

shared static this() {
    PTN_SHORT = regex(`^-\w$`, "g");
    PTN_LONG = regex(`^--[(\w\-)\w]+\w$`, "g");
    PTN_NEGATE = regex(`^--no-[(\w\-)\w]+\w$`, "g");
    PTN_VALUE = regex(`(<[(\w\-)\w]+\w(\.{3})?>$)|(\[[(\w\-)\w]+\w(\.{3})?\]$)`, "g");
    PTN_SP = regex(`[ |,]+`);
    PTN_CMDNAMEANDARGS = regex(`([^ ]+) *(.*)`, "g");
}