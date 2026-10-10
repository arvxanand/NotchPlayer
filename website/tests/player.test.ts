import { describe, expect, it } from 'vitest';
import { initial, step, act, seek, shuffled, nextRepeat, notchTrack } from '../src/notch/player';
import { tracks } from '../src/data/tracks';

const d = [200, 100, 300, 150];

describe('scripted player', () => {
  it('advances, and moves to the next song at the end', () => {
    let s = initial(4, 0, 199);
    s = step(s, 2, d);
    expect(s.at).toBe(1);
    expect(s.position).toBeCloseTo(1);
  });
  it('stands still when paused', () => {
    const s = act(initial(4, 0, 10), 'playpause');
    expect(step(s, 5, d)).toEqual(s);
  });
  it('repeats one song on repeat one, and wraps after the last song', () => {
    expect(step({ ...initial(4, 2, 299), repeat: 'one' }, 2, d)).toMatchObject({ at: 2 });
    expect(step(initial(4, 3, 149), 2, d)).toMatchObject({ at: 0 });
  });
  it('restarts the song on previous past 3 seconds, as Spotify does', () => {
    expect(act(initial(4, 2, 40), 'previous')).toMatchObject({ at: 2, position: 0 });
    expect(act(initial(4, 2, 1), 'previous')).toMatchObject({ at: 1, position: 0 });
    expect(act(initial(4, 0, 1), 'previous')).toMatchObject({ at: 3 });
  });
  it('shuffles with the current song first and unshuffles back to it', () => {
    const on = act(initial(4, 2, 10), 'shuffle');
    expect(on.order[on.at]).toBe(2);
    expect([...on.order].sort()).toEqual([0, 1, 2, 3]);
    const off = act(on, 'shuffle');
    expect(off.order[off.at]).toBe(2);
    expect(shuffled(4, 1)).toEqual(shuffled(4, 1));
  });
  it('cycles repeat off, all, one', () => {
    expect([nextRepeat('off'), nextRepeat('all'), nextRepeat('one')]).toEqual(['all', 'one', 'off']);
  });
  it('seeks within the song', () => {
    expect(seek(initial(4), 0.5, 200).position).toBe(100);
    expect(seek(initial(4), 2, 200).position).toBe(200);
  });
  it('only offers the + for Spotify', () => {
    expect(notchTrack(tracks[0], 'spotify').saveable).toBe(true);
    expect(notchTrack(tracks[0], 'music').saveable).toBe(false);
  });
});
