from flask import Flask
from users import users_bp
from products import products_bp

app = Flask(__name__)

# Register blueprints
app.register_blueprint(users_bp, url_prefix='/users')
app.register_blueprint(products_bp, url_prefix='/products')

@app.route('/')
def home():
    return "Welcome to the Flask App!"

if __name__ == '__main__':
    app.run(debug=True)
