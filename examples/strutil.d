module examples.strutil;

import std.stdio;
import std.string;
import std.regex;
import std.range;
import std.array : array;
import std.format;
import std.process;
import cmdline;

mixin template ConfigCmd() {
    mixin BEGIN;
    mixin DESC!("CLI to some string utilities");
    mixin VERSION!("0.0.1");

    mixin CONFIG;
    mixin PASS_THROUGH;

    mixin SUB_CMD!(JoinResult, SplitResult, ReplaceResult);

    mixin DEF!(
        "flag", bool,
        Flag_d!"-f",
        Desc_d!"the global flag"
    );

    mixin DEF!(
        "greet", string,
        Flag_d!"-g [greeting]",
        Desc_d!"set the greeting string",
        Default_d!"hi!",
        Preset_d!"hello!",
        Negate_d!("-G", "opposite to `--greet`"),
        ExportAs_d!("-x", "-y", "-z", "--xyz"),
        N_ExportAs_d!("-X", "-Y", "-Z", "--XYZ")
    );

    mixin END;
}

mixin template ConfigSplitCmd() {
    mixin BEGIN;
    mixin ALIAS!("spl");
    mixin DESC!("Split a string into substrings and display as an array.");

    mixin DEF!(
        "str", string,
        Desc_d!"string to split"
    );

    mixin DEF!(
        "separator", string,
        Flag_d!"-s <char>",
        Desc_d!"separator character",
        Default_d!",",
        ToArg_d,
    );

    mixin END;

    void action() {
        StrutilResult* parent = this.getParent!StrutilResult;
        writeln(parent.flag ? true : false);
        writeln(parent.greet ? parent.greet.get : "no greeting");
        string s = str.get;
        string sp = separator.get;
        writeln(split(s, sp));
    }
}

mixin template ConfigJoinCmd() {
    mixin BEGIN;
    mixin ALIAS!("jr");
    mixin DESC!("Join the command-arguments into a single string.");

    mixin DEF!(
        "strs", string[],
        Desc_d!"one or more string"
    );

    mixin DEF!(
        "separator", string,
        Flag_d!"-s <char>",
        Desc_d!"separator character",
        Default_d!","
    );

    mixin END;

    void action() {
        StrutilResult* parent = this.getParent!StrutilResult;
        writeln(parent.flag ? true : false);
        writeln(parent.greet ? parent.greet.get : "no greeting");
        auto ss = strs.get;
        auto sp = separator.get;
        writeln(ss.join(sp));
    }
}

mixin template ConfigReplaceCmd() {
    mixin BEGIN;
    mixin ALIAS!("rpl");
    mixin DESC!("Replace the specified string with new string on a string");

    mixin DEF_ARG!(
        "str", string,
        Desc_d!"the string that would be mutated"
    );

    mixin DEF_OPT!(
        "ptr", string, "-p <ptr>",
        Desc_d!"the pattern to search for",
        ToArg_d
    );

    mixin DEF_OPT!(
        "rpl", string, "-r <replacent>",
        Desc_d!"the replacent string",
        ToArg_d
    );

    OptVal!(bool, "-i") igc;
    mixin DESC_OPT!(igc, "ignore the lower and upper cases");

    OptVal!(bool, "-g") glb;
    mixin DESC_OPT!(glb, "global search all the satisfied string");

    OptVal!(bool, "-m") mlt;
    mixin DESC_OPT!(mlt, "allow multipule line search");

    OptVal!(bool, "-c") cmp;
    mixin DESC_OPT!(cmp, "show the comparision");

    mixin END;

    void action() {
        StrutilResult* parent = this.getParent!StrutilResult;
        writeln(parent.flag ? true : false);
        writeln(parent.greet ? parent.greet.get : "no greeting");
        string _str = this.str.get;
        string _ptr = this.ptr.get;
        string _rstr = this.rpl.get;
        string _igc = this.igc ? "i" : "";
        string _glb = this.glb ? "g" : "";
        string _mlt = this.mlt ? "m" : "";
        version (Windows) {
            enum os_num = 0;
        }
        else version (Posix) {
            enum os_num = 1;
        }
        bool is_cmp = this.cmp && os_num;
        auto fmt = `\033[36m%s\033[0m`;
        auto fn = (Captures!string m) {
            string tmp = '_'.repeat.take(m.hit.length).array;
            return _rstr.length
                ? (is_cmp ? format(fmt, _rstr) : _rstr) : (is_cmp ? format(fmt, tmp) : tmp);
        };
        auto pattern = regex(_ptr, join([_igc, _glb, _mlt], ""));
        string new_str = replace!(fn)(_str, pattern);
        auto ostr = is_cmp ? format("echo -e \"%s\"", new_str) : format("echo \"%s\"", new_str);
        auto result = executeShell(ostr);
        write(result.output);
    }
}

struct SplitResult {
    mixin ConfigSplitCmd;
}

struct JoinResult {
    mixin ConfigJoinCmd;
}

struct ReplaceResult {
    mixin ConfigReplaceCmd;
}

struct StrutilResult {
    mixin ConfigCmd;
}

void main(in string[] argv) {
    argv.run!StrutilResult;
}