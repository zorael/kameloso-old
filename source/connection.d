module kameloso.connection;

import
	std.socket,
	std.socketstream,
	core.memory;

import
	kameloso.common,
	kameloso.string,
    kameloso.concurrency;


final:


static if (useStreams)
struct SocketWrapper {
private:
	enum Timeout { socketSend = 5, socketReceive = 5, serverRetry = 1 }

	Server server;

	void reset() {
		writeln("SocketWrapper reset.");
		socket = new TcpSocket();
		stream = new SocketStream(socket);

		alias s = SocketOptionLevel.SOCKET;
		with (socket)
		with (SocketOption)
		with (Timeout) {
			setOption(s, SNDTIMEO, socketSend.seconds);
			setOption(s, RCVTIMEO, socketReceive.seconds);
			setOption(s, SNDBUF, 512);
			setOption(s, RCVBUF, 512);
		}
	}

	this(Server server_) {
		server = server_;
		reset();
	}

public:
	__gshared Socket socket;
	__gshared SocketStream stream;

	bool connect() {
		scope(failure) {
			writeln("Failed to connect to server!");
			return false;
		}

		//import std.typecons;

		//assert(server.host.length && (server.port > 0));
		scope adds = getAddress(server.host, server.port);
		scope(exit) GC.free(&adds);
		auto len   = adds.length;

		//writefln("host %s resolved into %d IPs", server.host, len);
		writeln("host ", server.host, " resolved into ", len, " IPs.");

		foreach (i, Address ip; adds) {
			//writefln("connecting to %s ...", ip);
			writeln("connecting to ", ip, " ...");

			try {
				socket.connect(ip);
				return true;
			}
			catch (SocketOSException e) {
				writeln("connection failed! ", e.msg);
			}

			socket.shutdown(SocketShutdown.BOTH);

			if (i < (len - 1)) {
				Thread.sleep(Timeout.serverRetry.seconds);
			}
		}

		return false;
	}

	void disconnect() {
		writeln("disconnecting ...");
		socket.shutdown(SocketShutdown.BOTH);
		socket.close();
	}
}


/*static if (!useStreams)
struct SocketWrapper {
private:
	enum Timeout { socketSend = 5, socketReceive = 5, serverRetry = 1 }
	enum BufferSize { send = 1024, receive = 1024 }

	Server server;
	SocketSet socketSet;

	void reset() {
		writeln("SocketWrapper reset.");
		socketSet = new SocketSet(3);

		alias s = SocketOptionLevel.SOCKET;
		with (socket) with (SocketOption) with (Timeout) with (BufferSize) {
			setOption(s, SNDTIMEO, socketSend.seconds);
			setOption(s, RCVTIMEO, socketReceive.seconds);
			setOption(s, SNDBUF, send);
			setOption(s, RCVBUF, receive);
		}
	}

	shared static this() {
		reset();
	}

	this(Server server_) {
		server = server_;
		//reset();
	}

public:
	bool connect() {
		scope(failure) {
			writeln("Failed to connect to server!");
			return false;
		}

		assert(server.host.length && (server.port > 0));
		auto adds = getAddress(server.host, server.port);
		auto len  = adds.length;

		writefln("host %s resolved into %d IPs", server.host, len);

		foreach (i, Address ip; adds) {
			writefln("connecting to %s ...", ip);

			try {
				socket.connect(ip);
				return true;
			}
			catch (SocketOSException e) {
				writeln("connection failed! ", e.msg);
			}

			if (i < (len - 1)) {
				Thread.sleep(Timeout.serverRetry.seconds);
			}
		}

		return false;
	}

	void disconnect() {
		writeln("disconnecting ...");
		socket.shutdown(SocketShutdown.BOTH);
		socket.close();
	}
}*/


auto socketWrapper(Server server) {
	auto c = SocketWrapper(server);
	return c;
}


private bool waitForConnection() {
	bool received, retval;

	mixin MA.Lambda!({ retval=true;  },Notification.Connected) _connected;
	mixin MA.Lambda!({ retval=false; },Variant) _unknown;

	received = receiveTimeout(10.seconds,
		&_connected.fun,
		&_unknown.fun
	);

	if (!received) {
		writeln("connection timeout.");
		ownerTid.send(Imperative.Abort());
	}

	return retval;
}


