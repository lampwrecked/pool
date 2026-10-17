// pool — settings shared by /pool/ and /input/
// After you deploy the contract, paste its address here. Leave empty for demo mode.
window.POOL_CONFIG = {
  contract: '',            // the pool engine (PoolEngine.sol), e.g. '0x1234…abcd'
  collection: '',          // the Transient Labs collection the engine mints into
  chainId: 1,              // 1 = Ethereum mainnet, 11155111 = Sepolia (for testing)
  // public read-only RPCs, tried in order (no keys needed)
  rpc: [
    'https://ethereum-rpc.publicnode.com',
    'https://eth.llamarpc.com',
    'https://cloudflare-eth.com',
  ],
  sepoliaRpc: [
    'https://ethereum-sepolia-rpc.publicnode.com',
    'https://rpc.sepolia.org',
  ],
};
