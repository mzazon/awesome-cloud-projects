"""
Payment Service Lambda Function
Handles payment processing with built-in failure simulation and event publishing
"""
import json
import boto3
import random
import time
import logging
from datetime import datetime
from typing import Dict, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
eventbridge = boto3.client('events')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for Payment Service
    Processes payments and publishes success/failure events
    
    Args:
        event: Lambda event containing payment data
        context: Lambda context object
        
    Returns:
        Dict containing status code and response body
    """
    try:
        logger.info(f"Received payment event: {json.dumps(event)}")
        
        # Parse payment data from Step Functions or direct invocation
        if 'detail' in event:
            # From EventBridge/Step Functions
            payment_data = event['detail']
        elif 'Payload' in event and 'detail' in event['Payload']:
            # From Step Functions with Payload wrapper
            payment_data = event['Payload']['detail']
        else:
            # Direct invocation
            payment_data = event
        
        # Extract required fields
        order_id = payment_data.get('orderId')
        customer_id = payment_data.get('customerId')
        amount = payment_data.get('totalAmount')
        
        if not all([order_id, customer_id, amount]):
            raise ValueError("Missing required payment data: orderId, customerId, or totalAmount")
        
        logger.info(f"Processing payment for order {order_id}, customer {customer_id}, amount ${amount}")
        
        # Simulate payment processing delay (1-3 seconds)
        processing_delay = random.uniform(1, 3)
        time.sleep(processing_delay)
        
        # Simulate payment success/failure (90% success rate)
        payment_successful = random.random() < 0.9
        
        # Get current timestamp
        current_time = datetime.utcnow().isoformat()
        
        # Update order status in DynamoDB
        table = dynamodb.Table('${dynamodb_table_name}')
        
        if payment_successful:
            payment_id = f"pay_{order_id[:8]}"
            
            # Update order with payment success
            table.update_item(
                Key={
                    'orderId': order_id,
                    'customerId': customer_id
                },
                UpdateExpression='SET #status = :status, paymentId = :paymentId, updatedAt = :updatedAt',
                ExpressionAttributeNames={
                    '#status': 'status'
                },
                ExpressionAttributeValues={
                    ':status': 'PAID',
                    ':paymentId': payment_id,
                    ':updatedAt': current_time
                }
            )
            
            # Publish payment success event
            event_detail = {
                'orderId': order_id,
                'customerId': customer_id,
                'paymentId': payment_id,
                'amount': amount,
                'status': 'SUCCESS',
                'processedAt': current_time
            }
            
            eventbridge.put_events(
                Entries=[
                    {
                        'Source': 'payment.service',
                        'DetailType': 'Payment Processed',
                        'Detail': json.dumps(event_detail),
                        'EventBusName': '${eventbus_name}'
                    }
                ]
            )
            
            logger.info(f"Payment successful for order {order_id}: {payment_id}")
            
            response_body = {
                'orderId': order_id,
                'paymentId': payment_id,
                'paymentStatus': 'SUCCESS',
                'amount': amount,
                'processedAt': current_time
            }
            
        else:
            # Update order with payment failure
            table.update_item(
                Key={
                    'orderId': order_id,
                    'customerId': customer_id
                },
                UpdateExpression='SET #status = :status, updatedAt = :updatedAt, failureReason = :reason',
                ExpressionAttributeNames={
                    '#status': 'status'
                },
                ExpressionAttributeValues={
                    ':status': 'PAYMENT_FAILED',
                    ':updatedAt': current_time,
                    ':reason': 'Payment processing failed'
                }
            )
            
            # Publish payment failure event
            event_detail = {
                'orderId': order_id,
                'customerId': customer_id,
                'amount': amount,
                'status': 'FAILED',
                'reason': 'Payment processing failed',
                'processedAt': current_time
            }
            
            eventbridge.put_events(
                Entries=[
                    {
                        'Source': 'payment.service',
                        'DetailType': 'Payment Failed',
                        'Detail': json.dumps(event_detail),
                        'EventBusName': '${eventbus_name}'
                    }
                ]
            )
            
            logger.warning(f"Payment failed for order {order_id}")
            
            response_body = {
                'orderId': order_id,
                'paymentStatus': 'FAILED',
                'amount': amount,
                'reason': 'Payment processing failed',
                'processedAt': current_time
            }
        
        # Return response
        response = {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps(response_body)
        }
        
        logger.info(f"Payment service completed for order {order_id}")
        return response
        
    except Exception as e:
        logger.error(f"Error processing payment: {str(e)}")
        
        # Try to update order status to payment failed if we have the order info
        try:
            if 'order_id' in locals() and 'customer_id' in locals():
                table = dynamodb.Table('${dynamodb_table_name}')
                table.update_item(
                    Key={
                        'orderId': order_id,
                        'customerId': customer_id
                    },
                    UpdateExpression='SET #status = :status, updatedAt = :updatedAt, failureReason = :reason',
                    ExpressionAttributeNames={
                        '#status': 'status'
                    },
                    ExpressionAttributeValues={
                        ':status': 'PAYMENT_ERROR',
                        ':updatedAt': datetime.utcnow().isoformat(),
                        ':reason': f'Payment service error: {str(e)}'
                    }
                )
        except:
            logger.error("Failed to update order status after payment error")
        
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'error': 'Payment processing error',
                'message': str(e)
            })
        }