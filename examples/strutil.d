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
    mixin DESC!("CLI to some string utilities");
    mixin VERSION!("0.0.1");

    mixin CONFIG;
    mixin PASS_THROUGH;

    JoinResult* joinSub;
    SplitResult* splitSub;
    ReplaceResult* replaceSub;

    OptVal!(bool, "-f") flag;
    mixin DESC_OPT!(flag, "the global flag");

    OptVal!(string, "-g [greeting]") greet;
    mixin DESC_OPT!(greet, "set the greeting string");
    mixin PRESET!(greet, "hello!");
    mixin DEFAULT!(greet, "hi!");

    mixin NEGATE!(greet, "-G", "opposite to `--greet`");
}

mixin template ConfigSplitCmd() {
    mixin BEGIN;
    mixin ALIAS!("spl");
    mixin DESC!("Split a string into substrings and display as an array.");

    ArgVal!string str;
    mixin DESC!(str, "string to split");

    OptVal!(string, "-s <char>") separator;
    mixin DESC!(separator, "separator character");
    mixin DEFAULT!(separator, ",");

    mixin OPT_TO_ARG!(separator);
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

    ArgVal!(string[]) strs;
    mixin DESC!(strs, "one or more string");

    OptVal!(string, "-s <char>") separator;
    mixin DESC!(separator, "separator character");
    mixin DEFAULT!(separator, ",");
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

    ArgVal!string str;
    mixin DESC!(str, "the string that would be mutated");

    OptVal!(string, "-p <ptr>") ptr;
    mixin DESC_OPT!(ptr, "the pattern to search for");

    OptVal!(string, "-r <replacent>") rpl;
    mixin DEFAULT!(rpl, "");
    mixin DESC_OPT!(rpl, "the replacent string");

    OptVal!(bool, "-i") igc;
    mixin DESC_OPT!(igc, "ignore the lower and upper cases");

    OptVal!(bool, "-g") glb;
    mixin DESC_OPT!(glb, "global search all the satisfied string");

    OptVal!(bool, "-m") mlt;
    mixin DESC_OPT!(mlt, "allow multipule line search");

    OptVal!(bool, "-c") cmp;
    mixin DESC_OPT!(cmp, "show the comparision");

    mixin OPT_TO_ARG!(ptr, rpl);
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

// void main(in string[] argv) {
//     StrutilResult output = parse!StrutilResult(argv);
//     if (const(JoinResult)* jr = output.subResult!JoinResult) {
//         jr.action(jr.separator.get, jr.strs.get);
//     }
//     else if (const(SplitResult)* spl = output.subResult!SplitResult) {
//         spl.action(spl.separator.get, spl.str.get);
//     }
//     else if (const(ReplaceResult)* rpl = output.subResult!ReplaceResult) {
//         string str = rpl.str.get;
//         string ptr = rpl.ptr.get;
//         string rstr = rpl.rpl.get;
//         string igc = rpl.igc.isValid ? "i" : "";
//         string glb = rpl.glb.isValid ? "g" : "";
//         string mlt = rpl.mlt.isValid ? "m" : "";
//         version (Windows) {
//             enum os_num = 0;
//         }
//         else version (Posix) {
//             enum os_num = 1;
//         }
//         bool is_cmp = rpl.cmp.isValid && os_num;
//         auto fmt = `\033[36m%s\033[0m`;
//         auto fn = (Captures!string m) {
//             string tmp = '_'.repeat.take(m.hit.length).array;
//             return rstr.length
//                 ? (is_cmp ? format(fmt, rstr) : rstr) : (is_cmp ? format(fmt, tmp) : tmp);
//         };
//         auto pattern = regex(ptr, join([igc, glb, mlt], ""));
//         string new_str = replace!(fn)(str, pattern);
//         auto ostr = is_cmp ? format("echo -e \"%s\"", new_str) : format("echo \"%s\"", new_str); 
//         auto result = executeShell(ostr);
//         write(result.output);
//     }
// }

// unittest {
//     static struct MyStruct {
//         static void* em;

//         void action(StrutilResult* parent) {
//             assert(parent.joinSub is null);
//             assert(parent.replaceSub is null);
//             assert(parent.splitSub is null);
//             writeln("action");
//         }

//         void run() {
//             writeln("run");
//             action(cast(StrutilResult*) this.em);
//         }
//     }

//     MyStruct ms;
//     ms.em = new StrutilResult;
//     ms.run;
//     string[] argv = ["strutil", "spl"];
//     StrutilResult* output = parse!StrutilResult(argv);
//     if (JoinResult* jr = output.subResult!JoinResult) {
//         jr.action(jr.separator.get, jr.strs.get);
//     }
//     else if (const(SplitResult)* spl = output.subResult!SplitResult) {
//         spl.action(spl.separator.get, spl.str.get);
//     }
//     else if (const(ReplaceResult)* rpl = output.subResult!ReplaceResult) {
//         string str = rpl.str.get;
//         string ptr = rpl.ptr.get;
//         string rstr = rpl.rpl.get;
//         string igc = rpl.igc.isValid ? "i" : "";
//         string glb = rpl.glb.isValid ? "g" : "";
//         string mlt = rpl.mlt.isValid ? "m" : "";
//         version (Windows) {
//             enum os_num = 0;
//         }
//         else version (Posix) {
//             enum os_num = 1;
//         }
//         bool is_cmp = rpl.cmp.isValid && os_num;
//         auto fmt = `\033[36m%s\033[0m`;
//         auto fn = (Captures!string m) {
//             string tmp = '_'.repeat.take(m.hit.length).array;
//             return rstr.length
//                 ? (is_cmp ? format(fmt, rstr) : rstr) : (is_cmp ? format(fmt, tmp) : tmp);
//         };
//         auto pattern = regex(ptr, join([igc, glb, mlt], ""));
//         string new_str = replace!(fn)(str, pattern);
//         auto ostr = is_cmp ? format("echo -e \"%s\"", new_str) : format("echo \"%s\"", new_str);
//         auto result = executeShell(ostr);
//         write(result.output);
//     }
// }
