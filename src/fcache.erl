%% crypto:start(), fcache:start(), fcache:locate({erlang, integer_to_list, [1]}).
-module(fcache).
-behaviour(gen_server).

-export([start/0, cache/1, locate/1, discover/0]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).
-export([terminate/2, code_change/3]).

init(_) ->
    {Good, _Bad} = gen_server:multi_call(nodes(), fcache, {info}, 10000),
    Nodes = [Name || {Name, ok} <- Good],
    {ok, {[node() | Nodes], gb_trees:empty()}}.

start() ->
    case node() of
        'nonode@nohost' -> exit(invalid_node);
        _ -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], [])
    end.

locate({Module, Function, Arguments}) ->
    Key = crypto:md5(erlang:term_to_binary({Module, Function, Arguments})),
    locate(Key);
locate(Key) ->
    gen_server:call(fcache, {locate, Key}, 6000).

cache({Module, Function, Arguments}) ->
    Key = crypto:md5(erlang:term_to_binary({Module, Function, Arguments})),
    Node = locate(Key),
    case gen_server:call({fcache, Node}, {get, Key}, 6000) of
        {ok, Value} -> Value;
        _ ->
            Value = apply(Module, Function, Arguments),
            gen_server:call({fcache, Node}, {set, Key, Value}, 6000),
            Value
    end.

discover() ->
    gen_server:call(fcache, {discover}, 6000).

handle_call({discover}, _From, {_, Cache}) ->
    {Good, _Bad} = gen_server:multi_call(nodes(), fcache, {info}, 10000),
    Nodes = [Name || {Name, ok} <- Good],
    {reply, [node() | Nodes], {[node() | Nodes], Cache}};

handle_call({locate, _}, _From, State = {Nodes, _}) when length(Nodes) == 1 ->
    {reply, node(), State};

handle_call({locate, Key}, _From, State = {Nodes, _}) ->
    <<X:128/integer>> = Key,
    Mod = X rem length(Nodes),
    {reply, Mod, State};

handle_call({get, Key}, _From, State = {_, Tree}) ->
    Resp = case gb_trees:is_defined(Key, Tree) of
        true ->
            {ok, gb_trees:get(Key, Tree)};
        false ->
            {nok, existance}
    end,
    {reply, Resp, State};

handle_call({set, Key, Value}, _From, {Nodes, Tree}) ->
    NewTree = case gb_trees:is_defined(Key, Tree) of
        true ->
            gb_trees:update(Key, Value, Tree);
        false ->
            gb_trees:insert(Key, Value, Tree)
    end,
    {reply, ok, {Nodes, NewTree}};

handle_call({nodes}, _From, State = {Nodes, _}) ->
    {reply, Nodes, State};

handle_call({info}, _From, State) ->
    {reply, ok, State};

handle_call(_, _From, State) -> {reply, {error, invalid_call}, State}.

handle_cast(_Message, State) -> {noreply, State}.

handle_info(_Info, State) -> {noreply, State}.

terminate(_Reason, _State) -> ok.

code_change(_OldVsn, State, _Extra) -> {ok, State}.
