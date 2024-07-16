from flask import Blueprint, jsonify

products_bp = Blueprint('products', __name__)

products = [
        {'id': 1, 'name': 'Product A'},
        {'id': 2, 'name': 'Product B'},
        {'id': 3, 'name': 'Product C'},
        {'id': 4, 'name': 'Product D'}
    ]


@products_bp.route('/', methods=['GET'])
def get_products():
    return jsonify(products)

@products_bp.route('/<int:product_id>', methods=['GET'])
def get_product(product_id):
    product = None
    for p in products:
        if p['id'] == product_id:
            product = p
            break
    if product:
        return jsonify(product)
    else:
        return jsonify({'error': 'Product not found'}), 404


@products_bp.route('/', methods=['POST'])
def create_product():
    return jsonify([]), 201
