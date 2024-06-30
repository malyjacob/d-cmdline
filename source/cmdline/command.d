/++
$(H2 The Command Type for Cmdline)

This modlue mainly has `Command` Type.

we can configure the command in manly way
and then use `Command.parse` to parse the input command line.
if you define its action callback, this callback would be called when parsing. 
Authors: 笑愚(xiaoyu)
+/
module cmdline.command;

import std.stdio;
import std.process;
import std.conv;
import std.array;
import std.range;
import std.range.primitives;
import std.traits;
import std.regex;
import std.string;
import std.typecons;
import std.algorithm;
import std.format;
import std.file;
import std.path;
import std.typetuple;
import std.json;

import cmdline.error;
import cmdline.argument;
import cmdline.option;
import cmdline.help;
import cmdline.pattern;
import cmdline.event;

version (Windows) import core.sys.windows.windows;

/// the enum represents the position of appendent help text
enum AddHelpPos : string {
    BeforeAll = "beforeAll",
    Before = "before",
    After = "after",
    AfterAll = "afterAll"
}

/// the callback passed as a parameter of `this.action`
alias ActionCallback = void delegate();

/// the callback passed as a parameter of `this.action`
alias ActionCallback_0 = void delegate(in OptsWrap);
/// the callback passed as a parameter of `this.action`
alias ActionCallback_1 = void delegate(in OptsWrap, in ArgWrap);
/// the callback passed as a parameter of `this.action`
alias ActionCallback_2 = void delegate(in OptsWrap, in ArgWrap, in ArgWrap);
/// the callback passed as a parameter of `this.action`
alias ActionCallback_3 = void delegate(in OptsWrap, in ArgWrap, in ArgWrap, in ArgWrap);
/// the callback passed as a parameter of `this.action`
alias ActionCallback_4 = void delegate(in OptsWrap, in ArgWrap, in ArgWrap, in ArgWrap, in ArgWrap);
/// the callback passed as a parameter of `this.action`
alias ActionCallback_5 = void delegate(in OptsWrap, in ArgWrap, in ArgWrap, in ArgWrap, in ArgWrap, in ArgWrap);

/// the sequence of action callbacks
alias ActionCallBackSeq = AliasSeq!(
    ActionCallback,
    ActionCallback_0,
    ActionCallback_1,
    ActionCallback_2,
    ActionCallback_3,
    ActionCallback_4,
    ActionCallback_5
);

/// Command Type
class Command : EventManager {
package:
    Command parent = null;
    Command[] _commands = [];

    Option[] _options = [];
    NegateOption[] _negates = [];
    Option[] _abandons = [];

    Argument[] _arguments = [];

    string _name;
    string _defaultCommandName = "";
    string[] _aliasNames = [];
    string _selfPath = "";

    string _version = "*";
    string _usage = "";

    string _description = "";
    string[string] _argsDescription = null;

    bool _execHandler = false;
    string _execFile = "";
    string _execDir = "";
    string[string] _externalCmdHelpFlagMap = null;

    string[] rawFlags = [];
    string[] argFlags = [];
    string[] errorFlags = [];
    string[] unknownFlags = [];

    Command subCommand = null;

    bool immediately = false;

    public ArgVariant[] args = [];
    public OptionVariant[string] opts = null;

    bool _allowExcessArguments = true;
    bool _showHelpAfterError = true;
    bool _showSuggestionAfterError = true;
    bool _combineFlagAndOptionalValue = true;

    void delegate() _actionHandler = null;
    Help _helpConfiguration = new Help;
    OutputConfiguration _outputConfiguration = new OutputConfiguration();

    bool _hidden = false;
    bool _addImplicitHelpCommand = true;
    bool _addImplicitHelpOption = true;
    Option _helpOption = null;
    Command _helpCommand = null;

    Option _versionOption = null;
    Command _versionCommand = null;

    Option _configOption = null;
    string configEnvKey = "";
    const(JSONValue)* jconfig = null;

    this(string name) {
        this._name = name;
    }

    alias Self = typeof(this);

    /// inherit the basic configuration from another command
    public Self copyInheritedSettings(Command src) {
        this._allowExcessArguments = src._allowExcessArguments;
        this._showHelpAfterError = src._showHelpAfterError;
        this._showSuggestionAfterError = src._showSuggestionAfterError;
        this._combineFlagAndOptionalValue = src._combineFlagAndOptionalValue;
        this._outputConfiguration = src._outputConfiguration;
        this._helpConfiguration = src._helpConfiguration;
        return this;
    }

    inout(Command)[] _getCommandAndAncestors() inout {
        Command[] result = [];
        for (Command cmd = cast(Command) this; cmd; cmd = cmd.parent) {
            result ~= cmd;
        }
        return cast(inout(Command)[]) result;
    }

public:
    /// get the description of command
    string description() const {
        return "description: " ~ this._description;
    }

    /// set the description of command
    Self description(string str, string[string] argsDesc = null) {
        this._description = str;
        if (argsDesc !is null)
            this._argsDescription = argsDesc;
        return this;
    }

    /// configurre the help
    Self configureHelp(Help helpConfig) {
        this._helpConfiguration = helpConfig;
        return this;
    }

    /// get the help configuration
    inout(Help) configureHelp() inout {
        return this._helpConfiguration;
    }

    /// define a sub command and sub command's arguments,
    /// this sub command inherit the basic configuration of parent command
    /// Params:
    ///   nameAndArgs = like `sub <arg1> [arg2] [arg3...]`
    ///   cmdOpts = controll the behavior,
    ///             `isDefault` determine whether this sub command is default sub command,
    ///             `hidden` determine whether this sub command is hidden out of help
    /// `Args`: that is type sequence of the arguments' type sequence
    /// Returns: the sub command that you define
    Command command(Args...)(string nameAndArgs, bool[string] cmdOpts = null) {
        auto cmd = createCommand!Args(nameAndArgs);
        this._registerCommand(cmd);
        cmd.parent = this;
        cmd.copyInheritedSettings(this);
        if (cmdOpts) {
            auto is_default = "isDefault" in cmdOpts;
            auto is_hidden = "hidden" in cmdOpts;
            if (is_default && *is_default)
                this._defaultCommandName = cmd._name;
            if (is_hidden)
                cmd._hidden = *is_hidden;
        }
        return cmd;
    }

    /// define a sub command, which represents the external command line program
    /// Params:
    ///   name = only the name of this sub command
    ///   desc = the description of this sub command
    ///   execOpts = controll the behavior,
    ///              `file` the file name of external command line program,
    ///              `dir` the directory that external command line program situates on
    ///              `help` the help option of this external command line program, which is useful when invoke the help of this sub command
    /// Returns: `Self` for chain call
    Self command(string name, string desc, string[string] execOpts = null) {
        auto cmd = createCommand(name, desc);
        cmd._execHandler = true;
        version (Posix) {
            cmd._execFile = format("%s-%s", this._name, cmd._name);
        }
        else version (Windows) {
            cmd._execFile = format("%s-%s.exe", this._name, cmd._name);
        }
        cmd._execDir = dirName(thisExePath());
        if (execOpts) {
            if (auto exec_file = "file" in execOpts) {
                string tmp = strip(*exec_file);
                auto cp = matchFirst(tmp, PTN_EXECUTABLE);
                if (cp.empty)
                    error("error format of excutable file: " ~ tmp);
                version (Windows) {
                    tmp = cp[1].empty ? tmp ~ ".exe" : tmp;
                }
                else version (Posix) {
                    tmp = !cp[1].empty ? tmp[0 .. $ - 4] : tmp;
                }
                cmd._execFile = tmp;
            }
            if (auto exec_dir = "dir" in execOpts)
                cmd._execDir = *exec_dir;
            if (auto exec_help_flag = "help" in execOpts) {
                this._externalCmdHelpFlagMap[cmd._name] = *exec_help_flag;
            }
        }
        if (!this._externalCmdHelpFlagMap || !(cmd._name in this._externalCmdHelpFlagMap))
            this._externalCmdHelpFlagMap[cmd._name] = "--help";
        cmd.usage(format!"run `%s %s --help` to see"(this._name, cmd._name));
        cmd.parent = this;
        cmd._allowExcessArguments = true;
        cmd._showHelpAfterError = false;
        cmd._showSuggestionAfterError = false;
        cmd._combineFlagAndOptionalValue = false;
        cmd._outputConfiguration = this._outputConfiguration;
        cmd._helpConfiguration = null;
        cmd.disableHelp();
        this._registerCommand(cmd);
        return this;
    }

