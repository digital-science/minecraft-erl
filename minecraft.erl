-module(minecraft).
-compile(export_all).

-define(KEEPALIVE,      16#00).
-define(LOGIN,          16#01).
-define(HANDSHAKE,      16#02).
-define(TIME_UPDATE,    16#04).
-define(KICK,           16#FF).

-define(HANDSHAKE_MESSAGE(Username),  list_to_binary([<<?HANDSHAKE:8>>, string_to_unicode_binary(Username)])).

-define(KEEPALIVE_PATTERN,            <<?KEEPALIVE:8, KeepAliveID:32/signed>>).
-define(HANDSHAKE_PATTERN,            <<?HANDSHAKE:8, HashLen:16, Hash:HashLen/binary-unit:16>>).
-define(KICK_PATTERN,                 <<?KICK:8, Len:16, Reason:Len/binary-unit:16>>).

start(MinecraftHost) ->
  application:start(inets),
  application:start(crypto),
  application:start(public_key),
  application:start(ssl),
  Pid = spawn(fun() -> connect(MinecraftHost) end),
  register(minecraft_socket, Pid).

connect(MinecraftHost) ->
  {ok,Socket} = gen_tcp:connect(MinecraftHost, 25565, [binary, {packet, 0}]),
  loop(Socket, []).

loop(Socket, Listeners) ->
  receive
    {tcp,Socket,Bin} ->
      case Bin of
        ?KEEPALIVE_PATTERN  -> gen_tcp:send(Socket, <<?KEEPALIVE:8, KeepAliveID:32/signed>>);
        ?HANDSHAKE_PATTERN  -> notify(Listeners, {handshake, utf16_binary_to_list(Hash)});
        ?KICK_PATTERN       -> notify(Listeners, {kick, utf16_binary_to_list(Reason)})
      end,
      loop(Socket, Listeners);
    {tcp_send,Packet} ->
      gen_tcp:send(Socket,Packet),
      loop(Socket, Listeners);
    {tcp_listen, Listener} ->
      loop(Socket, [Listener|Listeners])
  end.

notify([], _) -> [];
notify([Listener|Rest], Message) ->
  Listener ! Message,
  notify(Rest, Message).

login(User, Password) ->
  case login_request(User, Password) of
    {ok, {_, 200, _}, _, Body} ->
      [_,_,_,_SessionID] = string:tokens(Body, ":")
  end,
  minecraft_socket ! {tcp_send, ?HANDSHAKE_MESSAGE(User)}.

login_request(User, Password) ->
  httpc:request(post,
    {"https://login.minecraft.net/",
      [],
      "application/x-www-form-urlencoded",
      lists:flatten(io_lib:format("user=~s&password=~s&version=9999", [User, Password]))},
    [], []).

listen() ->
  minecraft_socket ! {tcp_listen, self()}.

%% Utility functions
string_to_unicode_binary(Str) ->
  StrLen = string:len(Str),
  StrBin = unicode:characters_to_binary(Str, utf8, utf16),
  <<StrLen:16/unsigned, StrBin/binary>>.

utf16_binary_to_list(Bin) ->
  unicode:characters_to_list(Bin, utf16).
