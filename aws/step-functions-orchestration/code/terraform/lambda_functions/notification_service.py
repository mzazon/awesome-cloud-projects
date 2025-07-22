import json
import datetime
import logging
import os
import random

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

def lambda_handler(event, context):
    """
    Notification Service Lambda Function
    
    Handles customer communications and order confirmations for the microservices workflow.
    Sends notifications after successful order processing and payment confirmation.
    
    Args:
        event: Lambda event containing userData, orderData, and paymentData
        context: Lambda context object
        
    Returns:
        dict: Notification result including delivery status and details
        
    Raises:
        Exception: When notification sending fails
    """
    
    logger.info(f"Notification Service invoked with event: {json.dumps(event)}")
    
    try:
        # Extract data from Step Functions parallel execution results
        user_data = event.get('userData', {})
        order_data = event.get('orderData', {})
        payment_data = event.get('paymentData', {})
        
        # Parse data if it's JSON strings from Step Functions
        if isinstance(user_data, str):
            user_data = json.loads(user_data)
        if isinstance(order_data, str):
            order_data = json.loads(order_data)
        if isinstance(payment_data, str):
            payment_data = json.loads(payment_data)
        
        # Extract key information
        user_email = user_data.get('email')
        user_id = user_data.get('userId')
        order_id = order_data.get('orderId')
        order_total = order_data.get('total', 0)
        transaction_id = payment_data.get('transactionId')
        payment_method = payment_data.get('method', 'credit_card')
        
        logger.info(f"Sending notification for order {order_id} to user {user_id} at {user_email}")
        
        # Validate required data
        if not user_email:
            error_msg = "User email is required for notification"
            logger.error(error_msg)
            raise Exception(error_msg)
        
        if not order_id:
            error_msg = "Order ID is required for notification"
            logger.error(error_msg)
            raise Exception(error_msg)
        
        # Create order summary for notification
        items_summary = []
        order_items = order_data.get('items', [])
        
        for item in order_items:
            items_summary.append({
                'productId': item.get('productId'),
                'quantity': item.get('quantity'),
                'price': item.get('price'),
                'subtotal': round(item.get('price', 0) * item.get('quantity', 1), 2)
            })
        
        # Generate notification content
        notification_content = {
            'subject': f"Order Confirmation #{order_id}",
            'message': f"""
Dear Customer,

Thank you for your order! Your purchase has been confirmed and is being processed.

Order Details:
- Order ID: {order_id}
- Total Amount: ${order_total}
- Payment Method: {payment_method.replace('_', ' ').title()}
- Transaction ID: {transaction_id}
- Order Date: {order_data.get('created', datetime.datetime.utcnow().isoformat())}

Items Ordered:
{chr(10).join([f"- {item['productId']}: Qty {item['quantity']} @ ${item['price']} each" for item in items_summary])}

Your order will be processed within 1-2 business days. You will receive a shipping confirmation once your items are dispatched.

Thank you for choosing us!

Best regards,
The E-Commerce Team
            """.strip(),
            'html_content': f"""
<html>
<body>
    <h2>Order Confirmation</h2>
    <p>Dear Customer,</p>
    <p>Thank you for your order! Your purchase has been confirmed and is being processed.</p>
    
    <h3>Order Details</h3>
    <ul>
        <li><strong>Order ID:</strong> {order_id}</li>
        <li><strong>Total Amount:</strong> ${order_total}</li>
        <li><strong>Payment Method:</strong> {payment_method.replace('_', ' ').title()}</li>
        <li><strong>Transaction ID:</strong> {transaction_id}</li>
        <li><strong>Order Date:</strong> {order_data.get('created', datetime.datetime.utcnow().isoformat())}</li>
    </ul>
    
    <h3>Items Ordered</h3>
    <ul>
        {''.join([f"<li>{item['productId']}: Qty {item['quantity']} @ ${item['price']} each</li>" for item in items_summary])}
    </ul>
    
    <p>Your order will be processed within 1-2 business days. You will receive a shipping confirmation once your items are dispatched.</p>
    
    <p>Thank you for choosing us!</p>
    
    <p>Best regards,<br>The E-Commerce Team</p>
</body>
</html>
            """
        }
        
        # Simulate notification delivery channels
        delivery_channels = []
        
        # Email notification (primary)
        email_delivery = {
            'channel': 'email',
            'to': user_email,
            'status': 'sent',
            'deliveryId': f"email_{random.randint(100000, 999999)}",
            'sentAt': datetime.datetime.utcnow().isoformat()
        }
        delivery_channels.append(email_delivery)
        
        # SMS notification (if enabled)
        user_phone = user_data.get('phone')
        if user_phone:
            sms_delivery = {
                'channel': 'sms',
                'to': user_phone,
                'message': f"Order #{order_id} confirmed! Total: ${order_total}. Transaction: {transaction_id}",
                'status': 'sent',
                'deliveryId': f"sms_{random.randint(100000, 999999)}",
                'sentAt': datetime.datetime.utcnow().isoformat()
            }
            delivery_channels.append(sms_delivery)
        
        # Push notification (if mobile app user)
        if user_data.get('mobileApp', False):
            push_delivery = {
                'channel': 'push',
                'deviceId': user_data.get('deviceId', 'unknown'),
                'message': f"Order confirmed! #{order_id} - ${order_total}",
                'status': 'sent',
                'deliveryId': f"push_{random.randint(100000, 999999)}",
                'sentAt': datetime.datetime.utcnow().isoformat()
            }
            delivery_channels.append(push_delivery)
        
        # Create comprehensive notification response
        notification_response = {
            'notificationId': f"notif_{random.randint(100000, 999999)}",
            'orderId': order_id,
            'userId': user_id,
            'subject': notification_content['subject'],
            'deliveryChannels': delivery_channels,
            'totalChannels': len(delivery_channels),
            'status': 'sent',
            'content': notification_content,
            'metadata': {
                'orderTotal': order_total,
                'itemCount': len(items_summary),
                'paymentMethod': payment_method,
                'transactionId': transaction_id
            },
            'sentAt': datetime.datetime.utcnow().isoformat(),
            'priority': 'high' if order_total > 500 else 'normal',
            'retryCount': 0
        }
        
        # Log notification details for monitoring
        logger.info(f"Notification sent successfully: {notification_response['notificationId']}")
        logger.info(f"Delivered via {len(delivery_channels)} channels: {[ch['channel'] for ch in delivery_channels]}")
        logger.debug(f"Notification details: {json.dumps(notification_response)}")
        
        # In a real implementation, this would integrate with:
        # - Amazon SES for email delivery
        # - Amazon SNS for SMS and push notifications
        # - Third-party services like SendGrid, Twilio, etc.
        
        # Return successful response
        response = {
            'statusCode': 200,
            'body': json.dumps(notification_response),
            'headers': {
                'Content-Type': 'application/json'
            }
        }
        
        logger.info("Notification Service completed successfully")
        return response
        
    except Exception as e:
        error_msg = f"Notification Service error: {str(e)}"
        logger.error(error_msg)
        
        # Return error response
        return {
            'statusCode': 400,
            'body': json.dumps({
                'error': error_msg,
                'orderId': event.get('orderData', {}).get('orderId'),
                'userId': event.get('userData', {}).get('userId'),
                'failedAt': datetime.datetime.utcnow().isoformat(),
                'status': 'failed'
            }),
            'headers': {
                'Content-Type': 'application/json'
            }
        }