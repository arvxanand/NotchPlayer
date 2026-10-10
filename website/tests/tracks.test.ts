import { describe, expect, it } from 'vitest';
import { tracks } from '../src/data/tracks';

describe('demo tracks', () => {
  it('has the four songs with a Spotify id, a cover url and a duration', () => {
    expect(tracks.map((t) => t.artist)).toEqual(['Drake', 'Drake, Majid Jordan', 'Spandau Ballet', 'Post Malone']);
    for (const t of tracks) {
      expect(t.id).toMatch(/^[A-Za-z0-9]{22}$/);
      expect(t.cover).toMatch(/^https:\/\/.+\/image\/[0-9a-f]{40}$/);
      expect(t.duration).toBeGreaterThan(60);
    }
  });
});
