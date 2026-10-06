FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt && useradd --uid 10001 --create-home relay && mkdir /data && chown relay:relay /data
COPY relay.py social.py ./
USER relay
ENV RELAY_HOST=0.0.0.0 PORT=8765 PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1
ENV SOCIAL_DB=/data/social.sqlite3
EXPOSE 8765
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8765/healthz', timeout=2)"
CMD ["python", "relay.py"]
