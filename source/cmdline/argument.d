module cmdline.argument;

import std.conv;
import std.range.primitives;

import mir.algebraic;

import cmdline.error;
import cmdline.option;

alias ArgBaseValue = OptionBaseValue;
alias ArgArrayValue = OptionArrayValue;
alias ArgValueSeq = OptionValueSeq;

alias ArgNullable = Nullable!ArgValueSeq;
alias ArgVariant = Variant!ArgValueSeq;

alias isBaseArgValueType(T) = isBaseOptionValueType!T;
alias isArgValueType(T) = isOptionValueType!T;
alias ArgMemberFnCallError = cmdline.error.OptionMemberFnCallError;

class Argument {
    string description;
    string defaultDescription;
    bool required;
    bool variadic;
    string[] argChoices;

    string _name;

    bool settled;
    Source source;

    this(string flag, string description) {
        this.description = description;
        this.defaultDescription = "";
        switch (flag[0]) {
        case '<':
            this.required = true;
            this._name = flag[1 .. $ - 1].idup;
            break;
        case '[':
            this.required = false;
            this._name = flag[1 .. $ - 1].idup;
            break;
        default:
            this.required = true;
            this._name = flag.idup;
            break;
        }
        auto has_3_dots = this._name[$ - 3 .. $] == "...";
        if (this._name.length > 3 && has_3_dots) {
            this.variadic = true;
            this._name = this._name[0 .. $ - 3].idup;
        }
        this.argChoices = [];
        this.settled = false;
        this.source = Source.None;
    }

    alias Self = typeof(this);

    @property
    string name() const {
        return this.name.idup;
    }

    @property
    string attrName() const {
        return _camelCase(this._name);
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
    bool isRequired() const {
        return this.required;
    }

    @property
    bool isOptional() const {
        return !this.required;
    }

    Self defaultVal() {
        throw new ArgMemberFnCallError;
    }

    Self configVal() {
        throw new ArgMemberFnCallError;
    }

    abstract bool isValid() const;
    abstract Self cliVal(string value, string[] rest...);
    abstract Self initialize();
    abstract ArgVariant get() const;

    Self defaultVal(T)(T value) if (isBaseArgValueType!T) {
        auto derived = cast(ValueArgument!T) this;
        return derived.defaultVal(value);
    }

    Self defaultVal(T)(T value, T[] rest...)
            if (isBaseArgValueType!T && !is(T == bool)) {
        auto derived = cast(ValueArgument!(T[])) this;
        return derived.defaultVal(value, rest);
    }

    Self defaultVal(T)(in T[] values) if (isBaseArgValueType!T && !is(T == bool)) {
        assert(values.length > 0);
        return defaultVal(values[0], cast(T[]) values[1 .. $]);
    }

    Self configVal(T)(T value) if (isBaseArgValueType!T) {
        auto derived = cast(ValueArgument!T) this;
        return derived.configVal(value);
    }

    Self configVal(T)(T value, T[] rest...)
            if (isBaseArgValueType!T && !is(T == bool)) {
        auto derived = cast(ValueArgument!(T[])) this;
        return derived.configVal(value, rest);
    }

    Self configVal(T)(in T[] values) if (isBaseArgValueType!T && !is(T == bool)) {
        assert(values.length > 0);
        return configVal(values[0], cast(T[]) values[1 .. $]);
    }

    T get(T)() const {
        return this.get.get!T;
    }
}

Argument createArgument(T : bool)(string flag, string desc = "") {
    bool is_variadic = flag[$ - 2] == '.';
    assert(!is_variadic);
    return new ValueArgument!bool(flag, desc);
}

Argument createArgument(T = bool)(string flag, string desc = "")
        if (!is(T == bool) && isBaseArgValueType!T) {
    bool is_variadic = flag[$ - 2] == '.';
    if (is_variadic) {
        return new ValueArgument!(T[])(flag, desc);
    }
    else {
        return new ValueArgument!T(flag, desc);
    }
}

unittest {
    Argument[] args = [
        createArgument!int("<int>", ""),
        createArgument!string("[str]", ""),
        createArgument!int("<int>", ""),
        createArgument!(double)("<int...>", "")
    ];
    import std.array;
    import std.algorithm;

    each!((Argument v) => v.cliVal("12").initialize)(args);

    assert(args[0].get!int == 12);
    assert(args[1].get!string == "12");
    assert(args[2].get!int == 12);
    assert(args[3].get!(double[]) == [12f]);
}

class ValueArgument(T) : Argument {
    static assert(isArgValueType!T);
    Nullable!T cliArg;
    Nullable!T configArg;
    Nullable!T defaultArg;

    T innerData;

    this(string flag, string description) {
        super(flag, description);
        this.cliArg = null;
        this.configArg = null;
        this.defaultArg = null;
        this.innerData = T.init;
    }

    alias Self = typeof(this);

    Self defaultVal(T value) {
        this.defaultArg = value;
        return this;
    }

    Self defaultVal(U)(U value, U[] rest...)
            if (is(U == ElementType!T) && !is(T == string)) {
        auto tmp = [value];
        foreach (val; rest) {
            tmp ~= val;
        }
        this.defaultArg = tmp;
    }

    Self configVal(T value) {
        this.configArg = value;
        return this;
    }

    Self configVal(U)(U value, U[] rest...)
            if (is(U == ElementType!T) && !is(T == string)) {
        auto tmp = [value];
        foreach (val; rest) {
            tmp ~= val;
        }
        this.defaultArg = tmp;
    }

    static if (is(T == bool)) {
        override Self defaultVal() {
            static assert(is(T == bool));
            this.defaultArg = true;
            return this;
        }

        override Self configVal() {
            static assert(is(T == bool));
            this.configArg = true;
            return this;
        }
    }

    override Self cliVal(string value, string[] rest...) {
        static if (is(T == string) || is(ElementType!T == void)) {
            assert(rest.length == 0);
            this.cliArg = value.to!T;
        }
        else {
            alias Ele = ElementType!T;
            auto tmp = [value.to!Ele];
            foreach (val; rest) {
                tmp ~= val.to!Ele;
            }
            this.cliArg = tmp;
        }
        return this;
    }

    @property
    override bool isValid() const {
        return !cliArg.isNull || !configArg.isNull || !defaultArg.isNull;
    }

    override Self initialize() {
        assert(this.isValid);
        this.settled = true;
        if (!cliArg.isNull) {
            innerData = cliArg.get!T;
            source = Source.Cli;
            return this;
        }
        if (!configArg.isNull) {
            innerData = configArg.get!T;
            source = Source.Config;
            return this;
        }
        if (!defaultArg.isNull) {
            innerData = defaultArg.get!T;
            source = Source.Default;
            return this;
        }
        return this;
    }

    @property
    override ArgVariant get() const {
        assert(this.isValid && this.settled);
        T result;
        static if (is(ElementType!T == void)) {
            result = this.innerData;
        }
        else {
            result = this.innerData.dup;
        }
        return ArgVariant(result);
    }

    @property
    T get(U : T)() const {
        assert(this.isValid && this.settled);
        return this.innerData;
    }
}
