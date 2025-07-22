import json
import random
import datetime
import logging
import os

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

def lambda_handler(event, context):
    """
    Inventory Service Lambda Function
    
    Manages stock levels and reservation logic for the microservices workflow.
    Validates inventory availability and reserves items for orders.
    
    Args:
        event: Lambda event containing orderData
        context: Lambda context object
        
    Returns:
        dict: Inventory result including reservations and status
        
    Raises:
        Exception: When insufficient inventory is available
    """
    
    logger.info(f"Inventory Service invoked with event: {json.dumps(event)}")
    
    try:
        # Extract order data from event
        order_data = event.get('orderData', {})
        
        # Parse order data if it's a JSON string from Step Functions
        if isinstance(order_data, str):
            order_data = json.loads(order_data)
        
        items = order_data.get('items', [])
        
        if not items:
            error_msg = "No items provided for inventory check"
            logger.error(error_msg)
            raise Exception(error_msg)
        
        logger.info(f"Processing inventory check for {len(items)} items")
        
        inventory_results = []
        total_reserved_value = 0
        
        # Mock inventory database - In production, this would query an inventory system
        inventory_db = {
            'PROD001': {'available': 50, 'name': 'Premium Widget', 'category': 'electronics'},
            'PROD002': {'available': 25, 'name': 'Standard Widget', 'category': 'electronics'},
            'PROD003': {'available': 100, 'name': 'Basic Widget', 'category': 'electronics'},
            'PROD004': {'available': 10, 'name': 'Premium Gadget', 'category': 'gadgets'},
            'PROD005': {'available': 0, 'name': 'Out of Stock Item', 'category': 'gadgets'}
        }
        
        for item in items:
            product_id = item.get('productId')
            requested_qty = item.get('quantity', 1)
            item_price = item.get('price', 0)
            
            logger.debug(f"Checking inventory for product {product_id}, quantity {requested_qty}")
            
            # Check if product exists in inventory
            if product_id not in inventory_db:
                # For unknown products, simulate random availability
                available_qty = random.randint(0, 20)
                product_name = f"Product {product_id}"
                category = "unknown"
            else:
                available_qty = inventory_db[product_id]['available']
                product_name = inventory_db[product_id]['name']
                category = inventory_db[product_id]['category']
            
            # Add some randomness to simulate real-world inventory fluctuations
            if available_qty > 0:
                available_qty += random.randint(-2, 5)
                available_qty = max(0, available_qty)  # Ensure non-negative
            
            if available_qty >= requested_qty:
                # Reserve the items
                reservation_id = f"RES_{random.randint(100000, 999999)}"
                reservation = {
                    'productId': product_id,
                    'productName': product_name,
                    'category': category,
                    'requestedQuantity': requested_qty,
                    'reservedQuantity': requested_qty,
                    'availableQuantity': available_qty,
                    'remainingQuantity': available_qty - requested_qty,
                    'reservationId': reservation_id,
                    'unitPrice': item_price,
                    'totalValue': round(item_price * requested_qty, 2),
                    'status': 'reserved',
                    'reservedAt': datetime.datetime.utcnow().isoformat(),
                    'expiresAt': (datetime.datetime.utcnow() + datetime.timedelta(minutes=30)).isoformat()
                }
                
                inventory_results.append(reservation)
                total_reserved_value += reservation['totalValue']
                
                logger.info(f"Reserved {requested_qty} units of {product_id} (Reservation ID: {reservation_id})")
                
            else:
                error_msg = f"Insufficient inventory for product {product_id}: requested {requested_qty}, available {available_qty}"
                logger.error(error_msg)
                raise Exception(error_msg)
        
        # Create final inventory response
        inventory_response = {
            'reservations': inventory_results,
            'status': 'confirmed',
            'totalItems': len(inventory_results),
            'totalReservedValue': round(total_reserved_value, 2),
            'reservationSummary': {
                'electronics': len([r for r in inventory_results if r['category'] == 'electronics']),
                'gadgets': len([r for r in inventory_results if r['category'] == 'gadgets']),
                'unknown': len([r for r in inventory_results if r['category'] == 'unknown'])
            },
            'processedAt': datetime.datetime.utcnow().isoformat(),
            'reservationExpiryMinutes': 30
        }
        
        logger.info(f"Inventory check completed successfully: {len(inventory_results)} items reserved, total value: ${total_reserved_value}")
        logger.debug(f"Inventory response: {json.dumps(inventory_response)}")
        
        # Return successful response
        response = {
            'statusCode': 200,
            'body': json.dumps(inventory_response),
            'headers': {
                'Content-Type': 'application/json'
            }
        }
        
        logger.info("Inventory Service completed successfully")
        return response
        
    except Exception as e:
        error_msg = f"Inventory Service error: {str(e)}"
        logger.error(error_msg)
        
        # Return error response
        return {
            'statusCode': 400,
            'body': json.dumps({
                'error': error_msg,
                'orderData': event.get('orderData'),
                'failedAt': datetime.datetime.utcnow().isoformat(),
                'status': 'failed'
            }),
            'headers': {
                'Content-Type': 'application/json'
            }
        }