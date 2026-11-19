# Session log: teacher chibi cake tags

- Date: 2026-11-19, Asia/Saigon.
- Repository: `/home/sinh/Documents/bakery-shop`.
- PA deployment: `d-df3cb0`, team/mode `rogue-one`, runtime `pi`.
- User requested session logging and registry completion after delivery.

## Delivered outcome

Two personalized cake decoration tags share one A6 landscape sheet
(148 × 105 mm). Both characters are female teacher chibis wearing áo dài,
without glasses. The first teacher wears pink and holds a book and flowers;
the second wears lavender and holds a book and pointer. Pink scalloped cutting
outlines, flowers, schoolbooks and brown/pink handwritten lettering follow
the supplied references.

Final messages:

1. **Chúc cô Nhiệt 20 - 11 vui vẻ**
2. **Chúc cô Nỡ 20 - 11 vui vẻ. Cảm ơn cô nhiều**

The requested removal of “Dạ” is applied to the first message. The second tag
was verified pixel-for-pixel unchanged after that text revision.

## Final files

- PNG: `/home/sinh/Documents/bakery-shop/designs/cake-tags/teachers-day/exports/cake-tags-teacher-chibi-20-11-a6.png`
- PDF: `/home/sinh/Documents/bakery-shop/designs/cake-tags/teachers-day/exports/cake-tags-teacher-chibi-20-11-a6.pdf`
- Reuse guide: `/home/sinh/Documents/bakery-shop/docs/cake-decoration-tags.md`

Print on **A6 landscape at 100% / Actual size**, with “Fit to page” disabled.
Cut along the outer pink scalloped contour, not the inner dashed decoration.

Final SHA-256:

```text
PNG 02811a8f82cc7d08055d7a2abbc463273e3347b1ac51b79751fc628e836ccb7c
PDF 88cd488f91450c1401c9272192786f522e9ac65e44591e7bee5c258225dcedbf
```

## Saved for future work

All reusable assets are under `designs/cake-tags/teachers-day/`:

- `messages.json`: editable message lines and highlighted names.
- `render-cake-tags.py`: deterministic Pillow typesetting and PNG/PDF export.
- `templates/teacher-chibi-blank.png`: current teacher artwork without text or glasses.
- `fonts/`: bundled Vietnamese-capable Dancing Script Bold and SIL OFL license.
- `references/`: five unchanged original images, with six upload records in
  `sources.json`; one duplicate upload shares a single saved original.
- The two November 13 teacher sheets are references only, not 12 additional
  tags on the final print sheet.
- Earlier little-girl chibi designs and their exports are preserved separately.

Regenerate the current files from the repository root:

```sh
python designs/cake-tags/teachers-day/render-cake-tags.py
```

This needs Python and Pillow, but no AI generation or external font install.

## Verification

Fresh closeout checks passed:

- Final PNG is RGB, 1748 × 1240 px, 300 DPI, with the exact final Vietnamese messages.
- PDF contains one A6 landscape page, approximately 147.997 × 104.987 mm.
- The second tag is pixel-for-pixel unchanged by the final text edit.
- Every saved reference matches its recorded SHA-256.
- `python -m ruff check designs/cake-tags/teachers-day/render-cake-tags.py --select E9,F63,F7,F82` passed.
- `git diff --check` passed.

Earlier checks also confirmed reproducible PNG output from another working
directory, preservation of the older design, and rejection of invalid tag
counts and overflowing text. The final image was visually inspected, including
the absence of glasses. Physical printing and human print-quality acceptance
were not performed or claimed.

## Repository and closeout notes

No application, database, deployment/runtime or CI code was changed. The
pre-existing staged `CHANGELOG.md` change was left untouched. Design assets,
reuse documentation and this report are saved locally; no Git commit or push
was requested or performed.

This report is the session-log attachment for native PA registry closeout.
`ppa registry complete d-df3cb0 --status success --log-file <this report>`
acknowledged: “Staged d-df3cb0 with status success; completion publishes when
foreground Pi exits”. The registry remains `running` while this foreground
Pi process is active; terminal success publication is deferred until Pi exits.
The native registry result, rather than this narrative, establishes the
final deployment status. No unresolved questions or implementation blockers
remain.
