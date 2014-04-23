module kameloso.main;

import
	kameloso.common,
	kameloso.irc,
	kameloso.connection,
	kameloso.mastermind;

final:


struct IrcBotDefaults {
static immutable:
	auto host   = "adams.freenode.net";
	ushort port = 6667;

	auto nickname = "kameloso";
	auto ident    = "NaN";
	auto fullname = "colin nutley";
	auto login    = "kameloso";
	//auto password = "";
	auto master   = "zorael";
	auto homechan = "#garderoben";
}


void printBanner(ref IrcBotState state) {
	ctWritefln!("kameloso bot! (built %s)\n", __DATE__);
	writeln(state);
}


private IrcBotState buildBot(string[] args) {
	import std.getopt;

	IrcBot bot;
	Server server;

	alias b = bot;
	alias s = server;
	alias d = IrcBotDefaults;

	s.host = d.host;
	s.port = d.port;

	b.nickname = d.nickname;
	b.ident    = d.ident;
	b.fullname = d.fullname;
	b.login    = d.login;
	//b.password = d.password;
	b.master   = d.master;
	b.homechan = d.homechan;

	with (bot) {
		try {
			getopt(args,
				"H|homechan", &b.homechan,
				"h|host",     &s.host,
				"i|ip",       &s.host,
				"s|server",   &s.host,
				"P|port",     &s.port,

				"n|nick",     &b.nickname,
				"I|ident",    &b.ident,
				"f|fullname", &b.fullname,
				"l|login",    &b.login,
				"p|password", &b.password,
				"m|master",   &b.master,
			);
		}
		catch (Exception e) {
			writeln(e.msg);
			return IrcBotState.init;
		}
	}

	return IrcBotState(server, bot);
}


int main(string[] args) {
    import core.memory : GC;
	bool success, retval;
	auto state = buildBot(args);

	assert(state.server.host.length && (state.server.port > 0));

	printBanner(state);

	auto m = mastermind(state);
	success = m.connect();
	if (!success) {
		return shellFailure;
	}

	GC.collect();  // because reasons
	retval = m.listen();
	writeln("main: FWIW asked to connect? ", retval);

	if (retval) {
		writeln("gonna reconnect, I think...");
		m.teardown();
		return main(args);
	}

	return retval;
}
