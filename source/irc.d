module kameloso.irc;

import std.encoding : isValid; //, sanitize;
import std.string   : indexOf;

import
	kameloso.common,
	kameloso.string,
	kameloso.connection,
	kameloso.concurrency;


final:


private IrcEvent toIrcEvent(string raw, ref IrcBotState state) {
	static IrcEvent parseBasic(string raw, ref IrcBotState state) {
		IrcEvent evt;
		// PING :cameron.freenode.net
		//     ^p
		// ERROR :Closing Link: 194.117.188.126 (Ping timeout: 264 seconds)
		//      ^p
		auto p      = raw.indexOf(' ');
		auto action = raw[0..p];

		raw = raw[p+2..$];
		// cameron.freenode.net
		// Closing Link: 194.117.188.126 (Ping timeout: 264 seconds)

		final switch (action) {

		case "PING":
			evt.type = IrcEvent.Type.PING;
			evt.sender = raw;
			break;

		case "ERROR":
			evt.type = IrcEvent.Type.ERROR;
			// Closing Link: 194.117.188.126 (Ping timeout: 264 seconds)
			//                               ^n
			auto n = raw.indexOf('(');

			if (n < 1) {
				throw new IrcParseFailureException(__FILE__, __LINE__,
					"Bad index n of whitespace when parsing ERROR event",
					n/*,
					orig,
					raw,
					evt*/
				);
			}

			evt.content = raw[0..n-1];
			evt.aux     = raw[n+1..$-1];
			break;
		}

		return evt;
	}

	if (raw[0] != ':')
		return parseBasic(raw, state);

	auto orig = raw;
	IrcEvent evt;

	/*scope(failure) {
		throw new IrcParseFailureException(__FILE__, __LINE__,
			"General parsing exception",
			orig,
			raw,
			evt);
	}*/

	// :zorael!~sunspire@2001:41d0:8:8ce8::1 MODE #garderoben +v-o klarrt kameloso
	// :services. 328 kameloso #ubuntu :http://www.ubuntu.com
	// :erry!erry@freenode/staff/gms-slayer/erry PRIVMSG #freenode :duh
	//  ^..$
	raw = raw[1..$];

	auto bang  = raw.indexOf('!');
	auto space = raw.indexOf(' ');
	if ((bang > 0) && (bang < space)) {
		// zorael!~sunspire@2001:41d0:8:8ce8::1 MODE #garderoben +v-o klarrt kameloso
		//       ^bang                         ^space
		evt.sender = raw[0..bang];
		raw = raw[bang+1..$];
		// ~sunspire@2001:41d0:8:8ce8::1 MODE #garderoben +v-o klarrt kameloso
		// NickServ@services. NOTICE kameloso :This nickname is registered. Please choose a different nickname, or identify via /msg NickServ identify <password>.
		evt.admin = (raw[0] != '~');

		auto p = raw.indexOf(' ');
		// ~sunspire@2001:41d0:8:8ce8::1 MODE #garderoben +v-o klarrt kameloso
		//                              ^p
		raw = raw[p+1..$];
		// MODE #garderoben +v-o klarrt kameloso
	}
	else {
		// services. 328 kameloso #ubuntu :http://www.ubuntu.com
		//          ^space
		evt.sender = raw[0..space];
		raw = raw[space+1..$];
		// 328 kameloso #ubuntu :http://www.ubuntu.com
	}

	space = raw.indexOf(' ');
	// 328 kameloso #ubuntu :http://www.ubuntu.com
	//    ^space
	// MODE #garderoben +v-o klarrt kameloso
	//     ^space
	// JOIN #freenode
	//     ^space
	// PRIVMSG #freenode :duh
	//        ^space
	auto action = raw[0..space];

	if ((action[0] < 48) || (action[0] > 57)) {  // !isNumeric
		try { evt.type = action.to!(IrcEvent.Type); }
		catch (Exception e) {
			/*throw new IrcParseFailureException(
				"Could not cast type string to Type enum",
				space,
				action,
				orig,
				raw,
				evt);*/
			throw new IrcParseFailureException("Could not cast type string to Type enum",
				                               space,
											   action,
				                               orig,
				                               raw,
				                               evt);
		}
	}
	else {
		// action is guaranteed to be numeric
		evt.num = action.to!size_t;
		IrcEvent.mapNumeric(evt);
	}

	raw = raw[space+1..$];
	// kameloso #ubuntu :http://www.ubuntu.com
	// #garderoben +v-o klarrt kameloso
	// :Quit: Leaving
	// #freenode :duh
	// #freenode

	if (raw[0] == ':') {
		// :Quit: Leaving
		// end of the line
		evt.content = raw[1..$];
		return evt;
	}

	space = raw.indexOf(' ');
	// kameloso #ubuntu :http://www.ubuntu.com
	//         ^space
	// #garderoben +v-o klarrt kameloso
	//            ^space
	// #freenode :duh
	//          ^space
	// #freenode
	// space = -1

	if (space < 0) {
		if (raw[0] == '#') {
			// ...JOIN #flerrp
			// #freenode
			// end of the line
			evt.channel = raw;
			return evt;
		}
		else {
			/*throw new IrcParseFailureException(__FILE__, __LINE__,
				"Unknown case",
				orig,
				raw,
				evt);*/
			throw new IrcParseFailureException(__FILE__, __LINE__,
				                               "Unknown case",
											   orig,
				                               raw,
				                               evt);
		}
	}

	if (evt.type != IrcEvent.Type.NUMERIC) {
		// don't do anything with numerics, always targeted to the bot

		auto target = raw[0..space];
		//yarn.put("3: ", raw).clearprint();

		if (target[0] == '#') {
			evt.channel = target;
		}
		else if (target[0] != '*') {
			if (state.bot.nickname != target) {
				state.bot.nickname = target;
			}
			evt.target = target;
			//yarn.put("evt.target: ", evt.target).clearprint();
			//evt.target = _bot.nickname;
		}
	}

	if (!raw.length) {
		/*throw new IrcParseFailureException(__FILE__, __LINE__,
			"Unknown case",
			orig,
			raw,
			evt);*/
		throw new IrcParseFailureException(__FILE__, __LINE__,
			                               "Unknown case",
			                               orig,
			                               raw,
										   evt);
	}

	raw = raw[space+1..$];
	// #ubuntu :http://www.ubuntu.com
	// #freenode :duh
	// +v-o klarrt kameloso

	switch (raw[0]) {

	case '@':
	case '=':
		space = raw.indexOf(' ');
		// @ #flerrp :kameloso^ @kameloso @zorael
		//  ^space
		raw = raw[space+1..$];
		//yarn.put("5: ", raw).clearprint();
		goto case '#';

	case '#':
		// #ubuntu :http://www.ubuntu.com
		space = raw.indexOf(' ');
		evt.channel = raw[0..space];
		//yarn.put("evt.channel: ", evt.channel).clearprint();
		raw = raw[space+1..$];
		//yarn.put("6: ", raw).clearprint();
		break;

	case ':':
		// :*** No Ident response
		evt.content = raw[1..$];
		//yarn.put("evt.content: ", evt.content).clearprint();
		//yarn.put("end").clearprint();
		return evt;

	default:
		// +v-o klarrt kameloso
		space = raw.indexOf(' ');
		//evt.aux = raw[0..space];
		//yarn.put("would do evt.aux 0: ", raw[0..space]).clearprint();
		//raw = raw[space+1..$];
		//yarn.put("7: ", raw).clearprint();
		break;
	}

	// #ubuntu :http://www.ubuntu.com
	// #freenode :duh
	// +v-o klarrt kameloso


	// #garderoben :kameloso^ @klarrt @kameloso @zorael
	//            ^^rest
	// +v-o klarrt kameloso
	// rest == -1

	if (raw[0] == ':') {
		evt.content = raw[1..$];
		//yarn.put("end").clearprint();
		return evt;
	}

	auto rest = raw.indexOf(" :");
	//yarn.put("rest: ", rest).clearprint();

	if (rest < 0) {
		space = raw.indexOf(' ');
		// +v-o klarrt kameloso
		//     ^space
		if (space > 0) {
			evt.aux = raw[0..space];
			//yarn.put("evt.aux 1: ", evt.aux).clearprint();
			raw = raw[space+1..$];
			//yarn.put("9: ", raw).clearprint();
		}
		evt.content = raw;
	}
	else {
		import std.string : stripRight;
		// #freenode :sig-wall_ autumn blah blah
		// #garderoben :kameloso^ @klarrt @kameloso @zorael
		//            ^^rest
		evt.aux = raw[0..rest];
		//yarn.put("evt.aux 2: ", evt.aux).clearprint();
		//yarn.put("RAW IS HERE: '", raw, "'").clearprint();
		evt.content = raw[rest+2..$].stripRight();
		//yarn.put("evt.content: ", evt.content).clearprint();
	}

	//yarn.put("end end").clearprint();
	return evt;
}


