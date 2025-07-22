import json
import logging
from datetime import datetime
import boto3

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
eventbridge = boto3.client('events')

# Environment variables
EVENT_BUS_NAME = "${event_bus_name}"

def lambda_handler(event, context):
    """Process EventBridge events"""
    
    try:
        logger.info(f"Received event: {json.dumps(event, indent=2)}")
        
        # Extract event details
        event_source = event.get('source', 'unknown')
        event_type = event.get('detail-type', 'unknown')
        event_detail = event.get('detail', {})
        
        # Process based on event type
        result = process_event(event_source, event_type, event_detail)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Event processed successfully',
                'eventSource': event_source,
                'eventType': event_type,
                'result': result,
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def process_event(source, event_type, detail):
    """Process different types of events"""
    
    if source == 'ecommerce.orders':
        return process_order_event(event_type, detail)
    elif source == 'ecommerce.users':
        return process_user_event(event_type, detail)
    elif source == 'ecommerce.payments':
        return process_payment_event(event_type, detail)
    else:
        return process_generic_event(event_type, detail)

def process_order_event(event_type, detail):
    """Process order-related events"""
    
    if event_type == 'Order Created':
        order_id = detail.get('orderId')
        customer_id = detail.get('customerId')
        total_amount = detail.get('totalAmount', 0)
        
        logger.info(f"Processing new order: {order_id} for customer {customer_id}")
        
        # Business logic for order processing
        result = {
            'action': 'order_processed',
            'orderId': order_id,
            'customerId': customer_id,
            'totalAmount': total_amount,
            'priority': 'high' if total_amount > 1000 else 'normal'
        }
        
        # Example: Trigger additional business logic
        if total_amount > 1000:
            logger.info(f"High-value order detected: {order_id}")
            # Could trigger fraud detection, special handling, etc.
        
        return result
        
    elif event_type == 'Order Updated':
        order_id = detail.get('orderId')
        logger.info(f"Processing order update: {order_id}")
        
        return {
            'action': 'order_updated',
            'orderId': order_id,
            'updateType': detail.get('updateType', 'unknown')
        }
        
    elif event_type == 'Order Cancelled':
        order_id = detail.get('orderId')
        logger.info(f"Processing order cancellation: {order_id}")
        
        return {
            'action': 'order_cancelled',
            'orderId': order_id,
            'reason': detail.get('reason', 'not specified')
        }
    
    return {'action': 'order_event_processed'}

def process_user_event(event_type, detail):
    """Process user-related events"""
    
    if event_type == 'User Registered':
        user_id = detail.get('userId')
        email = detail.get('email')
        
        logger.info(f"Processing new user registration: {user_id}")
        
        # Business logic for user registration
        result = {
            'action': 'user_registered',
            'userId': user_id,
            'email': email,
            'welcomeEmailSent': True,
            'accountSetupRequired': True
        }
        
        # Example: Trigger welcome email, create user profile, etc.
        logger.info(f"User onboarding initiated for: {email}")
        
        return result
    
    elif event_type == 'User Updated':
        user_id = detail.get('userId')
        logger.info(f"Processing user profile update: {user_id}")
        
        return {
            'action': 'user_updated',
            'userId': user_id,
            'updateFields': detail.get('updateFields', [])
        }
    
    return {'action': 'user_event_processed'}

def process_payment_event(event_type, detail):
    """Process payment-related events"""
    
    if event_type == 'Payment Processed':
        payment_id = detail.get('paymentId')
        order_id = detail.get('orderId')
        amount = detail.get('amount')
        
        logger.info(f"Processing payment: {payment_id} for order {order_id}")
        
        # Business logic for payment processing
        result = {
            'action': 'payment_processed',
            'paymentId': payment_id,
            'orderId': order_id,
            'amount': amount,
            'receiptGenerated': True
        }
        
        # Example: Generate receipt, update order status, etc.
        logger.info(f"Payment confirmation sent for order: {order_id}")
        
        return result
    
    elif event_type == 'Payment Failed':
        payment_id = detail.get('paymentId')
        order_id = detail.get('orderId')
        reason = detail.get('reason', 'unknown')
        
        logger.warning(f"Payment failed: {payment_id} for order {order_id} - {reason}")
        
        return {
            'action': 'payment_failed',
            'paymentId': payment_id,
            'orderId': order_id,
            'reason': reason,
            'retryRequired': True
        }
    
    return {'action': 'payment_event_processed'}

def process_generic_event(event_type, detail):
    """Process generic events"""
    
    logger.info(f"Processing generic event: {event_type}")
    
    return {
        'action': 'generic_event_processed',
        'eventType': event_type,
        'detailKeys': list(detail.keys()) if detail else []
    }

def publish_downstream_event(source, detail_type, detail):
    """Helper function to publish downstream events"""
    
    try:
        response = eventbridge.put_events(
            Entries=[
                {
                    'Source': source,
                    'DetailType': detail_type,
                    'Detail': json.dumps(detail),
                    'EventBusName': EVENT_BUS_NAME
                }
            ]
        )
        
        logger.info(f"Published downstream event: {source} - {detail_type}")
        return response
        
    except Exception as e:
        logger.error(f"Failed to publish downstream event: {str(e)}")
        raise