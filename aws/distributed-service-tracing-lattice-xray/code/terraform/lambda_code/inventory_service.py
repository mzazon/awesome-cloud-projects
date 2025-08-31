"""
Inventory Service Lambda Function with X-Ray Distributed Tracing
Manages inventory checks with comprehensive observability
"""

import json
import time
import random
import uuid
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all

# Patch all AWS SDK calls for X-Ray tracing
patch_all()

@xray_recorder.capture('check_inventory')
def lambda_handler(event, context):
    """
    Check inventory availability with comprehensive tracing
    
    Args:
        event: Inventory request containing product_id, quantity, etc.
        context: Lambda context object
        
    Returns:
        dict: Inventory check result with availability status
    """
    try:
        # Extract inventory request information
        product_id = event.get('product_id', f'product-{uuid.uuid4().hex[:8]}')
        quantity = int(event.get('quantity', 1))
        order_id = event.get('order_id', 'unknown-order')
        
        # Add annotations for filtering and analysis
        xray_recorder.current_segment().put_annotation('product_id', product_id)
        xray_recorder.current_segment().put_annotation('quantity_requested', quantity)
        xray_recorder.current_segment().put_annotation('order_id', order_id)
        xray_recorder.current_segment().put_annotation('service_type', 'inventory-management')
        
        print(f"Checking inventory for product {product_id}, quantity {quantity} (order: {order_id})")
        
        # Simulate database lookup with realistic timing
        inventory_data = perform_inventory_lookup(product_id, quantity)
        
        # Determine availability
        availability_result = check_availability(product_id, quantity, inventory_data)
        
        # Add comprehensive metadata for debugging
        xray_recorder.current_segment().put_metadata('inventory_check', {
            'product_id': product_id,
            'requested_quantity': quantity,
            'order_id': order_id,
            'current_stock': inventory_data['current_stock'],
            'reserved_stock': inventory_data['reserved_stock'],
            'available_stock': inventory_data['available_stock'],
            'availability_result': availability_result,
            'timestamp': time.time()
        })
        
        # Set final status annotation
        xray_recorder.current_segment().put_annotation('inventory_status', availability_result['status'])
        xray_recorder.current_segment().put_annotation('available_stock', inventory_data['available_stock'])
        
        if availability_result['status'] == 'available':
            # Simulate inventory reservation
            reservation_result = reserve_inventory(product_id, quantity, order_id)
            
            response = {
                'statusCode': 200,
                'body': json.dumps({
                    'status': 'available',
                    'product_id': product_id,
                    'requested_quantity': quantity,
                    'available_stock': inventory_data['available_stock'],
                    'reserved_quantity': quantity,
                    'reservation_id': reservation_result['reservation_id'],
                    'order_id': order_id,
                    'warehouse_location': inventory_data.get('warehouse_location', 'main'),
                    'estimated_ship_date': availability_result.get('estimated_ship_date')
                })
            }
            
            print(f"Inventory available for product {product_id}: reserved {quantity} units")
            
        else:
            # Handle insufficient inventory
            xray_recorder.current_segment().put_annotation('insufficient_stock', True)
            
            response = {
                'statusCode': 409,  # Conflict status for insufficient inventory
                'body': json.dumps({
                    'status': 'insufficient_stock',
                    'product_id': product_id,
                    'requested_quantity': quantity,
                    'available_stock': inventory_data['available_stock'],
                    'shortage': quantity - inventory_data['available_stock'],
                    'order_id': order_id,
                    'estimated_restock_date': availability_result.get('estimated_restock_date'),
                    'alternative_products': availability_result.get('alternatives', [])
                })
            }
            
            print(f"Insufficient inventory for product {product_id}: need {quantity}, available {inventory_data['available_stock']}")
        
        return response
        
    except Exception as e:
        # Add exception to X-Ray trace
        xray_recorder.current_segment().add_exception(e)
        xray_recorder.current_segment().put_annotation('inventory_status', 'error')
        xray_recorder.current_segment().put_annotation('error_occurred', True)
        
        print(f"Inventory service error: {str(e)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'status': 'error',
                'error': 'Inventory service unavailable',
                'message': str(e),
                'product_id': event.get('product_id', 'unknown'),
                'order_id': event.get('order_id', 'unknown')
            })
        }