private void refineIrcEvent(ref IrcEvent evt, ref IrcBotState state) {
	with (IrcEvent.Type)
	switch (evt.type)
	{

	case PRIVMSG:
		evt.type = (evt.channel.length)
			? CHAN_MSG
			: QUERY;

		// ACTION string always starts with ubyte 1
		enum ubyte hiddenActionCharacter = 1;

		if (evt.content.length && (evt.content[0] == hiddenActionCharacter)) {
			if ((evt.content.length > 8) && (evt.content[1..7] == "ACTION")) {
				evt.type = (evt.type == QUERY)
					? QUERY_EMOTE
					: CHAN_EMOTE;
				evt.content = evt.content[8..$];
			}
			else if ((evt.content.length > 4) && (evt.content[1..3] == "DCC")) {
				// DCC something...
				printErrorValues(
					"Cannot parse DCC event content",
					evt.content);
			}
			else {
				printErrorValues(
					"Cannot parse event content",
					evt.content);
			}
		}

		break;

	case MODE:
		if ((evt.sender == state.bot.nickname) && !evt.channel.length) {
			// no SELF_MODE_CHAN as of yet
			evt.type = SELF_MODE;
		}
		else {
			evt.type = (evt.content.length)
				? CHAN_MODE_USER
				: CHAN_MODE;
		}

		break;

	case NOTICE:
		if ((evt.content.length > 3) && (evt.content[0..3] == "***")) {
			switch (evt.content) {

			case "*** Couldn't look up your hostname":
			case "*** Found your hostname":
			case "*** No Ident response":
				evt.type = IDENT_END;
				break;

			default:
				evt.type = IDENT_LOOKUP;
				break;
			}

			state.server.newHost(evt.sender);
		}
		else if (evt.channel.length)
			evt.type = CHAN_NOTICE;
		else if (evt.sender == state.server.host)
			evt.type = SERVER_NOTICE;
		else if ((evt.sender == "NickServ") && evt.admin) {
			//import std.string : startsWith;

			enum regLine = "This nickname is registered.";
			enum idLine  = "You are now identified";
			enum regLen  = regLine.length;
			enum idLen   = idLine.length;

			if ((evt.content.length > regLen) &&
				(evt.content[0..regLen] == regLine)) {
				evt.type = NICK_CHALLENGE;
			}
			else if ((evt.content.length > idLen) &&
					(evt.content[0..idLen] == idLine)) {
				evt.type = NICK_IDENTIFIED;
			}
		}
		else if (!evt.channel.length && (evt.content.length > 3) &&
				(evt.content[0..3] == "[#") && (evt.sender == "ChanServ")) {
			// :ChanServ!ChanServ@services. NOTiCE kameloso^ :[#freenode] Welcome to #freenode. All network staff are voiced in here, but may not always be around
			// [NOTiCE] ChanServ --> kameloso: "[#amarok] Welcome to #amarok :: For native language support you might visit #amarok.de, #amarok.es or #amarok.fr"
			// FIXME: break out channel
			evt.type = CHANSERV_NOTICE;
			auto p = evt.content.indexOf(']');
			evt.channel = evt.content[2..p];
			// surely we don't need to check the length...
			evt.content = evt.content[p+2..$];
		}
		break;

	case WHOIS_LOGIN:
		// [WHOIS_LOGIN] hobana.freenode.net --> kameloso^: "is logged in as" (zorael^ zorael)
		auto i = evt.aux.indexOf(' ');
		if (i > 0) {
			evt.content = evt.aux[i+1..$];
			evt.aux = evt.aux[0..i];
		}
		break;

	case PART:
		if ((evt.content.length > 3) &&
			(evt.content[0] == '"') && (evt.content[$] == '"'))
		{
			// strip redundant quotes
			evt.content = evt.content[1..$-1];
		}
		goto case JOIN;

	case NICK:
		evt.target  = evt.content;
		evt.content = null;
		goto case JOIN;

	case KICK:
		// needs quirk; aux -> target
		writeln("target: ", evt.target);
		writeln("channel: ", evt.channel);
		writeln("aux: ", evt.aux);
		goto case JOIN;

	case JOIN:
	case QUIT:
		if (evt.sender != state.bot.nickname)
			break;

		with (IrcEvent.Type) {
			static immutable IrcEvent.Type[68] selfTypes = [
				JOIN : SELF_JOIN,
				PART : SELF_PART,
				NICK : SELF_NICK,
				KICK : SELF_KICK,
				QUIT : SELF_QUIT
			];

			evt.type = selfTypes[evt.type];
		}

		if (evt.type == SELF_NICK) {
			// we're modifying state here...
			state.bot.nickname = evt.target;
		}
		break;

	case NICK_CHANGE_BAN_BLOCK:
		/* needs quirk:
		--> nick kameloso
			:adams.freenode.net 435 kameloso^ kameloso #archlinux :Cannot change nickname while banned on channel
			[435] adams.freenode.net: "Cannot change nickname while banned on channel" (kameloso #archlinux) #435
		*/

		import std.string : munch;

		auto nick = evt.aux.munch("^ ");
		evt.channel = evt.aux[1..$];
		evt.aux = nick;

		break;

	default:
		// no need to correct anything
		break;
	}
}


