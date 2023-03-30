pragma solidity ^0.8.16;

import {LibSecp256k1} from "./libs/LibSecp256k1.sol";

interface IScribeAuth {
    event FeedLifted(address indexed caller, address indexed feed);
    event FeedDropped(address indexed caller, address indexed feed);
    event BarUpdated(address indexed caller, uint8 oldBar, uint8 newBar);

    function feeds(address who) external view returns (bool);
    function feeds() external view returns (address[] memory);
    function lift(LibSecp256k1.Point memory pubKey) external;
    function lift(LibSecp256k1.Point[] memory pubKeys) external;
    function drop(LibSecp256k1.Point memory pubKey) external;
    function drop(LibSecp256k1.Point[] memory pubKeys) external;

    function bar() external view returns (uint8);
    function setBar(uint8 bar) external;
}
