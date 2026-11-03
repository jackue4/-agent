/** Use the game's declared screen direction, not its cover shape or genre name. */
export function gameOrientation(game = {}) {
  for (const value of [game.spec?.meta?.orientation, game.game?.meta?.orientation, game.meta?.orientation, game.orientation]) {
    if (value === 'portrait' || value === 'landscape') return value;
  }
  return 'landscape';
}

/** Logical iframe viewport. Rotate the entire surface, not a small fitted thumbnail. */
export function gameViewport(orientation, width, height, { coarse = false, embedded = false } = {}) {
  if (embedded) return { width, height, rotation: 0 };
  if (orientation === 'landscape' && height > width) return { width: height, height: width, rotation: 90 };
  if (orientation === 'portrait' && width > height) {
    if (coarse) return { width: height, height: width, rotation: -90 };
    return { width: Math.min(width, height * 9 / 16), height, rotation: 0 };
  }
  return { width, height, rotation: 0 };
}

export function applyGameViewport(element, orientation, { embedded = false } = {}) {
  const viewport = window.visualViewport;
  const layout = gameViewport(orientation, viewport?.width || innerWidth, viewport?.height || innerHeight, {
    coarse: matchMedia('(pointer:coarse)').matches, embedded,
  });
  element.style.setProperty('--play-width', layout.width + 'px');
  element.style.setProperty('--play-height', layout.height + 'px');
  element.style.setProperty('--play-rotation', layout.rotation + 'deg');
  element.dataset.orientation = orientation;
  element.dataset.rotation = String(layout.rotation);
  return layout;
}

const fullscreenRequests = new WeakMap();

// Native fullscreen/locking is optional; CSS layout remains usable when either is denied.
export async function enterGameFullscreen(element, orientation, isCurrent = () => true) {
  const token = {};
  fullscreenRequests.set(element, token);
  try {
    const request = element.requestFullscreen || element.webkitRequestFullscreen;
    if (!request || !isCurrent()) return;
    await request.call(element);
    if (!isCurrent()) {
      const doc = globalThis.document;
      // An exit can happen while requestFullscreen is pending. Do not strand a dead card
      // in fullscreen, or cancel a newer request for the same card.
      if (fullscreenRequests.get(element) === token && doc && (doc.fullscreenElement === element || doc.webkitFullscreenElement === element)) {
        const exit = doc.exitFullscreen || doc.webkitExitFullscreen;
        await exit?.call(doc);
      }
      return;
    }
    await screen.orientation?.lock?.(orientation);
  } catch { /* Unsupported browser, missing activation, or orientation-lock permission. */ }
  finally { if (fullscreenRequests.get(element) === token) fullscreenRequests.delete(element); }
}
