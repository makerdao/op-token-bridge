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
