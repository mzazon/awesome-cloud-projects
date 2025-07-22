import json
import boto3
import uuid
import os
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
sqs = boto3.client('sqs')

ORDER_TABLE = os.environ['ORDER_TABLE']
SAGA_STATE_TABLE = os.environ['SAGA_STATE_TABLE']
PAYMENT_QUEUE_URL = os.environ['PAYMENT_QUEUE_URL']
COMPENSATION_QUEUE_URL = os.environ['COMPENSATION_QUEUE_URL']

def lambda_handler(event, context):
    """
    Order Service Lambda Function
    
    Handles order creation as the first step in the distributed transaction.
    Creates order records and forwards transaction to payment processing.
    """
    try:
        for record in event['Records']:
            message_body = json.loads(record['body'])
            transaction_id = message_body['transactionId']
            order_data = message_body['data']
            
            # Generate order ID
            order_id = str(uuid.uuid4())
            
            # Validate order data
            required_fields = ['customerId', 'productId', 'quantity', 'amount']
            for field in required_fields:
                if field not in order_data:
                    raise ValueError(f"Missing required field in order data: {field}")
            
            # Validate business rules
            if order_data['quantity'] <= 0:
                raise ValueError("Order quantity must be greater than 0")
            
            if order_data['amount'] <= 0:
                raise ValueError("Order amount must be greater than 0")
            
            # Create order record
            order_table = dynamodb.Table(ORDER_TABLE)
            saga_table = dynamodb.Table(SAGA_STATE_TABLE)
            
            # Create order with all required fields
            order_item = {
                'OrderId': order_id,
                'TransactionId': transaction_id,
                'CustomerId': order_data['customerId'],
                'ProductId': order_data['productId'],
                'Quantity': order_data['quantity'],
                'Amount': order_data['amount'],
                'Status': 'PENDING',
                'Timestamp': datetime.utcnow().isoformat(),
                'CreatedBy': 'order-service'
            }
            
            order_table.put_item(Item=order_item)
            
            # Update saga state to indicate order processing completed
            saga_table.update_item(
                Key={'TransactionId': transaction_id},
                UpdateExpression='SET CompletedSteps = list_append(CompletedSteps, :step), CurrentStep = :next_step, OrderId = :order_id',
                ExpressionAttributeValues={
                    ':step': ['ORDER_PROCESSING'],
                    ':next_step': 'PAYMENT_PROCESSING',
                    ':order_id': order_id
                }
            )
            
            # Send message to payment queue
            payment_message = {
                'transactionId': transaction_id,
                'step': 'PAYMENT_PROCESSING',
                'data': {
                    'orderId': order_id,
                    'customerId': order_data['customerId'],
                    'amount': order_data['amount'],
                    'productId': order_data['productId'],
                    'quantity': order_data['quantity']
                }
            }
            
            sqs.send_message(
                QueueUrl=PAYMENT_QUEUE_URL,
                MessageBody=json.dumps(payment_message),
                MessageGroupId=transaction_id
            )
            
            print(f"Order {order_id} created successfully for transaction {transaction_id}")
            
    except ValueError as ve:
        print(f"Validation error in order service: {str(ve)}")
        # Send compensation message for validation errors
        compensation_message = {
            'transactionId': transaction_id,
            'failedStep': 'ORDER_PROCESSING',
            'error': str(ve)
        }
        
        sqs.send_message(
            QueueUrl=COMPENSATION_QUEUE_URL,
            MessageBody=json.dumps(compensation_message),
            MessageGroupId=transaction_id
        )
        
        raise
        
    except Exception as e:
        print(f"Error in order service: {str(e)}")
        # Send compensation message for general errors
        compensation_message = {
            'transactionId': transaction_id,
            'failedStep': 'ORDER_PROCESSING',
            'error': str(e)
        }
        
        sqs.send_message(
            QueueUrl=COMPENSATION_QUEUE_URL,
            MessageBody=json.dumps(compensation_message),
            MessageGroupId=transaction_id
        )
        
        raise