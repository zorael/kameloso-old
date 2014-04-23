module kameloso.common;

public import std.concurrency;
public import core.thread;
public import std.stdio  : writeln, writefln, write, writef, stdout;
public import std.conv   : to, text;
public import std.array  : split;
public import std.string; // : format;

import std.typetuple : allSatisfy;


version = builderConcat;
version = useStreams;
version = stackYarn;

version(builderConcat) { enum builderConcat = true; } else { enum builderConcat = false; }
version(useStreams)		  { enum useStreams = true; } else { enum useStreams = false; }
version(stackYarn)		   { enum stackYarn = true; } else { enum stackYarn = false; }


enum invalidValue = size_t.max;


static immutable Friends = [
	"klarrt",
	"maku",
	"kameloso",
	"zorael",
	"fehuschluk"
];


enum : ubyte {
	success = 0x1 << 0,
	failure = 0x1 << 1,
	exit    = 0x1 << 2
}

enum : ubyte {
	shellSuccess = 0,
	shellFailure = 1,
	shellPanic   = 127
}


template ctFormat(string pattern, args...)
if (allSatisfy!(isValue,args))
{
	static immutable ctFormat = format(pattern, args);
}


template ctText(args...)
if (allSatisfy!(isValue,args))
{
	static immutable ctText = text(args);
}


template isValue(alias T) {
	static immutable isValue = !is(T);
}


template Tuple(T...) {
	alias T = Tuple;
}


final:


void ctWritefln(string pattern, args...)()
if (allSatisfy!(isValue,args))
{
	writefln(ctFormat!(pattern,args));
}


void ctWritef(string pattern, args...)()
if (allSatisfy!(isValue,args))
{
	writef(ctFormat!(pattern,args));
}


string ScopeMixin(ubyte states, string scopeName = "")()
if (!is(states) && (states & (success|failure|exit)))
{
	import std.string : text;
	char[] concat;

	static string scopeString(const string state) {
		import std.string : toLower, format;
		string header;

		static if (scopeName.length > 0)
			return `
// ScopeMixin
scope(` ~ state.toLower ~ `)
{
	"[%s] %s".writefln("` ~ scopeName ~ `", "` ~ state ~ `");
}
`;
		else
		{
			return `
// ScopeMixin
scope(` ~ state.toLower ~ `)
{
	import std.string;  // : indexOf;  // BUG #11939
	auto __dotPos = __FUNCTION__.indexOf('.');
	"[%s] %s".writefln(__FUNCTION__[(__dotPos+1)..$], "` ~ state ~ `");
}
`;
		}
	}

	static if (states & exit)
		concat ~= scopeString("exit");
	static if (states & success)
		concat ~= scopeString("success");
	static if (states & failure)
		concat ~= scopeString("FAILURE");

	return concat.idup;
}


static void printErrorValues(Values...)(const string desc, in ref Values vals) {
	// TODO: stringbuilder version for synchronized output
	writefln("[!!] %s", desc);
	foreach (val; vals) {
		writefln("     %-25s= %s", typeof(val).stringof, val);
	}
}


struct Command(T,C) {
	C category;
	T payload;
	int lives;

	@system bool function(ref T, in ref T) fn;

	this(C category_, T payload_, typeof(fn) fn_, int lives_ = 1)
	{
		category = category_;
		payload  = payload_;
		fn = fn_;
		lives = lives_;
	}

	bool opCast(T)()
	if (is(T : bool))
	{
		return (fn != null);
	}
}

