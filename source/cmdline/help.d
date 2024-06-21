module cmdline.help;

import std.algorithm;
import std.array;
import std.string : stripRight;
import std.regex;
import std.format;
import std.typecons;
import std.uni;
import std.range;

import cmdline.pattern;
import cmdline.option;
import cmdline.argument;
import cmdline.command;
import core.stdcpp.array;

class Help {
    int helpWidth = 80;

    bool sortSubCommands = false;
    bool sortOptions = false;
    bool showGlobalOptions = false;

    inout(Command)[] visibleCommands(inout(Command) cmd) const {
        Command cmd_tmp = cast(Command) cmd;
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
        visible_opts ~= cmd._abandons.filter!(opt => !opt.hidden).array;
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
        foreach (cmd; ancestor_cmd) {
            visible_opts ~= (cmd._options).filter!(opt => !opt.hidden).array;
            visible_opts ~= cmd._abandons.filter!(opt => !opt.hidden).array;
        }
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
        return command._arguments;
    }

    string subCommandTerm(in Command cmd) const {
        auto args_str = "";
        if (cmd._arguments.length)
            args_str = cmd._arguments.map!(arg => arg.readableArgName).join(" ");
        return (
            cmd._name ~
                (cmd._aliasNames.empty ? "" : "|" ~ cmd._aliasNames[0]) ~
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
            return max(mn, cast(int) subCommandTerm(command).length);
        })(0, visibleCommands(cmd));
    }

    int longestOptionTermLength(in Command cmd) const {
        int opt_len = reduce!((int mn, opt) {
            return max(mn, cast(int) optionTerm(opt).length);
        })(0, visibleOptions(cmd));

        int nopt_len = reduce!((int mn, opt) {
            return max(mn, cast(int) optionTerm(opt).length);
        })(0, visibleNegateOptions(cmd));

        return max(opt_len, nopt_len);
    }

    int longestGlobalOptionTermLength(in Command cmd) const {
        int opt_len = reduce!((int mn, opt) {
            return max(mn, cast(int) optionTerm(opt).length);
        })(0, visibleGlobalOptions(cmd));

        int nopt_len = reduce!((int mn, opt) {
            return max(mn, cast(int) optionTerm(opt).length);
        })(0, visibleGlobalNegateOptions(cmd));

        return max(opt_len, nopt_len);
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
        string[] info = [opt.description];
        auto type_str = opt.typeStr();
        auto choices_str = opt.choicesStr();
        auto default_str = opt.defaultValStr();
        auto preset_str = opt.presetStr();
        auto env_str = opt.envValStr();
        auto imply_str = opt.implyOptStr();
        auto conflict_str = opt.conflictOptStr();
        auto rangeof_str = opt.rangeOfStr();
        info ~= type_str;
        info ~= default_str;
        info ~= env_str;
        info ~= preset_str;
        info ~= rangeof_str;
        info ~= choices_str;
        info ~= imply_str;
        info ~= conflict_str;
        return info.filter!(str => !str.empty).join('\n');
    }

    string optionDesc(in NegateOption opt) const {
        return opt.description;
    }

    string argumentDesc(in Argument arg) const {
        string[] info = [arg.description];
        auto type_str = arg.typeStr;
        auto default_str = arg.defaultValStr;
        auto rangeof_str = arg.rangeOfStr;
        auto choices_str = arg.choicesStr;
        info ~= type_str;
        info ~= default_str;
        info ~= rangeof_str;
        info ~= choices_str;
        return info.filter!(str => !str.empty).join('\n');
    }

    string subCommandDesc(in Command cmd) const {
        return cmd.description;
    }

    int paddWidth(in Command cmd) const {
        auto lg_opl = longestOptionTermLength(cmd);
        auto lg_gopl = longestGlobalOptionTermLength(cmd);
        auto lg_scl = longestSubcommandTermLength(cmd);
        auto lg_arl = longestArgumentTermLength(cmd);
        return max(
            lg_opl,
            lg_gopl,
            lg_scl,
            lg_arl
        );
    }

    string formatHelp(in Command cmd) const {
        auto term_width = paddWidth(cmd);
        auto item_indent_width = 2;
        auto item_sp_width = 2;

        auto format_item = (string term, string desc) {
            if (desc != "") {
                string padded_term_str = term;
                if (term_width + item_sp_width > term.length) {
                    auto pad_num = term_width + item_sp_width - term.length;
                    string space = ' '.repeat(pad_num).array;
                    padded_term_str = term ~ space;
                }
                auto full_text = padded_term_str ~ desc;
                return this.wrap(
                    full_text,
                    this.helpWidth - item_indent_width,
                    term_width + item_sp_width);
            }
            return term;
        };

        auto format_list = (string[] textArr) {
            return textArr.join("\n").replaceAll(regex(`^`, "m"), "  ");
        };

        string[] output = ["Usage: " ~ this.commandUsage(cmd), ""];

        string cmd_desc = this.commandDesc(cmd);
        if (cmd_desc.length > 0) {
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

    string wrap(string str, int width, int indent) const {
        if (!matchFirst(str, PTN_MANUALINDENT).empty)
            return str;
        auto text = str[indent .. $].replaceAll(regex(`\s+(?=\n|$)`), "");
        auto leading_str = str[0 .. indent];
        int col_width = width - indent;
        string indent_str = repeat(' ', indent).array;
        string ex_indent_str = "  ";
        string[] col_texts = text.split('\n').filter!(s => s.length).array;
        auto get_front = () => col_texts.length ? col_texts.front : "";
        string[] tmp;
        string cur_txt = get_front();
        if (cur_txt.length)
            col_texts.popFront;
        int cur_max_width = col_width;
        bool is_ex_ing = cur_txt.length > cur_max_width;
        if (is_ex_ing) {
            col_texts.insertInPlace(0, cur_txt[cur_max_width .. $]);
            cur_txt = cur_txt[0 .. cur_max_width];
        }
        tmp ~= cur_txt;
        while ((cur_txt = get_front()).length) {
            col_texts.popFront;
            bool flag = is_ex_ing;
            cur_max_width = is_ex_ing ? col_width - 2 : col_width;
            is_ex_ing = cur_txt.length > cur_max_width;
            if (is_ex_ing) {
                col_texts.insertInPlace(0, cur_txt[cur_max_width .. $]);
                cur_txt = cur_txt[0 .. cur_max_width];
            }
            tmp ~= flag ? ex_indent_str ~ indent_str ~ cur_txt : indent_str ~ cur_txt;
        }
        return leading_str ~ tmp.join("\r\n");
    }
}

private:

enum int maxDistance = 3;

int _editDistance(string a, string b) {
    assert(max(a.length, b.length) < 20);
    int xy = cast(int) a.length - cast(int) b.length;
    if (xy < -maxDistance || xy > maxDistance) {
        return cast(int) max(a.length, b.length);
    }
    int[20][20] dp = (int[20][20]).init;
    for (int i = 0; i <= a.length; i++)
        dp[i][0] = i;
    for (int i = 0; i <= b.length; i++)
        dp[0][i] = i;
    int cost = 0;
    for (int i = 1; i <= a.length; i++) {
        for (int j = 1; j <= b.length; j++) {
            if (a[i - 1] == b[j - 1])
                cost = 0;
            else
                cost = 1;
            dp[i][j] = min(dp[i - 1][j] + 1, dp[i][j - 1] + 1, dp[i - 1][j - 1] + cost);
        }
    }
    return dp[a.length][b.length];
}

public:

string suggestSimilar(string word, in string[] _candidates) {
    if (!_candidates || _candidates.length == 0)
        return "";
    auto searching_opts = word[0 .. 2] == "--";
    string[] candidates;
    if (searching_opts) {
        word = word[2 .. $].idup;
        candidates = _candidates.map!(candidate => candidate[2 .. $].idup).array;
    }
    else {
        candidates = _candidates.dup;
    }
    string[] similar = [];
    int best_dist = maxDistance;
    double min_similarity = 0.4;
    candidates.each!((string candidate) {
        if (candidates.length <= 1)
            return No.each;
        double dist = _editDistance(word, candidate);
        double len = cast(double) max(word.length, candidate.length);
        double similarity = (len - dist) / len;
        if (similarity > min_similarity) {
            if (dist < best_dist) {
                best_dist = cast(int) dist;
                similar ~= candidate;
            }
            else if (dist == best_dist) {
                similar ~= candidate;
            }
        }
        return Yes.each;
    });
    similar.sort!((a, b) => a.toLower < b.toLower);
    if (searching_opts) {
        similar.each!((ref str) { str = "--" ~ str; });
    }
    if (similar.length > 1)
        return format("\n(Did you mean one of %s?)", similar.join(", "));
    if (similar.length == 1)
        return format("\n(Did you mean %s?)", similar[0]);
    return "";
}

unittest {
    import std.stdio;

    writeln("===:", suggestSimilar("--son", [
        "--sone", "--sans", "--sou", "--don"
    ]));
    assert(_editDistance("kitten", "sitting") == 3);
    assert(_editDistance("rosettacode", "raisethysword") == 8);
    assert(_editDistance("", "") == 0);
    assert(_editDistance("kitten", "") == 6);
    assert(_editDistance("", "sitting") == 7);
    assert(_editDistance("kitten", "kitten") == 0);
    assert(_editDistance("meow", "woof") == 3);
    assert(_editDistance("woof", "meow") == 3);
}

// unittest {

//     Command program = createCommand("program");
//     program.allowExcessArguments(false);
//     program.setVersion("0.0.1");

//     Option opt = createOption!string("-g, --greeting <str>");
//     program.addActionOption(opt, (string[] vals...) {
//         writeln("GREETING:\t", vals[0]);
//     });
//     program.option("-f, --first <num>", "test", 13);
//     program.option("-s, --second <num>", "test", 12);
//     program.argument("[multi]", "乘数", 4);
//     program.action((args, optMap) {
//         auto fnum = optMap["first"].get!int;
//         auto snum = optMap["second"].get!int;
//         int multi = 1;
//         if (args.length)
//             multi = args[0].get!int;
//         writeln(format("%4d * (%4d + %4d) = %4d", multi, fnum, snum, (fnum + snum) * multi));
//     });

//     program
//         .command("list")
//         .aliasName("ls")
//         .argument("[dir-path]", "dir path", ".")
//         .option("-a, --all", "do not ignore entries starting with .")
//         .option("-l, --long", "use a long listing format")
//         .option("-s, --size", "print the allocated size of each file, in blocks", true)
//         .action((args, opts) {
//             auto dir = args[0].get!string;
//             string l, a, s;
//             if ("all" in opts)
//                 a = opts["all"].get!bool ? "-a" : a;
//             if ("long" in opts)
//                 l = opts["long"].get!bool ? "-l" : l;
//             if ("size" in opts)
//                 s = opts["size"].get!bool ? "-s" : s;
//             auto flags = (["ls"] ~ [l, a, s, dir]).filter!(str => str.length).array.join(" ");
//             writeln("RUNNING:\t", flags);
//             auto result = executeShell(flags);
//             writeln(result[1]);
//         });

//     program
//         .command!(string, string)("greet <name> [greetings...]")
//         .aliasName("grt")
//         .action((args, opts) {
//             string name = args[0].get!string;
//             string[] greetings;
//             if (args.length > 1) {
//                 greetings = args[1].get!(string[]);
//             }
//             writeln(format("hello %s, %s", name, greetings.join(", ")));
//         });

//     Option header_opt = createOption!string("-H, --header <header-str>");
//     header_opt.env("HEADER");

//     program
//         .command("calculate")
//         .aliasName("cal")
//         .argument("tag", "tag", "Tag")
//         .option!int("-m, --multi <value>", "multi value")
//         .option!int("-n, --nums <numbers...>", "numbers value")
//         .addOption(header_opt)
//         .action((args, opts) {
//             int multi = opts["multi"].get!int;
//             int[] nums = opts["nums"].get!(int[]);
//             string tag = args[0].get!string;
//             string header = opts["header"].get!string;
//             int result = reduce!((a, b) => a + b)(0, nums) * multi;
//             string nums_str = nums.map!(n => n.to!string).join(" + ");
//             writefln("HEADER:\t%8s", header);
//             writeln(format("%8s: %d * (%s) = %d", tag, multi, nums_str, result));
//         });

//     Help help = new Help;
// }
