module kameloso.plugins.login;

import kameloso.plugins.common;

final:

enum eventArrayLength = 36;

class Login : IrcPlugin {
private:
	Yarn!string yarn;
	bool[eventArrayLength] wanted;
	Tid tid;

final:
	const bool wants(IrcEvent.Type type) const @safe pure nothrow {
		return (type > (wanted.length - 1))
			? false
			: wanted[type];
	}

public:
	this() {
		alias w = wanted;
		with (IrcEvent.Type) {
			w[PING]   = true;
			w[INVITE] = true;
			w[IDENT_END]  = true;
			w[MOTD_END]   = true;
			w[WELCOME]    = true;
			w[NICK_TAKEN] = true;
			w[SELF_NICK]  = true;
			w[NICK_CHALLENGE]  = true;
			w[NICK_IDENTIFIED] = true;
		}

		tid = thisTid;
		writeln("Login plugin loaded.");
	}

	@property const string name() const @safe pure nothrow
	{
		return "Login";
	}

	void process(IrcBotState state, in IrcEvent evt) {
		mixin(ScopeMixin!failure);

		if (!wants(evt.type))
			return;

		with (IrcEvent.Type)
		switch (evt.type) {

		case PING:
			tid.send(false, yarn
				.put("PONG :")
				.put(evt.sender)
				.consume()
			);
			break;

		/* --- login events --- */
		case IDENT_END:
			mixin(ScopeMixin!(failure,"IDENT_END"));
			wanted[IDENT_END] = false;

			tid.send(true, yarn
				.put("USER ")
				.put(state.bot.ident)
				.put(" 8 * :")
				.put(state.bot.nickname)
				.consume()
			);
			tid.send(true, yarn
				.put("NICK ")
				.put(state.bot.nickname)
				.consume()
			);
			break;

		case MOTD_END:
			mixin(ScopeMixin!(failure,"MOTD_END"));
			wanted[MOTD_END]   = false;
			wanted[NICK_TAKEN] = false;  // we don't want this triggering later/

			tid.send(true, yarn
				.put("JOIN ")
				.put(state.bot.homechan)
				.consume()
			);
			break;

		case NICK_TAKEN:
			mixin(ScopeMixin!(failure,"NICK_TAKEN"));
			// BUG: breaks if you fail to change nick and this reaction fails
			tid.send(true, yarn
				.put("NICK ")
				.put(evt.aux)
				.put('^')
				.consume()
			);
			break;

        case WELCOME:
            if (evt.target == state.bot.nickname)
                break;

            yarn.put("got a welcome with a new nickname!").clearprint();
            state.bot.nickname = evt.target;
            tid.send(state.bot);
            break;
		/* -------------------- */

		case SELF_NICK:
			mixin(ScopeMixin!(failure,"SELF_NICK"));
			wanted[NICK_TAKEN] = false;  // see above
			writeln("............................... SELF_NICK!");
			break;

		case NICK_CHALLENGE:
			mixin(ScopeMixin!(failure,"NICK_CHALLENGE"));
			wanted[NICK_CHALLENGE] = false;

			if (!(state.bot.login && state.bot.password)) {
				writeln("... missing login credentials :<");
				break;
			}

			tid.send(false, yarn
				.put("PRIVMSG NickServ :IDENTIFY ")
				.put(state.bot.login)
				.put(' ')
				.put(state.bot.password)
				.consume()
			);

			yarn.put("--> PRIVMSG NickServ :IDENTIFY ")
				.put(state.bot.login)
				.put(" hunter2")
				.clearprint();

			break;

		case NICK_IDENTIFIED:
			mixin(ScopeMixin!(failure,"NICK_IDENTIFIED"));
			wanted[NICK_IDENTIFIED] = false;

			writeln("...identified! :D->-<");
			state.bot.identified = true;
			tid.send(state.bot);
			break;

		case INVITE:
			mixin(ScopeMixin!(failure,"NICK_INVITE"));
			tid.send(true, yarn
				.put("JOIN ")
				.put(evt.channel)
				.consume()
			);
			break;

		default:
			yarn.put("LOGIN PLUGIN GOT UNEXPECTED EVENT ")
				.put(evt.type)
				.clearprint();
			break;
		}
	}
}