const IrcEvent buildIrcEvent(ref IrcBotState state, string raw) {
	mixin(ScopeMixin!failure);

	IrcEvent evt;

	try {
		//import std.encoding : sanitize;
		evt = raw.toIrcEvent(state); //.sanitize());
		evt.refineIrcEvent(state);
	}
	catch (Exception e) {
		//yarn.put("Caught exception!\n", e, "\n", e.msg);
		writeln("Caught exception!");
		writeln(e);
		writeln(e.msg);
	}
	return evt;
}


/*static if (parrotEvents)
static void parrotNG(ref IrcEvent evt, ref Yarn!string yarn)
{
	mixin MA.Print!(IrcEvent,false) evtPrinter;

	with (evt) with (IrcEvent.Type)
	switch (type) {

	case UNKNOWN:
	case PING:
	case MOTD_BODY:
	case MOTD_END:
	case NAMES:
	case NAMES_TOPIC:
	case NAMES_TOPIC_INFO:
	case NAMES_END:
		// ignore
		break;

	default:
		static if (builderConcat)
			evtPrinter.fun(evt, yarn);
		else
			evtPrinter.fun(evt);

		break;
	}
}*/


struct IrcBot {
	string nickname, ident, fullname;
	string login, password;
	string master, homechan;

	bool identified;

