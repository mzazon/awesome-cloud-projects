"""
Payment Service Lambda Function with X-Ray Distributed Tracing
Processes payment requests with comprehensive observability
"""

import json
import time
import random
import uuid
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all

# Patch all AWS SDK calls for X-Ray tracing
patch_all()

@xray_recorder.capture('process_payment')
def lambda_handler(event, context):
    """
    Process payment requests with comprehensive tracing and error simulation
    
    Args:
        event: Payment request containing order_id, amount, currency, etc.
        context: Lambda context object
        
    Returns:
        dict: Payment processing result with status and details
    """
    try:
        # Extract payment information
        order_id = event.get('order_id', f'order-{uuid.uuid4().hex[:8]}')
        amount = float(event.get('amount', 100.00))
        currency = event.get('currency', 'USD')
        payment_method = event.get('payment_method', 'credit_card')
        
        # Add annotations for filtering and analysis
        xray_recorder.current_segment().put_annotation('order_id', order_id)
        xray_recorder.current_segment().put_annotation('payment_amount', amount)
        xray_recorder.current_segment().put_annotation('currency', currency)
        xray_recorder.current_segment().put_annotation('payment_method', payment_method)
        xray_recorder.current_segment().put_annotation('service_type', 'payment-processing')
        
        # Simulate varying payment processing times (realistic latency)
        processing_time = random.uniform(0.1, 0.5)
        time.sleep(processing_time)
        
        # Add processing time annotation
        xray_recorder.current_segment().put_annotation('processing_time_ms', int(processing_time * 1000))
        
        # Simulate payment gateway selection based on amount
        payment_gateway = select_payment_gateway(amount)
        xray_recorder.current_segment().put_annotation('payment_gateway', payment_gateway)
        
        print(f"Processing payment for order {order_id}: ${amount} {currency} via {payment_gateway}")
        
        # Simulate payment processing with gateway
        payment_result = process_with_gateway(order_id, amount, currency, payment_method, payment_gateway)
        
        # Add comprehensive metadata for debugging
        xray_recorder.current_segment().put_metadata('payment_details', {
            'order_id': order_id,
            'amount': amount,
            'currency': currency,
            'payment_method': payment_method,
            'payment_gateway': payment_gateway,
            'processing_time_ms': processing_time * 1000,
            'timestamp': time.time(),
            'result': payment_result
        })
        
        # Determine response based on payment result
        if payment_result['status'] == 'approved':
            xray_recorder.current_segment().put_annotation('payment_status', 'approved')
            
            response = {
                'statusCode': 200,
                'body': json.dumps({
                    'payment_id': payment_result['payment_id'],
                    'status': 'approved',
                    'amount': amount,
                    'currency': currency,
                    'payment_gateway': payment_gateway,
                    'processing_time_ms': int(processing_time * 1000),
                    'transaction_id': payment_result.get('transaction_id'),
                    'approval_code': payment_result.get('approval_code')
                })
            }
            
            print(f"Payment approved for order {order_id}: {payment_result['payment_id']}")
            
        else:
            # Handle payment failure
            xray_recorder.current_segment().put_annotation('payment_status', 'failed')
            xray_recorder.current_segment().add_exception(
                Exception(f"Payment failed: {payment_result.get('error', 'Unknown error')}")
            )
            
            response = {
                'statusCode': 400,
                'body': json.dumps({
                    'status': 'failed',
                    'amount': amount,
                    'currency': currency,
                    'payment_gateway': payment_gateway,
                    'error': payment_result.get('error', 'Payment processing failed'),
                    'error_code': payment_result.get('error_code', 'PROCESSING_ERROR'),
                    'processing_time_ms': int(processing_time * 1000)
                })
            }
            
            print(f"Payment failed for order {order_id}: {payment_result.get('error')}")
        
        return response
        
    except Exception as e:
        # Add exception to X-Ray trace
        xray_recorder.current_segment().add_exception(e)
        xray_recorder.current_segment().put_annotation('payment_status', 'error')
        xray_recorder.current_segment().put_annotation('error_occurred', True)
        
        print(f"Payment service error: {str(e)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'status': 'error',
                'error': 'Payment service unavailable',
                'message': str(e),
                'order_id': event.get('order_id', 'unknown')
            })
        }

