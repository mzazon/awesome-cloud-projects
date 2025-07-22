"""
Order Service Lambda Function
Handles order creation requests from API Gateway and publishes events to EventBridge
Implements comprehensive X-Ray tracing for distributed observability
"""

import json
import boto3
import os
from datetime import datetime
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all

# Patch AWS SDK calls for automatic X-Ray tracing
patch_all()

# Initialize AWS clients with X-Ray tracing
eventbridge = boto3.client('events')

@xray_recorder.capture('order_service_handler')
def lambda_handler(event, context):
    """
    Main Lambda handler for order service
    Processes incoming order requests and publishes events to EventBridge
    """
    
    # Extract trace context from API Gateway request
    trace_header = event.get('headers', {}).get('X-Amzn-Trace-Id')
    
    # Create subsegment for order processing logic
    subsegment = xray_recorder.begin_subsegment('process_order')
    
    try:
        # Extract order details from the request
        customer_id = event.get('pathParameters', {}).get('customerId', 'anonymous')
        
        # Parse request body if present
        request_body = {}
        if event.get('body'):
            try:
                request_body = json.loads(event['body'])
            except json.JSONDecodeError:
                xray_recorder.put_annotation('error', 'Invalid JSON in request body')
                return {
                    'statusCode': 400,
                    'headers': {
                        'Content-Type': 'application/json',
                        'X-Amzn-Trace-Id': trace_header
                    },
                    'body': json.dumps({
                        'error': 'Invalid JSON in request body'
                    })
                }
        
        # Generate unique order ID
        order_id = f"order-{datetime.now().strftime('%Y%m%d%H%M%S')}-{customer_id}"
        
        # Extract product details from request
        product_id = request_body.get('productId', 'default-product')
        quantity = request_body.get('quantity', 1)
        amount = request_body.get('amount', 99.99)
        
        # Add comprehensive metadata to X-Ray trace
        subsegment.put_metadata('order_details', {
            'order_id': order_id,
            'customer_id': customer_id,
            'product_id': product_id,
            'quantity': quantity,
            'amount': amount,
            'timestamp': datetime.now().isoformat(),
            'request_id': context.aws_request_id
        })
        
        # Add annotations for filtering and searching traces
        xray_recorder.put_annotation('order_id', order_id)
        xray_recorder.put_annotation('customer_id', customer_id)
        xray_recorder.put_annotation('service_name', 'order-service')
        xray_recorder.put_annotation('order_amount', amount)
        
        # Create order event payload for EventBridge
        order_event_detail = {
            'orderId': order_id,
            'customerId': customer_id,
            'productId': product_id,
            'quantity': quantity,
            'amount': amount,
            'status': 'created',
            'timestamp': datetime.now().isoformat(),
            'traceId': trace_header
        }
        
        # Publish order created event to EventBridge
        event_response = eventbridge.put_events(
            Entries=[
                {
                    'Source': 'order.service',
                    'DetailType': 'Order Created',
                    'Detail': json.dumps(order_event_detail),
                    'EventBusName': '${event_bus_name}'
                }
            ]
        )
        
        # Add EventBridge response metadata to trace
        subsegment.put_metadata('eventbridge_response', {
            'entries_count': len(event_response.get('Entries', [])),
            'failed_entry_count': event_response.get('FailedEntryCount', 0)
        })
        
        # Check for EventBridge publish failures
        if event_response.get('FailedEntryCount', 0) > 0:
            xray_recorder.put_annotation('eventbridge_failures', event_response.get('FailedEntryCount'))
            failed_entries = event_response.get('Entries', [])
            subsegment.put_metadata('failed_entries', failed_entries)
        
        # Return successful response
        response = {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'X-Amzn-Trace-Id': trace_header,
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'orderId': order_id,
                'customerId': customer_id,
                'status': 'created',
                'amount': amount,
                'message': 'Order created successfully and events published',
                'timestamp': datetime.now().isoformat()
            })
        }
        
        # Add response metadata to trace
        subsegment.put_metadata('response', {
            'status_code': response['statusCode'],
            'order_created': True
        })
        
        return response
        
    except Exception as e:
        # Capture error details in X-Ray trace
        error_message = str(e)
        xray_recorder.put_annotation('error', error_message)
        xray_recorder.put_annotation('error_type', type(e).__name__)
        
        subsegment.put_metadata('error_details', {
            'error_message': error_message,
            'error_type': type(e).__name__,
            'request_id': context.aws_request_id
        })
        
        # Return error response
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'X-Amzn-Trace-Id': trace_header,
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Internal server error',
                'requestId': context.aws_request_id,
                'message': 'Failed to process order'
            })
        }
        
    finally:
        # Always end the subsegment
        xray_recorder.end_subsegment()