from flask import Flask, jsonify
from users import users_bp
from products import products_bp
import requests
from opentelemetry.instrumentation.requests import RequestsInstrumentor

app = Flask(__name__)

# Instrument requests
RequestsInstrumentor().instrument()

# Register blueprints
app.register_blueprint(users_bp, url_prefix='/users')
app.register_blueprint(products_bp, url_prefix='/products')

@app.route('/')
def home():
    return "Welcome to the Flask App!"

# External call example
@app.route('/random-post')
def random_post():
    response = requests.get('https://jsonplaceholder.typicode.com/posts/1')
    if response.status_code == 200:
        return jsonify(response.json())
    else:
        return jsonify({"error": "Failed to fetch post"}), 500

if __name__ == '__main__':
    app.run(debug=True)
