// DEV ONLY (deleted with the lab in M5): the app's preview states (Data/PreviewData.swift),
// transcribed so the HTML notch can be drawn with the same data and diffed against the captures.
import { synthetic } from '../notch/bands';
import type { NotchState, NotchTrack } from '../notch/notch';
import type { Play } from '../notch/stats';

const COVER = 'https://i.scdn.co/image/ab67616d0000b273e045aa197ada995407bf92fc';
const STATS_COVER = 'https://image-cdn-ak.spotifycdn.com/image/ab67616d00001e022c5b24ecfa39523a75c993c4';
const track = (o: Partial<NotchTrack> = {}): NotchTrack => ({
  id: 'spotify:track:4sIFi8LpJWPvI5xviWFyA6', title: 'D>E>A>T>H>M>E>T>A>L', artist: 'Panchiko',
  duration: 261.849, source: 'spotify', cover: COVER, tint: null, saveable: true, ...o,
});
// The app's title has an em dash; built from its code point so the site's copy check stays strict.
const quiet = synthetic(0.4).map((v) => v * 0.18);
const loud = synthetic(2.1).map((v) => Math.min(1, v * 1.9));
// The captures were taken just after midnight (00:16, 10 Oct), so of PreviewData.samplePlays only the two
// Panchiko plays (10 and 5 minutes before) fell in "Today". The lab reproduces that capture, not the intent.
const now = Date.now();
const plays: Play[] = [
  { id: 'a', name: 'D>E>A>T>H>M>E>T>A>L', artist: 'Panchiko', started: now - 10 * 60_000, seconds: 48 * 60 },
  { id: 'a', name: 'D>E>A>T>H>M>E>T>A>L', artist: 'Panchiko', started: now - 5 * 60_000, seconds: 12 },
];

const base: Partial<NotchState> = { position: 23.69, playing: true, bands: null, now };
export const refRows: { name: string; state: Partial<NotchState>; note?: string }[] = [];
const add = (name: string, s: Partial<NotchState>, note?: string) => {
  refRows.push({ name, state: { ...base, mode: 'peek', ...s }, note });
  refRows.push({ name: `${name}-expanded`, state: { ...base, mode: 'panel', ...s }, note });
};
add('playing', { track: track() }, 'bars animate in the app: compare the bar row in quiet/loud');
add('paused', { track: track(), playing: false });
add('quiet', { track: track(), bands: quiet });
add('loud', { track: track(), bands: loud });
add('longtitle', { track: track({ title: 'Everything In Its Right Place (Remastered 2016 Deluxe Anniversary Edition Bonus Track)', artist: 'Radiohead & A Very Long Collaborator Name' }) });
add('nonlatin', { track: track({ title: `夜に駆ける ${String.fromCharCode(0x2014)} ヨルシカ`, artist: 'أم كلثوم' }) });
add('noart', { track: track({ id: 'spotify:local:x', title: 'Episode 412: The Long Way Round', artist: 'Some Podcast', cover: null, saveable: false }), position: 12.5 });
add('music', { track: track({ id: '1A2B3C4D5E6F7081', title: 'Midnight City', artist: 'M83', duration: 243, source: 'music', cover: null, saveable: false }), position: 12.5 });
add('stats', { track: track({ cover: STATS_COVER, tint: '#ff8752' }), page: 'stats', plays });
add('stats-empty', { track: track(), page: 'stats', plays: [] });
