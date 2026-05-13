%% Run from a vanilla HyperBEAM checkout:
%%   rebar3 shell --eval 'file:script("../lapee-devices-clean/scripts/publish_and_smoke.erl"), halt().'

{ok, Cwd} = file:get_cwd().

DeviceDir =
    case os:getenv("LAPEE_DEVICE_DIR") of
        false -> filename:absname(filename:join(Cwd, "../lapee-devices-clean"));
        Dir -> filename:absname(Dir)
    end.

SrcDir = filename:join(DeviceDir, "src").
SpecDir = filename:join(DeviceDir, "specs").
OutDir = filename:join([DeviceDir, "_build/default/packaged-devices"]).
DistDir = filename:join(DeviceDir, "dist").
PluginEbin = filename:join([DeviceDir, "_build/default/plugins/hb_device/ebin"]).
true = code:add_patha(PluginEbin).

Devices = [
    #{ name => <<"ao-payment@1.0">>, root => dev_aopayment },
    #{ name => <<"arweave-byte-pricing@1.0">>, root => dev_arweave_byte_pricing },
    #{ name => <<"bundler-settlement@1.0">>, root => dev_bundler_settlement },
    #{ name => <<"pricing-router@1.0">>, root => dev_pricing_router },
    #{ name => <<"process-ledger@1.0">>, root => dev_process_ledger },
    #{ name => <<"simple-oracle@1.0">>, root => dev_simple_oracle }
].

Wallet =
    case os:getenv("LAPEE_DEVICE_WALLET") of
        false -> ar_wallet:new();
        WalletPath -> hb:wallet(hb_util:bin(WalletPath))
    end.

Signer = hb_util:human_id(ar_wallet:to_address(Wallet)).
StoreName =
    <<"cache-LAPEE/external-devices-",
        (integer_to_binary(erlang:system_time(millisecond)))/binary>>.
Store = #{ <<"store-module">> => hb_store_fs, <<"name">> => StoreName }.
Port = 12000 + rand:uniform(40000).
Opts0 = #{
    port => Port,
    <<"port">> => Port,
    <<"store">> => Store,
    <<"priv-wallet">> => Wallet,
    <<"load-remote-devices">> => true,
    <<"trusted-device-signers">> => [Signer]
}.

{ok, _} = application:ensure_all_started(hackney).
ok = hb_store:reset(Store).

ReadSpec =
    fun(Name) ->
        File = filename:join(SpecDir, binary_to_list(Name) ++ ".eterm"),
        {ok, [Spec]} = file:consult(File),
        Spec
    end.

Publish =
    fun(#{ name := Name, root := Root }) ->
        Spec = ReadSpec(Name),
        SpecMsg = hb_message:commit(Spec, Opts0),
        {ok, _SpecCacheID} = hb_cache:write(SpecMsg, Opts0),
        SpecID = hb_message:id(SpecMsg, signed, Opts0),
        #{ module := ModName, beam := Beam, beam_file := BeamFile } =
            hb_device_packager:package(
                Root,
                #{
                    src_dir => SrcDir,
                    out_dir => OutDir,
                    includes => [filename:join(Cwd, "src")]
                }
            ),
        ImplMsg =
            hb_message:commit(
                hb_ao:normalize_keys(
                    #{
                        <<"data-protocol">> => <<"ao">>,
                        <<"variant">> => <<"ao.N.1">>,
                        <<"content-type">> => <<"application/beam">>,
                        <<"implements-device">> => SpecID,
                        <<"module-name">> => hb_util:bin(ModName),
                        <<"requires-otp-release">> =>
                            hb_util:bin(erlang:system_info(otp_release)),
                        <<"body">> => Beam
                    },
                    Opts0
                ),
                Opts0
            ),
        {ok, _ImplCacheID} = hb_cache:write(ImplMsg, Opts0),
        ImplID = hb_message:id(ImplMsg, signed, Opts0),
        #{
            <<"name">> => Name,
            <<"root">> => hb_util:bin(Root),
            <<"spec-id">> => SpecID,
            <<"implementation-id">> => ImplID,
            <<"module">> => hb_util:bin(ModName),
            <<"beam-file">> => hb_util:bin(BeamFile),
            <<"signer">> => Signer
        }
    end.

Published = [Publish(Device) || Device <- Devices].
SpecIDByName =
    maps:from_list([
        {maps:get(<<"name">>, Entry), maps:get(<<"spec-id">>, Entry)}
    ||
        Entry <- Published
    ]).

