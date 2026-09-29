"""Attach the Vista theme after GlitchTip's generated stylesheet.

Fail the image build if the pinned frontend layout changes. The theme is a
self-hosted static asset; no proxy-side HTML rewriting or third-party request.
"""

from pathlib import Path
import re
import sys


THEME_LINK = '<link rel="stylesheet" href="static/vista-theme.css">'
STYLESHEET = re.compile(r'(<link rel="stylesheet" href="static/styles-[^"/]+\.css">)')


def inject(html: str) -> str:
    if html.count(THEME_LINK) == 1:
        return html
    if THEME_LINK in html:
        raise ValueError("Vista theme link appears more than once")
    if len(STYLESHEET.findall(html)) != 1:
        raise ValueError("expected exactly one generated GlitchTip stylesheet")
    return STYLESHEET.sub(lambda match: match.group(1) + "\n    " + THEME_LINK, html, count=1)


if __name__ == "__main__":
    index = Path(sys.argv[1])
    index.write_text(inject(index.read_text()))
