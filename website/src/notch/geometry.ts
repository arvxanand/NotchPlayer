// Every size the HTML notch draws, in points (1 CSS px = 1 pt). Calibration knobs: when the app's
// captures (design/refs/) and the HTML disagree, the app wins and the number changes here.
// Sources: Sources/NotchPlayerCore/Notch/NotchGeometry.swift, Views/{RootView,PeekView,PanelView,
// StatsView,TransportButton,WaveformView,ProgressLine}.swift.

export interface Mac { hasNotch: boolean; notchW: number; barH: number }
/** A 14" MacBook Pro, the Mac the captures were taken on (housing 208x37). */
export const NOTCHED: Mac = { hasNotch: true, notchW: 208, barH: 37 };
/** A Mac without a notch: the app draws a virtual one in the 24pt menu bar. */
export const PILL: Mac = { hasNotch: false, notchW: 0, barH: 24 };

export const WING = 72;
export const SHOULDER = 11;
export const OVERHANG = 2; // the shell hangs 2pt below a real cutout so its edge never shows
export const PANEL_H = 185;
export const DESIGNED_BAND = 37;
export const VIRTUAL_PANEL_W = 352;
export const SLACK = 16;
export const BOTTOM_R = { collapsed: 8, open: 22 };
export const HIT = 44;
/** The physical camera housing, drawn on the fake desktop when the app shows nothing. Not app
 *  geometry: tuned by eye against photos of a real MacBook, so check it against the user's photo. */
export const HOUSING = { topR: 4, botR: 8 };

export const PEEK = { art: 25, artR: 5, mark: 12, markGap: 7, inset: 8 };
export const BARS = { count: 14, w: 2, gap: 2, min: 2, max: 22 };
export const BARS_W = BARS.count * BARS.w + (BARS.count - 1) * BARS.gap; // 54

export const PANEL = {
  art: 72, artR: 8, inset: 16, gap: 14, topGap: 14, transportGap: 8, bottomGap: 10,
  titleLine: 21, artistGap: 2, artistLine: 16,
  progressCentre: 66, // measured off a capture by the app (PanelView.progressCentreBelowNotch)
  progress: 3, progressActive: 5, knob: 7, progressHit: 30, clockGap: 4,
  // SwiftUI lays text out from SF's own metrics; CSS line boxes differ. Measured in the lab (2x):
  artistGapNudge: -1, clockNudge: 2,
  plus: 18, stats: 14, statsInset: 8,
};
export const TRANSPORT = { side: 16.5, centre: 14, disc: 29, shuffle: 12.5, modeW: 30 };
export const TRANSPORT_W = HIT * 3 + TRANSPORT.modeW * 2; // 192
export const DOTS = { side: 5, gap: 5, bottom: 3 };
export const STATS = { topGap: 6, rowGap: 8, columnGap: 16, tab: 24, tabPad: 8, tabGap: 2, line: 22, bar: 2.5, barGap: 2, rank: 16, totals: 96 };
export const PAGE_TRAVEL = 14;

export interface Size { w: number; h: number }
export const collapsed = (m: Mac): Size => ({ w: m.notchW + 2 * WING, h: m.barH + (m.hasNotch ? OVERHANG : 0) });
export const open = (m: Mac): Size => ({
  w: m.hasNotch ? collapsed(m).w : VIRTUAL_PANEL_W,
  h: m.hasNotch ? PANEL_H : m.barH + PANEL_H - DESIGNED_BAND,
});
/** The app's window: the open panel plus room for the shoulders, plus slack below. */
export const frame = (m: Mac): Size => ({ w: open(m).w + 2 * SHOULDER, h: open(m).h + SLACK });

/** InverseCornerShape.path: concave quadratic shoulders, quadratic bottom corners, centred in a
 *  frame `frameW` wide. A path with the same commands for every size, so CSS can animate it. */
