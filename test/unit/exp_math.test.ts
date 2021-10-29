import { expect } from 'chai';
import { ethers } from 'hardhat';
import { b2f, f2b } from '../../scripts/utils';
import { ExpMathMock } from '../../typechain';

type TestCase = [bigint, number, bigint, bigint, number];

describe('ExpMath', function () {
  let expMath: ExpMathMock;

  before(async () => {
    expMath = (await ethers.getContract('ExpMathMock')) as ExpMathMock;
  });

  (
    [
      // t0    c0  t12   t    exp
      [100n, 1000, 20n, 120n, 500],
      [100n, 1000, 20n, 140n, 250],
      [100n, 1000, 20n, 110n, Math.sqrt(1000 * 500)],
      [100n, 1997.25, 20n, 110n, Math.sqrt(1997.25 * (1997.25 / 2.0))],
      [0n, 1997.25, 75n ** 5n, 75n ** 5n - 1n, 1997.25 * Math.pow(0.5, (75 ** 5 - 1) / 75 ** 5)],
      // [0n, 199700000000.45, 75n ** 5n, 75n ** 5n - 1n, 199700000000.45 * Math.pow(0.5, (75 ** 5 - 1) / 75 ** 5)], //TODO: fails
      [
        0n,
        4503599627370449.333,
        75n ** 5n,
        75n ** 5n - 1n,
        4503599627370449.333 * Math.pow(0.5, (75 ** 5 - 1) / 75 ** 5),
      ],
      [
        0n,
        Number.MAX_SAFE_INTEGER / 2.0,
        75n ** 5n,
        75n ** 5n - 1n,
        (Number.MAX_SAFE_INTEGER / 2.0) * Math.pow(0.5, (75 ** 5 - 1) / 75 ** 5),
      ],
    ] as TestCase[]
  ).forEach(([t0, c0, t12, t, expected], idx: number) => {
    it(`halfLife: ${idx}`, async function () {
      await expMath.measure(t0, f2b(c0), t12, t);

      const result = b2f(BigInt((await expMath.result()).toBigInt()));

      expect(result).to.approximately(expected, 1e-20);
    });
  });
});
