import { mountDesk } from '../notch/desk';
import { createNotch } from '../notch/notch';
import { storyFrame } from './storyboard';
import { notchFor } from './story-notch';
import { mountStory } from './story';

// The menu bar shows the visitor's own date and time, like their Mac would. The HTML keeps 9:41 without JS.
const clocks = document.querySelectorAll<HTMLElement>('[data-clock]');
const tick = () => {
  const d = new Date();
  const day = d.toLocaleDateString(undefined, { weekday: 'short', day: 'numeric', month: 'short' }).replace(',', '');
  const text = `${day}  ${d.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' })}`;
  clocks.forEach((c) => { c.textContent = text; });
  setTimeout(tick, 60000 - (Date.now() % 60000)); // on the minute
};
tick();

const html = document.documentElement;
const story = document.querySelector<HTMLElement>('.story');
if (story && html.classList.contains('enhanced')) {
  // If the story cannot start, the static stack below takes over instead of five empty screens.
  try { mountStory(story); } catch (e) { html.classList.remove('enhanced'); console.error(e); }
}

// Static stack: each beat gets a still notch frozen at its frame. Enhanced mode uses one shared notch instead.
if (!html.classList.contains('enhanced')) {
  const phone = matchMedia('(max-width: 799px)');
  const stills: HTMLElement[] = [];
  for (const el of document.querySelectorAll<HTMLElement>('[data-static-notch]')) {
    mountDesk(el.closest<HTMLElement>('.desk')!);
    createNotch(el, { interactive: false, still: true, state: notchFor(storyFrame(Number(el.dataset.p)), Date.now()) });
    stills.push(el);
  }
  // At phone scale the stills are pictures, not controls; the beat's caption carries the words (trap 8).
  // Re-checked on rotation, not decided once at load (trap 6).
  const inert = () => stills.forEach((el) => { el.inert = phone.matches; });
  inert();
  phone.addEventListener('change', inert);
}

// Phones cannot install a Mac app: share or copy the link instead.
document.querySelectorAll<HTMLButtonElement>('[data-share]').forEach((b) => {
  b.addEventListener('click', async () => {
    const url = location.href;
    try {
      if (navigator.share) await navigator.share({ title: document.title, url });
      else { await navigator.clipboard.writeText(url); b.textContent = 'Link copied'; }
    } catch { /* the visitor dismissed the share sheet */ }
  });
});
