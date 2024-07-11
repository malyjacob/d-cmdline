/++
$(H2 The Option Type for Cmdline)

This modlue mainly has `Option` Type.
We can set the inner value by manly way.
And if the `Option` value is valid, then we
can initialize it and get the inner value.

Authors: 笑愚(xiaoyu)
+/
module cmdline.option;

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

// the result type after parsing the flags.
package struct OptionFlags {
    // short flag
    // Examples: `-f`, `-s`, `-x`
    string shortFlag = "";
    // long flag
    // Examples: `--flag`, `--mixin-flag`, `--no-flag`
    string longFlag = "";
    // value flag
    // Examples: `<required>`, `[optional]`, `<variadic...>`
    string valueFlag = "";
}

/// a sequenece of inner option base type
alias OptionBaseValue = AliasSeq!(string, int, double, bool);
/// a sequenece of inner option array type
alias OptionArrayValue = AliasSeq!(string[], int[], double[]);
/// a sequenece of inner option type, equals to the union of `OptionBaseValue` and `OptionArrayValue`
alias OptionValueSeq = AliasSeq!(OptionBaseValue, OptionArrayValue);

/// a nullable variant which may contain one of type in `OptionValueSeq`
alias OptionNullable = Nullable!OptionValueSeq;
/// a no-nullable variant which may contain one of type in `OptionValueSeq`
alias OptionVariant = Variant!OptionValueSeq;

/// the source of the final option value gotten
enum Source {
    /// from client terminal
    Cli,
    /// from env
    Env,
    /// from config file
    Config,
    /// from impled value by other options
    Imply,
    /// from the value that is set by user using `defaultVal` 
    Default,
    /// from the value that is set by user using `preset`
    Preset,
    /// default value
    None
}

/// the callback for parsing the `string` value to the target type
alias ParseArgFn(Target) = Target function(string str);
/// furhter callback after using `ParseArgFn`
alias ProcessArgFn(Target) = Target function(Target value);
/// the callback for recursingly parsing the multiple values to only one value with same type, using in `VariadicOption` 
alias ProcessReduceFn(Target) = Target function(Target cur, Target prev);

/// a trait func for checking whether a type is base inner option value (`OptionBaseValue`)
template isBaseOptionValueType(T) {
    enum bool isBaseOptionValueType = isBoolean!T || allSameType!(T, int) ||
        allSameType!(T, double) || allSameType!(T, string);
}
/// a trait func for checking whether a type is option inner value (`OptionValueSeq`)
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

unittest {
    alias test_bool = visit!((bool v) => true, (v) => false);
    OptionVariant ov = 12;
    OptionNullable on = ov;
    assert(!test_bool(on));
}

/** 
the option type.
store the value that command line's options input.
we can get the inner value after it is initialized.
 */
class Option {
package:
    string _description;
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

    OptionNullable innerImplyData;

    bool found;
    bool settled;

    Source source;

    alias Self = typeof(this);
    alias ImplyOptionMap = OptionVariant[string];

    bool isValueData;
    bool innerBoolData;

    bool _isMerge;

    this(string flags, string description) {
        this.flags = flags;
        this._description = description;
        this.mandatory = false;
        this.defaultValueDescription = "";
        auto opt = splitOptionFlags(flags);
        this.shortFlag = opt.shortFlag;
        this.longFlag = opt.longFlag;
        if (longFlag.length == 0) {
            error("the long flag must be specified");
        }
        if (!matchFirst(this.longFlag, PTN_NEGATE).empty) {
            error("the negate flag cannot be specified by `new Option`");
        }
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
        this.conflictsWith = [];
        this.implyMap = null;
        this.envKey = "";
        this.found = false;
        this.settled = false;
        this.source = Source.None;
        this.innerImplyData = null;
        this.isValueData = false;
        this.innerBoolData = false;
        _isMerge = true;
    }

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

    /// test whether the other `Option` variable's flag same in some parts
    bool matchFlag(in Option other) const {
        return this.longFlag == other.longFlag ||
            (this.shortFlag.empty ? false : this.shortFlag == other.shortFlag);
    }

    /// test whether the other `NegateOption` variable's flag same in some parts
    bool matchFlag(in NegateOption other) const {
        auto short_flag = this.shortFlag;
        auto nshort_flag = other.shortFlag;
        return short_flag.empty ? false : short_flag == nshort_flag;
    }

    /// specify the name of the option that conflicts with this option
    /// Params:
    ///   name = the name of the option that conflicts with this option
    /// Returns: `Self` for chain call
    Self conflicts(string name) {
        this.conflictsWith ~= name;
        return this;
    }

    /// specify the name of the options that conflicts with this option
    /// Params:
    ///   names = the names of the option that conflicts with this option
    /// Returns: `Self` for chain call
    Self conflicts(const string[] names) {
        this.conflictsWith ~= names;
        return this;
    }

    /// imply the value of other options' value of `true`
    /// Params:
    ///   names = the options' names
    /// Returns: `Self` for chain call
    Self implies(string[] names) {
        if (!names.length) {
            error("the length of implies key cannot be zero");
        }
        foreach (name; names) {
            bool signal = false;
            foreach (k; implyMap.byKey) {
                if (name.length < k.length && name == k[0 .. name.length]) {
                    signal = true;
                    break;
                }
            }
            if (signal)
                error(format!"the implies key must be unique, here are keys: `%s`, key: `%s`"(
                        implyMap.byKey.to!string, name));
            implyMap[name ~ ":" ~ bool.stringof] = true;
        }
        return this;
    }

