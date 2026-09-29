# Vista VET theme for GlitchTip

GlitchTip 6.2.6 does not expose a full theme setting. Its supported
`GLITCHTIP_INSTANCE_NAME` changes the displayed instance name; the visual
system is compiled into the Angular frontend. This small derivative image keeps
the GlitchTip application intact and adds one same-origin stylesheet after its
generated CSS. It changes Material color roles, selected navigation, card and
form surfaces, focus rings, and motion. Error, warning, and uptime remain
distinct. The logo and product attribution remain GlitchTip.

The palette follows Vista's binding desktop brand contract:
graphite `#171513`, bone `#F4EFE4`, paper `#FFFCF4`, ochre `#B38F6B`, teal
`#3F837A`, and burden `#8A5A4D`. The panel keeps its existing compact
information density. Ochre marks focus and selection; it is not a large fill.
Light/dark selection continues to follow GlitchTip's own preference.

## Build and verification

The Dockerfile pins the exact GlitchTip image running on `libraxis-vm` on
29 September 2026. To prepare a replacement image without touching the live
service:

```sh
docker build -t vista-glitchtip:6.2.6-theme1 migration/glitchtip/vista-theme
docker run --rm --entrypoint python vista-glitchtip:6.2.6-theme1 -c \
  'from pathlib import Path; i=Path("/code/dist/index.html").read_text(); assert i.count("static/vista-theme.css")==1; assert Path("/code/static/vista-theme.css").is_file()'
```

`inject_theme.py` deliberately fails if the versioned frontend no longer has
exactly one generated stylesheet. Revalidate the hook, token names, and static
asset path before upgrading GlitchTip. The stylesheet is served from the same
origin, which fits the current CSP without adding a remote source.

Before activation, publish this image to an approved registry and set
`GLITCHTIP_IMAGE` in the private VM environment to its immutable digest. Keep
the previous digest for rollback. Activate **web and worker from the same
image**, then verify the public HTML loads `/static/vista-theme.css`, sign-in,
issue list/detail, project switcher, uptime page, light/dark preference, and
mobile layout. Re-run the event-ID ingestion probe and health check. If any
behavior differs, restore the previous digest and restart web/worker.

The image built during preparation is only a candidate; a successful image
build and color-contrast calculation do not prove the live panel has changed.
