/++
$(H2 The extenstion module for Cmdline)

This module give a new programming way to build the command line prgram.
And it is publicly imported into main modlue `cmdline`.

Using the following mixin-macro which are used for being embedded in a struct whose name
is end with `Result` and fields must be among `ArgVal`, `OptVal` and the pointer to other
structs that are satisfied with and the two function `coustruct` and `parse`, you can 
build and parse the command line argument and option parameters. And Also, We can get the
parsed value from command line more easily.

Authors: 笑愚(xiaoyu)
+/
module cmdline.ext;

import std.traits;
import std.meta;
import std.range : ElementType;

import cmdline.option;
import cmdline.argument;
import cmdline.command;

public:

enum __CMDLINE_EXT_isInnerArgValField__(T) = hasMember!(T, "ARGVAL_FLAG_");
enum __CMDLINE_EXT_isInnerOptValField__(T) = hasMember!(T, "OPTVAL_FLAG_");
enum __CMDLINE_EXT_isInnerValField__(T) = __CMDLINE_EXT_isInnerArgValField__!T
    || __CMDLINE_EXT_isInnerOptValField__!T;
enum __CMDLINE_EXT_isInnerSubField__(T) = isPointer!T && isOutputResult!(PointerTarget!T);
enum __CMDLINE_EXT_isInnerValFieldOrResult__(T) = __CMDLINE_EXT_isInnerValField__!T
    || __CMDLINE_EXT_isInnerSubField__!T;

/// check whether a type is the struct that can be the  
/// container to store the parsed value from command line. 
enum isOutputResult(T) = is(T == struct)
    && T.stringof.length > 6 && (T.stringof)[$ - 6 .. $] == "Result"
    && FieldTypeTuple!T.length > 0
    && allSatisfy!(__CMDLINE_EXT_isInnerValFieldOrResult__, FieldTypeTuple!T);

/// Add description to a registered argument.
/// Params:
///   field = the argument in the type of `ArgVal`
///   desc = the description
mixin template DESC_ARG(alias field, string desc) {
    static assert(__CMDLINE_EXT_isInnerArgValField__!(typeof(field)));
    debug pragma(msg, "enum DESC_ARG_" ~ field.stringof ~ "_ = \"" ~ desc ~ "\";");
    mixin("enum DESC_ARG_" ~ field.stringof ~ "_ = \"" ~ desc ~ "\";");
}

/// Add description to a registered option.
/// Params:
///   field = the option in the type of `OptVal`
///   desc = the description
mixin template DESC_OPT(alias field, string desc) {
    static assert(__CMDLINE_EXT_isInnerOptValField__!(typeof(field)));
    debug pragma(msg, "enum DESC_OPT_" ~ field.stringof ~ "_ = \"" ~ desc ~ "\";");
    mixin("enum DESC_OPT_" ~ field.stringof ~ "_ = \"" ~ desc ~ "\";");
}

/// Add description to a registered option or argument.
/// Params:
///   field = the option or argument in the type of `OptVal` or `ArgVal`
///   desc = the description
mixin template DESC(alias field, string desc) {
    static if (__CMDLINE_EXT_isInnerArgValField__!(typeof(field))) {
        mixin DESC_ARG!(field, desc);
    }
    else static if (__CMDLINE_EXT_isInnerOptValField__!(typeof(field))) {
        mixin DESC_OPT!(field, desc);
    }
    else {
        static assert(0);
    }
}

/// set the default value to a registered option or argument
/// Params:
///   field = the option or argument in the type of `OptVal` or `ArgVal`
///   val = the default value
mixin template DEFAULT(alias field, alias val) {
    alias FType = typeof(field);
    static assert(!is(FType.InnerType == bool));
    static if (__CMDLINE_EXT_isInnerOptValField__!FType
        && FType.VARIADIC
        && is(ElementType!(FType.InnerType) == void)) {
        static assert(is(typeof(val) == FType.InnerType[]));
    }
    else {
        static assert(is(typeof(val) : FType.InnerType));
    }
    debug pragma(msg, "static " ~ typeof(val)
            .stringof ~ " DEFAULT_" ~ field.stringof ~ "_ = " ~ val.stringof ~ ";");
    mixin("static " ~ typeof(val).stringof ~ " DEFAULT_" ~ field.stringof ~ "_ = " ~ val.stringof ~ ";");
}

