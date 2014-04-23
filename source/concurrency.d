module kameloso.concurrency;

import std.traits : isSomeFunction, isDelegate, isFunctionPointer, hasMember;
import std.typetuple : EraseAll;

import
	kameloso.common,
	kameloso.string;


final:


Tid locateTid(const string threadName)
{
	static immutable retryDelay = 100.msecs;
	Tid found;

	foreach (i; 0..10) {
		found = locate(threadName);

		if (found != Tid.init)
			return found;
		if (i < 9) {
			Thread.sleep(retryDelay);
		}
	}

	// TODO: yarn version? none in scope
	writefln("[!!] could not locate thread by name '%s'", threadName);
	return Tid.init;
}


alias Imperative Imp;
struct Imperative
{
static:
	struct Subscribe {}
	struct Unsubscribe {}
	struct Abort {}
	struct Reconnect {}
}

alias Notification Notif;
struct Notification
{
static:
	struct Connected {}
	struct Disconnected {}
}


alias MessageAction MA;
struct MessageAction
{
static:
	template Lambda(alias fn, Args...)
	if (isDelegate!fn || isFunctionPointer!fn)
	{
		enum _caller = __FUNCTION__.split(".")[2];

		void fun(Args args)
		{
			// TODO: add yarn version?
			writefln("[%s] received %s which triggered an action!",
				_caller, Args.stringof);
			fn();
		}
	}


	template Redirect(alias someTid, Args...)
	if (is(typeof(someTid) : Tid))
	{
		void fun(Args args)
		{
			someTid.send(args);
		}
	}


	/+template Cascade(alias variable, Tids...)
	if (!is(variable) && !EraseAll!(Tid,typeof(Tids)).length)
	{
		//private static immutable _caller = __FUNCTION__.split(".")[2];

		deprecated
		void fun(typeof(variable) newVar)
		{
			if (variable == newVar)
				return;

			variable = newVar;

			/*auto len = Tids.length;
			writefln("[%s] CASCADING updated %s to %d other %s", _caller,
				typeof(variable).stringof, len, len.plurality("thread", "threads"));*/

			foreach (tid; Tids)
			if ((tid != Tid.init) && (tid != thisTid)) {
				tid.send(newVar);
			}
		}
	}+/


	template Update(alias variable)
	if (!is(variable))
	{
		void fun(typeof(variable) newVar) @safe nothrow
		{
			variable = newVar;
		}
	}


	template Print(T, bool prependCaller = true)
	if (builderConcat && hasMember!(T, "fill"))
	{
		enum _caller = __FUNCTION__.split(".")[2];

		void fun(in ref T val, ref Yarn!string yarn)
		{
			static if (prependCaller) {
				yarn
					.put('[')
					.put(_caller)
					.put("] ");
			}

			val.fill(yarn)
			   .clearprint();
		}
	}

	template Print(T, bool prependCaller = true)
	if (!builderConcat || !hasMember!(T, "fill"))
	{
		enum _caller = __FUNCTION__.split(".")[2];

		deprecated
		void fun(ref T val)
		{
			static if (prependCaller) {
				writeln("[", _caller, "] ", T.stringof, " = ", val.toString);
			}
			else {
				writeln(val.toString);
			}
		}
	}

	/+template Noop(T, alias fun)
	if (!is(fun) && isSomeString!(typeof(fun)))
	{
		mixin(ctFormat!("void %s(%s _nothing) @safe pure nothrow {}",
		                fun, Type.stringof));
	}+/
}


void setupThread(const string threadName)
{
	setMaxMailboxSize(thisTid, 0, OnCrowding.block);

	bool success = register(threadName, thisTid);
	if (!success) {
		writeln("THREAD SETUP NAME COLLISION: ", threadName);
		throw new Exception("THREAD SETUP NAME COLLISION: " ~ threadName);
	}

	//writefln("[%s] becoming mindful", threadName);
}


bool matchesTid(const string threadName, in ref Tid expected)
{
	Tid found = threadName.locateTid();

	if (found == expected)
		return true;

	auto what = (found == Tid.init)
		? " (it is Tid.init)"
		: null;

	writefln("[%s]: not the expected Tid%s", threadName, what);
		/*(found == Tid.init)
			? " (it is Tid.init)"
			: string.init);*/

	return false;
}


struct NamedThread {
	string id;
	Tid tid;

	private enum { retries = 5, retryDelayMillisecs = 100 }

	@property bool isSane()
	{
		foreach (i; 0..retries) {
			if ((tid == locate(id)) && (!id.register(tid))) {
				return true;
			}
			if (++i < retries) {
				Thread.sleep(retryDelayMillisecs.msecs);
			}
		}
		return false;
	}

	this(F, Args...)(string id_, F fun, Args args)
	{
		id = id_;
		tid = spawn(fun, args);
	}

	void shutdown()
	{
		try { tid.send(Imperative.Abort()); }
		catch {}
	}
}
