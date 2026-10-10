import gsap from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';
import { SCREEN } from '../notch/desk';
import { createNotch } from '../notch/notch';
import { demo, envelope, silent } from '../notch/bands';
import { tracks } from '../data/tracks';
import { storyFrame } from './storyboard';
import { notchFor, STORY_TRACK } from './story-notch';

export function mountStory(root: HTMLElement) {
  gsap.registerPlugin(ScrollTrigger);
  const host = root.querySelector<HTMLElement>('[data-story-notch]')!;
  const desk = host.closest<HTMLElement>('.desk')!;
  const canvas = desk.querySelector<HTMLElement>('.desk-canvas')!;
  const hero = root.querySelector<HTMLElement>('.beat[data-beat="0"]')!;
  const win = root.querySelector<HTMLElement>('[data-caption-win]')!;
  // Beats 1-4 become captions in the desktop's window; beat 0 stays the headline block.
  const captions = [...root.querySelectorAll<HTMLElement>('.beat:not([data-beat="0"])')];
  const notch = createNotch(host, { interactive: false });

  // Small under the headline (s0, y0) to filling the window (s1, y1). Re-measured on refresh.
  // clientWidth, not innerWidth: a visible scrollbar would put the notch off centre (trap 5).
  const layout = { s0: 1, s1: 1, y0: 0, y1: 0, w: 0 };
  const measure = () => {
    layout.w = document.documentElement.clientWidth;
    layout.s1 = Math.min(layout.w / SCREEN.w, innerHeight / SCREEN.h);
    layout.s0 = layout.s1 * 0.62;
    layout.y1 = (innerHeight - SCREEN.h * layout.s1) / 2;
    layout.y0 = hero.offsetHeight + 24;
  };

  let p = 0;
  let frame = storyFrame(0);
  const apply = () => {
    frame = storyFrame(p);
    const { s0, s1, y0, y1, w } = layout;
    const s = s0 + (s1 - s0) * frame.grow;
    const y = y0 + (y1 - y0) * frame.grow;
    canvas.style.transform = `translate(${(w - SCREEN.w * s) / 2}px, ${y}px) scale(${s})`;
    hero.style.translate = `0 ${-frame.grow * y0}px`;
    hero.style.opacity = String(1 - frame.grow);
    hero.style.visibility = frame.grow >= 1 ? 'hidden' : '';
    desk.dataset.mac = frame.pill ? 'pill' : 'notch';
    win.classList.toggle('on', frame.beat > 0);
    captions.forEach((b, i) => b.classList.toggle('on', i + 1 === frame.beat));
    const { bands: _, ...state } = notchFor(frame, Date.now());
    notch.set(state);
  };

  // The bars move with the music while the desktop is on screen, at the app's 30 frames a second.
  // Observe the visible desktop, not the clipped notch layer (trap 7).
  const bpm = tracks[STORY_TRACK].bpm;
  let bands = silent(), raf = 0, last = 0, clock = 0;
  const tick = (now: number) => {
    raf = requestAnimationFrame(tick);
    if (now - last < 1000 / 30) return;
    clock += Math.min(0.1, (now - last) / 1000);
    last = now;
    bands = envelope(bands, demo(frame.position + clock, bpm));
    notch.set({ bands });
  };

  const st = ScrollTrigger.create({ trigger: root, start: 'top top', end: 'bottom bottom', onUpdate: (s) => { p = s.progress; apply(); } });
  let io: IntersectionObserver;
  try {
    measure();
    p = st.progress; // a mid-story reload starts where the page is, not at the top (trap 4)
    apply();
    io = new IntersectionObserver(([e]) => {
      cancelAnimationFrame(raf);
      if (e.isIntersecting) { last = performance.now(); raf = requestAnimationFrame(tick); }
    });
    io.observe(desk);
  } catch (e) { st.kill(); notch.destroy(); throw e; } // main.ts falls back to the static stack
  ScrollTrigger.addEventListener('refresh', () => { measure(); p = st.progress; apply(); });
  // Only now, when nothing above can throw: if setup failed, the beats must still be in the static stack (trap 3).
  win.querySelector('.dwin-body')!.append(...captions);

  // Late fonts and resizes change heights: re-measure, never leave a stale pin.
  document.fonts?.ready.then(() => ScrollTrigger.refresh());
  addEventListener('load', () => ScrollTrigger.refresh());
}
