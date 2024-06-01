module cmdline.option;

import std.stdio;
import std.string;
import std.regex;
import std.meta;
import std.traits;
import mir.algebraic;

import cmdline.error;
import mir.primitives;

private struct OptionFlags {
    string shortFlag = "";
    string longFlag = "";
    string valueFlag = "";
}

alias OptionBaseValue = AliasSeq!(string, int, double, bool);
alias OptionArrayValue = AliasSeq!(string[], int[], double[], bool[]);
alias OptionValueSeq = AliasSeq!(OptionBaseValue, OptionArrayValue);

alias OptionNullable = Nullable!OptionValueSeq;
alias OptionVariant = Variant!OptionValueSeq;

alias ParseArgFn(Target, Source = string) = Target function(in Source src);

alias ProcessArgFn(Target, Source = Target) = ParseArgFn!(Target, Source);

template ProcessArrArgReduceFn(Target, Current = Target, Previous = Target) {
    alias ProcessArrArgReduceFn = Target function(Current cur, Previous prev);
}

// unittest {
//     OptionNullable san = 123;
//     auto x = 13;
//     auto fn = (int v) => v + x;
//     pragma(msg, typeof(fn));
//     // alias trans = mir.algebraic.optionalMatch!(fn);

//     static auto fun(typeof(fn) arg) {
//         return mir.algebraic.optionalMatch!(arg);
//     }

//     auto trans = fun(fn);
//     // pragma(msg, trans);
//     san = trans(san);
//     assert(san == 136);
// }

template isBaseOptionValueType(T) {
    enum bool isBaseOptionValueType = isBoolean!T || allSameType!(T, int) ||
        allSameType!(T, double) || allSameType!(T, string);
}

template isOptionValueType(T) {
    static if (isDynamicArray!T && !allSameType!(T, string)) {
        enum bool isOptionValueType = isBaseOptionValueType!(ElementType!T);
    }
    else {
        enum bool isOptionValueType = isBaseOptionValueType!T;
    }
}

unittest {
    static assert(isBaseOptionValueType!int);
    static assert(isBaseOptionValueType!double);
    static assert(isBaseOptionValueType!bool);
    static assert(isBaseOptionValueType!string);

    static assert(isOptionValueType!int);
    static assert(isOptionValueType!double);
    static assert(isOptionValueType!bool);
    static assert(isOptionValueType!string);

    static assert(isOptionValueType!(int[]));
    static assert(isOptionValueType!(double[]));
    static assert(isOptionValueType!(bool[]));
    static assert(isOptionValueType!(string[]));
}

class Option {
    string description;
    string defaultValueDescription;

    bool mandatory;

    const bool required;
    const bool optional;

    const string shortFlag;
    const string longFlag;

    const string valueName;

    const bool variadic;

    bool hiden;

    string[] argChoices;
    string[] conflictsWith;
    string envVar;
    ImplyOptionMap implied;

    DefaultNullable defaultArg;
    string[] defaultArrArg;
    PresetNullable presetArg;
    PresetArrayNullable presetArrArg;

    alias Self = typeof(this);
    alias ImplyOptionMap = Variant!(bool, string)[string];
    alias DefaultNullable = Nullable!(bool, string);
    alias PresetNullable = Nullable!(OptionBaseValue);
    alias PresetArrayNullable = Nullable!OptionArrayValue;

    alias ProcessPresetFn = PresetNullable function(in PresetNullable arg);
    alias ProcessPresetArrMapFn = PresetArrayNullable function(in PresetArrayNullable arg);
    alias ProcessPresetArrFn = PresetNullable function(in PresetArrayNullable arg);

    this(string flags, string description) {
        this.description = description;
        this.mandatory = false;
        this.defaultValueDescription = "";
        auto opt = splitOptionFlags(flags);
        this.shortFlag = opt.shortFlag;
        this.longFlag = opt.longFlag;
        this.variadic = opt.valueFlag == "" || opt.valueFlag[$ - 2] != '.' ? false : true;
        this.valueName = opt.valueFlag == "" ? "" : this.variadic ? opt.valueFlag[1 .. $ - 4].idup
            : opt.valueFlag[1 .. $ - 1].idup;
        this.required = opt.valueFlag[0] == '<' ? true : false;
        this.optional = opt.valueFlag[0] == '[' ? true : false;
        this.presetArg = null;
        this.presetArrArg = null;
        if (this.optional) {
            this.presetArg = true;
        }
        this.hiden = false;
        this.argChoices = [];
        this.conflictsWith = [];
        this.implied = null;
        this.envVar = "";
        this.defaultArg = null;
        this.defaultArrArg = null;
    }

    Self defaultVal(bool value = true) {
        assert(!this.variadic);
        defaultArg = value;
        return this;
    }