void readStream(ref SocketWrapper conn) {
	mixin(ScopeMixin!(success|failure|exit));
	setupThread("readStream");
	scope(exit) ownerTid.send(Imperative.Abort());

	if (!waitForConnection()) {
		return;
	}

	enum errorThreshold = (300 / SocketWrapper.Timeout.socketReceive);
	enum messageCheckFrequency = 10;

	bool halt, verbose;
	//char[512] buf;
	auto buf = new char[](1024);
	char[] slice;
	string copy;
	size_t readCounter, errorCount;

	mixin MA.Lambda!({ verbose=true; },bool)  _verbose;
	mixin MA.Lambda!({ verbose=false; },char) _quiet;
	mixin MA.Lambda!({ halt=true; },Variant)  _unknown;

	while (!halt) {
		if (++readCounter > messageCheckFrequency) {
			receiveTimeout(0.seconds,
				&_verbose.fun,
				&_quiet.fun,
				&_unknown.fun
			);

			readCounter = 0;
		}

		slice = conn.stream.readLine(buf);

		if (slice.length) {
			copy = slice.idup;
			if (verbose)
				writeln(copy);

			ownerTid.send(copy);
			errorCount = 0;
			continue;
		}

		if (++errorCount > errorThreshold) {
			if (errorCount > (2 * errorThreshold)) {
				writeln("something's seriously wrong. dying");
				validateSocketError(lastSocketError);
				writeln("reader gonna die.");
				return;
			}
			else if (errorCount > errorThreshold) {
				if (!validateSocketError(lastSocketError)) {
					ownerTid.send(Imperative.Reconnect());
					writeln("reader gonna die.");
					return;
				}
			}
			else {
				validateSocketError(lastSocketError);
			}
		}

		// force recheck on empty message
		readCounter = messageCheckFrequency;
	}
}


void writeStream(ref SocketWrapper conn) {
	mixin(ScopeMixin!failure);
	setupThread("writeStream");
	scope(exit) ownerTid.send(Imperative.Abort());

	bool halt;
	size_t prev;

	void _writeLine(bool loud, string line) {
		import std.datetime : Clock;
		if (!line.length) {
			writeln("WRITER WAS SENT EMPTY STRING!");
			return;
		}

		if (loud)
			writeln("--> ", line);

		auto delta = (Clock.currStdTime - prev);
		if (delta < 10_000_000)
			Thread.sleep((10_000_000 - delta).hnsecs);

		try { conn.stream.writeLine(line); }
		catch (Exception e) {
			writefln("writer caught exception %s: %s", e.msg, lastSocketError);
			halt = true;
			return;
		}

		prev = Clock.currStdTime;
	}

	mixin MA.Lambda!({ halt=true; },Imperative.Abort) _killswitch;
	mixin MA.Lambda!({ halt=true; },OwnerTerminated)  _ownerTerm;
	mixin MA.Print!Variant _unknown;

	while (!halt) {
		receive(
			&_writeLine,
			&_killswitch.fun,
			&_ownerTerm.fun,
			&_unknown.fun
		);
	}
}


private bool validateSocketError(in string err) {
	switch (err) {

	case "Transport endpoint is not connected":
	case "Connection reset by peer":
	case "Bad file descriptor":
		//writefln("MALIGN last socket error %s!", err);
		writeln("MALIGN last socket error! ", err);
		return false;

	case "Resource temporarily unavailable":
	case "Interrupted system call":
		//writefln("benign? socket error %s", err);
		writeln("benign? socket error. ", err);
		break;

	default:
		writeln("would have blocked: ", wouldHaveBlocked);
		break;
	}

	return true;
}


struct Server {
	string host;
	ushort port;

	bool isResolved;

	this(string host_, ushort port_) {
		host = host_;
		port = port_;
	}

	bool newHost(string newHost) @safe pure nothrow
	{
		if (!isResolved) {
			isResolved = true;
			host = newHost;
			return true;
		}

		return false;
	}
}
