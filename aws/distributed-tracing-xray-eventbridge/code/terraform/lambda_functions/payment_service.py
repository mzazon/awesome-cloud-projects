"""
Payment Service Lambda Function
Processes payment events from EventBridge and publishes payment completion events
Implements X-Ray tracing to maintain distributed observability across event flows
"""

import json
import boto3
import os
import time
from datetime import datetime
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all

# Patch AWS SDK calls for automatic X-Ray tracing
patch_all()

# Initialize AWS clients with X-Ray tracing
eventbridge = boto3.client('events')

@xray_recorder.capture('payment_service_handler')
def lambda_handler(event, context):
    """
    Main Lambda handler for payment service
    Processes EventBridge events for order payments
    """
    
    # Process each EventBridge event record
    for record in event.get('Records', []):
        # Create subsegment for payment processing
        subsegment = xray_recorder.begin_subsegment('process_payment')
        
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
            amount = detail.get('amount', 0.0)
            trace_id = detail.get('traceId', '')
            
            # Add comprehensive metadata to X-Ray trace
            subsegment.put_metadata('payment_processing', {
                'order_id': order_id,
                'customer_id': customer_id,
                'amount': amount,
                'processor': 'stripe',
                'event_source': source,
                'event_detail_type': detail_type,
                'timestamp': datetime.now().isoformat(),
                'request_id': context.aws_request_id
            })
            
            # Add annotations for filtering and searching traces
            xray_recorder.put_annotation('order_id', order_id)
            xray_recorder.put_annotation('customer_id', customer_id)
            xray_recorder.put_annotation('service_name', 'payment-service')
            xray_recorder.put_annotation('payment_amount', amount)
            xray_recorder.put_annotation('event_source', source)
            
            # Simulate payment processing delay and validation
            payment_processing_time = min(max(amount / 100, 0.1), 2.0)  # Scale with amount
            time.sleep(payment_processing_time)
            
            # Generate payment ID and process payment
            payment_id = f"pay-{order_id}-{int(datetime.now().timestamp())}"
            
            # Simulate payment validation logic
            payment_status = 'processed'
            if amount > 10000:  # Large amount requires additional validation
                payment_status = 'pending_review'
                xray_recorder.put_annotation('payment_review_required', True)
            elif amount <= 0:  # Invalid amount
                payment_status = 'failed'
                xray_recorder.put_annotation('payment_failed', True)
            
            # Add payment result metadata
            subsegment.put_metadata('payment_result', {
                'payment_id': payment_id,
                'status': payment_status,
                'processing_time_seconds': payment_processing_time,
                'processor_response': {
                    'transaction_id': payment_id,
                    'processor': 'stripe',
                    'fees': round(amount * 0.029 + 0.30, 2)  # Stripe-like fee structure
                }
            })
            
            # Create payment processed event
            payment_event_detail = {
                'orderId': order_id,
                'customerId': customer_id,
                'paymentId': payment_id,
                'amount': amount,
                'status': payment_status,
                'processor': 'stripe',
                'timestamp': datetime.now().isoformat(),
                'traceId': trace_id,
                'processingTimeMs': int(payment_processing_time * 1000)
            }
            
            # Publish payment processed event to EventBridge
            event_response = eventbridge.put_events(
                Entries=[
                    {
                        'Source': 'payment.service',
                        'DetailType': 'Payment Processed',
                        'Detail': json.dumps(payment_event_detail),
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
            
            # Add success annotation
            xray_recorder.put_annotation('payment_processed', True)
            
            print(f"Payment processed successfully: {payment_id} for order {order_id}")
            
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
            
            print(f"Payment processing error: {error_message}")
            
        finally:
            # Always end the subsegment
            xray_recorder.end_subsegment()
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Payment events processed successfully',
            'processedCount': len(event.get('Records', [])),
            'timestamp': datetime.now().isoformat()
        })
    }