    /// add the sub command, which is often used when you want more detail configuration of sub command
    /// Params:
    ///   cmd = the command used as the sub command
    ///   cmdOpts = see also `this.command(Args...)(string nameAndArgs, bool[string] cmdOpts = null)`
    /// `Args`: see alos `this.command(Args...)(string nameAndArgs, bool[string] cmdOpts = null)`
    /// Returns: `Self` for chain call
    Self addCommand(Command cmd, bool[string] cmdOpts) {
        if (!cmd._name.length) {
            this.error("Command passed to .addCommand() must have a name
                - specify the name in Command constructor or using .name()");
        }
        this._registerCommand(cmd);
        cmd.parent = this;
        cmd.copyInheritedSettings(this);
        if (cmdOpts) {
            auto is_default = "isDefault" in cmdOpts;
            auto is_hidden = "hidden" in cmdOpts;
            if (is_default && *is_default)
                this._defaultCommandName = cmd._name;
            if (is_hidden)
                cmd._hidden = *is_hidden;
        }
        return this;
    }

    /// define the arguments' descriptions
    /// Params:
    ///   argName = the argument's name
    ///   desc = the description of the argument
    /// Returns: `Self` for chain call
    Self argumentDesc(string argName, string desc) {
        auto arg = _findArgument(argName);
        if (arg)
            arg._description = desc;
        return this;
    }

    /// define the arguments' descriptions
    /// Params:
    ///   descMap = the map of arguments' description, key is the name of argument
    /// Returns: `Self` for chain call
    Self argumentDesc(string[string] descMap) {
        foreach (argName, desc; descMap) {
            argumentDesc(argName, desc);
        }
        return this;
    }

package:
    void _registerArgument(Argument arg) {
        auto other = _findArgument(arg._name);
        if (other) {
            this.error(format!"cannot add argument `%s` as this name already used "(
                    arg._name));
        }
        this._arguments ~= arg;
    }

    void _registerCommand(Command command) {
        auto knownBy = (Command cmd) => [cmd.name] ~ cmd.aliasNames;
        auto alreadyUsed = knownBy(command).find!(name => this._findCommand(name));
        if (!alreadyUsed.empty) {
            string exit_cmd = knownBy(this._findCommand(alreadyUsed[0])).join("|");
            string new_cmd = knownBy(command).join("|");
            this.error(format!"cannot add command `%s` as already have command `%s`"(new_cmd, exit_cmd));
        }
        if (auto help_cmd = this._helpCommand) {
            auto num = knownBy(command).count!(name => name == help_cmd._name ||
                    cast(bool) help_cmd._aliasNames.count(name));
            if (num) {
                string help_cmd_names = knownBy(help_cmd).join("|");
                string new_cmd_names = knownBy(command).join("|");
                this.error(format(
                        "cannot add command `%s` as this command name cannot be same as " ~
                        "the name of help command `%s`",
                        new_cmd_names, help_cmd_names));
            }
        }
        else if (this._addImplicitHelpCommand) {
            string help_cmd_names = "help";
            if (auto num = knownBy(command).count(help_cmd_names)) {
                string new_cmd_names = knownBy(command).join("|");
                this.error(format(
                        "cannot add command `%s` as this command name cannot be same as " ~
                        "the name of help command `%s`",
                        new_cmd_names, help_cmd_names));
            }
        }
        if (auto version_cmd = this._versionCommand) {
            auto num = knownBy(command).count!(name => name == version_cmd._name || cast(bool) version_cmd
                    ._aliasNames.count(
                        name));
            if (num) {
                string version_cmd_names = knownBy(version_cmd).join("|");
                string new_cmd_names = knownBy(command).join("|");
                this.error(format(
                        "cannot add command `%s` as this command name cannot be same as " ~
                        "the name of version command `%s`",
                        new_cmd_names, version_cmd_names));
            }
        }
        command.parent = this;
        this._commands ~= command;
    }

    void _registerOption(Option option) {
        Option match_lopt = this._findOption(option.longFlag);
        Option match_sopt = this._findOption(option.shortFlag);
        NegateOption match_nopt = this._findNegateOption(option.shortFlag);
        if (match_lopt) {
            string match_flags = match_lopt is match_sopt ? match_lopt.flags : match_lopt.longFlag;
            this.error(
                format!"Cannot add option '%s' due to conflicting flag '%s' - already ued by option '%s'"(
                    option.flags, match_flags, match_lopt.flags
            ));
        }
        if (match_sopt && match_sopt !is match_lopt) {
            auto match_flags = option.shortFlag;
            this.error(
                format!"Cannot add option '%s' due to conflicting flag '%s' - already ued by option '%s'"(
                    option.flags, match_flags, match_sopt.flags
            ));
        }
        if (match_nopt) {
            string match_flags = match_nopt.shortFlag;
            this.error(
                format!"Cannot add option '%s' due to conflicting flag '%s' - already ued by option '%s'"(
                    option.flags, match_flags, match_nopt.flags
            ));
        }
        if (auto help_option = this._helpOption) {
            if (option.matchFlag(help_option)) {
                this.error(format!"Cannot add option '%s' due to confliction help option `%s`"(
                        option.flags, help_option.flags));
            }
        }
        else if (this._addImplicitHelpOption && (option.shortFlag == "-h" || option.longFlag == "--help")) {
            this.error(format!"Cannot add option '%s' due to confliction help option `%s`"(option.flags, "-h, --help"));
        }
        if (auto version_option = this._versionOption) {
            if (option.matchFlag(version_option)) {
                this.error(format!"Cannot add option '%s' due to confliction version option `%s`"(
                        option.flags, version_option.flags));
            }
        }
        if (auto config_option = this._configOption) {
            if (option.matchFlag(config_option)) {
                this.error(format!"Cannot add option '%s' due to confliction config option `%s`"(
                        option.flags, config_option.flags));
            }
        }
        this._options ~= option;
    }

    void _registerOption(NegateOption option) {
        NegateOption match_lopt = this._findNegateOption(option.longFlag);
        NegateOption match_sopt = this._findNegateOption(option.shortFlag);
        Option match_opt = this._findOption(option.shortFlag);
        if (match_lopt) {
            string match_flags = match_lopt is match_sopt ? match_lopt.flags : match_lopt.longFlag;
            this.error(
                format!"Cannot add option '%s' due to conflicting flag '%s' - already ued by option '%s'"(
                    option.flags, match_flags, match_lopt.flags
            ));
        }
        if (match_sopt && match_sopt !is match_lopt) {
            auto match_flags = option.shortFlag;
            this.error(
                format!"Cannot add option '%s' due to conflicting flag '%s' - already ued by option '%s'"(
                    option.flags, match_flags, match_sopt.flags
            ));
        }
        if (match_opt) {
            auto match_flags = match_opt.shortFlag;
            this.error(
                format!"Cannot add option '%s' due to conflicting flag '%s' - already ued by option '%s'"(
                    option.flags, match_flags, match_opt.flags
            ));
        }
        if (auto help_option = this._helpOption) {
            if (option.matchFlag(help_option))
                this.error(format!"Cannot add negate-option '%s' due to confliction help option `%s`"(
                        option.flags, help_option.flags));
        }
        else if (this._addImplicitHelpOption && (option.shortFlag == "-h" || option.longFlag == "--no-help")) {
            this.error(format!"Cannot add negate-option '%s' due to confliction help option `%s`"(
                    option.flags, "-h, --help"));
        }
        if (auto version_option = this._versionOption) {
            if (option.matchFlag(version_option))
                this.error(format!"Cannot add negate-option '%s' due to confliction version option `%s`"(
                        option.flags, version_option.flags));
        }
        if (auto config_option = this._configOption) {
            if (option.matchFlag(config_option)) {
                this.error(format!"Cannot add negate-option '%s' due to confliction config option `%s`"(
                        option.flags, config_option.flags));
            }
        }
        this._negates ~= option;
    }

public:
    /// add the option to command
    Self addOption(Option option) {
        this._registerOption(option);
        bool is_required = option.isRequired;
        bool is_optional = option.isOptional;
        bool is_variadic = option.variadic;
        string name = option.name;
        if (is_required) {
            if (is_variadic) {
                this.on("option:" ~ name, (string[] vals) {
                    if (vals.length == 0) {
                        this.parsingError(
                            format!"the value's num of variadic option `%s` cannot be zero"(name));
                    }
                    setOptionVal!(Source.Cli)(name, vals);
                });
            }
            else {
                this.on("option:" ~ name, (string val) {
                    setOptionVal!(Source.Cli)(name, val);
                });
            }
        }
        else if (is_optional) {
            if (is_variadic) {
                this.on("option:" ~ name, (string[] vals) {
                    if (vals.length)
                        setOptionVal!(Source.Cli)(name, vals);
                    else
                        option.found = true;
                });
            }
            else {
                this.on("option:" ~ name, (string val) {
                    setOptionVal!(Source.Cli)(name, val);
                });
                this.on("option:" ~ name, () { option.found = true; });
            }
        }
        else {
            this.on("option:" ~ name, () { option.found = true; });
        }
        return this;
    }

    /// add the negate option to command
    Self addOption(NegateOption option) {
        auto opt = _findOption(option.name);
        if (!opt) {
            opt = createOption("--" ~ option.name, "see also option " ~ option.flags).defaultVal();
            _registerOption(opt);
            _registerOption(option);
            this.on("negate:" ~ option.name, () {
                setOptionValDirectly(option.name, false, Source.Cli);
            });
        }
        else {
            _registerOption(option);
            if (opt.isBoolean)
                this.on("negate:" ~ option.name, () {
                    setOptionValDirectly(option.name, false, Source.Cli);
                });
            else
                this.on("negate:" ~ option.name, () {
                    this._options = this._options.remove!(ele => ele is opt);
                    this._abandons ~= opt;
                });
        }
        return this;
    }

    /// add the action option to command, which will invoke the callback we injected when parsing the flag of this option, only useful in client cmd
    Self addActionOption(Option option, void delegate(string[] vals...) call_back, bool endMode = true) {
        this._registerOption(option);
        string name = option.name;
        this.on("option:" ~ name, () {
            call_back();
            if (endMode)
                this._exitSuccessfully();
        });
        this.on("option:" ~ name, (string str) {
            call_back(str);
            if (endMode)
                this._exitSuccessfully();
        });
        this.on("option:" ~ name, (string[] strs) {
            call_back(strs);
            if (endMode)
                this._exitSuccessfully();
        });
        return this;
    }

    package Self _optionImpl(T, bool isMandatory = false)(string flags, string desc)
            if (isOptionValueType!T) {
        auto option = createOption!T(flags, desc);
        option.makeMandatory(isMandatory);
        return this.addOption(option);
    }

    package Self _optionImpl(string flags, string desc) {
        auto lflag = splitOptionFlags(flags).longFlag;
        auto is_negate = !matchFirst(lflag, PTN_NEGATE).empty;
        if (is_negate) {
            auto nopt = createNOption(flags, desc);
            return this.addOption(nopt);
        }
        else {
            auto opt = createOption(flags, desc);
            return this.addOption(opt);
        }
    }

    /// define a value/variadic option to this command
    Self option(T)(string flags, string desc) {
        return _optionImpl!(T)(flags, desc);
    }

    /// define a bool option to this command
    Self option(string flags, string desc) {
        return _optionImpl(flags, desc);
    }

    /// define a mandatory value/variadic option to this command
    Self requiredOption(T)(string flags, string desc) {
        return _optionImpl!(T, true)(flags, desc);
    }

    /// define a mandatory bool option to this command
    Self requireOption(string flags, string desc) {
        return _optionImpl!(bool, true)(flags, desc);
    }

    package Self _optionImpl(T, bool isMandatory = false)(string flags, string desc, T defaultValue)
            if (isOptionValueType!T) {
        auto option = createOption!T(flags, desc);
        option.makeMandatory(isMandatory);
        option.defaultVal(defaultValue);
        return this.addOption(option);
    }

    /// see also `Self option(T)(string flags, string desc)` and define a default value for this option
    Self option(T)(string flags, string desc, T defaultValue) {
        return _optionImpl(flags, desc, defaultValue);
    }

    /// see also `Self requiredOption(T)(string flags, string desc)` and define a default value for this option
    Self requiredOption(T)(string flags, string desc, T defaultValue) {
        return _optionImpl!(T, true)(flags, desc, defaultValue);
    }

package:
    Self setOptionVal(Source src, T)(string key, T value) if (isOptionValueType!T) {
        Option opt = this._findOption(key);
        if (!opt) {
            this.parsingError(format!"option `%s` doesn't exist"(key));
        }
        switch (src) {
        case Source.Default:
            opt.defaultVal(value);
            break;
        case Source.Config:
            opt.configVal(value);
            break;
        case Source.Imply:
            opt.implyVal(value);
            break;
        case Source.Preset:
            opt.preset(value);
            break;
        default:
            this.error;
            break;
        }
        return this;
    }

    Self setOptionVal(Source src)(string key) {
        auto opt = this._findOption(key);
        if (!opt) {
            this.parsingError(format!"option `%s` doesn't exist"(key));
        }
        switch (src) {
        case Source.Default:
            opt.defaultVal();
            break;
        case Source.Config:
            opt.configVal();
            break;
        case Source.Imply:
            opt.implyVal();
            break;
        case Source.Preset:
            opt.preset();
            break;
        default:
            this.error;
            break;
        }
        return this;
    }

    Self setOptionVal(Source src : Source.Env)(string key) {
        auto opt = this._findOption(key);
        if (!opt) {
            this.parsingError(format!"option `%s` doesn't exist"(key));
        }
        opt.envVal();
        return this;
    }

    Self setOptionVal(Source src : Source.Cli, T:
        string)(string key, T value, T[] rest...) {
        auto opt = this._findOption(key);
        if (!opt) {
            this.parsingError(format!"option `%s` doesn't exist"(key));
        }
        opt.cliVal(value, rest);
        opt.found = true;
        return this;
    }

    Self setOptionVal(Source src : Source.Cli, T:
        string)(string key, T[] values) {
        if (values.length == 0) {
            this.parsingError(
                format!"the value's num of option `%s` cannot be zero"(key));
        }
        return this.setOptionVal!src(key, values[0], values[1 .. $]);
    }

    Self setOptionValDirectly(T)(string key, T value, Source src = Source.None)
            if (isOptionValueType!T) {
        auto opt = this._findOption(key);
        if (!opt) {
            this.parsingError(format!"option `%s` doesn't exist"(key));
        }
        static if (!is(ElementType!T U == void) && !is(T == string)) {
            VariadicOption!U derived = cast(VariadicOption!U) opt;
            derived.innerValueData = value;
            derived.source = src;
            derived.settled = true;
        }
        else {
            ValueOption!T derived = cast(ValueOption!T) opt;
            derived.innerValueData = value;
            derived.source = src;
            derived.settled = true;
        }
        return this;
    }

    Self setOptionValDirectly(T)(string key, Source src = Source.None)
            if (isOptionValueType!T) {
        auto opt = this._findOption(key);
        if (!opt) {
            this.parsingError(format!"option `%s` doesn't exist"(key));
        }
        if (!opt.isOptional) {
            this.parsingError(format!"option `%s` must be optional"(key));
        }
        static if (!is(ElementType!T U == void) && !is(T == string)) {
            VariadicOption!U derived = cast(VariadicOption!U) opt;
            derived.innerBoolData = true;
            derived.isValueData = true;
            derived.source = src;
            derived.settled = true;
        }
        else {
            ValueOption!T derived = cast(ValueOption!T) opt;
            derived.innerBoolData = true;
            derived.isValueData = true;
            derived.source = src;
            derived.settled = true;
        }
        return this;
    }

    Self setOptionValDirectly(string key, bool value = true, Source src = Source.None) {
        auto opt = this._findOption(key);
        if (!opt) {
            this.parsingError(format!"option `%s` doesn't exist"(key));
        }
        BoolOption derived = cast(BoolOption) opt;
        derived.innerData = value;
        derived.source = src;
        derived.settled = true;
        return this;
    }

public:
    /// get the inner value of a option by flag wrapped by `ArgWrap`.
    /// remember better use it in action callabck or after parsing
    /// Params:
    ///   key = the flag of option
    /// Returns: the value wrapped by `ArgWrap`, which may be empty when cannot find the option
    ArgWrap getOptionVal(string key) const {
        if (!this.opts) {
            this.error("the options has not been initialized, cannnot get the value of option now");
        }
        auto ptr = key in this.opts;
        return ptr ? ArgWrap(*ptr) : ArgWrap(null);
    }

    // ArgWrap getOptionValWithGlobal(string key) const {
    //     auto cmds = this._getCommandAndAncestors();
    //     foreach (cmd; cmds) {
    //         if (cmd.opts && key in cmd.opts)
    //             return ArgWrap(this.opts[key]);
    //         auto opt = this._findOption(key);
    //         if (!opt) {
    //             this.error(format!"option `%s` doesn't exist"(key));
    //         }
    //         return ArgWrap(opt.get);
    //     }
    //     this.error(format!"cannot get the option `%s`'s value"(key));
    //     assert(0);
    // }

    /// get the source of option
    /// remember better use it in action callabck or after parsing
    /// Params:
    ///   key = the flag of option
    /// Returns: the source of option final value in `Source`
    Source getOptionValSource(string key) const {
        auto opt = this._findOption(key);
        if (!opt || !opt.settled) {
            this.error(format!"option `%s` doesn't exist or not settled"(key));
        }
        return opt.source;
    }

    // Source getOptionValWithGlobalSource(string key) const {
    //     auto cmds = this._getCommandAndAncestors();
    //     foreach (cmd; cmds) {
    //         auto opt = this._findOption(key);
    //         if (!opt) {
    //             this.error(format!"option `%s` doesn't exist"(key));
    //         }
    //         return opt.source;
    //     }
    //     this.error(format!"cannot get the option `%s`'s source"(key));
    //     assert(0);
    // }

    package void execSubCommand(in string[] unknowns) {
        string sub_path = buildPath(_execDir, _execFile);
        const(string)[] inputs;
        if (!(sub_path[0] == '"' && sub_path[$ - 1] == '"') && sub_path.any!(c => c == ' ')) {
            sub_path = '"' ~ sub_path ~ '"';
        }
        unknowns.each!((str) {
            if (!(str[0] == '"' && str[$ - 1] == '"') && str.any!(c => c == ' ')) {
                string new_str = '"' ~ str ~ '"';
                inputs ~= new_str;
            }
            else {
                inputs ~= str;
            }
        });
        auto result = executeShell(sub_path ~ " " ~ inputs.join(" "));
        if (result.status == 0) {
            this._outputConfiguration.writeOut(result.output);
            this._exitSuccessfully();
        }
        else {
            this._outputConfiguration.writeErr(result.output);
            this._exit(1);
        }
    }

    /// parse the command line argument variables
    /// Params:
    ///   argv = the command line argument variables
    void parse(in string[] argv) {
        auto user_argv = _prepareUserArgs(argv);
        try {
            _parseCommand(user_argv);
        }
        catch (InvalidArgumentError e) {
            parsingError(e.msg, e.code);
        }
        catch (InvalidOptionError e) {
            parsingError(e.msg, e.code);
        }
    }

package:
    string[] _prepareUserArgs(in string[] args) {
        auto arr = args.filter!(str => str.length).array;
        this._selfPath = arr[0];
        this.rawFlags = arr.dup;
        return args[1 .. $].dup;
    }

    void _parseCommand(in string[] unknowns) {
        auto has_cmd = (const string str) {
            auto _cmd = _findCommand(str);
            auto vcmd = this._versionCommand;
            auto hcmd = this._helpCommand;
            _cmd = !_cmd && vcmd && vcmd._name == str ? vcmd : _cmd;
            _cmd = !_cmd && hcmd && hcmd._name == str ? hcmd : _cmd;
            return _cmd ? true : (this._addImplicitHelpCommand && str == "help");
        };
        auto has_hvopt = (const string str) {
            auto vopt = this._versionOption;
            auto hopt = this._helpOption;
            auto _opt = vopt && vopt.isFlag(str) ? vopt : null;
            _opt = !_opt && hopt && hopt.isFlag(str) ? hopt : null;
            return _opt ? true : (this._addImplicitHelpOption &&
                    (str == "--help" || str == "-h"));
        };
        if (!this._defaultCommandName.empty &&
            unknowns.all!(str => !has_cmd(str) && !has_hvopt(str))) {
            auto cmd = _findCommand(this._defaultCommandName);
            if (!cmd)
                parsingError("cannot find the default sub command `"
                        ~ this._defaultCommandName ~ "`");
            if (this._configOption && !cmd._execHandler) {
                auto j_config = _processConfigFile(this.configEnvKey);
                if (j_config) {
                    auto cmd_name = cmd._name;
                    auto cmd_j_config = cmd_name in *j_config;
                    cmd.jconfig = cmd_j_config;
                }
            }
            cmd._parseCommand(unknowns);
            return;
        }
        this.parseOptionsEnv();
        auto parsed = this.parseOptions(unknowns);
        this.argFlags = parsed[0];
        this.unknownFlags = parsed[1];
        this.parseOptionsConfig();
        this.parseOptionsImply();
        this._options
            .filter!(opt => opt.settled || opt.isValid)
            .each!((opt) { opt.initialize; });
        _checkMissingMandatoryOption();
        _checkConfilctOption();
        this.opts = this._options
            .filter!(opt => opt.settled)
            .map!(opt => tuple(opt.name, opt.get))
            .assocArray;
        this.parseArguments(parsed[0]);
        if (this.subCommand && this.subCommand._execHandler) {
            this.subCommand.execSubCommand(parsed[1]);
        }
        if (this.subCommand) {
            this.subCommand._parseCommand(parsed[1]);
        }
        else {
            this.emit("action:" ~ this._name);
        }
    }

    Tuple!(string[], string[]) parseOptions(in string[] argv) {
        string[] operands = [];
        string[] unknowns = [];

        string[] _args = argv.dup;
        auto maybe_opt = (string str) {
            return (str.length > 1 && str[0] == '-' &&
                    (str[1] == '-' || (str[1] >= 'A' && str[1] <= 'Z') ||
                        (str[1] >= 'a' && str[1] <= 'z')));
        };
        auto get_front = (string[] strs) => strs.empty ? "" : strs.front;
        auto find_cmd = (string str) {
            auto _cmd = _findCommand(str);
            auto vcmd = this._versionCommand;
            auto hcmd = this._helpCommand;
            _cmd = !_cmd && vcmd && vcmd._name == str ? vcmd : _cmd;
            _cmd = !_cmd && hcmd && hcmd._name == str ? hcmd : _cmd;
            _cmd = _cmd ? _cmd : (!hcmd && str == "help") ? this._getHelpCommand() : null;
            return _cmd;
        };
        string[][string] variadic_val_map = null;
        while (_args.length) {
            auto arg = _args.front;
            _args.popFront;

            if (arg == "--") {
                auto value = get_front(_args);
                if (value.length == 0) {
                    this.parsingError(
                        "cannot end with `--`");
                }
                auto cmd = find_cmd(value);
                while (!cmd && value.length) {
                    operands ~= value;
                    popFront(_args);
                    value = get_front(_args);
                    cmd = find_cmd(value);
                }
                if (cmd) {
                    this.subCommand = cmd;
                    popFront(_args);
                    if (subCommand.immediately)
                        subCommand._parseCommand(_args);
                    unknowns ~= _args;
                }
                break;
            }

            if (maybe_opt(arg)) {
                auto opt = _findOption(arg);
                auto nopt = _findNegateOption(arg);
                if (opt) {
                    auto name = opt.name;
                    bool is_variadic = opt.variadic;
                    if (opt.isRequired) {
                        if (!is_variadic) {
                            auto value = get_front(_args);
                            if (value.empty || maybe_opt(value))
                                this.optionMissingArgument(opt);
                            this.emit("option:" ~ name, value);
                            _args.popFront;
                        }
                        else {
                            auto value = get_front(_args);
                            string[] tmps = [];
                            while (value.length && !maybe_opt(value)) {
                                tmps ~= value;
                                popFront(_args);
                                value = get_front(_args);
                            }
                            auto ptr = name in variadic_val_map;
                            if (ptr)
                                *ptr ~= tmps;
                            else
                                variadic_val_map[name] = tmps;
                        }
                    }
                    else if (opt.isOptional) {
                        if (!is_variadic) {
                            auto value = get_front(_args);
                            if (value.empty || maybe_opt(value))
                                this.emit("option:" ~ name);
                            else {
                                this.emit("option:" ~ name, value);
                                _args.popFront;
                            }
                        }
                        else {
                            auto value = get_front(_args);
                            string[] tmps = [];
                            while (value.length && !maybe_opt(value)) {
                                tmps ~= value;
                                popFront(_args);
                                value = get_front(_args);
                            }
                            auto ptr = name in variadic_val_map;
                            if (ptr)
                                *ptr ~= tmps;
                            else
                                variadic_val_map[name] = tmps;
                        }
                    }
                    else {
                        if (opt.settled && !opt.get!bool)
                            conflctNegateOption(arg);
                        this.emit("option:" ~ name);
                    }
                    continue;
                }
                if (nopt) {
                    this.emit("negate:" ~ nopt.name);
                    continue;
                }
                if (Option help_opt = this._helpOption) {
                    if (help_opt.isFlag(arg)) {
                        this.emit("option:" ~ help_opt.name);
                        continue;
                    }
                }
                else if (this._addImplicitHelpOption) {
                    if (arg == "-h" || arg == "--help") {
                        auto hopt = this._getHelpOption();
                        this.emit("option:" ~ hopt.name);
                        continue;
                    }
                }
                if (Option vopt = this._versionOption) {
                    if (vopt.isFlag(arg)) {
                        this.emit("option:" ~ vopt.name);
                        continue;
                    }
                }
                if (Option copt = this._configOption) {
                    if (copt.isFlag(arg)) {
                        string value = get_front(_args);
                        if (value.empty || maybe_opt(value))
                            this.optionMissingArgument(opt);
                        this.emit("option:" ~ copt.name, value);
                        _args.popFront;
                        continue;
                    }
                }
            }

            if (arg.length > 2 && arg[0] == '-' && arg[1] != '-') {
                Option opt = _findOption("-" ~ arg[1]);
                if (opt) {
                    string name = opt.name;
                    if (opt.isRequired || opt.isOptional) {
                        bool is_variadic = opt.variadic;
                        if (!is_variadic)
                            this.emit("option:" ~ name, arg[2 .. $]);
                        else {
                            auto ptr = name in variadic_val_map;
                            if (ptr)
                                *ptr ~= arg[2 .. $];
                            else
                                variadic_val_map[name] = [arg[2 .. $]];
                        }
                    }
                    else if (_combineFlagAndOptionalValue) {
                        this.emit("option:" ~ name);
                        _args.insertInPlace(0, "-" ~ arg[2 .. $]);
                    }
                    else {
                        this.parsingError(
                            "invalid value: `" ~ arg[2 .. $] ~ "` for bool option " ~ opt
                                .flags);
                    }
                    continue;
                }
            }

            auto cp = matchFirst(arg, PTN_LONGASSIGN);
            if (cp.length) {
                Option opt = _findOption(cp[1]);
                string value = cp[2];
                if (opt) {
                    if (opt.isRequired || opt.isOptional) {
                        bool is_variadic = opt.variadic;
                        if (!is_variadic)
                            this.emit("option:" ~ name, value);
                        else {
                            auto ptr = name in variadic_val_map;
                            if (ptr)

                                *ptr ~= value;
                            else
                                variadic_val_map[name] = [value];
                        }
                    }
                    else
                        this.parsingError(
                            "invalid value: `" ~ value ~ "` for bool option " ~ opt
                                .flags);
                    continue;
                }
            }

            if (auto _cmd = find_cmd(arg)) {
                this.subCommand = _cmd;
                if (subCommand.immediately && subCommand._actionHandler !is null) {
                    this.parseOptionsConfig();
                    subCommand._parseCommand(_args);
                }
                unknowns ~= _args;
                break;
            }

            if (maybe_opt(arg))
                unknownOption(arg);

            operands ~= arg;
        }
        if (variadic_val_map) {
            foreach (key, ref value; variadic_val_map)
                this.emit("option:" ~ key, value);
        }
        variadic_val_map = null;
        return tuple(operands, unknowns);
    }

    void optionMissingArgument(in Option opt) const {
        string message = format("option '%s' argument missing", opt.flags);
        this.parsingError(message);
    }

    void unknownOption(string flag) const {
        string msg = "";
        auto any_abandon = this._abandons.find!((const Option opt) => opt.isFlag(
                flag) || opt.name == flag);
        if (!any_abandon.empty) {
            msg = format("this option `%s` has been disable by its related negate option `--%s`",
                any_abandon[0].flags, any_abandon[0].name);
            this.parsingError(msg, "command.disableOption");
        }
        else {
            auto cmd = this;
            auto hlp = cmd._helpConfiguration;
            string suggestion = "";
            const(string)[] more_flags;
            string[] candidate_flags = [];
            if (flag[0 .. 2] == "--" && this._showSuggestionAfterError) {
                more_flags = hlp.visibleOptions(cmd).map!(opt => opt.longFlag).array;
                candidate_flags ~= more_flags;
            }
            suggestion = suggestSimilar(flag, candidate_flags);
            msg = format("unknown option `%s` %s", flag, suggestion);
            this.parsingError(msg, "command.unknownOption");
        }
    }

    void conflctNegateOption(string flag) const {
        string msg = format(
            "if negate option difined on client terminal," ~
                " then the releated option `%s` can not be", flag);
        this.parsingError(msg, "command.conflictNegateOption");
    }

    void excessArguments() const {
        if (!this._allowExcessArguments) {
            this.parsingError("too much args!!!");
        }
    }

    void _checkMissingMandatoryOption() const {
        auto f = this._options.filter!(opt => opt.mandatory && !opt.settled);
        if (!f.empty) {
            auto strs = f.map!(opt => format!"`%s`"(opt.name)).join(" and ");
            this.parsingError(format!"the option: %s must have a valid value!"(strs));
        }
    }

    void _checkConfilctOption() const {
        auto opts = this._options
            .filter!(opt => opt.settled)
            .filter!(opt => !(opt.source == Source.Default || opt.source == Source.None || opt.source == Source
                    .Imply))
            .array;
        auto is_conflict = (const Option opt) {
            const string[] confilcts = opt.conflictsWith;
            foreach (name; confilcts) {
                opts.each!((o) {
                    if (opt !is o && o.name == name)
                        this.parsingError(
                            format!"cannot set option `%s` and `%s` at the same time"(o.name, name));
                });
            }
        };
        opts.each!(is_conflict);
    }

    void parseArguments(in string[] _args) {
        auto args = _args.dup;
        auto get_front = () => args.empty ? "" : args.front;
        foreach (argument; this._arguments) {
            auto is_v = argument.variadic;
            if (!is_v) {
                auto value = get_front();
                if (!value.length)
                    break;
                argument.cliVal(value);
                popFront(args);
            }
            else {
                if (!args.length)
                    break;
                argument.cliVal(args[0], args[1 .. $]);
                args = [];
                break;
            }
        }
        if (args.length)
            this.excessArguments();
        this._arguments.each!((Argument arg) {
            if (arg.isRequired && !arg.isValid)
                this.parsingError(
                    format!"argument `%s` is required but its value is invalid"(arg._name));
        });
        this._arguments.each!((Argument arg) {
            if (arg.isValid || arg.settled)
                arg.initialize;
        });
        Argument prev = null;
        foreach (i, arg; this._arguments) {
            if (prev && arg.settled && !prev.settled)
                this.parsingError("arg should be valid in row");
            prev = arg;
        }
        this.args = this._arguments
            .filter!(arg => arg.settled)
            .map!(arg => arg.get)
            .array;
    }

    void parseOptionsEnv() {
        this._options.each!((Option opt) { opt.envVal(); });
    }

    void parseOptionsImply() {
        auto set_imply = (Option option) {
            auto imply_map = option.implyMap;
            foreach (string key, OptionVariant value; imply_map) {
                auto tmp = split(key, ':');
                string name = tmp[0];
                string type = tmp[1];
                Option opt = _findOption(name);
                if (opt && !opt.isValid)
                    opt.implyVal(value);
                if (opt && (opt.source == Source.Default)) {
                    opt.settled = false;
                    opt.implyVal(value);
                }
                auto any_abandon = this._abandons.find!((const Option opt) => opt.name == name);
                if (!opt && !any_abandon.empty) {
                    this.unknownOption(name);
                }
                if (!opt) {
                    string flag = format("--%s <%s-value>", name, name);
                    string flag2 = format("--%s", name);
                    string flag3 = format("--%s <%s-value...>", name, name);
                    switch (type) {
                    case int.stringof:
                        opt = createOption!int(flag);
                        break;
                    case double.stringof:
                        opt = createOption!double(flag);
                        break;
                    case string.stringof:
                        opt = createOption!string(flag);
                        break;
                    case bool.stringof:
                        opt = createOption!bool(flag2);
                        break;
                    case (int[]).stringof:
                        opt = createOption!int(flag3);
                        break;
                    case (double[]).stringof:
                        opt = createOption!double(flag3);
                        break;
                    case (string[]).stringof:
                        opt = createOption!string(flag3);
                        break;
                    default:
                        break;
                    }
                    if (opt) {
                        opt.implyVal(value);
                        this.addOption(opt);
                    }
                }
            }
        };
        this._options
            .filter!(opt => opt.settled || opt.isValid)
            .each!((opt) { opt.initialize; });
        this._options
            .filter!(opt => opt.settled)
            .filter!(opt => !(opt.source == Source.Default || opt.source == Source.None || opt.source == Source
                    .Imply))
            .each!(set_imply);
    }

    void parseOptionsConfig() {
        alias Value = const(JSONValue)*;
        if (this._configOption) {
            Value j_config = _processConfigFile(this.configEnvKey);
            this.jconfig = j_config ? j_config : this.jconfig;
        }
        if (this.jconfig) {
            parseConfigOptionsImpl(this.jconfig);
        }
    }

public:
    /// set the name of command
    Self name(string str) {
        this._name = str;
        return this;
    }

    /// get the name of command
    string name() const {
        return this._name.idup;
    }

    /// set the version of the command.
    /// if `flags` and `desc` not defined, then it will automatically set the version option flag `-V, --version` and version command name `version` 
    /// Params:
    ///   str = the version string like `0.0.1`
    ///   flags = the version option flag, which is a `bool` option
    ///   desc = the description of the version command and version option
    /// Returns: `Self` for chain call
    Self setVersion(string str, string flags = "", string desc = "") {
        this._version = str;
        setVersionOption(flags, desc);
        string vname = this._versionOption.name;
        setVersionCommand(vname, desc);
        return this;
    }

    /// get the version string of this command, if not set version, the default is `*`
    string getVersion() const {
        return this._version.idup;
    }

    /// set the version option of the command, see also `Self setVersion(string str, string flags = "", string desc = "")`
    Self setVersionOption(string flags = "", string desc = "") {
        assert(!this._versionOption);
        flags = flags == "" ? "-V, --version" : flags;
        desc = desc == "" ? "output the version number" : desc;
        auto vopt = createOption(flags, desc);
        if (auto help_opt = this._helpOption) {
            if (vopt.matchFlag(help_opt))
                this.error(format!"Cannot add option '%s'
                    due to confliction help option `%s`"(vopt.flags, help_opt.flags));
        }
        else if (this._addImplicitHelpOption && (vopt.shortFlag == "-h" || vopt.longFlag == "--help")) {
            this.error(format!"Cannot add option '%s'
                    due to confliction help option `%s`"(vopt.flags, "-h, --help"));
        }
        if (auto config_opt = this._configOption) {
            if (vopt.matchFlag(config_opt))
                this.error(format!"Cannot add option '%s'
                    due to confliction config option `%s`"(vopt.flags, config_opt.flags));
        }
        this._versionOption = vopt;
        string vname = vopt.name;
        this.on("option:" ~ vname, () {
            this._outputConfiguration.writeOut(this._version ~ "\n");
            this._exitSuccessfully();
        });
        return this;
    }

    /// set the version option of the command, see also `Self setVersion(string str, string flags = "", string desc = "")`
    Self addVersionOption(string flags = "", string desc = "") {
        return setVersionOption(flags, desc);
    }

    /// custom the version option
    /// Params:
    ///   opt = the version option
    ///   action = the action callback when parsing the flag of version option, if `null`, then do nothing and exit mutely
    /// Returns: `Self` for chain call
    Self addVersionOption(Option opt, void delegate() action = null) {
        assert(!this._versionOption);
        this._versionOption = opt;
        if (!action) {
            this.on("option:" ~ opt.name, () {
                this._outputConfiguration.writeOut(this._version ~ "\n");
                this._exitSuccessfully();
            });
        }
        else
            this.on("option:" ~ opt.name, () {
                action();
                this._exitSuccessfully();
            });
        return this;
    }

    /// set version command, see also `Self setVersion(string str, string flags = "", string desc = "")`
    Self setVersionCommand(string flags = "", string desc = "") {
        assert(!this._versionCommand);
        flags = flags == "" ? "version" : flags;
        desc = desc == "" ? "output the version number" : desc;
        Command cmd = createCommand(flags).description(desc);
        cmd.setHelpOption(false);
        cmd.setHelpCommand(false);
        string vname = cmd._name;
        if (auto help_cmd = this._helpCommand) {
            auto help_cmd_name_arr = help_cmd._aliasNames ~ help_cmd._name;
            auto none = help_cmd_name_arr.find!(
                name => vname == name).empty;
            if (!none) {
                string help_cmd_names = help_cmd_name_arr.join("|");
                this.error(
                    format!"cannot add command `%s` as this command name cannot be same as
                        the name of help command `%s`"(
                        vname, help_cmd_names));
            }
        }
        else if (this._addImplicitHelpCommand) {
            string help_cmd_names = "help";
            if (vname == help_cmd_names) {
                this.error(
                    format!"cannot add command `%s` as this command name cannot be same as
                        the name of help command `%s`"(
                        vname, help_cmd_names));
            }
        }
        this.on("command:" ~ vname, () {
            this._outputConfiguration.writeOut(this._version ~ "\n");
            this._exitSuccessfully();
        });
        ActionCallback fn = () {
            this._outputConfiguration.writeOut(this._version ~ "\n");
            this._exitSuccessfully();
        };
        cmd.parent = this;
        cmd.action(fn, true);
        this._versionCommand = cmd;
        return this;
    }

    /// set version command, see also `Self setVersion(string str, string flags = "", string desc = "")`
    Self addVersionCommand(string flags = "", string desc = "") {
        return setVersionCommand(flags, desc);
    }

    /// set version command, see also `Self setVersion(string str, string flags = "", string desc = "")`
    Self addVersionCommand(Command cmd) {
        assert(!this._versionCommand);
        string vname = cmd._name;
        if (auto help_cmd = this._helpCommand) {
            auto help_cmd_name_arr = help_cmd._aliasNames ~ help_cmd._name;
            auto none = help_cmd_name_arr.find!(
                name => vname == name).empty;
            if (!none) {
                string help_cmd_names = help_cmd_name_arr.join("|");
                this.error(
                    format!"cannot add command `%s` as this command name cannot be same as
                        the name of help command `%s`"(
                        vname, help_cmd_names));
            }
        }
        else if (this._addImplicitHelpCommand) {
            string help_cmd_names = "help";
            if (vname == help_cmd_names) {
                this.error(
                    format!"cannot add command `%s` as this command name cannot be same as
                        the name of help command `%s`"(
                        vname, help_cmd_names));
            }
        }
        cmd.parent = this;
        this._versionCommand = cmd;
        return this;
    }

