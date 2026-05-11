# LapEE Device Package

This repository contains the non-upstream HyperBEAM devices used by the LapEE
bundler build. The runtime stays on upstream `permaweb/HyperBEAM` `edge`; these
devices are published as AO messages and loaded by spec ID from a trusted signer.

## Devices

- `ao-payment@1.0`
- `arweave-byte-pricing@1.0`
- `bundler-settlement@1.0`
- `pricing-router@1.0`
- `process-ledger@1.0`
- `simple-oracle@1.0`

The public `ao-payment@1.0` route is retained for existing clients. Its package
root is `dev_aopayment` so the Erlang namespace stays single-purpose.

## Local Package Checks

```sh
cd /home/fn/Dev/hb_nodes/lapee-devices-clean
rebar3 hb_device package
rebar3 hb_device verify
```

The packager writes generated BEAMs under `_build/default/packaged-devices/`.

## Local Publish And Smoke Test

Run from a clean HyperBEAM `edge` checkout:

```sh
cd /home/fn/Dev/hb_nodes/hyperbeam-edge-clean
rebar3 shell --eval 'file:script("../lapee-devices-clean/scripts/publish_and_smoke.erl"), halt().'
```

Optional environment:

- `LAPEE_DEVICE_DIR`: device package path. Defaults to `../lapee-devices-clean`.
- `LAPEE_DEVICE_WALLET`: wallet used to sign specs and implementations.

The script writes `dist/device-manifest.eterm` and `dist/device-manifest.json`.
Use the manifest signer in `trusted-device-signers`.

## Local LapEE Node Script

`scripts/start-bulbasaur.sh` starts a local LapEE/Bulbasaur node from a
HyperBEAM checkout and uses this repo as the device package source:

```sh
cd /home/fn/Dev/hb_nodes/lapee-devices-clean
HYPERBEAM_DIR=/home/fn/Dev/hb_nodes/bulbasaur \
HB_KEY=/home/fn/Dev/hb_nodes/bulbasaur/bulbasaur-wallet.json \
./scripts/start-bulbasaur.sh
```

Useful environment:

- `HYPERBEAM_DIR`: HyperBEAM checkout to run. Defaults to `../bulbasaur`.
- `BULBASAUR_DEVICE_DIR` / `LAPEE_DEVICE_DIR`: device package repo. Defaults to this repo.
- `HB_PORT`: node port. Defaults to `8734`.
- `HB_KEY`: node wallet path. Defaults to `bulbasaur-wallet.json` under `HYPERBEAM_DIR`.
- `BULBASAUR_ARWEAVE_COPYCAT_MODE`: defaults to `mempool-sender`; set `block`
  for older HyperBEAM checkouts without mempool copycat support.
- `BULBASAUR_ARWEAVE_COPYCAT_PATH`: explicit copycat path override.
- `BULBASAUR_ARWEAVE_BLOCK_COPYCAT_INTERVAL`: interval such as `5-minutes`, or
  `false` / `0` to disable the worker.

## Runtime Wiring

The LapEE node only needs remote device loading enabled, the package signer
trusted, and local aliases from public device names to spec IDs:

```erlang
#{
    <<"load-remote-devices">> => true,
    <<"trusted-device-signers">> => [<<"SIGNER_ADDRESS">>],
    preloaded_devices => [
        #{<<"name">> => <<"ao-payment@1.0">>, <<"module">> => <<"AO_PAYMENT_SPEC_ID">>},
        #{<<"name">> => <<"arweave-byte-pricing@1.0">>, <<"module">> => <<"ARWEAVE_BYTE_PRICING_SPEC_ID">>},
        #{<<"name">> => <<"bundler-settlement@1.0">>, <<"module">> => <<"BUNDLER_SETTLEMENT_SPEC_ID">>},
        #{<<"name">> => <<"pricing-router@1.0">>, <<"module">> => <<"PRICING_ROUTER_SPEC_ID">>},
        #{<<"name">> => <<"process-ledger@1.0">>, <<"module">> => <<"PROCESS_LEDGER_SPEC_ID">>},
        #{<<"name">> => <<"simple-oracle@1.0">>, <<"module">> => <<"SIMPLE_ORACLE_SPEC_ID">>}
    ]
}.
```
