import json
import boto3
import time
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Lambda function to generate sample log data for testing the log analytics solution.
    
    This function creates realistic log entries that simulate:
    - API requests with response times
    - Error conditions
    - Warning messages
    - Performance metrics
    """
    
    # Initialize AWS clients
    logs_client = boto3.client('logs')
    
    # Get configuration from environment variables
    log_group_name = os.environ['LOG_GROUP_NAME']
    log_stream_name = os.environ['LOG_STREAM_NAME']
    
    print(f"Generating sample log data for log group: {log_group_name}")
    print(f"Log stream: {log_stream_name}")
    
    try:
        # Generate sample log events
        sample_events = generate_sample_log_events()
        
        # Put log events in batches (CloudWatch Logs has limits)
        batch_size = 10
        for i in range(0, len(sample_events), batch_size):
            batch = sample_events[i:i + batch_size]
            
            response = logs_client.put_log_events(
                logGroupName=log_group_name,
                logStreamName=log_stream_name,
                logEvents=batch
            )
            
            print(f"Successfully put {len(batch)} log events (batch {i//batch_size + 1})")
            
            # Small delay to avoid throttling
            time.sleep(0.1)
        
        print(f"Successfully generated {len(sample_events)} sample log events")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Sample log data generated successfully',
                'events_created': len(sample_events),
                'log_group': log_group_name,
                'log_stream': log_stream_name
            })
        }
        
    except Exception as e:
        error_message = f"Error generating sample log data: {str(e)}"
        print(error_message)
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Error generating sample log data',
                'error': str(e)
            })
        }

def generate_sample_log_events():
    """
    Generate a variety of realistic log events for testing.
    
    Returns:
        List of log events in CloudWatch Logs format
    """
    
    base_timestamp = int(time.time() * 1000)  # Current time in milliseconds
    events = []
    
    # Sample log patterns
    sample_logs = [
        # Successful API requests
        "[INFO] API Request: GET /users/123 - 200 - 45ms",
        "[INFO] API Request: POST /orders - 201 - 120ms",
        "[INFO] API Request: GET /products - 200 - 32ms",
        "[INFO] API Request: PUT /users/456 - 200 - 67ms",
        "[INFO] API Request: DELETE /orders/789 - 204 - 89ms",
        "[INFO] API Request: GET /health - 200 - 15ms",
        "[INFO] API Request: POST /login - 200 - 234ms",
        "[INFO] API Request: GET /dashboard - 200 - 156ms",
        
        # Error conditions
        "[ERROR] Database connection failed - Connection timeout",
        "[ERROR] Failed to process payment - Invalid credit card",
        "[ERROR] API Request: POST /orders - 500 - Authentication failed",
        "[ERROR] Memory allocation failed - Out of memory",
        "[ERROR] API Request: GET /users/999 - 404 - User not found",
        "[ERROR] External service timeout - Service unavailable",
        
        # Warning messages
        "[WARN] High memory usage detected: 85%",
        "[WARN] Slow query detected: 2.5s",
        "[WARN] Rate limit approaching: 90% of quota used",
        "[WARN] Deprecated API endpoint used: /v1/users",
        "[WARN] Large response size: 5MB",
        "[WARN] Connection pool exhausted: 95% utilization",
        
        # Performance and system metrics
        "[INFO] System Health Check: CPU=45%, Memory=62%, Disk=78%",
        "[INFO] Cache hit ratio: 87%",
        "[INFO] Active connections: 145",
        "[INFO] Queue size: 23 items",
        "[INFO] Processing batch job: 1,250 records",
        
        # Business logic events
        "[INFO] User registration completed: user_id=12345",
        "[INFO] Order processed successfully: order_id=67890, amount=$149.99",
        "[INFO] Email notification sent: recipient=user@example.com",
        "[INFO] File upload completed: size=2.3MB, type=image/jpeg",
        "[INFO] Background task started: task_id=task_abc123",
        
        # Security events
        "[INFO] User login successful: user_id=12345, ip=192.168.1.100",
        "[WARN] Multiple failed login attempts: user_id=54321, ip=10.0.0.50",
        "[INFO] Password reset requested: user_id=98765",
        "[INFO] Session expired: user_id=11111, session_duration=3600s",
        
        # Integration events
        "[INFO] Third-party API call: service=PaymentGateway, response_time=340ms",
        "[INFO] Message published to queue: topic=order-processing, message_id=msg_456",
        "[INFO] Webhook received: source=github, event=push",
        "[ERROR] Third-party service error: service=EmailService, error=Rate limit exceeded",
        
        # Additional varied content
        "[INFO] Scheduled job executed: job=daily-reports, duration=45s",
        "[INFO] Data synchronization completed: records=5,430",
        "[WARN] SSL certificate expires in 30 days",
        "[INFO] Feature flag toggled: feature=new-checkout, enabled=true",
        "[ERROR] Configuration validation failed: invalid JSON format"
    ]
    
    # Generate events with timestamps spread over the last hour
    for i, log_message in enumerate(sample_logs):
        # Spread events over the last hour with some randomness
        timestamp_offset = i * 60 * 1000  # 1 minute intervals
        timestamp = base_timestamp - (3600 * 1000) + timestamp_offset  # Start 1 hour ago
        
        event = {
            'timestamp': timestamp,
            'message': log_message
        }
        
        events.append(event)
    
    # Sort events by timestamp
    events.sort(key=lambda x: x['timestamp'])
    
    return events