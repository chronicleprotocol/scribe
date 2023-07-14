pragma solidity ^0.8.16;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {IScribe} from "src/IScribe.sol";
import {Scribe} from "src/Scribe.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

// @todo Import IGreenhouse via git repo once public.

/**
 * @title Scribe Management Script
 */
abstract contract ScribeScript is Script {
    IScribe scribe = IScribe(address(0));

    modifier broadcast() {
        vm.startBroadcast();
        _;
        vm.stopBroadcast();
    }

    function deploy() public virtual;

    function deploy(address greenhouse, bytes32 salt, bytes memory creationCode)
        public
        broadcast
    {
        address deployed = IGreenhouse(greenhouse).plant(salt, creationCode);

        string memory log =
            string.concat("Deployed ", vm.toString(salt), " at Address");
        console2.log(log, deployed);
    }

    function poke(
        IScribe.PokeData memory pokeData,
        IScribe.SchnorrData memory schnorrData
    ) public broadcast {
        scribe.poke(pokeData, schnorrData);
    }

    function setBar(uint8 bar) public broadcast {
        scribe.setBar(bar);
    }

    function lift(
        LibSecp256k1.Point memory pubKey,
        IScribe.ECDSAData memory ecdsaData
    ) public broadcast {
        scribe.lift(pubKey, ecdsaData);
    }

    function lift(
        LibSecp256k1.Point[] memory pubKeys,
        IScribe.ECDSAData[] memory ecdsaDatas
    ) public broadcast {
        scribe.lift(pubKeys, ecdsaDatas);
    }

    function drop(uint feedIndex) public broadcast {
        scribe.drop(feedIndex);
    }

    function drop(uint[] memory feedIndexes) public broadcast {
        scribe.drop(feedIndexes);
    }
}

// @todo Remove once imported via public git repo.
interface IGreenhouse {
    /// @notice Plants a new contract with creation code `creationCode` to a
    ///         deterministic address solely depending on the salt `salt`.
    ///
    /// @dev Only callable by toll'ed addresses.
    ///
    /// @dev Note to add constructor arguments to the creation code, if
    ///      applicable!
    ///
    /// @custom:example Appending constructor arguments to the creation code:
    ///
    ///     ```solidity
    ///     bytes memory creationCode = abi.encodePacked(
    ///         // Receive the creation code of `MyContract`.
    ///         type(MyContract).creationCode,
    ///
    ///         // `MyContract` receives as constructor arguments an address
    ///         // and a uint.
    ///         abi.encode(address(0xcafe), uint(1))
    ///     );
    ///     ```
    ///
    /// @param salt The salt to plant the contract at.
    /// @param creationCode The creation code of the contract to plant.
    /// @return The address of the planted contract.
    function plant(bytes32 salt, bytes memory creationCode)
        external
        returns (address);
}