    /// imply the value of other option's value of `T`, `T` must satisfy `isOptionValueType`
    /// Params:
    ///   key = the name of option
    ///   value = the value imply for
    /// Returns: `Self` for chain call
    Self implies(T)(string key, T value) if (isOptionValueType!T) {
        bool signal = false;
        foreach (k; implyMap.byKey) {
            if (key.length < k.length && key == k[0 .. key.length]) {
                signal = true;
                break;
            }
        }
        if (signal)
            error(format!"the implies key must be unique, here are keys: `%s`, key: `%s`"(
                    implyMap.byKey.to!string, key));
        implyMap[key ~ ":" ~ T.stringof] = value;
        return this;
    }

    /// set the env variable's key so that the option can set its value from `env`
    /// Params:
    ///   name = the env variable's key
    /// Returns: `Self` for chain call
    Self env(string name) {
        this.envKey = name;
        return this;
    }

    /// set whether the option is mandatory
    /// Params:
    ///   mandatory = whether the option is mandatory
    /// Returns: `Self` for chain call
    Self makeMandatory(bool mandatory = true) {
        this.mandatory = mandatory;
        return this;
    }

    /// set whether the option is hidden out of help command
    /// Params:
    ///   hide = whether the option is hidden out of help command
    /// Returns: `Self` for chain call
    Self hideHelp(bool hide = true) {
        this.hidden = hide;
        return this;
    }

    /// get the name
    @property
    string name() const {
        return this.longFlag[2 .. $].idup;
    }

    /// get the attribute name with camel-like
    @property
    string attrName() const {
        return _camelCase(this.name);
    }

    /// get the raw env variable in `string` type acccording to `this.envKey`
    /// which is set by `this.env`
    package
    @property
    string envStr() const {
        auto raw = environment.get(this.envKey);
        return raw;
    }

    /// test whether a string is this option's long or short flag 
    bool isFlag(string flag) const {
        return !flag.empty && (this.shortFlag == flag || this.longFlag == flag);
    }

    /// test whether is a bool option
    @property
    bool isBoolean() const {
        return this.valueName.length == 0;
    }

    /// test whether is optional option
    @property
    bool isOptional() const {
        return (!this.required && this.optional);
    }

    /// Test is required option
    @property
    bool isRequired() const {
        return (!this.optional && this.required);
    }

    /// Test is allowed to merge variadic final value from different source, default `true`
    bool isMerge() const {
        return this._isMerge;
    }

    /// whether is allowed to merge variadic final value from different source, default `true`
    Self merge(bool allow = true) {
        this._isMerge = allow;
        return this;
    }

    /// set the imply value as `true`, which is used for
    /// inernal impletation and is not recommended for use in you project
    /// Returns: `Self` for chain call
    Self implyVal() {
        // throw new OptionMemberFnCallError;
        this.innerImplyData = true;
        return this;
    }

    /// set the option value from `en`
    Self envVal() {
        // throw new OptionMemberFnCallError;
        return this;
    }

    /// set the preset value as `true`
    Self preset() {
        // throw new OptionMemberFnCallError;
        return this;
    }

    /// set the value from client shell
    /// Params:
    ///   value = the first input value, and this func will call inner parsing callback to transform `string` type
    ///           to the target type that `Self` required
    ///   rest = the rest of input value
    /// Returns: `Self`` for chain call
    Self cliVal(string value, string[] rest...) {
        // throw new OptionMemberFnCallError;
        return this;
    }

    /// test whether the argument is valid so that you can safely get the inner value
    /// after the return value is `true`
    @property
    abstract bool isValid() const;

    /// get the innner value and is recommended to be used after calling `this.initialize()`
    /// Returns: the variant of final value
    @property
    abstract OptionVariant get() const;

    /// initialize the final value. if `this.isValid` is `false`, then would throw error
    /// Returns: `Self`` for chain call
    abstract Self initialize();

    /// set the imply value, which is used for
    /// inernal impletation and is not recommended for use in you project
    /// Returns: `Self` for chain call
    abstract Self implyVal(OptionVariant value);

    /// set the choices of argument inner type
    ///Params: values = the sequence of choices value
    Self choices(T)(T[] values) {
        auto is_variadic = this.variadic;
        if (is_variadic) {
            auto derived = cast(VariadicOption!T) this;
            if (!derived) {
                error(format!"the element type of the inner value of option `%s` is not `%s` in `Option.choices`"(
                        this.flags,
                        T.stringof
                ));
            }
            return derived.choices(values);
        }
        else if (!this.isBoolean) {
            auto derived = cast(ValueOption!T) this;
            if (!derived) {
                error(format!"the type of the inner value of option `%s` is not `%s` in `Option.choices"(
                        this.flags,
                        T.stringof
                ));
            }
            return derived.choices(values);
        }
        else {
            error(format!"connnot use `Option.choices` for option `%s` is bool option"(this.flags));
        }
        return this;
    }

    /// set the choices of argument inner type
    /** 
     * 
     * Params:
     *   value = a choice value 
     *   rest = the rest choice values
     * Returns: `Self` for chain call
     */
    Self choices(T)(T value, T[] rest...) {
        auto tmp = rest ~ value;
        return choices(tmp);
    }