export function shellPath(s: Size, topR: number, botR: number, frameW: number): string {
  const x0 = (frameW - s.w) / 2, x1 = x0 + s.w;
  const tr = Math.min(topR, s.w / 2, s.h / 2), br = Math.min(botR, s.w / 2, s.h / 2);
  const n = (v: number) => +v.toFixed(3);
  return `M${n(x0 - tr)} 0Q${n(x0)} 0 ${n(x0)} ${n(tr)}L${n(x0)} ${n(s.h - br)}Q${n(x0)} ${n(s.h)} ${n(x0 + br)} ${n(s.h)}`
    + `L${n(x1 - br)} ${n(s.h)}Q${n(x1)} ${n(s.h)} ${n(x1)} ${n(s.h - br)}L${n(x1)} ${n(tr)}Q${n(x1)} 0 ${n(x1 + tr)} 0Z`;
}

/** PeekView.scale: 1 on a notched Mac; a 24pt menu bar shrinks the strip's contents to fit. */
export const peekScale = (m: Mac) => (m.hasNotch ? 1 : Math.min(1, collapsed(m).h / DESIGNED_BAND));

export interface Rect { x: number; y: number; w: number; h: number }
export interface PeekLayout { mark: Rect | null; art: Rect & { r: number }; bars: Rect & { min: number; max: number } }

/** Where the peek's three things sit, relative to the collapsed shell's top-left corner.
 *  `cover` false: no artwork, so the mark draws inside the cover square and the standalone mark hides. */
export function peekLayout(m: Mac, cover: boolean): PeekLayout {
  const s = peekScale(m), h = collapsed(m).h;
  const art = Math.round(PEEK.art * s), mark = PEEK.mark * s, gap = PEEK.markGap * s;
  const max = BARS.max * s;
  const leftContent = (cover ? mark + gap : 0) + art;
  let leftEnd: number; // the left wing's right edge, before its inset
  let barsX: number;
  if (m.hasNotch) {
    leftEnd = WING - PEEK.inset;
    barsX = WING + m.notchW + PEEK.inset;
  } else {
    // Unpinned wings: the pair is centred as one group (PeekView's comment on why).
    const group = leftContent + PEEK.inset + PEEK.inset + BARS_W;
    const start = (collapsed(m).w - group) / 2;
    leftEnd = start + leftContent;
    barsX = leftEnd + 2 * PEEK.inset;
  }
  const artX = leftEnd - art;
  return {
    mark: cover ? { x: artX - gap - mark, y: (h - mark) / 2, w: mark, h: mark } : null,
    art: { x: artX, y: (h - art) / 2, w: art, h: art, r: PEEK.artR * s },
    bars: { x: barsX, y: (h - max) / 2, w: BARS_W, h: max, min: BARS.min, max },
  };
}

/** The panel's blocks, relative to the open shell's top-left corner. */
export function panelLayout(m: Mac) {
  const o = open(m), top = m.barH; // NotchGeometry.notchExclusionTop
  const rowTop = top + PANEL.topGap;
  const textX = PANEL.inset + PANEL.art + PANEL.gap;
  const transportTop = rowTop + PANEL.art + PANEL.transportGap;
  return {
    art: { x: PANEL.inset, y: rowTop, w: PANEL.art, h: PANEL.art },
    text: { x: textX, y: rowTop, w: o.w - textX - PANEL.inset, h: PANEL.art },
    progressY: top + PANEL.progressCentre - PANEL.progress / 2,
    transport: { x: (o.w - TRANSPORT_W) / 2, y: transportTop, w: TRANSPORT_W, h: HIT },
    stats: { x: o.w - PANEL.statsInset - HIT, y: transportTop, w: HIT, h: HIT },
    dotsY: o.h - DOTS.bottom - DOTS.side,
    statsTop: top + STATS.topGap,
  };
}

// Scale the whole notch down so it fits a narrow container (16px gutter each side). Never scales up.
export function fitScale(containerW: number, contentW: number): number {
  return Math.max(0.1, Math.min(1, (containerW - 32) / contentW));
}