/// set the preset value to a registered option
/// Params:
///   field = the option in the type of `OptVal`
///   val = the preset value
mixin template PRESET(alias field, alias val) {
    alias FType = typeof(field);
    static assert(__CMDLINE_EXT_isInnerOptValField__!FType && !is(FType.InnerType == bool) && FType
            .OPTIONAL);
    static if (FType.VARIADIC && is(ElementType!(FType.InnerType) == void)) {
        static assert(is(typeof(val) == FType.InnerType[]));
    }
    else {
        static assert(is(typeof(val) : FType.InnerType));
    }
    debug pragma(msg, "static " ~ typeof(val)
            .stringof ~ " PRESET_" ~ field.stringof ~ "_ = " ~ val.stringof ~ ";");
    mixin("static " ~ typeof(val).stringof ~ " PRESET_" ~ field.stringof ~ "_ = " ~ val.stringof ~ ";");
}

/// set the env key from which get the values to a registered option
/// Params:
///   field = the option in the type of `OptVal`
///   envKey = the env key
mixin template ENV(alias field, string envKey) {
    alias FType = typeof(field);
    static assert(__CMDLINE_EXT_isInnerOptValField__!FType && !is(FType.InnerType == bool));
    debug pragma(msg, "enum ENV_" ~ field.stringof ~ "_ = \"" ~ envKey ~ "\";");
    mixin("enum ENV_" ~ field.stringof ~ "_ = \"" ~ envKey ~ "\";");
}

/// set the choices list to a registered option or argument
/// Params:
///   field = the option or argument in the type of `OptVal` or `ArgVal`
///   Args = the choices list items
mixin template CHOICES(alias field, Args...) {
    static assert(Args.length);
    alias FType = typeof(field);
    static assert(!is(FType.InnerType == bool));
    enum isRegularType(alias val) = is(typeof(val) : FType.InnerType)
        || is(ElementType!(FType.InnerType) == typeof(val));
    import std.meta;

    static assert(allSatisfy!(isRegularType, Args));
    debug pragma(msg, "static " ~ typeof(
            Args[0])[].stringof ~
            " CHOICES_" ~ field.stringof ~
            "_ = " ~ [Args].stringof ~ ";");
    mixin("static " ~ typeof(
            Args[0])[].stringof ~
            " CHOICES_" ~ field.stringof ~
            "_ = " ~ [Args].stringof ~ ";");
}

/// set the range of a registered option or argument which inner
/// type is numeric type
/// Params:
///   field = the option or argument in the type of `OptVal` or `ArgVal`
///   Args = the minimum and the maximum in numeric type
mixin template RANGE(alias field, Args...) {
    static assert(Args.length > 1);
    alias FType = typeof(field);
    static assert(is(FType.InnerType == int) || is(FType.InnerType == double));
    static assert(is(typeof(Args[0]) == typeof(Args[1])) && is(typeof(Args[0])));
    static assert(is(typeof(Args[0]) : FType.InnerType) && Args[0] < Args[1]);
    debug pragma(msg, "enum RANGE_" ~ field.stringof ~ "_MIN_ = " ~ Args[0].stringof ~ ";");
    debug pragma(msg, "enum RANGE_" ~ field.stringof ~ "_MAX_ = " ~ Args[1].stringof ~ ";");
    mixin("enum RANGE_" ~ field.stringof ~ "_MIN_ = " ~ Args[0].stringof ~ ";");
    mixin("enum RANGE_" ~ field.stringof ~ "_MAX_ = " ~ Args[1].stringof ~ ";");
}

/// disable the merge feature of a registered variadic option
/// Params:
///   field = the registered variadic option in the type of `OptVal`
mixin template DISABLE_MERGE(alias field) {
    alias FType = typeof(field);
    static assert(FType.VARIADIC);
    debug pragma(msg, "enum DISABLE_MERGE_" ~ field.stringof ~ "_ = " ~ "true;");
    mixin("enum DISABLE_MERGE_" ~ field.stringof ~ "_ = " ~ "true;");
}

