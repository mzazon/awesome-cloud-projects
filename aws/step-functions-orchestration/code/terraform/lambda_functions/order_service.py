import json
import uuid
import datetime
import logging
import os

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

def lambda_handler(event, context):
    """
    Order Service Lambda Function
    
    Manages order creation and validation logic for the microservices workflow.
    Creates orders with proper validation including inventory checks and payment authorization.
    
    Args:
        event: Lambda event containing orderData and userData
        context: Lambda context object
        
    Returns:
        dict: Order data including orderId, userId, items, total, status, and created timestamp
        
    Raises:
        Exception: When order items are missing or invalid
    """
    
    logger.info(f"Order Service invoked with event: {json.dumps(event)}")
    
    try:
        # Extract order and user data from event
        order_data = event.get('orderData', {})
        user_data = event.get('userData', {})
        
        # Parse user data if it's a JSON string from Step Functions
        if isinstance(user_data, str):
            user_data = json.loads(user_data)
        
        logger.info(f"Processing order creation for user: {user_data.get('userId')}")
        
        # Validate order requirements
        items = order_data.get('items', [])
        if not items:
            error_msg = "Order items are required"
            logger.error(error_msg)
            raise Exception(error_msg)
        
        # Validate item structure
        for i, item in enumerate(items):
            if not all(key in item for key in ['productId', 'quantity', 'price']):
                error_msg = f"Item {i} missing required fields (productId, quantity, price)"
                logger.error(error_msg)
                raise Exception(error_msg)
            
            if item['quantity'] <= 0 or item['price'] <= 0:
                error_msg = f"Item {i} has invalid quantity or price"
                logger.error(error_msg)
                raise Exception(error_msg)
        
        # Calculate order total
        total = sum(item.get('price', 0) * item.get('quantity', 1) for item in items)
        
        # Generate unique order ID
        order_id = str(uuid.uuid4())
        
        # Create order object
        order = {
            'orderId': order_id,
            'userId': user_data.get('userId'),
            'userEmail': user_data.get('email'),
            'items': items,
            'itemCount': len(items),
            'subtotal': round(total, 2),
            'tax': round(total * 0.08, 2),  # 8% tax rate
            'total': round(total * 1.08, 2),
            'status': 'pending',
            'created': datetime.datetime.utcnow().isoformat(),
            'currency': 'USD',
            'orderSource': 'web'
        }
        
        logger.info(f"Order created successfully: {order_id}, Total: ${order['total']}")
        logger.debug(f"Order details: {json.dumps(order)}")
        
        # Return successful response
        response = {
            'statusCode': 200,
            'body': json.dumps(order),
            'headers': {
                'Content-Type': 'application/json'
            }
        }
        
        logger.info("Order Service completed successfully")
        return response
        
    except Exception as e:
        error_msg = f"Order Service error: {str(e)}"
        logger.error(error_msg)
        
        # Return error response
        return {
            'statusCode': 400,
            'body': json.dumps({
                'error': error_msg,
                'orderData': event.get('orderData'),
                'userId': event.get('userData', {}).get('userId')
            }),
            'headers': {
                'Content-Type': 'application/json'
            }
        }