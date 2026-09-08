# ReinvestmentController

Reinvestment controller for Aave v4. Sweeps idle USDC out of the Hub, deposits it into
Circle's Gateway, and reclaims it on demand.

Deployed behind a `TransparentUpgradeableProxy`. Protocol addresses are immutable on the
implementation; limits and roles are set in `initialize`.

## Flow

- `invest` — sweeps from the Hub and deposits into the Gateway wallet
- `divest` — mints against a Circle attestation and reclaims to the Hub
- `initiateWithdrawal` / `withdraw` — on-chain exit path, subject to the Gateway's delay
- `isValidSignature` — ERC-1271, authorises burn intents signed by a `KEEPER_ROLE` holder

How much can be invested is bounded by the absolute exposure cap, the exposure cap in BPS of
supplied assets, and a liquid buffer of Hub liquidity that must stay idle. Set the absolute exposure
cap to zero to sunset.

## Fee accounting

The Gateway debits `amount + fee` when Circle burns, but mints only `amount`. Left alone,
each divest leaves the Hub's `swept` figure overstating the balance actually recoverable at
the Gateway. That is not just an unrecoverable balance: `swept` is counted at face value in
the Hub's `totalAddedAssets`, so the gap prices into supplier shares as phantom assets, and
the Hub has no way to write it down — `reportDeficit` is spoke-only and untied to `swept`.

So `divest` pre-pays: the caller transfers `maxFee` in, and the controller reclaims
`amount + maxFee`. The pre-payment is `maxFee` regardless of what Circle actually charges,
because a lower fee is not knowable on-chain — Circle attests before it burns, and neither the
attestation nor the transfer spec carries a fee. Circle charges a flat fee equal to `maxFee`
today, so the two match exactly and nothing is left behind. Were it ever to charge less, the
difference would stay in the Gateway, leaving it holding more than `swept` rather than less —
the opposite of the phantom-asset case above, and the safe direction. `initiateWithdrawal` caps
its withdrawal at `swept`, so neither that residue nor a third-party `depositFor` donation can
block the exit.

The attestation names **the controller** as `destinationRecipient`, not the Hub. Minting
straight to the Hub would remove the transfer, but `Hub.reclaim` only checks that the Hub's
aggregate balance covers `liquidity + amount` — a floor any USDC sitting there satisfies,
whatever its origin. Routing through the controller keeps the chain self-verifying: it
receives exactly `amount`, transfers exactly `amount + maxFee`, reclaims the same, each step
proven by its own balance rather than by a balance coincidence at the Hub. It also keeps
`_validateTransferSpec` pinning depositor, recipient, signer and destination caller all to
`self`, which is what makes the spec check easy to audit.

## Trust assumptions

The Gateway is Circle's. We depend on them for:

- **Attestations.** Minting requires a payload signed by an attestation signer. The signer
  set is controlled by the minter's owner, and attestations are obtained off-chain via
  Circle's API. Transaction size limit is imposed by the API.
- **Burns.** After attesting a burn intent, Circle debits the wallet balance out-of-band.
  The controller cannot trigger or observe it, so a divest mints without a matching burn
  from our side.
- **Withdrawal delay.** The on-chain exit delay is the wallet's `withdrawalDelay`, owner
  controlled. The controller does not enforce its own.
- **Pausing and denylisting.** Circle can pause either contract, denylist the controller,
  or drop USDC support. Any of these halts `invest`, `divest` or `withdraw`.
- **Upgradeability.** Both the wallet and the minter are upgradeable by Circle. This contract is
  upgradeable in case it needs to be updated post Circle upgrade.

On the Aave side, only governance can attach or detach the controller, via
`Hub.updateAssetConfig`. It cannot be detached while the asset still has a swept balance.

Note that `isValidSignature` is a view function and cannot record what it has signed for.
Multiple burn intents are each validated against the same balance; the wallet's own
accounting is what prevents over-burning.

## Usage

```shell
forge build
forge test
```

Fork tests run against mainnet and need `RPC_MAINNET` set in `.env`.
