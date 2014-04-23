module kameloso.mastermind;

import std.parallelism;  // : taskPool, TaskPool, scopedTask, totalCPUs;

import kameloso;
import kameloso.plugins;
//import kameloso;
//import kameloso.plugins;

final:

private alias IrcCommand = Command!(IrcEvent,IrcEvent.Type);


struct Mastermind
{
private:
	NamedThread reader, writer;
	IrcPlugin[] plugins;
	IrcCommand[] commands;
	IrcBotState state;
	TaskPool workers;
	Yarn!string yarn;

	__gshared SocketWrapper conn;

	enum DefaultSize { commandQueue = 8 };

	this(IrcBotState state_) {
		setupThread("Mastermind");

		state = state_;
		conn  = socketWrapper(state_.server);
		initPlugins();
		spawnThreads();

		workers = new TaskPool(plugins.length);
		commands.reserve(4);
	}

	void spawnThreads() {
		static if (useStreams) {
			reader = NamedThread("readStream",  &readStream, conn);
			writer = NamedThread("writeStream", &writeStream, conn);
		}
		else {
			reader = NamedThread("readSocket",  &readSocket, conn);
			writer = NamedThread("writeSocket", &writeSocket, conn);
		}

		assert (threadsAreSane);
	}

	bool threadsAreSane() @property {
		return (reader.isSane && writer.isSane);
	}

	void initPlugins() {
		plugins.clear();
		plugins.reserve(2);  // FIXME: figure out plugin management

		plugins ~= new Waiter();
		plugins ~= new Login();
	}

	void onReceivedString(in string raw) {
		const evt = buildIrcEvent(state, raw);
		if (!evt)
			return;

		// parrot
		evt.fill(yarn)
		   .clearprint();

		foreach (plugin; workers.parallel(plugins)) {
			// FIXME: this is still synchronous!
			plugin.process(state, evt);
		}

		if (commands.length) {
			import std.algorithm : remove;

			foreach (i, ref cmd; commands) {
				if (evt.type != cmd.category) {
					continue;
				}

				if (cmd.fn(cmd.payload, evt)) {
					--cmd.lives;
				}
			}

			commands = commands.remove!(a => a.lives == 0);
		}
	}

	void onReceivedCommand(IrcCommand newCommand) {
		scope /*auto*/ toRemove = new bool[](commands.length);  // <-- does that work?

		if (commands.length) {
			import std.algorithm : remove;
			// FIXME: exploitable logic vs overly restrictive logic
			foreach (ref cmd; commands) {
				if ((cmd.payload.sender == newCommand.payload.sender) &&
					(cmd.category == newCommand.category))
				{
					yarn.put("duplicate queued command; removing old").clearprint();
				}
			}
			yarn.put("commands.length pre-remove:    ", commands.length).clearprint();
			yarn.put("commands.capacity pre-remove:  ", commands.capacity).clearprint();
			commands = commands.remove!(a => a.lives == 0);
			yarn.put("commands.length post-remove:   ", commands.length).clearprint();
			yarn.put("commands.capacity post-remove: ", commands.capacity).clearprint();
		}

		yarn.put("commands.capacity:", commands.capacity).clearprint();
		if (!commands.capacity) {
			yarn.put("command queue ran out of space... growing.").clearprint();
			commands.reserve(commands.length + DefaultSize.commandQueue);
		}
		commands ~= newCommand;
	}

	void onReceivedEvent(const IrcEvent evt) {
		yarn.put("MASTERMIND REPLAYING ")
			.put(evt.type)
			.put(" EVENT!")
			.clearprint();

		foreach (plugin; workers.parallel(plugins)) {
			plugin.process(state, evt);
		}
	}

public:
	bool listen() {
		bool halt, disconnect, reconnect;

		scope(exit) {
			writeln("MASTERMIND SCOPE EXIT!");
			workers.finish(true);
			workers.stop();
			teardown();
		}

		/*concurrency.d(74): Error: this for tid needs to be type NamedThread not type Mastermind
		mastermind.d(152): Error: mixin kameloso.mastermind.Mastermind.listen.Redirect!(tid, bool, string) error instantiating */

		Tid writerTid = writer.tid;

		//mixin MA.Update!(state.bot) _newBot;
		//mixin MA.Update!(state.server) _newServer;
		void _newBot(IrcBot newBot) {
			state.bot = newBot;
		}
		void _newUser(IrcUser newUser) {
            state.users[newUser.nickname] = newUser;
        }
		void _newServer(Server newServer) {
			state.server = newServer;
		}
		mixin MA.Redirect!(writerTid,bool,string) _write;
		mixin MA.Lambda!({ halt=true; },Imperative.Abort) _killswitch;
		mixin MA.Lambda!({ disconnect=true; },Notification.Disconnected) _disc;
		mixin MA.Lambda!({ reconnect=true; },Imperative.Reconnect) _reconnect;
		mixin MA.Lambda!({ halt=!threadsAreSane; },LinkTerminated) _linkTerm;
		mixin MA.Print!Variant _unknown;

		while (!halt && !disconnect && !reconnect) {
			/*bool received =*/ receiveTimeout(10.seconds,
				&onReceivedString,
				&onReceivedCommand,
				&_write.fun,
				&onReceivedEvent,
				&_newBot, //.fun,
                &_newUser,  // .fun,
				&_newServer, //.fun,
				&_disc.fun,
				&_killswitch.fun,
				&_reconnect.fun,
				&_linkTerm.fun,
 				&_unknown.fun
			);

			/*if (!received)
				halt = !threadsAreSane;*/
		}

		writeln("MASTERMIND LOOP EXIT!");

		// TODO: implement real disconnect/reconnect logic

		return reconnect;
	}

	bool connect() {
		scope(failure) {
			writeln("connection failed!");
			return false;
		}

		scope(success) {
			writeln("connected.");
			reader.tid.send(Notification.Connected());
		}

		return conn.connect();
	}

	void teardown() {
		writer.shutdown();
		reader.shutdown();
		conn.disconnect();

		// exhaust mailbox queue
		bool empty;
		while (!empty) {
			empty = !receiveTimeout(50.msecs,
				(Variant v) {}
			);
		}
		unregister("Mastermind");
    }
}


auto mastermind(ref IrcBotState state) {
	// instantiator
	auto m = Mastermind(state);
	return m;
}