Gateway = hb_http_server:start_node(Opts0).
ServerOpts = hb_http_server:get_opts(#{ <<"http-server">> => Signer }).
Routes = [
    #{
        <<"template">> => <<"/graphql">>,
        <<"node">> => #{ <<"uri">> => <<Gateway/binary, "/~query@1.0/graphql">> }
    },
    #{
        <<"template">> => <<"^/arweave/raw">>,
        <<"node">> => #{
            <<"match">> => <<"^/arweave/raw/(.*)$">>,
            <<"with">> => <<Gateway/binary, "/\\1/body">>
        }
    }
].
Opts = ServerOpts#{ <<"routes">> => Routes }.

LoadAndSmoke =
    fun(Entry) ->
        Name = maps:get(<<"name">>, Entry),
        SpecID = maps:get(<<"spec-id">>, Entry),
        Module = binary_to_atom(maps:get(<<"module">>, Entry), utf8),
        {ok, Module} = hb_ao_device:load(SpecID, Opts),
        SmokeResult =
            case Name of
                <<"ao-payment@1.0">> ->
                    {error, #{ <<"status">> := 400 }} =
                        hb_ao:resolve(
                            #{ <<"device">> => SpecID },
                            #{ <<"path">> => <<"verify">> },
                            Opts
                        ),
                    ok;
                <<"arweave-byte-pricing@1.0">> ->
                    {ok, 35} =
                        hb_ao:resolve(
                            #{
                                <<"device">> => SpecID,
                                <<"arweave-byte-price">> => 7
                            },
                            #{
                                <<"path">> => <<"quote">>,
                                <<"resource">> => <<"arweave-bytes">>,
                                <<"amount">> => 5
                            },
                            Opts
                        ),
                    ok;
                <<"bundler-settlement@1.0">> ->
                    AoPaymentSpecID = maps:get(<<"ao-payment@1.0">>, SpecIDByName),
                    Token = hb_util:encode(crypto:strong_rand_bytes(32)),
                    Recipient = hb_util:encode(crypto:strong_rand_bytes(32)),
                    Secret = hb_util:encode(crypto:strong_rand_bytes(32)),
                    {ok, SubmitURL, MockHandle} =
                        hb_mock_server:start([
                            {
                                "/",
                                submit,
                                {202, <<"{\"message\":\"Processing DataItem\"}">>}
                            }
                        ]),
                    {ok, #{ <<"bundled-size">> := 128 }} =
                        try
                            WithdrawOpts =
                                hb_private:set(
                                    Opts,
                                    <<"ao-payment-withdraw-secret">>,
                                    Secret,
                                    Opts
                                ),
                            {ok, SettlementResult} =
                                hb_ao:resolve(
                                    #{
                                        <<"device">> => SpecID,
                                        <<"ledger-device">> =>
                                            #{
                                                charge =>
                                                    fun(_Base, _Req, _NodeMsg) ->
                                                        {ok, #{}}
                                                    end
                                            },
                                        <<"pricing-device">> =>
                                            #{
                                                quote =>
                                                    fun(_Base, _Req, _NodeMsg) ->
                                                        {ok, 7}
                                                    end
                                            },
                                        <<"beneficiary">> => Recipient,
                                        <<"withdraw">> => true,
                                        <<"withdraw-device">> => AoPaymentSpecID,
                                        <<"withdraw-token">> => Token,
                                        <<"withdraw-recipient">> => Recipient,
                                        <<"withdrawal-account">> => Token,
                                        <<"submit-url">> => SubmitURL
                                    },
                                    #{
                                        <<"path">> => <<"bundle-complete">>,
                                        <<"bundled-size">> => 128
                                    },
                                    WithdrawOpts
                                ),
                            [Captured] =
                                hb_mock_server:get_requests(submit, 1, MockHandle),
                            Headers = hb_maps:get(<<"headers">>, Captured, #{}, #{}),
                            <<"application/octet-stream">> =
                                hb_maps:get(
                                    <<"content-type">>,
                                    Headers,
                                    undefined,
                                    #{}
                                ),
                            Submitted =
                                hb_util:ok(
                                    dev_codec_ans104:deserialize(
                                        hb_maps:get(
                                            <<"body">>,
                                            Captured,
                                            undefined,
                                            #{}
                                        ),
                                        #{},
                                        WithdrawOpts
                                    )
                                ),
                            true = hb_message:verify(Submitted, all, WithdrawOpts),
                            Token =
                                hb_maps:get(
                                    <<"target">>,
                                    Submitted,
                                    undefined,
                                    WithdrawOpts
                                ),
                            Recipient =
                                hb_maps:get(
                                    <<"recipient">>,
                                    Submitted,
                                    undefined,
                                    WithdrawOpts
                                ),
                            <<"7">> =
                                hb_maps:get(
                                    <<"quantity">>,
                                    Submitted,
                                    undefined,
                                    WithdrawOpts
                                ),
                            {ok, SettlementResult}
                        after
                            hb_mock_server:stop(MockHandle)
                        end,
                    ok;
                <<"pricing-router@1.0">> ->
                    {ok, <<"routed">>} =
                        hb_ao:resolve(
                            #{
                                <<"device">> => SpecID,
                                <<"default-pricing-device">> =>
                                    #{ estimate => fun(_Base, _Req, _NodeMsg) -> {ok, <<"default">>} end },
                                <<"pricing-routes">> => [
                                    #{
                                        <<"template">> => <<"/paid-route">>,
                                        <<"pricing-device">> =>
                                            #{ estimate => fun(_Base, _Req, _NodeMsg) -> {ok, <<"routed">>} end }
                                    }
                                ]
                            },
                            #{
                                <<"path">> => <<"estimate">>,
                                <<"request">> => #{ <<"path">> => <<"/paid-route">> }
                            },
                            Opts
                        ),
                    ok;
                <<"process-ledger@1.0">> ->
                    {error, #{ <<"status">> := 500 }} =
                        hb_ao:resolve(
                            #{ <<"device">> => SpecID },
                            #{
                                <<"path">> => <<"balance">>,
                                <<"target">> => <<"alice">>
                            },
                            Opts
                        ),
                    ok;
                <<"simple-oracle@1.0">> ->
                    {ok, MockURL, MockHandle} =
                        hb_mock_server:start(
                            [
                                {"/ar", ar, {200, <<"{\"prices\":[[1,2.0]]}">>}},
                                {"/ao", ao, {200, <<"{\"prices\":[[1,4.0]]}">>}}
                            ]
                        ),
                    try
                        {ok, 2.0} =
                            hb_ao:resolve(
                                #{ <<"device">> => SpecID },
                                #{
                                    <<"path">> => <<"price-now">>,
                                    <<"ticker">> => <<"AR">>,
                                    <<"oracle-sources">> => #{
                                        <<"AR">> => [
                                            #{
                                                <<"shape">> => <<"coingecko-market-chart">>,
                                                <<"url">> => <<MockURL/binary, "/ar">>
                                            }
                                        ],
                                        <<"AO">> => [
                                            #{
                                                <<"shape">> => <<"coingecko-market-chart">>,
                                                <<"url">> => <<MockURL/binary, "/ao">>
                                            }
                                        ]
                                    }
                                },
                                Opts#{
                                    <<"relay-http-client">> => httpc,
                                    <<"oracle-cache-ttl-ms">> => 0
                                }
                            ),
                        ok
                    after
                        hb_mock_server:stop(MockHandle)
                    end
            end,
        Entry#{ <<"smoke">> => hb_util:bin(SmokeResult) }
    end.

