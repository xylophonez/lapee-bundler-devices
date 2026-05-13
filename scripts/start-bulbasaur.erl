%% Run from a HyperBEAM checkout:
%%   BULBASAUR_DEVICE_DIR=/path/to/lapee-bundler-devices \
%%     rebar3 shell --apps hackney \
%%       --eval 'file:script("/path/to/lapee-bundler-devices/scripts/start-bulbasaur.erl").'

{ok, Cwd} = file:get_cwd().

DeviceDir =
    case os:getenv("BULBASAUR_DEVICE_DIR") of
        false ->
            case os:getenv("LAPEE_DEVICE_DIR") of
                false -> filename:absname(filename:join(Cwd, "external_devices/bulbasaur"));
                RawLapeeDeviceDir -> filename:absname(RawLapeeDeviceDir)
            end;
        RawDeviceDir -> filename:absname(RawDeviceDir)
    end.
DeviceSrcDir = filename:join(DeviceDir, "src").
DeviceSpecDir = filename:join(DeviceDir, "specs").
DeviceOutDir = filename:join([DeviceDir, "_build/default/packaged-devices"]).
PluginEbins = [
    filename:join([DeviceDir, "_build/default/plugins/hb_device/ebin"]),
    filename:join([DeviceDir, "apps/hb_device/_build/default/lib/hb_device/ebin"])
].
[code:add_patha(PluginEbin) || PluginEbin <- PluginEbins].
{module, hb_device_packager} = code:ensure_loaded(hb_device_packager).

Price =
    case os:getenv("BULBASAUR_PROCESS_PRICE") of
        false -> 1;
        RawPrice -> list_to_integer(RawPrice)
    end.

BundlerBytePrice =
    case os:getenv("BULBASAUR_BUNDLER_BYTE_PRICE") of
        false -> dynamic;
        "dynamic" -> dynamic;
        RawBundlerBytePrice -> list_to_integer(RawBundlerBytePrice)
    end.
MeteringRates =
    #{ <<"beam-reductions">> => 0 }.
BundlerBytePriceLabel =
    case BundlerBytePrice of
        dynamic ->
            <<"dynamic oracle">>;
        _ ->
            <<(integer_to_binary(BundlerBytePrice))/binary,
                " AO base unit(s)">>
    end.

BundlerMaxItems =
    case os:getenv("BULBASAUR_BUNDLER_MAX_ITEMS") of
        false -> 1000;
        RawBundlerMaxItems -> list_to_integer(RawBundlerMaxItems)
    end.

BundlerDispatchMs =
    case os:getenv("BULBASAUR_BUNDLER_DISPATCH_MS") of
        false -> 2000;
        RawBundlerDispatchMs -> list_to_integer(RawBundlerDispatchMs)
    end.

ArweaveBlockCopycatInterval =
    case os:getenv("BULBASAUR_ARWEAVE_BLOCK_COPYCAT_INTERVAL") of
        false -> <<"5-minutes">>;
        "false" -> disabled;
        "0" -> disabled;
        RawBlockCopycatInterval -> list_to_binary(RawBlockCopycatInterval)
    end.

ArweaveBlockCopycatDepth =
    case os:getenv("BULBASAUR_ARWEAVE_BLOCK_COPYCAT_DEPTH") of
        false -> 10;
        RawBlockCopycatDepth -> list_to_integer(RawBlockCopycatDepth)
    end.

ArweaveCopycatMode =
    case os:getenv("BULBASAUR_ARWEAVE_COPYCAT_MODE") of
        false -> <<"mempool-sender">>;
        RawCopycatMode -> list_to_binary(RawCopycatMode)
    end.

Port =
    case os:getenv("HB_PORT") of
        false -> 8734;
        RawPort -> list_to_integer(RawPort)
    end.
