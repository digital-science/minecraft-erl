-module(minecraft_server).

-behaviour(gen_server).
-define(SERVER, ?MODULE).

-define(KEEPALIVE,      16#00).
-define(LOGIN,          16#01).
-define(HANDSHAKE,      16#02).
-define(TIME_UPDATE,    16#04).
-define(KICK,           16#FF).

-define(HANDSHAKE_MESSAGE(Username),  list_to_binary([<<?HANDSHAKE:8>>, minecraft:string_to_unicode_binary(Username)])).

-define(KEEPALIVE_PATTERN,            <<?KEEPALIVE:8, KeepAliveID:32/signed>>).
-define(HANDSHAKE_PATTERN,            <<?HANDSHAKE:8, HashLen:16, Hash:HashLen/binary-unit:16>>).
-define(KICK_PATTERN,                 <<?KICK:8, Len:16, Reason:Len/binary-unit:16>>).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([start_link/0]).
-export([start/0, connect/4, connect_local/2]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(state, {
          socket,
          session_id,
          user,
          listeners
         }).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start_link() ->
    application:start(inets),
    application:start(crypto),
    application:start(public_key),
    application:start(ssl),
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

start() ->
    start_link().

connect(IP, Port, User, Password) ->
    gen_server:call(?MODULE, {connect, IP, Port}),
    case minecraft:login_request(User, Password) of
        {ok, {{_, 200, _}, _, Body}} ->
            [_,_,_,SessionID] = string:tokens(Body, ":")
    end,
    gen_server:cast(?MODULE, {handshake_user, User, SessionID}).

connect_local(User, Password) ->
    connect("127.0.0.1", 25565, User, Password).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init([]) ->
    process_flag(trap_exit, true),
    %%io:format("Connecting to ~s~n", [MinecraftHost]),
    %%{ok, Socket} = gen_tcp:connect(MinecraftHost, 25565, [binary, {packet, 0}]),
    %%o:format("Socket: ~p~n", [Socket]),
    {ok, #state{listeners = []}}.

handle_call({connect, IP, Port}, _From, State) ->
    case gen_tcp:connect(IP, Port, [binary, {active, once}]) of
        {ok, Socket} ->
            %gen_tcp:controlling_process(Socket, ?MODULE),
            NewState = State#state{socket=Socket},
            io:format("Socket ar: ~p~n", [Socket]),
            {reply, ok, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call(_Request, _From, State) ->
    {noreply, ok, State}.

handle_cast({handshake_user, User, SessionID}, State) ->
    gen_tcp:send(State#state.socket, ?HANDSHAKE_MESSAGE(User)),
    {noreply, State#state{session_id = SessionID, user = User}};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({tcp, _, ?HANDSHAKE_PATTERN}, State = #state{session_id = SessionID, user = User}) ->
    StringHash = minecraft:utf16_binary_to_list(Hash),
    io:format("Handshake hash: ~p~n", [StringHash]),
    case httpc:request(get,
                       {lists:flatten(io_lib:format("http://session.minecraft.net/game/joinserver.jsp?user=~s&sessionId=~s&serverId=~s", [User, SessionID, StringHash])), []}, [], []) of
        {ok, {{_, 200, _}, _, Body}} ->
            io:format("Body: ~p~n", [Body])
    end,
    {noreply, State};

handle_info(Info, State) ->
    io:format("Received info: ~p~n", [Info]),
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
