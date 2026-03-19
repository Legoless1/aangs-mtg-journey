# Aang's MTG Journey - Authoring Guide

Last updated: 2026-03-19

This README documents the **current, supported markup** for writing content in this project.

If you change parsing/rendering behavior in `index.html`, update this file in the same change.

## Folder structure

```text
/blog
  .nojekyll
  build-site.cmd
  build-site.ps1
  index.html
  feed.xml
  /site-root
    google*.html
    BingSiteAuth.xml
  /docs
  /posts
    posts.json
    YYYY-MM-DD-slug.md
  /pages
    pages.json
    about.md
    guestbook.md
  /assets
    favicons/avatar-minimal.svg
    images/site-logo.svg
    images/... (or any static media)
```

## Source vs publish output

- `index.html` in the project root is the source/editor preview app.
- `docs/` is the generated static publish output.
- The live site should be served from `docs/`, not from the source root.

## Build and publish workflow

1. Create or edit a Markdown file in `posts/` or `pages/`.
2. Add or update the matching entry in `posts/posts.json` or `pages/pages.json`.
3. Rebuild the static site by running:

```text
build-site.cmd
```

This rebuilds:

- `docs/` static HTML pages
- `docs/feed.xml`
- `docs/sitemap.xml`
- `docs/search-index.json`
- any passthrough files from `site-root/` into the published site root
- the root `feed.xml` convenience copy

4. Publish `docs/`.

For GitHub Pages:

1. Open repo `Settings`
2. Open `Pages`
3. Set `Source` to `Deploy from a branch`
4. Set branch to `main`
5. Set folder to `/docs`

## RSS feed generation

- The published RSS feed lives at `docs/feed.xml`.
- The builder also writes a synced copy to the project root as `feed.xml`.
- Files placed in `site-root/` are copied into `docs/` unchanged. Use this for Google/Bing verification files or any other required root-level static files.
- Rebuild it any time you add or edit posts by running:

```text
build-site.cmd
```

- The builder reads:
  - `index.html` for site config and styling
  - `posts/posts.json` for post metadata
  - `pages/pages.json` for page metadata
  - the Markdown files in `posts/` and `pages/`

Important:

- Set `CFG.siteUrl` in `index.html` before rebuilding so feed links, canonicals, and sitemap URLs are absolute and correct.
- The generated static site is what makes the blog crawlable by search engines, AI agents, link-preview scrapers, and archival tools.

## Sitemap

- A static sitemap is generated at `docs/sitemap.xml`.
- `docs/robots.txt` includes a `Sitemap:` line when `CFG.siteUrl` is set.


## Favicon

- Favicons are loaded from `assets/favicons/` (SVG + PNG + ICO + manifest).
- To change the primary icon, replace `assets/favicons/avatar-minimal.svg`.
- Keep filenames stable to avoid future HTML changes.


## Post and page front matter

Supported front matter styles:

1. Fenced block:

```md
---
title: Raised Foil Avatar Aang (#363)
date: 2026-03-17
tags: TLA, acquisition, grail
---

Post body here...
```

2. Top-of-file key/value lines (must be followed by a blank line):

```md
title: Raised Foil Avatar Aang (#363)
date: 2026-03-17
tags: TLA, acquisition, grail

Post body here...
```

### Common keys

- `title`: string
- `date`: `YYYY-MM-DD` (used for posts)
- `tags`: comma-separated string or bracket form like `[tag1, tag2]`
- `comments`: `true` to append the Cusdis comment embed to that post/page view

Notes:

- Manifest values are the source of truth for title/date/tags/author.
- Front matter is parsed for body separation, but canonical metadata comes from the manifest.
- The `comments` flag is read from the Markdown file front matter and is not stored in the JSON manifests.
- For pages, `date` is optional/unused.

## Cusdis comments

To enable the embedded Cusdis thread on a single post or page, add `comments: true` in that file's front matter:

```md
---
comments: true
---
```

The embed is appended after the content on page views and after the adjacent-post navigation on single post views.

For this site, the intended public comment destination is the dedicated `Guestbook` page rather than the `About` page.

If you move a page that already has comments, you can preserve the existing Cusdis thread with optional overrides:

```md
---
comments: true
comment-id: page:about
comment-url: #/page/about
---
```

Use those only when you want a new page to keep showing an older thread instead of creating a new one.

## Manifest formats

### `posts/posts.json`

```json
[
  {
    "title": "Raised Foil Avatar Aang (#363)",
    "date": "2026-03-17",
    "slug": "raised-foil-aang",
    "file": "2026-03-17-raised-foil-aang.md",
    "tags": ["TLA", "acquisition", "grail"],
    "author": "Legoless",
    "excerpt": "Optional custom excerpt"
  }
]
```

### `pages/pages.json`

```json
[
  {
    "title": "About",
    "slug": "about",
    "file": "about.md"
  }
]
```

## Authors (hidden route)

- Posts now support an `author` field in `posts/posts.json`.
- Author names are shown on posts and are clickable.
- Clicking an author opens `#/author/<name>` with all posts by that author.
- `#/authors` exists as an index page, but it is intentionally not shown in the top navigation.

## Supported Markdown/content syntax

The renderer supports this core subset:

- Headings: `#` through `######`
- Paragraphs
- Hard line breaks inside a paragraph
- Links: `[label](url "optional title")`
- Emphasis: `*italic*`, `**bold**`, `~~strikethrough~~`
- Inline code: `` `code` ``
- Code fences: triple backticks, optional language
- Unordered and ordered lists
- Blockquotes: `>`
- Horizontal rules: `---`, `***`, `___`