/// hide a registered option from `help` sub-command and action-option
/// Params:
///   field = the registered option in the type of `OptVal`
mixin template HIDE(alias field) {
    static assert(__CMDLINE_EXT_isInnerOptValField__!(typeof(field)));
    debug pragma(msg, "enum HIDE_" ~ field.stringof ~ "_ = " ~ "true;");
    mixin("enum HIDE_" ~ field.stringof ~ "_ = " ~ "true;");
}

/// set a negate option for a registered option, and its long flag is
/// `--no-NAME_OF_OPTION`
/// Params:
///   field = the registered option in the type of `OptVal`
///   shortFlag = the short flag of the negate option
///   desc = the description of the negate option
mixin template NEGATE(alias field, string shortFlag, string desc = "") {
    static assert(__CMDLINE_EXT_isInnerOptValField__!(typeof(field)));
    debug pragma(msg, "enum NEGATE_" ~ field.stringof ~ "_ = \"" ~ shortFlag ~ "\";");
    mixin("enum NEGATE_" ~ field.stringof ~ "_ = \"" ~ shortFlag ~ "\";");
    static if (desc.length) {
        mixin("enum NEGATE_" ~ field.stringof ~ "_DESC_ =\"" ~ desc ~ "\";");
    }
}

/// set the version string and enable the `version` sub-command and action-option
/// Params:
///   ver = the version string
///   flags = the flag of the version action-option which name would be the name of
///     the relevant sub-command. if not defied then the flag would be `--version -V`
mixin template VERSION(string ver, string flags = "") {
    debug pragma(msg, "enum VERSION_ = \"" ~ ver ~ "\";");
    mixin("enum VERSION_ = \"" ~ ver ~ "\";");
    debug pragma(msg, "enum VERSION_FLAGS_ = \"" ~ flags ~ "\";");
    mixin("enum VERSION_FLAGS_ = \"" ~ flags ~ "\";");
}

/// set an alias
/// Params:
///   name = the alias
mixin template ALIAS(string name) {
    debug pragma(msg, "enum ALIAS_ = \"" ~ name ~ "\";");
    mixin("enum ALIAS_ = \"" ~ name ~ "\";");
}

/// set description
/// Params:
///   desc = the description
mixin template DESC(string desc) {
    enum DESC_ = desc;
}

/// <br><br>
/// hide the command from `help` sub-command and action-option, usually used on sub-command
mixin template HIDE() {
    enum HIDE_ = true;
}

/// disallow the excess arguments
mixin template DISALLOW_EXCESS_ARGS() {
    enum DISALLOW_EXCESS_ARGS_ = true;
}

/// show help after parsing error
mixin template SHOW_HELP_AFTER_ERR() {
    enum SHOW_HELP_AFTER_ERR_ = true;
}

/// don't show suggestions after parsing error
mixin template NO_SUGGESTION() {
    enum NO_SUGGESTION_ = true;
}

/// disallow the feature that can combine flags
mixin template DISALLOW_COMBINE() {
    enum DONT_COMBINE_ = true;
}

/// <br><br>
/// disable the feature that variadic options under the command can merge value
/// from various source
mixin template DISABLE_MERGE() {
    enum DISABLE_MERGE_ = true;
}

/// disable the `help` sub-command and action-option
mixin template DISABLE_HELP() {
    enum DISABLE_HELP_ = true;
}

/// enable gaining value from config file in json and set an option that specifies
/// the directories where the config file should be
/// Params:
///   flags = the flag of the config option which is used for specifying the directories
///     where the config file should be. if not defied then the flag would be
///     `-C, --config <config-dirs...>`
mixin template CONFIG(string flags = "") {
    debug pragma(msg, "enum CONFIG_FLAGS_ = \"" ~ flags ~ "\";");
    mixin("enum CONFIG_FLAGS_ = \"" ~ flags ~ "\";");
}

/// set the options acting as arguments on command line
/// Params:
///   Args = the options in the type of `OptVal`
mixin template OPT_TO_ARG(Args...) {
    static assert(Args.length);
    enum to_string(alias var) = var.stringof;
    import std.meta;

    debug pragma(msg, "static " ~ string[Args.length].stringof ~
            " OPT_TO_ARG_ = " ~ [staticMap!(to_string, Args)].stringof ~ ";");
    mixin("static " ~ string[Args.length].stringof ~
            " OPT_TO_ARG_ = " ~ [staticMap!(to_string, Args)].stringof ~ ";");
}

