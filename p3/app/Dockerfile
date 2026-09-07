FROM python:3.12-slim

WORKDIR /app

# La même base sert aux deux images. La valeur est enregistrée dans l'image :
# changer le tag GitOps de v1 vers v2 change donc réellement l'application.
ARG APP_VERSION=v1
ENV APP_VERSION=${APP_VERSION} \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .
COPY templates ./templates

EXPOSE 8888

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8888/health')"

CMD ["python", "app.py"]