	auto fill(ref Yarn!string yarn)
	{
		yarn.put(nickname)
			.put('!')
			.put(ident)
			.put(": ")
			.put(fullname)
			.put("\nnickserv: ")
			.put(login.length ? login : "<unset>")
			.put(identified ? "(identified)" : null);

		return yarn;
	}
}


struct IrcUser
{
	string nickname, login;
	bool alive;

	this(string nickname_)
	{
		nickname = nickname_;
	}

	bool opCast(T)() nothrow @safe
	if (is(T : bool))
	{
		return (nickname.length > 0);
	}

	bool identified() nothrow @safe @property
	{
		return (login.length > 0);
	}

	static if (builderConcat)
	auto fill(ref Yarn!string yarn)
	{
		yarn.put("[IrcUser] ")
			.put(nickname);

		if (identified)
			yarn.put("identified as ")
				.put(login);
		return yarn;
	}

	@property string toString() nothrow @safe
	{
		auto idString = identified
			? text("identified as ", login)
			: null;
		return text("[IrcUser] ", nickname, idString);
	}
}


struct IrcEvent {
public:
	static enum Type {
		UNSET, UNKNOWN, NUMERIC,
		IDENT_LOOKUP, IDENT_END,
		WELCOME, MOTD, MOTD_BODY, MOTD_END,
		PING, ERROR, NOTICE, SERVER_NOTICE,
		CHANSERV_WELCOME, CHANSERV_URL, CHANSERV_NOTICE,
		NICK, NICK_TAKEN, NICK_CHALLENGE, NICK_IDENTIFIED,
		NICK_CHANGE_BAN_BLOCK,
		CHAN_MODE, CHAN_MODE_USER, CHAN_MSG, CHAN_EMOTE,
		CHAN_INFO, CHAN_NOTICE, TOPIC, CHAN_FORWARDED,
		JOIN, PART, KICK, INVITE, INVITE_ONLY,
		SELF_MODE, SELF_NICK, SELF_JOIN, SELF_PART, SELF_KICK, SELF_QUIT,
		PRIVMSG, QUERY, QUERY_EMOTE, MODE,
		DCC_CHAT, DCC_SEND, DCC_FAILED,
		WHOIS_NAMES, WHOIS_SERVER, WHOIS_END, WHOIS_CHANLIST, WHOIS_LOGIN,
		WHOIS_IDLE_INFO, WHOIS_ADDRESS,
		NAMES, NAMES_TOPIC, NAMES_TOPIC_INFO, NAMES_END,
		NOT_OP, NICKCHANGE_BANNED, BAD_NICK, NO_SUCH_NICK,
		NO_SUCH_CHANNEL, USER_NOT_ON_CHANNEL,
		NOT_ENOUGH_PARAMETERS, MUST_IDENTIFY, BAD_MODE_SYNTAX,
		QUIT, DISCONNECT,
		ALL
	};

