/++
$(H2 The Argument Type for Cmdline)

This modlue mainly has `Argument` Type.
We can set the inner value by manly way.
And if the `Argument` value is valid, then we
can initialize it and get the inner value.

Authors: 笑愚(xiaoyu)
+/
module cmdline.argument;

import std.conv;
import std.range.primitives;
import std.algorithm;
import std.array;
import std.format;

import mir.algebraic;

import cmdline.error;
import cmdline.option;

/// same as `OptionBaseValue`
alias ArgBaseValue = OptionBaseValue;
/// same as `OptionArrayValue`
alias ArgArrayValue = OptionArrayValue;
/// same as `OptionValueSeq`
alias ArgValueSeq = OptionValueSeq;
/// same as `OptionNullable`
alias ArgNullable = Nullable!ArgValueSeq;
/// same as `OptionVariant`
alias ArgVariant = Variant!ArgValueSeq;

/// test whether the type`T` is base innner argument value type
alias isBaseArgValueType(T) = isBaseOptionValueType!T;
/// test whether the type`T` is innner argument value type
alias isArgValueType(T) = isOptionValueType!T;
/// same as `cmdline.error.OptionMemberFnCallError`
alias ArgMemberFnCallError = cmdline.error.OptionMemberFnCallError;

/** 
the argument type.
store the value that command line's arguments input.
we can get the inner value after it is initialized.
 */
class Argument {
package:
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

public:
    /// get the description, and the output starts with `description: `
    string description() const {
        return "description: " ~ this._description;
    }
    /// set the description
    Self description(string desc) {
        this._description = desc;
        return this;
    }
    /// get the name
    @property
    string name() const {
        return this._name.idup;
    }
    /// get the attribute name with camel-like
    @property
    string attrName() const {
        return _camelCase(this._name);
    }
    /// test whether the argument are required
    @property
    bool isRequired() const {
        return this.required;
    }
    ///  test whether the argument are optional
    @property
    bool isOptional() const {
        return !this.required;
    }
    /// set the choices of argument inner type
    ///Params: values = the sequence of choices value
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
    /// set the choices of argument inner type
    /** 
     * 
     * Params:
     *   value = a choice value 
     *   rest = the rest choice values
     * Returns: `Self` for chain call
     */
    Self choices(T)(T value, T[] rest...) if (isBaseArgValueType!T) {
        auto tmp = rest ~ value;
        return choices(tmp);
    }
    /// set the range of argument inner value when the argument innner value type is `int` or `double`
    /// Params:
    ///   min = the minimum
    ///   max = the maximum
    /// Returns: `Self` for chain call
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
    /// set the default value as `true`
    /// Returns: `Self` for chain call
    Self defaultVal() {
        throw new ArgMemberFnCallError;
    }
    /// set the config value as `true`, which is used for
    /// inernal impletation and is not recommended for use in you project
    /// Returns: `Self` for chain call
    Self configVal() {
        throw new ArgMemberFnCallError;
    }
    /// test whether the argument is valid so that you can safely get the inner value
    /// after the return value is `true`
    abstract bool isValid() const;

    /// set the value from client shell
    /// Params:
    ///   value = the first input value, and this func will call inner parsing callback to transform `string` type
    ///           to the target type that `Self` required
    ///   rest = the rest of input value
    /// Returns: `Self`` for chain call
    abstract Self cliVal(string value, string[] rest...);
    /// initialize the final value. if `this.isValid` is `false`, then would throw error
    /// Returns: `Self`` for chain call
    abstract Self initialize();
    /// get the innner value and is recommended to be used after calling `this.initialize()`
    /// Returns: the variant of final value
    abstract ArgVariant get() const;

    /// set the default value
    /// Params:
    ///   value = the value to be set as default value, `T` must satisfy `isBaseArgValueType`
    /// Returns: `Self`` for chain call
    Self defaultVal(T)(T value) if (isBaseArgValueType!T) {
        auto derived = cast(ValueArgument!T) this;
        if (!derived) {
            error(format("the value type is `%s` while the argument `%s` inner type is not the type or related array type",
                T.stringof, this._name));
        }
        return derived.defaultVal(value);
    }