/// set the default sub-command which would act like the main-command except
/// `help`, `version` and `config` options and sub-command if exists.
/// Params:
///   sub = the sub command of the command
mixin template DEFAULT(alias sub) {
    alias SubType = typeof(sub);
    import std.traits;

    static assert(isPointer!SubType && isOutputResult!(PointerTarget!SubType));
    enum DEFAULT_ = sub.stringof;
}

/// prepare for the future use of function `ready`, which must be embedded at the top
/// of struct domain with `END` mixin-marco at the end of this struct domain.
mixin template BEGIN() {
    enum bool __SPE_BEGIN_SEPCIAL__ = true;
    alias __SELF__ = __traits(parent, __SPE_BEGIN_SEPCIAL__);
}

/// prepare for the future use of function `ready`, which must be embedded at the end
/// of struct domain with `BEGIN` mixin-marco at the begin of this struct domain.
mixin template END() {
    import std.traits;
    import std.meta;

    enum bool __SPE_END_SEPCIAL__ = true;
    static foreach (index, Type; Filter!(__CMDLINE_EXT_isInnerSubField__, FieldTypeTuple!__SELF__)) {
        mixin("static bool IF_" ~ PointerTarget!Type.stringof ~ "_ = false;");
    }
}

/// detect whether a sub command's container of a main command is ready for use.
/// for using this function, the `BEGIN` and `END` mixin-macro must be embeed in
/// main command container.
/// `T` is the type in sub-command container, `U` is the type in main-command container
/// Params:
///   output = the main-command container
/// Returns: `true` if the sub-command is ready, otherwise is not ready.
bool ready(T, U)(const ref U output)
        if (isOutputResult!T && isOutputResult!U && hasMember!(U, "__SPE_END_SEPCIAL__")) {
    return mixin(output.stringof ~ '.' ~ "IF_" ~ T.stringof ~ '_');
}

/// get a pointer to sub-command container.
/// `T` is the type in sub-command container, `U` is the type in main-command container
/// Params:
///   output = the main-command container
/// Returns: a pointer to sub-command container if the sub-command is ready,
///     otherwise `null` 
const(T)* subResult(T, U)(const ref U output)
        if (isOutputResult!T && isOutputResult!U) {
    alias ftypes = FieldTypeTuple!U;
    alias fnames = FieldNameTuple!U;
    static foreach (index, Type; ftypes) {
        {
            static if (__CMDLINE_EXT_isInnerSubField__!Type && is(PointerTarget!Type == T)) {
                return mixin(output.stringof ~ '.' ~ fnames[index]);
            }
        }
    }
    return null;
}

/// the field of command container which is used to register a argument on the command.
/// the name of it is the name of this argument.
/// can implicitly convert to bool value same as the result of `ArgVal.isValid`.
/// `T` is the innerType of the argument,
/// `isOptional` `true` to set it optional, default is `false`.
struct ArgVal(T, bool isOptional = false) {
    static assert(isArgValueType!T);
    Argument _inner;

    enum ARGVAL_FLAG_ = true;
    enum OPTIONAL = isOptional;

    /// the inner type of the argument
    alias InnerType = T;

    /// test whether the inner value is ready.
    /// Returns: `true` if ready, otherwise not ready.
    bool isValid() const {
        return _inner.settled;
    }

    // make `ArgVal` enable to implicitly convert to bool value
    // same as the result of `isValid`
    alias isValid this;

    /// get the inner value
    auto get() const {
        return _inner.get!T;
    }

    /// assign the inner value through passing into `Argument` variable
    auto opAssign(Argument value) {
        this._inner = value;
        return this;
    }
}

/// the field of command container which is used to register a option on the command.
/// the name of it is the name of this option.
/// can implicitly convert to bool value same as the result of `ArgVal.isValid`.
/// `T` is the innerType of the option or the elemental type of innerType
/// `isMandatory` `true` to set it mandatory, default is `false`,
/// `shortAndVal` the short flag and value flag(if needed) seperated by space, comma and `|`
struct OptVal(T, string shortAndVal, bool isMandatory = false) {
    static assert(isOptionValueType!T);
    Option _inner;