PrimaryStore = #{
    <<"store-module">> => hb_store_fs,
    <<"name">> => <<"cache-bulbasaur-", (integer_to_binary(Port))/binary>>
}.
ArweaveIndexStore = #{
    <<"store-module">> => hb_store_lmdb,
    <<"name">> => <<"cache-bulbasaur-arweave-index-", (integer_to_binary(Port))/binary>>
}.
ArweaveStore = #{
    <<"store-module">> => hb_store_arweave,
    <<"name">> => <<"cache-bulbasaur-arweave-", (integer_to_binary(Port))/binary>>,
    <<"index-store">> => [ArweaveIndexStore],
    <<"local-store">> => [PrimaryStore]
}.
GatewayStore = #{
    <<"store-module">> => hb_store_gateway,
    <<"local-store">> => [PrimaryStore]
}.
Store = [PrimaryStore, ArweaveStore, GatewayStore].

WalletPath =
    case os:getenv("HB_KEY") of
        false -> <<"bulbasaur-wallet.json">>;
        RawWalletPath -> list_to_binary(RawWalletPath)
    end.

AOToken =
    case os:getenv("BULBASAUR_AO_TOKEN") of
        false -> <<"0syT13r0s0tgPmIed95bJnuSqaD29HQNN8D3ElLSrsc">>;
        RawToken -> list_to_binary(RawToken)
    end.
AOSubmitURL =
    case os:getenv("BULBASAUR_AO_SUBMIT_URL") of
        false -> <<"https://mu.ao-testnet.xyz">>;
        RawSubmitURL -> list_to_binary(RawSubmitURL)
    end.

LedgerProcPath =
    case os:getenv("BULBASAUR_LEDGER_PROCESS_FILE") of
        false -> <<"priv/bulbasaur-ledger-process.term">>;
        RawLedgerProcPath -> list_to_binary(RawLedgerProcPath)
    end.

TokenScriptPath =
    case os:getenv("BULBASAUR_TOKEN_SCRIPT") of
        false -> filename:join(Cwd, "scripts/hyper-token.lua");
        RawTokenScriptPath -> filename:absname(RawTokenScriptPath)
    end.
ProcessScriptPath =
    case os:getenv("BULBASAUR_PROCESS_SCRIPT") of
        false -> filename:join(Cwd, "scripts/hyper-token-p4.lua");
        RawProcessScriptPath -> filename:absname(RawProcessScriptPath)
    end.
{ok, TokenScript} = file:read_file(TokenScriptPath).
{ok, ProcessScript} = file:read_file(ProcessScriptPath).

Wallet = hb:wallet(WalletPath).
Operator = hb:address(Wallet).
Beneficiary =
    case os:getenv("BULBASAUR_BENEFICIARY") of
        false -> Operator;
        RawBeneficiary -> list_to_binary(RawBeneficiary)
    end.
WithdrawEnabled =
    case os:getenv("BULBASAUR_WITHDRAW") of
        "true" -> true;
        "1" -> true;
        _ -> false
    end.
WithdrawSecret =
    case os:getenv("BULBASAUR_WITHDRAW_SECRET") of
        false -> hb_util:encode(crypto:strong_rand_bytes(32));
        RawWithdrawSecret -> list_to_binary(RawWithdrawSecret)
    end.
InitialBalance =
    case {os:getenv("BULBASAUR_INITIAL_BALANCE_ADDRESS"), os:getenv("BULBASAUR_INITIAL_BALANCE")} of
        {false, _} -> #{};
        {_, false} -> #{};
        {RawBalanceAddress, RawBalance} ->
            #{ list_to_binary(RawBalanceAddress) => list_to_integer(RawBalance) }
    end.
LedgerCommitOpts = #{
    priv_wallet => Wallet,
    <<"priv-wallet">> => Wallet,
    store => Store,
    <<"store">> => Store
}.

LedgerBaseDef =
    #{
        <<"device">> => <<"process@1.0">>,
        <<"execution-device">> => <<"lua@5.3a">>,
        <<"scheduler-device">> => <<"scheduler@1.0">>,
        <<"scheduler">> => [Operator],
        <<"authority">> => [Operator],
        <<"admin">> => Operator,
        <<"token">> => AOToken,
        <<"balance">> => InitialBalance,
        <<"module">> => [
            #{
                <<"content-type">> => <<"text/x-lua">>,
                <<"name">> => <<"scripts/hyper-token.lua">>,
                <<"body">> => TokenScript
            },
            #{
                <<"content-type">> => <<"text/x-lua">>,
                <<"name">> => <<"scripts/hyper-token-p4.lua">>,
                <<"body">> => ProcessScript
            }
        ]
    }.

