// The HTML notch: the app's peek, player panel and stats page, drawn in the app's own window box
// (frame(mac), 374x201 on a notched Mac) so it lines up with the captures pixel for pixel.
// Pure layout comes from geometry.ts; this file only builds and updates the DOM.
import {
  NOTCHED, BOTTOM_R, SHOULDER, PANEL, HIT, BARS,
  collapsed, open, frame, shellPath, peekLayout, panelLayout, type Mac,
} from './geometry';
import { springCurve } from './spring';
import { barHeight, silent } from './bands';
import { mmss, remaining } from './clock';
import { summary, duration, RANGES, type Play, type Range } from './stats';
import * as ico from './icons';

export type Source = 'spotify' | 'music';
export interface NotchTrack {
  id: string; title: string; artist: string; duration: number; source: Source;
  cover: string | null; // null: no artwork, the source's mark stands in
  tint: string | null;  // the cover's accent, or null for white
  saveable: boolean;    // a real Spotify song: the + is drawn
}
export type Repeat = 'off' | 'all' | 'one';
export interface NotchState {
  mac: Mac;
  mode: 'off' | 'peek' | 'panel'; // off: nothing playing, the app draws nothing
  page: 'player' | 'stats';
  track: NotchTrack | null;
  playing: boolean;
  position: number;
  shuffle: boolean;
  repeat: Repeat;
  plays: Play[];
  now: number; // the stats page's clock, ms epoch
  range: Range;
  songs: boolean; // stats: Songs instead of Artists
  bands: number[] | null; // null: settle flat (paused)
}
export type Action = 'playpause' | 'previous' | 'next' | 'shuffle' | 'repeat' | 'save' | 'album' | 'track' | 'artist';
export interface NotchController {
  el: HTMLElement;
  get state(): NotchState;
  set(patch: Partial<NotchState>): void;
  onAction(cb: (a: Action) => void): void;
  onSeek(cb: (fraction: number) => void): void;
  onChange(cb: (s: NotchState, byUser: boolean) => void): void;
  destroy(): void;
}

export const defaultState: NotchState = {
  mac: NOTCHED, mode: 'peek', page: 'player', track: null, playing: true, position: 0,
  shuffle: false, repeat: 'off', plays: [], now: Date.now(), range: 'today', songs: false, bands: null,
};

const esc = (s: string) => s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]!);
const px = (v: number) => `${+v.toFixed(3)}px`;
const box = (r: { x: number; y: number; w: number; h: number }) => `left:${px(r.x)};top:${px(r.y)};width:${px(r.w)};height:${px(r.h)}`;
const mark = (s: Source, side: number) => (s === 'music' ? ico.musicMark(side) : ico.spotifyMark(side));

let ids = 0;

