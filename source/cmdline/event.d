module cmdline.event;

import std.stdio;
import cmdline.command;

alias EventCallbaclk_1 = void delegate();
alias EventCallbaclk_2 = void delegate(string val, string[] val...);
alias EventCallbaclk_3 = void delegate(bool isErrMode);

struct EventFn {
    EventCallbaclk_1 _fn1;
    EventCallbaclk_2 _fn2;
    EventCallbaclk_3 _fn3;

    void opCall() const {
        _fn1();
    }

    void opCall(string val, string[] vals...) const {
        _fn2(val, vals);
    }

    void opCall(bool isErrMode) const {
        _fn3(isErrMode);
    }

    auto opAssign(EventCallbaclk_1 value) {
        this._fn1 = value;
        return this;
    }

    auto opAssign(EventCallbaclk_2 value) {
        this._fn2 = value;
        return this;
    }

    auto opAssign(EventCallbaclk_3 value) {
        this._fn3 = value;
        return this;
    }
}

class EventManager {
private:
    EventFn[string] eventMap;

public:
    alias Self = typeof(this);

    Self on(string eventName, EventCallbaclk_1 callback) {
        auto ptr = eventName in eventMap;
        assert(!ptr);
        EventFn fn;
        eventMap[eventName] = fn = callback;
        return this;
    }

    Self on(string eventName, EventCallbaclk_2 callback) {
        auto ptr = eventName in eventMap;
        assert(!ptr);
        EventFn fn;
        eventMap[eventName] = fn = callback;
        eventMap[eventName] = callback;
        return this;
    }

    Self on(string eventName, EventCallbaclk_3 callback) {
        auto ptr = eventName in eventMap;
        assert(!ptr);
        EventFn fn;
        eventMap[eventName] = fn = callback;
        eventMap[eventName] = callback;
        return this;
    }

    bool emit(string eventName, string val, string[] vals...) const {
        auto fn_ptr = eventName in eventMap;
        if (!fn_ptr)
            return false;
        auto fn = *fn_ptr;
        fn(val, vals);
        return true;
    }

    bool emit(string eventName) const {
        auto fn_ptr = eventName in eventMap;
        if (!fn_ptr)
            return false;
        auto fn = *fn_ptr;
        fn();
        return true;
    }

    bool emit(string eventName, bool isErrMode) const {
        auto fn_ptr = eventName in eventMap;
        if (!fn_ptr)
            return false;
        auto fn = *fn_ptr;
        fn(isErrMode);
        return true;
    }

    bool remove(string eventName) {
        return this.eventMap.remove(eventName);
    }
}

unittest {
    import std.conv;

    int count = 0;
    bool fn1_called, fn2_called;

    EventManager em = new EventManager;

    em.on("fn1", () { count += 12; fn1_called = true; });
    em.on("fn2", () { count -= 12; fn2_called = true; });
    em.emit("fn1");
    em.emit("fn2");
    assert(!count && fn1_called && fn2_called);
}