NewLedgerProc =
    fun() ->
        Proc =
            hb_message:commit(
                LedgerBaseDef,
                LedgerCommitOpts,
                <<"httpsig@1.0">>
            ),
        ok = filelib:ensure_dir(binary_to_list(LedgerProcPath)),
        ok = file:write_file(LedgerProcPath, term_to_binary(Proc)),
        Proc
    end.

LedgerProc =
    case file:read_file(LedgerProcPath) of
        {ok, LedgerProcBin} ->
            ExistingLedgerProc = binary_to_term(LedgerProcBin),
            case hb_message:signers(ExistingLedgerProc, LedgerCommitOpts) of
                [] ->
                    io:format(
                        "Regenerating unsigned/stale ledger process file: ~s~n",
                        [LedgerProcPath]
                    ),
                    NewLedgerProc();
                _ ->
                    ExistingLedgerProc
            end;
        {error, enoent} ->
            NewLedgerProc();
        {error, LedgerProcReadError} ->
            error({failed_to_read_ledger_process, LedgerProcPath, LedgerProcReadError})
    end.
LedgerProcessID =
    hb_util:human_id(hb_message:id(LedgerProc, signed, LedgerCommitOpts)).

{ok, LedgerCacheID} =
    hb_cache:write(
        LedgerProc,
        LedgerCommitOpts
    ).
LedgerCachePath = hb_util:human_id(LedgerCacheID).
LedgerPath = <<"/ledger~node-process@1.0">>.

Devices = [
    #{ name => <<"ao-payment@1.0">>, root => dev_aopayment },
    #{ name => <<"arweave-byte-pricing@1.0">>, root => dev_arweave_byte_pricing },
    #{ name => <<"bundler-settlement@1.0">>, root => dev_bundler_settlement },
    #{ name => <<"pricing-router@1.0">>, root => dev_pricing_router },
    #{ name => <<"process-ledger@1.0">>, root => dev_process_ledger },
    #{ name => <<"simple-oracle@1.0">>, root => dev_simple_oracle }
].

ReadDeviceSpec =
    fun(Name) ->
        SpecFile = filename:join(DeviceSpecDir, binary_to_list(Name) ++ ".eterm"),
        {ok, [Spec]} = file:consult(SpecFile),
        Spec
    end.

PublishDevice =
    fun(#{ name := Name, root := Root }) ->
        Spec = ReadDeviceSpec(Name),
        SpecMsg =
            hb_message:commit(
                Spec,
                LedgerCommitOpts
            ),
        {ok, _SpecCacheID} = hb_cache:write(SpecMsg, LedgerCommitOpts),
        SpecID = hb_message:id(SpecMsg, signed, LedgerCommitOpts),
        #{ module := ModName, beam := Beam, beam_file := BeamFile } =
            hb_device_packager:package(
                Root,
                #{
                    src_dir => DeviceSrcDir,
                    out_dir => DeviceOutDir,
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
                    LedgerCommitOpts
                ),
                LedgerCommitOpts
            ),
        {ok, _ImplCacheID} = hb_cache:write(ImplMsg, LedgerCommitOpts),
        ImplID = hb_message:id(ImplMsg, signed, LedgerCommitOpts),
        #{
            <<"name">> => Name,
            <<"root">> => hb_util:bin(Root),
            <<"spec-id">> => SpecID,
            <<"impl-id">> => hb_util:human_id(ImplID),
            <<"module">> => hb_util:bin(ModName),
            <<"beam-file">> => hb_util:bin(BeamFile),
            <<"signer">> => Operator
        }
    end.

PublishedDevices = [PublishDevice(Device) || Device <- Devices].
DeviceNameResolver =
    maps:from_list([
        {maps:get(<<"name">>, Entry), maps:get(<<"spec-id">>, Entry)}
    ||
        Entry <- PublishedDevices
    ]).
NameResolvers =
    [DeviceNameResolver |
        hb_opts:get(name_resolvers, [], hb_opts:default_message())].
DefaultPreloadedDevices =
    hb_opts:get(preloaded_devices, [], hb_opts:default_message()),
