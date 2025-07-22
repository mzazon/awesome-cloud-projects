import json
import boto3
import os
from datetime import datetime

dynamodb = boto3.resource('dynamodb')

SAGA_STATE_TABLE = os.environ['SAGA_STATE_TABLE']

def lambda_handler(event, context):
    """
    Compensation Handler Lambda Function
    
    Handles compensation (rollback) logic when transactions fail,
    ensuring proper cleanup and state management.
    """
    try:
        # Process compensation messages
        for record in event['Records']:
            message_body = json.loads(record['body'])
            transaction_id = message_body['transactionId']
            failed_step = message_body['failedStep']
            error_message = message_body.get('error', 'Unknown error')
            
            # Update saga state to failed
            saga_table = dynamodb.Table(SAGA_STATE_TABLE)
            saga_table.update_item(
                Key={'TransactionId': transaction_id},
                UpdateExpression='SET #status = :status, FailedStep = :failed_step, ErrorMessage = :error_message, CompensationTimestamp = :timestamp',
                ExpressionAttributeNames={'#status': 'Status'},
                ExpressionAttributeValues={
                    ':status': 'FAILED',
                    ':failed_step': failed_step,
                    ':error_message': error_message,
                    ':timestamp': datetime.utcnow().isoformat()
                }
            )
            
            # Log compensation action
            print(f"Transaction {transaction_id} failed at step {failed_step}: {error_message}")
            
            # TODO: Implement specific compensation logic based on failed step
            # For example:
            # - If ORDER_PROCESSING failed, no cleanup needed
            # - If PAYMENT_PROCESSING failed, cancel any pending orders
            # - If INVENTORY_UPDATE failed, refund payment and cancel order
            
            compensation_actions = {
                'ORDER_PROCESSING': 'No compensation needed - transaction failed before any resources were committed',
                'PAYMENT_PROCESSING': 'Compensation: Cancel pending order if created',
                'INVENTORY_UPDATE': 'Compensation: Refund payment and cancel order'
            }
            
            action = compensation_actions.get(failed_step, 'Unknown compensation action')
            print(f"Compensation action for {failed_step}: {action}")
            
    except Exception as e:
        print(f"Error in compensation handler: {str(e)}")
        raise  # Re-raise to trigger DLQ if needed