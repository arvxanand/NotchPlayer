import { describe, expect, it } from 'vitest';
import { storyFrame, GROW_END } from '../src/scripts/storyboard';

const at = (n = 1000) => Array.from({ length: n + 1 }, (_, i) => storyFrame(i / n));

describe('storyFrame', () => {
  it('never goes back a beat as you scroll down, and reaches the last one', () => {
    let last = 0;
    for (const f of at()) { expect(f.beat).toBeGreaterThanOrEqual(last); last = f.beat; }
    expect(last).toBe(4);
  });
  it('is a pure function of p', () => {
    const a = storyFrame(0.7);
    storyFrame(0.1); storyFrame(0.99);
    expect(storyFrame(0.7)).toEqual(a);
  });
  it('grows the desktop over the opening, then stays full', () => {
    expect(storyFrame(0).grow).toBe(0);
    expect(storyFrame(GROW_END).grow).toBe(1);
    let last = 0;
    for (const f of at(100)) { expect(f.grow).toBeGreaterThanOrEqual(last); last = f.grow; }
  });
  it('the first caption arrives the moment the desktop is full', () => {
    expect(storyFrame(GROW_END - 0.001).beat).toBe(0);
    expect(storyFrame(GROW_END).beat).toBe(1);
  });
  it('starts on the bare notch, then peeks, opens, turns to the stats page, then shows the pill', () => {
    expect(storyFrame(0.02).mode).toBe('off');
    expect(storyFrame(0.1).mode).toBe('peek');
    expect(storyFrame(0.4)).toMatchObject({ mode: 'panel', page: 'player', shuffle: false });
    expect(storyFrame(0.55)).toMatchObject({ shuffle: true, repeat: 'all' });
    expect(storyFrame(0.7)).toMatchObject({ page: 'stats', range: 'week' });
    expect(storyFrame(0.8)).toMatchObject({ pill: true, mode: 'peek' });
    expect(storyFrame(0.95)).toMatchObject({ pill: true, mode: 'panel', page: 'player' });
  });
  it('plays the song forward as you scroll, never backward', () => {
    let last = 0;
    for (const f of at()) { expect(f.position).toBeGreaterThanOrEqual(last); last = f.position; }
    expect(storyFrame(1).position).toBe(100);
  });
});
