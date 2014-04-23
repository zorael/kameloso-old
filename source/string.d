module kameloso.string;

import kameloso.common;

import std.traits   : isSomeString, isNumeric; //, hasMember;
import std.typecons : Unqual;


enum yarnDefaultSize = 1024;


final:


bool isPlainNumeral(T)(T chars) @safe pure nothrow
if (isSomeString!T)
{
	if (!chars.length)
		return false;

	foreach (c; chars) {
		auto code = cast(size_t) c;
		if ((code < 48) || (code > 57))
			return false;
	}
	return true;
}


string plurality(T = string)(size_t n, T singular, T plural) @safe pure nothrow
if (isSomeString!T)
{
	return ((n == 1) || (n == -1)) ? singular : plural;
}


template isStringOrDerivative(String, Derivative, What)
{
	enum isStringOrDerivative =
		(is(Unqual!What: String) || is(Unqual!What : Derivative[]));
}


struct Yarn(T : qC[], size_t size = yarnDefaultSize, qC, C = Unqual!qC)
if (isSomeString!T)
{
@safe:
private:
	static if (stackYarn)
		C[size] arr;
	else
		C[] arr;

	size_t p;

	void putImpl(MaybeC)(MaybeC char_) pure nothrow
	if (is(Unqual!MaybeC : C))
	{
		arr[p++] = char_;
	}

	void putImpl(Arr)(Arr arr_) pure nothrow
	if (isStringOrDerivative!(T, C, Arr))
	{
		auto len = arr_.length;
		auto pre = p;
		p += len;
		arr[pre..p] = arr_[];
	}

	void putImpl(Other)(Other something) @system
	if (!is(Unqual!Other : T) && !is(Unqual!Other : C) && !isStringOrDerivative!(T, C, Other)) // || is(Unqual!Other : C[]) || is(Unqual!Other : C)))
	{
		putImpl(something.to!T);
	}

public:
	auto put(Args...)(Args args) @system
	{
		foreach (arg; args) {
			putImpl!(Unqual!(typeof(arg)))(arg);
		}
		return &this;
	}

	auto data() @property pure nothrow
	{
		return arr[0..p];
	}

	T consume() @property pure
	{
		auto p_ = p;
		p = 0;
		return arr[0..p_].idup;
	}

	void clearprint() @system
	{
		arr[0..p].writeln();
		p = 0;
	}

	T idup() @property pure
	{
		return arr[0..p].idup;
	}

	auto tempAppend(MaybeT)(MaybeT line) pure nothrow
	if (is(MaybeT : T))
	{
		auto len = line.length;
		auto end = (p + len);
		arr[p..end] = line[];
		return arr[0..end];
	}

	void clear(bool thorough = false)() pure nothrow
	{
		static if (thorough) {
			arr = typeof(arr).init;
		}
		p = 0;
	}

	alias length opDollar;
	const size_t length() @property pure nothrow
	{
		return p;
	}

	void opOpAssign(string op, SomeType)(SomeType stuff) pure nothrow
	if (op == "~")
	{
		_put(stuff);
	}

	void opAssign(Arr)(Arr arr_) pure nothrow
	if (is(Arr : T) || is(Arr : C[]))
	{
		p = 0;
		_put(arr_);
	}

	alias opCast!(char[]) opSlice;
	C[] opCast(A)() pure nothrow
	if (is(A : C[]))
	{
		return arr[0..p];
	}

	alias opCast!bool empty;
	bool opCast(B)() pure nothrow
	if (is(B : bool))
	{
		return (p == 0);
	}

	C[] opSlice(size_t lower, size_t upper) pure nothrow
	{
		return arr[lower..upper];
	}

	C opIndex(size_t i) pure nothrow
	{
		return arr[i];
	}

	unittest
	{
		Yarn!string y;
		y.put("asdf");
		assert(y.data == "asdf");
		y.clear();
		assert(y.empty);
		y.putln("asdf", 1, 2, 'c');
		auto newlineLen = "\n".length;
		assert(y.length == (7 + newLineLen));
		assert(y.consume == "asdf12c\n");
		assert(y.empty);
		y ~= [ "abc", "def", "ghi" ];
		y ~= [ 3.14, 3.85, 4.06 ];
		assert(y.data == "abcdefghi3.143.854.06");
		assert(y[8..11] == "i3.");
		assert(y[y.length] == y[$]);
		assert(y.idup == y.data);
		assert(y == true);
		y.clear();
		assert(y == false);
	}
}


T nomAt(size_t step = 1, T)(ref T arr, size_t i)
if (isSomeString!T)
{
	scope(exit) {
		arr = arr[i+step..$];
	}

	return arr[0..i];
}


T nom(size_t step = 1, T : qC[], qC, C = Unqual!qC)
	(ref T haystack, C needle)
if (isSomeString!T)
{
	import std.string : indexOf;
	ptrdiff_t i;

	scope(exit) {
		haystack = haystack[i+step..$];
	}

	i = haystack.indexOf(needle);
	return haystack[0..i];
}


T nom(size_t step = 1, T)(ref T arr)
if (isSomeString!T)
{
	return nom!step(arr, ' ');
}


unittest
{
	auto line = "asdf fdsa iii!999";

	auto bite = line.cheapMunch(' ');
    assert(bite == "asdf");
    assert(line == " fdsa iii!999");

    bite = line.cheapMunch('!');
    assert(bite == " fdsa iii");
    assert(line == "!99");
}
