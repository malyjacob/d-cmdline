module cmdline.event;

import std.stdio;
import cmdline.command;

package:

alias EventCallback_1 = void delegate();
alias EventCallback_2 = void delegate(string val);
alias EventCallback_3 = void delegate(bool isErrMode);
alias EventCallback_4 = void delegate(string[] vals);

struct EventFn {
    EventCallback_1 _fn1;
    EventCallback_2 _fn2;
    EventCallback_3 _fn3;
    EventCallback_4 _fn4;

    void opCall() const {
        _fn1();
    }

    void opCall(string val) const {
        _fn2(val);
    }

    void opCall(bool isErrMode) const {
        _fn3(isErrMode);
    }

    void opCall(string[] vals) const {
        _fn4(vals);
    }

    auto opAssign(EventCallback_1 value) {
        this._fn1 = value;
        return this;
    }

    auto opAssign(EventCallback_2 value) {
        this._fn2 = value;
        return this;
    }

    auto opAssign(EventCallback_3 value) {
        this._fn3 = value;
        return this;
    }

    auto opAssign(EventCallback_4 value) {
        this._fn4 = value;
        return this;
    }

    auto get(T)() {
        static if (is(T == EventCallback_1))
            return this._fn1;
        static if (is(T == EventCallback_2))
            return this._fn2;
        static if (is(T == EventCallback_3))
            return this._fn3;
        static if (is(T == EventCallback_4))
            return this._fn4;
        else
            return null;
    }
}

class EventManager {
    EventFn[string] eventMap;
    alias Self = typeof(this);

    Self on(string eventName, EventCallback_1 callback) {
        auto ptr = eventName in eventMap;
        assert(!ptr || (*ptr)._fn1 is null);
        if (ptr) {
            eventMap[eventName] = callback;
            return this;
        }
        EventFn fn;
        eventMap[eventName] = fn = callback;
        return this;
    }

    Self on(string eventName, EventCallback_2 callback) {
        auto ptr = eventName in eventMap;
        assert(!ptr || (*ptr)._fn2 is null);
        if (ptr) {
            eventMap[eventName] = callback;
            return this;
        }
        EventFn fn;
        eventMap[eventName] = fn = callback;
        eventMap[eventName] = callback;
        return this;
    }

    Self on(string eventName, EventCallback_3 callback) {
        auto ptr = eventName in eventMap;
        assert(!ptr || (*ptr)._fn3 is null);
        if (ptr) {
            eventMap[eventName] = callback;
            return this;
        }
        EventFn fn;
        eventMap[eventName] = fn = callback;
        eventMap[eventName] = callback;
        return this;
    }

    Self on(string eventName, EventCallback_4 callback) {
        auto ptr = eventName in eventMap;
        assert(!ptr || (*ptr)._fn4 is null);
        if (ptr) {
            eventMap[eventName] = callback;
            return this;
        }
        EventFn fn;
        eventMap[eventName] = fn = callback;
        eventMap[eventName] = callback;
        return this;
    }

    bool emit(string eventName, string val) const {
        auto fn_ptr = eventName in eventMap;
        if (!fn_ptr)
            return false;
        auto fn = *fn_ptr;
        fn(val);
        return true;
    }

    bool emit(string eventName, string[] vals) const {
        auto fn_ptr = eventName in eventMap;
        if (!fn_ptr)
            return false;
        auto fn = *fn_ptr;
        fn(vals);
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

    bool removeEvent(string eventName) {
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
