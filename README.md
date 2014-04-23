#kameloso
[kameloso](http://youtu.be/s-mOy8VUEBk) is a basic semi-asynchronous IRC bot written in the [D programming language](http://dlang.org).

It was largely done as an exercise and to learn the language. It thus suffers fairly heavily from over-engineering, feature creep, and other antipatterns caused by shotgun programming. It does not completely nor correctly cover the IRC protocol, yet knows enough to do a fair job as a channel bot.

*Great* effort was taken to avoid the garbage collector.

**Do not base your project off of this one.** If you are looking for an IRC bot written in D, you would be better off using [Dirk](https://github.com/JakobOvrum/Dirk).

##Compilation
Clone the repo and build the project using [`dub`](http://code.dlang.org/about).

```
git clone https://github.com/zorael/kameloso.git
dub build  # optionally add --build=release or --build=debug
```
The built binary will be placed in the project root directory, named `kameloso`.
##Usage

As of yet there is no command-line help screen, but the following flags are available:

* `-H`|`--homechan`: home channel, outside of which the bot will only partly react to events
* `-h`|`--host`: server host, defaults to `irc.freenode.net` (currently also: `-i`, `--ip`, `-s`, `--server`)
* `-P`|`--port`: server port, defaults to `6667`
* `-n`|`--nick`: nickname
* `-I`|`--ident`: [ident](http://en.wikipedia.org/wiki/Ident_protocol)
* `-f`|`--fullname`: full name shown in `/whois` output
* `-p`|`--password`: NickServ identification password
* `-m`|`--master`: login of the bot owner for remote control

**_Be sure to change master and home channel! Remember to escape the #channel octhorpe!_ **

There is currently also a hard-coded list of logins which are allowed to perform some non-essential commands via channel messages.

##TODO
* remove hard-coded stuff!
* basic terminal help screen
* support for configuration files
* implement table lookups for *string-to-enum* conversion (`IrcEvent.Type`)
* move from using `SocketStream` to directly using `Socket`
* move from using homebrew `Yarn!T` to using standard library `Appender!T`
* figure out how to do plugins in separate threads \*correctly\*
* improve disconnect/reconnect logic (requires direct `Socket` use)
* ...basic rework of everything
