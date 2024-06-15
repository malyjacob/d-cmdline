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

import cmdline.error;
import cmdline.argument;
import cmdline.option;
import cmdline.help;
import cmdline.pattern;
import cmdline.event;

version (Windows) import core.sys.windows.windows;

enum AddHelpPos : string {
    BeforeAll = "beforeAll",
    Before = "before",
    After = "after",
    AfterAll = "afterAll"
}

class Command : EventManager {
    Command parent = null;
    Command[] _commands = [];

    Option[] _options = [];
    NegateOption[] _negates = [];

    Argument[] _arguments = [];

    string _name;
    string _defaultCommandName = "";
    string[] _aliasNames = [];
    string _selfPath = "";

    string _version = "";
    string _usage = "";

    string _description = "";
    string[string] _argsDescription = null;

    bool _execHandler = false;
    string _execFile = "";
    string _execDir = "";

    string[] rawFlags = [];
    string[] argFlags = [];
    string[] errorFlags = [];
    string[] unknownFlags = [];
    string sub = "";

    ArgVariant[] args = [];
    OptionVariant[string] opts = null;

    bool _allowExcessArguments = true;
    bool _showHelpAfterError = false;
    bool _showSuggestionAfterError = true;
    bool _combineFlagAndOptionalValue = true;

    void function(CMDLineError) _exitCallback = null;
    void delegate() _actionHandler = null;
    Help _helpConfiguration = null;
    OutputConfiguration _outputConfiguration = new OutputConfiguration();

    bool _hidden = false;
    bool _addImplicitHelpCommand = true;
    bool _addImplicitHelpOption = true;
    Option _helpOption = null;
    Command _helpCommand = null;

    Option _versionOption = null;
    Command _versionCommand = null;

    Option _configOption = null;

    this(string name) {
        this._name = name;
    }

    alias Self = typeof(this);

