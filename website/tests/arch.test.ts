import { describe, expect, it } from 'vitest';
import { macArch } from '../src/scripts/arch';

describe('macArch', () => {
  it('trusts Chrome\'s architecture first', () => {
    expect(macArch('arm', 'Intel Iris')).toBe('arm');
    expect(macArch('x86', 'Intel Iris')).toBe('intel');
  });
  it('believes an Apple GPU over an x86 report (Chrome under Rosetta)', () => {
    expect(macArch('x86', 'ANGLE (Apple, ANGLE Metal Renderer: Apple M1, Unspecified Version)')).toBe('arm');
  });
  it('falls back to the GPU name', () => {
    expect(macArch(undefined, 'ANGLE (Apple, ANGLE Metal Renderer: Apple M2 Pro, Unspecified Version)')).toBe('arm');
    expect(macArch(undefined, 'ANGLE (Intel Inc., Intel(R) Iris(TM) Plus Graphics 655, OpenGL 4.1)')).toBe('intel');
    expect(macArch(undefined, 'AMD Radeon Pro 5500M')).toBe('intel');
  });
  it('stays unknown when it cannot tell (Safari masks the GPU), so the button stays', () => {
    expect(macArch(undefined, 'Apple GPU')).toBe('unknown');
    expect(macArch(undefined, undefined)).toBe('unknown');
  });
});
