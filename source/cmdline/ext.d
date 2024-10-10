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
    && (__CMDLINE_EXT_IndexOfCmdlineAttr__!T != -1 || (T.stringof.length > 6 && (T.stringof)[$ - 6 .. $] == "Result"));

template __CMDLINE_EXT_IndexOfCmdlineAttr__(T) {
    int __CMDLINE_EXT_IndexOfCmdlineAttr__() {
        alias AttrSeq = __traits(getAttributes, T);
        int result = -1;
        static foreach (idx, attr; AttrSeq) {
            static if (attr.stringof == "package cmdline") {
                result = cast(int) idx;
            }
        }
        return result;
    }
}
// && (FieldTypeTuple!T.length > 0 ? )
// && anySatisfy!(__CMDLINE_EXT_isInnerValFieldOrResult__, FieldTypeTuple!T);

/// Add description to a registered argument.
/// Params:
///   field = the argument in the type of `ArgVal`
///   desc = the description
mixin template DESC_ARG(alias field, string desc) {
    static assert(__CMDLINE_EXT_isInnerArgValField__!(typeof(field)));
    // debug pragma(msg, "enum DESC_ARG_" ~ field.stringof ~ "_ = \"" ~ desc ~ "\";");
    mixin("enum DESC_ARG_" ~ field.stringof ~ "_ = \"" ~ desc ~ "\";");
}

/// Add description to a registered option.
/// Params:
///   field = the option in the type of `OptVal`
///   desc = the description
mixin template DESC_OPT(alias field, string desc) {
    static assert(__CMDLINE_EXT_isInnerOptValField__!(typeof(field)));
    // debug pragma(msg, "enum DESC_OPT_" ~ field.stringof ~ "_ = \"" ~ desc ~ "\";");
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
    alias ___FType___CMDLINE = typeof(field);
    static assert(is(typeof(val) : ___FType___CMDLINE.InnerType));
    // debug pragma(msg, "static " ~ typeof(val)
    //         .stringof ~ " DEFAULT_" ~ field.stringof ~ "_ = " ~ val.stringof ~ ";");
    mixin("static " ~ typeof(val).stringof ~ " DEFAULT_" ~ field.stringof ~ "_ = " ~ val.stringof ~ ";");
}

/// set the preset value to a registered option
/// Params:
///   field = the option in the type of `OptVal`
///   val = the preset value
mixin template PRESET(alias field, alias val) {
    alias ___FType___CMDLINE = typeof(field);
    static assert(__CMDLINE_EXT_isInnerOptValField__!___FType___CMDLINE && !is(
            ___FType___CMDLINE.InnerType == bool) && ___FType___CMDLINE.OPTIONAL);
    static assert(is(typeof(val) : ___FType___CMDLINE.InnerType));
    // debug pragma(msg, "static " ~ typeof(val)
    //         .stringof ~ " PRESET_" ~ field.stringof ~ "_ = " ~ val.stringof ~ ";");
    mixin("static " ~ typeof(val).stringof ~ " PRESET_" ~ field.stringof ~ "_ = " ~ val.stringof ~ ";");
}

/// set the env key from which get the values to a registered option
/// Params:
///   field = the option in the type of `OptVal`
///   envKey = the env key
mixin template ENV(alias field, string envKey) {
    alias ___FType___CMDLINE = typeof(field);
    static assert(__CMDLINE_EXT_isInnerOptValField__!___FType___CMDLINE && !is(
            ___FType___CMDLINE.InnerType == bool));
    // debug pragma(msg, "enum ENV_" ~ field.stringof ~ "_ = \"" ~ envKey ~ "\";");
    mixin("enum ENV_" ~ field.stringof ~ "_ = \"" ~ envKey ~ "\";");
}

/// set the choices list to a registered option or argument
/// Params:
///   field = the option or argument in the type of `OptVal` or `ArgVal`
///   Args = the choices list items
mixin template CHOICES(alias field, Args...) {
    static assert(Args.length);
    alias ___FType___CMDLINE = typeof(field);
    static assert(!is(___FType___CMDLINE.InnerType == bool));
    enum isRegularType(alias val) = is(typeof(val) : ___FType___CMDLINE.InnerType)
        || is(ElementType!(___FType___CMDLINE.InnerType) == typeof(val));
    import std.meta;

    static assert(allSatisfy!(isRegularType, Args));
    // debug pragma(msg, "static " ~ typeof(
    //         Args[0])[].stringof ~
    //         " CHOICES_" ~ field.stringof ~
    //         "_ = " ~ [Args].stringof ~ ";");
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
    alias ___FType___CMDLINE = typeof(field);
    static assert(is(typeof(Args[0]) == typeof(Args[1])) && is(typeof(Args[0])));
    // debug pragma(msg, "enum RANGE_" ~ field.stringof ~ "_MIN_ = " ~ Args[0].stringof ~ ";");
    // debug pragma(msg, "enum RANGE_" ~ field.stringof ~ "_MAX_ = " ~ Args[1].stringof ~ ";");
    mixin("enum RANGE_" ~ field.stringof ~ "_MIN_ = " ~ Args[0].stringof ~ ";");
    mixin("enum RANGE_" ~ field.stringof ~ "_MAX_ = " ~ Args[1].stringof ~ ";");
}

/// disable the merge feature of a registered variadic option
/// Params:
///   field = the registered variadic option in the type of `OptVal`
mixin template DISABLE_MERGE(alias field) {
    alias ___FType___CMDLINE = typeof(field);
    static assert(___FType___CMDLINE.VARIADIC);
    // debug pragma(msg, "enum DISABLE_MERGE_" ~ field.stringof ~ "_ = " ~ "true;");
    mixin("enum DISABLE_MERGE_" ~ field.stringof ~ "_ = " ~ "true;");
}

/// hide a registered option from `help` sub-command and action-option
/// Params:
///   field = the registered option in the type of `OptVal`
mixin template HIDE(alias field) {
    static assert(__CMDLINE_EXT_isInnerOptValField__!(typeof(field)));
    // debug pragma(msg, "enum HIDE_" ~ field.stringof ~ "_ = " ~ "true;");
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
    // debug pragma(msg, "enum NEGATE_" ~ field.stringof ~ "_ = \"" ~ shortFlag ~ "\";");
    mixin("enum NEGATE_" ~ field.stringof ~ "_ = \"" ~ shortFlag ~ "\";");
    static if (desc.length) {
        mixin("enum NEGATE_" ~ field.stringof ~ "_DESC_ =\"" ~ desc ~ "\";");
    }
}

/// set the conflicts options of an option
/// Params:
///   field = the target option in the type of `OptVal`
///   OtherFields = the conflicts options
mixin template CONFLICTS(alias field, OtherFields...) {
    static assert(__CMDLINE_EXT_isInnerOptValField__!(typeof(field)));
    static foreach (f; OtherFields) {
        static assert(__CMDLINE_EXT_isInnerOptValField__!(typeof(f))
                && field.stringof != f.stringof);
    }
    // alias CONFLICTS_field_ = OtherFields;
    mixin("alias CONFLICTS_" ~ field.stringof ~ "_ = OtherFields;");
}

mixin template S_CONFLICTS(alias field, OtherFields...) {
    static assert(__CMDLINE_EXT_isInnerOptValField__!(typeof(field)));
    mixin("alias CONFLICTS_" ~ field.stringof ~ "_ = OtherFields;");
}

/// set the needs options of an option
/// Params:
///   field = the target option in the type of `OptVal`
///   OtherFields = the needed options
mixin template NEEDS(alias field, OtherFields...) {
    static assert(__CMDLINE_EXT_isInnerOptValField__!(typeof(field)));
    static foreach (f; OtherFields) {
        static assert(__CMDLINE_EXT_isInnerOptValField__!(typeof(f))
                && field.stringof != f.stringof);
    }
    // alias NEEDS_field_ = OtherFields;
    mixin("alias NEEDS_" ~ field.stringof ~ "_ = OtherFields;");
}

mixin template S_NEEDS(alias field, OtherFields...) {
    static assert(__CMDLINE_EXT_isInnerOptValField__!(typeof(field)));
    mixin("alias NEEDS_" ~ field.stringof ~ "_ = OtherFields;");
}

