---
name: test-conventions
description: Write and review Foundry tests in this repository against the Aave V4-family convention. Use when adding or modifying anything under tests/, when naming a test function, when restructuring or splitting a test file, when adding fuzz coverage, or when checking an existing suite against Aave review expectations. Covers file and contract naming, exact error names after revertsWith_, bare test_<fn>() happy paths, bounded fuzzing, test layering, and formatting.
---

# Foundry Test Conventions

Produce tests that match the Aave V4 family convention, so that suites in this
repository read the same way as the code Aave reviewers already maintain. The
authoritative reference repositories are `aave-v4` and `aave-v4-risk-stewards`.
Older Aave repositories vary and are not authoritative; do not copy them.

## Workflow

1. Place the test in the correct file and contract.
   - Name files `Subject.Feature.t.sol`, for example
     `ReinvestmentController.Invest.t.sol`.
   - Name test contracts with the fully qualified subject, for example
     `ReinvestmentControllerInvestTest`. Never use a bare name such as
     `InvestTest` or `DivestTest`.
   - Keep the shared fixture in `Subject.Base.t.sol` as `<Subject>TestBase`.
   - Use one test contract per function under test.
   - Put shared setup in the base fixture rather than duplicating it per file.

2. Name revert tests after the error, never after the condition.
   - Use `test_<fn>_revertsWith_<ExactErrorName>`, where the error name is the
     selector name in PascalCase, copied exactly.
   - Prefer `test_invest_revertsWith_AccessControlUnauthorizedAccount` over
     `test_invest_revertsWith_callerIsNotKeeper`.
   - When several tests expect the same error, append context after the error
     name, for example
     `test_divest_revertsWith_InvalidAmount_amountIsZero`.
   - Keep one test per failure scenario. Treat check ordering as its own
     scenario when the order is load-bearing.

3. Name the canonical happy path with the bare function name.
   - Use `test_invest()`, not `test_invest_successful()`.
   - Write exactly one success test per function, asserting the complete
     resulting state in a single body: balances on every party, accounting,
     allowances, derived views, and the event through `vm.expectEmit` placed
     before the call.
   - Do not split success assertions across several tests.

4. Give any remaining scenario a descriptive name.
   - Examples: `test_invest_partialAmountLeavesRemainingHeadroom`,
     `test_withdraw_whileStillPaused`, `test_setMaxInvest_allowsZeroToSunset`.
   - A separate test requires a genuinely different scenario or setup, not
     merely a different assertion about the same happy path.

5. Add bounded fuzz coverage alongside the unit tests.
   - Aave expects unit plus fuzz for small changes, and integration plus
     invariants for larger ones. A suite of only deterministic tests will be
     flagged in review.
   - Use the same plain `test_` prefix for fuzz tests. Do not use `testFuzz_`;
     `aave-v4` contains roughly 198 fuzz-signature functions and no
     `testFuzz_` prefix at all.
   - Always constrain inputs with `bound()`.
   - Prioritise arithmetic and boundaries: investment limits, buffer and BPS
     arithmetic, divest amounts, withdrawal timing.

6. Choose the right test layer for what is being proven.
   - Use mocks under `tests/mocks/` for logic and revert paths.
   - Keep the pinned-fork suite in `ReinvestmentController.Fork.t.sol` running
     against the real Hub, Gateway wallet, minter and USDC. Mocks alone are
     not sufficient for a contract coupled this tightly to external protocols.
   - Invariants over `liquidity + swept`, caps, and withdrawal state are not
     yet present. Add them when working on that surface.

7. Verify before reporting the work complete.
   - Run `forge test` and confirm the count and that nothing fails.
   - Confirm fuzz tests actually fuzz by checking for `(runs: 256, ...)` in
     the output.
   - Run `npm run lint`, and `npm run lint:fix` to correct drift.

## Output format

A test file follows this shape.

```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {IAccessControl} from '@openzeppelin/contracts/access/IAccessControl.sol';

import {IReinvestmentController} from '../src/ReinvestmentController.sol';
import {ReinvestmentControllerTestBase} from './ReinvestmentController.Base.t.sol';

contract ReinvestmentControllerInvestTest is ReinvestmentControllerTestBase {
  function test_invest_revertsWith_AccessControlUnauthorizedAccount() public {
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(this),
        controller.KEEPER_ROLE()
      )
    );
    controller.invest(1e6);
  }

  function test_invest_revertsWith_InvalidAmount() public {
    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    controller.invest(0);
  }

  function test_invest_withinInvestableAmount(uint256 amount) public {
    amount = bound(amount, 1, INVESTABLE);

    _invest(amount);

    assertEq(controller.getInvestedAmount(), amount);
  }

  function test_invest() public {
    vm.expectEmit(address(controller));
    emit IReinvestmentController.Invested(INVESTABLE);

    _invest(INVESTABLE);

    // full resulting state asserted here
  }
}
```

## Style and formatting

- Do not add `//` or `///` comments to test functions. The name carries the
  meaning. Comments are acceptable only for non-obvious setup inside a body,
  and on shared fixture helpers.
- Format with prettier, never with `forge fmt`. The repository uses single
  quotes, two-space indentation, and a 100 column width, configured in
  `.prettierrc`. Running `forge fmt` will fight that configuration on every
  file.
