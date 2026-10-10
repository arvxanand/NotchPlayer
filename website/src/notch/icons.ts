// The app's glyphs as SVG, sized to the boxes measured off its captures (2x, design/refs/):
// shuffle 15x12, previous/next 15.5x12.5, repeat 15x14 frame, chart.bar 17x12.5, plus.circle 18.
// SF Symbols can't ship on a website, so these are redrawn; the lab overlay is the check.

const svg = (w: number, h: number, body: string, cls = '') =>
  `<svg class="np-ico ${cls}" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" aria-hidden="true" focusable="false">${body}</svg>`;

export const shuffle = () => svg(15, 12,
  '<g fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">'
  + '<path d="M.9 2.5h1.9c2.6 0 3.6 1.2 4.6 3.5s2 3.5 4.6 3.5h1.9"/><path d="M.9 9.5h1.9c1.5 0 2.4-.4 3.1-1.2M8.6 3.7c.7-.8 1.6-1.2 3.1-1.2h1.9"/>'
  + '<path d="M11.9.6l2.2 1.9-2.2 1.9M11.9 7.6l2.2 1.9-2.2 1.9"/></g>');

// backward.end.fill: a rounded bar, then a rounded triangle pointing at it.
export const previous = () => svg(15.5, 12.5,
  '<rect x="0" y="0" width="2.7" height="12.5" rx="1.1" fill="currentColor"/>'
  + '<path d="M14.1.4c.8-.5 1.4-.1 1.4.8v10.1c0 .9-.6 1.3-1.4.8L4.7 7.1c-.8-.5-.8-1.3 0-1.8z" fill="currentColor"/>');
export const next = () => svg(15.5, 12.5,
  '<g transform="translate(15.5 0) scale(-1 1)"><rect x="0" y="0" width="2.7" height="12.5" rx="1.1" fill="currentColor"/>'
  + '<path d="M14.1.4c.8-.5 1.4-.1 1.4.8v10.1c0 .9-.6 1.3-1.4.8L4.7 7.1c-.8-.5-.8-1.3 0-1.8z" fill="currentColor"/></g>');

export const pause = () => svg(9, 12.5,
  '<rect x="0" y="0" width="3.6" height="12.5" rx="1" fill="currentColor"/><rect x="5.4" y="0" width="3.6" height="12.5" rx="1" fill="currentColor"/>');
export const play = () => svg(11, 12.5,
  '<path d="M1.5.3C.8-.1 0 .3 0 1.1v10.3c0 .8.8 1.2 1.5.8l8.9-5.2c.7-.4.7-1.3 0-1.7z" fill="currentColor"/>');

/** RepeatGlyph from Views/TransportButton.swift, point for point, in its 15x14 frame. */
export function repeat(one: boolean) {
  const lw = 1.7, w0 = 15, h0 = 14;
  const box = { x: lw / 2, y: lw / 2, w: w0 - lw, h: h0 * 0.8 - lw };
  const r = box.h * 0.3, w = box.w, minX = box.x, minY = box.y, maxX = box.x + box.w, maxY = box.y + box.h, midX = box.x + box.w / 2;
  const n = (v: number) => +v.toFixed(3);
  let d = `M${n(minX + w * 0.38)} ${n(maxY)}L${n(minX + r)} ${n(maxY)}Q${n(minX)} ${n(maxY)} ${n(minX)} ${n(maxY - r)}L${n(minX)} ${n(minY + r)}Q${n(minX)} ${n(minY)} ${n(minX + r)} ${n(minY)}`;
  if (one) d += `L${n(midX - w * 0.2)} ${n(minY)}M${n(midX + w * 0.2)} ${n(minY)}`;
  const tipX = minX + w * 0.5, wing = box.h * 0.26;
  d += `L${n(maxX - r)} ${n(minY)}Q${n(maxX)} ${n(minY)} ${n(maxX)} ${n(minY + r)}L${n(maxX)} ${n(maxY - r)}Q${n(maxX)} ${n(maxY)} ${n(maxX - r)} ${n(maxY)}L${n(tipX)} ${n(maxY)}`
    + `M${n(tipX + wing)} ${n(maxY - wing)}L${n(tipX)} ${n(maxY)}L${n(tipX + wing)} ${n(maxY + wing)}`;
  const digit = one ? '<text x="7.5" y="5.6" text-anchor="middle" font-size="9.5" font-weight="700" fill="currentColor" font-family="system-ui, -apple-system, sans-serif">1</text>' : '';
  return svg(w0, h0, `<path d="${d}" fill="none" stroke="currentColor" stroke-width="${lw}" stroke-linecap="round" stroke-linejoin="round"/>${digit}`);
}

export const chartBar = () => svg(17, 12.5,
  '<g fill="none" stroke="currentColor" stroke-width="1.05"><rect x=".5" y="4.5" width="4" height="7.5" rx="1.3"/>'
  + '<rect x="6.5" y="2.5" width="3.5" height="9.5" rx="1.3"/><rect x="12.5" y=".5" width="4" height="11.5" rx="1.3"/></g>');

export const plusCircle = () => svg(18, 18,
  '<g fill="none" stroke="currentColor" stroke-width="1.45" stroke-linecap="round"><circle cx="9" cy="9" r="8.2"/><path d="M9 4.8v8.4M4.8 9h8.4"/></g>');

/** SpotifyMark.swift: three arcs centred below the mark, drawn in black on Spotify's green. */
export function spotifyMark(side: number) {
  const arcs: [number, number, number][] = [[0.7, 31, 0.095], [0.55, 33, 0.082], [0.415, 35.3, 0.07]];
  const s = side, cx = 0.5 * s, cy = 1.0 * s;
  const paths = arcs.map(([r, sweep, lw]) => {
    const a = (sweep * Math.PI) / 180, R = r * s;
    const x1 = cx - R * Math.sin(a), y1 = cy - R * Math.cos(a), x2 = cx + R * Math.sin(a);
    return `<path d="M${x1.toFixed(3)} ${y1.toFixed(3)}A${R.toFixed(3)} ${R.toFixed(3)} 0 0 1 ${x2.toFixed(3)} ${y1.toFixed(3)}" fill="none" stroke="#000" stroke-width="${(lw * s).toFixed(3)}" stroke-linecap="round"/>`;
  }).join('');
  return svg(s, s, `<circle cx="${s / 2}" cy="${s / 2}" r="${s / 2}" fill="#1DB954"/>${paths}`, 'np-mark');
}

/** MusicMark: Apple Music's red disc with a note (SF `music.note`, bold, 0.58 of the side). */
export function musicMark(side: number) {
  const k = side / 24;
  return svg(side, side, `<circle cx="${side / 2}" cy="${side / 2}" r="${side / 2}" fill="#FA243C"/>`
    + `<g transform="scale(${k.toFixed(4)})"><path d="M14.6 5.2c0-.6.5-1 1.1-.9l1.6.3c.5.1.8.5.8 1v2.1c0 .5-.4.9-.9.8l-1.4-.2v8.2c0 2-1.6 3.4-3.6 3.4-1.6 0-2.7-.9-2.7-2.3 0-1.6 1.3-2.7 3.1-2.7.5 0 .9.1 1.3.2z" fill="#000"/></g>`, 'np-mark');
}