/// set the needs one of options of an option
/// Params:
///   field = the target option in the type of `OptVal`
///   OtherFields = the needed one of options
mixin template NEED_ONEOF(alias field, OtherFields...) {
    static assert(__CMDLINE_EXT_isInnerOptValField__!(typeof(field)));
    static foreach (f; OtherFields) {
        static assert(__CMDLINE_EXT_isInnerOptValField__!(typeof(f))
                && field.stringof != f.stringof);
    }
    // alias NEED_ONEOF_field_ = OtherFields;
    mixin("alias NEED_ONEOF_" ~ field.stringof ~ "_ = OtherFields;");
}

mixin template S_NEED_ONEOF(alias field, OtherFields...) {
    static assert(__CMDLINE_EXT_isInnerOptValField__!(typeof(field)));
    mixin("alias NEED_ONEOF_" ~ field.stringof ~ "_ = OtherFields;");
}

/// set the needs any of options of an option
/// Params:
///   field = the target option in the type of `OptVal`
///   OtherFields = the needed any of options
mixin template NEED_ANYOF(alias field, OtherFields...) {
    static assert(__CMDLINE_EXT_isInnerOptValField__!(typeof(field)));
    static foreach (f; OtherFields) {
        static assert(__CMDLINE_EXT_isInnerOptValField__!(typeof(f))
                && field.stringof != f.stringof);
    }
    // alias NEED_ANYOF_field_ = OtherFields;
    mixin("alias NEED_ANYOF_" ~ field.stringof ~ "_ = OtherFields;");
}

mixin template S_NEED_ANYOF(alias field, OtherFields...) {
    static assert(__CMDLINE_EXT_isInnerOptValField__!(typeof(field)));
    mixin("alias NEED_ANYOF_" ~ field.stringof ~ "_ = OtherFields;");
}

/// set the parser of option
/// Params:
///   field = the target option in the type of `OptVal`
///   fn = the parser function
mixin template PARSER(alias field, alias fn) {
    static assert(__CMDLINE_EXT_isInnerOptValField__!(typeof(field)));
    // alias PARSER_field_ = fn;
    mixin("alias PARSER_" ~ field.stringof ~ "_ = fn;");
}

/// set the processor of option
/// Params:
///   field = the target option in the type of `OptVal`
///   fn = the processor function
mixin template PROCESSOR(alias field, alias fn) {
    static assert(__CMDLINE_EXT_isInnerOptValField__!(typeof(field)));
    // alias PROCESSOR_field_ = fn;
    mixin("alias PROCESSOR_" ~ field.stringof ~ "_ = fn;");
}

/// set the reducer of option
/// Params:
///   field = the target option in the type of `OptVal`
///   fn = the reducer function
mixin template REDUCER(alias field, alias fn) {
    static assert(__CMDLINE_EXT_isInnerOptValField__!(typeof(field)));
    // alias REDUCER_field_ = fn;
    mixin("alias REDUCER_" ~ field.stringof ~ "_ = fn;");
}

/// set the option as action option
/// Params:
///   field = the target option in the type of `OptVal`
///   fn = the action fn/delegate in the type of `void(T[] vals...)`
///   endMode = set whether in endMode
mixin template ACTION(alias field, alias fn, bool endMode = true) {
    static assert(__CMDLINE_EXT_isInnerOptValField__!(typeof(field)));
    // enum N_ACTION_field_ = endMode;
    mixin("enum N_ACTION_" ~ field.stringof ~ "_ = endMode;");
    // alias F_ACTION_field_ = fn;
    mixin("alias F_ACTION_" ~ field.stringof ~ "_ = ACTFN!fn;");
}

/// set the version string and enable the `version` sub-command and action-option
/// Params:
///   ver = the version string
///   flags = the flag of the version action-option which name would be the name of
///     the relevant sub-command. if not defied then the flag would be `--version -V`
mixin template VERSION(string ver, string flags = "") {
    // debug pragma(msg, "enum VERSION_ = \"" ~ ver ~ "\";");
    mixin("enum VERSION_ = \"" ~ ver ~ "\";");
    // debug pragma(msg, "enum VERSION_FLAGS_ = \"" ~ flags ~ "\";");
    mixin("enum VERSION_FLAGS_ = \"" ~ flags ~ "\";");
}

