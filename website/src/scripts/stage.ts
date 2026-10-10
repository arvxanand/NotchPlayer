import { mountDesk } from '../notch/desk';
import { createNotch } from '../notch/notch';
import { NOTCHED, PILL } from '../notch/geometry';
import { createPlayer, initial, notchTrack } from '../notch/player';
import type { Source } from '../notch/notch';
import { tracks } from '../data/tracks';
import { demoPlays } from '../data/plays';
import { createTour } from './tour';

const STEP = 3500; // each step of the opening tour

export function mountStage(root: HTMLElement) {
  const host = root.querySelector<HTMLElement>('[data-stage]')!;
  const desk = host.closest<HTMLElement>('.desk')!;
  const tour = createTour();
  let source: Source = 'spotify';

  const notch = createNotch(host, { interactive: true, state: { plays: demoPlays(Date.now()) } });
  const player = createPlayer(tracks, (p) => {
    notch.set({ track: notchTrack(p.track, source), position: p.state.position, playing: p.state.playing,
      shuffle: p.state.shuffle, repeat: p.state.repeat, bands: p.bands });
    sync();
  }, initial(tracks.length, 1, 20));

  // Twin controls (the row and the dock) are kept true to the player, whatever changed it.
  const all = (ctl: string) => root.querySelectorAll<HTMLElement>(`[data-ctl="${ctl}"]`);
  const label = (ctl: string, text: string) => all(ctl).forEach((b) => { const l = b.querySelector('.lbl')!; if (l.textContent !== text) l.textContent = text; });
  const pressed = (ctl: string, on: boolean) => all(ctl).forEach((b) => b.setAttribute('aria-pressed', String(on)));
  let synced = '';
  function sync() {
    // Called on every player frame: only touch the DOM when something it shows changed.
    const key = `${player.state.playing}${source}${notch.state.mac.hasNotch}`;
    if (key === synced) return;
    synced = key;
    label('playpause', player.state.playing ? 'Pause' : 'Play');
    pressed('source', source === 'music'); // a fixed label ("Apple Music") with a pressed state
    pressed('notch', notch.state.mac.hasNotch);
    pressed('pill', !notch.state.mac.hasNotch);
  }

  // Anything the visitor does ends the tour.
  notch.onAction((a) => { tour.cancel(); player.act(a); });
  notch.onSeek((f) => { tour.cancel(); player.seek(f); });
  notch.onChange((_, byUser) => { if (byUser) tour.cancel(); });
  root.addEventListener('focusin', () => tour.cancel()); // a keyboard visitor inside the panel must not have it closed on them
  root.addEventListener('click', (e) => {
    const b = (e.target as HTMLElement).closest<HTMLElement>('[data-ctl]');
    if (!b || b.closest('.np')) return; // the notch's own buttons are the notch's business (trap 14)
    tour.cancel();
    const ctl = b.dataset.ctl;
    if (ctl === 'playpause') player.act('playpause');
    else if (ctl === 'next') player.act('next');
    else if (ctl === 'source') { source = source === 'spotify' ? 'music' : 'spotify'; player.set({}); }
    else if (ctl === 'stats') notch.set({ mode: 'panel', page: 'stats' });
    else if (ctl === 'notch' || ctl === 'pill') { notch.set({ mac: ctl === 'pill' ? PILL : NOTCHED }); desk.dataset.mac = ctl === 'pill' ? 'pill' : 'notch'; }
    sync();
  });

  // Phones get a cropped strip (menu bar + notch) and the button row; re-decided on rotation (trap 6).
  const phone = matchMedia('(max-width: 799px)');
  const strip = () => {
    if (phone.matches) { desk.dataset.strip = '230'; desk.style.setProperty('--strip', '230'); }
    else { delete desk.dataset.strip; desk.style.removeProperty('--strip'); }
  };
  strip();
  phone.addEventListener('change', strip);
  mountDesk(desk);

  // The song only plays while the stage is on screen. Observe the visible desktop, not the notch
  // layer, which a phone strip clips (trap 7).
  const motion = !matchMedia('(prefers-reduced-motion: reduce)').matches;
  let toured = false;
  new IntersectionObserver(([e]) => {
    if (!e.isIntersecting) return player.stop();
    player.start();
    if (toured || !motion) return;
    toured = true;
    // The opening tour, once: open it, change the song, show the stats, then hand over.
    tour.later(() => notch.set({ mode: 'panel', page: 'player' }), 800);
    tour.later(() => player.act('next'), 800 + STEP);
    tour.later(() => notch.set({ page: 'stats' }), 800 + 2 * STEP);
    tour.later(() => notch.set({ mode: 'peek', page: 'player' }), 800 + 3 * STEP);
  }, { threshold: 0.6 }).observe(desk);
  sync();
}
