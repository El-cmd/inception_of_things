import os

from flask import Flask, render_template

app = Flask(__name__)

APP_VERSION = os.getenv("APP_VERSION", "v1")

VERSION_CONTENT = {
    "v1": {
        "title": "Deploy Monitor",
        "message": "Première version déployée automatiquement avec Argo CD.",
    },
    "v2": {
        "title": "Deploy Monitor 2.0",
        "message": "Deuxième version synchronisée automatiquement depuis GitHub !",
    },
}

@app.route("/")
def index():
    content = VERSION_CONTENT.get(APP_VERSION, VERSION_CONTENT["v1"])
    return render_template(
        "index.html",
        version=APP_VERSION,
        title=content["title"],
        message=content["message"],
    )

@app.route("/health")
def health():
    return {
        "status": "ok",
        "version": APP_VERSION
    }

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8888)
