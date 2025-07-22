import json
import boto3
import base64
import time
import os
from datetime import datetime
from decimal import Decimal
from typing import Dict, Any, List

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
cloudwatch = boto3.client('cloudwatch')

# Get environment variables
DYNAMODB_TABLE = os.environ.get('DYNAMODB_TABLE', 'analytics-results')
LOG_LEVEL = os.environ.get('LOG_LEVEL', 'INFO')

# Get table reference
table = dynamodb.Table(DYNAMODB_TABLE)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process Kinesis stream records and store analytics in DynamoDB
    
    Args:
        event: Kinesis event containing records
        context: Lambda context object
        
    Returns:
        Dictionary with processing results
    """
    print(f"Received {len(event['Records'])} records from Kinesis")
    
    processed_records = 0
    failed_records = 0
    batch_processing_start = time.time()
    
    for record in event['Records']:
        try:
            # Decode Kinesis data
            payload = base64.b64decode(record['kinesis']['data'])
            data = json.loads(payload.decode('utf-8'))
            
            if LOG_LEVEL == 'DEBUG':
                print(f"Processing record: {json.dumps(data, indent=2)}")
            
            # Extract event information
            event_id = record['kinesis']['sequenceNumber']
            timestamp = int(record['kinesis']['approximateArrivalTimestamp'])
            
            # Validate required fields
            if not validate_event_data(data):
                print(f"Invalid event data: {data}")
                failed_records += 1
                continue
            
            # Process the data (calculate analytics)
            processed_data = process_analytics_data(data)
            
            # Store in DynamoDB
            store_analytics_result(event_id, timestamp, processed_data, data)
            
            # Send custom metrics to CloudWatch
            send_custom_metrics(processed_data)
            
            processed_records += 1
            
        except Exception as e:
            print(f"Error processing record: {str(e)}")
            print(f"Record data: {record}")
            failed_records += 1
            continue
    
    batch_processing_time = time.time() - batch_processing_start
    
    # Send batch processing metrics
    send_batch_metrics(processed_records, failed_records, batch_processing_time)
    
    print(f"Successfully processed {processed_records} records, {failed_records} failed in {batch_processing_time:.2f} seconds")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'processed': processed_records,
            'failed': failed_records,
            'processingTimeSeconds': round(batch_processing_time, 2)
        })
    }

def validate_event_data(data: Dict[str, Any]) -> bool:
    """
    Validate incoming event data structure
    
    Args:
        data: Event data to validate
        
    Returns:
        True if valid, False otherwise
    """
    required_fields = ['eventType']
    
    for field in required_fields:
        if field not in data:
            return False
    
    # Validate event type
    valid_event_types = ['page_view', 'purchase', 'user_signup', 'click', 'error', 'conversion']
    if data['eventType'] not in valid_event_types:
        print(f"Invalid event type: {data['eventType']}")
        return False
    
    return True

def process_analytics_data(data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Process incoming data and calculate analytics metrics
    
    Args:
        data: Raw event data
        
    Returns:
        Processed analytics data
    """
    processed = {
        'event_type': data.get('eventType', 'unknown'),
        'user_id': data.get('userId', 'anonymous'),
        'session_id': data.get('sessionId', ''),
        'device_type': data.get('deviceType', 'unknown'),
        'location': data.get('location', {}),
        'metrics': {},
        'derived_metrics': {}
    }
    
    # Calculate custom metrics based on event type
    if data.get('eventType') == 'page_view':
        processed['metrics'] = {
            'page_url': data.get('pageUrl', ''),
            'load_time': data.get('loadTime', 0),
            'referrer': data.get('referrer', ''),
            'user_agent': data.get('userAgent', '')
        }
        processed['derived_metrics'] = {
            'bounce_rate': calculate_bounce_rate(data),
            'performance_score': calculate_performance_score(data.get('loadTime', 0))
        }
        
    elif data.get('eventType') == 'purchase':
        amount = data.get('amount', 0)
        processed['metrics'] = {
            'amount': Decimal(str(amount)),
            'currency': data.get('currency', 'USD'),
            'items_count': data.get('itemsCount', 0),
            'discount_amount': Decimal(str(data.get('discountAmount', 0))),
            'payment_method': data.get('paymentMethod', 'unknown')
        }
        processed['derived_metrics'] = {
            'order_value_category': categorize_order_value(amount),
            'items_per_order': data.get('itemsCount', 0)
        }
        
    elif data.get('eventType') == 'user_signup':
        processed['metrics'] = {
            'signup_method': data.get('signupMethod', 'email'),
            'campaign_source': data.get('campaignSource', 'direct'),
            'referral_code': data.get('referralCode', ''),
            'marketing_consent': data.get('marketingConsent', False)
        }
        processed['derived_metrics'] = {
            'acquisition_channel': categorize_acquisition_channel(data.get('campaignSource', 'direct'))
        }
        
    elif data.get('eventType') == 'click':
        processed['metrics'] = {
            'element_id': data.get('elementId', ''),
            'element_type': data.get('elementType', ''),
            'page_url': data.get('pageUrl', ''),
            'coordinates': data.get('coordinates', {}),
            'timestamp': data.get('timestamp', '')
        }
        processed['derived_metrics'] = {
            'interaction_type': categorize_interaction(data.get('elementType', ''))
        }
        
    elif data.get('eventType') == 'error':
        processed['metrics'] = {
            'error_type': data.get('errorType', ''),
            'error_message': data.get('errorMessage', ''),
            'stack_trace': data.get('stackTrace', ''),
            'page_url': data.get('pageUrl', ''),
            'browser_info': data.get('browserInfo', {})
        }
        processed['derived_metrics'] = {
            'error_severity': categorize_error_severity(data.get('errorType', '')),
            'error_category': categorize_error_type(data.get('errorType', ''))
        }
    
    return processed

