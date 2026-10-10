// Which kind of Mac the visitor seems to be on. NotchPlayer is Apple Silicon only (the cask has
// `depends_on arch: :arm64`), so an Intel visitor should not get a download that won't open.
// Only a confident answer counts: anything unclear stays 'unknown' and keeps the button.
export type Arch = 'arm' | 'intel' | 'unknown';

/** uaArch: Chrome's userAgentData architecture ("arm", "x86"). renderer: the WebGL renderer
 *  string ("Apple M2", "Intel Iris Plus Graphics", or Safari's masked "Apple GPU"). */
export function macArch(uaArch: string | undefined, renderer: string | undefined): Arch {
  // The GPU name first: an x86 build of Chrome running under Rosetta reports x86 on Apple Silicon.
  if (renderer && /Apple M\d/i.test(renderer)) return 'arm';
  if (uaArch === 'arm') return 'arm';
  if (uaArch === 'x86') return 'intel';
  if (!renderer) return 'unknown';
  if (/Intel|AMD|Radeon/i.test(renderer)) return 'intel';
  return 'unknown'; // "Apple GPU" is what Safari reports on both
}

export async function detectArch(): Promise<Arch> {
  if (!/Mac/.test(navigator.platform)) return 'unknown';
  let ua: string | undefined;
  try {
    const d = (navigator as Navigator & { userAgentData?: { getHighEntropyValues(k: string[]): Promise<{ architecture?: string }> } }).userAgentData;
    ua = (await d?.getHighEntropyValues(['architecture']))?.architecture;
  } catch { /* not offered */ }
  let renderer: string | undefined;
  try {
    const gl = document.createElement('canvas').getContext('webgl');
    const ext = gl?.getExtension('WEBGL_debug_renderer_info');
    renderer = ext ? gl!.getParameter(ext.UNMASKED_RENDERER_WEBGL) : undefined;
    gl?.getExtension('WEBGL_lose_context')?.loseContext(); // one question, then give the GPU context back
  } catch { /* no WebGL */ }
  return macArch(ua, renderer);
}