    /// the inner type of the option
    alias InnerType = T;

    enum OPTVAL_FLAG_ = true;
    enum SHORT_FLAG_AND_VAL_STR = shortAndVal;
    enum MANDATORY = isMandatory;

    static if (!is(T == bool)) {
        static if (shortAndVal[$ - 1] == ']') {
            enum OPTIONAL = true;
        }
        else static if (shortAndVal[$ - 1] == '>') {
            enum OPTIONAL = false;
        }
        else {
            static assert(0);
        }
        static if (shortAndVal.length > 5 && shortAndVal[$ - 4 .. $ - 1] == "...") {
            enum VARIADIC = true;
        }
        else {
            enum VARIADIC = false;
        }
    }

    /// test whether the inner value is ready.
    /// Returns: `true` if ready, otherwise not ready.
    bool isValid() const {
        return _inner.settled;
    }

    /// get the value in type of `T`
    auto get() const {
        return _inner.get!T;
    }

    /// assign the inner value through passing into `Option` variable
    auto opAssign(Option value) {
        this._inner = value;
        return this;
    }
}

private alias getMember(alias T, string flag) = __traits(getMember, T, flag);

/// construct the command line program without action callback
/// Returns: the root command in `Command` that is confiured according to the given command conatiner type.
Command construct(T)() if (isOutputResult!T) {
    alias fnames = FieldNameTuple!T;
    alias ftypes = FieldTypeTuple!T;
    Command cmd = createCommand(T.stringof[0 .. $ - 6]._tokeytab);
    static if (hasMember!(T, "DESC_")) {
        cmd.description(T.DESC_);
    }
    static if (hasMember!(T, "HIDE_")) {
        cmd._hidden = true;
    }
    static if (hasMember!(T, "DISALLOW_EXCESS_ARGS_")) {
        cmd.allowExcessArguments(false);
    }
    static if (hasMember!(T, "VERSION_")) {
        cmd.setVersion(T.VERSION_, T.VERSION_FLAGS_);
    }
    static if (hasMember!(T, "SHOW_HELP_AFTER_ERR_")) {
        cmd.showHelpAfterError(true);
    }
    static if (hasMember!(T, "NO_SUGGESTION_")) {
        cmd.showSuggestionAfterError(false);
    }
    static if (hasMember!(T, "DONT_COMBINE_")) {
        cmd.comineFlagAndOptionValue(false);
    }
    static if (hasMember!(T, "DISABLE_MERGE_")) {
        cmd.allowVariadicMerge(false);
    }
    static if (hasMember!(T, "DISABLE_HELP_")) {
        cmd.disableHelp();
    }
    static if (hasMember!(T, "CONFIG_FLAGS_")) {
        cmd.setConfigOption(T.CONFIG_FLAGS_);
    }
    static if (hasMember!(T, "DEFAULT_")) {
        cmd._defaultCommandName = T.DEFAULT_;
    }
    static if (hasMember!(T, "ALIAS_")) {
        cmd.aliasName(T.ALIAS_);
    }
    static foreach (index, Type; ftypes) {
        static if (__CMDLINE_EXT_isInnerArgValField__!Type) {
            {
                mixin SetArgValField!(cmd, Type, T, index, fnames);
            }
        }
        else static if (__CMDLINE_EXT_isInnerOptValField__!Type) {
            {
                mixin SetOptValField!(cmd, Type, T, index, fnames);
            }
        }
        else {
            {
                mixin SetSubCommand!(cmd, Type);
            }
        }
    }
    static if (hasStaticMember!(T, "OPT_TO_ARG_")) {
        auto arr = getMember!(T, "OPT_TO_ARG_");
        import std.algorithm;
        import std.array;

        auto tmp = arr[].map!(str => _tokeytab(str)).array;
        cmd.argToOpt(tmp[0], tmp[1 .. $]);
    }
    return cmd;
}

