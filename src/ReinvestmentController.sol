// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {IReinvestmentController} from "./interfaces/IReinvestmentController.sol";

contract ReinvestmentController is IReinvestmentController, AccessControl {}
