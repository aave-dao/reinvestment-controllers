import {parseAbi} from 'viem';

export const controllerAbi = parseAbi([
  'function invest(uint256 amount)',
  'function divest(uint256 amount, bytes attestationPayload, bytes signature)',
  'function getInvestableAmount() view returns (uint256)',
  'function getInvestedAmount() view returns (uint256)',
  'function getMaxFee() view returns (uint256)',
  'function getLastInvestTimestamp() view returns (uint256)',
  'function getInvestMinDelay() view returns (uint256)',
  'function paused() view returns (bool)',
  'function GATEWAY_WALLET() view returns (address)',
  'function GATEWAY_MINTER() view returns (address)',
  'function DOMAIN() view returns (uint32)',
  'function USDC() view returns (address)',
]);
