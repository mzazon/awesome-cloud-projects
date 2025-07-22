import json
import boto3
import uuid
from datetime import datetime

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    try:
        table_name = event['tableName']
        table = dynamodb.Table(table_name)
        
        order_id = str(uuid.uuid4())
        order_data = {
            'orderId': order_id,
            'customerId': event['customerId'],
            'productId': event['productId'],
            'quantity': event['quantity'],
            'status': 'PENDING',
            'timestamp': datetime.utcnow().isoformat()
        }
        
        table.put_item(Item=order_data)
        
        return {
            'statusCode': 200,
            'status': 'ORDER_PLACED',
            'orderId': order_id,
            'message': 'Order placed successfully'
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'status': 'ORDER_FAILED',
            'error': str(e)
        }