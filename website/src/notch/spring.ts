// SwiftUI .spring(response:dampingFraction:) as a CSS linear() easing.
// ponytail: underdamped only (damping < 1), which is all the app uses.
export function springCurve(response: number, damping: number, points = 32) {
  const w0 = (2 * Math.PI) / response;
  const wd = w0 * Math.sqrt(1 - damping * damping);
  const durationS = 4.6 / (damping * w0); // ~1% settle
  const at = (t: number) =>
    1 - Math.exp(-damping * w0 * t) * (Math.cos(wd * t) + ((damping * w0) / wd) * Math.sin(wd * t));
  const samples = Array.from({ length: points + 1 }, (_, i) => at((i / points) * durationS));
  samples[points] = 1;
  return { durationMs: Math.round(durationS * 1000), css: `linear(${samples.map((v) => v.toFixed(4)).join(', ')})` };
}
