"""
Order Service Lambda Function with X-Ray Distributed Tracing
Processes orders and coordinates with payment and inventory services
"""

import json
import boto3
import os
import time
import uuid
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all

# Patch all AWS SDK calls for X-Ray tracing
patch_all()

# Initialize Lambda client for downstream service calls
lambda_client = boto3.client('lambda')

# Get function names from environment variables
PAYMENT_FUNCTION_NAME = os.environ.get('PAYMENT_FUNCTION_NAME', '${payment_function_name}')
INVENTORY_FUNCTION_NAME = os.environ.get('INVENTORY_FUNCTION_NAME', '${inventory_function_name}')

@xray_recorder.capture('process_order')
def lambda_handler(event, context):
    """
    Process incoming order requests with comprehensive tracing
    
    Args:
        event: Order request containing order_id, customer_id, and items
        context: Lambda context object
        
    Returns:
        dict: Order processing result with status and details
    """
    try:
        # Extract order information with defaults
        order_id = event.get('order_id', f'order-{uuid.uuid4().hex[:8]}')
        customer_id = event.get('customer_id', 'unknown-customer')
        items = event.get('items', [])
        
        # Add annotations for filtering and searching traces
        xray_recorder.current_segment().put_annotation('order_id', order_id)
        xray_recorder.current_segment().put_annotation('customer_id', customer_id)
        xray_recorder.current_segment().put_annotation('item_count', len(items))
        xray_recorder.current_segment().put_annotation('service_type', 'order-processing')
        
        # Calculate order total for business context
        total_amount = sum(item.get('price', 0) * item.get('quantity', 1) for item in items)
        xray_recorder.current_segment().put_annotation('order_total', total_amount)
        
        print(f"Processing order {order_id} for customer {customer_id} with {len(items)} items")
        
        # Process payment with tracing
        payment_response = process_payment(order_id, items, total_amount)
        
        # Check inventory with tracing
        inventory_response = check_inventory(order_id, items)
        
        # Determine overall order status
        order_status = determine_order_status(payment_response, inventory_response)
        
        # Add comprehensive metadata for debugging
        xray_recorder.current_segment().put_metadata('order_details', {
            'order_id': order_id,
            'customer_id': customer_id,
            'items': items,
            'total_amount': total_amount,
            'payment_status': payment_response,
            'inventory_status': inventory_response,
            'final_status': order_status,
            'processing_timestamp': time.time()
        })
        
        # Add final status annotation
        xray_recorder.current_segment().put_annotation('order_status', order_status)
        
        response = {
            'statusCode': 200 if order_status == 'completed' else 400,
            'body': json.dumps({
                'order_id': order_id,
                'customer_id': customer_id,
                'status': order_status,
                'total_amount': total_amount,
                'payment_status': payment_response.get('status', 'unknown'),
                'inventory_status': inventory_response.get('status', 'unknown'),
                'items_processed': len(items),
                'message': f'Order {order_status} successfully'
            })
        }
        
        print(f"Order {order_id} processing completed with status: {order_status}")
        return response
        
    except Exception as e:
        # Add exception to X-Ray trace
        xray_recorder.current_segment().add_exception(e)
        xray_recorder.current_segment().put_annotation('error_occurred', True)
        
        print(f"Error processing order: {str(e)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Order processing failed',
                'message': str(e),
                'order_id': event.get('order_id', 'unknown')
            })
        }

