module kameloso.plugins.waiter;

import std.algorithm : canFind;
import kameloso.plugins.common;

final:

private alias IrcCommand = Command!(IrcEvent,IrcEvent.Type);

class Waiter : IrcPlugin
{
private:
	Yarn!string yarn;
	Tid tid;

final:
	static const bool wants(IrcEvent.Type type) @safe pure nothrow
	{
		with (IrcEvent.Type)
		switch (type) {

		case CHAN_MSG:
		case QUERY:
		case WHOIS_LOGIN:
		case JOIN:
		case PART:
		case QUIT:
		//case WHOIS_END:  // TODO: add command removal?
			return true;

		default:
			return false;

		}
	}

final:
	void onCommand(IrcBotState state, in IrcEvent evt)
	{
		if (!state.allow(evt))
			return;

		scope(failure) {
			yarn.put("onCommand failure on ");
			evt.fill(yarn)
			   .clearprint();
			return;
		}

		import std.string;

		auto realContent  = evt.content.strip();
		auto wordBoundary = realContent.indexOf(' ');
		string powerword;

		if (wordBoundary < 0) {
			powerword   = realContent.toLower();
			realContent = null;
		}
		else {
			powerword   = realContent[0..wordBoundary].toLower();
			realContent = realContent[wordBoundary+1..$].stripLeft();
		}

		auto realTarget = (evt.type == IrcEvent.Type.QUERY)
			? evt.sender
			: evt.channel;

		yarn.put("POWERWORD: ")
			.put(powerword)
			.clearprint();

		switch (powerword) {

		case "raw":
		case "sudo":
			if (state.userIsMaster(evt.sender)) {
				tid.send(true, realContent);
			}
			break;

		case "hunch":
			import std.algorithm : startsWith;
			yarn.put("gonna hunch")
				.clearprint();

			//realContent = realContent.strip;  // <-- done already
			auto also = realContent.munch("^ ");

			yarn.put("also:'")
				.put(also)
				.put('\'')
				.clearprint();

			if (!also.length || !also.toLower.startsWith(powerword))
				break;

			yarn.put("yay, matches!")
				.clearprint();

			also = also[powerword.length..$];
			auto tail = also.munch("^!?.");
			if (tail) {
				yarn.put("has tail... '")
					.put(tail)
					.put("'")
					.clearprint();
				//break;
			}

			tid.send(true, yarn
				.put("PRIVMSG ")
				.put(realTarget)
				.put(" :what whaaat")
				.consume()
			);
			break;

		case "deop":
		case "op":
		case "voice":
		case "devoice":
			if (evt.type == IrcEvent.Type.QUERY) {
				tid.send(true, yarn
					.put("PRIVMSG ")
					.put(realTarget)
					.put(" :this is not a channel, nab")
					.consume()
				);
				break;
			}

			if (evt.channel != state.bot.homechan) {
				yarn.put("channel mismatch; ")
					.put(evt.channel)
					.put(" != ")
					.put(state.bot.homechan)
					.clearprint();
				break;
			}

			yarn.put("content:'")
				.put(realContent)
				.put("'")
				.clearprint();

			size_t num = (realContent.length)
				? (realContent.countchars(" ") + 1)
				: 0;

			auto sign = (powerword[0..2] == "de")
				? "-" //'-'
				: "+"; //'+';

			yarn.put("SIGN IS '")
				.put(sign)
				.put('\'')
				.clearprint();

			auto letter = (powerword[$-2..$] == "ce")
				? 'v' //'v'
				: 'o'; //'o';

			yarn.put("sign:'")
				.put(sign)
				.put('\'')
				.clearprint();
			yarn.put("letter:'")
				.put(letter)
				.put('\'')
				.clearprint();

			import std.range : repeat;
			import kameloso.string : plurality;

			yarn.put("num is ")
				.put(num)
				.clearprint();

			string whom = (num > 0)
				? realContent
				: evt.sender;

			auto pronoun = num.plurality("nab", "nabs");

			yarn.put("seems like we gotta ")
				.put(powerword)
				.put(" some ")
				.put(num)
				.put(' ')
				.put(pronoun)
				.put(": ")
				.put(whom)
				.clearprint();
			/*yarn.put("seems like we gotta %s some %d %s: %s"
				.format(powerword, num, num.plurality("nab", "nabs"), targets))
				.clearprint();*/

			tid.send(true, yarn
				.put("MODE ")
				.put(evt.channel)
				.put(' ')
				.put(sign)
				.put(letter.repeat(num+1))
				.put(' ')
				.put(whom)
				.consume()
			);
			break;

		case "join":
		case "part":
			if (!state.userIsMaster(evt.sender))
				break;

			import std.array : join;
			import std.algorithm : splitter;
			//import std.uni   : splitter;

			tid.send(true, yarn
				.put(powerword.toUpper())
				.put(' ')
				.put(realContent
					.strip()
					.splitter(' ')
					.join(","))
				.consume()
			);
			break;

		case "dance!":
		case "dance":
			if ((evt.channel != state.bot.homechan) && !state.userIsMaster(evt.sender))
				break;

			yarn.put("PRIVMSG ")
				.put(realTarget)
				.put(" ::D-");

			tid.send(true, yarn.tempAppend(r"/-<").idup);
			tid.send(true, yarn.tempAppend(r"\-<").idup);
			tid.send(true, yarn.tempAppend(r"|-<").idup);
			tid.send(true, yarn.tempAppend(r"S-<").idup);
			tid.send(true, yarn.tempAppend(r">-<").idup);
			yarn.clear();

			break;

		case "sethome":
			if (!state.userIsMaster(evt.sender))
				break;

			auto chan = realContent;  // merely an alias

			if (!chan.length || (chan[0] != '#'))
				break;

			state.bot.homechan = chan;
			yarn.put("new home: ")
				.put(chan)
				.clearprint();
			tid.send(state.bot);
			break;

		case "resetterm":
			if (!state.userIsMaster(evt.sender))
				break;

			import std.stdio : write;
			write(cast(char)15);
			yarn.put("terminal reset (by outputting char 15)")
				.clearprint();
			break;

		case "say":
		case "säg":
			tid.send(true, yarn
				.put("PRIVMSG ")
				.put(realTarget)
				.put(" :")
				.put(realContent)
				.consume()
			);
			break;

		default:
			yarn.put("ignoring unknown ")
				.put(powerword)
				.clearprint();
			break;
		}
	}

public:
	this()
	{
		tid = thisTid;
		writeln("Waiter plugin loaded.");
	}

