export const config = {
  name: 'NotchPlayer',
  domain: 'https://notchplayer.pages.dev', // the site's address: canonical URL and link-preview image
  ctaLabel: 'Download for Mac',
  version: '0.6', // bump on every release (CONTRIBUTING.md "Releasing a version")
  macosMin: '15',
  appleSiliconOnly: true,
  repoUrl: 'https://github.com/arvxanand/NotchPlayer',
  dmgUrl: 'https://github.com/arvxanand/NotchPlayer/releases/latest/download/NotchPlayer.dmg',
  brewCmd: 'brew install --cask arvxanand/notchplayer/notchplayer',
  shareUrl: '', // empty: use location.href at runtime
} as const;