@xray_recorder.capture('perform_inventory_lookup')
def perform_inventory_lookup(product_id, requested_quantity):
    """
    Simulate database lookup for inventory information
    
    Args:
        product_id: Product identifier
        requested_quantity: Requested quantity
        
    Returns:
        dict: Inventory data including stock levels
    """
    # Add database lookup annotations
    xray_recorder.current_subsegment().put_annotation('database_operation', 'inventory_lookup')
    xray_recorder.current_subsegment().put_annotation('lookup_product_id', product_id)
    
    # Simulate varying database lookup times
    lookup_time = random.uniform(0.05, 0.3)
    time.sleep(lookup_time)
    
    xray_recorder.current_subsegment().put_annotation('db_lookup_time_ms', int(lookup_time * 1000))
    xray_recorder.current_subsegment().put_annotation('database_type', 'dynamodb')
    
    # Simulate inventory data with realistic business logic
    # Some products have higher stock levels than others
    base_stock = random.randint(0, 100)
    
    # Product categories affect stock levels
    if 'premium' in product_id.lower():
        base_stock = random.randint(5, 25)  # Premium products have lower stock
    elif 'bulk' in product_id.lower():
        base_stock = random.randint(50, 200)  # Bulk products have higher stock
    
    reserved_stock = random.randint(0, min(10, base_stock))
    available_stock = max(0, base_stock - reserved_stock)
    
    # Simulate warehouse information
    warehouses = ['main', 'west', 'east', 'central']
    warehouse_location = random.choice(warehouses)
    
    inventory_data = {
        'product_id': product_id,
        'current_stock': base_stock,
        'reserved_stock': reserved_stock,
        'available_stock': available_stock,
        'warehouse_location': warehouse_location,
        'last_updated': time.time(),
        'stock_unit': 'units'
    }
    
    xray_recorder.current_subsegment().put_metadata('inventory_lookup_result', inventory_data)
    
    print(f"Inventory lookup for {product_id}: {available_stock} available ({base_stock} total, {reserved_stock} reserved)")
    
    return inventory_data

@xray_recorder.capture('check_availability')
def check_availability(product_id, requested_quantity, inventory_data):
    """
    Check if requested quantity is available and provide business context
    
    Args:
        product_id: Product identifier
        requested_quantity: Requested quantity
        inventory_data: Current inventory information
        
    Returns:
        dict: Availability result with business context
    """
    available_stock = inventory_data['available_stock']
    
    xray_recorder.current_subsegment().put_annotation('availability_check', True)
    xray_recorder.current_subsegment().put_annotation('available_vs_requested', available_stock >= requested_quantity)
    
    if available_stock >= requested_quantity:
        # Calculate estimated ship date based on warehouse location
        warehouse_location = inventory_data.get('warehouse_location', 'main')
        ship_days = {'main': 1, 'west': 2, 'east': 2, 'central': 1}
        estimated_ship_days = ship_days.get(warehouse_location, 2)
        
        estimated_ship_date = time.time() + (estimated_ship_days * 24 * 60 * 60)
        
        result = {
            'status': 'available',
            'available_quantity': available_stock,
            'estimated_ship_date': estimated_ship_date,
            'warehouse_location': warehouse_location
        }
        
        xray_recorder.current_subsegment().put_annotation('inventory_sufficient', True)
        
    else:
        # Calculate shortage and estimated restock
        shortage = requested_quantity - available_stock
        estimated_restock_days = random.randint(3, 14)  # 3-14 days restock time
        estimated_restock_date = time.time() + (estimated_restock_days * 24 * 60 * 60)
        
        # Suggest alternative products (simulated)
        alternatives = generate_alternative_products(product_id)
        
        result = {
            'status': 'insufficient_stock',
            'available_quantity': available_stock,
            'shortage': shortage,
            'estimated_restock_date': estimated_restock_date,
            'alternatives': alternatives
        }
        
        xray_recorder.current_subsegment().put_annotation('inventory_sufficient', False)
        xray_recorder.current_subsegment().put_annotation('shortage_amount', shortage)
    
    xray_recorder.current_subsegment().put_metadata('availability_result', result)
    
    return result

@xray_recorder.capture('reserve_inventory')
def reserve_inventory(product_id, quantity, order_id):
    """
    Reserve inventory for the order (simulated)
    
    Args:
        product_id: Product identifier
        quantity: Quantity to reserve
        order_id: Order identifier
        
    Returns:
        dict: Reservation result
    """
    # Simulate reservation process
    reservation_time = random.uniform(0.02, 0.1)
    time.sleep(reservation_time)
    
    reservation_id = f'res_{order_id}_{product_id}_{int(time.time())}'
    
    xray_recorder.current_subsegment().put_annotation('reservation_created', True)
    xray_recorder.current_subsegment().put_annotation('reservation_id', reservation_id)
    xray_recorder.current_subsegment().put_annotation('reserved_quantity', quantity)
    
    reservation_result = {
        'reservation_id': reservation_id,
        'product_id': product_id,
        'quantity': quantity,
        'order_id': order_id,
        'reserved_at': time.time(),
        'expires_at': time.time() + (15 * 60)  # 15 minute reservation
    }
    
    xray_recorder.current_subsegment().put_metadata('inventory_reservation', reservation_result)
    
    print(f"Reserved {quantity} units of {product_id} for order {order_id}: {reservation_id}")
    
    return reservation_result

def generate_alternative_products(product_id):
    """
    Generate alternative product suggestions (simulated)
    
    Args:
        product_id: Original product identifier
        
    Returns:
        list: Alternative products
    """
    # Simulate alternative product logic
    base_id = product_id.split('-')[0] if '-' in product_id else product_id[:7]
    alternatives = []
    
    for i in range(random.randint(1, 3)):
        alt_id = f"{base_id}-alt-{i+1}"
        alternatives.append({
            'product_id': alt_id,
            'available_stock': random.randint(1, 50),
            'price_difference': round(random.uniform(-10, 20), 2)
        })
    
    return alternatives

def health_check():
    """Simple health check for load balancer"""
    return {
        'statusCode': 200,
        'body': json.dumps({
            'status': 'healthy',
            'service': 'inventory-service',
            'timestamp': time.time(),
            'warehouse_count': 4,
            'database_status': 'connected'
        })
    }