	Type type;
	string sender, target, channel, content, aux;
	size_t num;
	bool admin;

	@property bool opCast(T)() const @safe pure nothrow
	if (is(T : bool)) {
		return (type != Type.init);
	}

	static bool mapNumeric(ref IrcEvent evt) @safe pure nothrow {
		with (IrcEvent.Type) {
			static immutable IrcEvent.Type[483] typeByNum = [
				  1 : WELCOME,
				311 : WHOIS_NAMES,
				312 : WHOIS_SERVER,
				317 : WHOIS_IDLE_INFO,
				318 : WHOIS_END,
				319 : WHOIS_CHANLIST,
				328 : CHANSERV_URL,
				330 : WHOIS_LOGIN,
				332 : NAMES_TOPIC,
				333 : NAMES_TOPIC_INFO,
				353 : NAMES,
				366 : NAMES_END,
				376 : MOTD_END,
				378 : WHOIS_ADDRESS,
				401 : NO_SUCH_NICK,
				403 : NO_SUCH_CHANNEL,
				432 : BAD_NICK,
				433 : NICK_TAKEN,
				435 : NICK_CHANGE_BAN_BLOCK,
				441 : USER_NOT_ON_CHANNEL,
				461 : NOT_ENOUGH_PARAMETERS,
				470 : CHAN_FORWARDED,
				472 : BAD_MODE_SYNTAX,
				477 : MUST_IDENTIFY,
				473 : INVITE_ONLY,
				482 : NOT_OP,
			];

			auto inTable = typeByNum[evt.num];

			if (inTable != IrcEvent.Type.init) {
				evt.type = inTable;
				return true;
			}

			switch (evt.num) {

				case   2:
				..
				case   5:
				case 250:
				..
				case 255:
				case 265:
				case 266:
				case 372:
				case 375:
					// MOTD_BODY is pretty spread out
					evt.type = MOTD_BODY;
					break;

				default:
					return false;
			}

			return true;
		}
	}