/// set an alias
/// Params:
///   name = the alias
mixin template ALIAS(string name) {
    // debug pragma(msg, "enum ALIAS_ = \"" ~ name ~ "\";");
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

/// allow the command to pass through its all option flags behind sub command
mixin template PASS_THROUGH() {
    enum bool PASS_THROUGH_ = true;
}

/// add custom help text before command help text
mixin template HELP_TEXT_BEFORE(string text) {
    enum HELP_TEXT_BEFORE_ = text;
}

/// add custom help text after command help text
mixin template HELP_TEXT_AFTER(string text) {
    enum HELP_TEXT_AFTER_ = text;
}

/// sort sub commands when invoke help
mixin template SORT_SUB_CMDS() {
    enum SORT_SUB_CMDS_ = true;
}

/// sort options when invoke help
mixin template SORT_OPTS() {
    enum SORT_OPTS_ = true;
}

/// show the global options when invoke help
mixin template SHOW_GLOBAL_OPTS() {
    enum SHOW_GLOBAL_OPTS_ = true;
}

/// register the external command line program as sub command
/// Params:
///   name = set the name of sub command
///   desc = set the description
///   bin = the binary file name of external command line program
///   dir = the search directory where the binary file locates,
///         if dir = `""` then search according to system,
///         if dir start with `"./"` or `"../"` then search according to relative path of this program,
///         else search according to absolute path
///   aliasName = set the alias name
mixin template EXT_SUB_CMD(string name, string desc = "", string bin = name, string dir = "./", string aliasName = "") {
    static assert(name.length && bin.length);

    // enum EXT_SUB_CMD_name_ = desc;
    mixin("enum EXT_SUB_CMD_" ~ name ~ "_N_ = \"" ~ desc ~ "\";");
    // enum EXT_SUB_CMD_name_bin_ = true;
    mixin("enum EXT_SUB_CMD_" ~ name ~ "_" ~ bin ~ "_B_ = 1;");
    // enum EXT_SUB_CMD_name_DIR_ = dir;
    mixin("enum EXT_SUB_CMD_" ~ name ~ "_DIR_ = \"" ~ dir ~ "\";");
    // enum EXT_SUB_CMD_name_aliasName_ = true;
    mixin("enum EXT_SUB_CMD_" ~ name ~ "_" ~ aliasName ~ "_A_ = 1;");
}

/// apply `Command.exportAs` to the command line container
///Params: 
///     field = the field with the type of `OptVal`
///     Flags = the new flags
mixin template EXPORT(alias field, Flags...) {
    import std.meta;
    import std.traits;

    static assert(__CMDLINE_EXT_isInnerOptValField__!(typeof(field)));
    enum bool ___is_str___CMDLINE__(alias arg) = isSomeString!(typeof(arg));
    static assert(allSatisfy!(___is_str___CMDLINE__, Flags));
    mixin("static string[] EXPORT_" ~ field.stringof ~ "_ = " ~ [Flags].stringof ~ ";");
}

/// apply `Command.exportNAs` to the command line container
/// Params:
///     field = the field with the type of `OptVal`, the field must be set with negate option
///     Flags = the new flags
mixin template EXPORT_N(alias field, Flags...) {
    import std.meta;
    import std.traits;

    static assert(__CMDLINE_EXT_isInnerOptValField__!(typeof(field)));
    enum bool ___is_str___CMDLINE__(alias arg) = isSomeString!(typeof(arg));
    static assert(allSatisfy!(___is_str___CMDLINE__, Flags));
    // static assert(hasMember!(__SELF__, "NEGATE_" ~ field.stringof ~ "_"));
    mixin("static string[] EXPORT_N_" ~ field.stringof ~ "_ = " ~ [Flags].stringof ~ ";");
}

/// apply `Command.importAs` to the command line container
///Params: 
///     flag = the flag of option for importing
///     Flags = the new flags
mixin template IMPORT(string flag, Flags...) {
    import std.meta;
    import std.traits;

    enum bool ___is_str___CMDLINE__(alias arg) = isSomeString!(typeof(arg));
    static assert(allSatisfy!(___is_str___CMDLINE__, Flags));
    // alias IMPORT_flag_N_ = Flags;
    mixin("alias IMPORT_" ~ flag ~ "_F_ = Flags;");
}

/// apply `Command.importNAs` to the command line container
///Params: 
///     flag = the flag ofnegate  option for importing
///     Flags = the new flags
mixin template IMPORT_N(string flag, Flags...) {
    import std.meta;
    import std.traits;

    enum bool ___is_str___CMDLINE__(alias arg) = isSomeString!(typeof(arg));
    static assert(allSatisfy!(___is_str___CMDLINE__, Flags));
    // alias IMPORT_N_flag_N_ = Flags;
    mixin("alias IMPORT_" ~ flag ~ "_N_ = Flags;");
}

/// enable gaining value from config file in json and set an option that specifies
/// the directories where the config file should be
/// Params:
///   flags = the flag of the config option which is used for specifying the directories
///     where the config file should be. if not defied then the flag would be
///     `-C, --config <config-dirs...>`
mixin template CONFIG(string flags = "") {
    // debug pragma(msg, "enum CONFIG_FLAGS_ = \"" ~ flags ~ "\";");
    mixin("enum CONFIG_FLAGS_ = \"" ~ flags ~ "\";");
}

/// set the options acting as arguments on command line
/// Params:
///   Args = the options in the type of `OptVal`
mixin template OPT_TO_ARG(Args...) {
    static assert(Args.length);
    enum ___to_string___CMDLINE(alias var) = var.stringof;
    import std.meta;

    // debug pragma(msg, "static " ~ string[Args.length].stringof ~
    //         " OPT_TO_ARG_ = " ~ [staticMap!(___to_string___CMDLINE, Args)].stringof ~ ";");
    mixin("static " ~ string[Args.length].stringof ~
            " OPT_TO_ARG_ = " ~ [staticMap!(___to_string___CMDLINE, Args)].stringof ~ ";");
}

/// set the default sub-command which would act like the main-command except
/// `help`, `version` and `config` options and sub-command if exists.
/// Params:
///   SubCmd = the type that statisfies `isOutResult` and be registered by `SUB_CMD` 
mixin template DEFAULT(SubCmd) {
    static assert(isOutputResult!SubCmd);
    static if (__CMDLINE_EXT_IndexOfCmdlineAttr__!SubCmd != -1)
        enum DEFAULT_ = SubCmd.stringof;
    else
        enum DEFAULT_ = (SubCmd.stringof)[0 .. $ - 6];
}

/// set the default sub-command which would act like the main-command except
/// Params:
///   subCmdName = the sub command name
mixin template DEFAULT(string subCmdName) {
    enum DEFAULT_ = subCmdName;
}

/// set sub commands
/// Params:
///   SubCmds = the sub command containers that satisfies with `isOutputResult`
mixin template SUB_CMD(SubCmds...) {
    import std.meta;
    import std.string;

    static assert(SubCmds.length && allSatisfy!(isOutputResult, SubCmds));
    static foreach (sub; SubCmds) {
        static if (__CMDLINE_EXT_IndexOfCmdlineAttr__!sub != -1) {
            mixin(sub.stringof ~ "* " ~ sub.stringof.toLower ~ "Sub;");
        }
        else {
            mixin(sub.stringof ~ "* " ~ (sub.stringof[0 .. $ - 6]).toLower ~ "Sub;");
        }
    }
}

/// see `Command.conflictOptions`
/// Params:
///   Args = the options in the type of `OptVal`
mixin template CONFLICT_OPTS(size_t id, Args...) {
    static foreach (f; Args)
        static assert(__CMDLINE_EXT_isInnerOptValField__!(typeof(f)));
    // alias CONFLICT_OPTS_ = Args;
    mixin("alias CONFLICT_OPTS_" ~ id.stringof ~ "_ = Args;");
}

/// see `Command.needAnyOfOptions`
/// Params:
///   Args = the options in the type of `OptVal
mixin template NEED_ANYOF_OPTS(size_t id, Args...) {
    static foreach (f; Args)
        static assert(__CMDLINE_EXT_isInnerOptValField__!(typeof(f)));
    // alias NEED_ANYOF_OPTS_ = Args;
    mixin("alias NEED_ANYOF_OPTS_" ~ id.stringof ~ "_ = Args;");
}

/// see `Command.needOneOfOptions`
/// Params:
///   Args = the options in the type of `OptVal
mixin template NEED_ONEOF_OPTS(size_t id, Args...) {
    static foreach (f; Args)
        static assert(__CMDLINE_EXT_isInnerOptValField__!(typeof(f)));
    // alias NEED_ONEOF_OPTS_ = Args;
    mixin("alias NEED_ONEOF_OPTS_" ~ id.stringof ~ "_ = Args;");
}

/// see `Command.groupOptions`
/// Params:
///   Args = the options in the type of `OptVal
mixin template GROUP_OPTS(size_t id, Args...) {
    static foreach (f; Args)
        static assert(__CMDLINE_EXT_isInnerOptValField__!(typeof(f)));
    // alias GROUP_OPTS_ = Args;
    mixin("alias GROUP_OPTS_" ~ id.stringof ~ "_ = Args;");
}

/// prepare for the future use of function `ready` and `getParent`, which must be embedded at the top
/// of struct domain with `END` mixin-marco at the end of this struct domain.
mixin template BEGIN() {
    enum bool __SPE_BEGIN_SEPCIAL__ = true;
    alias __SELF__ = __traits(parent, __SPE_BEGIN_SEPCIAL__);
    static void* __PARENT__;
    static string __PARENT_STRING_OF__;
    static bool __IS_SUB_CMD_CALLED__ = false;
    static Command __INNER_CMD__ = null;
}

/// prepare for the future use of function `ready` and `getParent`, which must be embedded at the end
/// of struct domain with `BEGIN` mixin-marco at the begin of this struct domain.
mixin template END() {
    import std.traits;
    import std.meta;

    enum bool __SPE_END_SEPCIAL__ = true;
    static foreach (index, Type; Filter!(__CMDLINE_EXT_isInnerSubField__, FieldTypeTuple!__SELF__)) {
        mixin("static bool IF_" ~ PointerTarget!Type.stringof ~ "_ = false;");
    }

    static T* __GET_PARENT__(T)() {
        if (this.__PARENT__ is null)
            return null;
        if (this.__PARENT_STRING_OF__ != T.stringof)
            return null;
        return cast(T*) this.__PARENT__;
    }

    // init opt_to_arg, export, export_n from mxin DEF
    enum __IS_FIELD_A_NAME__(string name) = name.length > 18
        && name[0 .. 18] == "__CMDLINE_FIELD_A_";
    enum __IS_FIELD_E_NAME__(string name) = name.length > 18
        && name[0 .. 18] == "__CMDLINE_FIELD_E_";
    enum __IS_FIELD_N_NAME__(string name) = name.length > 18
        && name[0 .. 18] == "__CMDLINE_FIELD_N_";

    struct __OPT_HELPER_CONTAINER__(Args...) {
        alias args = Args;
    }

    enum __GET_FIELD_NAME__(string name) = name[18 .. $];
    alias __GET_FIELD_FLAGS__(string name) = __OPT_HELPER_CONTAINER__!(
        __traits(getMember, __SELF__, name));

    alias __OPT_A_NAMES__ = staticMap!(__GET_FIELD_NAME__, Filter!(__IS_FIELD_A_NAME__, __traits(allMembers, __SELF__)));
    alias __OPT_E_NAMES__ = staticMap!(__GET_FIELD_NAME__, Filter!(__IS_FIELD_E_NAME__, __traits(allMembers, __SELF__)));
    alias __OPT_N_NAMES__ = staticMap!(__GET_FIELD_NAME__, Filter!(__IS_FIELD_N_NAME__, __traits(allMembers, __SELF__)));

    static if (__OPT_A_NAMES__.length) {
        mixin("static " ~ string[__OPT_A_NAMES__.length].stringof ~
                " OPT_TO_ARG_ = " ~ [__OPT_A_NAMES__].stringof ~ ";");
    }

    static if (__OPT_E_NAMES__.length) {
        alias __OPT_E_FLAGS__ = staticMap!(__GET_FIELD_FLAGS__, Filter!(__IS_FIELD_E_NAME__, __traits(allMembers, __SELF__)));
        // debug pragma(msg, __OPT_E_FLAGS__);
        static foreach (idx, nm; __OPT_E_NAMES__) {
            mixin("static string[] EXPORT_" ~ nm ~ "_ = " ~ [
                __OPT_E_FLAGS__[idx].args
            ].stringof ~ ";");
        }
    }

    static if (__OPT_N_NAMES__.length) {
        alias __OPT_N_FLAGS__ = staticMap!(__GET_FIELD_FLAGS__, Filter!(__IS_FIELD_N_NAME__, __traits(allMembers, __SELF__)));
        // debug pragma(msg, __OPT_N_FLAGS__);
        static foreach (idx, nm; __OPT_N_NAMES__) {
            mixin(
                "static string[] EXPORT_N_" ~ nm ~ "_ = " ~ [
                __OPT_N_FLAGS__[idx].args
            ].stringof ~ ";");
        }
    }
}

/// get the pointer to result container of parent.
/// Params:
///   subOutput = the sub result container
/// Returns: `null` if type of `subOutput` not embeds `BEGIN` and `END` or `T` is not correct
T* getParent(T, U)(in U subOutput) if (isOutputResult!U && isOutputResult!T) {
    static if (hasMember!(U, "__SPE_BEGIN_SEPCIAL__") && hasMember!(U, "__SPE_END_SEPCIAL__")) {
        return subOutput.__GET_PARENT__!T;
    }
    else {
        return null;
    }
}

/// get the pointer to result container of parent.
/// Params:
///   subOutput = the pointer to the sub result container
/// Returns: `null` if type of `subOutput` not embeds `BEGIN` and `END` or `T` is not correct
T* getParent(T, U)(const(U)* subOutput) if (isOutputResult!U && isOutputResult!T) {
    static if (hasMember!(U, "__SPE_BEGIN_SEPCIAL__") && hasMember!(U, "__SPE_END_SEPCIAL__")) {
        return subOutput.__GET_PARENT__!T;
    }
    else {
        return null;
    }
}

/// get the inner Command object of result container
/// Params:
///   output = the result container
/// Returns: the const Command
const(Command) getInnerCmd(T)(in T output) if (isOutputResult!T) {
    static if (hasMember!(T, "__SPE_BEGIN_SEPCIAL__")) {
        return output.__INNER_CMD__;
    }
}

/// detect whether a sub command's container of a main command is ready for use.
/// for using this function, the `BEGIN` and `END` mixin-macro must be embeed in
/// main command container.
/// `T` is the type in sub-command container, `U` is the type in main-command container
/// Params:
///   output = the main-command container
/// Returns: `true` if the sub-command is ready, otherwise is not ready.
bool ready(T, U)(const U* output)
        if (isOutputResult!T && isOutputResult!U && hasMember!(U, "__SPE_END_SEPCIAL__")) {
    return mixin(output.stringof ~ '.' ~ "IF_" ~ T.stringof ~ '_');
}

/// get a pointer to sub-command container.
/// `T` is the type in sub-command container, `U` is the type in main-command container
/// Params:
///   output = the main-command container
/// Returns: a pointer to sub-command container if the sub-command is ready,
///     otherwise `null` 
inout(T)* subResult(T, U)(inout(U)* output)
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
        return _inner !is null && _inner.settled;
    }

    /// test whether the inner value is bool, better to use it after calling isValid to determine it is valid 
    /// Returns: `true` if it is bool, otherwise not bool
    bool isBool() const {
        assert(isValid);
        return !_inner.isValueData;
    }

    // make `OptVal` enable to implicitly convert to bool value
    // same as the result of `isValid`
    alias isValid this;

    /// get the value of type `U`, default `U` == `T`
    /// `U` must be `T` or the Element Type of `T` if `T` is Array Type
    /// if `U` is `bool`, this function return true when inner option value is valid and the `bool` value of
    /// option is `true`, otherwise `false`
    U get(U = T)() const
    if (is(U == T) || (!is(U == void) && is(U == ElementType!T))) {
        static if (is(U == bool))
            return cast(U)(isValid && _inner.get!U);
        else {
            assert(isValid);
            return _inner.get!U;
        }
    }

    /// get the value of type `bool`
    bool getBool()()
            if (is(T == bool) || (hasMember!(typeof(this), "OPTIONAL") && OPTIONAL)) {
        assert(isValid && isBool);
        return _inner.get!bool;
    }

    /// assign the inner value through passing into `Option` variable
    auto opAssign(Option value) {
        this._inner = value;
        return this;
    }
}

