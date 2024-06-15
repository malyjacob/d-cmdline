module cmdline.help;

import std.algorithm;
import std.array;
import std.string : stripRight;
import std.regex;
import std.format;

import cmdline.pattern;
import cmdline.option;
import cmdline.argument;
import cmdline.command;

class Help {
    int helpWidth = 80;

    bool sortSubCommands = false;
    bool sortOptions = false;
    bool showGlobalOptions = false;

    inout(Command)[] visibleCommands(inout(Command) cmd) const {
        auto cmd_tmp = cast(Command) cmd;
        Command[] visible_cmds = cmd_tmp._commands.filter!(c => !c._hidden).array;
        auto help_cmd = cmd_tmp._getHelpCommand();
        auto version_cmd = cmd_tmp._versionCommand;
        if (help_cmd && !help_cmd._hidden) {
            visible_cmds ~= help_cmd;
        }
        if (version_cmd && !version_cmd._hidden) {
            visible_cmds ~= version_cmd;
        }
        if (this.sortSubCommands) {
            return cast(inout(Command[])) visible_cmds.sort!((a, b) => a.name < b.name).array;
        }
        return cast(inout(Command[])) visible_cmds;
    }

    inout(Option)[] visibleOptions(inout(Command) command) const {
        auto cmd = cast(Command) command;
        Option[] visible_opts = (cmd._options).filter!(opt => !opt.hidden).array;
        auto help_opt = cmd._getHelpOption();
        auto version_opt = cmd._versionOption;
        auto config_opt = cmd._configOption;
        if (help_opt && !help_opt.hidden)
            visible_opts ~= help_opt;
        if (version_opt && !version_opt.hidden)
            visible_opts ~= version_opt;
        if (config_opt && !config_opt.hidden)
            visible_opts ~= config_opt;
        if (this.sortOptions) {
            return cast(inout(Option[])) visible_opts.sort!((a, b) => a.name < b.name).array;
        }
        return cast(inout(Option[])) visible_opts;
    }

    inout(NegateOption)[] visibleNegateOptions(inout(Command) command) const {
        auto cmd = cast(Command) command;
        auto visible_opts = (cmd._negates).filter!(opt => !opt.hidden).array;
        if (this.sortOptions) {
            return cast(inout(NegateOption[])) visible_opts.sort!((a, b) => a.name < b.name).array;
        }
        return cast(inout(NegateOption[])) visible_opts;
    }

    inout(Option)[] visibleGlobalOptions(inout(Command) command) const {
        if (!this.showGlobalOptions)
            return [];
        auto cmds_global = command._getCommandAndAncestors();
        auto ancestor_cmd = (cast(Command[]) cmds_global)[1 .. $];
        Option[] visible_opts = [];
        foreach (cmd; ancestor_cmd)
            visible_opts ~= (cmd._options).filter!(opt => !opt.hidden).array;
        if (this.sortOptions) {
            return cast(inout(Option[])) visible_opts.sort!((a, b) => a.name < b.name).array;
        }
        return cast(inout(Option[])) visible_opts;
    }

    inout(NegateOption)[] visibleGlobalNegateOptions(inout(Command) command) const {
        if (!this.showGlobalOptions)
            return [];
        auto cmds_global = command._getCommandAndAncestors();
        auto ancestor_cmd = (cast(Command[]) cmds_global)[1 .. $];
        NegateOption[] visible_opts = [];
        foreach (cmd; ancestor_cmd)
            visible_opts ~= (cmd._negates).filter!(opt => !opt.hidden).array;
        if (this.sortOptions) {
            return cast(inout(NegateOption[])) visible_opts.sort!((a, b) => a.name < b.name).array;
        }
        return cast(inout(NegateOption[])) visible_opts;
    }

    inout(Argument)[] visibleArguments(inout(Command) command) const {
        if (command._argsDescription) {
            Command cmd = cast(Command) command;
            cmd._arguments.each!((arg) {
                if (arg.description == "") {
                    auto tmp = arg.name in cmd._argsDescription;
                    if (tmp)
                        arg.description = *tmp;
                }
            });
        }
        if (!command._arguments.find!(arg => arg.description != "").empty) {
            return command._arguments;
        }
        return [];
    }

