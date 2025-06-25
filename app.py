from flask import Flask, request, jsonify, send_from_directory
import sqlite3
import os

app = Flask(__name__, static_folder='static')

DB_FILE = 'orders.db'

def init_db():
    with sqlite3.connect(DB_FILE) as conn:
        conn.execute('''
            CREATE TABLE IF NOT EXISTS orders (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                order_data TEXT NOT NULL
            )
        ''')
init_db()

@app.route('/')
def index():
    return send_from_directory(app.static_folder, 'index.html')

@app.route('/submit_order', methods=['POST'])
def submit_order():
    data = request.json
    if not data:
        return jsonify({'error': 'No data provided'}), 400
    with sqlite3.connect(DB_FILE) as conn:
        conn.execute('INSERT INTO orders (order_data) VALUES (?)', (str(data),))
        conn.commit()
    return jsonify({'status': 'Order saved'}), 200

# Serve other static files (JS, CSS) automatically
@app.route('/<path:path>')
def static_proxy(path):
    return send_from_directory(app.static_folder, path)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
