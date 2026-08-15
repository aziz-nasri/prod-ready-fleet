# app.py
from flask import Flask, jsonify, request
import psycopg2
import os

app = Flask(__name__)

def get_db():
    return psycopg2.connect(
        host=os.environ["DB_HOST"],
        dbname=os.environ["DB_NAME"],
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
    )

@app.route("/health")
def health():
    try:
        conn = get_db()
        conn.close()
        return jsonify(status="ok", db="connected"), 200
    except Exception as e:
        return jsonify(status="degraded", error=str(e)), 503

@app.route("/notes", methods=["GET", "POST"])
def notes():
    conn = get_db()
    cur = conn.cursor()
    if request.method == "POST":
        text = request.json.get("text", "")
        cur.execute("INSERT INTO notes (text) VALUES (%s)", (text,))
        conn.commit()
    cur.execute("SELECT id, text, created_at FROM notes ORDER BY id DESC LIMIT 20")
    rows = cur.fetchall()
    conn.close()
    return jsonify([{"id": r[0], "text": r[1], "created_at": str(r[2])} for r in rows])

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)