def calculate_bounce_rate(data: Dict[str, Any]) -> float:
    """
    Calculate bounce rate analytics based on session data
    
    Args:
        data: Event data containing session information
        
    Returns:
        Bounce rate score (0.0 to 1.0)
    """
    session_length = data.get('sessionLength', 0)
    pages_viewed = data.get('pagesViewed', 1)
    
    # Simple bounce rate calculation
    if session_length < 30 and pages_viewed == 1:
        return 1.0  # High bounce rate
    elif session_length < 60 and pages_viewed <= 2:
        return 0.7  # Medium bounce rate
    else:
        return 0.0  # Low bounce rate

def calculate_performance_score(load_time: int) -> str:
    """
    Calculate performance score based on page load time
    
    Args:
        load_time: Page load time in milliseconds
        
    Returns:
        Performance category
    """
    if load_time < 1000:
        return 'excellent'
    elif load_time < 2500:
        return 'good'
    elif load_time < 4000:
        return 'fair'
    else:
        return 'poor'

def categorize_order_value(amount: float) -> str:
    """
    Categorize order value for analytics
    
    Args:
        amount: Order amount
        
    Returns:
        Order value category
    """
    if amount < 25:
        return 'low_value'
    elif amount < 100:
        return 'medium_value'
    elif amount < 500:
        return 'high_value'
    else:
        return 'premium_value'

def categorize_acquisition_channel(source: str) -> str:
    """
    Categorize acquisition channel for analytics
    
    Args:
        source: Campaign source
        
    Returns:
        Acquisition channel category
    """
    organic_channels = ['google', 'bing', 'yahoo', 'duckduckgo']
    social_channels = ['facebook', 'twitter', 'instagram', 'linkedin', 'tiktok']
    paid_channels = ['google_ads', 'facebook_ads', 'display', 'ppc']
    
    source_lower = source.lower()
    
    if source_lower in organic_channels:
        return 'organic_search'
    elif source_lower in social_channels:
        return 'social_media'
    elif source_lower in paid_channels:
        return 'paid_advertising'
    elif source_lower == 'direct':
        return 'direct'
    elif 'email' in source_lower:
        return 'email_marketing'
    else:
        return 'other'

def categorize_interaction(element_type: str) -> str:
    """
    Categorize user interaction for analytics
    
    Args:
        element_type: Type of UI element clicked
        
    Returns:
        Interaction category
    """
    navigation_elements = ['menu', 'nav', 'link', 'breadcrumb']
    action_elements = ['button', 'submit', 'cta', 'form']
    content_elements = ['image', 'video', 'text', 'card']
    
    element_lower = element_type.lower()
    
    if any(nav in element_lower for nav in navigation_elements):
        return 'navigation'
    elif any(action in element_lower for action in action_elements):
        return 'action'
    elif any(content in element_lower for content in content_elements):
        return 'content_engagement'
    else:
        return 'other'

def categorize_error_severity(error_type: str) -> str:
    """
    Categorize error severity for analytics
    
    Args:
        error_type: Type of error
        
    Returns:
        Error severity level
    """
    critical_errors = ['crash', 'fatal', 'security', 'data_loss']
    high_errors = ['authentication', 'payment', 'api_failure']
    medium_errors = ['validation', 'network', 'timeout']
    
    error_lower = error_type.lower()
    
    if any(critical in error_lower for critical in critical_errors):
        return 'critical'
    elif any(high in error_lower for high in high_errors):
        return 'high'
    elif any(medium in error_lower for medium in medium_errors):
        return 'medium'
    else:
        return 'low'

