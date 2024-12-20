/++
$(H2 The Help Type for Cmdline)

This modlue mainly has `Help` Type.
We can change it to control the behaviors 
of the cmd-line program's help command and help option

Authors: 笑愚(xiaoyu)
+/
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

class Help {
    /// the help print's max coloum width
    int helpWidth = 80;
    /// whether sort the sub commands on help print
    bool sortSubCommands = false;
    /// whether sort the options on help print
    bool sortOptions = false;
    /// whether show global options, which is not recommended to turn on it
    bool showGlobalOptions = false;

    /// get the list of not hidden sub commands
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

    /// get the list of not hidden options
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

    /// get the list of not hidden negate options
    inout(NegateOption)[] visibleNegateOptions(inout(Command) command) const {
        auto cmd = cast(Command) command;
        auto visible_opts = (cmd._negates).filter!(opt => !opt.hidden).array;
        if (this.sortOptions) {
            return cast(inout(NegateOption[])) visible_opts.sort!((a, b) => a.name < b.name).array;
        }
        return cast(inout(NegateOption[])) visible_opts;
    }

    /// get the list of not hidden global options
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

    /// get the list of not hidden global negate options 
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

    inout(T)[string] visibleInheritOptions(T)(inout(Command) command) const
    if (is(T == Option) || is(T == NegateOption)) {
        static if (is(T == Option)) {
            auto im = cast(T[string]) command._import_map;
        }
        else {
            auto im = cast(T[string]) command._import_n_map;
        }
        T[string] ex;
        T[string] ph;
        if (command.parent) {
            static if (is(T == Option)) {
                ex = cast(T[string]) command.parent._export_map;
                auto opt_seq = cast(T[]) command.parent._options;
            }
            else {
                ex = cast(T[string]) command.parent._export_n_map;
                auto opt_seq = cast(T[]) command.parent._negates;
            }
            if (command.parent._passThroughOptionValue) {
                foreach (opt; opt_seq) {
                    if (opt.shortFlag.length)
                        ph[opt.shortFlag] = opt;
                    if (opt.longFlag.length)
                        ph[opt.longFlag] = opt;
                }
            }
        }
        T[string[]] n_im = cast(T[string[]]) mergeKeys(im);
        typeof(n_im) n_ex = cast(T[string[]]) mergeKeys(ex);
        typeof(n_im) n_ph = cast(T[string[]]) mergeKeys(ph);
        typeof(n_im) imex;
        foreach (keys, value; n_im) {
            imex[keys] = value;
        }
        foreach (keys, value; n_ex) {
            imex[keys] = value;
        }
        foreach (keys, value; n_ph) {
            imex[keys] = value;
        }
        string[][T] r_imex;
        T[string] result;
        foreach (keys, value; imex) {
            if (r_imex.byKey.canFind!(v => v is value)) {
                r_imex[value] ~= cast(string[]) keys;
            }
            else {
                r_imex[value] = cast(string[]) keys;
            }
        }
        foreach (value, keys; r_imex) {
            if (value.hidden)
                continue;
            auto comp = (in string a, in string b) {
                if (a.startsWith("--") && !b.startsWith("--"))
                    return true;
                else if (!a.startsWith("--") && !b.startsWith("--"))
                    return false;
                return a < b;
            };
            result[keys.sort!(comp).uniq.join(", ")] = value;
        }
        return cast(inout(T)[string]) result;
    }

    private inout(T)[string[]] mergeKeys(T)(inout(T)[string] im) const
    if (is(T == Option) || is(T == NegateOption)) {
        string[][T] r_im;
        T[string[]] n_im;
        foreach (key, value; im) {
            if (r_im.byKey.canFind!(v => v is value)) {
                r_im[cast(T) value] ~= key;
            }
            else {
                r_im[cast(T) value] = [key];
            }
        }
        foreach (value, keys; r_im) {
            n_im[cast(immutable string[]) keys] = value;
        }
        return cast(inout(T)[string[]]) n_im;
    }

    /// get the list of arguments
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

package:
    string subCommandTerm(in Command cmd) const {
        auto args_str = "";
        if (cmd._arguments.length)
            args_str = cmd._arguments.map!(arg => arg.readableArgName).join(" ");
        return (
            cmd._name ~
                (cmd._aliasNames.empty ? "" : "|" ~ cmd._aliasNames[0]) ~
                (cmd._options.empty ? "" : " [options]") ~
                (args_str == "" ? args_str : " " ~ args_str) ~
                (cmd._execHandler ? " >> " ~ cmd._usage : "")
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

    int longestInheritOptionsTermLength(in Command cmd) const {
        int opt_len = reduce!((int mn, kv) {
            return max(mn, cast(int) kv.key.length);
        })(0, visibleInheritOptions!Option(cmd).byKeyValue);
        int nopt_len = reduce!((int mn, kv) {
            return max(mn, cast(int) kv.key.length);
        })(0, visibleInheritOptions!NegateOption(cmd).byKeyValue);
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

    /// get the usage of command
    public string commandUsage(in Command cmd) const {
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
        return "description: " ~ opt.description;
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
        auto lg_ihl = longestInheritOptionsTermLength(cmd);
        return max(
            lg_opl,
            lg_gopl,
            lg_scl,
            lg_arl,
            lg_ihl
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

        if (!cmd._defaultCommandName.empty) {
            string str = format("default sub command is `%s`", cmd._defaultCommandName);
            output ~= [this.wrap(str, this.helpWidth, 0), ""];
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

        string[] inherit_opt_list = visibleInheritOptions!Option(cmd).byKeyValue.map!(
            kv => format_item(kv.key, optionDesc(kv.value))).array;
        string[] inherit_nopt_list = visibleInheritOptions!NegateOption(cmd).byKeyValue.map!(
            kv => format_item(kv.key, optionDesc(kv.value))).array;
        inherit_opt_list ~= inherit_nopt_list;
        if (inherit_opt_list.length) {
            output ~= [
                format("Inherit Options from Command `%s`:",
                    cmd.parent._name ~ (cmd.parent._aliasNames.empty ? "" : "|" ~ cmd.parent._aliasNames[0])),
                format_list(inherit_opt_list), ""
            ];
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

package:

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
