# syntax=docker/dockerfile:1.7
# GlitchTip 6.2.6 currently deployed on libraxis-vm. Review the HTML hook and
# Material tokens again before changing this digest to a newer GlitchTip release.
FROM glitchtip/glitchtip@sha256:a3d8eb1b36c1e1603d55ab32711ea3dd8115874742a781a57391a62a16e0dff6

USER root
COPY vista-theme.css /code/static/vista-theme.css
COPY inject_theme.py /tmp/inject_vista_theme.py
RUN python /tmp/inject_vista_theme.py /code/dist/index.html \
    && rm /tmp/inject_vista_theme.py
USER app:app