    /// set the range of option inner value when the option innner value type is `int` or `double`
    /// Params:
    ///   min = the minimum
    ///   max = the maximum
    /// Returns: `Self` for chain call
    Self rangeOf(T)(T min, T max) if (is(T == int) || is(T == double)) {
        auto is_variadic = this.variadic;
        if (is_variadic) {
            auto derived = cast(VariadicOption!T) this;
            if (!derived) {
                error(format!"the element type of the inner value of option `%s` is not `%s` in `Option.rangeOf`"(
                        this.flags,
                        T.stringof
                ));
            }
            return derived.rangeOf(min, max);
        }
        else {
            auto derived = cast(ValueOption!T) this;
            if (!derived) {
                error(format!"the type of the inner value of option `%s` is not `%s` in `Option.rangeOf"(
                        this.flags,
                        T.stringof
                ));
            }
            return derived.rangeOf(min, max);
        }
    }

    /// set the default value `true`, only for `BooleanOption`.
    /// Returns: `Self` for chain call
    Self defaultVal() {
        auto derived = cast(BoolOption) this;
        if (!derived) {
            error(format!"connot cast the option `%s` to bool option using `Option.default()`"(
                    this.flags));
        }
        derived.defaultVal(true);
        return this;
    }

    /// set the default value
    /// Params:
    ///   value = the value to be set as default value, `T` must satisfy `isBaseOptionValueType`
    /// Returns: `Self`` for chain call
    Self defaultVal(T)(T value) if (isBaseOptionValueType!T) {
        static if (is(T == bool)) {
            auto derived = cast(BoolOption) this;
        }
        else {
            auto derived = cast(ValueOption!T) this;
        }
        if (!derived) {
            error(
                format!"the value type is `%s` while the option `%s` inner type is not the type or related array type"(
                    T.stringof, this.flags));
        }
        return derived.defaultVal(value);
    }

    /// set the default value
    /// Params:
    ///   value = the first value to be set as default value, usually as the first element of default array value 
    ///   rest = the rest values to be set as default value, `T` must satisfy `isBaseOptionValueType` and not `bool`
    /// Returns: `Self`` for chain call
    Self defaultVal(T)(T value, T[] rest...)
            if (isBaseOptionValueType!T && !is(T == bool)) {
        auto derived = cast(VariadicOption!T) this;
        if (!derived) {
            error(
                format!"the value type is `%s` while the option `%s` inner type is not the type or related array type"(
                    T.stringof, this.flags));
        }
        return derived.defaultVal(value, rest);
    }

    /// set the default value
    /// Params:
    ///   values = the value to be set as default value, usually as the default array value,
    ///            `T` must satisfy `isBaseOptionValueType` and not `bool`
    /// Returns: `Self`` for chain call
    Self defaultVal(T)(in T[] values) if (isBaseOptionValueType!T && !is(T == bool)) {
        if (!values.length) {
            error("the values length cannot be zero using `Self defaultVal(T)(in T[] values)`");
        }
        return defaultVal(values[0], cast(T[]) values[1 .. $]);
    }

package:
    Self configVal(T)(T value) if (isBaseOptionValueType!T) {
        static if (is(T == bool)) {
            auto derived = cast(BoolOption) this;
        }
        else {
            auto derived = cast(ValueOption!T) this;
        }
        if (!derived) {
            parsingError(
                format!"the value type is `%s` while the option `%s` inner type is not the type or related array type"(
                    this.flags,
                    T.stringof));
        }
        return derived.configVal(value);
    }

    Self configVal(T)(T value, T[] rest...)
            if (isBaseOptionValueType!T && !is(T == bool)) {
        auto derived = cast(VariadicOption!T) this;
        if (!derived) {
            parsingError(
                format!"the value type is `%s` while the option `%s` inner type is not the type or related array type"(
                    this.flags,
                    T.stringof));
        }
        return derived.configVal(value, rest);
    }

    Self configVal(T)(in T[] values) if (isBaseOptionValueType!T && !is(T == bool)) {
        if (!values.length) {
            parsingError(format!"the values length cannot be zero in option `%s`"(this.flags));
        }
        return configVal(values[0], cast(T[]) values[1 .. $]);
    }

    // Self implyVal(OptionVariant value) {
    //     this.innerImplyData = value;
    //     return this;
    // }

    Self implyVal(T)(T value) if (isBaseOptionValueType!T) {
        this.innerImplyData = value;
        return this;
    }

    Self implyVal(T)(T value, T[] rest...)
            if (isBaseOptionValueType!T && !is(T == bool)) {
        this.innerImplyData = [value] ~ rest;
        return this;
    }

    Self implyVal(T)(T[] values) if (isBaseOptionValueType!T && !is(T == bool)) {
        if (!values.length) {
            parsingError(format!"the values length cannot be zero in option `%s`"(this.flags));
        }
        return implyVal(values[0], values[1 .. $]);
    }

    // Self implyVal(T)(T value) if (isBaseOptionValueType!T) {
    //     static if (is(T == bool)) {
    //         auto derived = cast(BoolOption) this;
    //     }
    //     else {
    //         auto derived = cast(ValueOption!T) this;
    //     }
    //     return derived.implyVal(value);
    // }

    // Self implyVal(T)(T value, T[] rest...)
    //         if (isBaseOptionValueType!T && !is(T == bool)) {
    //     auto derived = cast(VariadicOption!T) this;
    //     return derived.implyVal(value, rest);
    // }

    // Self implyVal(T)(in T[] values) if (isBaseOptionValueType!T && !is(T == bool)) {
    //     assert(values.length > 0);
    //     return implyVal(values[0], cast(T[]) values[1 .. $]);
    // }
public:

    /// preset the value used for value option
    /// Params:
    ///   value = the value to be preset
    /// Returns: `Self` for chain call
    Self preset(T)(T value) if (isBaseOptionValueType!T && !is(T == bool)) {
        auto derived = cast(ValueOption!T) this;
        if (!derived) {
            error(
                format!"the value type is `%s` while the option `%s` inner type is not the type or related array type"(
                    T.stringof, this.flags));
        }
        return derived.preset(value);
    }

