# ReinvestmentController

Reinvestment controller for Aave v4. Sweeps idle USDC out of the Hub, deposits it into
Circle's Gateway, and reclaims it on demand.

Deployed behind a `TransparentUpgradeableProxy`. Protocol addresses are immutable on the
implementation; limits and roles are set in `initialize`.

## Flow

- `invest` — sweeps from the Hub and deposits into the Gateway wallet
- `divest` — mints against a Circle attestation and reclaims to the Hub
- `initiateWithdrawal` / `withdraw` — on-chain exit path, subject to the Gateway's delay
- `isValidSignature` — ERC-1271, authorises burn intents signed by an `INVESTOR_ROLE` holder

How much can be invested is bounded by `maxInvest`, `maxInvestBps` and a `bufferBps` of Hub
liquidity that must stay idle. Set `maxInvest` to zero to sunset.

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
