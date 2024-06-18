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

alias ActionCallback = void delegate(ArgVariant[], OptionVariant[string]);

class Command : EventManager {
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

    string[] rawFlags = [];
    string[] argFlags = [];
    string[] errorFlags = [];
    string[] unknownFlags = [];

    Command subCommand = null;

    ArgVariant[] args = [];
    OptionVariant[string] opts = null;

    bool _allowExcessArguments = true;
    bool _showHelpAfterError = false;
    bool _showSuggestionAfterError = true;
    bool _combineFlagAndOptionalValue = true;

    void function(CMDLineError) _exitCallback = (CMDLineError err) { throw err; };
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
        else if (this._addImplicitHelpCommand) {
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
        command.parent = this;
        this._commands ~= command;
    }

    void _registerOption(Option option) {
        Option match_lopt = this._findOption(option.longFlag);
        Option match_sopt = this._findOption(option.shortFlag);
        NegateOption match_nopt = this._findNegateOption(option.shortFlag);
        if (match_lopt) {
            string match_flags = match_lopt is match_sopt ? match_lopt.flags : match_lopt.longFlag;
            throw new CMDLineError(
                format!"Cannot add option '%s' due to conflicting flag '%s' - already ued by option '%s'"(
                    option.flags, match_flags, match_lopt.flags
            ));
        }
        if (match_sopt && match_sopt !is match_lopt) {
            auto match_flags = option.shortFlag;
            throw new CMDLineError(
                format!"Cannot add option '%s' due to conflicting flag '%s' - already ued by option '%s'"(
                    option.flags, match_flags, match_sopt.flags
            ));
        }
        if (match_nopt) {
            string match_flags = match_nopt.shortFlag;
            throw new CMDLineError(
                format!"Cannot add option '%s' due to conflicting flag '%s' - already ued by option '%s'"(
                    option.flags, match_flags, match_nopt.flags
            ));
        }
        if (auto help_option = this._helpOption) {
            if (option.matchFlag(help_option)) {
                throw new CMDLineError(format!"Cannot add option '%s'
                    due to confliction help option `%s`"(option.flags, help_option.flags));
            }
        }
        else if (this._addImplicitHelpOption && (option.shortFlag == "-h" || option.longFlag == "--help")) {
            throw new CMDLineError(format!"Cannot add option '%s'
                    due to confliction help option `%s`"(option.flags, "-h, --help"));
        }
        if (auto version_option = this._versionOption) {
            if (option.matchFlag(version_option)) {
                throw new CMDLineError(format!"Cannot add option '%s'
                    due to confliction version option `%s`"(option.flags, version_option.flags));
            }
        }
        if (auto config_option = this._configOption) {
            if (option.matchFlag(config_option)) {
                throw new CMDLineError(format!"Cannot add option '%s'
                    due to confliction config option `%s`"(option.flags, config_option.flags));
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
            throw new CMDLineError(
                format!"Cannot add option '%s' due to conflicting flag '%s' - already ued by option '%s'"(
                    option.flags, match_flags, match_lopt.flags
            ));
        }
        if (match_sopt && match_sopt !is match_lopt) {
            auto match_flags = option.shortFlag;
            throw new CMDLineError(
                format!"Cannot add option '%s' due to conflicting flag '%s' - already ued by option '%s'"(
                    option.flags, match_flags, match_sopt.flags
            ));
        }
        if (match_opt) {
            auto match_flags = match_opt.shortFlag;
            throw new CMDLineError(
                format!"Cannot add option '%s' due to conflicting flag '%s' - already ued by option '%s'"(
                    option.flags, match_flags, match_opt.flags
            ));
        }
        if (auto help_option = this._helpOption) {
            if (option.matchFlag(help_option))
                throw new CMDLineError(format!"Cannot add negate-option '%s'
                    due to confliction help option `%s`"(option.flags, help_option.flags));
        }
        else if (this._addImplicitHelpOption && (option.shortFlag == "-h" || option.longFlag == "--no-help")) {
            throw new CMDLineError(format!"Cannot add negate-option '%s'
                    due to confliction help option `%s`"(option.flags, "-h, --help"));
        }
        if (auto version_option = this._versionOption) {
            if (option.matchFlag(version_option))
                throw new CMDLineError(format!"Cannot add negate-option '%s'
                    due to confliction version option `%s`"(option.flags, version_option.flags));
        }
        if (auto config_option = this._configOption) {
            if (option.matchFlag(config_option)) {
                throw new CMDLineError(format!"Cannot add negate-option '%s'
                    due to confliction config option `%s`"(option.flags, config_option.flags));
            }
        }
        this._negates ~= option;
    }

    Self addOption(Option option) {
        this._registerOption(option);
        bool is_required = option.isRequired;
        bool is_optional = option.isOptional;
        bool is_variadic = option.variadic;
        string name = option.name;
        if (is_required) {
            if (is_variadic) {
                this.on("option:" ~ name, (string[] vals) {
                    assert(vals.length);
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

    Self addOption(NegateOption option) {
        auto opt = _findOption(option.name);
        if (!opt) {
            opt = createOption("--" ~ option.name, "see also option " ~ option.flags).defaultVal();
            _registerOption(opt);
            _registerOption(option);
            this.on("negate:" ~ option.name, () {
                setOptionValDirectly(option.name, false, Source.Imply);
            });
        }
        else {
            _registerOption(option);
            if (opt.isBoolean)
                this.on("negate:" ~ option.name, () {
                    setOptionValDirectly(option.name, false, Source.Imply);
                });
            else
                this.on("negate:" ~ option.name, () {
                    this._options = this._options.remove!(ele => ele is opt);
                    this._abandons ~= opt;
                });
        }
        return this;
    }

    Self addActionOption(Option option, void delegate(string[] vals...) call_back) {
        this._registerOption(option);
        string name = option.name;
        this.on("option:" ~ name, () { call_back(); this._exitSuccessfully(); });
        this.on("option:" ~ name, (string str) {
            call_back(str);
            this._exitSuccessfully();
        });
        this.on("option:" ~ name, (string[] strs) {
            call_back(strs);
            this._exitSuccessfully();
        });
        return this;
    }

    Self _optionImpl(T, bool isMandatory = false)(string flags, string desc)
            if (isOptionValueType!T) {
        auto option = createOption!T(flags, desc);
        option.makeOptionMandatory(isMandatory);
        return this.addOption(option);
    }

    Self _optionImpl(string flags, string desc) {
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

    Self option(T)(string flags, string desc) {
        return _optionImpl!(T)(flags, desc);
    }

    Self option(string flags, string desc) {
        return _optionImpl(flags, desc);
    }

    Self requiredOption(T)(string flags, string desc) {
        return _optionImpl!(T, true)(flags, desc);
    }

    Self requireOption(string flags, string desc) {
        return _optionImpl!(bool, true)(flags, desc);
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
        opt.found = true;
        return this;
    }

    Self setOptionVal(Source src : Source.Cli, T:
        string)(string key, T[] values) {
        assert(values.length);
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

    void parse(in string[] argv) {
        auto user_argv = _prepareUserArgs(argv);
        _parseCommand(user_argv);
    }

    string[] _prepareUserArgs(in string[] args) {
        auto arr = args.filter!(str => str.length).array;
        this._selfPath = arr[0];
        this.rawFlags = arr.dup;
        return args[1 .. $].dup;
    }

    void _parseCommand(in string[] unknowns) {
        auto parsed = this.parseOptions(unknowns);
        this.argFlags = parsed[0];
        this.unknownFlags = parsed[1];
        this.parseArguments(parsed[0]);
        this.parseOptionsEnv();
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
        if (this.subCommand)
            this.subCommand._parseCommand(parsed[1]);
        else
            this.emit("action:" ~ this._name);
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
                assert(value.length);
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
                    if (arg == "-h" || arg == "help") {
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
                        this.emit("option:" ~ copt.name);
                        continue;
                    }
                }
            }

            if (arg.length > 2 && arg[0] == '-' && arg[1] != '-') {
                Option opt = _findOption("-" ~ arg[1]);
                string name = opt.name;
                if (opt) {
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
                        _args.insertInPlace(0, arg[2 .. $]);
                    }
                    else {
                        this.error("invalid value: `" ~ arg[2 .. $] ~ "` for bool option " ~ opt
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
                        this.error("invalid value: `" ~ value ~ "` for bool option " ~ opt.flags);
                    continue;
                }
            }

            if (auto _cmd = find_cmd(arg)) {
                writeln("CMD_NAME:\t", _cmd._name);
                this.subCommand = _cmd;
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
        string message = format("error: option '%s' argument missing", opt.flags);
        this.error(message);
    }

    void unknownOption(string flag) const {
        string suggestion = "";
        string[] candidate_flags = [];
        auto cmd = this;
        const(string)[] more_flags;
        auto hlp = cmd._helpConfiguration;
        if (flag[0 .. 2] == "--" && this._showSuggestionAfterError) {
            more_flags = hlp.visibleOptions(cmd).map!(opt => opt.longFlag).array;
            candidate_flags ~= more_flags;
        }
        else if (flag[0] == '-' && this._showSuggestionAfterError) {
            more_flags = hlp.visibleOptions(cmd).filter!(opt => !opt.shortFlag.empty)
                .map!(opt => opt.shortFlag)
                .array;
            candidate_flags ~= more_flags;
        }
        suggestion = suggestSimilar(flag, candidate_flags);
        auto msg = format("error: unknown option `%s` %s", flag, suggestion);
        this.error(msg, "command.unknownOption");
    }

    void excessArguments() const {
        if (!this._allowExcessArguments) {
            this.error("too much args!!!");
        }
    }

    void _checkMissingMandatoryOption() const {
        auto f = this._options.filter!(opt => opt.mandatory && !opt.settled).empty;
        if (!f)
            throw new CMDLineError;
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
                        throw new CMDLineError;
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
                throw new CMDLineError;
        });
        this.args = this._arguments
            .filter!((Argument arg) { return !(arg.isOptional && !arg.isValid); })
            .map!((Argument arg) { arg.initialize; return arg.get; })
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
                Option opt = _findOption(name);
                if (opt && !opt.isValid)
                    opt.implyVal(value);
                if (opt && (opt.source == Source.Default)) {
                    opt.settled = false;
                    opt.implyVal(value);
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
        // next time to finish  it;
    }

    Self name(string str) {
        this._name = str;
        return this;
    }

    string name() const {
        return this._name.idup;
    }

    Self setVersion(string str, string flags = "", string desc = "") {
        assert(!this._versionOption);
        assert(!this._versionCommand);
        this._version = str;
        flags = flags == "" ? "-V, --version" : flags;
        desc = desc == "" ? "output the version number" : desc;
        auto vopt = createOption(flags, desc);
        if (auto help_opt = this._helpOption) {
            if (vopt.matchFlag(help_opt))
                throw new CMDLineError(format!"Cannot add option '%s'
                    due to confliction help option `%s`"(vopt.flags, help_opt.flags));
        }
        else if (this._addImplicitHelpOption && (vopt.shortFlag == "-h" || vopt.longFlag == "--help")) {
            throw new CMDLineError(format!"Cannot add option '%s'
                    due to confliction help option `%s`"(vopt.flags, "-h, --help"));
        }
        if (auto config_opt = this._configOption) {
            if (vopt.matchFlag(config_opt))
                throw new CMDLineError(format!"Cannot add option '%s'
                    due to confliction config option `%s`"(vopt.flags, config_opt.flags));
        }
        this._versionOption = vopt;
        string vname = this._versionOption.name;
        this.on("option:" ~ vname, () {
            this._outputConfiguration.writeOut(this._version ~ "\n");
            this._exitSuccessfully();
        });
        Command cmd = createCommand(vname).description(
            "output the version number");
        cmd.setHelpCommand(false);
        cmd.setHelpCommand(false);
        if (auto help_cmd = this._helpCommand) {
            auto help_cmd_name_arr = help_cmd._aliasNames ~ help_cmd._name;
            auto none = help_cmd_name_arr.find!(
                name => vname == name).empty;
            if (!none) {
                string help_cmd_names = help_cmd_name_arr.join("|");
                throw new CMDLineError(
                    format!"cannot add command `%s` as this command name cannot be same as
                        the name of help command `%s`"(
                        vname, help_cmd_names));
            }
        }
        else if (this._addImplicitHelpCommand) {
            string help_cmd_names = "help";
            if (vname == help_cmd_names) {
                throw new CMDLineError(
                    format!"cannot add command `%s` as this command name cannot be same as
                        the name of help command `%s`"(
                        vname, help_cmd_names));
            }
        }
        this.on("command:" ~ vname, () {
            this._outputConfiguration.writeOut(this._version ~ "\n");
            this._exitSuccessfully();
        });
        ActionCallback fn = (args, optMap) {
            this._outputConfiguration.writeOut(this._version ~ "\n");
            this._exitSuccessfully();
        };
        cmd.parent = this;
        cmd.action(fn);
        this._versionCommand = cmd;
        return this;
    }

    string getVersion() const {
        return this._version.idup;
    }

    Self setHelpCommand(string flags = "", string desc = "") {
        assert(!this._helpCommand);
        flags = flags == "" ? "help [command]" : flags;
        desc = desc == "" ? "display help for command" : desc;
        Command help_cmd = createCommand!(string)(flags, desc);
        help_cmd.setHelpOption(false);
        help_cmd.setHelpCommand(false);
        string hname = help_cmd._name;
        if (auto verison_cmd = this._versionCommand) {
            auto version_cmd_name_arr = verison_cmd._aliasNames ~ verison_cmd._name;
            auto none = version_cmd_name_arr.find!(name => hname == name).empty;
            if (!none) {
                string version_cmd_names = version_cmd_name_arr.join("|");
                throw new CMDLineError(
                    format!"cannot add command `%s` as this command name cannot be same as
                        the name of version command `%s`"(
                        hname, version_cmd_names));
            }
        }
        ActionCallback fn = (args, optMap) {
            if (args.length) {
                auto sub_cmd_name = args[0].get!string;
                auto sub_cmd = this._findCommand(sub_cmd_name);
                sub_cmd.help();
            }
            this.help();
        };
        help_cmd.parent = this;
        help_cmd.action(fn);
        this._helpCommand = help_cmd;
        return setHelpCommand(true);
    }

    Self setHelpCommand(bool enable) {
        this._addImplicitHelpCommand = enable;
        return this;
    }

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
                throw new CMDLineError(
                    format!"cannot add command `%s` as this command name cannot be same as
                        the name of version command `%s`"(
                        hnames.join("|"), version_cmd_names));
            }
        }
        cmd.parent = this;
        this._helpCommand = cmd;
        return setHelpCommand(true);
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
        assert(!this._helpOption);
        flags = flags == "" ? "-h, --help" : flags;
        desc = desc == "" ? "display help for command" : desc;
        auto hopt = createOption(flags, desc);
        if (auto config_opt = this._configOption) {
            if (hopt.matchFlag(config_opt))
                throw new CMDLineError(format!"Cannot add option '%s'
                    due to confliction config option `%s`"(hopt.flags, config_opt.flags));
        }
        if (auto version_opt = this._versionOption) {
            if (hopt.matchFlag(version_opt))
                throw new CMDLineError(format!"Cannot add option '%s'
                    due to confliction version option `%s`"(hopt.flags, version_opt.flags));
        }
        this._helpOption = hopt;
        this.on("option:" ~ hopt.name, () { this.help(); });
        return setHelpOption(true);
    }

    Self setHelpOption(bool enable) {
        this._addImplicitHelpOption = enable;
        return this;
    }

    Self addHelpOption(Option option) {
        assert(!this._helpOption);
        this._helpOption = option;
        this.on("option:" ~ option.name, () { this.help(); });
        return setHelpOption(true);
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
            this._exitErr("(outputHelp)", "command.help");
        this._exit(0);
    }

    Self addHelpText(AddHelpPos pos, string text) {
        assert(this._addImplicitHelpCommand || this._addImplicitHelpOption);
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

    Self action(ActionCallback fn) {
        auto listener = () {
            ArgVariant[] args;
            OptionVariant[string] opts;
            if (this.args)
                args = this.args;
            else
                this.args = args = this._arguments
                    .filter!(arg => arg.settled)
                    .map!(arg => arg.get)
                    .array;
            if (this.opts)
                opts = this.opts;
            else
                this.opts = opts = this._options
                    .filter!(opt => opt.settled)
                    .map!(opt => tuple(opt.name, opt.get))
                    .assocArray;
            fn(args, opts);
            this._exitSuccessfully();
        };
        this._actionHandler = listener;
        this.on("action:" ~ this._name, () {
            if (this._actionHandler)
                this._actionHandler();
        });
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
        if (prev_arg && prev_arg.isOptional && argument.isRequired) {
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

    void _exitErr(string msg, string code = "") const {
        auto fn = this._exitCallback;
        if (fn)
            fn(new CMDLineError(msg, 1, code));
        this._exit(1);
    }

    void _exitSuccessfully() const {
        _exit(0);
    }

    void _exit(ubyte exitCode) const {
        import core.stdc.stdlib : exit;

        exit(exitCode);
    }

    void error(string msg = "", string code = "command.error", ubyte exitCode = 1) const {
        this._outputConfiguration.writeErr(msg ~ "\n");
        if (this._showHelpAfterError) {
            this._outputConfiguration.writeErr("\n");
            this.outputHelp(true);
        }
        this._exitErr(msg, code);
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

unittest {
    Command program = createCommand("program");
    program.setVersion("0.0.1");
    program.allowExcessArguments(false);
    program.option("-f, --first <num>", "test", 13);
    program.option("-s, --second <num>", "test", 12);
    program.argument("[multi]", "乘数", 4);
    program.action((args, optMap) {
        auto fnum = optMap["first"].get!int;
        auto snum = optMap["second"].get!int;
        int multi = 1;
        if (args.length)
            multi = args[0].get!int;
        writeln("ACTION:\t", (fnum + snum) * multi);
    });

    program.parse(["program"]);
}