PackagedPreloadedDevices = [
    #{
        <<"name">> => maps:get(<<"name">>, Entry),
        <<"module">> => maps:get(<<"spec-id">>, Entry)
    }
||
    Entry <- PublishedDevices
],
PreloadedDevices = PackagedPreloadedDevices ++ DefaultPreloadedDevices.

DeviceNames = [
    maps:get(<<"name">>, Entry)
||
    Entry <- PublishedDevices
].

LocalGateway = <<"http://localhost:", (integer_to_binary(Port))/binary>>.
DeviceRoutes = [
    #{
        <<"template">> => <<"/graphql">>,
        <<"node">> => #{ <<"uri">> => <<LocalGateway/binary, "/~query@1.0/graphql">> }
    },
    #{
        <<"template">> => <<"^/arweave/raw">>,
        <<"node">> => #{
            <<"match">> => <<"^/arweave/raw/(.*)$">>,
            <<"with">> => <<LocalGateway/binary, "/\\1/body">>
        }
    }
].
Routes = DeviceRoutes ++ hb_opts:get(routes, [], hb_opts:default_message()).

Processor =
    #{
        <<"device">> => <<"p4@1.0">>,
        <<"ledger-device">> => <<"process-ledger@1.0">>,
        <<"pricing-device">> => <<"pricing-router@1.0">>,
        <<"default-pricing-device">> => <<"simple-pay@1.0">>,
        <<"ledger-path">> => LedgerPath,
        <<"pricing-routes">> => [
            #{
                <<"template">> => <<"/~bundler@1.0/tx">>,
                <<"pricing-device">> => <<"arweave-byte-pricing@1.0">>
            },
            #{
                <<"template">> => <<"/~bundler@1.0/item">>,
                <<"pricing-device">> => <<"arweave-byte-pricing@1.0">>
            }
        ]
    }.

BundlerSettlement =
    #{
        <<"device">> => <<"bundler-settlement@1.0">>,
        <<"ledger-device">> => <<"process-ledger@1.0">>,
        <<"pricing-device">> => <<"arweave-byte-pricing@1.0">>,
        <<"ledger-path">> => LedgerPath,
        <<"settlement-account">> => Operator,
        <<"beneficiary">> => Beneficiary,
        <<"withdraw">> => WithdrawEnabled,
        <<"withdraw-device">> => <<"ao-payment@1.0">>,
        <<"withdraw-token">> => AOToken,
        <<"withdraw-recipient">> => Beneficiary,
        <<"withdrawal-account">> => AOToken,
        <<"hook">> => #{ <<"result">> => <<"ignore">> }
    }.

P4NonChargableRoutes = [
    #{ <<"template">> => <<"/*~node-process@1.0/*">> },
    #{ <<"template">> => << LedgerPath/binary, "/*" >> },
    #{ <<"template">> => <<"/", LedgerProcessID/binary, "~process@1.0/*" >> },
    #{ <<"template">> => <<"/~ao-payment@1.0/*">> },
    #{ <<"template">> => <<"/~p4@1.0/balance">> },
    #{ <<"template">> => <<"/~meta@1.0/*">> },
    #{ <<"template">> => <<"/~query@1.0/*">> },
    #{ <<"template">> => <<"/graphql">> },
    #{ <<"template">> => <<"/schedule">> },
    #{ <<"template">> => <<"/[A-Za-z0-9_-]+/body">> }
].