	@property const string name() const @safe pure nothrow
	{
		return "Waiter";
	}

	void process(IrcBotState state, in IrcEvent evt) {
		if (!wants(evt.type))
			return;

		scope(failure) {
			yarn.put("Waiter process failure on ");
			evt.fill(yarn)
			   .clearprint();
			return;
		}

		with (IrcEvent.Type)
		switch (evt.type) {

		case CHAN_MSG:
			if ((evt.channel != state.bot.homechan) && !state.userIsMaster(evt.sender))
				break;

			import std.string : /*startsWith,*/ munch;
			//if (!evt.content.startsWith(state.bot.nickname))
            if ((evt.content.length < state.bot.nickname.length) ||
                (evt.content[0..state.bot.nickname.length] != state.bot.nickname))
				break;

            yarn
                .put("message started with bot nickname! (")
                .put(state.bot.nickname)
                .put(')')
                .clearprint();

            yarn.put(evt.content[0..state.bot.nickname.length]).clearprint();

			// new struct because of argument const-correctness
			IrcEvent newEvt = evt;
			newEvt.content = evt.content[state.bot.nickname.length..$].strip();
			newEvt.content.munch("?:!~;> ");  // TODO: remove munch
			return onCommand(state, newEvt);
			//break;

		case JOIN:
			if ((evt.channel != state.bot.homechan) || !state.allow(evt))
				break;

			// FIXME: move to automode plugin!
			tid.send(true, yarn
				.put("MODE ", evt.channel, " +o ", evt.sender)
				.consume()
			);
			break;

		case PART:
			if (evt.channel != state.bot.homechan)
				break;

			goto case QUIT;

		case QUIT:
			state.users.remove(evt.sender);  // expensive if in lots of channels :/
			break;

		case WHOIS_LOGIN:
			auto nick = evt.aux;
			auto login = evt.content;
			if (!Friends.canFind(login))
				break;

			auto guy = nick in state.users;
            bool altered;

			if (guy is null) {
				state.users[nick] = IrcUser(nick);
				guy = nick in state.users;  // ugh
				yarn.put("wasn't registered in users[]") //", is now tho")
					.clearprint();
                altered = true;
			}

			if (!guy.login) {
				guy.login = login;
				yarn.put("noted ")
					.put(nick)
					.put(" as having login ")
					.put(login)
					.clearprint();
                altered = true;
			}

			if (altered)
                tid.send(*guy);

			break;

		case QUERY:
			return onCommand(state, evt);

		default:
			break;
		}
	}

}
