import json
import boto3
import uuid
import random
from datetime import datetime

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    try:
        table_name = event['tableName']
        table = dynamodb.Table(table_name)
        
        # Simulate payment processing with configurable failure rate
        failure_rate = float("${failure_rate}")
        if random.random() < failure_rate:
            return {
                'statusCode': 400,
                'status': 'PAYMENT_FAILED',
                'message': 'Payment processing failed'
            }
        
        payment_id = str(uuid.uuid4())
        payment_data = {
            'paymentId': payment_id,
            'orderId': event['orderId'],
            'customerId': event['customerId'],
            'amount': event['amount'],
            'status': 'COMPLETED',
            'timestamp': datetime.utcnow().isoformat()
        }
        
        table.put_item(Item=payment_data)
        
        return {
            'statusCode': 200,
            'status': 'PAYMENT_COMPLETED',
            'paymentId': payment_id,
            'amount': event['amount'],
            'message': 'Payment processed successfully'
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'status': 'PAYMENT_FAILED',
            'error': str(e)
        }