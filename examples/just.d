module examples.just;

import std.string;
import std.utf;
import std.stdio;
import cmdline;

@cmdline struct Just {
    mixin BEGIN;
    mixin VERSION!"0.0.1";
    mixin DESC!"just the string in given width and fufill with given char";

    mixin DEF_OPT!(
        "str", string, "-s <str>", Desc_d!"the string to be justed",
        Mandatory_d, ToArg_d
    );

    mixin DEF_OPT!(
        "width", int, "-w <width>", Desc_d!"the width of new string justed",
        Mandatory_d, ToArg_d, Range_d!(0, int.max - 1)
    );

    mixin DEF_OPT!(
        "fillChar", string, "-f <char>", Desc_d!"the char to be fullfilled",
        Default_d!" ", ToArg_d
    );

    mixin DEF_OPT!(
        "mode", string, "-m <mode>", Desc_d!"the mode to just",
        Choices_d!("center", "left", "right")
    );

    mixin DEF_BOOL_OPT!(
        "rLess", "",
        Desc_d!"fullfill with char less on right side if needed, when in the mode `center`",
    );

    mixin DEF_BOOL_OPT!(
        "center", "-c", Desc_d!"set `center` mode",
        Conflicts_d!"mode"
    );

    mixin DEF_BOOL_OPT!(
        "left", "-l", Desc_d!"set `left` mode",
        Conflicts_d!("mode", "center")
    );

    mixin DEF_BOOL_OPT!(
        "right", "-r", Desc_d!"set `right` mode",
        Conflicts_d!("mode", "center", "left")
    );
    mixin END;

    void action() {
        dstring str_ = str.get.toUTF32;
        size_t width_ = cast(size_t) width.get;
        dchar fillChar_ = fillChar.get.toUTF32[0];
        bool is_center = this.center.get;
        bool is_left = this.left.get;
        bool is_right = this.right.get;
        bool rLess_ = rLess.get;
        string mode_ = mode ? mode.get : (
            is_center ? "center" : (
                is_right ? "right" : is_left ? "left" : "center"
            )
        );
        dstring result;
        final switch (mode_) {
        case "center":
            result = str_.center(width_, fillChar_);
            if (width_ > str_.length && (width_ - str_.length) % 2 != 0 && rLess_) {
                result = result[$ - 1] ~ result[0 .. $ - 1];
            }
            break;
        case "left":
            result = str_.leftJustify(width_, fillChar_);
            break;
        case "right":
            result = str_.rightJustify(width_, fillChar_);
            break;
        }
        writeln(result);
    }
}

mixin CMDLINE_MAIN!Just;
