export const config = {
  name: 'NotchPlayer',
  domain: '', // set when there is one; empty means "no canonical URL yet"
  ctaLabel: 'Download for Mac',
  version: '0.6', // bump on every release (CONTRIBUTING.md "Releasing a version")
  macosMin: '15',
  appleSiliconOnly: true,
  dmgUrl: 'https://github.com/arvxanand/NotchPlayer/releases/latest/download/NotchPlayer.dmg',
  brewCmd: 'brew install --cask arvxanand/notchplayer/notchplayer',
  shareUrl: '', // empty: use location.href at runtime
} as const;