/// use for defining a command line argument
/// Params:
///   name = the argument's name
///   T = the type of argument
///   Args = the configs
mixin template DEF_ARG(string name, T, Args...) {
    mixin DEF!(name, T, Args);
}

/// use for defining a bool argument
/// Params:
///   name = the argument's name
///   Args = the configs
mixin template DEF_BOOL_ARG(string name, Args...) {
    mixin DEF_ARG!(name, bool, Args);
}

/// use for defining a variadic argument
/// Params:
///   name = the argument's name
///   T = the element type of argument
///   Args = the configs
mixin template DEF_VAR_ARG(string name, T, Args...) {
    mixin DEF_ARG!(name, T[], Args);
}

/// use for defining a command line option
/// Params:
///   name = the name of option
///   T = the type of option
///   flag = the flag of option wihout long-flag
///   Args = the configs
mixin template DEF_OPT(string name, T, string flag, Args...) {
    mixin DEF!(name, T, Flag_d!flag, Args);
}

/// use for defining a bool option
/// Params:
///   name = the name of option
///   flag = the short flag
///   Args = the configs
mixin template DEF_BOOL_OPT(string name, string flag, Args...) {
    mixin DEF_OPT!(name, bool, flag, Args);
}

/// use for defining a variadic option
/// Params:
///   name = the name of option
///   T = the element type of option
///   flag = the flag of option wihout long-flag
///   Args = the configs
mixin template DEF_VAR_OPT(string name, T, string flag, Args...) {
    mixin DEF_OPT!(name, T[], flag, Args);
}

