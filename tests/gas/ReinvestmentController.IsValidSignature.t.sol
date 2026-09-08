// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.29;

import {IERC1271} from '@openzeppelin/contracts/interfaces/IERC1271.sol';

import {ReinvestmentControllerTestBase} from '../ReinvestmentController.Base.t.sol';

contract ReinvestmentControllerIsValidSignatureGasTest is ReinvestmentControllerTestBase {
  function test_isValidSignature() public {
    _invest(INVESTABLE);
    bytes memory intent = _encodeBurnIntent(_defaultTransferSpec(INVESTABLE / 2));
    (bytes32 digest, bytes memory signature) = _signBurnIntent(keeperPrivateKey, intent);

    bytes4 result = controller.isValidSignature(digest, signature);
    vm.snapshotGasLastFrame('ReinvestmentController.Operations', 'isValidSignature');

    assertEq(result, IERC1271.isValidSignature.selector);
  }
}
