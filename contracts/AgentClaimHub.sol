// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IAgentIdRegistry {
    function balanceOf(address owner) external view returns (uint256);
}

/// @title AgentClaimHub — Agent ID-gated ERC-20 claim campaigns
/// @notice Anyone can create a claim campaign by funding it with an ERC-20
/// allocation. Only wallets holding an Agent ID (checked on-chain against the
/// official SPACE ID Agent ID registry) can claim, up to a per-wallet limit.
/// @dev Design rules (SPEC §4.1 / §4.3): NO owner, NO pause, NO fees. The only
/// ways tokens ever leave this contract are: claim() to an eligible claimer,
/// cancelCampaign() refund to the creator (before the campaign starts), and
/// settleCampaign() returning the unclaimed remainder to the creator (after
/// the campaign ends). Nobody — including any admin, there is none — can
/// touch the funds of an active campaign.
contract AgentClaimHub is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice The official Agent ID registry on BNB Chain (SPACE ID Agent ID).
    /// Same address as SPEC §3 (0x60b9262456de011f7d15a54cdd8c48baaa8b022f),
    /// written here in EIP-55 checksummed form as Solidity requires.
    address public constant OFFICIAL_AGENT_ID_REGISTRY =
        0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;

    /// @notice Agent ID registry this hub gates on. Immutable.
    /// @dev Constructor accepts a registry address so tests can inject a mock;
    /// passing address(0) selects the official registry above. Production
    /// deployment passes address(0) (or the official address explicitly).
    IAgentIdRegistry public immutable agentIdRegistry;

    struct Campaign {
        address creator;
        IERC20 token;
        uint256 amountPerClaim;
        uint256 totalAllocation;
        uint256 claimedCount; // number of successful claim() calls
        uint256 startTime;
        uint256 endTime;
        uint256 perWalletLimit;
        bool cancelled;
        bool settled;
    }

    Campaign[] private _campaigns;

    /// @dev campaignId => claimer => number of claims made in that campaign.
    mapping(uint256 => mapping(address => uint256)) private _claimedBy;

    /// @notice Global set of addresses that have ever claimed (counted once).
    mapping(address => bool) public hasClaimed;

    /// @notice Total number of successful claim() calls across all campaigns.
    uint256 public totalClaimEvents;

    uint256 private _uniqueClaimerCount;

    event CampaignCreated(
        uint256 indexed campaignId,
        address indexed creator,
        address indexed token,
        uint256 amountPerClaim,
        uint256 totalAllocation,
        uint256 startTime,
        uint256 endTime,
        uint256 perWalletLimit
    );
    event Claimed(uint256 indexed campaignId, address indexed claimer, uint256 amount);
    event CampaignCancelled(uint256 indexed campaignId);
    event CampaignSettled(uint256 indexed campaignId, uint256 remainder);

    constructor(address registry_) {
        agentIdRegistry = IAgentIdRegistry(
            registry_ == address(0) ? OFFICIAL_AGENT_ID_REGISTRY : registry_
        );
    }

    // ------------------------------------------------------------------ views

    function campaignCount() external view returns (uint256) {
        return _campaigns.length;
    }

    function getCampaign(uint256 campaignId) external view returns (Campaign memory) {
        require(campaignId < _campaigns.length, "no campaign");
        return _campaigns[campaignId];
    }

    function claimedBy(uint256 campaignId, address wallet) external view returns (uint256) {
        return _claimedBy[campaignId][wallet];
    }

    /// @notice Tokens already paid out by a campaign.
    function claimedAmount(uint256 campaignId) public view returns (uint256) {
        require(campaignId < _campaigns.length, "no campaign");
        Campaign storage c = _campaigns[campaignId];
        return c.claimedCount * c.amountPerClaim;
    }

    /// @notice Tokens still available to claim from a campaign.
    function remainingAllocation(uint256 campaignId) external view returns (uint256) {
        Campaign storage c = _campaigns[campaignId];
        return c.totalAllocation - c.claimedCount * c.amountPerClaim;
    }

    /// @notice Number of unique addresses that have ever claimed (once each).
    function uniqueClaimers() external view returns (uint256) {
        return _uniqueClaimerCount;
    }

    /// @notice True if the wallet holds an Agent ID per the official registry.
    function holdsAgentId(address w) public view returns (bool) {
        return agentIdRegistry.balanceOf(w) > 0;
    }

    // -------------------------------------------------------------- campaigns

    /// @notice Create a campaign, pulling exactly `totalAllocation` of `token`
    /// from the caller via transferFrom (approve this contract first).
    /// @param perWalletLimit Max claims per wallet; 0 selects the default of 1.
    /// @return campaignId The id of the new campaign.
    function createCampaign(
        address token,
        uint256 amountPerClaim,
        uint256 totalAllocation,
        uint256 startTime,
        uint256 endTime,
        uint256 perWalletLimit
    ) external nonReentrant returns (uint256 campaignId) {
        require(token != address(0), "token zero");
        require(amountPerClaim > 0, "amountPerClaim zero");
        require(totalAllocation >= amountPerClaim, "allocation too small");
        require(endTime > startTime, "bad window");
        require(endTime > block.timestamp, "already ended");
        if (perWalletLimit == 0) perWalletLimit = 1; // SPEC default

        campaignId = _campaigns.length;
        _campaigns.push(
            Campaign({
                creator: msg.sender,
                token: IERC20(token),
                amountPerClaim: amountPerClaim,
                totalAllocation: totalAllocation,
                claimedCount: 0,
                startTime: startTime,
                endTime: endTime,
                perWalletLimit: perWalletLimit,
                cancelled: false,
                settled: false
            })
        );

        IERC20(token).safeTransferFrom(msg.sender, address(this), totalAllocation);

        emit CampaignCreated(
            campaignId,
            msg.sender,
            token,
            amountPerClaim,
            totalAllocation,
            startTime,
            endTime,
            perWalletLimit
        );
    }

    /// @notice Claim `amountPerClaim` from a campaign. Caller must hold an
    /// Agent ID, the campaign window must be active, the caller's per-wallet
    /// limit must not be reached, and allocation must remain.
    function claim(uint256 campaignId) external nonReentrant {
        require(campaignId < _campaigns.length, "no campaign");
        Campaign storage c = _campaigns[campaignId];
        require(!c.cancelled, "cancelled");
        require(!c.settled, "settled");
        require(block.timestamp >= c.startTime, "not started");
        require(block.timestamp <= c.endTime, "ended");
        require(holdsAgentId(msg.sender), "no Agent ID");
        require(_claimedBy[campaignId][msg.sender] < c.perWalletLimit, "limit reached");
        uint256 paidOut = c.claimedCount * c.amountPerClaim;
        require(c.totalAllocation - paidOut >= c.amountPerClaim, "allocation exhausted");

        _claimedBy[campaignId][msg.sender] += 1;
        c.claimedCount += 1;
        totalClaimEvents += 1;
        if (!hasClaimed[msg.sender]) {
            hasClaimed[msg.sender] = true;
            _uniqueClaimerCount += 1;
        }

        c.token.safeTransfer(msg.sender, c.amountPerClaim);

        emit Claimed(campaignId, msg.sender, c.amountPerClaim);
    }

    /// @notice Cancel a campaign before it starts; the full allocation is
    /// returned to the creator. Creator only.
    function cancelCampaign(uint256 campaignId) external nonReentrant {
        require(campaignId < _campaigns.length, "no campaign");
        Campaign storage c = _campaigns[campaignId];
        require(msg.sender == c.creator, "not creator");
        require(!c.cancelled, "cancelled");
        require(!c.settled, "settled");
        require(block.timestamp < c.startTime, "already started");

        c.cancelled = true;
        uint256 remainder = c.totalAllocation - c.claimedCount * c.amountPerClaim;
        if (remainder > 0) {
            c.token.safeTransfer(c.creator, remainder);
        }

        emit CampaignCancelled(campaignId);
    }

    /// @notice Settle a campaign after it ends; the unclaimed remainder is
    /// returned to the creator. Callable by anyone.
    function settleCampaign(uint256 campaignId) external nonReentrant {
        require(campaignId < _campaigns.length, "no campaign");
        Campaign storage c = _campaigns[campaignId];
        require(!c.cancelled, "cancelled");
        require(!c.settled, "settled");
        require(block.timestamp > c.endTime, "not ended");

        c.settled = true;
        uint256 remainder = c.totalAllocation - c.claimedCount * c.amountPerClaim;
        if (remainder > 0) {
            c.token.safeTransfer(c.creator, remainder);
        }

        emit CampaignSettled(campaignId, remainder);
    }
}
