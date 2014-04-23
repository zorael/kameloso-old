module kameloso.plugins.common;

public import std.parallelism : TaskPool;

public import kameloso.common;
public import kameloso.irc    : IrcEvent, IrcBot, IrcUser, IrcBotState;
public import kameloso.string : Yarn;

public interface IrcPlugin {
	@property const string name() const @safe pure nothrow;
	void process(IrcBotState state, in IrcEvent evt);
}