### List behavior

- Single-level lists are best supported.
- Additional indented lines under a list item are treated as continuation text.
- Deep nested list behavior is limited.

### Line breaks inside a paragraph

If you want a line break without starting a new paragraph, use one of these:

1. Two trailing spaces at the end of the line:

```md
**Bold text**  
Text paragraph.
```

2. A trailing backslash at the end of the line:

```md
**Bold text**\
Text paragraph.
```

3. A literal HTML break tag:

```md
**Bold text**<br>
Text paragraph.
```

All three render as a single paragraph with a forced line break.

## Image embeds (responsive + sizing + thumbnail)

By default, images are responsive and fit the content column (`max-width: 100%`).

### 1) Standard Markdown image

```md
![Card front](/assets/images/aang-card.jpg)
```

### 2) Markdown size token (`=...`)

```md
![Card front](/assets/images/aang-card.jpg =320x)
![Card front](/assets/images/aang-card.jpg =320x200)
![Card front](/assets/images/aang-card.jpg =75%)
![Card front](/assets/images/aang-card.jpg =30rem)
```

Rules:

- `320x` -> width only
- `320x200` -> width + height
- `75%`, `30rem`, `50vw`, etc. -> width
- Bare numbers are treated as px and capped at 4096 (`320` => `320px`)

### 3) Markdown image attribute block (`{...}`)

```md
![Card front](/assets/images/aang-card.jpg){width=320px}
![Card front](/assets/images/aang-card.jpg){width=320px height=200px}
![Card front](/assets/images/aang-card.jpg){size=320x200}
![Card front](/assets/images/aang-card.jpg){thumb=true}
![Card front](/assets/images/aang-card.jpg){thumb caption="Front view"}
![Card front](/assets/images/aang-card.jpg){caption="\"Quoted caption text\""}
![Card front](/assets/images/aang-card.jpg){class=card-shot link=/assets/images/aang-card.jpg}
![Card front](/assets/images/aang-card.jpg){alt="Alternate text"}
```

Supported attributes:

- `width`
- `height`
- `size` (same format as `=WxH`)
- `thumb` (`thumb`, `thumb=true`, `thumb=1`, `thumb=yes`)
- `caption`
- `class` (sanitized; letters/numbers/`_`/`-` class names)
- `link` (wraps image in anchor)
- `alt` (overrides alt text)

If both Markdown size token and attribute size are present, explicit attributes win.

Quoted attribute values support escaped quotes and backslashes:

- `caption="\"Quoted text\""`
- `caption='He said \"hello\"'`
- `caption="A backslash: \\"`

### 4) MediaWiki-style image embeds

```text
[[File:/assets/images/aang-card.jpg|thumb|260px|alt=Card front|Caption text]]
[[Image:/assets/images/aang-card.jpg|300x200px|caption=Front view]]
[[File:/assets/images/aang-card.jpg|class=card-shot|link=/assets/images/aang-card.jpg]]
```

Supported options include:

- `thumb`, `thumbnail`, `frame`
- `260px`
- `300x200px`
- `x200px` (height only)
- `alt=...`
- `caption=...`
- `class=...`
- `link=...`
- If a plain trailing token is present, it is used as caption

## URL and path recommendations

- Prefer absolute-from-site paths for assets: `/assets/images/file.jpg`
- Site-relative hash links like `/#/page/about` are supported and are normalized for both local viewing and GitHub Pages project-site paths.
- Avoid spaces in URLs; use hyphens or encode as `%20`
- Keep slugs lowercase and stable

## GitHub Pages notes

- This project supports both:
  - local `file://` viewing
  - GitHub Pages project sites such as `https://legoless1.github.io/mtg-avatar/`
- Keep a root-level `.nojekyll` file in the published repo. This prevents GitHub Pages from processing `.md` files through Jekyll and ensures the app can fetch raw Markdown from `posts/` and `pages/`.
- If publishing to a project site, set `CFG.siteUrl` in `index.html` to the full project URL, for example:

```js
siteUrl:'https://legoless1.github.io/mtg-avatar',
```

- After changing `siteUrl`, regenerate `feed.xml`.

## Search behavior

- The generated static site embeds its search index directly into the search page, so search works on GitHub Pages and when opening the generated site locally from `file://`.
- Search matches title, tags, author, and body text.
- Wrap text in double quotes to search for an exact phrase, for example:

```text
"collector booster"
```

## Known parser limitations

- Nested lists are limited.
- This is a lightweight Markdown parser, not full CommonMark.
- Complex inline nesting may render differently from full Markdown engines.

## Quick templates

### New post template

````md
---
title: My New Post
date: 2026-03-09
tags: notes, example
---

Intro paragraph.

## Section

Some text with a [link](/#/pages).

![Example image](/assets/images/example.jpg =640x)

```js
console.log("hello");
```
````

### New page template

```md
---
title: About
---

This is a static page.

[[File:/assets/images/profile.jpg|thumb|220px|caption=Profile photo]]
```

### Guestbook page template

```md
---
comments: true
comment-id: page:about
comment-url: #/page/about
---

Welcome to the guestbook.

Leave a note below.
```

## Documentation maintenance rule

When you change parser behavior in `index.html`, also update:

1. Supported syntax section
2. Image embed section
3. Known limitations
4. Templates/examples if behavior changed










