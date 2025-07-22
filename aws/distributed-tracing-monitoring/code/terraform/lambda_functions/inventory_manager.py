import json
import boto3
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all
import time
from datetime import datetime

# Patch AWS SDK calls for X-Ray tracing
patch_all()

@xray_recorder.capture('inventory_manager')
def lambda_handler(event, context):
    """
    Lambda function for inventory management with X-Ray tracing.
    
    This function simulates inventory operations and demonstrates:
    - Service-level tracing annotations
    - Detailed subsegment creation
    - Business operation tracking
    - Performance monitoring
    """
    try:
        # Add service identification annotations
        xray_recorder.put_annotation('service', 'inventory-manager')
        xray_recorder.put_annotation('operation', 'update_inventory')
        xray_recorder.put_annotation('function_version', context.function_version if context else 'unknown')
        
        # Extract inventory request details
        product_id = event.get('productId')
        quantity = event.get('quantity', 1)
        operation_type = event.get('operation', 'reserve')  # reserve, release, check
        
        if not product_id:
            raise ValueError("Product ID is required")
        
        # Add request metadata
        xray_recorder.put_metadata('inventory_request', {
            'product_id': product_id,
            'quantity': quantity,
            'operation_type': operation_type,
            'request_timestamp': datetime.utcnow().isoformat()
        })
        
        # Simulate inventory validation with detailed tracing
        with xray_recorder.in_subsegment('inventory_validation'):
            xray_recorder.current_subsegment().put_annotation('validation_product_id', product_id)
            xray_recorder.current_subsegment().put_annotation('validation_quantity', str(quantity))
            
            # Simulate database lookup delay
            time.sleep(0.1)
            
            # Mock inventory data
            current_inventory = get_current_inventory(product_id)
            
            # Validate inventory availability
            if operation_type == 'reserve' and current_inventory['available'] < quantity:
                xray_recorder.put_annotation('validation_result', 'insufficient_inventory')
                raise ValueError(f"Insufficient inventory. Available: {current_inventory['available']}, Requested: {quantity}")
            
            xray_recorder.put_annotation('validation_result', 'success')
            xray_recorder.put_metadata('validation_details', {
                'current_available': current_inventory['available'],
                'current_reserved': current_inventory['reserved'],
                'operation_quantity': quantity
            })
        
        # Simulate inventory update with performance tracking
        with xray_recorder.in_subsegment('inventory_update'):
            update_start_time = time.time()
            
            # Simulate update operation
            time.sleep(0.05)
            
            # Calculate new inventory levels
            if operation_type == 'reserve':
                new_available = current_inventory['available'] - quantity
                new_reserved = current_inventory['reserved'] + quantity
            elif operation_type == 'release':
                new_available = current_inventory['available'] + quantity
                new_reserved = max(0, current_inventory['reserved'] - quantity)
            else:  # check operation
                new_available = current_inventory['available']
                new_reserved = current_inventory['reserved']
            
            update_duration = time.time() - update_start_time
            
            xray_recorder.current_subsegment().put_annotation('update_duration_ms', int(update_duration * 1000))
            xray_recorder.current_subsegment().put_annotation('operation_type', operation_type)
            xray_recorder.put_annotation('inventory_updated', 'true')
            
            # Store update metadata
            xray_recorder.put_metadata('inventory_update', {
                'previous_available': current_inventory['available'],
                'previous_reserved': current_inventory['reserved'],
                'new_available': new_available,
                'new_reserved': new_reserved,
                'update_duration_ms': int(update_duration * 1000)
            })
        
        # Simulate audit logging
        with xray_recorder.in_subsegment('audit_logging'):
            log_audit_event(product_id, operation_type, quantity, {
                'previous': current_inventory,
                'new': {'available': new_available, 'reserved': new_reserved}
            })
        
        # Prepare response
        response_data = {
            'productId': product_id,
            'operation': operation_type,
            'status': 'completed',
            'inventory': {
                'available': new_available,
                'reserved': new_reserved,
                'total': new_available + new_reserved
            },
            'timestamp': datetime.utcnow().isoformat()
        }
        
        xray_recorder.put_annotation('response_status', 'success')
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps(response_data)
        }
        
    except ValueError as e:
        # Handle validation errors
        xray_recorder.put_annotation('error_type', 'validation')
        xray_recorder.put_annotation('error_message', str(e))
        
        return {
            'statusCode': 400,
            'headers': {
                'Content-Type': 'application/json'
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
                'Content-Type': 'application/json'
            },
            'body': json.dumps({
                'error': 'Internal Server Error',
                'message': 'An unexpected error occurred'
            })
        }

@xray_recorder.capture('get_current_inventory')
def get_current_inventory(product_id):
    """
    Simulate fetching current inventory levels from database.
    
    Args:
        product_id (str): Product identifier
        
    Returns:
        dict: Current inventory levels
    """
    # Simulate database query delay
    time.sleep(0.02)
    
    # Mock inventory data (in real implementation, this would query a database)
    mock_inventory = {
        'product-1': {'available': 100, 'reserved': 10},
        'product-2': {'available': 50, 'reserved': 5},
        'test-product': {'available': 75, 'reserved': 25}
    }
    
    inventory = mock_inventory.get(product_id, {'available': 100, 'reserved': 0})
    
    xray_recorder.put_annotation('inventory_product_id', product_id)
    xray_recorder.put_metadata('current_inventory', {
        'product_id': product_id,
        'available': inventory['available'],
        'reserved': inventory['reserved']
    })
    
    return inventory

@xray_recorder.capture('log_audit_event')
def log_audit_event(product_id, operation, quantity, inventory_change):
    """
    Simulate audit logging for inventory operations.
    
    Args:
        product_id (str): Product identifier
        operation (str): Type of operation performed
        quantity (int): Quantity affected
        inventory_change (dict): Before and after inventory levels
    """
    # Simulate audit log writing
    time.sleep(0.01)
    
    audit_data = {
        'timestamp': datetime.utcnow().isoformat(),
        'product_id': product_id,
        'operation': operation,
        'quantity': quantity,
        'inventory_change': inventory_change
    }
    
    xray_recorder.put_annotation('audit_logged', 'true')
    xray_recorder.put_metadata('audit_event', audit_data)
    
    # In a real implementation, this would write to CloudWatch Logs, S3, or a database
    print(f"AUDIT: {json.dumps(audit_data)}")