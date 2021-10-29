import { Contract } from '@ethersproject/contracts';

export const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';

export enum FacetCutAction {
  Add = 0,
  Replace = 1,
  Remove = 2,
}

export function getSelectors(contract: Contract): string[] {
  return Object.keys(contract.interface.functions).map((x) => contract.interface.getSighash(x));
}

export const BASE = 60n;

export function f2b(x: number): bigint {
  if (x === 0) return 0n;

  const sign = Math.sign(x);
  x *= sign;

  let numerator = 0n;
  let denominator = 1n;

  // eslint-disable-next-line no-constant-condition
  while (true) {
    numerator = numerator * 2n + BigInt(Math.floor(x));
    x -= Math.floor(x);
    if (x === 0) break;
    x = x * 2;
    denominator *= 2n;
  }

  return (BigInt(sign) * numerator * 2n ** BASE) / denominator;
}

export function b2f(x: bigint): number {
  if (x === 0n) return 0;

  return Number(x) / Number(2n ** BASE);
}
