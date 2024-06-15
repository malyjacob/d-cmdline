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

    string flags;

    bool required;
    bool optional;
    string shortFlag;
    string longFlag;

    string valueName;

    bool variadic;

    bool hidden;

    string[] conflictsWith;
    string envKey;
    ImplyOptionMap implyMap;

    bool found;
    bool settled;

    Source source;

    alias Self = typeof(this);
    alias ImplyOptionMap = OptionVariant[string];

    this(string flags, string description) {
        this.flags = flags;
        this.description = description;
        this.mandatory = false;
        this.defaultValueDescription = "";
        auto opt = splitOptionFlags(flags);
        this.shortFlag = opt.shortFlag;
        this.longFlag = opt.longFlag;
        assert(longFlag != "");
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
        this.hidden = false;
        // this.argChoices = [];
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
            bool signal = false;
            foreach (k; implyMap.byKey) {
                if (name == k[0 .. name.length]) {
                    signal = true;
                    break;
                }
            }
            if (signal)
                throw new ImplyOptionError;
            implyMap[name ~ ":" ~ bool.stringof] = true;
        }
        return this;
    }

    Self implies(T)(string key, T value) if (isOptionValueType!T) {
        bool signal = false;
        foreach (k; implyMap.byKey) {
            if (key == k[0 .. key.length]) {
                signal = true;
                break;
            }
        }
        if (signal)
            throw new ImplyOptionError;
        implyMap[key ~ ":" ~ T.stringof] = value;
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
        this.hidden = hide;
        return this;
    }

    @property
    string name() const {
        return this.longFlag[2 .. $].idup;
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

    Self choices(T)(T[] values) {
        auto is_variadic = this.variadic;
        if (is_variadic) {
            auto derived = cast(VariadicOption!T) this;
            return derived.choices(values);
        }
        else {
            auto derived = cast(ValueOption!T) this;
            return derived.choices(values);
        }
    }

    Self choices(T)(T value, T[] rest...) {
        auto tmp = rest ~ value;
        return choices(tmp);
    }

    Self rangeOf(T)(T min, T max) if (is(T == int) || is(T == double)) {
        auto is_variadic = this.variadic;
        if (is_variadic) {
            auto derived = cast(VariadicOption!T) this;
            return derived.rangeOf(min, max);
        }
        else {
            auto derived = cast(ValueOption!T) this;
            return derived.rangeOf(min, max);
        }
    }

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
        return implyVal(values[0], cast(T[]) values[1 .. $]);
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

    string typeStr() const {
        return "";
    }

    string defaultValStr() const {
        return "";
    }

    string presetStr() const {
        return "";
    }

    string envValStr() const {
        if (this.envKey == "")
            return this.envKey;
        return "env: " ~ this.envKey;
    }

    string implyOptStr() const {
        if (!implyMap)
            return "";
        auto str = "imply { ";
        foreach (key, val; implyMap) {
            auto captures = matchFirst(key, PTN_IMPLYMAPKEY);
            auto name = captures[1];
            auto is_variadic = captures[4] == "[]";
            auto type_str = captures[2];
            assert(name != "");
            string value;
            if (!is_variadic) {
                if (type_str == "bool")
                    value = val.get!bool
                        .to!string;
                if (type_str == "string")
                    value = val.get!string;
                if (type_str == "int")
                    value = val.get!int
                        .to!string;
                if (type_str == "double")
                    value = val.get!double
                        .to!string;
            }
            else {
                if (type_str == "string[]")
                    value = val.get!(string[])
                        .to!string;
                if (type_str == "int[]")
                    value = val.get!(int[])
                        .to!string;
                if (type_str == "double[]")
                    value = val.get!(double[])
                        .to!string;
            }
            str ~= (name ~ ": " ~ value ~ ", ");
        }
        str ~= "}";
        return str;
    }

    string conflictOptStr() const {
        if (this.conflictsWith.empty)
            return "";
        auto str = "conflict with [ ";
        conflictsWith.each!((name) { str ~= (name ~ ", "); });
        return str ~ "]";
    }

    string choicesStr() const {
        return "";
    }

    string rangeOfStr() const {
        return "";
    }
}

