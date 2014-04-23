__EOF__

module kameloso.plugins.automode;

import kameloso.plugins.common;


final:


class Automode : IrcPlugin {
private:
	IrcBot _bot;
	bool[64] done = true;
	Tid me;

public:
	this(IrcBot bot_)
	{
		_bot = bot_;
		me = thisTid;

		alias d = done;
		with (IrcEvent.Type) {
			d[JOIN]  = false;
			d[QUERY] = false;
			d[CHAN_MSG]   = false;
		}

		writeln("Automode plugin loaded.");
	}

	const string name() @property @safe pure nothrow
	{
		return "Automode";
	}

	void bot(ref IrcBot bot_) nothrow @safe
	{
		_bot = bot_;
	}

	ref IrcBot bot() nothrow @property @safe
	{
		return _bot;
	}

	bool wants(IrcEvent.Type type)
	{
		return (type > done.length)
			? false
			: !done[type];
	}

	void process(const ref IrcEvent evt) {
		mixin(ScopeMixin!failure);

		with (evt) with (IrcEvent.Type)
		switch (type) {

		case JOIN:
		case CHAN_MSG:
		case QUERY:
			break;

		default:
			return;
		}
	}
}
