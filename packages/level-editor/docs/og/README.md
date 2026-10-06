`card.html` is the source of the link-preview image `public/og-image.png`
(1200×630, used by the `og:image` / `twitter:image` tags in `index.html`).
To remake it after changing the card or `docs/img/overview.png`, from
`packages/level-editor`:

```
google-chrome --headless --hide-scrollbars --force-device-scale-factor=1 \
  --window-size=1200,630 --screenshot="$PWD/public/og-image.png" "file://$PWD/docs/og/card.html"
```