/// the basic version of both `DEF_ARG` and `DEF_OPT`
/// Params:
///   name = the name of argument or option
///   T = the type of argument or option
///   Args = the configs
mixin template DEF(string name, T, Args...) {
    import std.meta;
    import std.string : join;

    static assert(allSatisfy!(__CMDLINE_isFieldDef__, Args));

    static if (!is(__CMDLINE_getFiledById__!(-2, Args) == void)) {
        mixin("enum " ~ "__CMDLINE_FIELD_isOptional_" ~ name ~ " = " ~ true.stringof ~ ";");
    }
    else {
        mixin("enum " ~ "__CMDLINE_FIELD_isOptional_" ~ name ~ " = " ~ false.stringof ~ ";");
    }

    static if (!is(__CMDLINE_getFiledById__!(-1, Args) == void)) {
        mixin("OptVal!(" ~ T.stringof ~ ", \"" ~ __CMDLINE_getFiledById__!(-1, Args).args ~ "\", "
                ~ "__CMDLINE_FIELD_isOptional_" ~ name ~ ")" ~ name ~ ";");
        // debug pragma(msg, "OptVal!(" ~ T.stringof ~ ", \"" ~ __CMDLINE_getFiledById__!(-1, Args).args ~ "\", "
        //         ~ "__CMDLINE_FIELD_isOptional_" ~ name ~ ")" ~ name ~ ";");
    }
    else {
        mixin("ArgVal!(" ~ T.stringof ~ ", " ~ "__CMDLINE_FIELD_isOptional_" ~ name ~ ")" ~ name ~ ";");
        // debug pragma(msg, "ArgVal!(" ~ T.stringof ~ ", " ~ "__CMDLINE_FIELD_isOptional_" ~ name ~ ")" ~ name ~ ";");
    }

    mixin("alias " ~ "__CMDLINE_FIELD_F_" ~ name ~ "= " ~ name ~ ";");

    static foreach (decl; Args) {
        static if (decl.__CMDLINE_FIELD_DEF__ == 0) {
            mixin DESC!(
                mixin("__CMDLINE_FIELD_F_" ~ name),
                decl.args
            );
        }
        else static if (decl.__CMDLINE_FIELD_DEF__ == 1) {
            mixin RANGE!(
                mixin("__CMDLINE_FIELD_F_" ~ name),
                decl.args
            );
        }
        else static if (decl.__CMDLINE_FIELD_DEF__ == 2) {
            mixin CHOICES!(
                mixin("__CMDLINE_FIELD_F_" ~ name),
                decl.args
            );
        }
        else static if (decl.__CMDLINE_FIELD_DEF__ == 3) {
            mixin DEFAULT!(
                mixin("__CMDLINE_FIELD_F_" ~ name),
                decl.args
            );
        }
        else static if (decl.__CMDLINE_FIELD_DEF__ == 4) {
            mixin PRESET!(
                mixin("__CMDLINE_FIELD_F_" ~ name),
                decl.args
            );
        }
        else static if (decl.__CMDLINE_FIELD_DEF__ == 5) {
            mixin ENV!(
                mixin("__CMDLINE_FIELD_F_" ~ name),
                decl.args
            );
        }
        else static if (decl.__CMDLINE_FIELD_DEF__ == 6) {
            mixin NEGATE!(
                mixin("__CMDLINE_FIELD_F_" ~ name),
                decl.args
            );
        }
        else static if (decl.__CMDLINE_FIELD_DEF__ == 7) {
            mixin HIDE!(mixin("__CMDLINE_FIELD_F_" ~ name));
        }
        else static if (decl.__CMDLINE_FIELD_DEF__ == 8) {
            mixin DISABLE_MERGE!(mixin("__CMDLINE_FIELD_F_" ~ name));
        }
        else static if (decl.__CMDLINE_FIELD_DEF__ == 9) {
            mixin("enum " ~ "__CMDLINE_FIELD_A_" ~ name ~ " = 1;");
        }
        else static if (decl.__CMDLINE_FIELD_DEF__ == 10) {
            mixin("alias " ~ "__CMDLINE_FIELD_E_" ~ name ~ " = decl.args;");
        }
        else static if (decl.__CMDLINE_FIELD_DEF__ == 11) {
            mixin("alias " ~ "__CMDLINE_FIELD_N_" ~ name ~ " = decl.args;");
        }
        else static if (decl.__CMDLINE_FIELD_DEF__ == 12) {
            mixin S_IMPLIES_TRUE!(
                mixin("__CMDLINE_FIELD_F_" ~ name),
                decl.args
            );
        }
        else static if (decl.__CMDLINE_FIELD_DEF__ == 13) {
            static if (is(decl.args[1] == struct) && hasMember!(decl.args[1], "__VAR_WRAP__")) {
                mixin S_IMPLIES!(
                    mixin("__CMDLINE_FIELD_F_" ~ name),
                    decl.args[0],
                    true,
                    decl.args[1].args
                );
            }
            else {
                mixin S_IMPLIES!(
                    mixin("__CMDLINE_FIELD_F_" ~ name),
                    decl.args[0],
                    false,
                    decl.args[1]
                );
            }
        }
        else static if (decl.__CMDLINE_FIELD_DEF__ == 14) {
            mixin S_CONFLICTS!(
                mixin("__CMDLINE_FIELD_F_" ~ name),
                decl.args
            );
        }
        else static if (decl.__CMDLINE_FIELD_DEF__ == 15) {
            mixin PARSER!(
                mixin("__CMDLINE_FIELD_F_" ~ name),
                decl.args
            );
        }
        else static if (decl.__CMDLINE_FIELD_DEF__ == 16) {
            mixin PROCESSOR!(
                mixin("__CMDLINE_FIELD_F_" ~ name),
                decl.args
            );
        }
        else static if (decl.__CMDLINE_FIELD_DEF__ == 17) {
            mixin REDUCER!(
                mixin("__CMDLINE_FIELD_F_" ~ name),
                decl.args
            );
        }
        else static if (decl.__CMDLINE_FIELD_DEF__ == 18) {
            mixin ACTION!(
                mixin("__CMDLINE_FIELD_F_" ~ name),
                decl.args
            );
        }
        else static if (decl.__CMDLINE_FIELD_DEF__ == 19) {
            mixin S_NEEDS!(
                mixin("__CMDLINE_FIELD_F_" ~ name),
                decl.args
            );
        }
        else static if (decl.__CMDLINE_FIELD_DEF__ == 20) {
            mixin S_NEED_ONEOF!(
                mixin("__CMDLINE_FIELD_F_" ~ name),
                decl.args
            );
        }
        else static if (decl.__CMDLINE_FIELD_DEF__ == 21) {
            mixin S_NEED_ANYOF!(
                mixin("__CMDLINE_FIELD_F_" ~ name),
                decl.args
            );
        }
    }
}

/// used inside the bracket of `DEF` or `DEF_ARG` to set the argument optional
struct Optional_d {
    enum __CMDLINE_FIELD_DEF__ = -2;
}

// used inside the bracket of `DEF` or `DEF_OPT` to set the option mandatory
alias Mandatory_d = Optional_d;

/// used inside the bracket of `DEF` to set the flag of an option
struct Flag_d(alias flag) {
    enum __CMDLINE_FIELD_DEF__ = -1;
    alias args = flag;
}

/// used inside the bracket of `DEF`, `DEF_ARG` and `DEF_OPT` to set the desc of an option or an argument
struct Desc_d(alias desc) {
    enum __CMDLINE_FIELD_DEF__ = 0;
    alias args = desc;
}

/// used inside the bracket of `DEF`, `DEF_ARG` and `DEF_OPT` to set the range of an option or an argument
struct Range_d(Args...) {
    enum __CMDLINE_FIELD_DEF__ = 1;
    alias args = Args;
}

/// used inside the bracket of `DEF`, `DEF_ARG` and `DEF_OPT` to set the choices of an option or an argument
struct Choices_d(Args...) {
    enum __CMDLINE_FIELD_DEF__ = 2;
    alias args = Args;
}

/// used inside the bracket of `DEF`, `DEF_ARG` and `DEF_OPT` to set the default value of an option or an argument
struct Default_d(alias val) {
    enum __CMDLINE_FIELD_DEF__ = 3;
    alias args = val;
}

/// used inside the bracket of `DEF`, `DEF_OPT` to set the preset value of an option
struct Preset_d(alias val) {
    enum __CMDLINE_FIELD_DEF__ = 4;
    alias args = val;
}

/// used inside the bracket of `DEF`, `DEF_OPT` to set the value from environment of an option
struct Env_d(alias envKey) {
    enum __CMDLINE_FIELD_DEF__ = 5;
    alias args = envKey;
}

/// used inside the bracket of `DEF`, `DEF_OPT` to set the negate option of an option
struct Negate_d(alias shortFlag = "", alias desc = "") {
    enum __CMDLINE_FIELD_DEF__ = 6;
    alias args = AliasSeq!(shortFlag, desc);
}

/// used inside the bracket of `DEF`, `DEF_OPT` to hide an option from help info
struct Hide_d {
    enum __CMDLINE_FIELD_DEF__ = 7;
}

/// used inside the bracket of `DEF`, `DEF_OPT` to disable the merge feature of variadic option
struct DisableMerge_d {
    enum __CMDLINE_FIELD_DEF__ = 8;
}

/// used inside the bracket of `DEF`, `DEF_OPT` to make an option act like an argument
struct ToArg_d {
    enum __CMDLINE_FIELD_DEF__ = 9;
}

/// used inside the bracket of `DEF`, `DEF_OPT`, see `EXPORT`
struct ExportAs_d(Args...) {
    static assert(Args.length);
    enum __CMDLINE_FIELD_DEF__ = 10;
    alias args = Args;
}

/// used inside the bracket of `DEF`, `DEF_OPT`, see `EXPORT`
struct Export_d {
    enum __CMDLINE_FIELD_DEF__ = 10;
    alias args = AliasSeq!();
}

/// used inside the bracket of `DEF`, `DEF_OPT`, see `EXPORT_N`
struct N_ExportAs_d(Args...) {
    static assert(Args.length);
    enum __CMDLINE_FIELD_DEF__ = 11;
    alias args = Args;
}

