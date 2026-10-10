import { describe, expect, it } from 'vitest';
import { check } from '../tools/check-lib.mjs';

const DMG = 'https://github.com/arvxanand/NotchPlayer/releases/latest/download/NotchPlayer.dmg';
const good = {
  html: `<script>addEventListener('error',(e)=>{e.target instanceof HTMLScriptElement})</script><main><h1>Whatever&rsquo;s playing, <em>right there.</em></h1><a href="${DMG}">Download for Mac</a></main><footer>not affiliated with Spotify AB or Apple</footer>`,
  css: '.beat{padding:1rem}.enhanced .beat{opacity:0}',
  src: [{ file: 'src/a.ts', text: 'const a = 1;' }],
  dmgUrl: DMG,
  required: ['Whatever’s playing, right there.', 'Download for Mac', 'not affiliated'],
};
const failures = (o: Partial<typeof good>) => check({ ...good, ...o }).fail.join('\n');

describe('check-static', () => {
  it('passes the good fixture', () => expect(check(good).fail).toEqual([]));
  it('requires the copy', () => {
    expect(failures({ html: good.html.replace('right there.', 'x') })).toContain('missing copy');
    expect(failures({ html: good.html.replace('not affiliated', 'x') })).toContain('missing copy: not affiliated');
    expect(failures({ html: good.html.replace('Download for Mac', 'x') })).toContain('missing copy: Download for Mac');
  });
  it('requires the script-failure fallback', () => expect(failures({ html: good.html.replace('HTMLScriptElement', '') })).toContain('fallback'));
  it('allows only the direct DMG github link', () => {
    expect(failures({ html: good.html + '<a href="https://github.com/arvxanand/NotchPlayer">repo</a>' })).toContain('GitHub');
    expect(failures({ html: good.html.split(DMG).join('/x') })).toContain('direct DMG');
  });
  it('rejects em dashes in html, &mdash; and JS sources', () => {
    expect(failures({ html: good.html + ' a — b' })).toContain('em dash');
    expect(failures({ html: good.html + ' a &mdash; b' })).toContain('em dash');
    expect(failures({ src: [{ file: 'src/b.ts', text: "el.textContent = 'a — b'" }] })).toContain('em dash in src/b.ts');
    expect(failures({ src: [{ file: 'src/b.ts', text: "el.textContent = 'a \\u2014 b'" }] })).toContain('em dash in src/b.ts');
  });
  it('rejects banned words', () => expect(failures({ html: good.html + ' seamless' })).toContain('banned word: seamless'));
  it('limits the word count', () => expect(failures({ html: good.html.replace('</main>', 'word '.repeat(401) + '</main>') })).toContain('words'));
  it('does not count reference text (install steps, FAQ) against the limit', () =>
    expect(failures({ html: good.html.replace('</main>', `<div class="wrap" data-reference>${'step '.repeat(500)}</div></main>`) })).toBe(''));
  it('never lets base CSS hide a beat', () => {
    expect(failures({ css: '.beat{opacity:0}' })).toContain('hides a beat');
    expect(failures({ css: '.beat{opacity:.5}.enhanced .beat{opacity:0}' })).toBe('');
  });
});
