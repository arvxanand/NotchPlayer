/// <reference types="vite/client" />
// DEV ONLY: reference (the app's capture) | HTML | difference. Black in the third cell = a match.
// ?only=<name prefix>  ?h=<px> crops each row  ?bare shows the HTML cell alone at 0,0 (for headless 2x).
import { createNotch } from '../notch/notch';
import { refRows } from '../data/preview-ref';

const urls = import.meta.glob('../../design/refs/*.png', { eager: true, query: '?url', import: 'default' }) as Record<string, string>;
const root = document.getElementById('lab')!;
const q = new URLSearchParams(location.search);
const only = q.get('only'), crop = Number(q.get('h') ?? 0), bare = q.has('bare');
if (bare) root.className = 'bare';
const W = 374, H = crop || 201;

for (const row of q.has('live') ? [] : refRows) {
  if (only && !(row.name === only || (!q.has('exact') && row.name.startsWith(only)))) continue;
  const url = urls[`../../design/refs/${row.name}.png`];
  const sec = document.createElement('section');
  sec.innerHTML = bare ? '<div class="cell" data-k="html"></div>'
    : `<p>${row.name}${row.note ? ` (${row.note})` : ''}</p><div class="row"><div class="cell" data-k="ref"></div><div class="cell" data-k="html"></div><div class="cell mix" data-k="mix"></div></div>`;
  root.append(sec);
  const notchInto = (cell: HTMLElement) => createNotch(cell, { interactive: false, still: true, state: row.state });
  const imgInto = (cell: HTMLElement) => { const i = new Image(); i.src = url; i.width = W; cell.append(i); };
  for (const cell of sec.querySelectorAll<HTMLElement>('.cell')) {
    cell.style.width = `${W}px`; cell.style.height = `${H}px`;
    const k = cell.dataset.k;
    if (k === 'ref') url ? imgInto(cell) : (cell.textContent = 'no reference');
    if (k === 'html') notchInto(cell);
    if (k === 'mix' && url) {
      // Two opaque layers, the second in difference mode: transparent corners compare as white on white.
      const a = document.createElement('div'), b = document.createElement('div');
      a.className = 'layer a'; b.className = 'layer b';
      cell.append(a, b);
      notchInto(a); imgInto(b);
    }
  }
}

// ?live: one interactive notch driven by the scripted player, for transitions, hover and keys.
if (q.has('live')) {
  const { createPlayer, notchTrack } = await import('../notch/player');
  const { tracks } = await import('../data/tracks');
  const { demoPlays } = await import('../data/plays');
  const { NOTCHED, PILL } = await import('../notch/geometry');
  root.innerHTML = '<p>live: hover or click the peek, Esc closes. Keys: n next, p pill, s source.</p><div class="cell" style="width:374px;height:201px;background:#2a1c18"></div>';
  let source: 'spotify' | 'music' = 'spotify';
  const n = createNotch(root.querySelector<HTMLElement>('.cell')!, { interactive: true, state: { plays: demoPlays(Date.now()) } });
  const player = createPlayer(tracks, (p) => n.set({
    track: notchTrack(p.track, source), position: p.state.position, playing: p.state.playing,
    shuffle: p.state.shuffle, repeat: p.state.repeat, bands: p.bands,
  }));
  n.onAction((a) => player.act(a));
  n.onSeek((f) => player.seek(f));
  player.start();
  Object.assign(window, { notch: n, player });
  document.addEventListener('keydown', (e) => {
    if (e.key === 'n') player.act('next');
    if (e.key === 'p') n.set({ mac: n.state.mac.hasNotch ? PILL : NOTCHED });
    if (e.key === 's') { source = source === 'spotify' ? 'music' : 'spotify'; player.set({}); }
  });
}
