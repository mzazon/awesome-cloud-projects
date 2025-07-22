"""
Lambda function for processing DynamoDB stream records in real-time.

This function processes DynamoDB stream events and performs the following actions:
1. Logs stream record processing information
2. Stores audit records in S3 for compliance and analysis
3. Sends notifications via SNS for real-time alerting
4. Handles errors gracefully with comprehensive error logging

Environment Variables:
- SNS_TOPIC_ARN: ARN of the SNS topic for notifications
- S3_BUCKET_NAME: Name of the S3 bucket for storing audit logs
"""

import json
import boto3
import logging
import os
from datetime import datetime
from decimal import Decimal
from typing import Dict, Any, List
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
sns_client = boto3.client('sns')
s3_client = boto3.client('s3')

# Environment variables
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN')
S3_BUCKET_NAME = os.environ.get('S3_BUCKET_NAME')


def decimal_default(obj: Any) -> Any:
    """
    JSON serializer for objects not serializable by default json code.
    
    Args:
        obj: Object to serialize
        
    Returns:
        Serializable representation of the object
        
    Raises:
        TypeError: If object is not serializable
    """
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError(f"Object of type {type(obj)} is not JSON serializable")


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for processing DynamoDB stream records.
    
    Args:
        event: DynamoDB stream event containing records
        context: Lambda runtime context
        
    Returns:
        Response indicating success/failure of processing
    """
    try:
        records = event.get('Records', [])
        logger.info(f"Processing {len(records)} stream records")
        
        if not records:
            logger.warning("No records found in event")
            return {
                'statusCode': 200,
                'body': json.dumps('No records to process')
            }
        
        # Process each record
        processed_count = 0
        for record in records:
            try:
                process_stream_record(record)
                processed_count += 1
            except Exception as e:
                logger.error(f"Failed to process record: {str(e)}")
                # Re-raise to trigger retry mechanism
                raise e
        
        logger.info(f"Successfully processed {processed_count} records")
        return {
            'statusCode': 200,
            'body': json.dumps(f'Successfully processed {processed_count} records')
        }
        
    except Exception as e:
        logger.error(f"Error in lambda_handler: {str(e)}")
        raise e


def process_stream_record(record: Dict[str, Any]) -> None:
    """
    Process a single DynamoDB stream record.
    
    Args:
        record: Individual DynamoDB stream record
    """
    try:
        # Extract basic information from the record
        event_name = record.get('eventName')
        aws_region = record.get('awsRegion')
        event_source = record.get('eventSource')
        
        # Extract DynamoDB specific information
        dynamodb_data = record.get('dynamodb', {})
        keys = dynamodb_data.get('Keys', {})
        
        # Extract primary key values
        user_id = keys.get('UserId', {}).get('S', 'unknown')
        activity_id = keys.get('ActivityId', {}).get('S', 'unknown')
        
        logger.info(f"Processing {event_name} event for user {user_id}, activity {activity_id}")
        
        # Create comprehensive audit record
        audit_record = create_audit_record(record, event_name, user_id, activity_id, aws_region, event_source)
        
        # Store audit record in S3
        store_audit_record(audit_record)
        
        # Send notification based on event type
        send_notification_for_event(event_name, user_id, audit_record)
        
    except Exception as e:
        logger.error(f"Error processing stream record: {str(e)}")
        raise e


def create_audit_record(record: Dict[str, Any], event_name: str, user_id: str, 
                       activity_id: str, aws_region: str, event_source: str) -> Dict[str, Any]:
    """
    Create a comprehensive audit record from the stream record.
    
    Args:
        record: DynamoDB stream record
        event_name: Type of event (INSERT, MODIFY, REMOVE)
        user_id: User ID from the record
        activity_id: Activity ID from the record
        aws_region: AWS region where the event occurred
        event_source: Source of the event
        
    Returns:
        Dictionary containing audit information
    """
    audit_record = {
        'timestamp': datetime.utcnow().isoformat(),
        'eventName': event_name,
        'userId': user_id,
        'activityId': activity_id,
        'awsRegion': aws_region,
        'eventSource': event_source,
        'sequenceNumber': record.get('dynamodb', {}).get('SequenceNumber'),
        'sizeBytes': record.get('dynamodb', {}).get('SizeBytes'),
        'streamViewType': record.get('dynamodb', {}).get('StreamViewType')
    }
    
    # Add old and new images if available
    dynamodb_data = record.get('dynamodb', {})
    if 'OldImage' in dynamodb_data:
        audit_record['oldImage'] = dynamodb_data['OldImage']
    if 'NewImage' in dynamodb_data:
        audit_record['newImage'] = dynamodb_data['NewImage']
    
    return audit_record


def store_audit_record(audit_record: Dict[str, Any]) -> None:
    """
    Store audit record in S3 with hierarchical key structure.
    
    Args:
        audit_record: Audit record to store
    """
    try:
        if not S3_BUCKET_NAME:
            logger.error("S3_BUCKET_NAME environment variable not set")
            return
            
        # Generate hierarchical S3 key based on timestamp
        timestamp = datetime.utcnow()
        s3_key = f"audit-logs/{timestamp.strftime('%Y/%m/%d/%H')}/{audit_record['userId']}-{audit_record['activityId']}-{timestamp.strftime('%Y%m%d%H%M%S')}.json"
        
        # Convert audit record to JSON
        audit_json = json.dumps(audit_record, default=decimal_default, indent=2)
        
        # Store in S3 with metadata
        s3_client.put_object(
            Bucket=S3_BUCKET_NAME,
            Key=s3_key,
            Body=audit_json,
            ContentType='application/json',
            Metadata={
                'eventName': audit_record['eventName'],
                'userId': audit_record['userId'],
                'activityId': audit_record['activityId'],
                'timestamp': audit_record['timestamp']
            }
        )
        
        logger.info(f"Audit record stored: s3://{S3_BUCKET_NAME}/{s3_key}")
        
    except ClientError as e:
        logger.error(f"Failed to store audit record in S3: {str(e)}")
        raise e
    except Exception as e:
        logger.error(f"Unexpected error storing audit record: {str(e)}")
        raise e


def send_notification_for_event(event_name: str, user_id: str, audit_record: Dict[str, Any]) -> None:
    """
    Send SNS notification based on the event type.
    
    Args:
        event_name: Type of DynamoDB event
        user_id: User ID associated with the event
        audit_record: Complete audit record for context
    """
    try:
        if not SNS_TOPIC_ARN:
            logger.error("SNS_TOPIC_ARN environment variable not set")
            return
            
        # Create event-specific message
        if event_name == 'INSERT':
            message = f"New activity created for user {user_id}"
            subject = f"DynamoDB Activity: New Record Created"
        elif event_name == 'MODIFY':
            message = f"Activity updated for user {user_id}"
            subject = f"DynamoDB Activity: Record Modified"
        elif event_name == 'REMOVE':
            message = f"Activity deleted for user {user_id}"
            subject = f"DynamoDB Activity: Record Removed"
        else:
            message = f"Unknown event type {event_name} for user {user_id}"
            subject = f"DynamoDB Activity: Unknown Event"
        
        # Create detailed notification payload
        notification_payload = {
            'message': message,
            'details': {
                'eventName': audit_record['eventName'],
                'userId': audit_record['userId'],
                'activityId': audit_record['activityId'],
                'timestamp': audit_record['timestamp'],
                'awsRegion': audit_record['awsRegion']
            }
        }
        
        # Send SNS notification
        sns_client.publish(
            TopicArn=SNS_TOPIC_ARN,
            Message=json.dumps(notification_payload, default=decimal_default, indent=2),
            Subject=subject
        )
        
        logger.info(f"Notification sent: {message}")
        
    except ClientError as e:
        logger.error(f"Failed to send SNS notification: {str(e)}")
        raise e
    except Exception as e:
        logger.error(f"Unexpected error sending notification: {str(e)}")
        raise e


def get_attribute_value(attribute: Dict[str, Any]) -> Any:
    """
    Extract value from DynamoDB attribute format.
    
    Args:
        attribute: DynamoDB attribute dictionary
        
    Returns:
        Extracted value
    """
    if 'S' in attribute:
        return attribute['S']
    elif 'N' in attribute:
        return Decimal(attribute['N'])
    elif 'B' in attribute:
        return attribute['B']
    elif 'SS' in attribute:
        return attribute['SS']
    elif 'NS' in attribute:
        return [Decimal(n) for n in attribute['NS']]
    elif 'BS' in attribute:
        return attribute['BS']
    elif 'M' in attribute:
        return {k: get_attribute_value(v) for k, v in attribute['M'].items()}
    elif 'L' in attribute:
        return [get_attribute_value(v) for v in attribute['L']]
    elif 'NULL' in attribute:
        return None
    elif 'BOOL' in attribute:
        return attribute['BOOL']
    else:
        return str(attribute)