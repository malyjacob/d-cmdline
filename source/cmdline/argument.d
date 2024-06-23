module cmdline.argument;

import std.conv;
import std.range.primitives;
import std.algorithm;
import std.array;
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
    string _description;
    string defaultDescription;
    bool required;
    bool variadic;

    string _name;

    bool settled;
    Source source;

    this(string flag, string description) {
        this._description = description;
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
        this.settled = false;
        this.source = Source.None;
    }

    alias Self = typeof(this);

    string description() const {
        return "description: " ~ this._description;
    }

    Self description(string desc) {
        this._description = desc;
        return this;
    }

    @property
    string name() const {
        return this._name.idup;
    }

    @property
    string attrName() const {
        return _camelCase(this._name);
    }

    @property
    bool isRequired() const {
        return this.required;
    }

    @property
    bool isOptional() const {
        return !this.required;
    }

    Self choices(T)(T[] values) if (isBaseArgValueType!T) {
        auto is_variadic = this.variadic;
        if (!is_variadic) {
            auto derived = cast(ValueArgument!T) this;
            return derived.choices(values);
        }
        else {
            auto derived = cast(ValueArgument!(T[])) this;
            return derived.choices(values);
        }
    }

    Self choices(T)(T values, T[] rest...) if (isBaseArgValueType!T) {
        auto tmp = rest ~ values;
        return choices(tmp);
    }

    Self rangeOf(T)(T min, T max) if (is(T == int) || is(T == double)) {
        auto is_variadic = this.variadic;
        if (!is_variadic) {
            auto derived = cast(ValueArgument!T) this;
            return derived.rangeOf(min, max);
        }
        else {
            auto derived = cast(ValueArgument!(T[])) this;
            return derived.rangeOf(min, max);
        }
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

    @property
    string readableArgName() const {
        auto nameOutput = this.name ~ (this.variadic ? "..." : "");
        return this.isRequired
            ? "<" ~ nameOutput ~ ">" : "[" ~ nameOutput ~ "]";
    }

    string typeStr() const {
        return "";
    }

    string defaultValStr() const {
        return "";
    }

    string choicesStr() const {
        return "";
    }

    string rangeOfStr() const {
        return "";
    }
}

Argument createArgument(string flag, string desc = "") {
    return createArgument!bool(flag, desc);
}

Argument createArgument(T : bool)(string flag, string desc = "") {
    bool is_variadic = flag[$ - 2] == '.';
    assert(!is_variadic);
    return new ValueArgument!bool(flag, desc);
}

Argument createArgument(T)(string flag, string desc = "")
        if (!is(T == bool) && isBaseArgValueType!T) {
    bool is_variadic = flag[$ - 2] == '.';
    if (is_variadic) {
        return new ValueArgument!(T[])(flag, desc);
    }
    else {
        return new ValueArgument!T(flag, desc);
    }
}

Argument createArgument(T : U[], U)(string flag, string desc = "")
        if (!is(U == bool) && isBaseArgValueType!U) {
    bool is_variadic = flag[$ - 2] == '.';
    assert(is_variadic);
    return new ValueArgument!T(flag, desc);
}

unittest {
    Argument[] args = [
        createArgument!int("<int>", ""),
        createArgument!string("[str]", ""),
        createArgument!int("<int>", ""),
        createArgument!(double[])("<int...>", "")
    ];
    import std.array;
    import std.algorithm;

    each!((Argument v) => v.cliVal("12").initialize)(args);

    assert(args[0].get!int == 12);
    assert(args[1].get!string == "12");
    assert(args[2].get!int == 12);
    assert(args[3].get!(double[]) == [12f]);
}

unittest {
    import std.stdio;

    Argument arg1 = createArgument!int("<age>");
    Argument arg2 = createArgument!double("<tall>");
    Argument arg3 = createArgument!string("<family...>");

    arg1.rangeOf(18, 65).defaultVal(20).cliVal("24").initialize;
    arg2.rangeOf(1.0, 2.0).choices(1.55, 1.66, 1.77).defaultVal(1.77).initialize;
    arg3.choices("father", "mother", "brother", "sister", "son")
        .cliVal("son", "brother").initialize;

    assert(arg1.get == 24);
    assert(arg2.get == 1.77);
    assert(arg3.get == ["brother", "son"]);

    writeln(arg1.typeStr);
    writeln(arg1.defaultValStr);
    writeln(arg1.rangeOfStr);

    writeln(arg2.typeStr);
    writeln(arg2.defaultValStr);
    writeln(arg2.rangeOfStr);
    writeln(arg2.choicesStr);

    writeln(arg3.typeStr);
    writeln(arg3.choicesStr);
}