    string subCommandTerm(in Command cmd) const {
        auto args_str = "";
        if (cmd._arguments.length)
            args_str = cmd._arguments.map!(arg => arg.readableArgName).join(" ");
        return (
            cmd._name ~
                (cmd._aliasNames.empty ? "" : cmd._aliasNames[0]) ~
                (cmd._options.empty ? "" : " [options]") ~
                (args_str == "" ? args_str : " " ~ args_str)
        );
    }

    string optionTerm(in Option opt) const {
        return opt.flags;
    }

    string optionTerm(in NegateOption opt) const {
        return opt.flags;
    }

    string argumentTerm(in Argument arg) const {
        return arg.name;
    }

    int longestSubcommandTermLength(in Command cmd) const {
        return reduce!((int mn, command) {
            return max(mn, cast(int) subCommandTerm(cmd).length);
        })(0, visibleCommands(cmd));
    }

    int longestOptionTermLength(in Command cmd) const {
        return reduce!((int mn, opt) {
            return max(mn, cast(int) optionTerm(opt).length);
        })(0, visibleOptions(cmd));
    }

    int longestGlobalOptionTermLength(in Command cmd) const {
        return reduce!((int mn, opt) {
            return max(mn, cast(int) optionTerm(opt).length);
        })(0, visibleGlobalOptions(cmd));
    }

    int longestArgumentTermLength(in Command cmd) const {
        return reduce!((int mn, arg) {
            return max(mn, cast(int) argumentTerm(arg).length);
        })(0, visibleArguments(cast(Command) cmd));
    }

    string commandUsage(in Command cmd) const {
        string cmd_name = cmd._name;
        if (!cmd._aliasNames.empty)
            cmd_name = cmd_name ~ "|" ~ cmd._aliasNames[0];
        string ancestor_name = "";
        auto tmp = cmd._getCommandAndAncestors();
        Command[] ancestor = (cast(Command[]) tmp)[1 .. $];
        ancestor.each!((c) { ancestor_name = c.name ~ " " ~ ancestor_name; });
        return ancestor_name ~ cmd_name ~ " " ~ cmd.usage;
    }

    string commandDesc(in Command cmd) const {
        return cmd.description;
    }

    string optionDesc(in Option opt) const {
        string[] extraInfo = [];
        auto type_str = opt.typeStr();
        auto choices_str = opt.choicesStr();
        auto default_str = opt.defaultValStr();
        auto preset_str = opt.presetStr();
        auto env_str = opt.envValStr();
        auto imply_str = opt.implyOptStr();
        auto conflict_str = opt.conflictOptStr();
        auto rangeof_str = opt.rangeOfStr();
        extraInfo ~= type_str;
        extraInfo ~= default_str;
        extraInfo ~= env_str;
        extraInfo ~= preset_str;
        extraInfo ~= rangeof_str;
        extraInfo ~= choices_str;
        extraInfo ~= imply_str;
        extraInfo ~= conflict_str;
        string str = extraInfo.filter!(str => !str.empty).join(", ");
        if (extraInfo.length)
            return opt.description ~ " " ~ str;
        return opt.description;
    }

    string optionDesc(in NegateOption opt) const {
        return opt.description;
    }

    string argumentDesc(in Argument arg) const {
        string[] extraInfo = [];
        auto type_str = arg.typeStr;
        auto default_str = arg.defaultValStr;
        auto rangeof_str = arg.rangeOfStr;
        auto choices_str = arg.choicesStr;
        extraInfo ~= type_str;
        extraInfo ~= default_str;
        extraInfo ~= rangeof_str;
        extraInfo ~= choices_str;
        string str = extraInfo.filter!(str => !str.empty).join(", ");
        if (extraInfo.length)
            return arg.description ~ " " ~ str;
        return arg.description;
    }

