"""
Inventory Service Lambda Function
Manages product availability and reservation logic with event-driven patterns
"""
import json
import boto3
import random
import logging
from datetime import datetime
from typing import Dict, Any, List

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
eventbridge = boto3.client('events')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for Inventory Service
    Handles inventory checks, reservations, and publishes inventory events
    
    Args:
        event: Lambda event containing inventory data
        context: Lambda context object
        
    Returns:
        Dict containing status code and response body
    """
    try:
        logger.info(f"Received inventory event: {json.dumps(event)}")
        
        # Parse inventory data from Step Functions or direct invocation
        if 'detail' in event:
            # From EventBridge/Step Functions
            inventory_data = event['detail']
        elif 'Payload' in event and 'detail' in event['Payload']:
            # From Step Functions with Payload wrapper
            inventory_data = event['Payload']['detail']
        else:
            # Direct invocation
            inventory_data = event
        
        # Extract required fields
        order_id = inventory_data.get('orderId')
        customer_id = inventory_data.get('customerId')
        items = inventory_data.get('items', [])
        
        if not all([order_id, customer_id, items]):
            raise ValueError("Missing required inventory data: orderId, customerId, or items")
        
        logger.info(f"Processing inventory for order {order_id}, customer {customer_id}")
        
        # Validate items structure
        if not isinstance(items, list) or len(items) == 0:
            raise ValueError("Items must be a non-empty list")
        
        # Simulate inventory availability check
        inventory_details = []
        total_items = 0
        
        for item in items:
            product_id = item.get('productId')
            quantity = item.get('quantity', 0)
            
            if not product_id or quantity <= 0:
                raise ValueError(f"Invalid item data: {item}")
            
            total_items += quantity
            
            # Simulate individual item availability (95% success rate per item)
            item_available = random.random() < 0.95
            
            inventory_details.append({
                'productId': product_id,
                'requestedQuantity': quantity,
                'available': item_available,
                'reservedQuantity': quantity if item_available else 0
            })
        
        # Determine overall inventory availability
        inventory_available = all(item['available'] for item in inventory_details)
        
        # Calculate processing delay based on number of items (1-4 seconds)
        processing_delay = min(1 + (total_items * 0.1), 4)
        import time
        time.sleep(processing_delay)
        
        # Get current timestamp
        current_time = datetime.utcnow().isoformat()
        
        # Update order status in DynamoDB
        table = dynamodb.Table('${dynamodb_table_name}')
        
        if inventory_available:
            # Reserve inventory - update order status
            table.update_item(
                Key={
                    'orderId': order_id,
                    'customerId': customer_id
                },
                UpdateExpression='SET #status = :status, updatedAt = :updatedAt, inventoryDetails = :details',
                ExpressionAttributeNames={
                    '#status': 'status'
                },
                ExpressionAttributeValues={
                    ':status': 'INVENTORY_RESERVED',
                    ':updatedAt': current_time,
                    ':details': inventory_details
                }
            )
            
            # Publish inventory reserved event
            event_detail = {
                'orderId': order_id,
                'customerId': customer_id,
                'items': items,
                'inventoryDetails': inventory_details,
                'status': 'RESERVED',
                'reservedAt': current_time
            }
            
            eventbridge.put_events(
                Entries=[
                    {
                        'Source': 'inventory.service',
                        'DetailType': 'Inventory Reserved',
                        'Detail': json.dumps(event_detail),
                        'EventBusName': '${eventbus_name}'
                    }
                ]
            )
            
            logger.info(f"Inventory reserved successfully for order {order_id}")
            
            response_body = {
                'orderId': order_id,
                'inventoryStatus': 'RESERVED',
                'inventoryDetails': inventory_details,
                'totalItemsReserved': total_items,
                'reservedAt': current_time
            }
            
        else:
            # Inventory unavailable - update order status
            unavailable_items = [
                item for item in inventory_details if not item['available']
            ]
            
            table.update_item(
                Key={
                    'orderId': order_id,
                    'customerId': customer_id
                },
                UpdateExpression='SET #status = :status, updatedAt = :updatedAt, inventoryDetails = :details',
                ExpressionAttributeNames={
                    '#status': 'status'
                },
                ExpressionAttributeValues={
                    ':status': 'INVENTORY_UNAVAILABLE',
                    ':updatedAt': current_time,
                    ':details': inventory_details
                }
            )
            
            # Publish inventory unavailable event
            event_detail = {
                'orderId': order_id,
                'customerId': customer_id,
                'items': items,
                'inventoryDetails': inventory_details,
                'unavailableItems': unavailable_items,
                'status': 'UNAVAILABLE',
                'checkedAt': current_time
            }
            
            eventbridge.put_events(
                Entries=[
                    {
                        'Source': 'inventory.service',
                        'DetailType': 'Inventory Unavailable',
                        'Detail': json.dumps(event_detail),
                        'EventBusName': '${eventbus_name}'
                    }
                ]
            )
            
            logger.warning(f"Inventory unavailable for order {order_id}")
            
            response_body = {
                'orderId': order_id,
                'inventoryStatus': 'UNAVAILABLE',
                'inventoryDetails': inventory_details,
                'unavailableItems': unavailable_items,
                'checkedAt': current_time
            }
        
        # Return response
        response = {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps(response_body)
        }
        
        logger.info(f"Inventory service completed for order {order_id}")
        return response
        
    except Exception as e:
        logger.error(f"Error processing inventory: {str(e)}")
        
        # Try to update order status to inventory error if we have the order info
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
                        ':status': 'INVENTORY_ERROR',
                        ':updatedAt': datetime.utcnow().isoformat(),
                        ':reason': f'Inventory service error: {str(e)}'
                    }
                )
        except:
            logger.error("Failed to update order status after inventory error")
        
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'error': 'Inventory processing error',
                'message': str(e)
            })
        }