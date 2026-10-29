import {parseAbi} from 'viem';

export const controllerAbi = parseAbi([
  'function invest(uint256 amount)',
  'function divest(uint256 amount, bytes attestationPayload, bytes signature)',
  'function getInvestableAmount() view returns (uint256)',
  'function getInvestedAmount() view returns (uint256)',
  'function getMaxFee() view returns (uint256)',
  'function getLastInvestTimestamp() view returns (uint256)',
  'function getInvestMinDelay() view returns (uint256)',
  'function getExposureCapAbs() view returns (uint256)',
  'function getExposureCapBps() view returns (uint256)',
  'function getLiquidBufferBps() view returns (uint256)',
  'function paused() view returns (bool)',
  'function KEEPER_ROLE() view returns (bytes32)',
  'function hasRole(bytes32 role, address account) view returns (bool)',
  'function HUB() view returns (address)',
  'function ASSET_ID() view returns (uint256)',
  'function GATEWAY_WALLET() view returns (address)',
  'function GATEWAY_MINTER() view returns (address)',
  'function DOMAIN() view returns (uint32)',
  'function USDC() view returns (address)',
]);
