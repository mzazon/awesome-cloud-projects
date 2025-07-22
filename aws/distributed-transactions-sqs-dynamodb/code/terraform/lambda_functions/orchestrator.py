import json
import boto3
import uuid
import os
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
sqs = boto3.client('sqs')

SAGA_STATE_TABLE = os.environ['SAGA_STATE_TABLE']
ORDER_QUEUE_URL = os.environ['ORDER_QUEUE_URL']
COMPENSATION_QUEUE_URL = os.environ['COMPENSATION_QUEUE_URL']

def lambda_handler(event, context):
    """
    Transaction Orchestrator Lambda Function
    
    Initiates distributed transactions using the Saga pattern and coordinates
    the transaction flow across multiple microservices.
    """
    try:
        # Initialize transaction
        transaction_id = str(uuid.uuid4())
        order_data = json.loads(event['body'])
        
        # Validate required fields
        required_fields = ['customerId', 'productId', 'quantity', 'amount']
        for field in required_fields:
            if field not in order_data:
                return {
                    'statusCode': 400,
                    'body': json.dumps({
                        'error': f'Missing required field: {field}',
                        'transactionId': transaction_id
                    })
                }
        
        # Create saga state record
        saga_table = dynamodb.Table(SAGA_STATE_TABLE)
        saga_table.put_item(
            Item={
                'TransactionId': transaction_id,
                'Status': 'STARTED',
                'CurrentStep': 'ORDER_PROCESSING',
                'Steps': ['ORDER_PROCESSING', 'PAYMENT_PROCESSING', 'INVENTORY_UPDATE'],
                'CompletedSteps': [],
                'OrderData': order_data,
                'Timestamp': datetime.utcnow().isoformat(),
                'TTL': int(datetime.utcnow().timestamp()) + 86400  # 24 hours TTL
            }
        )
        
        # Start transaction by sending to order queue
        message_body = {
            'transactionId': transaction_id,
            'step': 'ORDER_PROCESSING',
            'data': order_data
        }
        
        sqs.send_message(
            QueueUrl=ORDER_QUEUE_URL,
            MessageBody=json.dumps(message_body),
            MessageGroupId=transaction_id
        )
        
        print(f"Transaction {transaction_id} initiated successfully")
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'transactionId': transaction_id,
                'status': 'STARTED',
                'message': 'Transaction initiated successfully'
            })
        }
        
    except json.JSONDecodeError:
        return {
            'statusCode': 400,
            'body': json.dumps({
                'error': 'Invalid JSON in request body'
            })
        }
    except Exception as e:
        print(f"Error in orchestrator: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Internal server error',
                'message': str(e)
            })
        }