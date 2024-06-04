module cmdline.option;

import std.stdio;
import std.string;
import std.regex;
import std.meta;
import std.traits;
import std.conv;
import std.process;
import std.range.primitives;
import std.algorithm;
import std.array;

import mir.algebraic;

import cmdline.error;
import cmdline.pattern;

private struct OptionFlags {
    string shortFlag = "";
    string longFlag = "";
    string valueFlag = "";
}

alias OptionBaseValue = AliasSeq!(string, int, double, bool);
alias OptionArrayValue = AliasSeq!(string[], int[], double[]);
alias OptionValueSeq = AliasSeq!(OptionBaseValue, OptionArrayValue);

alias OptionNullable = Nullable!OptionValueSeq;
alias OptionVariant = Variant!OptionValueSeq;

enum Source {
    None,
    Cli,
    Env,
    Imply,
    Config,
    Default,
    Preset
}

alias ParseArgFn(Target) = Target function(string str);

alias ProcessArgFn(Target) = Target function(Target value);

alias ProcessReduceFn(Target) = Target function(Target cur, Target prev);

template isBaseOptionValueType(T) {
    enum bool isBaseOptionValueType = isBoolean!T || allSameType!(T, int) ||
        allSameType!(T, double) || allSameType!(T, string);
}

template isOptionValueType(T) {
    static if (isDynamicArray!T && !allSameType!(T, string)) {
        enum bool isOptionValueType = !is(ElementType!T == bool) && isBaseOptionValueType!(
                ElementType!T);
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
    string envKey;
    ImplyOptionMap implyMap;

    bool found;
    bool settled;

    Source source;

    alias Self = typeof(this);
    alias ImplyOptionMap = OptionVariant[string];

    this(string flags, string description) {
        this.description = description;
        this.mandatory = false;
        this.defaultValueDescription = "";
        auto opt = splitOptionFlags(flags);
        this.shortFlag = opt.shortFlag;
        this.longFlag = opt.longFlag;
        this.variadic = (opt.valueFlag == "" || opt.valueFlag[$ - 2] != '.') ? false : true;
        this.valueName = opt.valueFlag == "" ? "" : this.variadic ? opt.valueFlag[1 .. $ - 4].idup
            : opt.valueFlag[1 .. $ - 1].idup;
        if (this.valueName == "") {
            this.required = this.optional = false;
        }
        else {
            this.required = opt.valueFlag[0] == '<' ? true : false;
            this.optional = opt.valueFlag[0] == '[' ? true : false;
        }
        this.hiden = false;
        this.argChoices = [];
        this.conflictsWith = [];
        this.implyMap = null;
        this.envKey = "";

        this.found = false;
        this.settled = false;

        this.source = Source.None;
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
            auto value_ptr = name in this.implyMap;
            if (value_ptr !is null)
                throw new ImplyOptionError;
            implyMap[name] = true;
        }
        return this;
    }

    Self implies(T)(const T[string] optionMap) if (isOptionValueType!T) {
        assert(optionMap !is null);
        foreach (key, value; optionMap) {
            auto value_ptr = key in this.implyMap;
            if (value_ptr !is null)
                throw new ImplyOptionError;
            implyMap[key] = value;
        }
        return this;
    }

    Self env(string name) {
        this.envKey = name;
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

    @property
    string envStr() const {
        assert(this.envKey.length);
        auto raw = environment.get(this.envKey);
        return raw;
    }

    bool isFlag(string flag) const {
        return this.shortFlag == flag || this.longFlag == flag;
    }

    @property
    bool isBoolean() const {
        return this.valueName.length == 0;
    }

    @property
    bool isOptional() const {
        return (!this.required && this.optional);
    }

    @property
    bool isRequired() const {
        return (!this.optional && this.required);
    }

    // for being inhelited
    Self defaultVal() {
        throw new OptionMemberFnCallError;
    }

    Self configVal() {
        throw new OptionMemberFnCallError;
    }

    Self implyVal() {
        throw new OptionMemberFnCallError;
    }

    Self envVal() {
        throw new OptionMemberFnCallError;
    }

    Self preset() {
        throw new OptionMemberFnCallError;
    }

    Self cliVal(string value, string[] rest...) {
        throw new OptionMemberFnCallError;
    }

    @property
    abstract bool isValid() const;
    @property
    abstract OptionVariant get() const;
    abstract Self initialize();

    Self defaultVal(T)(T value) if (isBaseOptionValueType!T) {
        static if (is(T == bool)) {
            auto derived = cast(BoolOption) this;
        }
        else {
            auto derived = cast(ValueOption!T) this;
        }
        return derived.defaultVal(value);
    }

    Self defaultVal(T)(T value, T[] rest...)
            if (isBaseOptionValueType!T && !is(T == bool)) {
        auto derived = cast(VariadicOption!T) this;
        return derived.defaultVal(value, rest);
    }

    Self defaultVal(T)(in T[] values) if (isBaseOptionValueType!T && !is(T == bool)) {
        assert(values.length > 0);
        return defaultVal(values[0], cast(T[]) values[1 .. $]);
    }

    Self configVal(T)(T value) if (isBaseOptionValueType!T) {
        static if (is(T == bool)) {
            auto derived = cast(BoolOption) this;
        }
        else {
            auto derived = cast(ValueOption!T) this;
        }
        return derived.configVal(value);
    }

    Self configVal(T)(T value, T[] rest...)
            if (isBaseOptionValueType!T && !is(T == bool)) {
        auto derived = cast(VariadicOption!T) this;
        return derived.configVal(value, rest);
    }

    Self configVal(T)(in T[] values) if (isBaseOptionValueType!T && !is(T == bool)) {
        assert(values.length > 0);
        return configVal(values[0], cast(T[]) values[1 .. $]);
    }

    Self implyVal(T)(T value) if (isBaseOptionValueType!T) {
        static if (is(T == bool)) {
            auto derived = cast(BoolOption) this;
        }
        else {
            auto derived = cast(ValueOption!T) this;
        }
        return derived.implyVal(value);
    }

    Self implyVal(T)(T value, T[] rest...)
            if (isBaseOptionValueType!T && !is(T == bool)) {
        auto derived = cast(VariadicOption!T) this;
        return derived.implyVal(value, rest);
    }

    Self implyVal(T)(in T[] values) if (isBaseOptionValueType!T && !is(T == bool)) {
        assert(values.length > 0);
        return implytVal(values[0], cast(T[]) values[1 .. $]);
    }

    Self preset(T)(T value) if (isBaseOptionValueType!T && !is(T == bool)) {
        auto derived = cast(ValueOption!T) this;
        return derived.preset(value);
    }

    Self preset(T)(T value, T[] rest...)
            if (isBaseOptionValueType!T && !is(T == bool)) {
        auto derived = cast(VariadicOption!T) this;
        return derived.preset(value, rest);
    }

    Self preset(T)(in T[] values) if (isBaseOptionValueType!T && !is(T == bool)) {
        assert(values.length > 0);
        return preset(values[0], cast(T[]) values[1 .. $]);
    }

    T get(T)() const {
        return this.get.get!T;
    }

    Self parser(alias fn)() {
        alias T = typeof({ string v; return fn(v); }());
        static assert(isBaseOptionValueType!T && !is(T == bool));
        Self result_this;
        try {
            auto derived = this.to!(ValueOption!T);
            derived.parseFn = fn;
            result_this = derived;
        }
        catch (ConvException e) {
            auto derived = this.to!(VariadicOption!T);
            derived.parseFn = fn;
            result_this = derived;
        }
        return result_this;
    }

    Self processor(alias fn)() {
        alias return_t = ReturnType!fn;
        alias param_t = Parameters!fn;
        static assert(param_t.length == 1 && is(return_t == param_t[0]));
        static assert(isBaseOptionValueType!return_t && !is(return_t == bool));
        alias T = return_t;
        Self result_this;
        try {
            auto derived = this.to!(ValueOption!T);
            derived.processFn = fn;
            result_this = derived;
        }
        catch (ConvException e) {
            auto derived = this.to!(VariadicOption!T);
            derived.processFn = fn;
            result_this = derived;
        }
        return result_this;
    }

    Self processReducer(alias fn)() {
        alias return_t = ReturnType!fn;
        alias param_t = Parameters!fn;
        static assert(allSameType!(return_t, param_t) && param_t.length == 2);
        alias T = return_t;
        static assert(isBaseOptionValueType!T && !is(T == bool));
        auto derived = this.to!(VariadicOption!T);
        derived.processReduceFn = fn;
        return derived;
    }
}

Option createOption(T : bool)(string flags, string desc = "") {
    auto opt = splitOptionFlags(flags);
    bool is_bool = opt.valueFlag == "";
    assert(is_bool);
    return new BoolOption(flags, desc);
}

Option createOption(T)(string flags, string desc = "")
        if (!is(T == bool) && isBaseOptionValueType!T) {
    auto opt = splitOptionFlags(flags);
    bool is_bool = opt.valueFlag == "";
    bool is_variadic = (is_bool || opt.valueFlag[$ - 2] != '.') ? false : true;
    assert(!is_bool);
    if (is_variadic) {
        return new VariadicOption!T(flags, desc);
    }
    else {
        return new ValueOption!T(flags, desc);
    }
}

unittest {
    Option[] opts = [
        new BoolOption("-m, --mixed", ""),
        new ValueOption!int("-m, --mixed [dig]", ""),
        new VariadicOption!int("-m, --mixed <dig...>", "")
    ];

    auto opt_1 = opts[0];
    auto opt_2 = opts[1];
    auto opt_3 = opts[2];

    opt_1.defaultVal().implyVal(false);
    opt_2.defaultVal().parser!((string v) => v.to!(int)).cliVal("123");
    opt_3.defaultVal([123]).parser!((string v) => v.to!(int))
        .processor!((int a) => a + 1)
        .cliVal("12", "13", "14");

    opt_1.initialize();
    opt_2.found = true;
    opt_2.initialize();
    opt_3.found = true;
    opt_3.initialize();

    assert(opt_1.get!bool == false);
    assert(opt_2.get!int == 123);
    assert(opt_3.get!(int[]) == [13, 14, 15]);
}

unittest {
    Option[] opts = [
        createOption!bool("-m, --mixed").defaultVal.implyVal(false),
        createOption!int("-m, --mixed [dig]", "")
            .defaultVal.parser!((string v) => v.to!(int)).cliVal("123"),
        createOption!int("-m, --mixed <dig...>", "").defaultVal([123])
            .parser!((string v) => v.to!(int))
            .processor!((int a) => a + 1)
            .cliVal("12", "13", "14")
    ];
    opts[1].found = opts[2].found = true;
    opts.each!(v => v.initialize);

    assert(opts[0].get!bool == false);
    assert(opts[1].get!int == 123);
    assert(opts[2].get!(int[]) == [13, 14, 15]);
}

class BoolOption : Option {
    Nullable!bool implyArg;
    Nullable!bool configArg;
    Nullable!bool defaultArg;

    bool innerData;

    this(string flags, string description) {
        super(flags, description);
        assert(this.isBoolean);
        assert(!this.variadic);
        this.implyArg = null;
        this.configArg = null;
        this.defaultArg = null;
        this.innerData = false;
    }

    alias Self = typeof(this);

    Self defaultVal(bool value) {
        this.defaultArg = value;
        return this;
    }

    override Self defaultVal() {
        this.defaultArg = true;
        return this;
    }

    Self configVal(bool value) {
        this.configArg = value;
        return this;
    }

    override Self configVal() {
        this.configArg = true;
        return this;
    }

    Self implyVal(bool value) {
        this.implyArg = value;
        return this;
    }

    override Self implyVal() {
        this.implyArg = true;
        return this;
    }

    @property
    override bool isValid() const {
        return this.found || !this.implyArg.isNull
            || !this.configArg.isNull || !this.defaultArg.isNull;
    }

    override Self initialize() {
        assert(this.isValid);
        this.settled = true;
        if (this.found) {
            this.innerData = (true);
            this.source = Source.Cli;
            return this;
        }
        if (!this.implyArg.isNull) {
            this.innerData = this.implyArg.get;
            this.source = Source.Imply;
            return this;
        }
        if (!this.configArg.isNull) {
            this.innerData = this.configArg.get;
            this.source = Source.Config;
            return this;
        }
        if (!this.defaultArg.isNull) {
            this.innerData = this.defaultArg.get;
            this.source = Source.Default;
            return this;
        }
        return this;
    }

    @property
    override OptionVariant get() const {
        assert(this.isValid && this.settled);
        return OptionVariant(this.innerData);
    }

    @property
    bool get(T : bool)() const {
        assert(this.isValid && this.settled);
        return this.innerData;
    }
}

unittest {
    auto bopt = new BoolOption("-m, --mixed", "").implyVal(false).configVal.defaultVal;
    bopt.initialize;
    bool value = bopt.get!bool;
    assert(!value);
}

class ValueOption(T) : Option {
    static assert(isBaseOptionValueType!T && !is(T == bool));

    Nullable!T cliArg;
    Nullable!T envArg;
    Nullable!(T, bool) implyArg;
    Nullable!(T, bool) configArg;
    Nullable!(T, bool) defaultArg;

    Nullable!(T, bool) presetArg;

    T innerValueData;
    bool innerBoolData;

    bool isValueData;

    ParseArgFn!T parseFn;
    ProcessArgFn!T processFn;

    this(string flags, string description) {
        super(flags, description);
        assert(!this.isBoolean);
        assert(!this.variadic);
        this.cliArg = null;
        this.envArg = null;
        this.implyArg = null;
        this.configArg = null;
        this.defaultArg = null;
        innerBoolData = false;
        innerValueData = T.init;
        isValueData = true;
        this.parseFn = (string v) => to!T(v);
        this.processFn = v => v;
        if (isRequired)
            this.presetArg = null;
        else if (isOptional)
            this.presetArg = true;
        else
            throw new CMDLineError;
    }

    alias Self = typeof(this);

    Self defaultVal(T value) {
        this.defaultArg = value;
        return this;
    }

    override Self defaultVal() {
        assert(isOptional);
        this.defaultArg = true;
        return this;
    }

    Self configVal(T value) {
        this.configArg = value;
        return this;
    }

    override Self configVal() {
        assert(isOptional);
        this.configArg = true;
        return this;
    }

    Self implyVal(T value) {
        this.implyArg = value;
        return this;
    }

    override Self implyVal() {
        assert(isOptional);
        this.implyArg = true;
        return this;
    }

    override Self cliVal(string value, string[] rest...) {
        assert(rest.length == 0);
        this.cliArg = this.parseFn(value);
        return this;
    }

    override Self envVal() {
        this.envArg = this.parseFn(this.envStr);
        return this;
    }

    Self preset(T value) {
        this.presetArg = value;
        return this;
    }

    override Self preset() {
        assert(isOptional);
        this.presetArg = true;
        return this;
    }

    @property
    override bool isValid() const {
        return this.found ? (!this.presetArg.isNull || !this.cliArg.isNull) : (!this.envArg.isNull || !this
                .implyArg.isNull || !this.configArg.isNull || !this
                .defaultArg.isNull);
    }

    override Self initialize() {
        assert(this.isValid);
        this.settled = true;
        alias test_bool = visit!((bool v) => true, (T v) => false);
        alias test_t = visit!((T v) => true, (bool v) => false);
        if (this.found) {
            if (!this.cliArg.isNull) {
                this.innerValueData = this.cliArg.get!T;
                this.source = Source.Cli;
                return this;
            }
            if (test_bool(this.presetArg)) {
                this.isValueData = false;
                this.innerBoolData = this.presetArg.get!bool;
            }
            if (test_t(this.presetArg)) {
                this.innerValueData = this.presetArg.get!T;
            }
            this.source = Source.Preset;
            return this;
        }
        if (!this.envArg.isNull) {
            this.innerValueData = this.envArg.get!T;
            this.source = Source.Env;
            return this;
        }
        if (!this.implyArg.isNull) {
            if (test_bool(this.implyArg)) {
                this.isValueData = false;
                this.innerBoolData = this.implyArg.get!bool;
            }
            if (test_t(this.implyArg))
                this.innerValueData = this.implyArg.get!T;
            this.source = Source.Imply;
            return this;
        }
        if (!this.configArg.isNull) {
            if (test_bool(this.configArg)) {
                this.isValueData = false;
                this.innerBoolData = this.configArg.get!bool;
            }
            if (test_t(this.configArg))
                this.innerValueData = this.configArg.get!T;
            this.source = Source.Config;
            return this;
        }
        if (!this.defaultArg.isNull) {
            if (test_bool(this.defaultArg)) {
                this.isValueData = false;
                this.innerBoolData = this.defaultArg.get!bool;
            }
            if (test_t(this.defaultArg))
                this.innerValueData = this.defaultArg.get!T;
            this.source = Source.Imply;
            return this;
        }
        return this;
    }

    @property
    override OptionVariant get() const {
        assert(this.isValid && this.settled);
        auto fn = this.processFn;
        T tmp = fn(this.innerValueData);
        return isValueData ? OptionVariant(tmp) : OptionVariant(this.innerBoolData);
    }

    @property
    bool get(U : bool)() const {
        assert(this.isValid && this.settled);
        assert(!this.isValueData);
        return this.innerBoolData;
    }

    @property
    T get(U : T)() const {
        assert(this.isValid && this.settled);
        assert(this.isValueData);
        auto fn = this.processFn;
        T tmp = fn(this.innerValueData);
        return tmp;
    }
}

unittest {
    auto vopt = new ValueOption!int("-m, --mixed [raw]", "");
    vopt.defaultVal(123);
    vopt.found = true;
    vopt.initialize;
    assert(vopt.get == true);
}

class VariadicOption(T) : Option {
    static assert(isBaseOptionValueType!T && !is(T == bool));

    Nullable!(T[]) cliArg;
    Nullable!(T[]) envArg;
    Nullable!(T[], bool) implyArg;
    Nullable!(T[], bool) configArg;
    Nullable!(T[], bool) defaultArg;

    Nullable!(T[], bool) presetArg;

    T[] innerValueData;
    bool innerBoolData;

    bool isValueData;

    ParseArgFn!T parseFn;
    ProcessArgFn!T processFn;

    ProcessReduceFn!T processReduceFn;

    this(string flags, string description) {
        super(flags, description);
        assert(!this.isBoolean);
        assert(this.variadic);
        this.cliArg = null;
        this.envArg = null;
        this.implyArg = null;
        this.configArg = null;
        this.defaultArg = null;
        innerBoolData = false;
        innerValueData = null;
        isValueData = true;
        this.parseFn = (string v) => to!T(v);
        this.processFn = v => v;
        this.processReduceFn = (T cur, T prev) => cur;
        if (isRequired)
            this.presetArg = null;
        else if (isOptional)
            this.presetArg = true;
        else
            throw new CMDLineError;
    }

    alias Self = typeof(this);

    Self defaultVal(T value, T[] rest...) {
        auto tmp = [value] ~ rest;
        this.defaultArg = tmp;
        return this;
    }

    override Self defaultVal() {
        assert(isOptional);
        this.defaultArg = true;
        return this;
    }

    Self configVal(T value, T[] rest...) {
        auto tmp = [value] ~ rest;
        this.configArg = tmp;
        return this;
    }

    override Self configVal() {
        assert(isOptional);
        this.configArg = true;
        return this;
    }

    Self implyVal(T value, T[] rest...) {
        auto tmp = [value] ~ rest;
        this.implyArg = tmp;
        return this;
    }

    override Self implyVal() {
        assert(isOptional);
        this.implyArg = true;
        return this;
    }

    override Self cliVal(string value, string[] rest...) {
        string[] tmp = [value] ~ rest;
        auto fn = parseFn;
        this.cliArg = tmp.map!(fn).array;
        return this;
    }

    override Self envVal() {
        string[] str_arr = split(this.envStr, regex(`;`)).filter!(v => v != "").array;
        auto fn = parseFn;
        this.envArg = str_arr.map!(fn).array;
        return this;
    }

    Self preset(T value, T[] rest...) {
        auto tmp = [value] ~ rest;
        this.presetArg = tmp;
        return this;
    }

    override Self preset() {
        assert(isOptional);
        this.presetArg = true;
        return this;
    }

    @property
    override bool isValid() const {
        return this.found ? (!this.presetArg.isNull || !this.cliArg.isNull) : (!this.envArg.isNull || !this
                .implyArg.isNull || !this.configArg.isNull || !this
                .defaultArg.isNull);
    }

    override Self initialize() {
        assert(this.isValid);
        this.settled = true;
        alias test_bool = visit!((T[] v) => false, (bool v) => true);
        alias test_t = visit!((T[] v) => true, (bool v) => false);
        if (this.found) {
            if (!this.cliArg.isNull) {
                this.innerValueData = this.cliArg.get!(T[]);
                this.source = Source.Cli;
                return this;
            }
            if (test_bool(this.presetArg)) {
                this.isValueData = false;
                this.innerBoolData = this.presetArg.get!bool;
            }
            if (test_t(this.presetArg)) {
                this.innerValueData = this.presetArg.get!(T[]);
            }
            this.source = Source.Preset;
            return this;
        }
        if (!this.envArg.isNull) {
            this.innerValueData = this.envArg.get!(T[]);
            this.source = Source.Env;
            return this;
        }
        if (!this.implyArg.isNull) {
            if (test_bool(this.implyArg)) {
                this.isValueData = false;
                this.innerBoolData = this.implyArg.get!bool;
            }
            if (test_t(this.implyArg))
                this.innerValueData = this.implyArg.get!(T[]);
            this.source = Source.Imply;
            return this;
        }
        if (!this.configArg.isNull) {
            if (test_bool(this.configArg)) {
                this.isValueData = false;
                this.innerBoolData = this.configArg.get!bool;
            }
            if (test_t(this.configArg))
                this.innerValueData = this.configArg.get!(T[]);
            this.source = Source.Config;
            return this;
        }
        if (!this.defaultArg.isNull) {
            if (test_bool(this.defaultArg)) {
                this.isValueData = false;
                this.innerBoolData = this.defaultArg.get!bool;
            }
            if (test_t(this.defaultArg))
                this.innerValueData = this.defaultArg.get!(T[]);
            this.source = Source.Imply;
            return this;
        }
        return this;
    }

    @property
    override OptionVariant get() const {
        assert(this.isValid && this.settled);
        if (isValueData) {
            auto fn = this.processFn;
            auto tmp = this.innerValueData.map!fn.array;
            return OptionVariant(tmp);
        }
        return OptionVariant(this.innerBoolData);
    }

    @property
    bool get(U : bool)() const {
        assert(this.isValid && this.settled);
        assert(!this.isValueData);
        return this.innerBoolData;
    }

    @property
    T[] get(U : T[])() const {
        assert(this.isValid && this.settled);
        assert(this.isValueData);
        auto fn = this.processFn;
        auto tmp = this.innerValueData.map!fn.array;
        return tmp;
    }

    @property
    T get(U : T)() const {
        assert(this.isValid && this.settled);
        assert(this.isValueData);
        auto process_fn = this.processFn;
        auto reduce_fn = this.processReduceFn;
        auto tmp = this.innerValueData
            .map!process_fn
            .reduce!reduce_fn;
        return tmp;
    }
}

unittest {
    auto vopt = new VariadicOption!int("-n, --number [num...]", "");
    vopt.defaultVal(1, 2, 3, 4, 5, 6, 7);
    vopt.processReduceFn = (int a, int b) => a + b;
    vopt.initialize;
    assert(vopt.get!int == 28);
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

package string _camelCase(string str) {
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

// __gshared Regex!char PTN_SHORT;
// __gshared Regex!char PTN_LONG;
// __gshared Regex!char PTN_VALUE;
// __gshared Regex!char PTN_SP;
// __gshared Regex!char PTN_NEGATE;

// shared static this() {
//     PTN_SHORT = regex(`^-\w$`);
//     PTN_LONG = regex(`^--[(\w\-)\w]+\w$`);
//     PTN_NEGATE = regex(`^--no-[(\w\-)\w]+\w$`);
//     PTN_VALUE = regex(`(<[(\w\-)\w]+\w(\.{3})?>$)|(\[[(\w\-)\w]+\w(\.{3})?\]$)`);
//     PTN_SP = regex(`[ |,]+`);
// }
