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

Deploy the L1 and L2 tokens (not included in this repo) that must be supported by the bridge then fill in the addresses of these tokens in `script/input/{chainId}/config.json` as two arrays of address strings under the `tokens` key for both the L1 and L2 domains. On testnet, if the `tokens` key is missing for a domain, mock tokens will automatically be deployed for that domain.

The following command deploys the L1 and L2 sides of the bridge:

```
forge script script/Deploy.s.sol:Deploy --slow --multi --broadcast --verify
```
