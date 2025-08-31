"""
Test Traffic Generator Lambda Function
Generates realistic test traffic for distributed tracing demonstration
"""

import json
import boto3
import time
import random
import uuid
from concurrent.futures import ThreadPoolExecutor
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all

# Patch all AWS SDK calls for X-Ray tracing
patch_all()

# Initialize Lambda client
lambda_client = boto3.client('lambda')

# Get order service function name from environment
ORDER_FUNCTION_NAME = '${order_function_name}'

@xray_recorder.capture('generate_test_traffic')
def lambda_handler(event, context):
    """
    Generate test traffic for distributed tracing demonstration
    
    Args:
        event: Test configuration (optional)
        context: Lambda context object
        
    Returns:
        dict: Test execution results
    """
    try:
        # Extract test configuration
        num_requests = event.get('num_requests', 20)
        concurrent_requests = event.get('concurrent_requests', 5)
        
        xray_recorder.current_segment().put_annotation('test_requests', num_requests)
        xray_recorder.current_segment().put_annotation('concurrent_requests', concurrent_requests)
        
        print(f"Starting test traffic generation: {num_requests} requests with {concurrent_requests} concurrent")
        
        # Generate test traffic
        results = generate_realistic_traffic(num_requests, concurrent_requests)
        
        # Summarize results
        successful_requests = sum(1 for r in results if r.get('success', False))
        failed_requests = len(results) - successful_requests
        
        xray_recorder.current_segment().put_annotation('successful_requests', successful_requests)
        xray_recorder.current_segment().put_annotation('failed_requests', failed_requests)
        
        # Add comprehensive metadata
        xray_recorder.current_segment().put_metadata('test_execution', {
            'total_requests': num_requests,
            'successful_requests': successful_requests,
            'failed_requests': failed_requests,
            'success_rate': successful_requests / num_requests if num_requests > 0 else 0,
            'execution_time': time.time(),
            'results_summary': results[:5]  # First 5 results for debugging
        })
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'test_completed': True,
                'total_requests': num_requests,
                'successful_requests': successful_requests,
                'failed_requests': failed_requests,
                'success_rate': round(successful_requests / num_requests * 100, 2) if num_requests > 0 else 0,
                'message': f'Generated {num_requests} test requests with {successful_requests} successful'
            })
        }
        
    except Exception as e:
        xray_recorder.current_segment().add_exception(e)
        print(f"Test generation error: {str(e)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Test generation failed',
                'message': str(e)
            })
        }

@xray_recorder.capture('generate_realistic_traffic')
def generate_realistic_traffic(num_requests, max_concurrent):
    """
    Generate realistic test traffic with varied patterns
    
    Args:
        num_requests: Total number of requests to generate
        max_concurrent: Maximum concurrent requests
        
    Returns:
        list: Results from all test requests
    """
    results = []
    
    with ThreadPoolExecutor(max_workers=max_concurrent) as executor:
        futures = []
        
        for i in range(num_requests):
            # Create varied test orders
            test_order = generate_test_order(i)
            
            # Submit request
            future = executor.submit(invoke_order_service, test_order, i)
            futures.append(future)
            
            # Vary request timing to simulate realistic load
            time.sleep(random.uniform(0.1, 0.8))
        
        # Collect all results
        for i, future in enumerate(futures):
            try:
                result = future.result(timeout=30)
                results.append(result)
            except Exception as e:
                print(f"Request {i} failed: {str(e)}")
                results.append({'success': False, 'error': str(e), 'request_id': i})
    
    return results

@xray_recorder.capture('invoke_order_service')
def invoke_order_service(test_order, request_id):
    """
    Invoke order service with test data
    
    Args:
        test_order: Test order data
        request_id: Unique request identifier
        
    Returns:
        dict: Invocation result
    """
    try:
        xray_recorder.current_subsegment().put_annotation('test_order_id', test_order['order_id'])
        xray_recorder.current_subsegment().put_annotation('test_request_id', request_id)
        xray_recorder.current_subsegment().put_annotation('item_count', len(test_order['items']))
        
        print(f"Invoking order service for test order: {test_order['order_id']}")
        
        response = lambda_client.invoke(
            FunctionName=ORDER_FUNCTION_NAME,
            InvocationType='RequestResponse',
            Payload=json.dumps(test_order)
        )
        
        # Parse response
        response_payload = json.loads(response['Payload'].read())
        success = response_payload.get('statusCode') == 200
        
        xray_recorder.current_subsegment().put_annotation('request_success', success)
        xray_recorder.current_subsegment().put_metadata('test_request_result', {
            'order_id': test_order['order_id'],
            'status_code': response_payload.get('statusCode'),
            'success': success,
            'response_body': response_payload.get('body', '{}')[:200]  # Truncated for metadata
        })
        
        return {
            'success': success,
            'order_id': test_order['order_id'],
            'request_id': request_id,
            'status_code': response_payload.get('statusCode'),
            'response_body': response_payload.get('body')
        }
        
    except Exception as e:
        xray_recorder.current_subsegment().add_exception(e)
        print(f"Error invoking order service for request {request_id}: {str(e)}")
        
        return {
            'success': False,
            'order_id': test_order.get('order_id', 'unknown'),
            'request_id': request_id,
            'error': str(e)
        }

def generate_test_order(request_id):
    """
    Generate realistic test order data
    
    Args:
        request_id: Unique request identifier
        
    Returns:
        dict: Test order data
    """
    # Generate realistic order data with variety
    order_id = f'test-order-{request_id}-{uuid.uuid4().hex[:8]}'
    customer_id = f'test-customer-{random.randint(1, 100)}'
    
    # Product categories for realistic variety
    product_categories = [
        'electronics', 'clothing', 'books', 'home', 'sports',
        'premium', 'bulk', 'seasonal', 'digital', 'handmade'
    ]
    
    # Generate 1-4 items per order
    num_items = random.randint(1, 4)
    items = []
    
    for i in range(num_items):
        category = random.choice(product_categories)
        product_id = f'{category}-product-{random.randint(1, 50)}'
        quantity = random.randint(1, 5)
        
        # Price varies by category
        price_ranges = {
            'premium': (100, 500),
            'electronics': (50, 300),
            'clothing': (20, 100),
            'books': (10, 50),
            'bulk': (5, 25),
            'digital': (1, 30),
            'handmade': (25, 150),
            'seasonal': (15, 80),
            'home': (30, 200),
            'sports': (25, 150)
        }
        
        price_min, price_max = price_ranges.get(category, (10, 100))
        price = round(random.uniform(price_min, price_max), 2)
        
        items.append({
            'product_id': product_id,
            'quantity': quantity,
            'price': price,
            'category': category
        })
    
    test_order = {
        'order_id': order_id,
        'customer_id': customer_id,
        'items': items,
        'test_request': True,
        'generated_at': time.time()
    }
    
    return test_order