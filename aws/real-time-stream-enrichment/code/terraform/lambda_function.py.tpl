import json
import base64
import boto3
import os
import logging
from datetime import datetime
from typing import Dict, List, Any, Optional

# Configure logging
log_level = os.environ.get('LOG_LEVEL', 'INFO')
logger = logging.getLogger()
logger.setLevel(getattr(logging, log_level))

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
table_name = os.environ.get('TABLE_NAME', '${table_name}')
table = dynamodb.Table(table_name)

def lambda_handler(event: Dict[str, Any], context: Any) -> List[Dict[str, Any]]:
    """
    Lambda function to enrich streaming events with reference data from DynamoDB.
    
    This function processes events from EventBridge Pipes, looks up additional
    product information from DynamoDB, and returns enriched events.
    
    Args:
        event: Event data from EventBridge Pipes containing Kinesis records
        context: Lambda context object
        
    Returns:
        List of enriched event records
    """
    logger.info(f"Processing {len(event.get('records', []))} records")
    enriched_records = []
    
    try:
        # Process each record from the event
        records = event.get('records', [])
        for record in records:
            try:
                # Decode the Kinesis data
                kinesis_data = record.get('data', '')
                if kinesis_data:
                    # Decode base64 data
                    decoded_data = base64.b64decode(kinesis_data).decode('utf-8')
                    payload = json.loads(decoded_data)
                else:
                    # Handle direct payload (for testing)
                    payload = record
                
                logger.debug(f"Processing payload: {payload}")
                
                # Enrich the payload with reference data
                enriched_payload = enrich_event(payload)
                enriched_records.append(enriched_payload)
                
            except Exception as e:
                logger.error(f"Error processing individual record: {str(e)}")
                # Add error information to the record
                error_payload = record.copy()
                error_payload.update({
                    'enrichmentStatus': 'processing_error',
                    'enrichmentError': str(e),
                    'enrichmentTimestamp': datetime.utcnow().isoformat()
                })
                enriched_records.append(error_payload)
    
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        raise
    
    logger.info(f"Successfully processed {len(enriched_records)} records")
    return enriched_records

def enrich_event(payload: Dict[str, Any]) -> Dict[str, Any]:
    """
    Enrich a single event with reference data from DynamoDB.
    
    Args:
        payload: The event payload to enrich
        
    Returns:
        Enriched event payload
    """
    enriched_payload = payload.copy()
    
    # Extract product ID from the payload
    product_id = payload.get('productId')
    
    if not product_id:
        logger.warning("No productId found in payload")
        enriched_payload.update({
            'enrichmentStatus': 'no_product_id',
            'enrichmentTimestamp': datetime.utcnow().isoformat()
        })
        return enriched_payload
    
    try:
        # Lookup product details from DynamoDB
        logger.debug(f"Looking up product: {product_id}")
        response = table.get_item(Key={'productId': product_id})
        
        if 'Item' in response:
            # Product found - enrich the payload
            product_info = response['Item']
            logger.debug(f"Found product info: {product_info}")
            
            # Add product information to the payload
            enriched_payload.update({
                'productName': product_info.get('productName'),
                'category': product_info.get('category'),
                'price': float(product_info.get('price', 0)),
                'description': product_info.get('description'),
                'manufacturer': product_info.get('manufacturer'),
                'enrichmentStatus': 'success',
                'enrichmentTimestamp': datetime.utcnow().isoformat(),
                'enrichmentSource': 'dynamodb'
            })
            
            # Calculate derived fields
            quantity = payload.get('quantity', 0)
            if quantity and enriched_payload.get('price'):
                enriched_payload['totalValue'] = float(quantity) * enriched_payload['price']
            
            logger.info(f"Successfully enriched product {product_id}")
            
        else:
            # Product not found
            logger.warning(f"Product {product_id} not found in reference data")
            enriched_payload.update({
                'enrichmentStatus': 'product_not_found',
                'enrichmentTimestamp': datetime.utcnow().isoformat(),
                'enrichmentSource': 'dynamodb'
            })
    
    except Exception as e:
        logger.error(f"Error looking up product {product_id}: {str(e)}")
        enriched_payload.update({
            'enrichmentStatus': 'lookup_error',
            'enrichmentError': str(e),
            'enrichmentTimestamp': datetime.utcnow().isoformat(),
            'enrichmentSource': 'dynamodb'
        })
    
    return enriched_payload

def get_product_info(product_id: str) -> Optional[Dict[str, Any]]:
    """
    Retrieve product information from DynamoDB with error handling.
    
    Args:
        product_id: The product ID to look up
        
    Returns:
        Product information dictionary or None if not found
    """
    try:
        response = table.get_item(Key={'productId': product_id})
        return response.get('Item')
    except Exception as e:
        logger.error(f"DynamoDB lookup error for {product_id}: {str(e)}")
        return None

# Test handler for local development
if __name__ == "__main__":
    # Test event structure
    test_event = {
        "records": [
            {
                "data": base64.b64encode(json.dumps({
                    "eventId": "test-001",
                    "productId": "PROD-001",
                    "quantity": 5,
                    "timestamp": datetime.utcnow().isoformat(),
                    "source": "test"
                }).encode()).decode()
            }
        ]
    }
    
    # Mock context
    class MockContext:
        function_name = "test-function"
        function_version = "1"
        invoked_function_arn = "arn:aws:lambda:us-east-1:123456789012:function:test"
        memory_limit_in_mb = "256"
        remaining_time_in_millis = 30000
    
    # Test the function
    result = lambda_handler(test_event, MockContext())
    print(json.dumps(result, indent=2))