    Self copyInheritedSettings(Command src) {
        this._allowExcessArguments = src._allowExcessArguments;
        this._showHelpAfterError = src._showHelpAfterError;
        this._showSuggestionAfterError = src._showSuggestionAfterError;
        this._combineFlagAndOptionalValue = src._combineFlagAndOptionalValue;
        this._exitCallback = src._exitCallback;
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

    string description() const {
        return this._description;
    }

    Self description(string str, string[string] argsDesc = null) {
        this._description = str;
        if (argsDesc !is null)
            this._argsDescription = argsDesc;
        return this;
    }

    Self configureHelp(Help helpConfig) {
        this._helpConfiguration = helpConfig;
        return this;
    }

    inout(Help) configureHelp() inout {
        return this._helpConfiguration;
    }

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

    Self command(Args...)(string nameAndArgs, string desc, string[string] execOpts = null) {
        auto cmd = createCommand!Args(nameAndArgs, desc);
        cmd._execHandler = true;
        if (execOpts) {
            auto exec_file = "execFile" in execOpts;
            if (exec_file)
                cmd._execFile = *exec_file;
        }
        this._registerCommand(cmd);
        cmd.parent = this;
        cmd.copyInheritedSettings(this);
        return this;
    }

    Self addCommand(Command cmd, bool[string] cmdOpts) {
        if (!cmd._name.length) {
            throw new CMDLineError("Command passed to .addCommand() must have a name
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

    void _registerCommand(Command command) {
        auto knownBy = (Command cmd) => [cmd.name] ~ cmd.aliasNames;
        auto alreadyUsed = knownBy(command).find!(name => this._findCommand(name));
        if (!alreadyUsed.empty) {
            string exit_cmd = knownBy(this._findCommand(alreadyUsed[0])).join("|");
            string new_cmd = knownBy(command).join("|");
            throw new CMDLineError(format!"cannot add command `%s` as already have command `%s`"(new_cmd, exit_cmd));
        }
        if (auto help_cmd = this._helpCommand) {
            auto num = knownBy(command).count!(name => name == help_cmd._name ||
                    cast(bool) help_cmd._aliasNames.count(name));
            if (num) {
                string help_cmd_names = knownBy(help_cmd).join("|");
                string new_cmd_names = knownBy(command).join("|");
                throw new CMDLineError(
                    format!"cannot add command `%s` as this command name cannot be same as
                        the name of help command `%s`"(
                        new_cmd_names, help_cmd_names));
            }
        }
        else {
            string help_cmd_names = "help";
            if (auto num = knownBy(command).count(help_cmd_names)) {
                string new_cmd_names = knownBy(command).join("|");
                throw new CMDLineError(
                    format!"cannot add command `%s` as this command name cannot be same as
                        the name of help command `%s`"(
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
                throw new CMDLineError(
                    format!"cannot add command `%s` as this command name cannot be same as
                        the name of version command `%s`"(
                        new_cmd_names, version_cmd_names));
            }
        }
        this._commands ~= command;
    }

    void _registerOption(Option option) {
        Option short_opt = option.shortFlag != "" ? this._findOption(option.shortFlag) : null;
        Option long_opt = option.longFlag != "" ? this._findOption(option.longFlag) : null;
        Option match_opt = (short_opt is null) ? long_opt : short_opt;
        if (match_opt) {
            auto match_flag = option.longFlag != "" && this._findOption(option.longFlag)
                ? option.longFlag : option.shortFlag;
            throw new CMDLineError(
                format!"Cannot add option '%s' due to conflicting flag '%s' - already ued by option '%s'"(
                    option.flags, this._name, match_flag
            ));
        }
        if (auto help_option = this._helpOption) {
            if (help_option.shortFlag == option.shortFlag || help_option.longFlag == option
                .longFlag) {
                throw new CMDLineError(format!"Cannot add option '%s'
                    due to confliction help option `%s`"(option.flags, help_option.flags));
            }
        }
        else if (option.shortFlag == "-h" || option.longFlag == "--help") {
            throw new CMDLineError(format!"Cannot add option '%s'
                    due to confliction help option `%s`"(option.flags, "-h, --help"));
        }
        if (auto version_option = this._versionOption) {
            if (version_option.shortFlag == option.shortFlag || version_option.longFlag == option
                .longFlag) {
                throw new CMDLineError(format!"Cannot add option '%s'
                    due to confliction version option `%s`"(option.flags, version_option.flags));
            }
        }
        if (auto config_option = this._configOption) {
            if (config_option.shortFlag == option.shortFlag || config_option.longFlag == option
                .longFlag) {
                throw new CMDLineError(format!"Cannot add option '%s'
                    due to confliction config option `%s`"(option.flags, config_option.flags));
            }
        }
        this._options ~= option;
    }

    void _registerOption(NegateOption option) {
        NegateOption short_opt = option.shortFlag != "" ? this._findNegateOption(
            option.shortFlag) : null;
        NegateOption long_opt = option.longFlag != "" ? this._findNegateOption(
            option.longFlag) : null;
        NegateOption match_opt = (short_opt is null) ? long_opt : short_opt;
        if (match_opt) {
            auto match_flag = option.longFlag != "" && this._findNegateOption(option.longFlag)
                ? option.longFlag : option.shortFlag;
            throw new CMDLineError(
                format!"Cannot add option `%s` due to conflicting flag `%s` - already ued by option `%s`"(
                    option.flags, this._name, match_flag
            ));
        }
        if (auto help_option = this._helpOption) {
            if (help_option.name == option.name)
                throw new CMDLineError(format!"Cannot add negate-option '%s'
                    due to confliction help option `%s`"(option.flags, help_option.flags));
        }
        else if (option.name == "help") {
            throw new CMDLineError(format!"Cannot add negate-option '%s'
                    due to confliction help option `%s`"(option.flags, "-h, --help"));
        }
        if (auto version_option = this._versionOption) {
            if (version_option.name == option.name)
                throw new CMDLineError(format!"Cannot add negate-option '%s'
                    due to confliction version option `%s`"(option.flags, version_option.flags));
        }
        if (auto config_option = this._configOption) {
            if (config_option.name == option.name) {
                throw new CMDLineError(format!"Cannot add negate-option '%s'
                    due to confliction config option `%s`"(option.flags, config_option.flags));
            }
        }
        this._negates ~= option;
    }

    Self addOption(Option option) {
        this._registerOption(option);
        this.on("option:" ~ option.name, (string val, string[] vals...) {
            // auto invalid_msg = format!"error: option `%s` argument `%s` is invalid."(option.flags, val);
            setOptionVal!(Source.Cli)(option.name, val, vals);
        });
        return this;
    }

    Self addOption(NegateOption option) {
        this._registerOption(option);
        return this;
    }

    Self _optionImpl(T, bool isMandatory = false)(string flags, string desc)
            if (isOptionValueType!T) {
        auto option = createOption!T(flags, desc);
        option.makeOptionMandatory(isMandatory);
        return this.addOption(option);
    }

    Self option(T)(string flags, string desc) {
        return _optionImpl!(T)(flags, desc);
    }

    Self requiredOption(T)(string flags, string desc) {
        return _optionImpl!(T, true)(flags, desc);
    }

    Self _optionImpl(T, bool isMandatory = false)(string flags, string desc, T defaultValue)
            if (isOptionValueType!T) {
        auto option = createOption!T(flags, desc);
        option.makeOptionMandatory(isMandatory);
        option.defaultVal(defaultValue);
        return this.addOption(option);
    }

    Self option(T)(string flags, string desc, T defaultValue) {
        return _optionImpl(flags, desc, defaultValue);
    }

    Self requiredOption(T)(string flags, string desc, T defaultValue) {
        return _optionImpl!(T, true)(flags, desc, defaultValue);
    }

    Self setOptionVal(Source src, T)(string key, T value) if (isOptionValueType!T) {
        Option opt = this._findOption(key);
        assert(opt);
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
            throw new CMDLineError;
            break;
        }
        return this;
    }

    Self setOptionVal(Source src)(string key) {
        auto opt = this._findOption(key);
        assert(opt);
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
            throw new CMDLineError;
            break;
        }
        return this;
    }

    Self setOptionVal(Source src : Source.Env)(string key) {
        auto opt = this._findOption(key);
        assert(opt);
        opt.envVal();
        return this;
    }

    Self setOptionVal(Source src : Source.Cli, T:
        string)(string key, T value, T[] rest...) {
        auto opt = this._findOption(key);
        assert(opt);
        opt.cliVal(value, rest);
        return this;
    }

    Self setOptionVal(Source src : Source.Cli, T:
        string)(string key, T values...) {
        return this.setOptionVal!src(key, values[0], values[1 .. $]);
    }

    Self setOptionValDirectly(T)(string key, T value, Source src = Source.None)
            if (isOptionValueType!T) {
        auto opt = this._findOption(key);
        assert(opt);
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
        assert(opt && opt.isOptional);
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
        assert(opt);
        BoolOption derived = cast(BoolOption) opt;
        derived.innerData = value;
        derived.source = src;
        derived.settled = true;
        return this;
    }

    inout(OptionVariant) getOptionVal(string key) inout {
        if (this.opts && key in this.opts)
            return this.opts[key];
        auto opt = this._findOption(key);
        assert(opt);
        return opt.get;
    }

    inout(OptionVariant) getOptionValWithGlobal(string key) inout {
        auto cmds = this._getCommandAndAncestors();
        foreach (cmd; cmds) {
            if (cmd.opts && key in cmd.opts)
                return cmd.opts[key];
            auto opt = this._findOption(key);
            assert(opt);
            return opt.get;
        }
        throw new CMDLineError;
    }

    Source getOptionValSource(string key) const {
        auto opt = this._findOption(key);
        assert(opt);
        return opt.source;
    }

    Source getOptionValWithGlobalSource(string key) const {
        auto cmds = this._getCommandAndAncestors();
        foreach (cmd; cmds) {
            auto opt = this._findOption(key);
            assert(opt);
            return opt.source;
        }
        throw new CMDLineError;
    }

    Self name(string str) {
        this._name = str;
        return this;
    }

    string name() const {
        return this._name.idup;
    }

    Self setVersion(string str, string flags = "", string desc = "") {
        this._version = str;
        flags = flags == "" ? "-V, --version" : flags;
        desc = desc == "" ? "output the version number" : desc;
        this._versionOption = createOption(flags, desc);
        this.on("option:" ~ _versionOption.name, () {
            this._outputConfiguration.writeOut(this._version ~ "\n");
            this._exitSuccessfully();
        });
        Command cmd = createCommand("version").description("output the version number");
        cmd.parent = this;
        this.on("command:" ~ _versionOption.name, () {
            this._outputConfiguration.writeOut(this._version ~ "\n");
            this._exitSuccessfully();
        });
        return this;
    }

    string getVersion() const {
        return this._version.idup;
    }

    Self setHelpCommand(string flags = "", string desc = "") {
        flags = flags == "" ? "help [command]" : flags;
        desc = desc == "" ? "display help for command" : desc;
        Command help_cmd = createCommand!(string)(flags, desc);
        help_cmd.setHelpOption(false);
        this._addImplicitHelpCommand = true;
        this._helpCommand = help_cmd;
        return this;
    }

    Self setHelpCommand(bool enable) {
        this._addImplicitHelpCommand = enable;
        return this;
    }

    Self addHelpCommand(Command cmd) {
        this._addImplicitHelpCommand = true;
        this._helpCommand = cmd;
        return this;
    }

    Self addHelpCommand(string flags = "", string desc = "") {
        return this.setHelpCommand(flags, desc);
    }

    Command _getHelpCommand() {
        if (!this._addImplicitHelpCommand)
            return null;
        if (!this._helpCommand)
            this.setHelpCommand();
        return this._helpCommand;
    }

    Self setHelpOption(string flags = "", string desc = "") {
        flags = flags == "" ? "-h, --help" : flags;
        desc = desc == "" ? "display help for command" : desc;
        this._helpOption = createOption(flags, desc);
        return this;
    }

    Self setHelpOption(bool enable) {
        this._addImplicitHelpOption = enable;
        return this;
    }

    Self addHelpOption(Option option) {
        this._helpOption = option;
        return this;
    }

    Self addHelpOption(string flags = "", string desc = "") {
        return this.setHelpOption(flags, desc);
    }

    Option _getHelpOption() {
        if (!this._addImplicitHelpCommand)
            return null;
        if (!this._helpOption)
            this.setHelpOption();
        return this._helpOption;
    }

    void outputHelp(bool isErrorMode = false) const {
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

    string helpInfo(bool isErrorMode = false) const {
        auto helper = cast(Help) this._helpConfiguration;
        helper.helpWidth = isErrorMode ?
            this._outputConfiguration.getErrHelpWidth() : this._outputConfiguration.getOutHelpWidth();
        return helper.formatHelp(this);
    }

    void help(bool isErrorMode = false) {
        this.outputHelp(isErrorMode);
        if (isErrorMode)
            this._exit("(outputHelp)", 1, "command.help");
        this._exit(0);
    }

    Self addHelpText(AddHelpPos pos, string text) {
        string help_event = pos.to!string ~ "Help";
        this.on(help_event, (bool isErrMode) {
            if (text.length) {
                auto writer = isErrMode ?
                    this._outputConfiguration.writeErr : this._outputConfiguration.writeOut;
                writer(text ~ "\n");
            }
        });
        return this;
    }

    void _outputHelpIfRequested(string[] flags) {
        auto help_opt = this._getHelpOption();
        bool help_requested = help_opt !is null &&
            !flags.find!(flag => help_opt.isFlag(flag)).empty;
        if (help_requested) {
            this.outputHelp();
            this._exitSuccessfully();
        }
    }

    Self action(alias fn)() {
        auto listener = () {
            auto args = this._arguments
                .filter!(arg => arg.settled)
                .map!(arg => arg.get)
                .array;
            auto options = this._options
                .filter!(opt => opt.settled)
                .map!(opt => tuple(opt.name, opt.get))
                .assocArray;
            fn(args, options);
            this._exitSuccessfully();
        };
        this._actionHandler = listener;
        return this;
    }

    Self aliasName(string aliasStr) {
        Command command = this;
        if (this._commands.length != 0 && this._commands[$ - 1]._execHandler) {
            command = this._commands[$ - 1];
        }
        if (aliasStr == command._name)
            throw new CMDLineError;
        auto matchingCommand = this.parent ? this._findCommand(aliasStr) : null;
        if (matchingCommand) {
            auto exitCmdNames = [matchingCommand.name()];
            exitCmdNames ~= matchingCommand.aliasNames;
            auto namesStr = exitCmdNames.join("|");
            throw new CMDLineError(
                format!"cannot add alias %s to command %s as already have command %s"(aliasStr, this.name, namesStr));
        }
        command._aliasNames ~= aliasStr;
        return this;
    }

    string aliasName() const {
        assert(this._aliasNames.length);
        return this._aliasNames[0];
    }

    Self aliasNames(string[] aliasStrs) {
        aliasStrs.each!(str => this.aliasName(str));
        return this;
    }

    const(string[]) aliasNames() const {
        return this._aliasNames;
    }

    inout(Command) _findCommand(string name) inout {
        auto validate = (inout Command cmd) => cmd._name == name || cast(bool) cmd._aliasNames.count(
            name);
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

    Self addArgument(Argument argument) {
        auto args = this._arguments;
        Argument prev_arg = args.length ? args[$ - 1] : null;
        if (prev_arg && prev_arg.variadic) {
            throw new CMDLineError;
        }
        this._arguments ~= argument;
        return this;
    }

    Self argument(T)(string name, string desc = "") if (isArgValueType!T) {
        auto arg = createArgument!T(name, desc);
        this.addArgument(arg);
        return this;
    }

    Self argument(T)(string name, string desc, T val) if (isBaseArgValueType!T) {
        auto arg = createArgument!T(name, desc);
        arg.defaultVal(val);
        this.addArgument(arg);
        return this;
    }

    Self argument(T)(string name, string desc, T val, T[] rest...)
            if (isBaseArgValueType!T && !is(T == bool)) {
        auto arg = createArgument!T(name, desc);
        arg.defaultVal(val, rest);
        this.addArgument(arg);
        return this;
    }

    Self argument(T : U[], U)(string name, string desc, T defaultVal)
            if (!is(U == bool) && isBaseArgValueType!U) {
        assert(defaultVal.length >= 1);
        auto arg = createArgument!T(name, desc);
        arg.defaultVal(defaultVal);
        this.addArgument(arg);
        return this;
    }

    Self arguments(Args...)(string names) {
        enum args_num = Args.length;
        auto arg_strs = names.strip().split(" ");
        assert(args_num == arg_strs.length);
        static foreach (index, T; Args) {
            this.argument!T(arg_strs[index]);
        }
        return this;
    }

    Self configureOutput(OutputConfiguration config) {
        this._outputConfiguration = config;
        return this;
    }

    inout(OutputConfiguration) configureOutput() inout {
        return this._outputConfiguration;
    }

    Self showHelpAfterError(bool displayHelp = true) {
        this._showHelpAfterError = displayHelp;
        return this;
    }

    Self showSuggestionAfterError(bool displaySuggestion = true) {
        this._showSuggestionAfterError = displaySuggestion;
        return this;
    }

    Self comineFlagAndOptionValue(bool combine) {
        this._combineFlagAndOptionalValue = combine;
        return this;
    }

    Self allowExcessArguments(bool allow) {
        this._allowExcessArguments = allow;
        return this;
    }

    Self exitOverride(typeof(this._exitCallback) fn = null) {
        if (fn)
            this._exitCallback = fn;
        else
            this._exitCallback = (CMDLineError err) { throw err; };
        return this;
    }

    void _exit(string msg, ubyte exitCode = 1, string code = "") const {
        auto fn = this._exitCallback;
        if (fn)
            fn(new CMDLineError(msg, exitCode, code));
        this._exit(exitCode);
    }

    void _exitSuccessfully() const {
        _exit(0);
    }

    void _exit(ubyte exitCode) const {
        import core.stdc.stdlib : exit;

        exit(exitCode);
    }

    void error(string msg = "", string code = "command.error", ubyte exitCode = 1) {
        this._outputConfiguration.writeErr(msg ~ "\n");
        if (this._showHelpAfterError) {
            this._outputConfiguration.writeErr("\n");
            this.outputHelp(true);
        }
        this._exit(msg, exitCode, code);
    }

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

    Self usage(string str) {
        if (str == "") {
            string[] args_str = _arguments.map!(arg => arg.readableArgName).array;
            string[] seed = [];
            _usage = "" ~ (seed ~
                    (_options.length || _addImplicitHelpOption ? "[options]" : [
            ]) ~
                    (_commands.length ? "[command]" : []) ~
                    (_arguments.length ? args_str : [])
            ).join(" ");
        }
        else
            this._usage = str;
        return this;
    }
}

unittest {
    auto cmd = new Command("cmdline");
    assert(cmd._allowExcessArguments);
    cmd.description("this is test");
    assert("this is test" == cmd.description);
    cmd.description("this is test", ["first": "1st", "second": "2nd"]);
    assert(cmd._argsDescription == ["first": "1st", "second": "2nd"]);
    cmd.setVersion("0.0.1");
    // cmd.emit("command:version");
    // cmd.emit("option:version");
}

unittest {
    auto program = new Command("program");
    program.command!(string, int)("start <service> [number]", "start named service", [
        "execFile": "./tmp/ss.txt"
    ]);
    auto arg1 = program._commands[0]._arguments[0];
    auto arg2 = program._commands[0]._arguments[1];
    writeln(program._commands[0]._execFile);
    writeln(arg1.name);
    writeln(arg2.name);

    auto cmd = program.command!(string, int)("stop <service> [number]", [
        "isDefault": true
    ]);
    auto arg3 = cmd._arguments[0];
    auto arg4 = cmd._arguments[1];
    writeln(program._defaultCommandName);
    writeln(arg3.name);
    writeln(arg4.name);
}

Command createCommand(string name) {
    return new Command(name);
}

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
    int _getOutHelpWidth() {
        HANDLE hConsole = GetStdHandle(STD_OUTPUT_HANDLE);
        CONSOLE_SCREEN_BUFFER_INFO csbi;
        GetConsoleScreenBufferInfo(hConsole, &csbi);
        return csbi.srWindow.Right - csbi.srWindow.Left + 1;
    }
}
else version (Posix) {
    int _getOutHelpWidth() {
        Tuple!(int, string) result = executeShell("stty size");
        string tmp = result[1].strip;
        return tmp.split(" ")[1].to!int;
    }
}

unittest {
    writeln(_getOutHelpWidth());

    OutputConfiguration outputConfig = new OutputConfiguration;
    assert(outputConfig.getOutHelpWidth() == _getOutHelpWidth());
}
