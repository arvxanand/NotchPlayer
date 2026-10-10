// The post-build copy checks as one pure function, so tests/check-static.test.ts can feed it fixtures.
// The page must read without JavaScript and obey the copy rules.
export const REQUIRED_COPY = ['Whatever’s playing, right there.', 'One glance is enough.', 'Hover, and it opens.', 'Your week, in minutes.', 'No notch, same idea.', 'Download for Mac', 'not affiliated'];
const EM_DASH = /—|&mdash;|&#8212;|&#x2014;|\\u2014/i;

/** @param {{ html: string, css: string, src: { file: string, text: string }[], dmgUrl: string, required?: string[] }} o */
export function check({ html, css, src, dmgUrl, required = REQUIRED_COPY }) {
  const fail = [];
  // Copy needles match visible text, so inline tags like <em> inside a headline do not hide them.
  const text = html.replace(/<(script|style)[\s\S]*?<\/\1>/gi, '').replace(/<[^>]+>/g, '').replace(/&rsquo;/g, '’').replace(/\s+/g, ' ');
  const lower = text.toLowerCase();

  for (const s of required) if (!lower.includes(s.toLowerCase())) fail.push(`missing copy: ${s}`);
  if (!html.includes('HTMLScriptElement')) fail.push('the inline fallback that drops .enhanced when the page script fails is missing');
  // The visitor never sees GitHub: the one allowed mention is the direct DMG link.
  if (/github\.com/i.test(html.split(dmgUrl).join(''))) fail.push('GitHub link found (only the direct DMG link is allowed)');
  if (!html.includes(`href="${dmgUrl}"`)) fail.push('the download button does not link to the direct DMG url');
  if (EM_DASH.test(html)) fail.push('em dash found in copy');
  // JS-rendered strings never reach the built HTML, so scan the sources too (MatchNotch's check missed these).
  for (const f of src) if (EM_DASH.test(f.text)) fail.push(`em dash in ${f.file}`);
  for (const w of ['seamless', 'supercharge', 'revolutionize']) if (lower.includes(w)) fail.push(`banned word: ${w}`);

  const main = (html.match(/<main[\s\S]*<\/footer>/i) ?? [html])[0].replace(/<(script|style|svg)[\s\S]*?<\/\1>/gi, '').replace(/<[^>]+>/g, ' ');
  const words = main.split(/\s+/).filter(Boolean).length;
  if (words > 400) fail.push(`page copy is ${words} words (limit 400, target about 350)`);

  // Base styles must never hide a beat: only `.enhanced` may set opacity:0 on it.
  if (!css.includes('.beat')) fail.push('no page CSS found to check');
  for (const m of css.matchAll(/([^{}]+)\{[^{}]*opacity:\s*0(?![.\d])[^{}]*\}/g))
    if (/\.beat\b/.test(m[1]) && !/\.enhanced/.test(m[1])) fail.push(`base CSS hides a beat: ${m[1].trim()}`);

  return { fail, words };
}