Smoked = [LoadAndSmoke(Entry) || Entry <- Published].

ok = filelib:ensure_dir(filename:join(DistDir, "device-manifest.eterm")).
Manifest = #{
    <<"runtime">> => <<"permaweb/HyperBEAM edge">>,
    <<"runtime-commit">> =>
        hb_util:bin(string:trim(os:cmd("git rev-parse HEAD"))),
    <<"device-dir">> => hb_util:bin(DeviceDir),
    <<"store">> => StoreName,
    <<"signer">> => Signer,
    <<"devices">> => Smoked
}.
ok = file:write_file(
    filename:join(DistDir, "device-manifest.eterm"),
    io_lib:format("~p.~n", [Manifest])
).
ok = file:write_file(
    filename:join(DistDir, "device-manifest.json"),
    hb_json:encode(Manifest)
).

io:format("Published and smoke-tested ~p LapEE device specs.~n", [length(Smoked)]).
io:format("Manifest: ~s~n", [filename:join(DistDir, "device-manifest.eterm")]).
io:format("Signer: ~s~n", [Signer]).
lists:foreach(
    fun(Entry) ->
        io:format(
            "~s spec=~s impl=~s module=~s~n",
            [
                maps:get(<<"name">>, Entry),
                maps:get(<<"spec-id">>, Entry),
                maps:get(<<"implementation-id">>, Entry),
                maps:get(<<"module">>, Entry)
            ]
        )
    end,
    Smoked
).

ok.
