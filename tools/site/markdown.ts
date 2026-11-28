// The Markdown the addon's README.md and CHANGELOG.md use, as HTML: headings, paragraphs, lists (nested by indent),
// bold, italics, code and links. Nothing else is needed, so no dependency is.

export const escapeHtml = (text: string) =>
  text.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;");

const renderInline = (text: string) => {
  // (code spans set aside while the rest is marked up, each held by a placeholder of private-use characters)
  const codes: string[] = [];
  const withoutCode = text.replace(/`([^`]+)`/g, (_match, code: string) => {
    codes.push(`<code>${escapeHtml(code)}</code>`);
    return `\uE000${codes.length - 1}\uE001`;
  });
  return escapeHtml(withoutCode)
    .replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, '<a href="$2">$1</a>')
    .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
    .replace(/(^|[\s(])_([^_]+)_(?=[\s).,!?:;]|$)/g, "$1<em>$2</em>")
    .replace(/\uE000(\d+)\uE001/g, (_match, index: string) => codes[Number(index)] ?? "");
};

type ListItem = { text: string; children: ListItem[] };

const renderList = (items: ListItem[]): string =>
  `<ul>${items
    .map((item) => `<li>${renderInline(item.text)}${item.children.length ? renderList(item.children) : ""}</li>`)
    .join("")}</ul>`;

const LIST_LINE = /^(\s*)[-*] (.*)$/;

// Lines of a list, from `start`: each item with its own lines and its deeper items. Returns where the list ends.
const readList = (lines: string[], start: number) => {
  const items: ListItem[] = [];
  const stack: { indent: number; items: ListItem[] }[] = [{ indent: -1, items }];
  // (a wrapped line belongs to the item read last, however deep)
  let lastItem: ListItem | undefined;
  let index = start;
  for (; index < lines.length; index++) {
    const line = lines[index] ?? "";
    if (!line.trim()) {
      break;
    }
    const match = LIST_LINE.exec(line);
    if (!match) {
      if (lastItem) {
        lastItem.text += ` ${line.trim()}`;
      }
      continue;
    }
    const indent = (match[1] ?? "").length;
    while ((stack.at(-1)?.indent ?? -1) >= indent) {
      stack.pop();
    }
    const parent = stack.at(-1) ?? { indent: -1, items };
    const item: ListItem = { text: match[2] ?? "", children: [] };
    parent.items.push(item);
    lastItem = item;
    stack.push({ indent, items: item.children });
  }
  return { html: renderList(items), end: index };
};

export type RenderOptions = {
  // The id a heading gets, if any (the changelog's versions get one, for links to them)
  getHeadingId?: (level: number, text: string) => string | undefined;
  // How many levels to move every heading down (the README's ## under the page's own h2: 1)
  headingShift?: number;
};

export const renderMarkdown = (markdown: string, options: RenderOptions = {}) => {
  const lines = markdown.replaceAll("\r\n", "\n").split("\n");
  const blocks: string[] = [];
  let paragraph: string[] = [];
  const closeParagraph = () => {
    if (paragraph.length) {
      blocks.push(`<p>${renderInline(paragraph.join(" "))}</p>`);
      paragraph = [];
    }
  };
  for (let index = 0; index < lines.length; index++) {
    const line = lines[index] ?? "";
    const heading = /^(#{1,6}) (.*)$/.exec(line);
    if (heading) {
      closeParagraph();
      const text = (heading[2] ?? "").trim();
      const level = Math.min(6, (heading[1] ?? "#").length + (options.headingShift ?? 0));
      const id = options.getHeadingId?.(level, text);
      blocks.push(`<h${level}${id ? ` id="${escapeHtml(id)}"` : ""}>${renderInline(text)}</h${level}>`);
      continue;
    }
    if (LIST_LINE.test(line) && paragraph.length === 0) {
      const list = readList(lines, index);
      blocks.push(list.html);
      index = list.end - 1;
      continue;
    }
    if (!line.trim()) {
      closeParagraph();
      continue;
    }
    paragraph.push(line.trim());
  }
  closeParagraph();
  return blocks.join("\n");
};

// The changelog's link to a version: its heading's id (0.16.0 is "v0-16-0"). tools/release/curseforge.py links to it.
export const getVersionAnchor = (version: string) => `v${version.replace(/[^0-9A-Za-z]+/g, "-")}`;
