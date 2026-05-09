#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const { Readable } = require("stream");
const { TurboFactory } = require("@ardrive/turbo-sdk");
const { ArweaveSigner: TurboArweaveSigner } = require("@ar.io/sdk");
const {
  ArweaveSigner: BundleArweaveSigner,
  DataItem,
  createData,
} = require("@dha-team/arbundles");

const DEVICES = [
  { name: "ao-payment@1.0", root: "dev_aopayment" },
  { name: "arweave-byte-pricing@1.0", root: "dev_arweave_byte_pricing" },
  { name: "bundler-settlement@1.0", root: "dev_bundler_settlement" },
  { name: "pricing-router@1.0", root: "dev_pricing_router" },
  { name: "process-ledger@1.0", root: "dev_process_ledger" },
  { name: "simple-oracle@1.0", root: "dev_simple_oracle" },
];

const deviceDir = process.env.LAPEE_DEVICE_DIR || path.resolve(__dirname, "..");
const walletPath = process.env.LAPEE_DEVICE_WALLET;
const otpRelease = process.env.LAPEE_OTP_RELEASE || "27";
const uploadServiceUrl =
  process.env.LAPEE_DEVICE_UPLOADER || "https://up.arweave.net";
const requestedNames = new Set(
  (process.env.LAPEE_DEVICE_NAMES || "")
    .split(",")
    .map((name) => name.trim())
    .filter(Boolean)
);

if (!walletPath) {
  throw new Error("Set LAPEE_DEVICE_WALLET to the trusted signer JWK path.");
}

function toBase64Url(value) {
  return typeof value === "string"
    ? value
    : Buffer.from(value).toString("base64url");
}

function addressFromJwk(jwk) {
  return crypto
    .createHash("sha256")
    .update(Buffer.from(jwk.n, "base64url"))
    .digest("base64url");
}

function beamFor(root) {
  const ebin = path.join(deviceDir, "_build/default/packaged-devices/ebin");
  const prefix = `_hb_device_${root}_`;
  const matches = fs
    .readdirSync(ebin)
    .filter((entry) => entry.startsWith(prefix) && entry.endsWith(".beam"));

  if (matches.length !== 1) {
    throw new Error(
      `expected one packaged BEAM for ${root} in ${ebin}, found ${matches.length}`
    );
  }

  const file = matches[0];
  return {
    file: path.join(ebin, file),
    module: path.basename(file, ".beam"),
  };
}

async function signedItem(data, signer, tags) {
  const item = createData(data, signer, {
    tags: Object.entries(tags).map(([name, value]) => ({ name, value })),
  });
  await item.sign(signer);
  const raw = Buffer.from(item.getRaw());
  return {
    id: toBase64Url(item.id || new DataItem(raw).id),
    raw,
  };
}

async function upload(turbo, label, item) {
  const res = await turbo.uploadSignedDataItem({
    dataItemStreamFactory: () => Readable.from(item.raw),
    dataItemSizeFactory: () => item.raw.length,
  });
  const id = res?.id || item.id;
  console.error(`${label} ${id}`);
  return id;
}

async function main() {
  const jwk = JSON.parse(fs.readFileSync(walletPath, "utf8"));
  const signer = addressFromJwk(jwk);
  const bundleSigner = new BundleArweaveSigner(jwk);
  const turbo = TurboFactory.authenticated({
    signer: new TurboArweaveSigner(jwk),
    token: "arweave",
    uploadServiceConfig: { url: uploadServiceUrl },
  });
  const entries = [];

  for (const device of DEVICES) {
    if (requestedNames.size && !requestedNames.has(device.name)) {
      continue;
    }

    const specFile = path.join(deviceDir, "specs", `${device.name}.eterm`);
    const spec = await signedItem(fs.readFileSync(specFile), bundleSigner, {
      "data-protocol": "ao",
      variant: "ao.N.1",
      "content-type": "application/ao-device-spec",
      "device-name": device.name,
      "root-module": device.root,
    });
    await upload(turbo, `${device.name} spec=`, spec);

    const beam = beamFor(device.root);
    const impl = await signedItem(fs.readFileSync(beam.file), bundleSigner, {
      "data-protocol": "ao",
      variant: "ao.N.1",
      "content-type": "application/beam",
      "implements-device": spec.id,
      "module-name": beam.module,
      "requires-otp-release": otpRelease,
      "device-name": device.name,
      "root-module": device.root,
    });
    await upload(turbo, `${device.name} impl=`, impl);

    entries.push({
      name: device.name,
      root: device.root,
      specId: spec.id,
      implementationId: impl.id,
      module: beam.module,
      beamFile: path.relative(deviceDir, beam.file),
      signer,
      specBytes: spec.raw.length,
      implementationBytes: impl.raw.length,
    });
  }

  const manifest = {
    runtime: "permaweb/HyperBEAM edge",
    signer,
    uploader: uploadServiceUrl,
    publishedAt: new Date().toISOString(),
    devices: entries,
  };
  const dist = path.join(deviceDir, "dist");
  fs.mkdirSync(dist, { recursive: true });
  fs.writeFileSync(
    path.join(dist, "device-manifest.json"),
    `${JSON.stringify(manifest, null, 2)}\n`
  );
  console.log(JSON.stringify(manifest, null, 2));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