    Self defalueVal(string value, string[] rest...) {
        if (this.variadic) {
            auto tmp = [value];
            foreach (val; rest) {
                tmp ~= val;
            }
            defaultArrArg = tmp;
            return this;
        }
        assert(rest.length == 0);
        defaultArg = value;
        return this;
    }

    Self preset(bool value = true) {
        assert(!this.variadic);
        presetArg = value;
        return this;
    }

    Self preset(T)(T value, T[] rest...) if (isBaseOptionValueType!T) {
        if (this.variadic) {
            auto tmp = [value];
            foreach (val; rest) {
                tmp ~= val;
            }
            presetArrArg = tmp;
            return this;
        }
        assert(rest.length == 0);
        presetArg = value;
        return this;
    }

    Self conflicts(string name) {
        this.conflictsWith ~= name;
        return this;
    }

    Self conflicts(const string[] names) {
        this.conflictsWith ~= names;
        return this;
    }

    Self implies(string[] names...) {
        assert(names.length);
        foreach (name; names) {
            auto value_ptr = name in this.implied;
            if (value_ptr !is null)
                throw new ImplyOptionError;
            implied[name] = true;
        }
        return this;
    }

    Self implies(T)(const T[string] optionMap) if (is(T == bool) || is(T == string)) {
        assert(optionMap !is null);
        foreach (key, value; optionMap) {
            auto value_ptr = key in this.implied;
            if (value_ptr !is null)
                throw new ImplyOptionError;
            implied[key] = value;
        }
        return this;
    }

    Self env(string name) {
        this.envVar = name;
        return this;
    }

    Self makeOptionMandatory(bool mandatory = true) {
        this.mandatory = mandatory;
        return this;
    }

    Self hideHelp(bool hide = true) {
        this.hiden = hide;
        return this;
    }

    Self choices(const string[] values) {
        foreach (value; values) {
            bool flag = false;
            foreach (item; this.argChoices) {
                flag = item == value;
                if (flag)
                    break;
            }
            if (flag)
                continue;
            this.argChoices ~= value;
        }
        return this;
    }

    @property
    string name() const {
        if (!this.longFlag.length && !this.shortFlag.length)
            throw new InvalidFlagError;
        if (this.longFlag.length > 2) {
            return this.longFlag[2 .. $].idup;
        }
        return this.longFlag[1 .. $].idup;
    }

    @property
    string attrName() const {
        return _camelCase(this.name);
    }

    bool isFlag(string flag) const {
        return this.shortFlag == flag || this.longFlag == flag;
    }

    template getPreset(T = bool) {
        static assert(isOptionValueType!T);
        static if (isBaseOptionValueType!T) {
            T getPreset() const {
                assert(!this.variadic);
                return this.presetArg.get!T;
            }
        }
        else {
            T getPreset() const {
                assert(this.variadic);
                return this.presetArrArg.get!T.dup;
            }
        }
    }

    T[] getPresetArr(T)() const if (isBaseOptionValueType!T) {
        return this.getPreset!(T[]);
    }

    template getDefault(T = string) {
        static assert(is(T == string) || is(T == bool) || is(T == string[]));
        static if (is(T == string) || is(T == bool)) {
            T getDefault() const {
                assert(!this.variadic);
                return this.defaultArg.get!T();
            }
        }
        else {
            T getDefault() const {
                assert(this.variadic);
                return this.defaultArrArg.dup;
            }
        }
    }

    string[] getDefaultArr() const {
        return getDefault!(string[]);
    }
}

unittest {
    static class DOption : Option {
        this(string flags, string description) {
            super(flags, description);
        }
    }

    auto dopt = new DOption("--xx-dox, -x, <file-path>", "")
        .defaultVal()
        .defalueVal("maly")
        .preset()
        .preset(123);
    with (dopt) {
        assert(defaultArg == "maly");
        assert(presetArg == 123);
        assert(isFlag("--xx-dox"));
        auto arg = getPreset!int;
        assert(arg == 123);
    }
}

unittest {
    auto opt = new Option("--xx-dox, -x <file-path>", "");
    with (opt) {
        assert(description == "");
        assert(!mandatory);
        assert(required);
        assert(!optional);
        assert(shortFlag == "-x");
        assert(longFlag == "--xx-dox");
        assert(valueName == "file-path");
        assert(!variadic);
        assert(name == "xx-dox");
        assert(attrName == "xxDox");
    }
}

unittest {
    auto opt = new Option("--xx-dox, -x <file-path>", "")
        .defaultVal()
        .defalueVal("maly")
        .preset()
        .preset(123);
    with (opt) {
        assert(defaultArg == "maly");
        assert(presetArg == 123);
        assert(isFlag("--xx-dox"));
        auto arg = getPreset!int;
        assert(arg == 123);
    }
}