/// parse the command line option and argument parameters according to the given command conatiner type.
/// T = the command conatiner type
/// Params:
///   argv = the command line arguments in string
/// Returns: an initialized instance of the command conatiner type
T parse(T)(in string[] argv) if (isOutputResult!T) {
    alias fnames = FieldNameTuple!T;
    alias ftypes = FieldTypeTuple!T;
    auto cmd = construct!T;
    if (argv.length)
        cmd.parse(argv);
    T output;
    static foreach (index, name; fnames) {
        {
            mixin InitOutputResultField!(cmd, output, index, name, ftypes);
        }
    }
    return output;
}

private:

mixin template InitOutputResultField(alias cmd, alias output, alias index, alias name, ftypes...) {
    alias Type = ftypes[index];
    static if (__CMDLINE_EXT_isInnerArgValField__!Type) {
        auto x = mixin(output.stringof ~ '.' ~ name) = cmd.findArgument(name._tokeytab);
    }
    else static if (__CMDLINE_EXT_isInnerOptValField__!Type) {
        auto x = mixin(output.stringof ~ '.' ~ name) = cmd.findOption(name._tokeytab);
    }
    else {
        alias T = PointerTarget!Type;
        alias sfnames = FieldNameTuple!T;
        alias sftypes = FieldTypeTuple!T;
        Command sub = cmd.findCommand(T.stringof[0 .. $ - 6]._tokeytab);
        auto xfn = () {
            if (cmd._called_sub == sub._name) {
                static if (hasMember!(typeof(output), "__SPE_END_SEPCIAL__")) {
                    mixin(output.stringof ~ '.' ~ "IF_" ~ T.stringof ~ '_') = true;
                }
                auto sub_output = mixin(output.stringof ~ '.' ~ name) = new T;
                static foreach (index, name; sfnames) {
                    {
                        mixin InitOutputResultField!(sub, sub_output, index, name, sftypes);
                    }
                }
            }
            return 1;
        };
        auto _x_ = xfn();
    }
}

mixin template SetArgValField(alias cmd, Type, T, alias index, fnames...) {
    alias IType = Type.InnerType;
    enum string arg_name = fnames[index];
    enum bool optional = Type.OPTIONAL;
    enum bool variadic = !isSomeString!IType && !is(ElementType!IType == void);
    string nameOutput = _tokeytab(arg_name) ~ (variadic ? "..." : "");
    Argument arg = createArgument!(IType)(
        optional ? "[" ~ nameOutput ~ "]" : "<" ~ nameOutput ~ ">"
    );
    enum string fdesc = "DESC_ARG_" ~ arg_name ~ '_';
    enum string fdef = "DEFAULT_" ~ arg_name ~ '_';
    enum string fchoices = "CHOICES_" ~ arg_name ~ "_";
    enum string frange_min = "RANGE_" ~ arg_name ~ "_MIN_";
    enum string frange_max = "RANGE_" ~ arg_name ~ "_MAX_";
    static if (hasMember!(T, fdesc)) {
        auto x = arg.description(getMember!(T, fdesc));
    }
    static if (hasStaticMember!(T, fdef)) {
        auto xx = arg.defaultVal(getMember!(T, fdef));
    }
    static if (hasStaticMember!(T, fchoices)) {
        auto xxx = arg.choices(getMember!(T, fchoices));
    }
    static if (hasMember!(T, frange_min) && hasMember!(T, frange_max)) {
        auto xxxxx = arg.rangeOf(
            getMember!(T, frange_min),
            getMember!(T, frange_max)
        );
    }
    auto xxxxxx = cmd.addArgument(arg);
}

