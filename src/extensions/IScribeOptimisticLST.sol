// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;
// forgefmt: disable-start

import {IScribeOptimistic} from "../IScribeOptimistic.sol";

import {IRateSource} from "./external_/interfaces/IRateSource.sol";

interface IScribeOptimisticLST is IScribeOptimistic, IRateSource {}

// forgefmt: disable-end
