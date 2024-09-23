module examples.json_reader;

import cmdline;

import std.stdio;
import std.file;
import std.path;
import std.json;
import std.format;

// void main(in string[] argv) {
//     program.name("jread");
//     program.argument!string("<file-name>", "the file name you want to parse");
//     program.argument!string("[key]", "the key of the json object");
//     program.option("-p, --pretty", "set the output is human readable", true);
//     program.option("-P, --no-pretty", "disable pretty output");

//     Option mopt = createOption!string("-m, --mode <mode>", "set the parsing mode");
//     mopt.choices("doNotEscapeSlashes", "escapeNonAsciiChars", "none",
//         "specialFloatLiterals", "strictParsing");
//     mopt.defaultVal("none");

//     program.addOption(mopt);

//     program.action((opts, fname, _key) {
//         string current_dir = getcwd();
//         string file_name = cast(string) fname;
//         bool is_pretty = opts("pretty").get!bool;
//         string mode = cast(string) opts("mode");
//         string key = _key.isValid ? _key.get!string : "";
//         string f = buildPath(current_dir, file_name);

//         JSONValue jsconfig;
//         JSONOptions jmode;

//         try {
//             string str = readText(f);
//             jsconfig = parseJSON(str);
//             switch (mode) {
//             case JSONOptions.doNotEscapeSlashes.stringof:
//                 jmode = JSONOptions.doNotEscapeSlashes;
//                 break;
//             case JSONOptions.escapeNonAsciiChars.stringof:
//                 jmode = JSONOptions.escapeNonAsciiChars;
//                 break;
//             case JSONOptions.none.stringof:
//                 jmode = JSONOptions.none;
//                 break;
//             case JSONOptions.specialFloatLiterals.stringof:
//                 jmode = JSONOptions.specialFloatLiterals;
//                 break;
//             default:
//                 jmode = JSONOptions.strictParsing;
//                 break;
//             }
//             if (key == "")
//                 writeln(toJSON(jsconfig, is_pretty, jmode));
//             else {
//                 if (jsconfig.type != JSONType.OBJECT) {
//                     throw new JReadError(
//                         "ERRROR: the target root json is not `" ~ JSONType.OBJECT.stringof ~ "`");
//                 }
//                 auto ptr = key in jsconfig;
//                 if (!ptr)
//                     throw new JReadError(
//                         format!"ERRROR: the key: `%s` not found in the target root json"(key));
//                 writeln(toJSON(*ptr, is_pretty, jmode));
//             }
//         }
//         catch (JReadError e) {
//             stderr.writeln(e.msg);
//             stderr.writeln("Here is the target root json: ");
//             stderr.writeln(toJSON(jsconfig, is_pretty, jmode));
//         }
//         catch (Exception e) {
//             stderr.writeln(e.msg);
//         }
//     });

//     program.parse(argv);
// }

// class JReadError : Error {
//     this(string msg, Throwable nextInChain = null) pure nothrow @nogc @safe {
//         super(msg, nextInChain);
//     }
// }

struct JreadResult {
    mixin BEGIN;
    mixin DESC!"read the data from json file";
    mixin VERSION!"0.0.1";

    mixin DEF_ARG!(
        "fileName", string,
        Desc_d!"the file name you want to parse"
    );

    mixin DEF_ARG!(
        "key", string,
        Optional_d,
        Desc_d!"the key of the json object"
    );

    mixin DEF_OPT!(
        "pretty", bool, "-p",
        Desc_d!"set the output is human readable",
        Negate_d!("-P", "disable pretty output")
    );

    mixin DEF_OPT!(
        "mode", string, "-m <mode>",
        Desc_d!"set the parsing mode",
        Choices_d!("doNotEscapeSlashes", "escapeNonAsciiChars", "none", "specialFloatLiterals", "strictParsing"),
        Default_d!"none"
    );

    mixin END;

    void action() {
        auto cur_dir = getcwd();
        auto file_name = fileName.get;
        auto is_pretty = pretty.get;
        auto mode_ = mode.get;
        auto key_ = key ? key.get : "";
        auto f = buildPath(cur_dir, file_name);

        JSONValue jsconfig;
        JSONOptions jmode;

        try {
            string str = readText(f);
            jsconfig = parseJSON(str);
            switch (mode_) {
            case JSONOptions.doNotEscapeSlashes.stringof:
                jmode = JSONOptions.doNotEscapeSlashes;
                break;
            case JSONOptions.escapeNonAsciiChars.stringof:
                jmode = JSONOptions.escapeNonAsciiChars;
                break;
            case JSONOptions.none.stringof:
                jmode = JSONOptions.none;
                break;
            case JSONOptions.specialFloatLiterals.stringof:
                jmode = JSONOptions.specialFloatLiterals;
                break;
            default:
                jmode = JSONOptions.strictParsing;
                break;
            }
            if (key_ == "")
                writeln(toJSON(jsconfig, is_pretty, jmode));
            else {
                if (jsconfig.type != JSONType.OBJECT) {
                    throw new JReadError(
                        "ERRROR: the target root json is not `" ~ JSONType.OBJECT.stringof ~ "`");
                }
                auto ptr = key_ in jsconfig;
                if (!ptr)
                    throw new JReadError(
                        format!"ERRROR: the key: `%s` not found in the target root json"(key_));
                writeln(toJSON(*ptr, is_pretty, jmode));
            }
        }
        catch (JReadError e) {
            stderr.writeln(e.msg);
            stderr.writeln("Here is the target root json: ");
            stderr.writeln(toJSON(jsconfig, is_pretty, jmode));
        }
        catch (Exception e) {
            stderr.writeln(e.msg);
        }
    }
}

class JReadError : Error {
    this(string msg, Throwable nextInChain = null) pure nothrow @nogc @safe {
        super(msg, nextInChain);
    }
}

void main(in string[] argv) {
    argv.run!JreadResult;
}
