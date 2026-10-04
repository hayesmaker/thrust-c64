// docs/user-guide.md as HTML, for the in-app guide. Loaded on first open
// (dynamic import), so the guide and marked stay out of the main bundle.

import { Marked } from 'marked';
import markdown from '../../docs/user-guide.md?raw';

/** docs/img/*.png as bundled URLs, keyed by the path the guide uses. */
const images: Record<string, string> = Object.fromEntries(
  Object.entries(import.meta.glob('../../docs/img/*.png', { eager: true, query: '?url', import: 'default' })).map(
    ([path, url]) => [path.replace('../../docs/', ''), url as string],
  ),
);

/** GitHub's heading anchors, so the guide's own #links work. */
export function slug(text: string): string {
  return text
    .trim()
    .toLowerCase()
    .replace(/<[^>]+>/g, '')
    .replace(/[^\w\- ]/g, '')
    .replace(/ /g, '-');
}

const marked = new Marked({
  renderer: {
    heading({ tokens, depth, text }) {
      return `<h${depth} id="${slug(text)}">${this.parser.parseInline(tokens)}</h${depth}>\n`;
    },
    image({ href, title, text }) {
      const src = images[href] ?? href;
      return `<img src="${src}" alt="${text}"${title ? ` title="${title}"` : ''} loading="lazy">`;
    },
  },
});

export const guideHtml = (): string => marked.parse(markdown, { async: false });