    /// preset the value used for variadic option
    /// Params:
    ///   value = the first value to be preset as an element of array inner value
    ///   rest = the rest value to be preset
    /// Returns: `Self` for chain call
    Self preset(T)(T value, T[] rest...)
            if (isBaseOptionValueType!T && !is(T == bool)) {
        auto derived = cast(VariadicOption!T) this;
        if (!derived) {
            error(
                format!"the value type is `%s` while the option `%s` inner type is not the type or related array type"(
                    T.stringof, this.flags));
        }
        return derived.preset(value, rest);
    }

    /// preset the value used for variadic option
    /// Params:
    ///   values = the first value to be preset
    /// Returns: `Self` for chain call
    Self preset(T)(in T[] values) if (isBaseOptionValueType!T && !is(T == bool)) {
        if (!values.length) {
            error("the values length cannot be zero using `Self preset(T)(in T[] values)`");
        }
        return preset(values[0], cast(T[]) values[1 .. $]);
    }

    /// get inner value in the specified type, `T` usually is among `OptionValueSeq`
    /// Returns: the result value
    T get(T)() const if (isBaseOptionValueType!T && !is(T == bool)) {
        assert(isValueData);
        auto derived_1 = cast(ValueOption!T) this;
        auto derived_2 = cast(VariadicOption!T) this;
        if (derived_1) {
            return derived_1.get!T;
        }
        if (derived_2) {
            return derived_2.get!T;
        }
        error(format!"connot get the value of type `%s` from option `%s`"(
                T.stringof,
                this.flags
        ));
        return T.init;
    }

    /// get inner value in the specified type, `T` usually is among `OptionValueSeq`
    /// Returns: the result value
    T get(T : bool)() const {
        assert(!isValueData);
        if (isValueData) {
            error(format!"connot get the value of type `%s` from option `%s`"(
                    T.stringof,
                    this.flags
            ));
        }
        return this.innerBoolData;
    }

    /// get inner value in the specified type, `T` usually is among `OptionValueSeq`
    /// Returns: the result value
    T get(T)() const
    if (!is(ElementType!T == void) && isBaseOptionValueType!(ElementType!T)) {
        alias Ele = ElementType!T;
        static assert(!is(Ele == bool));
        assert(isValueData);
        auto derived = cast(VariadicOption!Ele) this;
        if (!derived)
            error(format!"connot get the value of type `%s` from option `%s`"(
                    Ele.stringof,
                    this.flags
            ));
        return derived.get!T;
    }

    /// set the parsing function using for transforming from `string` to `T`
    /// alias fn = `T fn(string v)`, where `T` is the inner value type 
    /// Returns: `Self` for chain call
    Self parser(alias fn)() {
        alias T = typeof({ string v; return fn(v); }());
        static assert(isBaseOptionValueType!T && !is(T == bool));
        auto derived_1 = cast(ValueOption!T) this;
        auto derived_2 = cast(VariadicOption!T) this;

        if (derived_1) {
            derived_1.parseFn = fn;
            return derived_1;
        }
        if (derived_2) {
            derived_2.parseFn = fn;
            return derived_2;
        }
        error(format!"connot set the parser fn `%s` to option `%s`"(
                typeof(fn)
                .stringof,
                this.flags
        ));
        return this;
    }

    /// set the process function for processing the value parsed by innner parsing function
    /// alias fn = `T fn(T v)`, where `T` is the inner value type
    /// Returns: `Self` for chain call
    Self processor(alias fn)() {
        alias return_t = ReturnType!fn;
        alias param_t = Parameters!fn;
        static assert(param_t.length == 1 && is(return_t == param_t[0]));
        static assert(isBaseOptionValueType!return_t && !is(return_t == bool));
        alias T = return_t;
        auto derived_1 = cast(ValueOption!T) this;
        auto derived_2 = cast(VariadicOption!T) this;
        if (derived_1) {
            derived_1.processFn = fn;
            return derived_1;
        }
        if (derived_2) {
            derived_2.processFn = fn;
            return derived_2;
        }
        error(format!"connot set the processor fn `%s` to option `%s`"(
                typeof(fn)
                .stringof,
                this.flags
        ));
        return this;
    }

