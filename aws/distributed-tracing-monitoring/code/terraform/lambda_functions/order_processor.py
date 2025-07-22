import json
import boto3
import uuid
from datetime import datetime
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all
import os

# Patch AWS SDK calls for X-Ray tracing
patch_all()

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['ORDERS_TABLE'])

@xray_recorder.capture('process_order')
def lambda_handler(event, context):
    """
    Lambda function to process order requests with comprehensive X-Ray tracing.
    
    This function demonstrates X-Ray instrumentation patterns including:
    - Custom annotations for filtering
    - Metadata capture for detailed analysis
    - Subsegment creation for operation timing
    - Error tracking and annotation
    """
    try:
        # Add custom annotations for filtering
        xray_recorder.put_annotation('service', 'order-processor')
        xray_recorder.put_annotation('operation', 'create_order')
        
        # Extract order details from API Gateway event
        body = json.loads(event['body']) if isinstance(event['body'], str) else event['body']
        
        # Generate unique order ID
        order_id = str(uuid.uuid4())
        
        # Validate required fields
        required_fields = ['customerId', 'productId']
        for field in required_fields:
            if field not in body:
                raise ValueError(f"Missing required field: {field}")
        
        order_data = {
            'orderId': order_id,
            'customerId': body.get('customerId'),
            'productId': body.get('productId'),
            'quantity': body.get('quantity', 1),
            'timestamp': datetime.utcnow().isoformat(),
            'status': 'pending'
        }
        
        # Add custom metadata for detailed analysis
        xray_recorder.put_metadata('order_details', {
            'order_id': order_id,
            'customer_id': body.get('customerId'),
            'product_id': body.get('productId'),
            'quantity': order_data['quantity'],
            'request_source': event.get('requestContext', {}).get('identity', {}).get('sourceIp', 'unknown')
        })
        
        # Store order in DynamoDB with subsegment tracking
        with xray_recorder.in_subsegment('dynamodb_put_item'):
            xray_recorder.current_subsegment().put_annotation('table_name', os.environ['ORDERS_TABLE'])
            table.put_item(Item=order_data)
            xray_recorder.put_annotation('order_stored', 'true')
        
        # Simulate calling inventory service
        inventory_response = check_inventory(body.get('productId'), order_data['quantity'])
        
        # Simulate calling notification service
        notification_response = send_notification(order_id, body.get('customerId'))
        
        # Success response
        response = {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Allow-Methods': 'POST, OPTIONS'
            },
            'body': json.dumps({
                'orderId': order_id,
                'status': 'processed',
                'timestamp': order_data['timestamp'],
                'inventory': inventory_response,
                'notification': notification_response
            })
        }
        
        xray_recorder.put_annotation('response_status', '200')
        return response
        
    except ValueError as e:
        # Handle validation errors
        xray_recorder.put_annotation('error_type', 'validation')
        xray_recorder.put_annotation('error_message', str(e))
        
        return {
            'statusCode': 400,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Validation Error',
                'message': str(e)
            })
        }
        
    except Exception as e:
        # Handle unexpected errors
        xray_recorder.put_annotation('error_type', 'internal')
        xray_recorder.put_annotation('error_message', str(e))
        
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Internal Server Error',
                'message': 'An unexpected error occurred'
            })
        }

@xray_recorder.capture('check_inventory')
def check_inventory(product_id, quantity):
    """
    Simulate inventory check with artificial delay and comprehensive tracing.
    
    Args:
        product_id (str): Product identifier
        quantity (int): Requested quantity
        
    Returns:
        dict: Inventory check response
    """
    import time
    
    # Add tracing annotations
    xray_recorder.put_annotation('product_id', product_id)
    xray_recorder.put_annotation('requested_quantity', str(quantity))
    
    # Simulate processing time
    time.sleep(0.1)
    
    # Simulate inventory availability logic
    available_quantity = 100  # Mock available quantity
    
    if quantity > available_quantity:
        xray_recorder.put_annotation('inventory_status', 'insufficient')
        return {
            'status': 'insufficient',
            'available': available_quantity,
            'requested': quantity
        }
    
    xray_recorder.put_annotation('inventory_status', 'available')
    xray_recorder.put_metadata('inventory_details', {
        'product_id': product_id,
        'available_quantity': available_quantity,
        'reserved_quantity': quantity
    })
    
    return {
        'status': 'available',
        'quantity': available_quantity,
        'reserved': quantity
    }

@xray_recorder.capture('send_notification')
def send_notification(order_id, customer_id):
    """
    Simulate notification sending with tracing.
    
    Args:
        order_id (str): Order identifier
        customer_id (str): Customer identifier
        
    Returns:
        dict: Notification response
    """
    import time
    
    # Add tracing annotations
    xray_recorder.put_annotation('notification_order_id', order_id)
    xray_recorder.put_annotation('notification_customer_id', customer_id)
    
    # Simulate notification processing time
    time.sleep(0.05)
    
    # Simulate notification channels
    channels = ['email', 'sms', 'push']
    selected_channel = 'email'  # Default channel
    
    xray_recorder.put_annotation('notification_channel', selected_channel)
    xray_recorder.put_annotation('notification_sent', 'true')
    
    xray_recorder.put_metadata('notification_details', {
        'order_id': order_id,
        'customer_id': customer_id,
        'channel': selected_channel,
        'timestamp': datetime.utcnow().isoformat()
    })
    
    return {
        'status': 'sent',
        'channel': selected_channel,
        'order_id': order_id
    }