mixin template SetOptValField(alias cmd, Type, T, alias idnex, fnames...) {
    alias IType = Type.InnerType;
    enum string opt_name = fnames[idnex];
    enum bool mandatory = Type.MANDATORY;
    string kname = _tokeytab(opt_name);
    Option opt = createOption!IType("--" ~ kname ~ ' '
            ~ Type.SHORT_FLAG_AND_VAL_STR);
    enum string fdesc = "DESC_OPT_" ~ opt_name ~ '_';
    enum string fdef = "DEFAULT_" ~ opt_name ~ '_';
    enum string fpreset = "PRESET_" ~ opt_name ~ '_';
    enum string fenv = "ENV_" ~ opt_name ~ '_';
    enum string fchoices = "CHOICES_" ~ opt_name ~ "_";
    enum string frange_min = "RANGE_" ~ opt_name ~ "_MIN_";
    enum string frange_max = "RANGE_" ~ opt_name ~ "_MAX_";
    enum string fnegate_sh = "NEGATE_" ~ opt_name ~ '_';
    enum string fnegate_desc = "NEGATE_" ~ opt_name ~ "_DESC_";
    auto x = opt.makeMandatory(mandatory);
    static if (hasMember!(T, "DISABLE_MERGE_" ~ opt_name ~ '_')) {
        auto xx = opt.merge(false);
    }
    static if (hasMember!(T, "HIDE_" ~ opt_name ~ '_')) {
        auto xxx = opt.hidden = true;
    }
    NegateOption nopt = null;
    static if (hasMember!(T, fnegate_sh)) {
        string short_flag = getMember!(T, fnegate_sh);
        static if (hasMember!(T, fnegate_desc)) {
            auto _x_ = getMember!(T, fnegate_desc);
        }
        else {
            auto _x_ = "";
        }
        auto xxxx = nopt = createNegateOption("--no-" ~ kname ~ ' ' ~ short_flag, _x_);
    }
    static if (hasMember!(T, fdesc)) {
        auto xxxxx = opt.description(getMember!(T, fdesc));
    }
    static if (hasStaticMember!(T, fdef)) {
        auto xxxxxx = opt.defaultVal(getMember!(T, fdef));
    }
    static if (hasStaticMember!(T, fchoices)) {
        auto xxxxxxx = opt.choices(getMember!(T, fchoices));
    }
    static if (hasMember!(T, frange_min) && hasMember!(T, frange_max)) {
        auto xxxxxxxx = opt.rangeOf(
            getMember!(T, frange_min),
            getMember!(T, frange_max)
        );
    }
    static if (hasStaticMember!(T, fpreset)) {
        auto xxxxxxxxx = opt.preset(getMember!(T, fpreset));
    }
    static if (hasMember!(T, fenv)) {
        auto xxxxxxxxxx = opt.env(getMember!(T, fenv));
    }
    auto xxxxxxxxxxx = cmd.addOption(opt);
    auto xxxxxxxxxxxx = nopt ? cmd.addOption(nopt) : cmd;
}

mixin template SetSubCommand(alias cmd, Type) {
    alias SubT = PointerTarget!Type;
    Command sub = construct!SubT;
    auto x = cmd.addCommand(sub);
}

string _tokeytab(string from) {
    import std.regex;
    import std.string : toLower;

    auto trans = (Captures!(string) m) { return '-' ~ toLower(m.hit); };
    return cast(char) toLower(from[0]) ~ replaceAll!(trans)(from[1 .. $], regex(`[A-Z]`));
}

// mixin template IMPLIES(alias field, string key, alias val) {
//     alias FType = typeof(field);
//     static assert(__CMDLINE_EXT_isInnerOptValField__!FType && !is(FType.InnerType == bool));
//     static assert(isOptionValueType!(typeof(val)));
//     debug pragma(msg, "static " ~ typeof(val)
//             .stringof ~
//             " IMPLIES_" ~ field.stringof ~ "_" ~ key ~
//             "_ = " ~ val.stringof ~ ";");
//     mixin("static " ~ typeof(val)
//             .stringof ~
//             " IMPLIES_" ~ field.stringof ~ "_" ~ key ~
//             "_ = " ~ val.stringof ~ ";");
// }

// mixin template IMPLIES_BOOL(alias field, Args...) {
//     static assert(Args.length);
//     alias FType = typeof(field);
//     static assert(allSatisfy!(isSomeString, Args));
//     debug pragma(msg, "static " ~ typeof(
//             Args[0])[].stringof ~
//             " IMPLIES_" ~ field.stringof ~
//             "_ = " ~ [Args].stringof ~ ";");
//     mixin("static " ~ typeof(
//             Args[0])[].stringof ~
//             " IMPLIES_" ~ field.stringof ~
//             "_ = " ~ [Args].stringof ~ ";");
// }
