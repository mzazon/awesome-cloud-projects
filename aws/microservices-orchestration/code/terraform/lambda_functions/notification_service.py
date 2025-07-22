"""
Notification Service Lambda Function
Handles customer communications and system alerts with multi-channel support
"""
import json
import logging
from datetime import datetime
from typing import Dict, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for Notification Service
    Processes notification requests and handles customer communications
    
    Args:
        event: Lambda event containing notification data
        context: Lambda context object
        
    Returns:
        Dict containing status code and response body
    """
    try:
        logger.info(f"Received notification event: {json.dumps(event)}")
        
        # Parse notification data from various sources
        notification_data = None
        
        if 'detail' in event:
            # From EventBridge
            notification_data = event['detail']
            source = "EventBridge"
        elif 'Payload' in event:
            # From Step Functions
            notification_data = event['Payload']
            source = "Step Functions"
        else:
            # Direct invocation or API Gateway
            if 'body' in event:
                notification_data = json.loads(event['body'])
            else:
                notification_data = event
            source = "Direct"
        
        # Extract notification details
        message = notification_data.get('message', 'Notification')
        order_id = notification_data.get('orderId', 'Unknown')
        customer_id = notification_data.get('customerId', 'Unknown')
        status = notification_data.get('status', 'INFO')
        notification_type = notification_data.get('type', 'ORDER_UPDATE')
        
        # Get current timestamp
        current_time = datetime.utcnow().isoformat()
        
        # Format notification based on type and status
        formatted_notification = format_notification(
            notification_type=notification_type,
            status=status,
            order_id=order_id,
            customer_id=customer_id,
            message=message,
            timestamp=current_time
        )
        
        # Log the notification (in production, this would send to external services)
        logger.info(f"NOTIFICATION SENT: {json.dumps(formatted_notification, indent=2)}")
        
        # Simulate different notification channels based on status
        channels_used = send_notification(formatted_notification, status)
        
        # Prepare response
        response_body = {
            'notificationId': f"notif_{order_id[:8]}_{int(datetime.utcnow().timestamp())}",
            'status': 'SENT',
            'channels': channels_used,
            'recipient': customer_id,
            'orderId': order_id,
            'message': message,
            'sentAt': current_time
        }
        
        response = {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps(response_body)
        }
        
        logger.info(f"Notification sent successfully for order {order_id}")
        return response
        
    except json.JSONDecodeError as e:
        logger.error(f"JSON decode error in notification service: {str(e)}")
        return {
            'statusCode': 400,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'error': 'Invalid JSON format',
                'message': str(e)
            })
        }
        
    except Exception as e:
        logger.error(f"Error in notification service: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'error': 'Notification service error',
                'message': str(e)
            })
        }

def format_notification(notification_type: str, status: str, order_id: str, 
                       customer_id: str, message: str, timestamp: str) -> Dict[str, Any]:
    """
    Format notification based on type and status
    
    Args:
        notification_type: Type of notification
        status: Order/payment status
        order_id: Order identifier
        customer_id: Customer identifier
        message: Notification message
        timestamp: Current timestamp
        
    Returns:
        Formatted notification dictionary
    """
    
    notification_templates = {
        'ORDER_CREATED': {
            'subject': f'Order Confirmation - {order_id}',
            'body': f'Thank you for your order! Your order {order_id} has been received and is being processed.',
            'priority': 'NORMAL'
        },
        'PAYMENT_SUCCESS': {
            'subject': f'Payment Confirmed - {order_id}',
            'body': f'Your payment for order {order_id} has been processed successfully.',
            'priority': 'NORMAL'
        },
        'PAYMENT_FAILED': {
            'subject': f'Payment Issue - {order_id}',
            'body': f'We encountered an issue processing payment for order {order_id}. Please update your payment method.',
            'priority': 'HIGH'
        },
        'INVENTORY_RESERVED': {
            'subject': f'Items Reserved - {order_id}',
            'body': f'All items in your order {order_id} have been reserved and will be shipped soon.',
            'priority': 'NORMAL'
        },
        'INVENTORY_UNAVAILABLE': {
            'subject': f'Items Unavailable - {order_id}',
            'body': f'Some items in your order {order_id} are currently unavailable. We will notify you when they are back in stock.',
            'priority': 'HIGH'
        },
        'ORDER_COMPLETED': {
            'subject': f'Order Complete - {order_id}',
            'body': f'Great news! Your order {order_id} has been completed and is ready for shipment.',
            'priority': 'NORMAL'
        },
        'ORDER_FAILED': {
            'subject': f'Order Processing Issue - {order_id}',
            'body': f'We encountered an issue processing your order {order_id}. Our team has been notified and will contact you shortly.',
            'priority': 'URGENT'
        }
    }
    
    # Determine notification type based on status if not provided
    if notification_type == 'ORDER_UPDATE':
        status_mapping = {
            'COMPLETED': 'ORDER_COMPLETED',
            'PAYMENT_FAILED': 'PAYMENT_FAILED',
            'INVENTORY_FAILED': 'INVENTORY_UNAVAILABLE',
            'SUCCESS': 'PAYMENT_SUCCESS',
            'RESERVED': 'INVENTORY_RESERVED',
            'PENDING': 'ORDER_CREATED'
        }
        notification_type = status_mapping.get(status, 'ORDER_UPDATE')
    
    # Get template or use default
    template = notification_templates.get(notification_type, {
        'subject': f'Order Update - {order_id}',
        'body': message,
        'priority': 'NORMAL'
    })
    
    return {
        'notificationType': notification_type,
        'orderId': order_id,
        'customerId': customer_id,
        'subject': template['subject'],
        'body': template['body'],
        'priority': template['priority'],
        'status': status,
        'timestamp': timestamp,
        'metadata': {
            'originalMessage': message,
            'processingSource': 'notification-service'
        }
    }

def send_notification(notification: Dict[str, Any], status: str) -> list:
    """
    Simulate sending notification through different channels
    
    Args:
        notification: Formatted notification data
        status: Order status
        
    Returns:
        List of channels used for notification
    """
    channels = []
    priority = notification.get('priority', 'NORMAL')
    
    # Always use email for notifications
    channels.append('EMAIL')
    logger.info(f"EMAIL notification sent: {notification['subject']}")
    
    # Use SMS for high priority notifications
    if priority in ['HIGH', 'URGENT']:
        channels.append('SMS')
        logger.info(f"SMS notification sent: Order {notification['orderId']} - {status}")
    
    # Use push notifications for urgent issues
    if priority == 'URGENT':
        channels.append('PUSH')
        logger.info(f"PUSH notification sent: {notification['subject']}")
    
    # Use webhook for order completion
    if status in ['COMPLETED', 'SUCCESS']:
        channels.append('WEBHOOK')
        logger.info(f"WEBHOOK notification sent for order completion: {notification['orderId']}")
    
    return channels