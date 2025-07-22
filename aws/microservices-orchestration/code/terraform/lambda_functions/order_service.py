"""
Order Service Lambda Function
Handles order creation, validation, and publishes order events to EventBridge
"""
import json
import boto3
import uuid
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
    Lambda handler for Order Service
    Creates new orders and publishes events to EventBridge
    
    Args:
        event: Lambda event containing order data
        context: Lambda context object
        
    Returns:
        Dict containing status code and response body
    """
    try:
        logger.info(f"Received event: {json.dumps(event)}")
        
        # Parse order data from event
        if 'body' in event:
            # Handle API Gateway event
            order_data = json.loads(event['body'])
        else:
            # Handle direct invocation
            order_data = event
        
        # Validate required fields
        required_fields = ['customerId', 'items', 'totalAmount']
        for field in required_fields:
            if field not in order_data:
                raise ValueError(f"Missing required field: {field}")
        
        # Validate items structure
        if not isinstance(order_data['items'], list) or len(order_data['items']) == 0:
            raise ValueError("Items must be a non-empty list")
        
        for item in order_data['items']:
            if not all(key in item for key in ['productId', 'quantity', 'price']):
                raise ValueError("Each item must have productId, quantity, and price")
        
        # Generate unique order ID
        order_id = str(uuid.uuid4())
        
        # Create order record
        order_item = {
            'orderId': order_id,
            'customerId': order_data['customerId'],
            'items': order_data['items'],
            'totalAmount': order_data['totalAmount'],
            'status': 'PENDING',
            'createdAt': datetime.utcnow().isoformat(),
            'updatedAt': datetime.utcnow().isoformat()
        }
        
        # Store order in DynamoDB
        table = dynamodb.Table('${dynamodb_table_name}')
        table.put_item(Item=order_item)
        
        logger.info(f"Order created successfully: {order_id}")
        
        # Publish order created event to EventBridge
        event_detail = {
            'orderId': order_id,
            'customerId': order_data['customerId'],
            'items': order_data['items'],
            'totalAmount': order_data['totalAmount'],
            'status': 'PENDING',
            'timestamp': datetime.utcnow().isoformat()
        }
        
        eventbridge.put_events(
            Entries=[
                {
                    'Source': 'order.service',
                    'DetailType': 'Order Created',
                    'Detail': json.dumps(event_detail),
                    'EventBusName': '${eventbus_name}'
                }
            ]
        )
        
        logger.info(f"Order created event published for order: {order_id}")
        
        # Return success response
        response = {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'orderId': order_id,
                'status': 'PENDING',
                'message': 'Order created successfully',
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
        logger.info(f"Order service completed successfully for order: {order_id}")
        return response
        
    except json.JSONDecodeError as e:
        logger.error(f"JSON decode error: {str(e)}")
        return {
            'statusCode': 400,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'error': 'Invalid JSON format',
                'message': str(e)
            })
        }
        
    except ValueError as e:
        logger.error(f"Validation error: {str(e)}")
        return {
            'statusCode': 400,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'error': 'Validation failed',
                'message': str(e)
            })
        }
        
    except Exception as e:
        logger.error(f"Unexpected error in order service: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'error': 'Internal server error',
                'message': 'Failed to process order'
            })
        }