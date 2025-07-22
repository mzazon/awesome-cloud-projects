"""
Notification Service Lambda Function
Sends customer notifications triggered by payment and inventory events
Implements X-Ray tracing for end-to-end distributed observability
"""

import json
import boto3
import os
from datetime import datetime
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all

# Patch AWS SDK calls for automatic X-Ray tracing
patch_all()

# Initialize AWS clients (in production, you might use SES, SNS, etc.)
# For demo purposes, we'll simulate notification sending

# Notification templates for different event types
NOTIFICATION_TEMPLATES = {
    'Payment Processed': {
        'subject': 'Payment Confirmation - Order #{order_id}',
        'message': 'Your payment of ${amount} for order {order_id} has been processed successfully. Payment ID: {payment_id}'
    },
    'Inventory Updated': {
        'subject': 'Order Confirmation - Order #{order_id}',
        'message': 'Your order {order_id} has been confirmed and inventory has been reserved at our {warehouse} warehouse.'
    },
    'Inventory Insufficient': {
        'subject': 'Order Status Update - Order #{order_id}',
        'message': 'We\'re sorry, but there is insufficient inventory for your order {order_id}. Available quantity: {available_quantity}. We\'ll notify you when more stock is available.'
    }
}

@xray_recorder.capture('notification_service_handler')
def lambda_handler(event, context):
    """
    Main Lambda handler for notification service
    Processes EventBridge events and sends appropriate notifications
    """
    
    # Process each EventBridge event record
    for record in event.get('Records', []):
        # Create subsegment for notification processing
        subsegment = xray_recorder.begin_subsegment('send_notification')
        
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
            
            # Extract common information
            order_id = detail.get('orderId', '')
            customer_id = detail.get('customerId', '')
            trace_id = detail.get('traceId', '')
            
            # Add comprehensive metadata to X-Ray trace
            subsegment.put_metadata('notification_processing', {
                'order_id': order_id,
                'customer_id': customer_id,
                'event_source': source,
                'event_detail_type': detail_type,
                'timestamp': datetime.now().isoformat(),
                'request_id': context.aws_request_id
            })
            
            # Add annotations for filtering and searching traces
            xray_recorder.put_annotation('order_id', order_id)
            xray_recorder.put_annotation('customer_id', customer_id)
            xray_recorder.put_annotation('service_name', 'notification-service')
            xray_recorder.put_annotation('notification_type', detail_type)
            xray_recorder.put_annotation('event_source', source)
            
            # Process different types of events
            notification_result = None
            
            if detail_type == 'Payment Processed':
                notification_result = send_payment_notification(detail, subsegment)
                
            elif detail_type == 'Inventory Updated':
                notification_result = send_inventory_notification(detail, subsegment)
                
            elif detail_type == 'Inventory Insufficient':
                notification_result = send_backorder_notification(detail, subsegment)
                
            else:
                # Handle unknown event types
                xray_recorder.put_annotation('unknown_event_type', detail_type)
                subsegment.put_metadata('unknown_event', {
                    'detail_type': detail_type,
                    'source': source,
                    'detail': detail
                })
                print(f"Unknown event type: {detail_type}")
                continue
            
            # Add notification result to trace
            if notification_result:
                subsegment.put_metadata('notification_result', notification_result)
                xray_recorder.put_annotation('notification_sent', notification_result['success'])
                
                if notification_result['success']:
                    xray_recorder.put_annotation('notification_channel', notification_result['channel'])
                else:
                    xray_recorder.put_annotation('notification_error', notification_result['error'])
            
            print(f"Notification processed for order {order_id}, type: {detail_type}")
            
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
            
            print(f"Notification processing error: {error_message}")
            
        finally:
            # Always end the subsegment
            xray_recorder.end_subsegment()
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Notification events processed successfully',
            'processedCount': len(event.get('Records', [])),
            'timestamp': datetime.now().isoformat()
        })
    }


