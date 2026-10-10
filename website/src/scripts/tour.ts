// The stage's one-time autoplay tour. The first thing the visitor does cancels it, and nothing
// queued can fire afterwards.
export function createTour() {
  let cancelled = false;
  const ids: ReturnType<typeof setTimeout>[] = [];
  return {
    later(fn: () => void, ms: number) {
      if (cancelled) return;
      ids.push(setTimeout(() => { if (!cancelled) fn(); }, ms));
    },
    cancel() { cancelled = true; ids.splice(0).forEach(clearTimeout); },
    get cancelled() { return cancelled; },
  };
}
