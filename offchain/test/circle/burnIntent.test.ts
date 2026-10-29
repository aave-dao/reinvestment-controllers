import {decodeAbiParameters, hashTypedData, pad, recoverTypedDataAddress, toHex} from 'viem';
import {generatePrivateKey, privateKeyToAccount} from 'viem/accounts';
import {describe, expect, it} from 'vitest';
import {
  buildBurnIntent,
  burnIntentTypes,
  encodeBurnIntent,
  gatewayDomain,
  getTransferSpecHash,
  signBurnIntent,
} from '../../src/circle/burnIntent.js';
import {burnIntent} from '../signer/helpers.js';

const ENCODED_BURN_INTENT =
  '0x070afbc2ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000010c8e000000154ca85def700000001000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000003b9aca00000000000000000000000000000000000000000000000000000000000000000500000000';
const TRANSFER_SPEC_HASH = '0x1ff73c8b023a454176cd9be62217a7560d2e08ebfb70f0029ad9c7664f280df5';
const TYPED_DATA_HASH = '0x7c3bb306c47a77c43577f44e3cd21721840fee7411fbe36a5bded0b53ec45fd2';

const CONTROLLER = '0x1111111111111111111111111111111111111111';
const GATEWAY_WALLET = '0x2222222222222222222222222222222222222222';
const GATEWAY_MINTER = '0x3333333333333333333333333333333333333333';
const USDC = '0x4444444444444444444444444444444444444444';

function defaultIntent() {
  return buildBurnIntent({
    controller: CONTROLLER,
    gatewayWallet: GATEWAY_WALLET,
    gatewayMinter: GATEWAY_MINTER,
    usdc: USDC,
    domain: 0,
    value: 1_000_000_000n,
    maxFee: 1_100_000n,
    maxBlockHeight: 24_000_000n,
    salt: toHex(7, {size: 32}),
  });
}

describe('encodeBurnIntent', () => {
  it('matches BurnIntentLib.encodeBurnIntent', () => {
    expect(encodeBurnIntent(burnIntent.message)).toBe(ENCODED_BURN_INTENT);
  });
});

describe('getTransferSpecHash', () => {
  it('matches keccak256 of TransferSpecLib.encodeTransferSpec', () => {
    expect(getTransferSpecHash(burnIntent.message)).toBe(TRANSFER_SPEC_HASH);
  });
});

describe('burnIntentTypes', () => {
  it('hashes to BurnIntentLib.getTypedDataHash under the GatewayWallet domain', () => {
    expect(hashTypedData(burnIntent)).toBe(TYPED_DATA_HASH);
  });
});

describe('buildBurnIntent', () => {
  it('pins every party to the controller on the same domain', () => {
    const {maxBlockHeight, maxFee, spec} = defaultIntent();

    expect({maxBlockHeight, maxFee}).toEqual({maxBlockHeight: 24_000_000n, maxFee: 1_100_000n});
    expect(spec).toEqual({
      version: 1,
      sourceDomain: 0,
      destinationDomain: 0,
      sourceContract: pad(GATEWAY_WALLET),
      destinationContract: pad(GATEWAY_MINTER),
      sourceToken: pad(USDC),
      destinationToken: pad(USDC),
      sourceDepositor: pad(CONTROLLER),
      destinationRecipient: pad(CONTROLLER),
      sourceSigner: pad(CONTROLLER),
      destinationCaller: pad(CONTROLLER),
      value: 1_000_000_000n,
      salt: toHex(7, {size: 32}),
      hookData: '0x',
    });
  });
});

describe('signBurnIntent', () => {
  it('wraps the keeper signature with the encoded intent', async () => {
    const account = privateKeyToAccount(generatePrivateKey());
    const intent = defaultIntent();

    const [keeperSignature, payload] = decodeAbiParameters(
      [{type: 'bytes'}, {type: 'bytes'}],
      await signBurnIntent(account, intent),
    );

    expect(payload).toBe(encodeBurnIntent(intent));
    expect(
      await recoverTypedDataAddress({
        domain: gatewayDomain,
        types: burnIntentTypes,
        primaryType: 'BurnIntent',
        message: intent,
        signature: keeperSignature,
      }),
    ).toBe(account.address);
  });
});