Option createOption(string flags, string desc = "") {
    return createOption!bool(flags, desc);
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

Option createOption(T : U[], U)(string flags, string desc = "")
        if (!is(U == bool) && isBaseOptionValueType!U) {
    return createOption!U(flags, desc);
}

unittest {
    Option[] opts = [
        new BoolOption("-m, --mixed", ""),
        new ValueOption!int("-m, --mixed [dig]", ""),
        new VariadicOption!int("-m, --mixed <dig...>", "")
    ];

    Option opt_1 = opts[0];
    Option opt_2 = opts[1];
    Option opt_3 = opts[2];

    opt_1.defaultVal().implyVal(false);
    opt_2.defaultVal().parser!((string v) => v.to!(int)).cliVal("123");
    opt_3.rangeOf(11, 150);
    opt_3.choices(12, 13, 14, 15, 123);
    opt_3.defaultVal([123]);
    opt_3.parser!((string v) => v.to!(int));
    opt_3.processor!((int a) => a + 1);
    opt_3.cliVal("12", "13", "14");

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
        if (this.settled)
            return this;
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
        assert(this.settled);
        return OptionVariant(this.innerData);
    }

    @property
    bool get(T : bool)() const {
        assert(this.settled);
        return this.innerData;
    }

    override string typeStr() const {
        return "type: " ~ "bool";
    }

    override string defaultValStr() const {
        if (defaultArg.isNull)
            return "";
        else
            return "default: " ~ this.get!bool
                .to!string;
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

    T[] argChoices;

    static if (is(T == int) || is(T == double)) {
        T _min = int.min;
        T _max = int.max;
    }

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
        this.argChoices = [];
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

    Self choices(T[] values...) {
        foreach (index_i, i; values) {
            foreach (j; values[index_i + 1 .. $]) {
                assert(i != j);
            }
        }
        static if (is(T == int) || is(T == double)) {
            assert(values.find!(val => val < this._min || val > this._max).empty);
        }
        this.argChoices = values;
        return this;
    }

    void _checkVal(in T value) const {
        if (!this.argChoices.empty)
            assert(this.argChoices.count(value));
        static if (is(T == int) || is(T == double)) {
            assert(value >= this._min && value <= this._max);
        }
    }

    static if (is(T == int) || is(T == double)) {
        Self rangeOf(T min, T max) {
            assert(max > min);
            this._min = min;
            this._max = max;
            return this;
        }

        Self choices(string[] values...) {
            auto fn = this.parseFn;
            auto arr = values.map!fn.array;
            return this.choices(arr);
        }

        override string rangeOfStr() const {
            return "range: " ~ _min.to!string ~ " ~ " ~ _max.to!string;
        }
    }

    Self defaultVal(T value) {
        _checkVal(value);
        this.defaultArg = value;
        return this;
    }

    override Self defaultVal() {
        assert(isOptional);
        this.defaultArg = true;
        return this;
    }

    Self configVal(T value) {
        _checkVal(value);
        this.configArg = value;
        return this;
    }

    override Self configVal() {
        assert(isOptional);
        this.configArg = true;
        return this;
    }

    Self implyVal(T value) {
        _checkVal(value);
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
        auto tmp = this.parseFn(value);
        _checkVal(tmp);
        this.cliArg = tmp;
        return this;
    }

    override Self envVal() {
        auto tmp = this.parseFn(this.envStr);
        _checkVal(tmp);
        this.envArg = tmp;
        return this;
    }

    Self preset(T value) {
        _checkVal(value);
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
        if (this.settled)
            return this;
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
        assert(this.settled);
        auto fn = this.processFn;
        T tmp = fn(this.innerValueData);
        return isValueData ? OptionVariant(tmp) : OptionVariant(this.innerBoolData);
    }

    @property
    bool get(U : bool)() const {
        assert(this.settled);
        assert(!this.isValueData);
        return this.innerBoolData;
    }

    @property
    T get(U : T)() const {
        assert(this.settled);
        assert(this.isValueData);
        auto fn = this.processFn;
        T tmp = fn(this.innerValueData);
        return tmp;
    }

    override string typeStr() const {
        return "type: " ~ (this.isOptional ? T.stringof ~ "|true" : T.stringof);
    }

    override string defaultValStr() const {
        if (defaultArg.isNull)
            return "";
        return "default: " ~ defaultArg.get!T
            .to!string;
    }

    override string presetStr() const {
        if (presetArg.isNull)
            return "";
        alias test_bool = visit!((bool v) => true, (const T v) => false);
        alias test_t = visit!((const T v) => true, (bool v) => false);
        if (test_bool(presetArg))
            return "preset: " ~ presetArg.get!bool
                .to!string;
        if (test_t(presetArg))
            return "preset: " ~ presetArg.get!T
                .to!string;
        throw new CMDLineError;
    }

    override string choicesStr() const {
        if (argChoices.empty)
            return "";
        return "choices " ~ argChoices.to!string;
    }
}

unittest {
    auto vopt = new ValueOption!int("-m, --mixed [raw]", "");
    vopt.defaultVal(123);
    vopt.preset(125);
    vopt.found = true;
    vopt.initialize;
    assert(vopt.get == 125);
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

    T[] argChoices;

    ProcessReduceFn!T processReduceFn;

    static if (is(T == int) || is(T == double)) {
        T _min = int.min;
        T _max = int.max;
    }

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
        this.argChoices = [];
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

    Self choices(T[] values...) {
        foreach (index_i, i; values) {
            foreach (j; values[index_i + 1 .. $]) {
                assert(i != j);
            }
        }
        static if (is(T == int) || is(T == double)) {
            assert(values.find!(val => val < this._min || val > this._max).empty);
        }
        this.argChoices = values;
        return this;
    }

    void _checkVal_impl(in T value) const {
        if (!this.argChoices.empty)
            assert(this.argChoices.count(value));
        static if (is(T == int) || is(T == double)) {
            assert(value >= this._min && value <= this._max);
        }
    }

    void _checkVal(T value, T[] rest...) const {
        _checkVal_impl(value);
        foreach (T val; rest) {
            _checkVal_impl(val);
        }
    }

    void _checkVal(T[] values) const {
        assert(values.length > 0);
        foreach (T val; values) {
            _checkVal_impl(val);
        }
    }

    static if (is(T == int) || is(T == double)) {
        Self rangeOf(T min, T max) {
            assert(max > min);
            this._min = min;
            this._max = max;
            return this;
        }

        Self choices(string[] values...) {
            auto fn = this.parseFn;
            auto arr = values.map!fn.array;
            return this.choices(arr);
        }

        override string rangeOfStr() const {
            return "range: " ~ _min.to!string ~ " ~ " ~ _max.to!string;
        }
    }

    Self defaultVal(T value, T[] rest...) {
        auto tmp = [value] ~ rest;
        _checkVal(tmp);
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
        _checkVal(tmp);
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
        _checkVal(tmp);
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
        auto xtmp = tmp.map!(fn).array;
        _checkVal(xtmp);
        this.cliArg = xtmp;
        return this;
    }

    override Self envVal() {
        string[] str_arr = split(this.envStr, regex(`;`)).filter!(v => v != "").array;
        auto fn = parseFn;
        auto tmp = str_arr.map!(fn).array;
        _checkVal(tmp);
        this.envArg = tmp;
        return this;
    }

    Self preset(T value, T[] rest...) {
        auto tmp = [value] ~ rest;
        _checkVal(tmp);
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
        if (this.settled)
            return this;
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
        assert(this.settled);
        if (isValueData) {
            auto fn = this.processFn;
            auto tmp = this.innerValueData.map!fn.array;
            return OptionVariant(tmp);
        }
        return OptionVariant(this.innerBoolData);
    }

    @property
    bool get(U : bool)() const {
        assert(this.settled);
        assert(!this.isValueData);
        return this.innerBoolData;
    }

    @property
    T[] get(U : T[])() const {
        assert(this.settled);
        assert(this.isValueData);
        auto fn = this.processFn;
        auto tmp = this.innerValueData.map!fn.array;
        return tmp;
    }

    @property
    T get(U : T)() const {
        assert(this.settled);
        assert(this.isValueData);
        auto process_fn = this.processFn;
        auto reduce_fn = this.processReduceFn;
        auto tmp = this.innerValueData
            .map!process_fn
            .reduce!reduce_fn;
        return tmp;
    }

    override string typeStr() const {
        return "type: " ~ (isOptional ? T.stringof ~ "[]|true" : T.stringof ~ "[]");
    }

    override string defaultValStr() const {
        if (defaultArg.isNull)
            return "";
        return "default: " ~ defaultArg.get!(T[])
            .to!string;
    }

    override string presetStr() const {
        if (presetArg.isNull)
            return "";
        alias test_bool = visit!((const T[] v) => false, (bool v) => true);
        alias test_t = visit!((const T[] v) => true, (bool v) => false);
        // pragma(msg, typeof(test_bool).stringof);
        if (test_bool(presetArg))
            return "preset: " ~ presetArg.get!bool
                .to!string;
        if (test_t(presetArg))
            return "preset: " ~ presetArg.get!(T[])
                .to!string;
        throw new CMDLineError;
    }

    override string choicesStr() const {
        if (argChoices.empty)
            return "";
        return "choices " ~ argChoices.to!string;
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
    string flags;
    string description;

    bool hidden;

    this(string flags, string description) {
        this.flags = flags;
        this.description = description;
        this.hidden = false;
        auto opt = splitOptionFlags(flags);
        this.shortFlag = opt.shortFlag;
        this.longFlag = opt.longFlag;
        assert(!(matchFirst(this.longFlag, PTN_NEGATE)).empty);
    }

    @property
    string name() const {
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

NegateOption createNegateOption(string flags, string desc = "") {
    return new NegateOption(flags, desc);
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
