"""
AWS Lambda function for processing IoT security events
This function processes IoT security events and stores them in DynamoDB for analysis
"""

import json
import boto3
import logging
import os
from datetime import datetime
from typing import Dict, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process IoT security events and take appropriate actions
    
    Args:
        event: IoT security event data
        context: Lambda execution context
        
    Returns:
        Response dictionary with status and message
    """
    
    try:
        # Log the security event
        logger.info(f"Security event received: {json.dumps(event, default=str)}")
        
        # Extract device information
        device_id = event.get('clientId', 'unknown')
        event_type = event.get('eventType', 'unknown')
        timestamp = event.get('timestamp', datetime.utcnow().isoformat())
        
        # Process different types of security events
        process_security_event(device_id, event_type, event)
        
        # Store event for analysis
        store_security_event(event, context, device_id, event_type, timestamp)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Security event processed successfully',
                'deviceId': device_id,
                'eventType': event_type
            })
        }
        
    except Exception as e:
        logger.error(f"Failed to process security event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error processing security event: {str(e)}')
        }


def process_security_event(device_id: str, event_type: str, event_data: Dict[str, Any]) -> None:
    """
    Process specific security event types and take appropriate actions
    
    Args:
        device_id: Device identifier
        event_type: Type of security event
        event_data: Complete event data
    """
    
    if event_type == 'Connect.AuthError':
        logger.warning(f"Authentication failure for device: {device_id}")
        # In production, could trigger device quarantine or alert escalation
        
    elif event_type == 'Publish.AuthError':
        logger.warning(f"Unauthorized publish attempt from device: {device_id}")
        # In production, could update device policy or disable device
        
    elif event_type == 'Subscribe.AuthError':
        logger.warning(f"Unauthorized subscribe attempt from device: {device_id}")
        # In production, could review and update subscription policies
        
    elif 'Disconnect' in event_type:
        logger.info(f"Device disconnection event for device: {device_id}")
        # In production, could check for unexpected disconnections
        
    else:
        logger.info(f"Processing general security event: {event_type} for device: {device_id}")


def store_security_event(event_data: Dict[str, Any], context: Any, device_id: str, 
                        event_type: str, timestamp: str) -> None:
    """
    Store security event in DynamoDB for analysis and compliance
    
    Args:
        event_data: Complete event data
        context: Lambda execution context
        device_id: Device identifier
        event_type: Type of security event
        timestamp: Event timestamp
    """
    
    table_name = os.environ.get('DYNAMODB_TABLE', '${table_name}')
    
    try:
        table = dynamodb.Table(table_name)
        
        # Prepare item for DynamoDB
        item = {
            'eventId': context.aws_request_id,
            'deviceId': device_id,
            'eventType': event_type,
            'timestamp': timestamp,
            'eventData': json.dumps(event_data, default=str),
            'processed': True,
            'ttl': int((datetime.utcnow().timestamp() + (90 * 24 * 60 * 60)))  # 90 days TTL
        }
        
        # Add additional metadata if available
        if 'sourceIp' in event_data:
            item['sourceIp'] = event_data['sourceIp']
            
        if 'userAgent' in event_data:
            item['userAgent'] = event_data['userAgent']
            
        if 'protocol' in event_data:
            item['protocol'] = event_data['protocol']
        
        # Store in DynamoDB
        table.put_item(Item=item)
        
        logger.info(f"Security event stored successfully: {context.aws_request_id}")
        
    except Exception as e:
        logger.error(f"Failed to store security event in DynamoDB: {str(e)}")
        # Don't fail the entire function if storage fails
        # In production, consider dead letter queue for retry


def analyze_event_patterns(device_id: str) -> Dict[str, Any]:
    """
    Analyze recent event patterns for a specific device (optional enhancement)
    
    Args:
        device_id: Device identifier
        
    Returns:
        Analysis results
    """
    
    table_name = os.environ.get('DYNAMODB_TABLE', '${table_name}')
    
    try:
        table = dynamodb.Table(table_name)
        
        # Query recent events for this device
        response = table.query(
            IndexName='DeviceIndex',
            KeyConditionExpression='deviceId = :device_id',
            ExpressionAttributeValues={
                ':device_id': device_id
            },
            ScanIndexForward=False,  # Get most recent first
            Limit=50
        )
        
        events = response.get('Items', [])
        
        # Basic pattern analysis
        auth_failures = sum(1 for event in events if 'AuthError' in event.get('eventType', ''))
        connection_attempts = sum(1 for event in events if 'Connect' in event.get('eventType', ''))
        
        analysis = {
            'deviceId': device_id,
            'totalEvents': len(events),
            'authFailures': auth_failures,
            'connectionAttempts': connection_attempts,
            'riskScore': calculate_risk_score(auth_failures, connection_attempts, len(events))
        }
        
        return analysis
        
    except Exception as e:
        logger.error(f"Failed to analyze event patterns: {str(e)}")
        return {'error': str(e)}


def calculate_risk_score(auth_failures: int, connection_attempts: int, total_events: int) -> str:
    """
    Calculate a simple risk score based on event patterns
    
    Args:
        auth_failures: Number of authentication failures
        connection_attempts: Number of connection attempts
        total_events: Total number of events
        
    Returns:
        Risk level string
    """
    
    if auth_failures > 10 or (auth_failures > 0 and auth_failures / max(connection_attempts, 1) > 0.5):
        return "HIGH"
    elif auth_failures > 3 or total_events > 100:
        return "MEDIUM"
    else:
        return "LOW"


# Additional utility functions for production use

def quarantine_device(device_id: str) -> bool:
    """
    Quarantine a device by applying restrictive policies (production implementation)
    
    Args:
        device_id: Device identifier
        
    Returns:
        Success status
    """
    
    try:
        iot_client = boto3.client('iot')
        
        # This would implement the quarantine logic from the recipe
        # For now, just log the action
        logger.warning(f"Device quarantine requested for: {device_id}")
        
        # In production, implement:
        # 1. Get device certificates
        # 2. Detach current policies
        # 3. Attach quarantine policy
        # 4. Notify security team
        
        return True
        
    except Exception as e:
        logger.error(f"Failed to quarantine device {device_id}: {str(e)}")
        return False


def send_security_alert(event_type: str, device_id: str, details: Dict[str, Any]) -> None:
    """
    Send security alert via SNS (production implementation)
    
    Args:
        event_type: Type of security event
        device_id: Device identifier
        details: Additional event details
    """
    
    try:
        sns_client = boto3.client('sns')
        topic_arn = os.environ.get('SNS_TOPIC_ARN')
        
        if topic_arn:
            message = {
                'eventType': event_type,
                'deviceId': device_id,
                'timestamp': datetime.utcnow().isoformat(),
                'details': details
            }
            
            sns_client.publish(
                TopicArn=topic_arn,
                Message=json.dumps(message, default=str),
                Subject=f"IoT Security Alert: {event_type} for device {device_id}"
            )
            
            logger.info(f"Security alert sent for device: {device_id}")
            
    except Exception as e:
        logger.error(f"Failed to send security alert: {str(e)}")