/// used inside the bracket of `DEF`, `DEF_OPT`, see `EXPORT_N`
struct N_Export_d {
    enum __CMDLINE_FIELD_DEF__ = 11;
    alias args = AliasSeq!();
}

/// used inside the bracket of `DEF`, `DEF_OPT`, see `IMPLIES_TRUE`
struct ImpliesTrue_d(Args...) {
    enum __CMDLINE_FIELD_DEF__ = 12;
    alias args = Args;
}

/// only used for wrap the values for impling values to variadic option in `Implies_d`
struct VarWrap(Args...) {
    enum __VAR_WRAP__ = 1;
    alias args = Args;
}

/// used inside the bracket of `DEF`, `DEF_OPT`, see `IMPLIES`. 
/// if `value` is `VarWrap`, it will imply values to variadic option
struct Implies_d(alias target, alias value) {
    enum __CMDLINE_FIELD_DEF__ = 13;
    alias args = AliasSeq!(target, value);
}

/// used inside the bracket of `DEF`, `DEF_OPT`, see `CONFLICTS`
struct Conflicts_d(Args...) {
    enum __CMDLINE_FIELD_DEF__ = 14;
    alias args = Args;
}

/// used inside the bracket of `DEF`, `DEF_OPT`, see `PARSER`
struct Parser_d(alias fn) {
    enum __CMDLINE_FIELD_DEF__ = 15;
    alias args = fn;
}

/// used inside the bracket of `DEF`, `DEF_OPT`, see `PROCESSOR`
struct Processor_d(alias fn) {
    enum __CMDLINE_FIELD_DEF__ = 16;
    alias args = fn;
}

/// used inside the bracket of `DEF`, `DEF_OPT`, see `REDUCER`
struct Reducer_d(alias fn) {
    enum __CMDLINE_FIELD_DEF__ = 17;
    alias args = fn;
}

/// used inside the bracket of `DEF`, `DEF_OPT`, see `ACTION`
struct Action_d(alias actionFn, bool endMode = true) {
    enum __CMDLINE_FIELD_DEF__ = 18;
    alias args = AliasSeq!(actionFn, endMode);
}

/// used inside the bracket of `DEF`, `DEF_OPT`, see `NEEDS`
struct Needs_d(Args...) {
    enum __CMDLINE_FIELD_DEF__ = 19;
    alias args = Args;
}

/// used inside the bracket of `DEF`, `DEF_OPT`, see `NEED_ONEOF`
struct NeedOneOf_d(Args...) {
    enum __CMDLINE_FIELD_DEF__ = 20;
    alias args = Args;
}

/// used inside the bracket of `DEF`, `DEF_OPT`, see `NEED_ANYOF`
struct NeedAnyOf_d(Args...) {
    enum __CMDLINE_FIELD_DEF__ = 21;
    alias args = Args;
}

enum __CMDLINE_isFieldDef__(T) = hasMember!(T, "__CMDLINE_FIELD_DEF__");
template __CMDLINE_getFiledById__(int id, Types...) {
    enum __XX(T) = T.__CMDLINE_FIELD_DEF__ == id;
    alias tmp = Filter!(__XX, Types);
    static if (tmp.length)
        alias __CMDLINE_getFiledById__ = tmp[0];
    else
        alias __CMDLINE_getFiledById__ = void;
}

private alias getMember(alias T, string flag) = __traits(getMember, T, flag);

/// construct the command line program without action callback
/// Returns: the root command in `Command` that is confiured according to the given command conatiner type.
Command construct(T)() if (isOutputResult!T) {
    alias fnames = FieldNameTuple!T;
    alias ftypes = FieldTypeTuple!T;
    static if (__CMDLINE_EXT_IndexOfCmdlineAttr__!T != -1)
        Command cmd = createCommand(T.stringof._tokeytab);
    else
        Command cmd = createCommand(T.stringof[0 .. $ - 6]._tokeytab);
    static if (hasStaticMember!(T, "__INNER_CMD__")) {
        T.__INNER_CMD__ = cmd;
    }
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
        cmd._defaultCommandName = _tokeytab(T.DEFAULT_);
    }
    static if (hasMember!(T, "PASS_THROUGH_")) {
        cmd._passThroughOptionValue = true;
    }
    static if (hasMember!(T, "ALIAS_")) {
        cmd.aliasName(T.ALIAS_);
    }
    static if (hasMember!(T, "HELP_TEXT_BEFORE_")) {
        cmd.addHelpText(AddHelpPos.Before, T.HELP_TEXT_BEFORE_);
    }
    static if (hasMember!(T, "HELP_TEXT_AFTER_")) {
        cmd.addHelpText(AddHelpPos.After, T.HELP_TEXT_AFTER_);
    }
    static if (hasMember!(T, "SORT_SUB_CMDS_")) {
        cmd.sortSubCommands;
    }
    static if (hasMember!(T, "SORT_OPTS_")) {
        cmd.sortOptions;
    }
    static if (hasMember!(T, "SHOW_GLOBAL_OPTS_")) {
        cmd.showGlobalOptions;
    }

    static foreach (Type; Filter!(__CMDLINE_EXT_isInnerArgValField__, ftypes)) {
        {
            mixin SetArgValField!(cmd, Type, T, staticIndexOf!(Type, ftypes), fnames);
        }
    }
    static foreach (Type; Filter!(__CMDLINE_EXT_isInnerOptValField__, ftypes)) {
        {
            mixin SetOptValField!(cmd, Type, T, staticIndexOf!(Type, ftypes), fnames);
        }
    }
    static foreach (Type; Filter!(__CMDLINE_EXT_isInnerSubField__, ftypes)) {
        {
            mixin SetSubCommand!(cmd, Type);
        }
    }

    static if (hasStaticMember!(T, "OPT_TO_ARG_")) {
        auto arr = getMember!(T, "OPT_TO_ARG_");
        import std.algorithm;
        import std.array;

        auto tmp = arr[].map!(str => _tokeytab(str)).array;
        cmd.argToOpt(tmp[0], tmp[1 .. $]);
    }

    enum __IS_EXT_SUB_CMD_PREFIX__(string name) = name.length > 12
        && name[0 .. 12] == "EXT_SUB_CMD_";
    enum __GET_SLICE__(string name, size_t begin, size_t end = 3) = name[begin .. $ - end];
    alias __EXT_SUB_CMD_PREFIX_SEQ__ = Filter!(__IS_EXT_SUB_CMD_PREFIX__, __traits(allMembers, T));
    static if (__EXT_SUB_CMD_PREFIX_SEQ__.length) {
        static foreach (idx, ext; __EXT_SUB_CMD_PREFIX_SEQ__) {
            static if (idx % 4 == 0) {
                {
                    enum name = __GET_SLICE__!(ext, 12);
                    enum len = name.length + 13;
                    enum bin = __GET_SLICE__!(__EXT_SUB_CMD_PREFIX_SEQ__[idx + 1], len);
                    enum desc = getMember!(T, ext);
                    enum dir = getMember!(T, __EXT_SUB_CMD_PREFIX_SEQ__[idx + 2]);
                    enum aliasName = __GET_SLICE__!(__EXT_SUB_CMD_PREFIX_SEQ__[idx + 3], len);
                    cmd.commandX(name._tokeytab, desc, [
                        "file": bin,
                        "dir": dir
                    ]);
                    static if (aliasName.length)
                        cmd.aliasName(aliasName._tokeytab);
                }
            }
        }
    }

    import std.algorithm : map;
    import std.array : array;
    enum __to_stringof__(alias xxfxx) = xxfxx.stringof;
    static foreach (id; 0 .. 10) {
        static if (hasMember!(T, "CONFLICT_OPTS_" ~ id.stringof ~ "LU_")) {
            cmd.conflictOptions([
                staticMap!(__to_stringof__, getMember!(T, "CONFLICT_OPTS_" ~ id.stringof ~ "LU_"))
            ].map!_tokeytab.array);
        }
        static if (hasMember!(T, "NEED_ANYOF_OPTS_" ~ id.stringof ~ "LU_")) {
            cmd.needAnyOfOptions([
                staticMap!(__to_stringof__, getMember!(T, "NEED_ANYOF_OPTS_" ~ id.stringof ~ "LU_"))
            ].map!_tokeytab.array);
        }
        static if (hasMember!(T, "NEED_ONEOF_OPTS_" ~ id.stringof ~ "LU_")) {
            cmd.needOneOfOptions([
                staticMap!(__to_stringof__, getMember!(T, "NEED_ONEOF_OPTS_" ~ id.stringof ~ "LU_"))
            ].map!_tokeytab.array);
        }
        static if (hasMember!(T, "GROUP_OPTS_" ~ id.stringof ~ "LU_")) {
            cmd.groupOptions([
                staticMap!(__to_stringof__, getMember!(T, "GROUP_OPTS_" ~ id.stringof ~ "LU_"))
            ].map!_tokeytab.array);
        }
    }
    return cmd;
}

