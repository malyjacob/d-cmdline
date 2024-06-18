module cmdline.pattern;

import std.regex;

package:
__gshared Regex!char PTN_SHORT;
__gshared Regex!char PTN_LONG;
__gshared Regex!char PTN_VALUE;
__gshared Regex!char PTN_SP;
__gshared Regex!char PTN_NEGATE;
__gshared Regex!char PTN_CMDNAMEANDARGS;
__gshared Regex!char PTN_IMPLYMAPKEY;
__gshared Regex!char PTN_MANUALINDENT;
__gshared Regex!char PTN_LONGASSIGN;

shared static this() {
    PTN_SHORT = regex(`^-\w$`, "g");
    PTN_LONG = regex(`^--[(\w\-)\w]+\w$`, "g");
    PTN_NEGATE = regex(`^--no-[(\w\-)\w]+\w$`, "g");
    PTN_VALUE = regex(`(<[(\w\-)\w]+\w(\.{3})?>$)|(\[[(\w\-)\w]+\w(\.{3})?\]$)`, "g");
    PTN_SP = regex(`[ |,]+`);
    PTN_CMDNAMEANDARGS = regex(`([^ ]+) *(.*)`, "g");
    PTN_IMPLYMAPKEY = regex(`([(?:\w\-)\w]+\w)\:((\w+)(\[\])?)`, "g");
    PTN_MANUALINDENT = regex("[\\n][ \\f\\t\\v\u00a0\u1680\u2000-\u200a\u202f\u205f\u3000\ufeff]+");
    PTN_LONGASSIGN = regex(`^(--[(?:\w\-)\w]+\w)=([\S]+)`, "g");
}

unittest {
    import std.stdio;
    auto str1 = "maly-flag:int";
    auto cp1 = matchFirst(str1, PTN_IMPLYMAPKEY);
    writeln(cp1);
    auto str2 = "maly:string[]";
    auto cp2 = matchFirst(str2, PTN_IMPLYMAPKEY);
    writeln(cp2);
    auto str3 = "--flag-sa=123we";
    auto cp3 = matchFirst(str3, PTN_LONGASSIGN);
    writeln(cp3.length);
}