import json
import boto3
import os
import random
from datetime import datetime
from botocore.exceptions import ClientError

dynamodb = boto3.resource('dynamodb')
sqs = boto3.client('sqs')

INVENTORY_TABLE = os.environ['INVENTORY_TABLE']
SAGA_STATE_TABLE = os.environ['SAGA_STATE_TABLE']
COMPENSATION_QUEUE_URL = os.environ['COMPENSATION_QUEUE_URL']

def lambda_handler(event, context):
    """
    Inventory Service Lambda Function
    
    Handles inventory updates as the final step in the distributed transaction.
    Uses DynamoDB conditional updates to ensure atomic inventory operations.
    """
    try:
        for record in event['Records']:
            message_body = json.loads(record['body'])
            transaction_id = message_body['transactionId']
            inventory_data = message_body['data']
            
            # Validate inventory data
            required_fields = ['orderId', 'paymentId', 'productId', 'quantity']
            for field in required_fields:
                if field not in inventory_data:
                    raise ValueError(f"Missing required field in inventory data: {field}")
            
            # Validate business rules
            if inventory_data['quantity'] <= 0:
                raise ValueError("Inventory quantity must be greater than 0")
            
            # Simulate inventory availability check (85% success rate)
            # In production, this would check actual inventory levels
            if random.random() < 0.15:
                raise Exception("Insufficient inventory available for the requested quantity")
            
            # Update inventory using DynamoDB conditional update
            inventory_table = dynamodb.Table(INVENTORY_TABLE)
            saga_table = dynamodb.Table(SAGA_STATE_TABLE)
            
            # Try to update inventory atomically with conditional check
            try:
                update_response = inventory_table.update_item(
                    Key={'ProductId': inventory_data['productId']},
                    UpdateExpression='SET QuantityAvailable = QuantityAvailable - :quantity, LastUpdated = :timestamp, LastOrderId = :order_id',
                    ConditionExpression='QuantityAvailable >= :quantity',
                    ExpressionAttributeValues={
                        ':quantity': inventory_data['quantity'],
                        ':timestamp': datetime.utcnow().isoformat(),
                        ':order_id': inventory_data['orderId']
                    },
                    ReturnValues='UPDATED_NEW'
                )
                
                print(f"Inventory updated successfully for product {inventory_data['productId']}")
                
            except ClientError as e:
                if e.response['Error']['Code'] == 'ConditionalCheckFailedException':
                    # Get current inventory to provide detailed error
                    current_item = inventory_table.get_item(
                        Key={'ProductId': inventory_data['productId']}
                    )
                    
                    if 'Item' in current_item:
                        current_qty = current_item['Item'].get('QuantityAvailable', 0)
                        error_msg = f"Insufficient inventory - requested: {inventory_data['quantity']}, available: {current_qty}"
                    else:
                        error_msg = f"Product {inventory_data['productId']} not found in inventory"
                    
                    raise Exception(error_msg)
                else:
                    raise Exception(f"DynamoDB error: {str(e)}")
            
            # Update saga state to completed
            saga_table.update_item(
                Key={'TransactionId': transaction_id},
                UpdateExpression='SET CompletedSteps = list_append(CompletedSteps, :step), CurrentStep = :next_step, #status = :status, CompletionTimestamp = :timestamp',
                ExpressionAttributeNames={'#status': 'Status'},
                ExpressionAttributeValues={
                    ':step': ['INVENTORY_UPDATE'],
                    ':next_step': 'COMPLETED',
                    ':status': 'COMPLETED',
                    ':timestamp': datetime.utcnow().isoformat()
                }
            )
            
            print(f"Transaction {transaction_id} completed successfully - inventory updated for product {inventory_data['productId']}")
            
    except ValueError as ve:
        print(f"Validation error in inventory service: {str(ve)}")
        # Send compensation message for validation errors
        compensation_message = {
            'transactionId': transaction_id,
            'failedStep': 'INVENTORY_UPDATE',
            'error': str(ve)
        }
        
        sqs.send_message(
            QueueUrl=COMPENSATION_QUEUE_URL,
            MessageBody=json.dumps(compensation_message),
            MessageGroupId=transaction_id
        )
        
        raise
        
    except Exception as e:
        print(f"Error in inventory service: {str(e)}")
        # Send compensation message for inventory failures
        compensation_message = {
            'transactionId': transaction_id,
            'failedStep': 'INVENTORY_UPDATE',
            'error': str(e)
        }
        
        sqs.send_message(
            QueueUrl=COMPENSATION_QUEUE_URL,
            MessageBody=json.dumps(compensation_message),
            MessageGroupId=transaction_id
        )
        
        raise