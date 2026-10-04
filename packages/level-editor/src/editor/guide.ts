// User guide overlay: docs/user-guide.md rendered in the app. Editor
// shortcuts are paused while it is open (like the emulator overlay).

export class GuideOverlay {
  isOpen = false;
  onOpen: () => void = () => {};
  onClose: () => void = () => {};

  private root: HTMLElement;
  private body: HTMLElement;
  private loaded = false;

  constructor(host: HTMLElement) {
    this.root = document.createElement('div');
    this.root.id = 'guide';
    this.root.hidden = true;
    this.root.innerHTML = `
      <div class="guide-bar">
        <b>User guide</b>
        <button id="guide-top" title="back to the contents">Contents</button>
        <span class="spacer"></span>
        <button id="guide-close" title="Esc">Close</button>
      </div>
      <article class="guide-body" tabindex="-1">Loading…</article>`;
    host.append(this.root);
    this.body = this.root.querySelector('.guide-body')!;
    this.root.querySelector<HTMLElement>('#guide-close')!.onclick = () => this.close();
    this.root.querySelector<HTMLElement>('#guide-top')!.onclick = () => this.body.scrollTo({ top: 0 });
    // in-page links scroll the guide (the page itself has no such anchors)
    this.body.addEventListener('click', (e) => {
      const a = (e.target as HTMLElement).closest('a');
      const href = a?.getAttribute('href');
      if (!href?.startsWith('#')) return;
      e.preventDefault();
      this.show(href.slice(1));
    });
    // While open, keys belong to the guide: stop them before the editor's
    // and the emulator's listeners (this capture listener is added first),
    // but keep their default action (arrow keys, PgDn scroll the guide).
    const block = (e: KeyboardEvent) => {
      if (!this.isOpen) return;
      e.stopImmediatePropagation();
      if (e.type === 'keydown' && e.key === 'Escape') {
        e.preventDefault();
        this.close();
      }
    };
    window.addEventListener('keydown', block, true);
    window.addEventListener('keyup', block, true);
  }

  /** Open the guide, optionally at a section anchor (e.g. "10-memory"). */
  async open(anchor?: string): Promise<void> {
    if (!this.isOpen) {
      this.isOpen = true;
      this.root.hidden = false;
      this.onOpen();
    }
    if (!this.loaded) {
      try {
        const { guideHtml } = await import('./guide-content');
        this.body.innerHTML = guideHtml();
        this.loaded = true;
      } catch (e) {
        this.body.textContent = `Could not load the guide: ${e}`;
        return;
      }
    }
    this.body.focus({ preventScroll: true }); // arrow keys / PgDn scroll the guide
    if (anchor) this.show(anchor);
  }

  close(): void {
    if (!this.isOpen) return;
    this.isOpen = false;
    this.root.hidden = true;
    this.onClose();
  }

  private show(anchor: string): void {
    this.body.querySelector(`#${CSS.escape(anchor)}`)?.scrollIntoView({ block: 'start' });
  }
}
