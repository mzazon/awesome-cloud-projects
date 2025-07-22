import json
import boto3
import uuid
import os
import random
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
sqs = boto3.client('sqs')

PAYMENT_TABLE = os.environ['PAYMENT_TABLE']
SAGA_STATE_TABLE = os.environ['SAGA_STATE_TABLE']
INVENTORY_QUEUE_URL = os.environ['INVENTORY_QUEUE_URL']
COMPENSATION_QUEUE_URL = os.environ['COMPENSATION_QUEUE_URL']

def lambda_handler(event, context):
    """
    Payment Service Lambda Function
    
    Handles payment processing as the second step in the distributed transaction.
    Simulates payment gateway integration with configurable failure rates for testing.
    """
    try:
        for record in event['Records']:
            message_body = json.loads(record['body'])
            transaction_id = message_body['transactionId']
            payment_data = message_body['data']
            
            # Validate payment data
            required_fields = ['orderId', 'customerId', 'amount']
            for field in required_fields:
                if field not in payment_data:
                    raise ValueError(f"Missing required field in payment data: {field}")
            
            # Validate business rules
            if payment_data['amount'] <= 0:
                raise ValueError("Payment amount must be greater than 0")
            
            # Simulate payment processing with 90% success rate
            # In production, this would integrate with actual payment providers
            if random.random() < 0.1:
                raise Exception("Payment processing failed - insufficient funds or payment declined")
            
            # Generate payment ID
            payment_id = str(uuid.uuid4())
            
            # Create payment record
            payment_table = dynamodb.Table(PAYMENT_TABLE)
            saga_table = dynamodb.Table(SAGA_STATE_TABLE)
            
            # Create payment record with all required fields
            payment_item = {
                'PaymentId': payment_id,
                'TransactionId': transaction_id,
                'OrderId': payment_data['orderId'],
                'CustomerId': payment_data['customerId'],
                'Amount': payment_data['amount'],
                'Status': 'PROCESSED',
                'PaymentMethod': 'CREDIT_CARD',  # Simulated payment method
                'Timestamp': datetime.utcnow().isoformat(),
                'ProcessedBy': 'payment-service'
            }
            
            payment_table.put_item(Item=payment_item)
            
            # Update saga state to indicate payment processing completed
            saga_table.update_item(
                Key={'TransactionId': transaction_id},
                UpdateExpression='SET CompletedSteps = list_append(CompletedSteps, :step), CurrentStep = :next_step, PaymentId = :payment_id',
                ExpressionAttributeValues={
                    ':step': ['PAYMENT_PROCESSING'],
                    ':next_step': 'INVENTORY_UPDATE',
                    ':payment_id': payment_id
                }
            )
            
            # Get original order data for inventory update
            saga_response = saga_table.get_item(
                Key={'TransactionId': transaction_id}
            )
            
            if 'Item' not in saga_response:
                raise Exception(f"Saga state not found for transaction {transaction_id}")
            
            order_data = saga_response['Item']['OrderData']
            
            # Send message to inventory queue
            inventory_message = {
                'transactionId': transaction_id,
                'step': 'INVENTORY_UPDATE',
                'data': {
                    'orderId': payment_data['orderId'],
                    'paymentId': payment_id,
                    'productId': order_data['productId'],
                    'quantity': order_data['quantity'],
                    'customerId': payment_data['customerId']
                }
            }
            
            sqs.send_message(
                QueueUrl=INVENTORY_QUEUE_URL,
                MessageBody=json.dumps(inventory_message),
                MessageGroupId=transaction_id
            )
            
            print(f"Payment {payment_id} processed successfully for transaction {transaction_id}")
            
    except ValueError as ve:
        print(f"Validation error in payment service: {str(ve)}")
        # Send compensation message for validation errors
        compensation_message = {
            'transactionId': transaction_id,
            'failedStep': 'PAYMENT_PROCESSING',
            'error': str(ve)
        }
        
        sqs.send_message(
            QueueUrl=COMPENSATION_QUEUE_URL,
            MessageBody=json.dumps(compensation_message),
            MessageGroupId=transaction_id
        )
        
        raise
        
    except Exception as e:
        print(f"Error in payment service: {str(e)}")
        # Send compensation message for payment failures
        compensation_message = {
            'transactionId': transaction_id,
            'failedStep': 'PAYMENT_PROCESSING',
            'error': str(e)
        }
        
        sqs.send_message(
            QueueUrl=COMPENSATION_QUEUE_URL,
            MessageBody=json.dumps(compensation_message),
            MessageGroupId=transaction_id
        )
        
        raise