    /// set the reduce process function for reducely processing the value parsed by innner parsing function or process function
    /// mainly used in variadic option
    /// alias fn = `T fn(T v, T t)`, where `T` is the inner value type
    /// Returns: `Self` for chain call
    Self processReducer(alias fn)() {
        alias return_t = ReturnType!fn;
        alias param_t = Parameters!fn;
        static assert(allSameType!(return_t, param_t) && param_t.length == 2);
        alias T = return_t;
        static assert(isBaseOptionValueType!T && !is(T == bool));
        auto derived = cast(VariadicOption!T) this;
        if (!derived) {
            error(format!"connot set the process reducer fn `%s` to option `%s`"(
                    typeof(fn)
                    .stringof,
                    this.flags
            ));
        }
        derived.processReduceFn = fn;
        return derived;
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

    /// get the preset value in `string` type, start with `preset: `
    string presetStr() const {
        return "";
    }

    /// get the env variable's key
    string envValStr() const {
        if (this.envKey == "")
            return this.envKey;
        return "env: " ~ this.envKey;
    }

    /// get the imply map in`string` type, start with `imply `
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

    /// get the list of confilt option in `string` type, start with `conflict with `
    string conflictOptStr() const {
        if (this.conflictsWith.empty)
            return "";
        auto str = "conflict with [ ";
        conflictsWith.each!((name) { str ~= (name ~ ", "); });
        return str ~ "]";
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

/// create `bool` option
/// Params:
///   flags = the flag like `-f, --flag`, `--flag`, must include long flag
///   desc = the description of option
/// Returns: a `bool` option
Option createOption(string flags, string desc = "") {
    return createOption!bool(flags, desc);
}

/// create `bool` option
Option createOption(T : bool)(string flags, string desc = "") {
    auto opt = splitOptionFlags(flags);
    bool is_bool = opt.valueFlag == "";
    if (!is_bool) {
        error("the value flag must not exist using `createOption!bool`");
    }
    return new BoolOption(flags, desc);
}

/// create value/variadic option, whose inner type or inner value's element type
/// `T` must satisfy `isBaseOptionValueType` and not `bool`
/// Params:
///   flags = the flag like `-f, --flag <name>`, `--flag [name...]`
///   desc = the description of option
/// Returns: a value/variadic option
Option createOption(T)(string flags, string desc = "")
        if (!is(T == bool) && isBaseOptionValueType!T) {
    auto opt = splitOptionFlags(flags);
    bool is_bool = opt.valueFlag == "";
    bool is_variadic = (is_bool || opt.valueFlag[$ - 2] != '.') ? false : true;
    if (is_bool) {
        error("the value flag must exist using `createOption!T`, while `T` is not bool");
    }
    if (is_variadic) {
        return new VariadicOption!T(flags, desc);
    }
    else {
        return new ValueOption!T(flags, desc);
    }
}

/// create varidic option, whose inner values's element type `T` must satisfy `isBaseOptionValueType` and not `bool`
/// Params:
///   flags = the flag like `-f, --flag [name...]`, `--flag <name...>`
///   desc = the description of option
/// Returns: a variadic option
Option createOption(T : U[], U)(string flags, string desc = "")
        if (!is(U == bool) && isBaseOptionValueType!U) {
    return createOption!U(flags, desc);
}

NegateOption createNOption(string flags, string desc = "") {
    return new NegateOption(flags, desc);
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

package class BoolOption : Option {
    // Nullable!bool implyArg;
    Nullable!bool configArg;
    Nullable!bool defaultArg;

    this(string flags, string description) {
        super(flags, description);
        if (!this.isBoolean || this.variadic) {
            error(
                "the value flag must not exist and the flag cannot contain `...` using `new BoolOption`");
        }
        // this.implyArg = null;
        this.configArg = null;
        this.defaultArg = null;
    }

    alias Self = typeof(this);

    Self defaultVal(bool value) {
        this.defaultArg = value;
        return this;
    }

    Self configVal(bool value = true) {
        this.configArg = value;
        return this;
    }

    override Self implyVal(OptionVariant value) {
        alias test_bool = visit!((bool v) => true, v => false);
        if (!test_bool(value))
            parsingError(format!"the imply value must be a bool value in option %s"(this.flags));
        this.innerImplyData = value;
        return this;
    }

    // Self implyVal(bool value) {
    //     this.implyArg = value;
    //     return this;
    // }

    // override Self implyVal() {
    //     this.implyArg = true;
    //     return this;
    // }

    @property
    override bool isValid() const {
        return this.found || !this.configArg.isNull ||
            !this.defaultArg.isNull || !this.innerImplyData.isNull;
    }

    override Self initialize() {
        if (this.settled)
            return this;
        if (!this.isValid) {
            parsingError(format!"the option `%s` must valid before initializing"(this.name));
        }
        this.settled = true;
        if (this.found) {
            this.innerBoolData = (true);
            this.source = Source.Cli;
            return this;
        }
        // if (!this.implyArg.isNull) {
        //     this.innerBoolData = this.implyArg.get;
        //     this.source = Source.Imply;
        //     return this;
        // }
        if (!this.configArg.isNull) {
            this.innerBoolData = this.configArg.get;
            this.source = Source.Config;
            return this;
        }
        if (!this.innerImplyData.isNull) {
            this.innerBoolData = this.innerImplyData.get!bool;
            this.source = Source.Imply;
            return this;
        }
        if (!this.defaultArg.isNull) {
            this.innerBoolData = this.defaultArg.get;
            this.source = Source.Default;
            return this;
        }
        return this;
    }

    @property
    override OptionVariant get() const {
        assert(this.settled);
        return OptionVariant(this.innerBoolData);
    }

    @property
    bool get(T : bool)() const {
        assert(this.settled);
        return this.innerBoolData;
    }

    override string typeStr() const {
        return "type: " ~ "bool";
    }

    override string defaultValStr() const {
        if (defaultArg.isNull)
            return "";
        else
            return "default: " ~ defaultArg.get!bool
                .to!string;
    }
}

// unittest {
//     auto bopt = new BoolOption("-m, --mixed", "").implyVal(false).configVal.defaultVal;
//     bopt.initialize;
//     bool value = bopt.get!bool;
//     assert(!value);
// }

package class ValueOption(T) : Option {
    static assert(isBaseOptionValueType!T && !is(T == bool));

    Nullable!T cliArg;
    Nullable!T envArg;
    // Nullable!(T, bool) implyArg;
    Nullable!(T) configArg;
    Nullable!(T) defaultArg;

    Nullable!(T, bool) presetArg;

    T innerValueData;
    // bool innerBoolData;

    // bool isValueData;

    ParseArgFn!T parseFn;
    ProcessArgFn!T processFn;

    T[] argChoices;

    static if (is(T == int) || is(T == double)) {
        T _min = int.min;
        T _max = int.max;
    }

    this(string flags, string description) {
        super(flags, description);
        if (this.isBoolean || this.variadic) {
            error(
                "the value flag must exist and the flag cannot contain `...` using `new ValueOption!T`");
        }
        this.cliArg = null;
        this.envArg = null;
        // this.implyArg = null;
        this.configArg = null;
        this.defaultArg = null;
        this.innerBoolData = false;
        innerValueData = T.init;
        this.argChoices = [];
        this.isValueData = true;
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
                if (i == j) {
                    error(format!"the element value of choices can not be equal in option `%s`, the values is: `%s`"(
                            this.flags,
                            values.to!string));
                }
            }
        }
        static if (is(T == int) || is(T == double)) {
            if (values.any!(val => val < this._min || val > this._max)) {
                error(format!"the element value of choices cannot be out of %s in option `%s`, the values is: `%s`"(
                        this.rangeOfStr(), this.flags, values.to!string
                ));
            }
        }
        this.argChoices = values;
        return this;
    }

    void _checkVal(in T value) const {
        if (!this.argChoices.empty) {
            if (!this.argChoices.count(value)) {
                parsingError(format!"the value cannot be out of %s in option `%s`, the value is: `%s`"(
                        this.choicesStr(),
                        this.flags,
                        value.to!string
                ));
            }
        }
        static if (is(T == int) || is(T == double)) {
            if (value < this._min || value > this._max) {
                parsingError(format!"the value cannot be out of %s in option `%s`, the value is: `%s`"(
                        this.rangeOfStr(),
                        this.flags,
                        value.to!string
                ));
            }
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
            try {
                auto fn = this.parseFn;
                auto arr = values.map!fn.array;
                return this.choices(arr);
            }
            catch (ConvException e) {
                error(format!"on option `%s` cannot convert the input `%s` to type `%s`"(
                        this.name,
                        values.to!string,
                        T.stringof
                ));
            }
            return this;
        }

        override string rangeOfStr() const {
            if (_min == int.min && _max == int.max)
                return "";
            return "range: " ~ _min.to!string ~ " ~ " ~ _max.to!string;
        }
    }

    Self defaultVal(T value) {
        _checkVal(value);
        this.defaultArg = value;
        return this;
    }

    // override Self defaultVal() {
    //     if (!isOptional) {
    //         error("the option must be optional using `Self defaultVal()`");
    //     }
    //     this.defaultArg = true;
    //     return this;
    // }

    Self configVal(T value) {
        _checkVal(value);
        this.configArg = value;
        return this;
    }

    // override Self configVal() {
    //     if (!isOptional) {
    //         parsingError("the option must be optional using `Self configVal()`");
    //     }
    //     this.configArg = true;
    //     return this;
    // }

    override Self implyVal(OptionVariant value) {
        alias test_t = visit!((T v) => true, v => false);
        if (!test_t(value)) {
            parsingError(format!"the value type must be %s in option `%s`"(T.stringof, this.flags));
        }
        _checkVal(value.get!T);
        this.innerImplyData = value;
        return this;
    }

    // Self implyVal(T value) {
    //     _checkVal(value);
    //     this.implyArg = value;
    //     return this;
    // }

    // override Self implyVal() {
    //     assert(isOptional);
    //     this.implyArg = true;
    //     return this;
    // }

    override Self cliVal(string value, string[] rest...) {
        assert(rest.length == 0);
        try {
            auto tmp = this.parseFn(value);
            _checkVal(tmp);
            this.cliArg = tmp;
        }
        catch (ConvException e) {
            parsingError(format!"on option `%s` cannot convert the input `%s` to type `%s`"(
                    this.name,
                    value,
                    T.stringof
            ));
        }
        return this;
    }

    override Self envVal() {
        if (this.envStr.empty)
            return this;
        try {
            auto tmp = this.parseFn(this.envStr);
            _checkVal(tmp);
            this.envArg = tmp;
        }
        catch (ConvException e) {
            parsingError(format!"on option `%s` cannot convert the input `%s` to type `%s`"(
                    this.name,
                    this.envStr,
                    T.stringof
            ));
        }

        return this;
    }

    Self preset(T value) {
        if (!isOptional) {
            error("the option must be optional using `Self preset()`");
        }
        _checkVal(value);
        this.presetArg = value;
        return this;
    }

    override Self preset() {
        if (!isOptional) {
            error("the option must be optional using `Self preset()`");
        }
        this.presetArg = true;
        return this;
    }

    @property
    override bool isValid() const {
        return this.found ? (!this.presetArg.isNull || !this.cliArg.isNull) : (!this.envArg.isNull
                || !this.configArg.isNull || !this.defaultArg.isNull || !this.innerImplyData.isNull);
    }

    override Self initialize() {
        if (this.settled)
            return this;
        if (!this.isValid) {
            parsingError(format!"the option `%s` must valid before initializing"(this.name));
        }
        this.settled = true;
        alias test_bool = visit!((bool v) => true, (v) => false);
        alias test_t = visit!((T v) => true, (v) => false);
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
        // if (!this.implyArg.isNull) {
        //     if (test_bool(this.implyArg)) {
        //         this.isValueData = false;
        //         this.innerBoolData = this.implyArg.get!bool;
        //     }
        //     if (test_t(this.implyArg))
        //         this.innerValueData = this.implyArg.get!T;
        //     this.source = Source.Imply;
        //     return this;
        // }
        if (!this.configArg.isNull) {
            this.innerValueData = this.configArg.get!T;
            this.source = Source.Config;
            return this;
        }
        if (!this.innerImplyData.isNull) {
            this.innerValueData = this.innerImplyData.get!T;
            this, source = Source.Imply;
            return this;
        }
        if (!this.defaultArg.isNull) {
            this.innerValueData = this.defaultArg.get!T;
            this.source = Source.Default;
            return this;
        }
        return this;
    }

    @property
    override OptionVariant get() const {
        assert(this.settled);
        return isValueData ? OptionVariant(this.get!T) : OptionVariant(this.get!bool);
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

package class VariadicOption(T) : Option {
    static assert(isBaseOptionValueType!T && !is(T == bool));

    Nullable!(T[]) cliArg;
    Nullable!(T[]) envArg;
    // Nullable!(T[], bool) implyArg;
    Nullable!(T[]) configArg;
    Nullable!(T[]) defaultArg;

    Nullable!(T[], bool) presetArg;

    T[] innerValueData;
    // bool innerBoolData;

    // bool isValueData;

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
        if (this.isBoolean || !this.variadic) {
            error(
                "the value flag must exist and the flag must contain `...` using `new VariadicOption!T`");
        }
        this.cliArg = null;
        this.envArg = null;
        // this.implyArg = null;
        this.configArg = null;
        this.defaultArg = null;
        this.innerBoolData = false;
        this.innerValueData = [];
        this.isValueData = true;
        this.argChoices = [];
        this.parseFn = (string v) => to!T(v);
        this.processFn = v => v;
        this.processReduceFn = null;
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
                if (i == j) {
                    error(format!"the element value of choices can not be equal in option `%s`, the values is: `%s`"(
                            this.flags,
                            values.to!string));
                }
            }
        }
        static if (is(T == int) || is(T == double)) {
            if (values.any!(val => val < this._min || val > this._max)) {
                error(format!"the element value of choices cannot be out of %s in option `%s`, the values is: `%s`"(
                        this.rangeOfStr(), this.flags, values.to!string
                ));
            }
        }
        this.argChoices = values;
        return this;
    }

    void _checkVal_impl(in T value) const {
        if (!this.argChoices.empty) {
            if (!this.argChoices.count(value)) {
                parsingError(format!"the value cannot be out of %s in option `%s`, the value is: `%s`"(
                        this.choicesStr(),
                        this.flags,
                        value.to!string
                ));
            }
        }
        static if (is(T == int) || is(T == double)) {
            if (value < this._min || value > this._max) {
                parsingError(format!"the value cannot be out of %s in option `%s`, the value is: `%s`"(
                        this.rangeOfStr(),
                        this.flags,
                        value.to!string
                ));
            }
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
            try {
                auto fn = this.parseFn;
                auto arr = values.map!fn.array;
                return this.choices(arr);
            }
            catch (ConvException e) {
                error(format!"on option `%s` cannot convert the input `%s` to type `%s`"(
                        this.name,
                        values.to!string,
                        T.stringof
                ));
            }
            return this;
        }

        override string rangeOfStr() const {
            if (_min == int.min && _max == int.max)
                return "";
            return "range: " ~ _min.to!string ~ " ~ " ~ _max.to!string;
        }
    }

    Self defaultVal(T value, T[] rest...) {
        auto tmp = [value] ~ rest;
        _checkVal(tmp);
        this.defaultArg = tmp;
        return this;
    }

    // override Self defaultVal() {
    //     if (!isOptional) {
    //         error("the option must be optional using `Self defaultVal()`");
    //     }
    //     this.defaultArg = true;
    //     return this;
    // }

    Self configVal(T value, T[] rest...) {
        auto tmp = [value] ~ rest;
        _checkVal(tmp);
        this.configArg = tmp;
        return this;
    }

    // override Self configVal() {
    //     if (!isOptional) {
    //         parsingError("the option must be optional using `Self configVal()`");
    //     }
    //     this.configArg = true;
    //     return this;
    // }

    override Self implyVal(OptionVariant value) {
        alias test_t = visit!((T[] v) => true, (v) => false);
        if (!test_t(value)) {
            parsingError(format!"the value type must be %s in option `%s`"((T[])
                    .stringof, this.flags));
        }
        _checkVal(value.get!(T[]));
        this.innerImplyData = value;
        return this;
    }

    // Self implyVal(T value, T[] rest...) {
    //     auto tmp = [value] ~ rest;
    //     _checkVal(tmp);
    //     this.implyArg = tmp;
    //     return this;
    // }

    // override Self implyVal() {
    //     assert(isOptional);
    //     this.implyArg = true;
    //     return this;
    // }

    override Self cliVal(string value, string[] rest...) {
        try {
            string[] tmp = [value] ~ rest;
            auto fn = parseFn;
            auto xtmp = tmp.map!(fn).array;
            _checkVal(xtmp);
            if (this._isMerge) {
                cliArg = (cliArg.isNull ? [] : cliArg.get!(T[])) ~ xtmp;
            }
            else
                this.cliArg = xtmp;
        }
        catch (ConvException e) {
            parsingError(format!"on option `%s` cannot convert the input `%s` to type `%s`"(
                    this.name,
                    ([value] ~ rest).to!string,
                    T.stringof
            ));
        }
        return this;
    }

    override Self envVal() {
        if (this.envStr.empty)
            return this;
        try {
            string[] str_arr = split(this.envStr, regex(`;`)).filter!(v => v != "").array;
            auto fn = parseFn;
            auto tmp = str_arr.map!(fn).array;
            _checkVal(tmp);
            this.envArg = tmp;
        }
        catch (ConvException e) {
            parsingError(format!"on option `%s` cannot convert the input `%s` to type `%s`"(
                    this.name,
                    this.envStr,
                    T.stringof
            ));
        }
        return this;
    }

    Self preset(T value, T[] rest...) {
        if (!isOptional) {
            error("the option must be optional using `Self preset()`");
        }
        auto tmp = [value] ~ rest;
        _checkVal(tmp);
        this.presetArg = tmp;
        return this;
    }

    override Self preset() {
        if (!isOptional) {
            error("the option must be optional using `Self preset()`");
        }
        this.presetArg = true;
        return this;
    }

    @property
    override bool isValid() const {
        return this.found ? (!this.presetArg.isNull || !this.cliArg.isNull) : (!this.envArg.isNull || !this
                .configArg.isNull || !this.defaultArg.isNull || !this.innerImplyData.isNull);
    }

    override Self initialize() {
        if (this.settled)
            return this;
        if (!this.isValid) {
            parsingError(format!"the option `%s` must valid before initializing"(this.name));
        }
        this.settled = true;
        alias test_bool = visit!((bool v) => true, (v) => false);
        alias test_t = visit!((T[] v) => true, (v) => false);
        this.innerValueData = [];
        if (this.found) {
            if (!this.cliArg.isNull) {
                this.innerValueData = this.cliArg.get!(T[]);
                this.source = Source.Cli;
                if (_isMerge)
                    goto _env_ini_;
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
    _env_ini_:
        if (!this.envArg.isNull) {
            if (this._isMerge) {
                this.innerValueData ~= this.envArg.get!(T[]);
                this.source = cast(int) this.source < cast(int) Source.Env ?
                    this.source : Source.Env;
                goto _config_ini_;
            }
            this.innerValueData = this.envArg.get!(T[]);
            this.source = Source.Env;
            return this;
        }
    _config_ini_:
        if (!this.configArg.isNull) {
            if (this._isMerge) {
                this.innerValueData ~= this.configArg.get!(T[]);
                this.source = cast(int) this.source < cast(int) Source.Config ?
                    this.source : Source.Config;
                goto _imply_ini_;
            }
            this.innerValueData = this.configArg.get!(T[]);
            this.source = Source.Config;
            return this;
        }
    _imply_ini_:
        if (!this.innerImplyData.isNull) {
            if (this._isMerge) {
                this.innerValueData ~= this.innerImplyData.get!(T[]);
                this.source = cast(int) this.source < cast(int) Source.Imply ?
                    this.source : Source.Imply;
                goto _default_ini_;
            }
            this.innerValueData = this.innerImplyData.get!(T[]);
            this.source = Source.Imply;
            return this;
        }
    _default_ini_:
        if (!this.defaultArg.isNull) {
            if (this._isMerge) {
                this.innerValueData ~= this.defaultArg.get!(T[]);
                this.source = cast(int) this.source < cast(int) Source.Default ?
                    this.source : Source.Default;
                return this;
            }
            this.innerValueData = this.defaultArg.get!(T[]);
            this.source = Source.Default;
            return this;
        }
        return this;
    }

    @property
    override OptionVariant get() const {
        assert(this.settled);
        return isValueData ? OptionVariant(this.get!(T[])) : OptionVariant(this.get!bool);
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
        if (!reduce_fn) {
            error(format!"connot get `%s` value from option `%s`"(
                    U.stringof,
                    this.flags
            ));
        }
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

/++ 
the negate option like `--no-flag`, which is controller option that doesn't contains inner value.
+/
class NegateOption {
package:
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
        if ((matchFirst(this.longFlag, PTN_NEGATE)).empty) {
            error("the long flag must star with `--no-` using `new NegateOption`");
        }
    }

public:
    /// test whether the other `NegateOption` variable's flag same in some parts
    bool matchFlag(in NegateOption other) const {
        return this.longFlag == other.longFlag ||
            (this.shortFlag.empty ? false : this.shortFlag == other.shortFlag);
    }

    /// test whether the other `Option` variable's flag same in some parts
    bool matchFlag(in Option other) const {
        auto nshort_flag = this.shortFlag;
        auto short_flag = other.shortFlag;
        return short_flag.empty ? false : short_flag == nshort_flag;
    }

    /// get the name of option
    @property
    string name() const {
        return this.longFlag[5 .. $].idup;
    }

    /// get the attribute name of option in camel-like, which is gennerated from `this.name`
    @property
    string attrName() const {
        return _camelCase(this.name);
    }

    /// test whether a string matches this option's long/short flag
    bool isFlag(string flag) const {
        return !flag.empty && (this.shortFlag == flag || this.longFlag == flag);
    }
}

/// creae a negate option
/// Params:
///   flags = the flag like `-F, --no-flag`
///   desc = the description of option
/// Returns: a negate option
NegateOption createNegateOption(string flags, string desc = "") {
    return new NegateOption(flags, desc);
}

unittest {
    import std.stdio;

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

package OptionFlags splitOptionFlags(string flags) {
    string short_flag = "", long_flag = "", value_flag = "";
    string[] flag_arr = flags.split(PTN_SP);
    if (flag_arr.length > 3)
        error(format!"error type of flag `%s`"(flags));
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

package bool testType(T)(in OptionNullable value) {
    if (is(T == typeof(null)) && value.isNull)
        return true;
    if (!is(T == typeof(null)) && value.isNull)
        return false;
    alias test_t = visit!((const T v) => true, v => false);
    return test_t(value);
}

private void error(string msg = "", string code = "option.error") {
    throw new CMDLineError(msg, 1, code);
}

private void parsingError(string msg = "", string code = "option.error") {
    throw new InvalidOptionError(msg, code);
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