    string subCommandDesc(in Command cmd) const {
        return cmd.description;
    }

    int padWidth(in Command cmd) const {
        return max(
            longestGlobalOptionTermLength(cmd),
            longestGlobalOptionTermLength(cmd),
            longestSubcommandTermLength(cmd),
            longestArgumentTermLength(cmd)
        );
    }

    string formatHelp(in Command cmd) const {
        auto term_width = padWidth(cmd);
        auto item_indent_width = 2;
        auto item_sp_width = 2;

        auto format_item = (string term, string desc) {
            if (desc != "") {
                auto pad_num = term_width + item_sp_width - term.length;
                auto space = " ";
                for (int i = 1; i < pad_num; i++) {
                    space ~= space;
                }
                auto padded_term_str = term ~ space;
                auto full_text = padded_term_str ~ desc;
                return this.wrap(
                    full_text,
                    this.helpWidth - item_indent_width,
                    term_width + item_sp_width);
            }
            return term;
        };

        auto format_list = (string[] textArr) {
            return textArr.join("\n").replaceAll(regex("^", "m"), "  ");
        };

        string[] output = ["Usage: " ~ this.commandUsage(cmd), ""];

        string cmd_desc = this.commandDesc(cmd);
        if (cmd_desc.length) {
            output ~= [this.wrap(cmd_desc, this.helpWidth, 0), ""];
        }

        string[] arg_list = visibleArguments(cmd).map!(
            arg => format_item(argumentTerm(arg), argumentDesc(arg))).array;
        if (arg_list.length) {
            output ~= ["Arguments:", format_list(arg_list), ""];
        }

        string[] opt_list = visibleOptions(cmd).map!(
            opt => format_item(optionTerm(opt), optionDesc(opt))).array;
        string[] negate_list = visibleNegateOptions(cmd).map!(
            opt => format_item(optionTerm(opt), optionDesc(opt))).array;
        opt_list ~= negate_list;
        if (opt_list.length) {
            output ~= ["Options:", format_list(opt_list), ""];
        }

        if (this.showGlobalOptions) {
            string[] global_list = visibleGlobalOptions(cmd).map!(
                opt => format_item(optionTerm(opt), optionDesc(opt))).array;
            string[] nglobal_list = visibleGlobalNegateOptions(cmd).map!(
                opt => format_item(optionTerm(opt), optionDesc(opt))).array;
            global_list ~= nglobal_list;
            if (global_list.length) {
                output ~= ["Global Options:", format_list(global_list), ""];
            }
        }

        string[] cmd_list = visibleCommands(cmd).map!(
            c => format_item(subCommandTerm(c), subCommandDesc(c))).array;
        if (cmd_list.length) {
            output ~= ["Commands:", format_list(cmd_list), ""];
        }

        return output.join("\n");
    }

    string wrap(string str, int width, int indent, int minColumnWidth = 40) const {
        if (matchFirst(str, PTN_MANUALINDENT)[0] != "")
            return str;
        int col_width = width - indent;
        if (col_width < minColumnWidth)
            return str;
        auto leading_str = str[0 .. indent];
        auto col_text = str[indent .. $].replaceFirst(regex("\\r\\n"), "\n");
        auto indent_str = " ";
        for (int i = 1; i < indent; i++) {
            indent_str ~= indent_str;
        }
        string breaks = "\\s\u200B";
        auto re = regex(format("\\n|.{1, %d}([%s]|$)|[^%s]+?([%s]|$)",
                col_width - 1, breaks, breaks, breaks), "g");
        auto re_matches = col_text.matchAll(re);
        string[] lines = re_matches.empty ?
            [] : re_matches.map!(m => m.hit).array;
        string[] tmp = [];
        foreach (i, line; lines) {
            if (line == "\n")
                tmp ~= "";
            else
                tmp ~= (i > 0 ? indent_str : "") ~ stripRight(line);
        }
        return leading_str ~ tmp.join("\n");
    }
}
