// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.29;

import {IERC20} from '@openzeppelin/contracts/interfaces/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {AttestationLib} from '@circle-gateway/src/lib/AttestationLib.sol';
import {TransferSpecLib} from '@circle-gateway/src/lib/TransferSpecLib.sol';
import {AddressLib} from '@circle-gateway/src/lib/AddressLib.sol';
import {Cursor} from '@circle-gateway/src/lib/Cursor.sol';

import {MockUSDC} from './MockUSDC.sol';
import {MockGatewayWallet} from './MockGatewayWallet.sol';

contract MockGatewayMinter {
  using SafeERC20 for IERC20;
  using TransferSpecLib for bytes29;

  error InvalidAttestationSigner();
  error MustHaveAtLeastOneAttestation();

  event Minted(address indexed token, address indexed recipient, uint256 value);

  MockGatewayWallet public immutable GATEWAY_WALLET;

  uint256 public nextFee;
  bool public mintBeforeBurn;

  constructor(address gatewayWallet) {
    GATEWAY_WALLET = MockGatewayWallet(gatewayWallet);
  }

  /// @dev By default, pays with tokens released by gatewayBurn. Mint-before-burn mode leaves
  /// source settlement to the handler, matching Circle's ordering. Signature checking is reduced
  /// to a non-empty length; the controller validates the attestation itself before calling.
  function gatewayMint(bytes memory attestationPayload, bytes memory signature) external {
    require(signature.length > 0, InvalidAttestationSigner());

    Cursor memory cursor = AttestationLib.cursor(attestationPayload);
    require(cursor.numElements > 0, MustHaveAtLeastOneAttestation());

    while (!cursor.done) {
      bytes29 spec = AttestationLib.getTransferSpec(AttestationLib.next(cursor));

      address token = AddressLib._bytes32ToAddress(spec.getSourceToken());
      address depositor = AddressLib._bytes32ToAddress(spec.getSourceDepositor());
      address recipient = AddressLib._bytes32ToAddress(spec.getDestinationRecipient());
      uint256 value = spec.getValue();

      uint256 fee = nextFee;
      nextFee = 0;

      if (mintBeforeBurn) {
        MockUSDC(token).mint(recipient, value);
      } else {
        GATEWAY_WALLET.gatewayBurn(token, depositor, value, fee);
        IERC20(token).safeTransfer(recipient, value);
      }

      emit Minted(token, recipient, value);
    }
  }

  function setMintBeforeBurn() external {
    mintBeforeBurn = true;
  }

  function setNextFee(uint256 fee) external {
    nextFee = fee;
  }
}