OptsBase =
    #{
        port => Port,
        <<"port">> => Port,
        priv_key_location => WalletPath,
        priv_wallet => Wallet,
        <<"priv-key-location">> => WalletPath,
        <<"priv-wallet">> => Wallet,
        store => Store,
        <<"store">> => Store,
        load_remote_devices => true,
        <<"load-remote-devices">> => true,
        trusted_device_signers => [Operator],
        <<"trusted-device-signers">> => [Operator],
        name_resolvers => NameResolvers,
        <<"name-resolvers">> => NameResolvers,
        preloaded_devices => PreloadedDevices,
        <<"preloaded-devices">> => PreloadedDevices,
        routes => Routes,
        <<"routes">> => Routes,
        operator => Operator,
        p4_recipient => Operator,
        <<"operator">> => Operator,
        <<"p4-recipient">> => Operator,
        bundler_beneficiary => Beneficiary,
        <<"bundler-beneficiary">> => Beneficiary,
        <<"bundler-max-items">> => BundlerMaxItems,
        bundler_max_items => BundlerMaxItems,
        bundler_max_bundle_dispatch_delay => BundlerDispatchMs,
        <<"bundler-max-bundle-dispatch-delay">> => BundlerDispatchMs,
        arweave_index_store => ArweaveStore,
        <<"arweave-index-store">> => ArweaveStore,
        arweave_mempool_copycat_on_bundle_complete => true,
        <<"arweave-mempool-copycat-on-bundle-complete">> => true,
        arweave_mempool_progress => true,
        <<"arweave-mempool-progress">> => true,
        arweave_index_workers => 1,
        <<"arweave-index-workers">> => 1,
        arweave_pending_chunk_poll_attempts => 20,
        <<"arweave-pending-chunk-poll-attempts">> => 20,
        arweave_pending_chunk_poll_ms => 500,
        <<"arweave-pending-chunk-poll-ms">> => 500,
        simple_pay_price => 0,
        <<"simple-pay-price">> => 0,
        <<"arweave-byte-price">> => BundlerBytePrice,
        <<"metering-rates">> => MeteringRates,
        p4_non_chargable_routes => P4NonChargableRoutes,
        <<"p4-non-chargable-routes">> => P4NonChargableRoutes,
        ao_payment_token => AOToken,
        <<"ao-payment-token">> => AOToken,
        ao_payment_ledger => LedgerProcessID,
        <<"ao-payment-ledger">> => LedgerProcessID,
        ao_payment_deposit_address => Operator,
        <<"ao-payment-deposit-address">> => Operator,
        ao_payment_node => <<"http://localhost:", (integer_to_binary(Port))/binary>>,
        <<"ao-payment-node">> => <<"http://localhost:", (integer_to_binary(Port))/binary>>,
        ao_payment_mainnet_url => <<"https://state.forward.computer">>,
        <<"ao-payment-mainnet-url">> => <<"https://state.forward.computer">>,
        ao_payment_submit_url => AOSubmitURL,
        <<"ao-payment-submit-url">> => AOSubmitURL,
        ao_payment_withdraw_recipient => Beneficiary,
        <<"ao-payment-withdraw-recipient">> => Beneficiary,
        router_opts => #{
            <<"offered">> => [
                #{
                    <<"template">> => <<"/.*~process@1.0/.*">>,
                    <<"price">> => Price
                },
                #{
                    <<"template">> => <<"/~bundler@1.0/tx">>,
                    <<"price">> => 0
                },
                #{
                    <<"template">> => <<"/~bundler@1.0/item">>,
                    <<"price">> => 0
                }
            ]
        },
        <<"router-opts">> => #{
            <<"offered">> => [
                #{
                    <<"template">> => <<"/.*~process@1.0/.*">>,
                    <<"price">> => Price
                },
                #{
                    <<"template">> => <<"/~bundler@1.0/tx">>,
                    <<"price">> => 0
                },
                #{
                    <<"template">> => <<"/~bundler@1.0/item">>,
                    <<"price">> => 0
                }
            ]
        },
        node_processes => #{
            <<"ledger">> => LedgerBaseDef
        },
        <<"node-processes">> => #{
            <<"ledger">> => LedgerBaseDef
        },
        local_names => #{
            <<"ledger">> => LedgerProcessID
        },
        <<"local-names">> => #{
            <<"ledger">> => LedgerProcessID
        },
        on => #{
            <<"request">> => Processor,
            <<"response">> => Processor,
            <<"bundled-message-complete">> => BundlerSettlement
        },
        <<"on">> => #{
            <<"request">> => Processor,
            <<"response">> => Processor,
            <<"bundled-message-complete">> => BundlerSettlement
        }
    }.
Opts =
    case WithdrawEnabled of
        true ->
            hb_private:set(
                OptsBase,
                <<"ao-payment-withdraw-secret">>,
                WithdrawSecret,
                OptsBase
            );
        false ->
            OptsBase
    end.