/** `interactive` false draws a still picture (story beats, phone stills): no hit button, no focus. */
export function createNotch(host: HTMLElement, opts: { interactive: boolean; state?: Partial<NotchState>; still?: boolean }): NotchController {
  const id = `np${++ids}`;
  const spring = springCurve(0.38, 0.78);
  const el = document.createElement('div');
  el.className = 'np';
  if (opts.still) el.dataset.still = '';
  el.style.setProperty('--np-spring', spring.css);
  el.style.setProperty('--np-spring-ms', `${spring.durationMs}ms`);
  el.innerHTML = `
    <div class="np-shell">
      <div class="np-peek" aria-hidden="true">
        <span class="np-pmark"></span>
        <span class="np-art np-part"></span>
        <span class="np-bars">${'<i></i>'.repeat(BARS.count)}</span>
      </div>
      <div class="np-panel" id="${id}-panel" role="group" aria-label="Now playing">
        <div class="np-page np-player">
          <button type="button" class="np-art np-aart" data-act="album" aria-label="Album cover"></button>
          <div class="np-text">
            <div class="np-row"><div class="np-names"><button type="button" class="np-title" data-act="track"></button><button type="button" class="np-artist" data-act="artist"></button></div>
              <button type="button" class="np-plus" data-act="save" aria-label="Save the song">${ico.plusCircle()}</button></div>
            <div class="np-progress" role="slider" aria-label="Playback position" aria-valuemin="0" aria-valuemax="100" tabindex="0"><i class="np-track"></i><i class="np-fill"></i><i class="np-knob"></i></div>
            <div class="np-clock"><span class="np-el"></span><span class="np-rem"></span></div>
          </div>
          <div class="np-transport">
            <button type="button" class="np-mode np-shuffle" data-act="shuffle" aria-label="Shuffle">${ico.shuffle()}<i class="np-on"></i></button>
            <button type="button" class="np-tbtn" data-act="previous" aria-label="Previous track">${ico.previous()}</button>
            <button type="button" class="np-tbtn np-pp" data-act="playpause" aria-label="Pause"><span class="np-disc"></span></button>
            <button type="button" class="np-tbtn" data-act="next" aria-label="Next track">${ico.next()}</button>
            <button type="button" class="np-mode np-repeat" data-act="repeat" aria-label="Repeat"><span class="np-rglyph"></span><i class="np-on"></i></button>
          </div>
          <button type="button" class="np-statsbtn" data-page="stats" aria-label="Show your listening stats">${ico.chartBar()}</button>
        </div>
        <div class="np-page np-stats">
          <div class="np-tabs" role="tablist" aria-label="Range">${RANGES.map((r) => `<button type="button" role="tab" class="np-tab" data-range="${r.id}" id="${id}-r-${r.id}" aria-controls="${id}-sbody">${r.title}</button>`).join('')}</div>
          <div class="np-sbody" id="${id}-sbody" role="tabpanel">
            <div class="np-totals"><span class="np-total"></span><span class="np-listened">listened</span><span class="np-count"></span></div>
            <div class="np-top"><div class="np-tabs" role="tablist" aria-label="Show"><button type="button" role="tab" class="np-tab" data-songs="0" id="${id}-a">Artists</button><button type="button" role="tab" class="np-tab" data-songs="1" id="${id}-s">Songs</button></div><ol class="np-rows"></ol></div>
          </div>
          <button type="button" class="np-back sr-only" data-page="player">Back to the player</button>
        </div>
        <div class="np-dots" aria-hidden="true"><i></i><i></i></div>
      </div>
    </div>
    ${opts.interactive ? `<button type="button" class="np-hit" aria-label="Open the player" aria-expanded="false" aria-controls="${id}-panel"></button>` : ''}`;
  host.append(el);

  const q = <T extends Element = HTMLElement>(s: string) => el.querySelector<T>(s)!;
  const shell = q('.np-shell'), peek = q('.np-peek'), panel = q('.np-panel');
  const bars = [...peek.querySelectorAll<HTMLElement>('.np-bars i')];
  const hit = el.querySelector<HTMLButtonElement>('.np-hit');
  const progress = q('.np-progress');
  if (!opts.interactive) {
    // A still is a picture: nothing in it is focusable or announced as a control.
    panel.inert = true;
    el.setAttribute('aria-hidden', 'true');
  }

  let s: NotchState = { ...defaultState, ...opts.state };
  // What is on screen already, so a render at 60fps only touches what changed.
  let shown: { mac?: Mac; track?: NotchTrack | null; repeatOne?: boolean; playing?: boolean; stats?: unknown[] } = {};
  const actions: ((a: Action) => void)[] = [], seeks: ((f: number) => void)[] = [], changes: ((st: NotchState, u: boolean) => void)[] = [];

  /** Positions that depend only on which Mac this is. */
  function layout(m: Mac) {
    const f = frame(m), c = collapsed(m), o = open(m);
    el.style.width = px(f.w); el.style.height = px(f.h);
    el.dataset.pill = String(!m.hasNotch);
    const pl = panelLayout(m);
    panel.style.cssText = box({ x: (f.w - o.w) / 2, y: 0, w: o.w, h: o.h });
    peek.style.cssText = box({ x: (f.w - c.w) / 2, y: 0, w: c.w, h: c.h });
    q('.np-aart').style.cssText = box(pl.art);
    q('.np-text').style.cssText = box(pl.text);
    progress.style.top = px(pl.progressY - pl.text.y);
    q('.np-clock').style.top = px(pl.progressY - pl.text.y + PANEL.progress + PANEL.clockGap + PANEL.clockNudge);
    q('.np-artist').style.marginTop = px(PANEL.artistGap + PANEL.artistGapNudge);
    q('.np-transport').style.cssText = box(pl.transport);
    q('.np-statsbtn').style.cssText = box(pl.stats);
    q('.np-dots').style.top = px(pl.dotsY);
    q('.np-stats').style.paddingTop = px(pl.statsTop);
    if (hit) hit.style.cssText = box({ x: (f.w - c.w) / 2, y: 0, w: c.w, h: Math.max(c.h, 24) });
  }

  function placePeek(t: NotchTrack | null) {
    const p = peekLayout(s.mac, !!t?.cover);
    const pm = q('.np-pmark'), art = q('.np-art.np-part'), bx = q('.np-bars');
    pm.style.cssText = p.mark ? box(p.mark) : 'display:none';
    pm.innerHTML = p.mark && t ? mark(t.source, p.mark.w) : '';
    art.style.cssText = `${box(p.art)};border-radius:${px(p.art.r)}`;
    bx.style.cssText = box(p.bars);
    bx.dataset.min = String(p.bars.min); bx.dataset.max = String(p.bars.max);
  }

  /** The cover slot: an <img> over a slot whose colour is the fallback (the tint, or the shell black). */
  function cover(slot: HTMLElement, t: NotchTrack, side: number, animate: boolean) {
    slot.style.setProperty('--np-slot', t.tint ?? '#000');
    if (!t.cover) { slot.querySelectorAll('img').forEach((i) => i.remove()); slot.innerHTML = mark(t.source, side * 0.62); return; }
    slot.querySelector('.np-mark')?.remove();
    const img = document.createElement('img');
    img.alt = ''; img.decoding = 'async'; img.referrerPolicy = 'no-referrer';
    img.onerror = () => img.remove(); // the slot's colour shows instead
    img.src = t.cover;
    const old = [...slot.querySelectorAll('img')];
    // A cross-dissolve, as ArtworkView: the new cover fades in over the old, which stays opaque.
    if (animate && old.length && !opts.still) {
      img.className = 'np-in';
      img.addEventListener('animationend', () => old.forEach((o) => o.remove()), { once: true });
      setTimeout(() => old.forEach((o) => o.remove()), 600);
    } else old.forEach((o) => o.remove());
    slot.append(img);
  }

  /** Title and artist: the old line lifts out, then the new one rises in (PanelView.textChange). */
  function swapText(btn: HTMLElement, text: string, animate: boolean) {
    const old = btn.querySelector<HTMLElement>('span:not(.np-out)');
    if (old && old.textContent === text) return;
    const span = document.createElement('span');
    span.textContent = text;
    if (animate && old && !opts.still) {
      old.classList.add('np-out');
      setTimeout(() => old.remove(), 140);
      span.classList.add('np-rise');
    } else old?.remove();
    btn.append(span);
  }

  function renderTrack(t: NotchTrack, animate: boolean) {
    placePeek(t);
    cover(q('.np-art.np-part'), t, peekLayout(s.mac, !!t.cover).art.w, animate);
    cover(q('.np-aart'), t, PANEL.art, animate);
    swapText(q('.np-title'), t.title, animate);
    swapText(q('.np-artist'), t.artist, animate);
    q('.np-aart').setAttribute('aria-label', t.source === 'spotify' ? 'Open the album in Spotify' : 'Album cover');
    q('.np-plus').hidden = !t.saveable;
    // The + takes its glyph plus the gap PanelView keeps clear of its 44pt target.
    q('.np-names').style.width = t.saveable ? px(panelLayout(s.mac).text.w - PANEL.plus - ((HIT - PANEL.plus) / 2 + 4)) : '100%';
    el.style.setProperty('--np-accent', t.tint ?? '#fff');
  }

  function renderStats() {
    const sum = summary(s.plays, s.range, s.now);
    q('.np-total').textContent = duration(sum.seconds);
    q('.np-count').textContent = sum.songs === 1 ? '1 song' : `${sum.songs} songs`;
    for (const b of el.querySelectorAll<HTMLElement>('[data-range]')) {
      const on = b.dataset.range === s.range;
      b.setAttribute('aria-selected', String(on)); b.tabIndex = on ? 0 : -1;
    }
    for (const b of el.querySelectorAll<HTMLElement>('[data-songs]')) {
      const on = (b.dataset.songs === '1') === s.songs;
      b.setAttribute('aria-selected', String(on)); b.tabIndex = on ? 0 : -1;
    }
    q('.np-sbody').setAttribute('aria-labelledby', `${id}-r-${s.range}`);
    const entries = s.songs ? sum.tracks : sum.artists;
    const most = Math.max(1, ...entries.map((e) => (s.songs ? e.plays : e.seconds)));
    q('.np-rows').innerHTML = entries.length
      ? entries.map((e, i) => {
        const share = (s.songs ? e.plays : e.seconds) / most;
        const value = s.songs ? (e.plays === 1 ? '1 play' : `${e.plays} plays`) : duration(e.seconds);
        return `<li class="np-srow"><span class="np-rank">${i + 1}</span><span class="np-sname">${esc(e.name)}</span><span class="np-sval">${value}</span>`
          + `<i class="np-sbar" style="--share:${share.toFixed(4)};opacity:${1 - i * 0.25}"></i></li>`;
      }).join('')
      : '<li class="np-none">Nothing yet</li>';
  }

  function renderBars() {
    const bx = q('.np-bars');
    const min = Number(bx.dataset.min), max = Number(bx.dataset.max);
    const v = s.playing && s.bands ? s.bands : silent();
    bars.forEach((b, i) => { b.style.height = px(barHeight(v[i], min, max)); });
  }

  function render() {
    const m = s.mac, t = s.track;
    if (shown.mac !== m) { layout(m); shown.mac = m; shown.track = undefined; }
    const draws = s.mode !== 'off' && !!t;
    const isOpen = draws && s.mode === 'panel';
    el.dataset.mode = draws ? s.mode : 'off';
    el.dataset.npPage = s.page; // not data-page: the click handler reads data-page as "switch to this page"
    const size = isOpen ? open(m) : collapsed(m);
    shell.style.clipPath = `path('${shellPath(size, SHOULDER, isOpen ? BOTTOM_R.open : BOTTOM_R.collapsed, frame(m).w)}')`;
    panel.inert = !isOpen || !opts.interactive;
    q('.np-player').inert = s.page !== 'player';
    q('.np-stats').inert = s.page !== 'stats';
    if (hit) { hit.setAttribute('aria-expanded', String(isOpen)); hit.hidden = !draws; }
    if (t) {
      if (shown.track?.id !== t.id) { renderTrack(t, !!shown.track); shown.track = t; }
      const f = t.duration > 0 ? Math.max(0, Math.min(1, s.position / t.duration)) : 0;
      el.style.setProperty('--np-f', f.toFixed(5));
      progress.setAttribute('aria-valuenow', String(Math.round(f * 100)));
      progress.setAttribute('aria-valuetext', `${mmss(s.position)} of ${mmss(t.duration)}`);
      q('.np-el').textContent = mmss(s.position);
      q('.np-rem').textContent = remaining(s.position, t.duration);
    }
    if (shown.playing !== s.playing) {
      const pp = q('.np-pp');
      pp.setAttribute('aria-label', s.playing ? 'Pause' : 'Play');
      pp.querySelector('.np-disc')!.innerHTML = s.playing ? ico.pause() : ico.play();
      shown.playing = s.playing;
    }
    q('.np-shuffle').dataset.on = String(s.shuffle);
    q('.np-shuffle').setAttribute('aria-pressed', String(s.shuffle));
    const rep = q('.np-repeat');
    rep.dataset.on = String(s.repeat !== 'off');
    rep.setAttribute('aria-pressed', String(s.repeat !== 'off'));
    rep.setAttribute('aria-label', `Repeat ${s.repeat === 'off' ? 'off' : s.repeat === 'all' ? 'all songs' : 'this song'}`);
    if (shown.repeatOne !== (s.repeat === 'one')) { q('.np-rglyph').innerHTML = ico.repeat(s.repeat === 'one'); shown.repeatOne = s.repeat === 'one'; }
    const stats = [s.plays, s.range, s.songs, Math.floor(s.now / 60_000)];
    if (!shown.stats || stats.some((v, i) => v !== shown.stats![i])) { renderStats(); shown.stats = stats; }
    renderBars();
  }

  const set = (patch: Partial<NotchState>, byUser = false) => {
    const wasOpen = s.mode === 'panel';
    s = { ...s, ...patch };
    render();
    if (byUser) changes.forEach((cb) => cb(s, true));
    if (byUser && !wasOpen && s.mode === 'panel' && document.activeElement === hit) q<HTMLElement>('.np-player [data-act="playpause"]').focus({ preventScroll: true });
  };

  // ---- interaction ----
  const ac = new AbortController();
  if (opts.interactive) {
    const on = (t: EventTarget, type: string, fn: (e: any) => void) => t.addEventListener(type, fn, { signal: ac.signal });
    let dragging = false;
    on(hit!, 'click', () => set({ mode: 'panel' }, true));
    // The app's main gesture is hover: arriving on the notch opens it, leaving the panel closes it.
    on(hit!, 'pointerenter', (e: PointerEvent) => { if (e.pointerType === 'mouse') set({ mode: 'panel' }, true); });
    on(shell, 'pointerleave', (e: PointerEvent) => { if (e.pointerType === 'mouse' && s.mode === 'panel' && !dragging) set({ mode: 'peek' }, true); });
    on(el, 'click', (e: MouseEvent) => {
      const t = e.target as HTMLElement;
      const act = t.closest<HTMLElement>('[data-act]')?.dataset.act as Action | undefined;
      if (act) return actions.forEach((cb) => cb(act));
      const page = t.closest<HTMLElement>('[data-page]')?.dataset.page as NotchState['page'] | undefined;
      if (page) { set({ page }, true); return q<HTMLElement>(page === 'stats' ? '.np-stats [aria-selected="true"]' : '.np-statsbtn').focus({ preventScroll: true }); }
      const range = t.closest<HTMLElement>('[data-range]')?.dataset.range as Range | undefined;
      if (range) return set({ range }, true);
      const songs = t.closest<HTMLElement>('[data-songs]')?.dataset.songs;
      if (songs) return set({ songs: songs === '1' }, true);
      if (t.closest('.np-dots')) set({ page: s.page === 'player' ? 'stats' : 'player' }, true);
    });
    // Tabs: arrow keys move and select, as a tablist should.
    on(el, 'keydown', (e: KeyboardEvent) => {
      const tab = (e.target as HTMLElement).closest<HTMLElement>('[role="tab"]');
      if (tab && (e.key === 'ArrowRight' || e.key === 'ArrowLeft')) {
        const list = [...tab.parentElement!.querySelectorAll<HTMLElement>('[role="tab"]')];
        const nextTab = list[(list.indexOf(tab) + (e.key === 'ArrowRight' ? 1 : list.length - 1)) % list.length];
        nextTab.click(); nextTab.focus(); e.preventDefault();
      }
      if (e.target === progress && s.track && (e.key === 'ArrowRight' || e.key === 'ArrowLeft')) {
        const f = (s.position + (e.key === 'ArrowRight' ? 5 : -5)) / s.track.duration;
        seeks.forEach((cb) => cb(Math.max(0, Math.min(1, f)))); e.preventDefault();
      }
    });
    // The progress line: a 30pt tall band answers the pointer, the line grows to 5pt while dragged.
    const fraction = (e: PointerEvent) => { const r = progress.getBoundingClientRect(); return Math.max(0, Math.min(1, (e.clientX - r.left) / r.width)); };
    on(progress, 'pointerdown', (e: PointerEvent) => { dragging = true; progress.setPointerCapture(e.pointerId); el.dataset.drag = ''; seeks.forEach((cb) => cb(fraction(e))); });
    on(progress, 'pointermove', (e: PointerEvent) => { if (dragging) seeks.forEach((cb) => cb(fraction(e))); });
    const end = () => { dragging = false; delete el.dataset.drag; };
    on(progress, 'pointerup', end); on(progress, 'pointercancel', end);
    // On document, not the notch: after a mouse click nothing inside may hold focus.
    on(document, 'keydown', (e: KeyboardEvent) => { if (e.key === 'Escape' && s.mode === 'panel') { set({ mode: 'peek' }, true); hit?.focus({ preventScroll: true }); } }); // a scroll would slide the notch under a resting mouse and reopen it
    on(document, 'pointerdown', (e: PointerEvent) => { if (s.mode === 'panel' && !el.contains(e.target as Node)) set({ mode: 'peek' }, true); });
  }

  render();
  return {
    el,
    get state() { return s; },
    set: (p) => set(p),
    onAction: (cb) => { actions.push(cb); },
    onSeek: (cb) => { seeks.push(cb); },
    onChange: (cb) => { changes.push(cb); },
    destroy: () => { ac.abort(); el.remove(); },
  };
}
