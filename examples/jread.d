module examples.json_reader;

import cmdline;

import std.stdio;
import std.file;
import std.path;
import std.json;
import std.format;

void main(in string[] argv) {
    program.name("jread");
    program.argument!string("<file-name>", "the file name you want to parse");
    program.argument!string("[key]", "the key of the json object");
    program.option("-p, --pretty", "set the output is human readable", true);
    program.option("-P, --no-pretty", "disable pretty output");

    Option mopt = createOption!string("-m, --mode <mode>", "set the parsing mode");
    mopt.choices("doNotEscapeSlashes", "escapeNonAsciiChars", "none",
        "specialFloatLiterals", "strictParsing");
    mopt.defaultVal("none");

    program.addOption(mopt);

    program.action((opts, fname, _key) {
        string current_dir = getcwd();
        string file_name = cast(string) fname;
        bool is_pretty = opts("pretty").get!bool;
        string mode = cast(string) opts("mode");
        string key = _key.isValid ? _key.get!string : "";
        string f = buildPath(current_dir, file_name);

        JSONValue jsconfig;
        JSONOptions jmode;

        try {
            string str = readText(f);
            jsconfig = parseJSON(str);
            switch (mode) {
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
            if (key == "")
                writeln(toJSON(jsconfig, is_pretty, jmode));
            else {
                if (jsconfig.type != JSONType.OBJECT) {
                    throw new JReadError(
                        "ERRROR: the target root json is not `" ~ JSONType.OBJECT.stringof ~ "`");
                }
                auto ptr = key in jsconfig;
                if (!ptr)
                    throw new JReadError(
                        format!"ERRROR: the key: `%s` not found in the target root json"(key));
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
    });

    program.parse(argv);
}

class JReadError : Error {
    this(string msg, Throwable nextInChain = null) pure nothrow @nogc @safe {
        super(msg, nextInChain);
    }
}