def categorize_error_type(error_type: str) -> str:
    """
    Categorize error type for analytics
    
    Args:
        error_type: Type of error
        
    Returns:
        Error category
    """
    frontend_errors = ['javascript', 'render', 'ui', 'dom']
    backend_errors = ['api', 'server', 'database', 'service']
    network_errors = ['timeout', 'connection', 'dns', 'ssl']
    
    error_lower = error_type.lower()
    
    if any(frontend in error_lower for frontend in frontend_errors):
        return 'frontend'
    elif any(backend in error_lower for backend in backend_errors):
        return 'backend'
    elif any(network in error_lower for network in network_errors):
        return 'network'
    else:
        return 'unknown'

def store_analytics_result(event_id: str, timestamp: int, processed_data: Dict[str, Any], raw_data: Dict[str, Any]) -> None:
    """
    Store processed analytics in DynamoDB
    
    Args:
        event_id: Unique event identifier
        timestamp: Event timestamp
        processed_data: Processed analytics data
        raw_data: Original raw event data
    """
    try:
        # Add a Global Secondary Index attribute for querying
        gsi_timestamp = int(time.time())
        
        item = {
            'eventId': event_id,
            'timestamp': timestamp,
            'processedAt': gsi_timestamp,
            'eventType': processed_data['event_type'],
            'userId': processed_data['user_id'],
            'sessionId': processed_data['session_id'],
            'deviceType': processed_data['device_type'],
            'location': processed_data['location'],
            'metrics': processed_data['metrics'],
            'derivedMetrics': processed_data['derived_metrics'],
            'rawData': raw_data,
            'ttl': gsi_timestamp + (30 * 24 * 60 * 60)  # 30 days TTL
        }
        
        table.put_item(Item=item)
        
        if LOG_LEVEL == 'DEBUG':
            print(f"Stored item in DynamoDB: {event_id}")
            
    except Exception as e:
        print(f"Error storing data in DynamoDB: {str(e)}")
        raise

def send_custom_metrics(processed_data: Dict[str, Any]) -> None:
    """
    Send custom metrics to CloudWatch
    
    Args:
        processed_data: Processed analytics data
    """
    try:
        metric_data = []
        
        # Send event type metrics
        metric_data.append({
            'MetricName': 'EventsProcessed',
            'Dimensions': [
                {
                    'Name': 'EventType',
                    'Value': processed_data['event_type']
                },
                {
                    'Name': 'DeviceType',
                    'Value': processed_data['device_type']
                }
            ],
            'Value': 1,
            'Unit': 'Count',
            'Timestamp': datetime.utcnow()
        })
        
        # Send event-specific metrics
        if processed_data['event_type'] == 'purchase':
            metric_data.append({
                'MetricName': 'PurchaseAmount',
                'Dimensions': [
                    {
                        'Name': 'Currency',
                        'Value': processed_data['metrics'].get('currency', 'USD')
                    }
                ],
                'Value': float(processed_data['metrics']['amount']),
                'Unit': 'None',
                'Timestamp': datetime.utcnow()
            })
            
        elif processed_data['event_type'] == 'page_view':
            load_time = processed_data['metrics'].get('load_time', 0)
            if load_time > 0:
                metric_data.append({
                    'MetricName': 'PageLoadTime',
                    'Value': load_time,
                    'Unit': 'Milliseconds',
                    'Timestamp': datetime.utcnow()
                })
        
        # Send metrics in batches (CloudWatch limit is 20 metrics per call)
        if metric_data:
            cloudwatch.put_metric_data(
                Namespace='RealTimeAnalytics',
                MetricData=metric_data
            )
            
    except Exception as e:
        print(f"Error sending CloudWatch metrics: {str(e)}")
        # Don't raise exception to avoid processing failure

def send_batch_metrics(processed_count: int, failed_count: int, processing_time: float) -> None:
    """
    Send batch processing metrics to CloudWatch
    
    Args:
        processed_count: Number of successfully processed records
        failed_count: Number of failed records
        processing_time: Total batch processing time
    """
    try:
        metric_data = [
            {
                'MetricName': 'BatchProcessedRecords',
                'Value': processed_count,
                'Unit': 'Count',
                'Timestamp': datetime.utcnow()
            },
            {
                'MetricName': 'BatchFailedRecords',
                'Value': failed_count,
                'Unit': 'Count',
                'Timestamp': datetime.utcnow()
            },
            {
                'MetricName': 'BatchProcessingTime',
                'Value': processing_time,
                'Unit': 'Seconds',
                'Timestamp': datetime.utcnow()
            }
        ]
        
        if processed_count + failed_count > 0:
            success_rate = (processed_count / (processed_count + failed_count)) * 100
            metric_data.append({
                'MetricName': 'BatchSuccessRate',
                'Value': success_rate,
                'Unit': 'Percent',
                'Timestamp': datetime.utcnow()
            })
        
        cloudwatch.put_metric_data(
            Namespace='RealTimeAnalytics/Batch',
            MetricData=metric_data
        )
        
    except Exception as e:
        print(f"Error sending batch metrics: {str(e)}")
        # Don't raise exception to avoid processing failure