/// parse the command line option and argument parameters according to the given command conatiner type.
/// T = the command conatiner type
/// Params:
///   argv = the command line arguments in string
/// Returns: an initialized instance of the command conatiner type
T* parse(T)(in string[] argv) if (isOutputResult!T) {
    alias fnames = FieldNameTuple!T;
    alias ftypes = FieldTypeTuple!T;
    assert(argv.length);
    auto cmd = construct!T;
    cmd.parse(argv);
    T* output = new T;
    static foreach (index, name; fnames) {
        {
            mixin InitOutputResultField!(cmd, output, index, name, ftypes);
        }
    }
    return output;
}

/// parse the command line option and argument parameters  according to the given command conatiner type.
/// And invoke the `action` member function and return if exists, otherwise invoke member container's `action`
/// member function recursely.
/// T = the root command container type
/// Params:
///   argv = the arguments list in string
void run(T)(in string[] argv) if (isOutputResult!T) {
    T* output = parse!T(argv);
    runImpl(output);
}

/// the main function to parse and run the command line program
/// Params:
///   T = the main command line container
mixin template CMDLINE_MAIN(T) if (isOutputResult!T) {
    void main(in string[] argv) {
        argv.run!T;
    }
}

private:

void runImpl(T)(T* output) if (isOutputResult!T) {
    static if (hasMember!(T, "action")) {
        static if (!hasStaticMember!(T, "__IS_SUB_CMD_CALLED__")) {
            output.action();
        }
        else {
            if (!T.__IS_SUB_CMD_CALLED__) {
                output.action();
            }
            else {
                alias fnames = FieldNameTuple!T;
                static foreach (index, Type; Filter!(__CMDLINE_EXT_isInnerSubField__, FieldTypeTuple!T)) {
                    if (auto sub_output = output.subResult!(PointerTarget!Type)) {
                        runImpl(sub_output);
                    }
                }
            }
        }
    }
    else {
        alias fnames = FieldNameTuple!T;
        static foreach (index, Type; Filter!(__CMDLINE_EXT_isInnerSubField__, FieldTypeTuple!T)) {
            if (auto sub_output = output.subResult!(PointerTarget!Type)) {
                runImpl(sub_output);
            }
        }
    }
}