Node = hb_http_server:start_node(Opts).
{ok, _LedgerScheduleRes} = hb_http:post(Node, <<"/schedule">>, LedgerProc, Opts).

ArweaveBlockCopycatPath =
    case {os:getenv("BULBASAUR_ARWEAVE_COPYCAT_PATH"), ArweaveCopycatMode} of
        {false, <<"block">>} ->
            <<"/~copycat@1.0/arweave?from=-1&to=-",
                (integer_to_binary(ArweaveBlockCopycatDepth))/binary>>;
        {false, _} ->
            <<"/~copycat@1.0/arweave?mode=mempool&sender=", Operator/binary>>;
        {RawCopycatPath, _} ->
            list_to_binary(RawCopycatPath)
    end,
ParseIntervalMs =
    fun(BinInterval) ->
        [AmountBin, UnitBin] = binary:split(BinInterval, <<"-">>),
        Amount = binary_to_integer(AmountBin),
        Unit = string:lowercase(binary_to_list(UnitBin)),
        Multiplier =
            case Unit of
                "millisecond" ++ _ -> 1;
                "second" ++ _ -> 1000;
                "minute" ++ _ -> 60 * 1000;
                "hour" ++ _ -> 60 * 60 * 1000;
                "day" ++ _ -> 24 * 60 * 60 * 1000
            end,
        Amount * Multiplier
    end,
ArweaveBlockCopycatWorker =
    case ArweaveBlockCopycatInterval of
        disabled ->
            disabled;
        _ ->
            IntervalMs = ParseIntervalMs(ArweaveBlockCopycatInterval),
            spawn(
                fun Loop() ->
                    try hb_http:get(Node, ArweaveBlockCopycatPath, Opts) of
                        _ -> ok
                    catch
                        Class:Reason:Stack ->
                            hb_event:log(
                                cron_error,
                                {arweave_block_copycat_error,
                                    {path, ArweaveBlockCopycatPath},
                                    {error, Class, Reason, {trace, Stack}}
                                }
                            )
                    end,
                    timer:sleep(IntervalMs),
                    Loop()
                end
            )
    end.

io:format(
    "~nBulbasaur paid-process node started at ~s~n"
    "Operator: ~s~n"
    "Bundler beneficiary: ~s~n"
    "Bundler withdrawal: ~p~n"
    "Wallet: ~s~n"
    "Device package: ~s~n"
    "Device signer: ~s~n"
    "Devices: ~p~n"
    "Process route price: ~p AO base unit(s)~n"
    "Bundler byte price: ~s~n"
    "Bundler max items: ~p~n"
    "Bundler dispatch delay: ~p ms~n"
    "Bundler optimistic cache: enabled~n"
    "Arweave block copycat interval: ~p~n"
    "Arweave copycat mode: ~s~n"
    "Arweave copycat path: ~s~n"
    "Arweave block copycat depth: ~p block(s)~n"
    "Arweave block copycat worker: ~p~n"
    "AO root token: ~s~n"
    "AO submit URL: ~s~n"
    "Ledger process file: ~s~n"
    "Ledger process ID: ~s~n"
    "AO deposit address: ~s~n"
    "Ledger route: ~s~n"
    "Ledger local cache ID: ~s~n~n",
    [
        Node,
        Operator,
        Beneficiary,
        WithdrawEnabled,
        WalletPath,
        DeviceDir,
        Operator,
        DeviceNames,
        Price,
        BundlerBytePriceLabel,
        BundlerMaxItems,
        BundlerDispatchMs,
        ArweaveBlockCopycatInterval,
        ArweaveCopycatMode,
        ArweaveBlockCopycatPath,
        ArweaveBlockCopycatDepth,
        ArweaveBlockCopycatWorker,
        AOToken,
        AOSubmitURL,
        LedgerProcPath,
        LedgerProcessID,
        Operator,
        LedgerPath,
        LedgerCachePath
    ]
).

%% Keep the evaluator process alive. The HTTP server started by
%% hb_http_server:start_node/1 is linked to this process, so returning to the
%% shell prompt would tear the listener down immediately.
receive
    stop ->
        ok
after
    infinity ->
        ok
end.
