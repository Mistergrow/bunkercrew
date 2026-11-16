# Tag and digest as published on Docker Hub on 2026-11-14. Refresh both together
# to pick up base image updates: docker pull python:3.12-slim prints the digest.
FROM python:3.12-slim@sha256:5e2bdb1b0d542d5039cffb8181c65930093949194a65c365dfb1b0fe13a4fa5b
WORKDIR /app
COPY requirements.lock .
RUN pip install --no-cache-dir --require-hashes -r requirements.lock && useradd --uid 10001 --create-home relay && mkdir /data && chown relay:relay /data
COPY relay.py social.py ./
USER relay
ENV RELAY_HOST=0.0.0.0 PORT=8765 PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1
ENV SOCIAL_DB=/data/social.sqlite3
EXPOSE 8765
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8765/healthz', timeout=2)"
CMD ["python", "relay.py"]
