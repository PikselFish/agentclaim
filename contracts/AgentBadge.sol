// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IAgentIdRegistry {
    function balanceOf(address owner) external view returns (uint256);
}

/// @title AgentClaim Pioneer Badge — launch campaign NFT for AgentClaim
/// @notice A free participation badge, claimable only by Agent ID holders:
/// 1 per wallet, hard cap of 500, first come first served. It is NOT an
/// investment asset and carries no promise of value or returns.
/// @dev Owner powers are deliberately minimal (SPEC §4.2 / §4.3): the owner
/// may only open/close claims (setClaimOpen) and set the base URI *before
/// claims have ever been opened*. There is NO owner mint function.
contract AgentBadge is ERC721, Ownable {
    /// @notice The official Agent ID registry on BNB Chain (SPACE ID Agent ID).
    /// Same address as SPEC §3 (0x60b9262456de011f7d15a54cdd8c48baaa8b022f),
    /// written here in EIP-55 checksummed form as Solidity requires.
    address public constant OFFICIAL_AGENT_ID_REGISTRY =
        0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;

    uint256 public constant MAX_SUPPLY = 500;

    /// @notice Agent ID registry this badge gates on. Immutable.
    /// @dev Constructor accepts a registry address so tests can inject a mock;
    /// passing address(0) selects the official registry above.
    IAgentIdRegistry public immutable agentIdRegistry;

    // NOTE: totalSupply and claimedCount are declared first among this
    // contract's own state variables on purpose: the cap test seeds them via
    // hardhat_setStorageAt, locating their slots by scanning storage for the
    // (totalSupply, claimedCount) value pair rather than assuming numbers —
    // OpenZeppelin v5 bases occupy the leading slots (name/symbol/owner).
    uint256 public totalSupply;
    uint256 public claimedCount;
    bool public claimOpen;

    bool private _claimsEverOpened;
    mapping(address => bool) public hasClaimedBadge;
    string private _baseTokenURI;

    event BadgeClaimed(address indexed claimer, uint256 tokenId);
    event ClaimOpenChanged(bool open);

    constructor(address registry_, address owner_)
        ERC721("AgentClaim Pioneer Badge", "ACPB")
        Ownable(owner_)
    {
        agentIdRegistry = IAgentIdRegistry(
            registry_ == address(0) ? OFFICIAL_AGENT_ID_REGISTRY : registry_
        );
    }

    /// @notice Open or close badge claims. Once claims have been opened, the
    /// base URI is locked forever (see setBaseURI).
    function setClaimOpen(bool v) external onlyOwner {
        claimOpen = v;
        if (v) _claimsEverOpened = true;
        emit ClaimOpenChanged(v);
    }

    /// @notice Set the metadata base URI. Only possible before claims have
    /// ever been opened.
    function setBaseURI(string memory u) external onlyOwner {
        require(!_claimsEverOpened, "base URI locked");
        _baseTokenURI = u;
    }

    /// @notice True if the wallet holds an Agent ID per the official registry.
    function holdsAgentId(address w) public view returns (bool) {
        return agentIdRegistry.balanceOf(w) > 0;
    }

    /// @notice Claim one Pioneer Badge. Caller must hold an Agent ID, must
    /// not have claimed before, claims must be open, and the 500 cap must
    /// not be reached. Free — the claimer only pays gas.
    function claimBadge() external {
        require(claimOpen, "claims closed");
        require(holdsAgentId(msg.sender), "no Agent ID");
        require(!hasClaimedBadge[msg.sender], "already claimed");
        require(totalSupply < MAX_SUPPLY, "sold out");

        hasClaimedBadge[msg.sender] = true;
        totalSupply += 1;
        claimedCount += 1;
        _safeMint(msg.sender, totalSupply);

        emit BadgeClaimed(msg.sender, totalSupply);
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }
}