class ValueArgument(T) : Argument {
    static assert(isArgValueType!T);
    Nullable!T cliArg;
    Nullable!T configArg;
    Nullable!T defaultArg;

    T innerData;

    static if (isBaseArgValueType!T) {
        T[] argChoices;
    }
    else {
        T argChoices;
    }

    static if (is(T == int) || is(T == double)) {
        T _min = int.min;
        T _max = int.max;
    }
    else static if (is(T == int[]) || is(T == double[])) {
        ElementType!T _min = int.min;
        ElementType!T _max = int.max;
    }

    this(string flag, string description) {
        super(flag, description);
        this.cliArg = null;
        this.configArg = null;
        this.defaultArg = null;
        this.innerData = T.init;
        this.argChoices = [];
    }

    alias Self = typeof(this);

    Self choices(U)(U[] values...) if (isBaseArgValueType!T && is(U == T)) {
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

    Self choices(U)(U[] values...) if (is(U == ElementType!T) && !is(T == string)) {
        foreach (index_i, i; values) {
            foreach (j; values[index_i + 1 .. $]) {
                assert(i != j);
            }
        }
        static if (is(T == int[]) || is(T == double[])) {
            assert(values.find!(val => val < this._min || val > this._max).empty);
        }
        this.argChoices = values;
        return this;
    }

    void _checkVal(U)(in U value) const if (isBaseArgValueType!T && is(U == T)) {
        if (!this.argChoices.empty)
            assert(this.argChoices.count(value));
        static if (is(T == int) || is(T == double)) {
            assert(value >= this._min && value <= this._max);
        }
    }

    void _checkVal(U)(in U value) const
    if (is(U == ElementType!T) && !is(T == string)) {
        if (!this.argChoices.empty)
            assert(this.argChoices.count(value));
        static if (is(T == int[]) || is(T == double[])) {
            assert(value >= this._min && value <= this._max);
        }
    }

    void _checkValSeq(U)(U[] values...) const
    if (is(U == ElementType!T) && !is(T == string)) {
        assert(values.length);
        foreach (val; values) {
            _checkVal(val);
        }
    }

    static if (is(T == int) || is(T == double) || is(T == int[]) || is(T == double[])) {
        Self rangeOf(U)(U min, U max) {
            assert(max > min);
            this._min = min;
            this._max = max;
            return this;
        }

        override string rangeOfStr() const {
            if (_min == int.min && _max == int.max)
                return "";
            return "range: " ~ _min.to!string ~ " ~ " ~ _max.to!string;
        }
    }

    Self defaultVal(T value) {
        static if (isBaseArgValueType!T) {
            _checkVal(value);
        }
        else {
            _checkValSeq(value);
        }
        this.defaultArg = value;
        return this;
    }

    Self defaultVal(U)(U value, U[] rest...)
            if (is(U == ElementType!T) && !is(T == string)) {
        auto tmp = rest ~ [value];
        _checkValSeq(tmp);
        this.defaultArg = tmp;
    }

    Self configVal(T value) {
        static if (isBaseArgValueType!T) {
            _checkVal(value);
        }
        else {
            _checkValSeq(value);
        }
        this.configArg = value;
        return this;
    }

    Self configVal(U)(U value, U[] rest...)
            if (is(U == ElementType!T) && !is(T == string)) {
        auto tmp = rest ~ [value];
        _checkValSeq(tmp);
        this.configArg = tmp;
        return this;
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
        static if (isBaseArgValueType!T) {
            assert(rest.empty);
            auto tmp = value.to!T;
            _checkVal(tmp);
            this.cliArg = tmp;
        }
        else {
            auto tmp = (rest ~ [value]).map!(to!(ElementType!T)).array;
            _checkValSeq(tmp);
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

    override string typeStr() const {
        return "type: " ~ T.stringof;
    }

    override string defaultValStr() const {
        if (defaultArg.isNull)
            return "";
        return "default: " ~ defaultArg.get!T
            .to!string;
    }

    override string choicesStr() const {
        if (argChoices.empty)
            return "";
        return "choices " ~ argChoices.to!string;
    }
}
