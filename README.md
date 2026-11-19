# AgentClaim

**The claim hub for Agent ID holders** — live on BNB Smart Chain.

AgentClaim is a public claim hub where only Agent ID holders can claim. Projects create ERC-20 claim campaigns without writing their own contracts; every claim is gated on-chain by the official Agent ID registry. Its launch campaign is the free Pioneer Badge NFT for the first 500 Agent ID holders.

🌐 **Live product:** https://agentclaim-2ua.pages.dev
🐦 **X:** https://x.com/ugatkai

## How Agent ID is used

Agent ID is the single access key for the whole product:

- Both contracts check `balanceOf(claimer)` on the official Agent ID registry (`0x60b9262456de011f7d15a54cdd8c48baaa8b022f`) **inside the claim transaction itself**, and revert if the wallet holds no Agent ID.
- The website reads the same registry live to show each visitor their eligibility before they connect.
- Holding an Agent ID is what turns a wallet into an eligible participant — projects get distribution that can only reach real Agent ID holders. One person, one Agent ID, no bot farms.

## Contracts (BNB Smart Chain, chainId 56)

| Contract | Address | Verified |
|---|---|---|
| AgentClaimHub | `0x1d3665da429D876f66e63e782BBdF7e22EbFbB0d` | [BscScan](https://bscscan.com/address/0x1d3665da429D876f66e63e782BBdF7e22EbFbB0d) · Sourcify exact match |
| AgentBadge (ACPB) | `0x6BE9e81145628a42Bd9BC005960Ce96D8B73409c` | [BscScan](https://bscscan.com/address/0x6BE9e81145628a42Bd9BC005960Ce96D8B73409c) · Sourcify exact match |

### AgentClaimHub

- `createCampaign(token, amountPerClaim, totalAllocation, perWalletLimit, start, end)` — pulls the exact total allocation into the hub via `transferFrom`. No contract writing needed for project teams.
- `claim(campaignId)` — gated by the Agent ID registry, the per-wallet limit, the campaign window, and the remaining allocation.
- `cancelCampaign(campaignId)` — creator only, before the campaign starts; full refund.
- `settleCampaign(campaignId)` — anyone may call after the campaign ends; the unclaimed remainder returns to the creator.
- **The hub has no owner at all.** No pause switch, no fees, no admin withdrawal. Tokens can only leave the hub as a claim to an eligible Agent ID holder, a pre-start cancellation refund, or the post-end remainder.

### AgentBadge — Pioneer Badge (ACPB)

- Free participation badge, hard cap 500, 1 per wallet, first come first served.
- `claimBadge()` — same on-chain Agent ID gate.
- The owner may only open/close badge claims and set the metadata base URI — and the base URI **locks forever** once claims have ever been opened. There is no owner mint function; badges can only come into existence through `claimBadge()` by an eligible wallet.

## Repository layout

- `contracts/` — the two deployed Solidity sources (solc 0.8.26, OpenZeppelin 5.6.1 patterns), identical to the BscScan-verified code.
- `website/` — the live single-page product (`index.html`, ethers v6 via CDN, reads all figures live from the contracts).

## Disclaimer

The Pioneer Badge is a participation collectible, not an investment. Nothing in this repository or on the website promises returns. Campaign tokens are distributed by their own creators under their own responsibility; AgentClaim provides the gating tool, not an endorsement of any campaign.

## License

MIT
