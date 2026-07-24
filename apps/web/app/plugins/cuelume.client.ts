import { bind, play } from "cuelume";

type InteractiveElement = HTMLButtonElement | HTMLAnchorElement;

function resolveInteractiveElement(
  target: EventTarget | null,
): InteractiveElement | null {
  if (!(target instanceof Element)) return null;

  const interactive = target.closest(
    'button, a, [role="button"], input[type="button"], input[type="submit"]',
  );

  if (!interactive) return null;
  if (interactive instanceof HTMLButtonElement) return interactive;
  if (interactive instanceof HTMLAnchorElement) return interactive;

  // Coerce generic interactive elements into button behavior sounds.
  return interactive as HTMLButtonElement;
}

function isKeyboardActivation(event: KeyboardEvent): boolean {
  return event.key === "Enter" || event.key === " ";
}

export default defineNuxtPlugin((nuxtApp) => {
  if (!import.meta.client) return;

  bind();

  const pointerDown = (event: PointerEvent) => {
    if (event.button !== 0) return;
    const interactive = resolveInteractiveElement(event.target);
    if (!interactive) return;

    if (interactive instanceof HTMLAnchorElement) {
      play("tick");
      return;
    }

    play("press");
  };

  const pointerUp = (event: PointerEvent) => {
    if (event.button !== 0) return;
    const interactive = resolveInteractiveElement(event.target);
    if (!interactive) return;
    if (interactive instanceof HTMLAnchorElement) return;

    play("release");
  };

  const keydown = (event: KeyboardEvent) => {
    if (!isKeyboardActivation(event)) return;
    const interactive = resolveInteractiveElement(event.target);
    if (!interactive) return;

    if (interactive instanceof HTMLAnchorElement) {
      play("tick");
      return;
    }

    play("press");
  };

  const router = useRouter();
  router.beforeEach(() => {
    play("pageloading");
  });

  router.afterEach(() => {
    play("ready");
  });

  router.onError(() => {
    play("error");
  });

  window.addEventListener("pointerdown", pointerDown, {
    capture: true,
    passive: true,
  });
  window.addEventListener("pointerup", pointerUp, {
    capture: true,
    passive: true,
  });
  window.addEventListener("keydown", keydown, { capture: true });

  nuxtApp.hook("app:beforeUnmount", () => {
    window.removeEventListener("pointerdown", pointerDown, { capture: true });
    window.removeEventListener("pointerup", pointerUp, { capture: true });
    window.removeEventListener("keydown", keydown, { capture: true });
  });
});