    /// set the default value
    /// Params:
    ///   value = the first value to be set as default value, usually as the first element of default array value 
    ///   rest = the rest values to be set as default value, `T` must satisfy `isBaseArgValueType` and not `bool`
    /// Returns: `Self`` for chain call
    Self defaultVal(T)(T value, T[] rest...)
            if (isBaseArgValueType!T && !is(T == bool)) {
        auto derived = cast(ValueArgument!(T[])) this;
        if (!derived) {
            error(format("the value type is `%s` while the argument `%s` inner type is not the type or related array type",
                T.stringof, this._name));
        }
        return derived.defaultVal(value, rest);
    }

    /// set the default value
    /// Params:
    ///   values = the value to be set as default value, usually as the default array value,
    ///            `T` must satisfy `isBaseArgValueType` and not `bool`
    /// Returns: `Self`` for chain call
    Self defaultVal(T)(in T[] values) if (isBaseArgValueType!T && !is(T == bool)) {
        if (values.length == 0) {
            error(format("the default value's num of argument `%s` cannot be zero", this._name));
        }
        return defaultVal(values[0], cast(T[]) values[1 .. $]);
    }

package:
    Self configVal(T)(T value) if (isBaseArgValueType!T) {
        auto derived = cast(ValueArgument!T) this;
        if (!derived) {
            parsingError(format("the value type is `%s` while argument the inner type is not the type or related array type in argument `%s`",
                T.stringof, this._name));
        }
        return derived.configVal(value);
    }

    Self configVal(T)(T value, T[] rest...)
            if (isBaseArgValueType!T && !is(T == bool)) {
        auto derived = cast(ValueArgument!(T[])) this;
        if (!derived) {
            parsingError(format("the value type is `%s` while argument the inner type is not the type or related array type in argument `%s`",
                T.stringof, this._name));
        }
        return derived.configVal(value, rest);
    }

    Self configVal(T)(in T[] values) if (isBaseArgValueType!T && !is(T == bool)) {
        if (values.length == 0) {
            error(format("the default value's num of argument `%s` cannot be zero", this._name));
        }
        return configVal(values[0], cast(T[]) values[1 .. $]);
    }

public:
    /// get inner value in the specified type, `T` usually is among `ArgValueSeq`
    /// Returns: the result value
    T get(T)() const {
        return this.get.get!T;
    }
    /// get the human readable name, start with `<` representing required argument,
    /// `[` representing optional argument and `...` is variadic argument
    /// Returns: the result value
    @property
    string readableArgName() const {
        auto nameOutput = this.name ~ (this.variadic ? "..." : "");
        return this.isRequired
            ? "<" ~ nameOutput ~ ">" : "[" ~ nameOutput ~ "]";
    }
    /// get the type in `string` type, used for help command and help option
    /// start with `type: `
    string typeStr() const {
        return "";
    }
    /// get the default value in `string` type, start with `default: `
    string defaultValStr() const {
        return "";
    }
    /// get the choices in `string` type, start with `choices: `
    string choicesStr() const {
        return "";
    }
    /// get the range in `string` type, start with `range: `
    string rangeOfStr() const {
        return "";
    }
}

/// create `bool` argument
/// Params:
///   flag = the flag like `<name>`, `[name]`, `name`
///   desc = the description of argument
/// Returns: a `bool` argument
Argument createArgument(string flag, string desc = "") {
    return createArgument!bool(flag, desc);
}

/// create `bool` argument
Argument createArgument(T : bool)(string flag, string desc = "") {
    bool is_variadic = flag[$ - 2] == '.';
    if (is_variadic) {
        error(format("the flag `%s` cannot contain `...` in creating bool argument", flag));
    }
    return new ValueArgument!bool(flag, desc);
}

/// create `T` or `T[]` argument, which `T` must not `bool`
/// if flag is like `<name...>` then the argument's innner type is `T[]` 
/// Params:
///   flag = the flag like `<name>`, `[name]`, `name`, `<name...>`
///   desc = the description of argument
/// Returns: a value/variadic argument
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

