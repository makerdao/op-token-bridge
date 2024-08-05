# MakerDAO OP Token Bridge

## Overview

The OP Token Bridge is a [custom bridge](https://docs.optimism.io/builders/app-developers/bridging/custom-bridge) to an OP Stack L2 that allows users to deposit a supported token to the L2 and withdraw it back to Ethereum. It operates similarly to the previously deployed [Optimism Dai Bridge](https://github.com/makerdao/optimism-dai-bridge) and relies on the same security model but allows MakerDAO governance to update the set of tokens supported by the bridge.

## Contracts

- `L1TokenBridge.sol` - L1 side of the bridge. Transfers the deposited tokens into an escrow contract. Transfer them back to the user upon receiving a withdrawal message from the `L2TokenBridge`.
- `L2TokenBridge.sol` - L2 side of the bridge. Mints new L2 tokens after receiving a deposit message from `L1TokenBridge`. Burns L2 tokens when withdrawing them to L1.
- `Escrow.sol` - Escrow contract that holds the bridged tokens on L1.
- `L1GovernanceRelay.sol` - L1 side of the governance relay, which allows governance to exert admin control over the deployed L2 contracts.
- `L2GovernanceRelay.sol` - L2 side of the governance relay

### External dependencies

- The L2 implementations of the bridged tokens are not provided as part of this repository and are assumed to exist in external repositories. It is assumed that only simple, regular ERC20 tokens will be used with this bridge. In particular, the supported tokens are assumed to revert on failure (instead of returning false) and do not execute any hook on transfer.

## User flows

### L1 to L2 deposits

To deposit a given amount of a supported token to the L2, Alice calls `bridgeERC20[To]()` on the `L1TokenBridge`. This call locks Alice's tokens into the `Escrow` contract and calls the [L1CrossDomainMessenger](https://github.com/ethereum-optimism/optimism/blob/9001eef4784dc2950d0bdcda29752cb2939bae2b/packages/contracts-bedrock/src/L1/L1CrossDomainMessenger.sol) which instructs the sequencer to asynchroneously relay a cross-chain message on L2. This will involve a call to `finalizeBridgeERC20()` on `L2TokenBridge`, which mints an equivalent amount of L2 tokens for Alice.

### L2 to L1 withdrawals

To withdraw her tokens back to L1, Alice calls `bridgeERC20[To]()` on the `L2TokenBridge`. This call burns Alice's tokens and calls the [L2CrossDomainMessenger](https://github.com/ethereum-optimism/optimism/blob/9001eef4784dc2950d0bdcda29752cb2939bae2b/packages/contracts-bedrock/src/L2/L2CrossDomainMessenger.sol), which will eventually (after the ~7 days security period) allow the permissionless finalization of the withdrawal on L1. This will involve a call to `finalizeBridgeERC20()` on the `L1TokenBridge`, which releases an equivalent amount of L1 tokens from the `Escrow` to Alice.

## Upgrades

### Upgrade to a new bridge (and deprecate this bridge)

1. Deploy the new token bridge and connect it to the same escrow as the one used by this bridge. The old and new bridges can operate in parallel.
2. Optionally, deprecate the old bridge by closing it. This involves calling `close()` on both the `L1TokenBridge` and `L2TokenBridge` so that no new outbound message can be sent to the other side of the bridge. After all cross-chain messages are done processing (can take ~1 week), the bridge is effectively closed and governance can consider revoking the approval to transfer funds from the escrow on L1 and the token minting rights on L2.

### Upgrade a single token to a new bridge

To migrate a single token to a new bridge, follow the steps below:

1. Deploy the new token bridge and connect it to the same escrow as the one used by this bridge.
2. Unregister the token on both `L1TokenBridge` and `L2TokenBridge`, so that no new outbound message can be sent to the other side of the bridge for that token.

## Deployment

### Declare env variables

Add the required env variables listed in `.env.example` to your `.env` file, and run `source .env`.

Make sure to set the `L1` and `L2` env variables according to your desired deployment environment. To deploy the bridge on Base, use the following values:

Mainnet deployment:

```
L1=mainnet
L2=base
```

Testnet deployment:

```
L1=sepolia
L2=base_sepolia
```

### Deploy the bridge

Fill in the required variables into your domain config in `script/input/{chainId}/config.json` by using `base` or `base_sepolia` as an example. Deploy the L1 and L2 tokens (not included in this repo) that must be supported by the bridge then fill in the addresses of these tokens in `script/input/{chainId}/config.json` as two arrays of address strings under the `tokens` key for both the L1 and L2 domains. On testnet, if the `tokens` key is missing for a domain, mock tokens will automatically be deployed for that domain.

The following command deploys the L1 and L2 sides of the bridge:

```
forge script script/Deploy.s.sol:Deploy --slow --multi --broadcast --verify
```

### Initialize the bridge

On mainnet, the bridge should be initialized via the spell process. Importantly, the spell caster should add at least 20% gas on top of the estimated gas limit to account for the possibility of a sudden spike in the amount of gas burned to pay for the L1 to L2 message. On testnet, the bridge initialization can be performed via the following command:

```
forge script script/Init.s.sol:Init --slow --multi --broadcast
```

### Test the deployment

Make sure the L1 deployer account holds at least 10^18 units of the first token listed under `"l1Tokens"` in `script/output/{chainId}/deployed-latest.json`. To perform a test deposit of that token, use the following command:

```
forge script script/Deposit.s.sol:Deposit --slow --multi --broadcast
```

To subsequently perform a test withdrawal, use the following command:

```
forge script script/Withdraw.s.sol:Withdraw --slow --multi --broadcast
```

The message can be relayed manually to L1 using the [Superchain Relayer](https://superchainrelayer.xyz/).