mixin template InitOutputResultField(alias cmd, alias output, alias index, alias name, ftypes...) {
    alias Type = ftypes[index];
    static if (__CMDLINE_EXT_isInnerArgValField__!Type) {
        auto x = mixin(output.stringof ~ '.' ~ name) = cmd.findArgument(name._tokeytab);
    }
    else static if (__CMDLINE_EXT_isInnerOptValField__!Type) {
        auto x = mixin(output.stringof ~ '.' ~ name) = cmd.findOption(name._tokeytab);
    }
    else static if (__CMDLINE_EXT_isInnerSubField__!Type) {
        alias T = PointerTarget!Type;
        alias sfnames = FieldNameTuple!T;
        alias sftypes = FieldTypeTuple!T;
        // debug pragma(msg, T.stringof, " ", typeof(output).stringof);
        static if (__CMDLINE_EXT_IndexOfCmdlineAttr__!T != -1)
            Command sub = cmd.findCommand(T.stringof._tokeytab);
        else
            Command sub = cmd.findCommand(T.stringof[0 .. $ - 6]._tokeytab);
        auto xfn = () {
            if (cmd._called_sub == sub._name) {
                static if (hasMember!(PointerTarget!(typeof(output)), "__IS_SUB_CMD_CALLED__")) {
                    output.__IS_SUB_CMD_CALLED__ = true;
                }
                static if (hasMember!(typeof(output), "__SPE_END_SEPCIAL__")) {
                    mixin(output.stringof ~ '.' ~ "IF_" ~ T.stringof ~ '_') = true;
                }
                auto sub_output = mixin(output.stringof ~ '.' ~ name) = new T;
                static if (hasMember!(T, "__SPE_BEGIN_SEPCIAL__") && hasMember!(T, "__SPE_END_SEPCIAL__")) {
                    auto x = T.__PARENT__ = output;
                    auto xx = T.__PARENT_STRING_OF__ = PointerTarget!(typeof(output)).stringof;
                }
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
    import std.meta;
    import std.array;
    import std.algorithm;
    import std.functional : toDelegate;

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
    enum string fexport = "EXPORT_" ~ opt_name ~ "_";
    enum string fexport_n = "EXPORT_N_" ~ opt_name ~ "_";
    enum string fconflicts = "CONFLICTS_" ~ opt_name ~ "_";
    enum string fneeds = "NEEDS_" ~ opt_name ~ "_";
    enum string fneed_oneof = "NEED_ONEOF_" ~ opt_name ~ "_";
    enum string fneed_anyof = "NEED_ANYOF_" ~ opt_name ~ "_";
    enum string fparser = "PARSER_" ~ opt_name ~ "_";
    enum string fprocessor = "PROCESSOR_" ~ opt_name ~ "_";
    enum string freducer = "REDUCER_" ~ opt_name ~ "_";
    enum string faction_n = "N_ACTION_" ~ opt_name ~ "_";
    enum string faction_f = "F_ACTION_" ~ opt_name ~ "_";
    auto x0 = opt.makeMandatory(mandatory);
    static if (hasMember!(T, "DISABLE_MERGE_" ~ opt_name ~ '_')) {
        auto x1 = opt.merge(false);
    }
    static if (hasMember!(T, "HIDE_" ~ opt_name ~ '_')) {
        auto x2 = opt.hidden = true;
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
        auto x3 = nopt = createNegateOption("--no-" ~ kname ~ ' ' ~ short_flag, _x_);
    }
    static if (hasMember!(T, fdesc)) {
        auto x4 = opt.description(getMember!(T, fdesc));
    }
    static if (hasStaticMember!(T, fdef)) {
        auto x5 = opt.defaultVal(getMember!(T, fdef));
    }
    static if (hasStaticMember!(T, fchoices)) {
        auto x6 = opt.choices(getMember!(T, fchoices));
    }
    static if (hasMember!(T, frange_min) && hasMember!(T, frange_max)) {
        auto x7 = opt.rangeOf(
            getMember!(T, frange_min),
            getMember!(T, frange_max)
        );
    }
    static if (hasStaticMember!(T, fpreset)) {
        auto x8 = opt.preset(getMember!(T, fpreset));
    }
    static if (hasMember!(T, fenv)) {
        auto x9 = opt.env(getMember!(T, fenv));
    }

    static if (hasMember!(T, faction_n)) {
        auto x10 = cmd.addActionOption!(ElementType!(Parameters!(getMember!(T, faction_f))[0]))(opt, toDelegate(
                getMember!(T, faction_f)), getMember!(T, faction_n));
    }
    else {
        auto x10 = cmd.addOption(opt);
    }

    auto x11 = nopt ? cmd.addOption(nopt) : cmd;
    static if (hasStaticMember!(T, fexport)) {
        auto x12 = cmd.exportAs(kname, getMember!(T, fexport));
    }
    static if (hasStaticMember!(T, fexport_n)) {
        auto x13 = cmd.exportNAs(kname, getMember!(T, fexport_n));
    }

    template __to__stringof__(alias f) {
        static if (is(typeof(f) == string)) {
            enum __to__stringof__ = f;
        }
        else
            enum __to__stringof__ = f.stringof;
    }

    static if (hasMember!(T, fconflicts)) {
        auto x14 = opt.conflicts([
            staticMap!(__to__stringof__, getMember!(T, fconflicts))
        ].map!_tokeytab.array);
    }
    static if (hasMember!(T, fneeds)) {
        auto x15 = opt.needs([
            staticMap!(__to__stringof__, getMember!(T, fneeds))
        ].map!_tokeytab.array);
    }
    static if (hasMember!(T, fneed_oneof)) {
        auto x16 = opt.needOneOf([
            staticMap!(__to__stringof__, getMember!(T, fneed_oneof))
        ].map!_tokeytab.array);
    }
    static if (hasMember!(T, fneed_anyof)) {
        auto x17 = opt.needAnyOf([
            staticMap!(__to__stringof__, getMember!(T, fneed_anyof))
        ].map!_tokeytab.array);
    }

    static if (hasMember!(T, fparser)) {
        auto x18 = opt.parser!(getMember!(T, fparser));
    }
    static if (hasMember!(T, fprocessor)) {
        auto x19 = opt.processor!(getMember!(T, fprocessor));
    }
    static if (hasMember!(T, freducer)) {
        auto x20 = opt.processReducer!(getMember!(T, freducer));
    }

    enum __IS_IMPLIES_TRUE_FIELD_NAME__(string name) = name.length > 13 + opt_name.length &&
        name[0 .. 13 + opt_name.length] == "IMPLIES_TRUE_" ~ opt_name;
    enum __IS_IMPLIES_VALUE_FIELD_NAME__(string name) = name.length > 14 + opt_name.length &&
        name[0 .. 14 + opt_name.length] == "IMPLIES_VALUE_" ~ opt_name;
    enum __GET_IMPLIES_VALUE_TARGET_NAME__(string name) = name[15 + opt_name.length .. $ - 3];
    enum __IS_IMPLIES_VALUE_VAR_(string name) = name[$ - 3 .. $] == "_R_";
    alias __IMPLIES_TRUE_FIELD_NAME_SEQ__ = Filter!(__IS_IMPLIES_TRUE_FIELD_NAME__, __traits(allMembers, T));
    alias __IMPLIES_VALUE_FIELD_NAME_SEQ__ = Filter!(__IS_IMPLIES_VALUE_FIELD_NAME__, __traits(allMembers, T));
    static if (__IMPLIES_TRUE_FIELD_NAME_SEQ__.length) {
        auto y = opt.implies([
            __traits(getMember, T, __IMPLIES_TRUE_FIELD_NAME_SEQ__[0])
        ].map!(_tokeytab).array);
    }
    static if (__IMPLIES_VALUE_FIELD_NAME_SEQ__.length) {
        static foreach (idx, field_name; __IMPLIES_VALUE_FIELD_NAME_SEQ__) {
            static if (__IS_IMPLIES_VALUE_VAR_!field_name) {
                mixin("auto y" ~ idx.stringof ~ " = opt.implies(__GET_IMPLIES_VALUE_TARGET_NAME__!(field_name)._tokeytab, [__traits(getMember, T, field_name)]);");
            }
            else {
                mixin("auto y" ~ idx.stringof ~ " = opt.implies(__GET_IMPLIES_VALUE_TARGET_NAME__!(field_name)._tokeytab, __traits(getMember, T, field_name));");
            }
        }
    }
}

mixin template SetSubCommand(alias cmd, Type) {
    alias SubT = PointerTarget!Type;
    Command sub = construct!SubT;
    auto x = cmd.addCommand(sub);
    enum __IS_IMPORT_PREFIX__(string name) = name.length > 7 && name[0 .. 7] == "IMPORT_";
    static foreach (idx, imp; Filter!(__IS_IMPORT_PREFIX__, __traits(allMembers, SubT))) {
        mixin("string name_" ~ idx.stringof ~ " = imp[7 .. $ - 3]._tokeytab;");
        static if (imp[$ - 3 .. $] == "_N_")
            mixin(
                "auto x" ~ idx.stringof ~ " = sub.importNAs(name_" ~ idx.stringof ~ ", getMember!(SubT, imp));");
        else
            mixin(
                "auto x" ~ idx.stringof ~ " = sub.importAs(name_" ~ idx.stringof ~ ", getMember!(SubT, imp));");
    }
}

string _tokeytab(string from) {
    import std.regex;
    import std.string : toLower;

    auto trans = (Captures!(string) m) { return '-' ~ toLower(m.hit); };
    return cast(char) toLower(from[0]) ~ replaceAll!(trans)(from[1 .. $], regex(`[A-Z]`));
}

/// implies `true` value for one or more option, which must be bool option
/// Params:
///   srcField = the source option in `OptVal`
///   targetFields = the target options in `OptVal`
public mixin template IMPLIES_TRUE(alias srcField, targetFields...) {
    import std.meta;

    alias __TO_IMPLIES_TARGET_TYPE__(alias target) = typeof(target);
    enum __TO_IMPLIES_TARGET_STR(alias target) = target.stringof;
    static assert(__CMDLINE_EXT_isInnerOptValField__!(typeof(srcField)));
    static assert(targetFields.length);
    static assert(allSatisfy!(__CMDLINE_EXT_isInnerOptValField__, staticMap!(
            __TO_IMPLIES_TARGET_TYPE__, targetFields)));

    // alias IMPLIES_TRUE_name_N_ = staticMap!(__TO_IMPLIES_TARGET_STR, targetFields)
    mixin("alias IMPLIES_TRUE_" ~ srcField.stringof ~ "_N_ = " ~ "staticMap!(__TO_IMPLIES_TARGET_STR, targetFields);");
}

/// similar to `IMPLIES_TRUE`, but `targetFields` in string not symbol
/// Params:
///   srcField = the source option in `OptVal`
///   targetFields = the target options in `OptVal`
public mixin template S_IMPLIES_TRUE(alias srcField, targetFields...) {
    import std.meta;

    static assert(__CMDLINE_EXT_isInnerOptValField__!(typeof(srcField)));
    static assert(targetFields.length);
    mixin("alias IMPLIES_TRUE_" ~ srcField.stringof ~ "_N_ = targetFields;");
}

/// implies value for an option, if the target option is variadic then implies in array
/// Params:
///   srcField = the source option in `OptVal`
///   targetField = the target options in `OptVal`
///   values = the values, if the target option is not bool option, values must not be in bool value
public mixin template IMPLIES(alias srcField, alias targetField, values...)
        if (__CMDLINE_EXT_isInnerOptValField__!(typeof(srcField))
        && __CMDLINE_EXT_isInnerOptValField__!(typeof(targetField))
        && values.length) {
    static if (isBaseOptionValueType!(typeof(targetField).InnerType)) {
        static assert(values.length == 1);
        // enum IMPLIES_VALUE_name_targetName_E_ = values[0];
        mixin(
            "enum IMPLIES_VALUE_" ~ srcField.stringof ~ "_" ~ targetField.stringof ~ "_E_ = values[0];");
    }
    else {
        // alias IMPLIES_VALUE_name_targetName_R_ = values;
        mixin("alias IMPLIES_VALUE_" ~ srcField.stringof ~ "_" ~ targetField.stringof ~ "_R_ = values;");
    }
}

/// similar to `IMPLIES`, but `targetField` in string
/// Params:
///   srcField = the source option in `OptVal`
///   targetField = the target options in `OptVal`
///   values = the values, if the target option is not bool option, values must not be in bool value
public mixin template S_IMPLIES(alias srcField, string targetField, bool isVariadic, values...)
        if (__CMDLINE_EXT_isInnerOptValField__!(typeof(srcField)) && values.length) {
    static if (!isVariadic) {
        static assert(values.length == 1);
        // enum IMPLIES_VALUE_name_targetName_E_ = values[0];
        mixin("enum IMPLIES_VALUE_" ~ srcField.stringof ~ "_" ~ targetField ~ "_E_ = values[0];");
    }
    else {
        // alias IMPLIES_VALUE_name_targetName_R_ = values;
        mixin("alias IMPLIES_VALUE_" ~ srcField.stringof ~ "_" ~ targetField ~ "_R_ = values;");
    }
}

public template ACTFN(alias fn) {
    alias ACTFN = (Parameters!(fn)[0] vals...) => fn(vals);
}
