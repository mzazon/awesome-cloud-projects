"""
Inventory Service Lambda Function
Manages inventory updates triggered by order creation events
Implements X-Ray tracing for comprehensive distributed system observability
"""

import json
import boto3
import os
import random
from datetime import datetime
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all

# Patch AWS SDK calls for automatic X-Ray tracing
patch_all()

# Initialize AWS clients with X-Ray tracing
eventbridge = boto3.client('events')

# Simulated inventory data for demonstration
WAREHOUSE_INVENTORY = {
    'east-coast': {'capacity': 1000, 'current_stock': 750},
    'west-coast': {'capacity': 800, 'current_stock': 600},
    'midwest': {'capacity': 1200, 'current_stock': 900}
}

@xray_recorder.capture('inventory_service_handler')
def lambda_handler(event, context):
    """
    Main Lambda handler for inventory service
    Processes EventBridge events for inventory management
    """
    
    # Process each EventBridge event record
    for record in event.get('Records', []):
        # Create subsegment for inventory processing
        subsegment = xray_recorder.begin_subsegment('update_inventory')
        
        try:
            # Parse EventBridge event detail
            if 'body' in record:
                # EventBridge event wrapped in SQS format
                event_body = json.loads(record['body'])
                detail = event_body.get('detail', {})
                detail_type = event_body.get('detail-type', '')
                source = event_body.get('source', '')
            else:
                # Direct EventBridge event
                detail = record.get('detail', {})
                detail_type = record.get('detail-type', '')
                source = record.get('source', '')
            
            # Extract order information
            order_id = detail.get('orderId', '')
            customer_id = detail.get('customerId', '')
            product_id = detail.get('productId', 'default-product')
            quantity = detail.get('quantity', 1)
            trace_id = detail.get('traceId', '')
            
            # Select optimal warehouse based on inventory levels
            selected_warehouse = select_optimal_warehouse(quantity)
            
            # Check inventory availability
            inventory_status = check_inventory_availability(
                selected_warehouse, product_id, quantity
            )
            
            # Add comprehensive metadata to X-Ray trace
            subsegment.put_metadata('inventory_processing', {
                'order_id': order_id,
                'customer_id': customer_id,
                'product_id': product_id,
                'quantity': quantity,
                'selected_warehouse': selected_warehouse,
                'inventory_status': inventory_status,
                'event_source': source,
                'event_detail_type': detail_type,
                'timestamp': datetime.now().isoformat(),
                'request_id': context.aws_request_id
            })
            
            # Add annotations for filtering and searching traces
            xray_recorder.put_annotation('order_id', order_id)
            xray_recorder.put_annotation('customer_id', customer_id)
            xray_recorder.put_annotation('service_name', 'inventory-service')
            xray_recorder.put_annotation('product_id', product_id)
            xray_recorder.put_annotation('warehouse', selected_warehouse)
            xray_recorder.put_annotation('inventory_available', inventory_status['available'])
            
            # Generate reservation ID
            reservation_id = f"res-{order_id}-{int(datetime.now().timestamp())}"
            
            # Process inventory reservation
            if inventory_status['available']:
                # Reserve inventory
                reservation_result = reserve_inventory(
                    selected_warehouse, product_id, quantity, reservation_id
                )
                
                # Add reservation metadata
                subsegment.put_metadata('inventory_reservation', {
                    'reservation_id': reservation_id,
                    'reserved_quantity': quantity,
                    'warehouse_remaining': reservation_result['remaining_stock'],
                    'reservation_timestamp': datetime.now().isoformat()
                })
                
                # Create inventory updated event
                inventory_event_detail = {
                    'orderId': order_id,
                    'customerId': customer_id,
                    'productId': product_id,
                    'reservationId': reservation_id,
                    'quantity': quantity,
                    'warehouse': selected_warehouse,
                    'status': 'reserved',
                    'remainingStock': reservation_result['remaining_stock'],
                    'timestamp': datetime.now().isoformat(),
                    'traceId': trace_id
                }
                
                event_detail_type = 'Inventory Updated'
                xray_recorder.put_annotation('inventory_reserved', True)
                
            else:
                # Handle insufficient inventory
                inventory_event_detail = {
                    'orderId': order_id,
                    'customerId': customer_id,
                    'productId': product_id,
                    'quantity': quantity,
                    'warehouse': selected_warehouse,
                    'status': 'insufficient_stock',
                    'availableQuantity': inventory_status['available_quantity'],
                    'timestamp': datetime.now().isoformat(),
                    'traceId': trace_id
                }
                
                event_detail_type = 'Inventory Insufficient'
                xray_recorder.put_annotation('inventory_insufficient', True)
                
                # Add backorder information
                subsegment.put_metadata('backorder_info', {
                    'requested_quantity': quantity,
                    'available_quantity': inventory_status['available_quantity'],
                    'shortfall': quantity - inventory_status['available_quantity']
                })
            
            # Publish inventory event to EventBridge
            event_response = eventbridge.put_events(
                Entries=[
                    {
                        'Source': 'inventory.service',
                        'DetailType': event_detail_type,
                        'Detail': json.dumps(inventory_event_detail),
                        'EventBusName': '${event_bus_name}'
                    }
                ]
            )
            
            # Add EventBridge response metadata
            subsegment.put_metadata('eventbridge_response', {
                'entries_count': len(event_response.get('Entries', [])),
                'failed_entry_count': event_response.get('FailedEntryCount', 0)
            })
            
            # Check for EventBridge publish failures
            if event_response.get('FailedEntryCount', 0) > 0:
                xray_recorder.put_annotation('eventbridge_failures', event_response.get('FailedEntryCount'))
                failed_entries = event_response.get('Entries', [])
                subsegment.put_metadata('failed_entries', failed_entries)
            
            print(f"Inventory processed for order {order_id}: {inventory_status['available']}")
            
        except json.JSONDecodeError as e:
            # Handle JSON parsing errors
            error_message = f"Invalid JSON in event: {str(e)}"
            xray_recorder.put_annotation('error', error_message)
            xray_recorder.put_annotation('error_type', 'JSONDecodeError')
            
            subsegment.put_metadata('error_details', {
                'error_message': error_message,
                'error_type': 'JSONDecodeError',
                'raw_record': str(record)[:500]  # Limit size
            })
            
            print(f"JSON decode error: {error_message}")
            
        except Exception as e:
            # Handle other processing errors
            error_message = str(e)
            xray_recorder.put_annotation('error', error_message)
            xray_recorder.put_annotation('error_type', type(e).__name__)
            
            subsegment.put_metadata('error_details', {
                'error_message': error_message,
                'error_type': type(e).__name__,
                'request_id': context.aws_request_id
            })
            
            print(f"Inventory processing error: {error_message}")
            
        finally:
            # Always end the subsegment
            xray_recorder.end_subsegment()
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Inventory events processed successfully',
            'processedCount': len(event.get('Records', [])),
            'timestamp': datetime.now().isoformat()
        })
    }