/// create a argument, whose inner type is array type of `T` and `T` is not `bool`
/// Params:
///   flag = the flag like `<name...>`, `[name...]`, `name...`
///   desc = the description of argument
/// Returns: a variadic argument
Argument createArgument(T : U[], U)(string flag, string desc = "")
        if (!is(U == bool) && isBaseArgValueType!U) {
    bool is_variadic = flag[$ - 2] == '.';
    if (!is_variadic) {
        error(format("the flag `%s` must contain `...` in creating variadic option", flag));
    }
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
    assert(arg3.get == ["son", "brother"]);

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

package class ValueArgument(T) : Argument {
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
                if (i == j) {
                    error(format("the element value of choices can not be equal in argument `%s`, the values is: `%s`",
                        this._name, values.to!string));
                }
            }
        }
        static if (is(T == int) || is(T == double)) {
            if (values.any!(val => val < this._min || val > this._max)) {
                error(format("the element value of choices cannot be out of %s in argument `%s`, the values is: `%s`",
                    this.rangeOfStr(), this._name, values.to!string));
            }
        }
        this.argChoices = values;
        return this;
    }

    Self choices(U)(U[] values...) if (is(U == ElementType!T) && !is(T == string)) {
        foreach (index_i, i; values) {
            foreach (j; values[index_i + 1 .. $]) {
                if (i == j) {
                    error(format("the element value of choices can not be equal in argument `%s`, the values is: `%s`",
                        this._name, values.to!string));
                }
            }
        }
        static if (is(T == int[]) || is(T == double[])) {
            if (values.any!(val => val < this._min || val > this._max)) {
                error(format("the element value of choices cannot be out of %s in argument `%s`, the values is: `%s`",
                    this.rangeOfStr(), this._name, values.to!string));
            }
        }
        this.argChoices = values;
        return this;
    }

    void _checkVal(U)(in U value) const if (isBaseArgValueType!T && is(U == T)) {
        if (!this.argChoices.empty) {
            if (!this.argChoices.count(value)) {
                parsingError(format("the value cannot be out of %s for argument `%s`, the value is: `%s`",
                    this.choicesStr(), this._name, value.to!string));
            }
        }
        static if (is(T == int) || is(T == double)) {
            if (value < this._min || value > this._max) {
                parsingError(format("the value cannot be out of %s for argument `%s`, the value is: `%s`",
                    this.rangeOfStr(), this._name, value.to!string));
            }
        }
    }

    void _checkVal(U)(in U value) const
    if (is(U == ElementType!T) && !is(T == string)) {
        if (!this.argChoices.empty) {
            if (!this.argChoices.count(value)) {
                parsingError(format("the value cannot be out of %s for argument `%s`, the value is: `%s`",
                    this.choicesStr(), this._name, value.to!string));
            }
        }
        static if (is(T == int[]) || is(T == double[])) {
            if (value < this._min || value > this._max) {
                parsingError(format("the value cannot be out of %s for argument `%s`, the value is: `%s`",
                    this.rangeOfStr(), this._name, value.to!string));
            }
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
        auto tmp = [value] ~ rest;
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
        auto tmp = [value] ~ rest;
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
            try {
                auto tmp = value.to!T;
                _checkVal(tmp);
                this.cliArg = tmp;
            }
            catch (ConvException e) {
                parsingError(format("on argument `%s` cannot convert the input `%s` to type `%s`",
                        this._name, value, T.stringof));
            }
        }
        else {
            try {
                auto tmp = ([value] ~ rest).map!(to!(ElementType!T)).array;
                _checkValSeq(tmp);
                this.cliArg = tmp;
            }
            catch (ConvException e) {
                parsingError(format("on argument `%s` cannot convert the input `%s` to type `%s`",
                        this._name, ([value] ~ rest).to!string, T.stringof));
            }
        }
        return this;
    }

    @property
    override bool isValid() const {
        return !cliArg.isNull || !configArg.isNull || !defaultArg.isNull;
    }

    override Self initialize() {
        if (!this.isValid) {
            parsingError(format("the argument `%s` must valid before initializing", this._name));
        }
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
        assert(this.settled);
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
        assert(this.settled);
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
        return "choices: " ~ argChoices.to!string;
    }
}

private void error(string msg = "", string code = "argument.error") {
    throw new CMDLineError(msg, 1, code);
}

private void parsingError(string msg = "", string code = "argument.error") {
    throw new InvalidArgumentError(msg, code);
}
