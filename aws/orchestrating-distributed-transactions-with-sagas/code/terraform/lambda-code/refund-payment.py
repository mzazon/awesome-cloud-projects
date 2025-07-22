import json
import boto3
import uuid
from datetime import datetime

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    try:
        table_name = event['tableName']
        table = dynamodb.Table(table_name)
        
        # Create refund record
        refund_id = str(uuid.uuid4())
        refund_data = {
            'paymentId': refund_id,
            'originalPaymentId': event['paymentId'],
            'orderId': event['orderId'],
            'customerId': event['customerId'],
            'amount': event['amount'],
            'status': 'REFUNDED',
            'type': 'REFUND',
            'timestamp': datetime.utcnow().isoformat()
        }
        
        table.put_item(Item=refund_data)
        
        return {
            'statusCode': 200,
            'status': 'PAYMENT_REFUNDED',
            'refundId': refund_id,
            'amount': event['amount'],
            'message': 'Payment refunded successfully'
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'status': 'REFUND_FAILED',
            'error': str(e)
        }