// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;
// forgefmt: disable-start

import {IScribe} from "../IScribe.sol";

import {IRateSource} from "./external_/interfaces/IRateSource.sol";

interface IScribeLST is IScribe, IRateSource {}

// forgefmt: disable-end
