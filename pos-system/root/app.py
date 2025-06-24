import os
from flask import Flask, request, jsonify, render_template
import boto3
from botocore.exceptions import ClientError

app = Flask(__name__)

# Environment variables — must be set per container/region
DYNAMODB_TABLE = os.getenv('DYNAMODB_TABLE')
REGION = os.getenv('REGION')
MASTER_DB_TABLE = os.getenv('MASTER_DB_TABLE')

if not DYNAMODB_TABLE or not REGION or not MASTER_DB_TABLE:
    raise RuntimeError("Required environment variables: DYNAMODB_TABLE, REGION, MASTER_DB_TABLE")

# Initialize DynamoDB resource
dynamodb = boto3.resource('dynamodb', region_name=REGION)

store_table = dynamodb.Table(DYNAMODB_TABLE)
master_table = dynamodb.Table(MASTER_DB_TABLE)

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/order', methods=['POST'])
def create_order():
    try:
        order = request.json
        required_keys = {"order_id", "items", "total", "timestamp"}
        if not order or not required_keys.issubset(order.keys()):
            return jsonify({"error": "Missing required order fields"}), 400

        # Put order in store table
        store_table.put_item(Item=order)

        # Put order in master table
        master_table.put_item(Item=order)

        return jsonify({"message": "Order created successfully"}), 201

    except ClientError as e:
        return jsonify({"error": str(e)}), 500

@app.route('/orders/<order_id>', methods=['GET'])
def get_order(order_id):
    try:
        response = store_table.get_item(Key={"order_id": order_id})
        item = response.get('Item')
        if not item:
            return jsonify({"error": "Order not found"}), 404
        return jsonify(item)
    except ClientError as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
