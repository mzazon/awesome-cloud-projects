import json
import logging
import os
import urllib3
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.getenv('LOG_LEVEL', 'INFO'))

# Initialize HTTP client
http = urllib3.PoolManager()

def lambda_handler(event, context):
    """
    Process webhook notification messages from SQS
    
    This function sends HTTP POST requests to webhook endpoints
    with retry logic and error handling.
    """
    
    processed_messages = []
    
    logger.info(f"Processing {len(event['Records'])} webhook message(s)")
    
    for record in event['Records']:
        try:
            # Parse message body
            message_body = json.loads(record['body'])
            
            # Extract webhook details
            webhook_url = message_body.get('webhook_url', '${webhook_url}')
            payload = message_body.get('payload', {})
            headers = message_body.get('headers', {
                'Content-Type': 'application/json',
                'User-Agent': 'AWS-Lambda-Webhook-Handler/1.0'
            })
            retry_count = message_body.get('retry_count', 0)
            timeout = message_body.get('timeout', 30)
            
            # Add metadata to payload
            enhanced_payload = {
                **payload,
                'notification_metadata': {
                    'timestamp': message_body.get('timestamp', datetime.utcnow().isoformat()),
                    'subject': message_body.get('subject', 'Webhook Notification'),
                    'message': message_body.get('message', ''),
                    'priority': message_body.get('priority', 'normal'),
                    'source': 'aws-lambda-notification-system',
                    'environment': os.getenv('ENVIRONMENT', 'dev'),
                    'project': os.getenv('PROJECT_NAME', 'notification-system')
                }
            }
            
            if not webhook_url:
                logger.error("No webhook URL provided in message")
                continue
            
            # Send webhook request
            logger.info(f"Sending webhook to {webhook_url}")
            logger.info(f"Payload size: {len(json.dumps(enhanced_payload))} bytes")
            
            try:
                response = http.request(
                    'POST',
                    webhook_url,
                    body=json.dumps(enhanced_payload),
                    headers=headers,
                    timeout=timeout
                )
                
                if response.status >= 200 and response.status < 300:
                    logger.info(f"✅ Webhook sent successfully to {webhook_url}")
                    logger.info(f"   Response status: {response.status}")
                    logger.info(f"   Response headers: {dict(response.headers)}")
                    
                    # Log response body if it's small enough
                    if response.data and len(response.data) < 1000:
                        logger.info(f"   Response body: {response.data.decode('utf-8')}")
                    
                    status = 'success'
                    
                elif response.status >= 400 and response.status < 500:
                    # Client errors (4xx) - don't retry
                    logger.error(f"❌ Webhook client error {response.status}: {response.data.decode('utf-8') if response.data else 'No response body'}")
                    status = 'client_error'
                    
                elif response.status >= 500:
                    # Server errors (5xx) - retry
                    logger.warning(f"⚠️ Webhook server error {response.status}: {response.data.decode('utf-8') if response.data else 'No response body'}")
                    status = 'server_error'
                    if retry_count < 3:
                        raise Exception(f"Webhook server error {response.status}, will retry")
                else:
                    logger.warning(f"⚠️ Webhook unexpected status {response.status}")
                    status = 'unexpected_status'
                    
            except urllib3.exceptions.TimeoutError:
                logger.error(f"❌ Webhook request timeout after {timeout} seconds")
                status = 'timeout'
                if retry_count < 3:
                    raise Exception(f"Webhook timeout, will retry")
                    
            except Exception as webhook_error:
                logger.error(f"❌ Webhook request failed: {str(webhook_error)}")
                status = 'network_error'
                if retry_count < 3:
                    raise webhook_error  # Will trigger SQS retry
            
            processed_messages.append({
                'messageId': record['messageId'],
                'status': status,
                'webhook_url': webhook_url,
                'retry_count': retry_count,
                'timestamp': datetime.utcnow().isoformat()
            })
            
        except Exception as e:
            logger.error(f"Error processing message {record['messageId']}: {str(e)}")
            # Re-raise to trigger SQS retry mechanism
            raise e
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'processed': len(processed_messages),
            'messages': processed_messages,
            'timestamp': datetime.utcnow().isoformat()
        })
    }

def validate_webhook_url(url):
    """
    Validate webhook URL format and security
    
    Args:
        url (str): Webhook URL to validate
    
    Returns:
        bool: True if valid, False otherwise
    """
    
    import re
    
    # Basic URL validation
    url_pattern = re.compile(
        r'^https?://'  # http:// or https://
        r'(?:(?:[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?\.)+[A-Z]{2,6}\.?|'  # domain...
        r'localhost|'  # localhost...
        r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})'  # ...or ip
        r'(?::\d+)?'  # optional port
        r'(?:/?|[/?]\S+)$', re.IGNORECASE)
    
    if not url_pattern.match(url):
        return False
    
    # Security checks
    if url.startswith('http://') and not url.startswith('http://localhost'):
        logger.warning(f"Insecure HTTP URL: {url}")
        # In production, you might want to reject HTTP URLs
        # return False
    
    return True

def add_webhook_signature(payload, secret_key):
    """
    Add webhook signature for security (optional)
    
    Args:
        payload (dict): Webhook payload
        secret_key (str): Secret key for signing
    
    Returns:
        str: Signature to include in headers
    """
    
    import hmac
    import hashlib
    
    payload_string = json.dumps(payload, sort_keys=True)
    signature = hmac.new(
        secret_key.encode('utf-8'),
        payload_string.encode('utf-8'),
        hashlib.sha256
    ).hexdigest()
    
    return f"sha256={signature}"

def format_webhook_payload(subject, message, priority, timestamp, custom_payload=None):
    """
    Format webhook payload with standard structure
    
    Args:
        subject (str): Notification subject
        message (str): Notification message
        priority (str): Priority level
        timestamp (str): Timestamp
        custom_payload (dict): Additional custom data
    
    Returns:
        dict: Formatted webhook payload
    """
    
    payload = {
        'event': 'notification',
        'data': {
            'subject': subject,
            'message': message,
            'priority': priority,
            'timestamp': timestamp,
            'environment': os.getenv('ENVIRONMENT', 'dev'),
            'project': os.getenv('PROJECT_NAME', 'notification-system')
        }
    }
    
    if custom_payload:
        payload['data']['custom'] = custom_payload
    
    return payload