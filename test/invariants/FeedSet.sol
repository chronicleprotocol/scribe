pragma solidity ^0.8.16;

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";
import {LibFeed} from "script/libs/LibFeed.sol";

struct FeedSet {
    LibFeed.Feed[] feeds;
    mapping(address => bool) saved;
    mapping(address => bool) lifted;
}

/**
 * @author Inspired by horsefacts.eth's [article](https://mirror.xyz/horsefacts.eth/Jex2YVaO65dda6zEyfM_-DXlXhOWCAoSpOx5PLocYgw).
 */
library LibFeedSet {
    using LibSecp256k1 for LibSecp256k1.Point;

    function add(FeedSet storage s, LibFeed.Feed memory feed, bool lifted)
        internal
    {
        address addr = feed.pubKey.toAddress();
        if (!s.saved[addr]) {
            s.feeds.push(feed);
            s.saved[addr] = true;
            s.lifted[addr] = lifted;
        }
    }

    function updateLifted(
        FeedSet storage s,
        LibFeed.Feed memory feed,
        bool lifted
    ) internal {
        address addr = feed.pubKey.toAddress();
        require(s.saved[addr], "LibFeedSet::updateLifted: Unknown feed");

        s.lifted[addr] = lifted;
    }

    function liftedFeeds(FeedSet storage s, uint amount)
        internal
        view
        returns (LibFeed.Feed[] memory)
    {
        LibFeed.Feed[] memory feeds = new LibFeed.Feed[](amount);
        uint ctr;
        for (uint i; i < s.feeds.length; i++) {
            address addr = s.feeds[i].pubKey.toAddress();

            if (s.lifted[addr]) {
                feeds[ctr++] = s.feeds[i];

                if (ctr == amount) break;
            }
        }

        require(
            ctr == amount,
            "LibFeedSet::liftedFeeds: Not enough lifted feeds in FeedSet"
        );
        return feeds;
    }

    function rand(FeedSet storage s, uint seed)
        internal
        view
        returns (LibFeed.Feed memory)
    {
        require(s.feeds.length > 0, "LibFeedSet::rand: No feeds in FeedSet");

        return s.feeds[seed % s.feeds.length];
    }
}