def select_optimal_warehouse(quantity):
    """
    Select the optimal warehouse based on inventory levels and capacity
    """
    best_warehouse = 'east-coast'  # Default
    best_score = 0
    
    for warehouse, info in WAREHOUSE_INVENTORY.items():
        # Calculate warehouse score based on available capacity
        available_capacity = info['current_stock']
        capacity_ratio = available_capacity / info['capacity']
        
        # Prefer warehouses with sufficient stock and good capacity ratio
        if available_capacity >= quantity:
            score = capacity_ratio * 100 + random.uniform(0, 10)  # Add randomness
            if score > best_score:
                best_score = score
                best_warehouse = warehouse
    
    return best_warehouse


def check_inventory_availability(warehouse, product_id, quantity):
    """
    Check if sufficient inventory is available at the specified warehouse
    """
    warehouse_info = WAREHOUSE_INVENTORY.get(warehouse, {'current_stock': 0})
    available_stock = warehouse_info['current_stock']
    
    # Simulate product-specific inventory (for demo purposes, assume all products available)
    available_quantity = min(available_stock, max(0, available_stock - random.randint(0, 50)))
    
    return {
        'available': available_quantity >= quantity,
        'available_quantity': available_quantity,
        'warehouse_total_stock': available_stock
    }


def reserve_inventory(warehouse, product_id, quantity, reservation_id):
    """
    Reserve inventory at the specified warehouse
    """
    # In a real implementation, this would update a database
    # For demo purposes, we'll simulate the reservation
    
    warehouse_info = WAREHOUSE_INVENTORY.get(warehouse, {'current_stock': 0})
    current_stock = warehouse_info['current_stock']
    
    # Update inventory (simulation)
    new_stock = max(0, current_stock - quantity)
    WAREHOUSE_INVENTORY[warehouse]['current_stock'] = new_stock
    
    return {
        'reservation_id': reservation_id,
        'reserved_quantity': quantity,
        'remaining_stock': new_stock,
        'success': True
    }