unittest {
    auto opt = new Option("--xx-dox, -x <file-path...>", "")
        .defalueVal("12345")
        .preset(123, 124);
    Option nopt = opt;
    assert(nopt.getDefaultArr == ["12345"]);
    assert(nopt.getPresetArr!int == [123, 124]);
}

class NegateOption {
    string shortFlag;
    string longFlag;

    string description;

    this(string flags, string description) {
        this.description = description;
        auto opt = splitOptionFlags(flags);
        this.shortFlag = opt.shortFlag;
        this.longFlag = opt.longFlag;
    }

    @property
    string name() const {
        if (!matchAll(this.longFlag, PTN_NEGATE))
            throw new InvalidFlagError;
        return this.longFlag[5 .. $].idup;
    }

    @property
    string attrName() const {
        return _camelCase(this.name);
    }

    bool isFlag(string flag) const {
        return this.shortFlag == flag || this.longFlag == flag;
    }
}

unittest {
    auto nopt = new NegateOption("-P, --no-print-warning", "");
    scope (exit) {
        writeln(nopt.name, " ", nopt.attrName);
        writeln(nopt.shortFlag);
        writeln(nopt.longFlag);
    }
    assert(nopt.name == "print-warning" && nopt.attrName == "printWarning");
}

private string _camelReducer(string str, string word = "") {
    return str ~ cast(char) word[0].toUpper ~ cast(string) word[1 .. $];
}

private string _camelCase(string str) {
    import std.algorithm : reduce;

    return str.split("-").reduce!(_camelReducer);
}

unittest {
    template TestCamelCase(string input, string expected) {
        bool flag = expected == _camelCase(input);
    }

    assert(TestCamelCase!("value-flag", "valueFlag").flag);
    assert(TestCamelCase!("s-s-s-s", "sSSS").flag);
    assert(TestCamelCase!("Val-cc", "ValCc").flag);
}

private OptionFlags splitOptionFlags(string flags) {
    string short_flag = "", long_flag = "", value_flag = "";
    string[] flag_arr = flags.split(PTN_SP);
    if (flag_arr.length > 3)
        throw new OptionFlagsError("");
    foreach (const ref string flag; flag_arr) {
        if (!matchAll(flag, PTN_SHORT).empty) {
            short_flag = flag;
            continue;
        }
        if (!matchAll(flag, PTN_LONG).empty) {
            long_flag = flag;
            continue;
        }
        if (!matchAll(flag, PTN_VALUE).empty) {
            value_flag = flag;
            continue;
        }
    }
    return OptionFlags(short_flag, long_flag, value_flag);
}

unittest {
    import std.stdio : stderr;

    mixin template TestFlags(string text) {
        string flags = text;
        auto opt = splitOptionFlags(flags);
        auto shortFlag = opt.shortFlag;
        auto longFlag = opt.longFlag;
        auto valueFlag = opt.valueFlag;
    }

    {
        mixin TestFlags!"-m, --mixed <value>";
        scope (failure)
            stderr.writeln(opt);
        assert(shortFlag == "-m" && longFlag == "--mixed" && valueFlag == "<value>");
    }
    {
        mixin TestFlags!"-m [value]";
        scope (failure)
            stderr.writeln(opt);
        assert(shortFlag == "-m" && longFlag == "" && valueFlag == "[value]");
    }
    {
        mixin TestFlags!"-m";
        scope (failure)
            stderr.writeln(opt);
        assert(shortFlag == "-m" && longFlag == "" && valueFlag == "");
    }
    {
        mixin TestFlags!"--mixed";
        scope (failure)
            stderr.writeln(opt);
        assert(longFlag == "--mixed" && shortFlag == "" && valueFlag == "");
    }
    {
        mixin TestFlags!"--mixed [value]";
        scope (failure)
            stderr.writeln(opt);
        assert(longFlag == "--mixed" && shortFlag == "" && valueFlag == "[value]");
    }
    {
        mixin TestFlags!"--mixed-flag <value>";
        scope (failure)
            stderr.writeln(opt);
        assert(longFlag == "--mixed-flag" && shortFlag == "" && valueFlag == "<value>");
    }
    {
        mixin TestFlags!"--mixed-flag-xx | -m [value-flag]";
        scope (failure)
            stderr.writeln(opt);
        assert(longFlag == "--mixed-flag-xx" && shortFlag == "-m" && valueFlag == "[value-flag]");
    }
    {
        mixin TestFlags!"--mixed-flag-xx | -m [value-flag...]";
        scope (failure)
            stderr.writeln(opt);
        assert(longFlag == "--mixed-flag-xx" && shortFlag == "-m" && valueFlag == "[value-flag...]");
    }
}

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