@xray_recorder.capture('call_payment_service')
def process_payment(order_id, items, total_amount):
    """
    Call payment service with comprehensive tracing
    
    Args:
        order_id: Unique order identifier
        items: List of order items
        total_amount: Total order amount
        
    Returns:
        dict: Payment processing result
    """
    try:
        # Add service-specific annotations
        xray_recorder.current_subsegment().put_annotation('service', 'payment')
        xray_recorder.current_subsegment().put_annotation('total_amount', total_amount)
        xray_recorder.current_subsegment().put_annotation('payment_method', 'credit_card')
        
        # Prepare payment request payload
        payment_payload = {
            'order_id': order_id,
            'amount': total_amount,
            'currency': 'USD',
            'payment_method': 'credit_card',
            'items': items
        }
        
        xray_recorder.current_subsegment().put_metadata('payment_request', payment_payload)
        
        print(f"Calling payment service for order {order_id} amount ${total_amount}")
        
        # Invoke payment service Lambda function
        response = lambda_client.invoke(
            FunctionName=PAYMENT_FUNCTION_NAME,
            InvocationType='RequestResponse',
            Payload=json.dumps(payment_payload)
        )
        
        # Parse response
        response_payload = json.loads(response['Payload'].read())
        payment_result = json.loads(response_payload.get('body', '{}'))
        
        # Add response metadata
        xray_recorder.current_subsegment().put_metadata('payment_response', {
            'status_code': response_payload.get('statusCode'),
            'payment_result': payment_result
        })
        
        success = response_payload.get('statusCode') == 200
        xray_recorder.current_subsegment().put_annotation('payment_success', success)
        
        if success:
            print(f"Payment approved for order {order_id}")
            return {'status': 'approved', 'amount': total_amount, 'details': payment_result}
        else:
            print(f"Payment failed for order {order_id}")
            return {'status': 'failed', 'amount': total_amount, 'error': payment_result.get('error', 'Unknown error')}
            
    except Exception as e:
        xray_recorder.current_subsegment().add_exception(e)
        print(f"Payment service call failed: {str(e)}")
        return {'status': 'error', 'amount': total_amount, 'error': str(e)}

@xray_recorder.capture('call_inventory_service')  
def check_inventory(order_id, items):
    """
    Check inventory availability with comprehensive tracing
    
    Args:
        order_id: Unique order identifier
        items: List of order items to check
        
    Returns:
        dict: Inventory check result
    """
    try:
        # Add service-specific annotations
        xray_recorder.current_subsegment().put_annotation('service', 'inventory')
        xray_recorder.current_subsegment().put_annotation('items_to_check', len(items))
        
        inventory_results = []
        overall_status = 'available'
        
        # Check each item individually (in real scenario, might batch this)
        for item in items:
            product_id = item.get('product_id', 'unknown')
            quantity = item.get('quantity', 1)
            
            inventory_payload = {
                'product_id': product_id,
                'quantity': quantity,
                'order_id': order_id
            }
            
            print(f"Checking inventory for product {product_id} quantity {quantity}")
            
            # Invoke inventory service Lambda function
            response = lambda_client.invoke(
                FunctionName=INVENTORY_FUNCTION_NAME,
                InvocationType='RequestResponse',
                Payload=json.dumps(inventory_payload)
            )
            
            # Parse response
            response_payload = json.loads(response['Payload'].read())
            inventory_result = json.loads(response_payload.get('body', '{}'))
            
            item_status = 'available' if response_payload.get('statusCode') == 200 else 'insufficient'
            if item_status != 'available':
                overall_status = 'insufficient'
            
            inventory_results.append({
                'product_id': product_id,
                'requested_quantity': quantity,
                'status': item_status,
                'details': inventory_result
            })
        
        xray_recorder.current_subsegment().put_annotation('inventory_status', overall_status)
        xray_recorder.current_subsegment().put_metadata('inventory_check', {
            'order_id': order_id,
            'overall_status': overall_status,
            'item_results': inventory_results
        })
        
        print(f"Inventory check completed for order {order_id}: {overall_status}")
        
        return {
            'status': overall_status,
            'items_checked': len(items),
            'results': inventory_results
        }
        
    except Exception as e:
        xray_recorder.current_subsegment().add_exception(e)
        print(f"Inventory service call failed: {str(e)}")
        return {'status': 'error', 'error': str(e)}

def determine_order_status(payment_response, inventory_response):
    """
    Determine final order status based on payment and inventory results
    
    Args:
        payment_response: Payment service response
        inventory_response: Inventory service response
        
    Returns:
        str: Final order status
    """
    payment_status = payment_response.get('status', 'unknown')
    inventory_status = inventory_response.get('status', 'unknown')
    
    if payment_status == 'approved' and inventory_status == 'available':
        return 'completed'
    elif payment_status == 'failed':
        return 'payment_failed'
    elif inventory_status == 'insufficient':
        return 'inventory_insufficient'
    else:
        return 'processing_error'

# Health check endpoint for VPC Lattice
def health_check():
    """Simple health check for load balancer"""
    return {
        'statusCode': 200,
        'body': json.dumps({
            'status': 'healthy',
            'service': 'order-service',
            'timestamp': time.time()
        })
    }