	auto fill(ref Yarn!string yarn) const
	{
		// what have I wrought
		// hotspot!

		yarn.put('[');
		if (type == Type.NUMERIC)
			yarn.put(num);
		else
			yarn.put(type);
		yarn.put(']');

		/*if (admin)
			yarn.put("*");*/

		if (sender.length)
			yarn.put(' ')
				.put(sender);

		if (target.length) {
			if (type == Type.PART)
				yarn.put(" <-- ");
			else
				yarn.put(" --> ");

			yarn.put(target);
		}

		if (channel.length) {
			if (type == Type.PART)
				yarn.put(" <-- ");
			else
				yarn.put(" --> ");

			//yarn.put("[", channel, "]");
			yarn.put('[')
				.put(channel)
				.put(']');
		}

		if (content.length)
			yarn.put(`: "`)
				.put(content)
				.put('"');

		if (aux.length)
			yarn.put(" (")
				.put(aux)
				.put(")");

		if ((type == Type.NUMERIC) && (num > 0))
			yarn.put(" #")
				.put(num);


		return &yarn;
	}
}


struct IrcBotState {
	IrcUser[string] users;
	IrcBot bot;
	Yarn!string yarn;
	Tid tid;
	Server server;

	alias IrcCommand = Command!(IrcEvent,IrcEvent.Type);

	this(Server server_, IrcBot bot_)
	{
		server = server_;
		bot = bot_;
		tid = thisTid;
	}

	string toString()
	{
		return yarn.put(server, "\n", bot).consume();
	}

	bool allow(in IrcEvent evt)
	{
		import std.algorithm : canFind;
		mixin(ScopeMixin!failure);

		if (evt.sender !in users) {
			users[evt.sender] = IrcUser(evt.sender);
		}

		auto login = users[evt.sender].login;
		if (!login.length) {
			yarn.put("no login on record of user ")
				.put(evt.sender)
				.clearprint();
			whoisAndReplay(evt);
			return false;
		}
		yarn.put(evt.sender)
			.put(" has login ")
			.put(login)
			.clearprint();

		return Friends.canFind(login);
	}


	const bool userIsMaster(const string nickname) @safe pure nothrow
	{
		auto guy = nickname in users;
		return ((guy !is null) && (guy.login == bot.master));
	}


	static bool replay(ref IrcEvent origEvt, in ref IrcEvent newEvt)
	{
		mixin(ScopeMixin!failure);
		import std.algorithm : canFind;
		// aux contains nick, content login

		if (origEvt.sender != newEvt.aux) {
			return false;
		}
		else if (Friends.canFind(newEvt.content)) {
			thisTid.send(origEvt);
		}
		return true;
	}

	void whoisAndReplay(IrcEvent evt)
	{
		mixin(ScopeMixin!failure);
		import std.algorithm : remove;

		yarn.put("need login info on ", evt.sender)
			.clearprint();

		// restore content string that we stripped of bot name
		if (evt.channel.length) {
			evt.content = yarn
				.put(bot.nickname)
				.put(':')
				.put(evt.content)
				.consume();
		}

		tid.send(IrcCommand(IrcEvent.Type.WHOIS_LOGIN, evt, &replay));
		tid.send(true, yarn
			.put("WHOIS ")
			.put(evt.sender)
			.consume()
		);
	}
}

class IrcParseFailureException : Exception
{
	this(Args...)(string file, size_t line, string msg, Args args)
	{
		printErrorValues(msg, args);
		super(msg, file, line);
	}
}
