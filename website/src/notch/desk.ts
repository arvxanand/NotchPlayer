// The desktop is drawn at real MacBook point size and scaled with one transform, so the
// notch keeps its true proportion to the screen. A strip is the top of the desktop only
// (menu bar + notch), cropped, for phones and the static stack.
import { HOUSING, NOTCHED, shellPath } from './geometry';

export const SCREEN = { w: 1512, h: 982 }; // 14" MacBook Pro default; calibration knob
export const STRIP_W = 560;                 // width a strip keeps visible: the 352pt panel plus margin

export function deskFit(width: number, strip: number): { s: number; x: number; h: number } {
  const s = strip ? Math.min(1, width / STRIP_W) : width / SCREEN.w;
  return { s, x: (width - SCREEN.w * s) / 2, h: (strip || SCREEN.h) * s };
}

/** The physical camera housing, which shows whenever the app draws nothing. */
export const housingPath = () =>
  shellPath({ w: NOTCHED.notchW, h: NOTCHED.barH }, HOUSING.topR, HOUSING.botR, NOTCHED.notchW + 2 * HOUSING.topR);

export function mountDesk(el: HTMLElement): () => void {
  const canvas = el.querySelector<HTMLElement>('.desk-canvas')!;
  // Re-read the strip on every fit: a phone rotated to landscape changes it (trap 6).
  const fit = () => {
    const { s, x } = deskFit(el.clientWidth, Number(el.dataset.strip ?? 0));
    canvas.style.transform = `translate(${x}px, 0) scale(${s})`;
  };
  const ro = new ResizeObserver(fit);
  ro.observe(el);
  fit();
  return () => ro.disconnect();
}
