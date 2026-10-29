FROM mcr.microsoft.com/playwright/python:v1.56.0-noble
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends xvfb x11vnc novnc websockify \
    && rm -rf /var/lib/apt/lists/*
COPY app.py run.sh ./
RUN chmod +x /app/run.sh && mkdir -p /data/profile
ENV PYTHONUNBUFFERED=1 DISPLAY=:99 BROWSER_PROFILE=/data/profile HEADLESS=false
EXPOSE 8000 6080
CMD ["/app/run.sh"]
