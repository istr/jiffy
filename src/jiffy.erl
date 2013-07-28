% This file is part of Jiffy released under the MIT license.
% See the LICENSE file for more information.

-module(jiffy).
-export([decode/1, encode/1, encode/2]).
-define(NOT_LOADED, not_loaded(?LINE)).

-on_load(init/0).

-spec decode(binary() | maybe_improper_list(binary() 
    | maybe_improper_list(any(), binary() | []) 
    | byte(),binary() | [])) -> any().
decode(Data) when is_binary(Data) ->
    case nif_decode(Data) of
        {error, _} = Error ->
            throw(Error);
        {partial, EJson} ->
            finish_decode(EJson);
        EJson ->
            EJson
    end;
decode(Data) when is_list(Data) ->
    decode(iolist_to_binary(Data)).


-spec encode(_) -> any().
encode(Data) ->
    encode(Data, []).


-spec encode(_,[any()]) -> any().
encode(Data, Options) ->
    ForceUTF8 = lists:member(force_utf8, Options),
    case nif_encode(Data, Options) of
        {error, invalid_string} when ForceUTF8 == true ->
            FixedData = jiffy_utf8:fix(Data),
            encode(FixedData, Options -- [force_utf8]);
        {error, _} = Error ->
            throw(Error);
        {partial, IOData} ->
            finish_encode(IOData, []);
        IOData ->
            IOData
    end.


-spec finish_decode(_) -> any().
finish_decode({bignum, Value}) ->
    list_to_integer(binary_to_list(Value));
finish_decode({bignum_e, Value}) ->
    {IVal, EVal} = case string:to_integer(binary_to_list(Value)) of
        {I, [$e | ExpStr]} ->
            {E, []} = string:to_integer(ExpStr),
            {I, E};
        {I, [$E | ExpStr]} ->
            {E, []} = string:to_integer(ExpStr),
            {I, E}
    end,
    IVal * math:pow(10, EVal);
finish_decode({bigdbl, Value}) ->
    list_to_float(binary_to_list(Value));
finish_decode({Pairs}) when is_list(Pairs) ->
    finish_decode_obj(Pairs, []);
finish_decode(Vals) when is_list(Vals) ->
    finish_decode_arr(Vals, []);
finish_decode(Val) ->
    Val.

-spec finish_decode_obj([{_,_}],[{_,_}]) -> {[{_,_}]}.
finish_decode_obj([], Acc) ->
    {lists:reverse(Acc)};
finish_decode_obj([{K, V} | Pairs], Acc) ->
    finish_decode_obj(Pairs, [{K, finish_decode(V)} | Acc]).

-spec finish_decode_arr([any()],[any()]) -> [any()].
finish_decode_arr([], Acc) ->
    lists:reverse(Acc);
finish_decode_arr([V | Vals], Acc) ->
    finish_decode_arr(Vals, [finish_decode(V) | Acc]).


-spec finish_encode([binary() | integer()],[binary()]) -> [binary()].
finish_encode([], Acc) ->
    %% No reverse! The NIF returned us
    %% the pieces in reverse order.
    Acc;
finish_encode([<<_/binary>>=B | Rest], Acc) ->
    finish_encode(Rest, [B | Acc]);
finish_encode([Val | Rest], Acc) when is_integer(Val) ->
    Bin = list_to_binary(integer_to_list(Val)),
    finish_encode(Rest, [Bin | Acc]);
finish_encode(_, _) ->
    throw({error, invalid_ejson}).


-spec init() -> ok
    | {error, {bad_lib|load|load_failed|old_code|reload|upgrade, string()}}.
init() ->
    PrivDir = case code:priv_dir(?MODULE) of
        {error, _} ->
            EbinDir = filename:dirname(code:which(?MODULE)),
            AppPath = filename:dirname(EbinDir),
            filename:join(AppPath, "priv");
        Path ->
            Path
    end,
    erlang:load_nif(filename:join(PrivDir, "jiffy"), 0).


-spec not_loaded(116 | 120) -> any().
not_loaded(Line) ->
    erlang:nif_error({not_loaded, [{module, ?MODULE}, {line, Line}]}).

-spec nif_decode(binary()) -> any().
nif_decode(_Data) ->
    ?NOT_LOADED.

-spec nif_encode(_,[any()]) -> any().
nif_encode(_Data, _Options) ->
    ?NOT_LOADED.