def send_payment_notification(detail, subsegment):
    """
    Send payment confirmation notification
    """
    try:
        order_id = detail.get('orderId', '')
        customer_id = detail.get('customerId', '')
        payment_id = detail.get('paymentId', '')
        amount = detail.get('amount', 0.0)
        payment_status = detail.get('status', 'unknown')
        
        # Get notification template
        template = NOTIFICATION_TEMPLATES.get('Payment Processed', {})
        subject = template.get('subject', '').format(order_id=order_id)
        message = template.get('message', '').format(
            order_id=order_id,
            amount=amount,
            payment_id=payment_id
        )
        
        # Simulate sending notification (in production, use SES, SNS, etc.)
        notification_id = f"notif-pay-{order_id}-{int(datetime.now().timestamp())}"
        
        # Add notification details to subsegment
        subsegment.put_metadata('payment_notification', {
            'notification_id': notification_id,
            'customer_id': customer_id,
            'subject': subject,
            'message': message,
            'payment_status': payment_status,
            'amount': amount,
            'channel': 'email'
        })
        
        # Simulate notification delivery
        delivery_result = simulate_notification_delivery('email', customer_id, subject, message)
        
        return {
            'success': delivery_result['success'],
            'notification_id': notification_id,
            'channel': 'email',
            'delivery_time_ms': delivery_result['delivery_time_ms'],
            'error': delivery_result.get('error')
        }
        
    except Exception as e:
        return {
            'success': False,
            'error': str(e),
            'channel': 'email'
        }


def send_inventory_notification(detail, subsegment):
    """
    Send inventory confirmation notification
    """
    try:
        order_id = detail.get('orderId', '')
        customer_id = detail.get('customerId', '')
        warehouse = detail.get('warehouse', 'unknown')
        reservation_id = detail.get('reservationId', '')
        quantity = detail.get('quantity', 0)
        
        # Get notification template
        template = NOTIFICATION_TEMPLATES.get('Inventory Updated', {})
        subject = template.get('subject', '').format(order_id=order_id)
        message = template.get('message', '').format(
            order_id=order_id,
            warehouse=warehouse
        )
        
        # Simulate sending notification
        notification_id = f"notif-inv-{order_id}-{int(datetime.now().timestamp())}"
        
        # Add notification details to subsegment
        subsegment.put_metadata('inventory_notification', {
            'notification_id': notification_id,
            'customer_id': customer_id,
            'subject': subject,
            'message': message,
            'warehouse': warehouse,
            'reservation_id': reservation_id,
            'quantity': quantity,
            'channel': 'email'
        })
        
        # Simulate notification delivery
        delivery_result = simulate_notification_delivery('email', customer_id, subject, message)
        
        return {
            'success': delivery_result['success'],
            'notification_id': notification_id,
            'channel': 'email',
            'delivery_time_ms': delivery_result['delivery_time_ms'],
            'error': delivery_result.get('error')
        }
        
    except Exception as e:
        return {
            'success': False,
            'error': str(e),
            'channel': 'email'
        }


def send_backorder_notification(detail, subsegment):
    """
    Send backorder/insufficient inventory notification
    """
    try:
        order_id = detail.get('orderId', '')
        customer_id = detail.get('customerId', '')
        available_quantity = detail.get('availableQuantity', 0)
        requested_quantity = detail.get('quantity', 0)
        
        # Get notification template
        template = NOTIFICATION_TEMPLATES.get('Inventory Insufficient', {})
        subject = template.get('subject', '').format(order_id=order_id)
        message = template.get('message', '').format(
            order_id=order_id,
            available_quantity=available_quantity
        )
        
        # Simulate sending notification
        notification_id = f"notif-back-{order_id}-{int(datetime.now().timestamp())}"
        
        # Add notification details to subsegment
        subsegment.put_metadata('backorder_notification', {
            'notification_id': notification_id,
            'customer_id': customer_id,
            'subject': subject,
            'message': message,
            'available_quantity': available_quantity,
            'requested_quantity': requested_quantity,
            'shortfall': requested_quantity - available_quantity,
            'channel': 'email'
        })
        
        # Simulate notification delivery
        delivery_result = simulate_notification_delivery('email', customer_id, subject, message)
        
        return {
            'success': delivery_result['success'],
            'notification_id': notification_id,
            'channel': 'email',
            'delivery_time_ms': delivery_result['delivery_time_ms'],
            'error': delivery_result.get('error')
        }
        
    except Exception as e:
        return {
            'success': False,
            'error': str(e),
            'channel': 'email'
        }


def simulate_notification_delivery(channel, customer_id, subject, message):
    """
    Simulate notification delivery (replace with actual implementation)
    """
    import time
    import random
    
    # Simulate delivery time
    delivery_time_ms = random.randint(100, 500)
    time.sleep(delivery_time_ms / 1000)
    
    # Simulate occasional failures (5% failure rate)
    if random.random() < 0.05:
        return {
            'success': False,
            'error': 'Delivery service temporarily unavailable',
            'delivery_time_ms': delivery_time_ms
        }
    
    # Simulate successful delivery
    return {
        'success': True,
        'delivery_time_ms': delivery_time_ms,
        'message_size_bytes': len(message.encode('utf-8'))
    }