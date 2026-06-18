# Blog build

Jekyll source lives in this repository. Markdown articles are synced from
`../omni/blog` into `_posts` before building.

```sh
make setup
make sync
make build
make serve
```

GitHub Actions deploys the site from the committed Jekyll source. In the
repository settings, set GitHub Pages' build source to **GitHub Actions**.
Do not commit `_site` or generated article HTML under category/date folders.

Article source layout:

```text
../omni/blog/<category>/YYYY-MM-DD-slug.md
../omni/blog/attrs/img/...
../omni/blog/attrs/pdf/...
```

The sync step injects Jekyll post metadata, removes the duplicate top-level
Markdown title, rewrites local asset links to `/img` and `/pdf`, and rewrites
internal `.md` links to their generated `.html` URLs.

LaTeX is rendered by MathJax in the shared page head. Inline math supports
`$...$` and `\(...\)`, and display math supports `$$...$$` and `\[...\]`.

Comments are configured in `_config.yml` under `comments.provider`.

- `giscus`: current provider. Comments are GitHub Discussions-backed under the
  `General` discussion category.

If giscus shows an installation error, install the giscus GitHub App for
`vitrun/vitrun.github.io`.