    /// set the config option, if `flags` not defined, then config option's flags is `-C, --config <config-path>`;
    /// if `desc not defined, then description is by default;
    /// if `envKey` not defined, then the `envKey` would be `${PROGRAM_NAME}_CONFIG_PATH`, which automatically store the path to config file
    /// Params:
    ///   flags = the flags of config option
    ///   desc = the description of config option
    ///   envKey = the envKey of an env variable that store the destination of config file
    /// Returns: 
    Self setConfigOption(string flags = "", string desc = "", string envKey = "") {
        assert(!this._configOption);
        flags = flags == "" ? "-C, --config <config-path>" : flags;
        string exePath = thisExePath();
        string exeDir = dirName(exePath);
        version (Posix) {
            string base_name = baseName(exePath);
        }
        else version (Windows)
            string base_name = baseName(exePath)[0 .. $ - 4];
        desc = desc == "" ?
            format("define the path to the config file," ~
                    "if not specified, the config file name would be" ~
                    " `%s.config.json` and it is on the dir where `%s` situates on",
                this._name, base_name) : desc;
        string tmp = (this.name ~ "-config-path").replaceAll(regex(`-`), "_").toUpper;
        envKey = envKey.empty ? tmp : envKey;
        environment[envKey] = buildPath(exeDir, format("%s.config.json", this._name));
        this.configEnvKey = envKey;
        auto copt = createOption!string(flags, desc);
        if (auto help_opt = this._helpOption) {
            if (copt.matchFlag(help_opt))
                this.error(format!"Cannot add option '%s'
                    due to confliction help option `%s`"(copt.flags, help_opt.flags));
        }
        else if (this._addImplicitHelpOption && (copt.shortFlag == "-h" || copt.longFlag == "--help")) {
            this.error(format!"Cannot add option '%s'
                    due to confliction help option `%s`"(copt.flags, "-h, --help"));
        }
        if (auto version_opt = this._versionOption) {
            if (copt.matchFlag(version_opt))
                this.error(format!"Cannot add option '%s'
                    due to confliction version option `%s`"(copt.flags, version_opt.flags));
        }
        this._configOption = copt;
        string cname = copt.name;
        this.on("option:" ~ cname, (string configPath) {
            string path = environment[this.configEnvKey];
            string origin_path = dirName(path);
            string base = baseName(path);
            string p1 = buildPath(origin_path, configPath);
            string p2 = buildPath(configPath);
            if (exists(p1)) {
                environment[this.configEnvKey] = buildPath(p1, base);
            }
            else if (exists(p2)) {
                environment[this.configEnvKey] = buildPath(p2, base);
            }
            else
                this.parsingError(format("invalid path: %s\n\v%s", p1, p2));
        });
        return this;
    }

    package void parseConfigOptionsImpl(const(JSONValue)* config) {
        alias Value = const(JSONValue)*;
        if (this.subCommand && !this.subCommand._execHandler) {
            string sub_name = this.subCommand._name;
            Value sub_config = sub_name in *config;
            this.subCommand.jconfig = sub_config;
        }
        if (this.subCommand && this.subCommand.immediately)
            return;
        Value[string] copts;
        Value[] cargs;
        if (Value ptr = "arguments" in *config) {
            if (ptr.type != JSONType.ARRAY) {
                this.parsingError("the `arguments`'s value must be array!");
            }
            ptr.array.each!((const ref JSONValue ele) {
                if (ele.type == JSONType.NULL || ele.type == JSONType.OBJECT) {
                    this.parsingError("the `argument`'s element value cannot be object or null!");
                }
                cargs ~= &ele;
            });
        }
        if (Value ptr = "options" in *config) {
            if (ptr.type != JSONType.OBJECT) {
                this.parsingError("the `options`'s value must be object!");
            }
            foreach (string key, const ref JSONValue ele; ptr.object) {
                if (ele.type == JSONType.NULL || ele.type == JSONType.OBJECT) {
                    this.parsingError("the `option`'s value cannot be object or null!");
                }
                if (ele.type == JSONType.ARRAY) {
                    if (ele.array.length < 1)
                        this.parsingError("if the `option`'s value is array,
                                then its length cannot be 0");
                    bool all_int = ele.array.all!((ref e) => e.type == JSONType.INTEGER);
                    bool all_double = ele.array.all!((ref e) => e.type == JSONType.FLOAT);
                    bool all_string = ele.array.all!((ref e) => e.type == JSONType.STRING);
                    if (!(all_int || all_double || all_string)) {
                        this.parsingError("if the `option`'s value is array,
                                then its element type must all be int or double or string the same");
                    }
                }
                copts[key] = &ele;
            }
        }
        auto get_front = () => cargs.empty ? null : cargs.front;
        auto test_regulra = () {
            bool all_int = cargs.all!((ref e) => e.type == JSONType.INTEGER);
            bool all_double = cargs.all!((ref e) => e.type == JSONType.FLOAT);
            bool all_string = cargs.all!((ref e) => e.type == JSONType.STRING);
            if (!(all_int || all_double || all_string)) {
                this
                    .parsingError(
                        "the variadic `arguments`'s element type must all be int or double or string the same");
            }
        };
        auto assign_arg_arr = (Argument arg) {
            test_regulra();
            auto tmp = cargs[0];
            switch (tmp.type) {
            case JSONType.INTEGER:
                arg.configVal(cargs.map!((ref ele) => cast(int) ele.get!int).array);
                break;
            case JSONType.FLOAT:
                arg.configVal(cargs.map!((ref ele) => cast(double) ele.get!double).array);
                break;
            case JSONType.STRING:
                arg.configVal(cargs.map!((ref ele) => cast(string) ele.get!string).array);
                break;
            default:
                break;
            }
        };
        foreach (Argument argument; this._arguments) {
            auto is_v = argument.variadic;
            if (!is_v) {
                if (Value value = get_front()) {
                    mixin AssignOptOrArg!(argument, value);
                    cargs.popFront();
                }
                else
                    break;
            }
            else {
                if (cargs.length) {
                    assign_arg_arr(argument);
                    break;
                }
            }
        }
        foreach (string key, Value value; copts) {
            Option opt = _findOption(key);
            if (opt) {
                mixin AssignOptOrArg!(opt, value);
            }
            else {
                this.unknownOption(key);
            }
        }
    }

    private mixin template AssignOptOrArg(alias target, alias src)
            if (is(typeof(src) == const(JSONValue)*)) {
        static if (is(typeof(target) == Argument)) {
            Argument arg = target;
        }
        else static if (is(typeof(target) == Option)) {
            Option arg = target;
        }
        else {
            static assert(false);
        }
        const(JSONValue)* val = src;

        static if (is(typeof(target) == Option)) {
            auto assign_arr = () {
                auto tmp = (val.array)[0];
                switch (tmp.type) {
                case JSONType.INTEGER:
                    arg.configVal(val.array.map!((ref ele) => cast(int) ele.get!int).array);
                    break;
                case JSONType.FLOAT:
                    arg.configVal(val.array.map!((ref ele) => cast(double) ele.get!double).array);
                    break;
                case JSONType.STRING:
                    arg.configVal(val.array.map!((ref ele) => cast(string) ele.get!string).array);
                    break;
                default:
                    break;
                }
            };
        }

        auto assign = () {
            switch (val.type) {
            case JSONType.INTEGER:
                arg.configVal(cast(int) val.get!int);
                break;
            case JSONType.FLOAT:
                arg.configVal(cast(double) val.get!double);
                break;
            case JSONType.STRING:
                arg.configVal(cast(string) val.get!string);
                break;
            case JSONType.FALSE, JSONType.TRUE:
                arg.configVal(cast(bool) val.get!bool);
                break;
                static if (is(typeof(target) == Option)) {
            case JSONType.ARRAY:
                    assign_arr();
                    break;
                }
            default:
                break;
            }
            return 0;
        };

        auto _x_Inner_ff = assign();
    }

    package JSONValue* _processConfigFile(string envKey) const {
        string path_to_config = environment[envKey];
        if (path_to_config.length > 12 && path_to_config[$ - 12 .. $] == ".config.json"
            && exists(path_to_config)) {
            try {
                string raw = readText(path_to_config);
                return new JSONValue(parseJSON(raw));
            }
            catch (Exception e) {
                this.parsingError(e.msg);
            }
        }
        return null;
    }

    /// set the help command
    Self setHelpCommand(string flags = "", string desc = "") {
        assert(!this._helpCommand);
        bool has_sub_cmd = this._versionCommand !is null || !this._commands.find!(
            cmd => !cmd._hidden)
            .empty;
        flags = flags == "" ? has_sub_cmd ? "help [command]" : "help" : flags;
        desc = desc == "" ? "display help for command" : desc;
        Command help_cmd = has_sub_cmd ? createCommand!(string)(flags, desc) : createCommand(flags, desc);
        help_cmd.setHelpOption(false);
        help_cmd.setHelpCommand(false);
        string hname = help_cmd._name;
        if (auto verison_cmd = this._versionCommand) {
            auto version_cmd_name_arr = verison_cmd._aliasNames ~ verison_cmd._name;
            auto none = version_cmd_name_arr.find!(name => hname == name).empty;
            if (!none) {
                string version_cmd_names = version_cmd_name_arr.join("|");
                this.error(
                    format!"cannot add command `%s` as this command name cannot be same as
                        the name of version command `%s`"(
                        hname, version_cmd_names));
            }
        }
        ActionCallback_1 fn = (options, hcommand) {
            if (hcommand.isValid) {
                auto sub_cmd_name = hcommand.get!string;
                auto sub_cmd = this._findCommand(sub_cmd_name);
                auto vcmd = this._versionCommand;
                sub_cmd = sub_cmd ? sub_cmd : vcmd && vcmd._name == sub_cmd_name ? vcmd : null;
                if (!sub_cmd || sub_cmd._hidden)
                    this.parsingError("can not find the sub command `" ~ sub_cmd_name ~ "`!");
                if (sub_cmd._execHandler) {
                    sub_cmd.execSubCommand([
                        this._externalCmdHelpFlagMap[sub_cmd._name]
                    ]);
                }
                sub_cmd.help();
            }
            this.help();
        };
        help_cmd.parent = this;
        help_cmd.action(fn, true);
        this._helpCommand = help_cmd;
        return setHelpCommand(true);
    }

    /// enable or disable the help command
    Self setHelpCommand(bool enable) {
        this._addImplicitHelpCommand = enable;
        return this;
    }

    /// add the help command
    Self addHelpCommand(Command cmd) {
        assert(!this._helpCommand);
        string[] hnames = cmd._aliasNames ~ cmd._name;
        if (auto verison_cmd = this._versionCommand) {
            auto version_cmd_name_arr = verison_cmd._aliasNames ~ verison_cmd._name;
            auto none = version_cmd_name_arr.find!((name) {
                return !hnames.find!(h => h == name).empty;
            }).empty;
            if (!none) {
                string version_cmd_names = version_cmd_name_arr.join("|");
                this.error(
                    format!"cannot add command `%s` as this command name cannot be same as
                        the name of version command `%s`"(
                        hnames.join("|"), version_cmd_names));
            }
        }
        cmd.parent = this;
        this._helpCommand = cmd;
        return setHelpCommand(true);
    }

    /// add the help command
    Self addHelpCommand(string flags = "", string desc = "") {
        return this.setHelpCommand(flags, desc);
    }

    package Command _getHelpCommand() {
        if (!this._addImplicitHelpCommand)
            return null;
        if (!this._helpCommand)
            this.setHelpCommand();
        return this._helpCommand;
    }

    /// set the help option
    Self setHelpOption(string flags = "", string desc = "") {
        assert(!this._helpOption);
        flags = flags == "" ? "-h, --help" : flags;
        desc = desc == "" ? "display help for command" : desc;
        auto hopt = createOption(flags, desc);
        if (auto config_opt = this._configOption) {
            if (hopt.matchFlag(config_opt))
                this.error(format!"Cannot add option '%s'
                    due to confliction config option `%s`"(hopt.flags, config_opt.flags));
        }
        if (auto version_opt = this._versionOption) {
            if (hopt.matchFlag(version_opt))
                this.error(format!"Cannot add option '%s'
                    due to confliction version option `%s`"(hopt.flags, version_opt.flags));
        }
        this._helpOption = hopt;
        this.on("option:" ~ hopt.name, () { this.help(); });
        return setHelpOption(true);
    }

    /// enable the help option or not
    Self setHelpOption(bool enable) {
        this._addImplicitHelpOption = enable;
        return this;
    }

    /// add the help option
    Self addHelpOption(Option option, void delegate() action = null) {
        assert(!this._helpOption);
        this._helpOption = option;
        if (!action)
            this.on("option:" ~ option.name, () { this.help(); });
        else
            this.on("option:" ~ option.name, () {
                action();
                this._exitSuccessfully();
            });
        return setHelpOption(true);
    }

    /// add the help option
    Self addHelpOption(string flags = "", string desc = "") {
        return this.setHelpOption(flags, desc);
    }

    /// disable the help support
    Self disableHelp() {
        setHelpCommand(false);
        setHelpOption(false);
        return this;
    }

    package Option _getHelpOption() {
        if (!this._addImplicitHelpCommand)
            return null;
        if (!this._helpOption)
            this.setHelpOption();
        return this._helpOption;
    }

    package void outputHelp(bool isErrorMode = false) const {
        auto writer = isErrorMode ?
            this._outputConfiguration.writeErr : this._outputConfiguration.writeOut;
        auto ancestors = cast(Command[]) _getCommandAndAncestors();
        ancestors.reverse.each!(
            cmd => cmd.emit("beforeAllHelp", isErrorMode)
        );
        this.emit("beforeHelp", isErrorMode);
        writer(helpInfo(isErrorMode) ~ "\n");
        this.emit("afterHelp", isErrorMode);
        ancestors.each!(
            cmd => cmd.emit("afterAllHelp", isErrorMode)
        );
    }

    /// generate the help info
    /// Params:
    ///   isErrorMode = turn on the error mode, which would make the info output to this command's error output
    /// Returns: the string of help info
    string helpInfo(bool isErrorMode = false) const {
        auto helper = cast(Help) this._helpConfiguration;
        helper.helpWidth = isErrorMode ?
            this._outputConfiguration.getErrHelpWidth() : this._outputConfiguration.getOutHelpWidth();
        return helper.formatHelp(this);
    }

    /// invoke the help if the help support is not disabled
    /// Params:
    ///   isErrorMode = turn on the error mode, which would make the info output to this command's error output
    void help(bool isErrorMode = false) {
        this.outputHelp(isErrorMode);
        if (isErrorMode)
            this._exitErr("(outputHelp)", "command.help");
        this._exit(0);
    }

    /// add a appendent help text at specified position
    /// Params:
    ///   pos = the postion to insert at
    ///   text = the appendent hlp text
    /// Returns: `Self` for chain call
    Self addHelpText(AddHelpPos pos, string text) {
        assert(this._addImplicitHelpCommand || this._addImplicitHelpOption);
        string help_event = pos ~ "Help";
        this.on(help_event, (bool isErrMode) {
            if (text.length) {
                auto writer = isErrMode ?
                    this._outputConfiguration.writeErr : this._outputConfiguration.writeOut;
                writer(text ~ "\n");
            }
        });
        return this;
    }

    /// whether sort sub commands when invoke help, default: false
    Self sortSubCommands(bool enable = true) {
        this._helpConfiguration.sortSubCommands = enable;
        return this;
    }

    /// whether sort sub options when invoke help, default: false
    Self sortOptions(bool enable = true) {
        this._helpConfiguration.sortOptions = enable;
        return this;
    }

    /// whether show the global options when invoke help, default: false
    Self showGlobalOptions(bool enable = true) {
        this._helpConfiguration.showGlobalOptions = enable;
        return this;
    }

    package void _outputHelpIfRequested(string[] flags) {
        auto help_opt = this._getHelpOption();
        bool help_requested = help_opt !is null &&
            !flags.find!(flag => help_opt.isFlag(flag)).empty;
        if (help_requested) {
            this.outputHelp();
            this._exitSuccessfully();
        }
    }

    static foreach (Action; ActionCallBackSeq) {
        /// define the action at the end of parsing
        /// Params:
        ///   Fn = the action call back
        mixin SetActionFn!Action;
    }

    private mixin template SetActionFn(Fn) {
        public Self action(Fn fn, bool immediately = false) {
            this.immediately = immediately;
            enum len = Parameters!(fn).length;
            auto listener = () {
                static if (len == 0) {
                    fn();
                }
                else {
                    this.opts = this.opts is null ? this._options
                        .filter!(opt => opt.settled)
                        .map!(opt => tuple(opt.name, opt.get))
                        .assocArray : this.opts;
                    this.args = this.args.empty ? this._arguments
                        .filter!(arg => arg.settled)
                        .map!(arg => arg.get)
                        .array : this.args;
                    OptsWrap wopts = OptsWrap(this.opts);
                    static if (len == 1) {
                        fn(wopts);
                    }
                    else {
                        auto nlen = len - 1;
                        ArgWrap[] wargs;
                        if (this.args.length >= nlen) {
                            wargs = this.args[0 .. nlen].map!((return a) => ArgWrap(a)).array;
                        }
                        else {
                            wargs = this.args.map!(a => ArgWrap(a)).array;
                            ulong less_num = nlen - this.args.length;
                            foreach (_; 0 .. less_num) {
                                wargs ~= ArgWrap(null);
                            }
                        }
                        static if (len == 2) {
                            fn(wopts, wargs[0]);
                        }
                        static if (len == 3) {
                            fn(wopts, wargs[0], wargs[1]);
                        }
                        static if (len == 4) {
                            fn(wopts, wargs[0], wargs[1], wargs[2]);
                        }
                        static if (len == 5) {
                            fn(wopts, wargs[0], wargs[1], wargs[2], wargs[3]);
                        }
                        static if (len == 6) {
                            fn(wopts, wargs[0], wargs[1], wargs[2], wargs[3], wargs[4]);
                        }
                    }
                }
                this._exitSuccessfully();
            };
            this._actionHandler = listener;
            this.on("action:" ~ this._name, () {
                if (this._actionHandler)
                    this._actionHandler();
            });
            return this;
        }
    }

    /// get the options' value map wrap by `OptsWrap`. remember use it after parsing or at the action callabck
    inout(OptsWrap) getOpts() inout {
        return inout OptsWrap(this.opts);
    }

    /// get the array of arguments' value wrap by `ArgWrap`. remember use it after parsing or at the action callabck
    ArgWrap[] getArgs() const {
        auto len = this._arguments.length;
        ArgWrap[] wargs;
        if (this.args.length >= len) {
            wargs = this.args[0 .. len].map!((return a) => ArgWrap(a)).array;
        }
        else {
            wargs = this.args.map!(a => ArgWrap(a)).array;
            ulong less_num = len - this.args.length;
            foreach (_; 0 .. less_num) {
                wargs ~= ArgWrap(null);
            }
        }
        return wargs;
    }

    /// set the alias of command
    Self aliasName(string aliasStr) {
        Command command = this;
        if (this._commands.length != 0 && this._commands[$ - 1]._execHandler) {
            command = this._commands[$ - 1];
        }
        if (aliasStr == command._name)
            this.error(format!"cannot add alias `%s` to command `%s` as they cannot be same"(
                    aliasStr, command._name
            ));
        auto matchingCommand = this.parent ? this._findCommand(aliasStr) : null;
        if (matchingCommand) {
            auto exitCmdNames = [matchingCommand.name()];
            exitCmdNames ~= matchingCommand.aliasNames;
            auto namesStr = exitCmdNames.join("|");
            this.error(
                format!"cannot add alias %s to command %s as already have command %s"(aliasStr, this.name, namesStr));
        }
        command._aliasNames ~= aliasStr;
        return this;
    }

    /// get the first alias of command
    string aliasName() const {
        if (this._aliasNames.length == 0) {
            this.error("the num of alias names cannot be zero");
        }
        return this._aliasNames[0];
    }

    /// set a sequence of aliases of command
    Self aliasNames(string[] aliasStrs) {
        aliasStrs.each!(str => this.aliasName(str));
        return this;
    }

    /// get the sequence of aliases of command
    const(string[]) aliasNames() const {
        return this._aliasNames;
    }

package:
    inout(Argument) _findArgument(string name) inout {
        auto validate = (inout Argument arg) { return name == arg._name; };
        auto tmp = this._arguments.find!validate;
        return tmp.empty ? null : tmp[0];
    }

    inout(Command) _findCommand(string name) inout {
        auto validate = (inout Command cmd) {
            auto result = cmd._name == name || cmd._aliasNames.any!(n => n == name);
            return result;
        };
        auto tmp = this._commands.find!validate;
        return tmp.empty ? null : tmp[0];
    }

    inout(Option) _findOption(string flag) inout {
        auto tmp = this._options.find!(opt => opt.isFlag(flag) || flag == opt.name);
        return tmp.empty ? null : tmp[0];
    }

    inout(NegateOption) _findNegateOption(string flag) inout {
        auto tmp = this._negates.find!(opt => opt.isFlag(flag) || flag == opt.name);
        return tmp.empty ? null : tmp[0];
    }

public:
    /// add argument for command
    Self addArgument(Argument argument) {
        auto args = this._arguments;
        Argument prev_arg = args.length ? args[$ - 1] : null;
        if (prev_arg && prev_arg.variadic) {
            this.error(format!"cannot add argument `%s` after the variadic argument `%s`"(
                    argument._name, prev_arg._name
            ));
        }
        if (prev_arg && prev_arg.isOptional && argument.isRequired) {
            this.error(format!"cannot add required argument `%s` after the optional argument `%s`"(
                    argument._name, prev_arg._name
            ));
        }
        _registerArgument(argument);
        return this;
    }

    /// define the argument for command
    Self argument(T)(string name, string desc = "") if (isArgValueType!T) {
        auto arg = createArgument!T(name, desc);
        this.addArgument(arg);
        return this;
    }

    /// define the argument with default value for command, used for no-variadic argument
    Self argument(T)(string name, string desc, T val) if (isBaseArgValueType!T) {
        auto arg = createArgument!T(name, desc);
        arg.defaultVal(val);
        this.addArgument(arg);
        return this;
    }

    /// define the argument with default value for command, used for variadic argument
    Self argument(T)(string name, string desc, T val, T[] rest...)
            if (isBaseArgValueType!T && !is(T == bool)) {
        auto arg = createArgument!T(name, desc);
        arg.defaultVal(val, rest);
        this.addArgument(arg);
        return this;
    }

    /// define the argument with default value for command, used for variadic argument
    Self argument(T : U[], U)(string name, string desc, T defaultVal)
            if (!is(U == bool) && isBaseArgValueType!U) {
        assert(defaultVal.length >= 1);
        auto arg = createArgument!T(name, desc);
        arg.defaultVal(defaultVal);
        this.addArgument(arg);
        return this;
    }

    /// define manly arguments for command
    Self arguments(Args...)(string names) {
        enum args_num = Args.length;
        auto arg_strs = names.strip().split(" ");
        assert(args_num == arg_strs.length);
        static foreach (index, T; Args) {
            this.argument!T(arg_strs[index]);
        }
        return this;
    }

    /// configure the output of command
    Self configureOutput(OutputConfiguration config) {
        this._outputConfiguration = config;
        return this;
    }

    /// get the output cofiguration of command
    inout(OutputConfiguration) configureOutput() inout {
        return this._outputConfiguration;
    }

    /// whether show help info when parsing occur error, default: `true`
    Self showHelpAfterError(bool displayHelp = true) {
        this._showHelpAfterError = displayHelp;
        return this;
    }

    /// whether show suggestion info when parsing occur error, default: `true`
    Self showSuggestionAfterError(bool displaySuggestion = true) {
        this._showSuggestionAfterError = displaySuggestion;
        return this;
    }

    /// whether allow combine flag mode like `ls -al`, default: `true`
    Self comineFlagAndOptionValue(bool combine) {
        this._combineFlagAndOptionalValue = combine;
        return this;
    }

    /// whether allow excess argument, default: `true`
    Self allowExcessArguments(bool allow) {
        this._allowExcessArguments = allow;
        return this;
    }

package:
    void _exitErr(string msg, string code = "") const {
        this._outputConfiguration.writeErr("ERROR:\t" ~ msg ~ " " ~ code ~ "\n");
        if (this._showHelpAfterError) {
            this._outputConfiguration.writeErr("\n");
            this.outputHelp(true);
        }
        debug this.error();
        this._exit(1);
    }

    void _exitSuccessfully() const {
        _exit(0);
    }

    void _exit(ubyte exitCode) const {
        import core.stdc.stdlib : exit;

        exit(exitCode);
    }

public:
    /// invoke error when parsing command line
    /// Params:
    ///   msg = the error message
    ///   code = the code to tag the error
    void parsingError(string msg = "", string code = "command.error") const {
        this._exitErr(msg, code);
    }

    /// invoke error when configuring command
    /// Params:
    ///   msg = the error message
    ///   code = the code to tag the error
    void error(string msg = "", string code = "command.error") const {
        throw new CMDLineError(msg, 1, code);
    }

    /// get the usage of command
    string usage() const {
        if (this._usage == "") {
            string[] args_str = _arguments.map!(arg => arg.readableArgName).array;
            string[] seed = [];
            return "" ~ (seed ~
                    (_options.length || _addImplicitHelpOption ? "[options]" : [
            ]) ~
                    (_commands.length ? "[command]" : []) ~
                    (_arguments.length ? args_str : [])
            ).join(" ");
        }
        return this._usage;
    }

    /// set the usage of command
    /// Params:
    ///   str = the usage string. if `str` is `""`, then will automatically generate the usage for command
    /// Returns: `Self` for chain call
    Self usage(string str) {
        Command command = this;
        if (this._commands.length != 0 && this._commands[$ - 1]._execHandler) {
            command = this._commands[$ - 1];
        }
        if (str == "") {
            string[] args_str = _arguments.map!(arg => arg.readableArgName).array;
            string[] seed = [];
            command._usage = "" ~ (seed ~
                    (_options.length || _addImplicitHelpOption ? "[options]" : [
            ]) ~
                    (_commands.length ? "[command]" : []) ~
                    (_arguments.length ? args_str : [])
            ).join(" ");
        }
        else
            command._usage = str;
        return this;
    }

    /// get sub command by name
    alias findCommand = _findCommand;
    /// get option by name, short flag and long flag
    alias findOption = _findOption;
    /// get negate option by name, short flag and long flag
    alias findNOption = _findNegateOption;
    /// get argument by name
    alias findArgument = _findArgument;
}

unittest {
    auto cmd = new Command("cmdline");
    assert(cmd._allowExcessArguments);
    cmd.description("this is test");
    assert("description: this is test" == cmd.description);
    cmd.description("this is test", ["first": "1st", "second": "2nd"]);
    assert(cmd._argsDescription == ["first": "1st", "second": "2nd"]);
    cmd.setVersion("0.0.1");
    // cmd.emit("command:version");
    // cmd.emit("option:version");
}

// unittest {
//     auto program = new Command("program");
//     program.command!(string, int)("start <service> [number]", "start named service", [
//         "execFile": "./tmp/ss.txt"
//     ]);
//     auto arg1 = program._commands[0]._arguments[0];
//     auto arg2 = program._commands[0]._arguments[1];
//     writeln(program._commands[0]._execFile);
//     writeln(arg1.name);
//     writeln(arg2.name);

//     auto cmd = program.command!(string, int)("stop <service> [number]", [
//         "isDefault": true
//     ]);
//     auto arg3 = cmd._arguments[0];
//     auto arg4 = cmd._arguments[1];
//     writeln(program._defaultCommandName);
//     writeln(arg3.name);
//     writeln(arg4.name);
// }

/// create a command by name
Command createCommand(string name) {
    return new Command(name);
}

/// create a command by the flag that contains its name and arguments with description
/// see `Command.command(Args...)(string nameAndArgs, string desc = "")`
Command createCommand(Args...)(string nameAndArgs, string desc = "") {
    auto caputures = matchFirst(nameAndArgs, PTN_CMDNAMEANDARGS);
    string name = caputures[1], _args = caputures[2];
    assert(name != "");
    auto cmd = createCommand(name);
    cmd.description(desc);
    if (_args != "")
        cmd.arguments!Args(_args);
    return cmd;
}

/// the output type used in command
class OutputConfiguration {
    void function(string str) writeOut = (string str) => stdout.write(str);
    void function(string str) writeErr = (string str) => stderr.write(str);
    int function() getOutHelpWidth = &_getOutHelpWidth;
    int function() getErrHelpWidth = &_getOutHelpWidth;
    void outputError(alias fn)(string str) {
        fn(str);
    }
}

version (Windows) {
    package int _getOutHelpWidth() {
        HANDLE hConsole = GetStdHandle(STD_OUTPUT_HANDLE);
        CONSOLE_SCREEN_BUFFER_INFO csbi;
        GetConsoleScreenBufferInfo(hConsole, &csbi);
        return csbi.srWindow.Right - csbi.srWindow.Left + 1;
    }
}
else version (Posix) {
    package int _getOutHelpWidth() {
        Tuple!(int, string) result = executeShell("stty size");
        string tmp = result[1].strip;
        return tmp.split(" ")[1].to!int;
    }
}

/// the wrap of option value map
struct OptsWrap {
    private OptionVariant[string] innerValue;

    /// enable getting option value wrapped by `ArgWrap` by name using call form
    ArgWrap opCall(string member) const {
        auto ptr = member in innerValue;
        if (ptr) {
            return ArgWrap(*ptr);
        }
        else
            return ArgWrap(null);
    }

    package this(inout OptionVariant[string] v) inout {
        innerValue = v;
    }
}

/// the wrap of option and argument value
struct ArgWrap {
    private ArgNullable innerValue;

    package this(in ArgVariant value) {
        this.innerValue = value;
    }

    package this(typeof(null) n) {
        this.innerValue = n;
    }

    /// test wheter the inner value is valid
    @property
    bool isValid() inout {
        return !innerValue.isNull;
    }

    /// enable implicitly convert to `bool` type representing `this.isValid`
    alias isValid this;

    /// get the innner type, remember use it after test whether it is valid
    T get(T)() const if (isArgValueType!T) {
        bool is_type = testType!T(this.innerValue);
        if (!is_type) {
            throw new CMDLineError("the inner type is not " ~ T.stringof);
        }
        return cast(T) this.innerValue.get!T;
    }

    /// test whether the type is the innner vlalue type
    bool verifyType(T)() const {
        return testType!T(this.innerValue);
    }

    /// enable the assign oparator with innner type that allow by `ArgWrap`
    auto opAssign(T)(T value) if (isArgValueType!T || is(T == typeof(null))) {
        this.innerValue = value;
        return this;
    }

    /// enbale the explicity cast that can get the inner value
    T opCast(T)() const if (isArgValueType!T) {
        return this.get!T;
    }
}

unittest {
    writeln(_getOutHelpWidth());

    OutputConfiguration outputConfig = new OutputConfiguration;
    assert(outputConfig.getOutHelpWidth() == _getOutHelpWidth());
}

// unittest {
//     Command program = createCommand("program");
//     program.setVersion("0.0.1");
//     program.allowExcessArguments(false);
//     program.option("-f, --first <num>", "test", 13);
//     program.option("-s, --second <num>", "test", 12);
//     program.argument("[multi]", "乘数", 4);
//     program.action((args, optMap) {
//         auto fnum = optMap["first"].get!int;
//         auto snum = optMap["second"].get!int;
//         int multi = 1;
//         if (args.length)
//             multi = args[0].get!int;
//         writeln("ACTION:\t", (fnum + snum) * multi);
//     });

//     program.parse(["program"]);
// }
