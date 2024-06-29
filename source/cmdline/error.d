/++
$(H2 The Error Types for Cmdline)
Authors: 笑愚(xiaoyu)
+/
module cmdline.error;

/// the error occurs when configuring the cmd-line or parsing the command line in debug mode
class CMDLineError : Error {
    enum string name = typeof(this).stringof;

    string code;
    ubyte exitCode;

    this(string msg = "", ubyte exitCode = 1, string code = "", Throwable nextInChain = null) pure nothrow @nogc @safe {
        super(msg, nextInChain);
        this.exitCode = exitCode;
        this.code = code;
    }
}

/// the error about argument.
/// the error would be caputured then throw `CMDLineError` when parsing the command line
/// or not captured when configuring argument
class InvalidArgumentError : CMDLineError {
    enum string name = typeof(this).stringof;

    this(string msg = "", string code = "") {
        super(msg, 1, code);
    }
}

/// the error about option
/// the error would be captured the throw `CMDLineError` when parsing the command line
/// or not captured when configuring option
class InvalidOptionError : CMDLineError {
    enum string name = typeof(this).stringof;

    this(string msg = "", string code = "") {
        super(msg, 1, code);
    }
}

/// deprecated
class InvalidFlagError : CMDLineError {
    enum string name = typeof(this).stringof;

    this(string msg = "") {
        super(msg, 1, "CMDLine."~name);
    }
}

/// deprecated
class ImplyOptionError : CMDLineError {
    enum string name = typeof(this).stringof;

    this(string msg = "") {
        super(msg, 1, "CMDLine."~name);
    }
}

/// deprecated
class OptionFlagsError : CMDLineError {
    enum string name = typeof(this).stringof;

    this(string msg = "") {
        super(msg, 1, "CMDLine."~name);
    }
}

/// deprecated
class OptionMemberFnCallError : CMDLineError {
    enum string name = typeof(this).stringof;

    this(string msg = "") {
        super(msg, 1, "CMDLine."~name);
    }
}