@xray_recorder.capture('select_payment_gateway')
def select_payment_gateway(amount):
    """
    Select appropriate payment gateway based on transaction amount
    
    Args:
        amount: Transaction amount
        
    Returns:
        str: Selected payment gateway name
    """
    # Add business logic for gateway selection
    xray_recorder.current_subsegment().put_annotation('gateway_selection_amount', amount)
    
    if amount > 1000:
        gateway = 'premium_gateway'
    elif amount > 100:
        gateway = 'standard_gateway'
    else:
        gateway = 'basic_gateway'
    
    xray_recorder.current_subsegment().put_annotation('selected_gateway', gateway)
    xray_recorder.current_subsegment().put_metadata('gateway_selection', {
        'amount': amount,
        'selected_gateway': gateway,
        'selection_criteria': 'amount_based'
    })
    
    return gateway

@xray_recorder.capture('process_with_gateway')
def process_with_gateway(order_id, amount, currency, payment_method, gateway):
    """
    Process payment with selected gateway (simulated)
    
    Args:
        order_id: Order identifier
        amount: Payment amount
        currency: Payment currency
        payment_method: Payment method
        gateway: Selected payment gateway
        
    Returns:
        dict: Payment processing result
    """
    # Add gateway-specific annotations
    xray_recorder.current_subsegment().put_annotation('gateway_name', gateway)
    xray_recorder.current_subsegment().put_annotation('gateway_amount', amount)
    
    # Simulate different failure rates by gateway
    failure_rates = {
        'basic_gateway': 0.15,      # 15% failure rate
        'standard_gateway': 0.08,   # 8% failure rate  
        'premium_gateway': 0.03     # 3% failure rate
    }
    
    failure_rate = failure_rates.get(gateway, 0.10)
    xray_recorder.current_subsegment().put_annotation('expected_failure_rate', failure_rate)
    
    # Simulate gateway response time variance
    gateway_delay = {
        'basic_gateway': random.uniform(0.05, 0.2),
        'standard_gateway': random.uniform(0.03, 0.15),
        'premium_gateway': random.uniform(0.02, 0.1)
    }
    
    time.sleep(gateway_delay.get(gateway, 0.1))
    
    # Simulate payment processing outcome
    if random.random() < failure_rate:
        # Simulate payment failure
        error_types = [
            {'error': 'Insufficient funds', 'error_code': 'INSUFFICIENT_FUNDS'},
            {'error': 'Card declined', 'error_code': 'CARD_DECLINED'},
            {'error': 'Gateway timeout', 'error_code': 'GATEWAY_TIMEOUT'},
            {'error': 'Invalid card details', 'error_code': 'INVALID_CARD'}
        ]
        
        error_info = random.choice(error_types)
        xray_recorder.current_subsegment().put_annotation('failure_reason', error_info['error_code'])
        
        return {
            'status': 'failed',
            'error': error_info['error'],
            'error_code': error_info['error_code'],
            'gateway': gateway
        }
    
    else:
        # Simulate successful payment
        payment_id = f'pay_{order_id}_{int(time.time())}_{random.randint(1000, 9999)}'
        transaction_id = f'txn_{uuid.uuid4().hex[:12]}'
        approval_code = f'APP{random.randint(100000, 999999)}'
        
        xray_recorder.current_subsegment().put_annotation('payment_approved', True)
        xray_recorder.current_subsegment().put_metadata('payment_success', {
            'payment_id': payment_id,
            'transaction_id': transaction_id,
            'approval_code': approval_code,
            'gateway': gateway
        })
        
        return {
            'status': 'approved',
            'payment_id': payment_id,
            'transaction_id': transaction_id,
            'approval_code': approval_code,
            'gateway': gateway
        }

def health_check():
    """Simple health check for load balancer"""
    return {
        'statusCode': 200,
        'body': json.dumps({
            'status': 'healthy',
            'service': 'payment-service',
            'timestamp': time.time(),
            'available_gateways': ['basic_gateway', 'standard_gateway', 'premium_gateway']
        })
    }