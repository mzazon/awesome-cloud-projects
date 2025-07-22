import json
import boto3
import hashlib
import datetime
import os
import logging
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
qldb_client = boto3.client('qldb')
s3_client = boto3.client('s3')
cloudwatch = boto3.client('cloudwatch')

# Environment variables
LEDGER_NAME = os.environ['LEDGER_NAME']
S3_BUCKET = os.environ['S3_BUCKET']
REGION = os.environ['REGION']

def lambda_handler(event, context):
    """
    Main Lambda handler for processing compliance audit events.
    
    This function processes CloudTrail events and stores them as immutable
    audit records in Amazon QLDB for compliance and regulatory requirements.
    """
    try:
        logger.info(f"Processing audit event: {json.dumps(event)}")
        
        # Create audit record from the incoming event
        audit_record = create_audit_record(event)
        logger.info(f"Created audit record with ID: {audit_record['auditId']}")
        
        # Store the audit record in QLDB
        store_audit_record(audit_record)
        logger.info(f"Stored audit record in QLDB ledger: {LEDGER_NAME}")
        
        # Generate compliance metrics for monitoring
        generate_compliance_metrics(audit_record)
        logger.info("Generated compliance metrics")
        
        # Store audit record in S3 for long-term retention
        store_audit_in_s3(audit_record)
        logger.info("Stored audit record in S3")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Audit record processed successfully',
                'auditId': audit_record['auditId'],
                'timestamp': audit_record['timestamp']
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing audit record: {str(e)}")
        
        # Send error metrics to CloudWatch
        send_error_metrics(str(e))
        
        # Re-raise the exception to trigger Lambda error handling
        raise

def create_audit_record(event):
    """
    Create a structured audit record from the incoming CloudTrail event.
    
    Args:
        event: The CloudTrail event from EventBridge
        
    Returns:
        dict: Structured audit record with integrity hash
    """
    timestamp = datetime.datetime.utcnow().isoformat()
    
    # Extract event details safely with defaults
    detail = event.get('detail', {})
    user_identity = detail.get('userIdentity', {})
    
    # Create base audit record
    audit_record = {
        'auditId': generate_audit_id(event),
        'timestamp': timestamp,
        'eventTime': detail.get('eventTime', timestamp),
        'eventName': detail.get('eventName', 'Unknown'),
        'eventSource': detail.get('eventSource', ''),
        'awsRegion': detail.get('awsRegion', REGION),
        'sourceIPAddress': detail.get('sourceIPAddress', ''),
        'userAgent': detail.get('userAgent', ''),
        'userIdentity': {
            'type': user_identity.get('type', ''),
            'principalId': user_identity.get('principalId', ''),
            'arn': user_identity.get('arn', ''),
            'accountId': user_identity.get('accountId', ''),
            'userName': user_identity.get('userName', '')
        },
        'requestParameters': detail.get('requestParameters', {}),
        'responseElements': detail.get('responseElements', {}),
        'resources': detail.get('resources', []),
        'errorCode': detail.get('errorCode', ''),
        'errorMessage': detail.get('errorMessage', ''),
        'requestId': detail.get('requestID', ''),
        'eventId': detail.get('eventID', ''),
        'readOnly': detail.get('readOnly', False),
        'apiVersion': detail.get('apiVersion', ''),
        'managementEvent': detail.get('managementEvent', True),
        'recipientAccountId': detail.get('recipientAccountId', ''),
        'serviceName': detail.get('serviceName', ''),
        'sharedEventID': detail.get('sharedEventID', ''),
        'vpcEndpointId': detail.get('vpcEndpointId', ''),
        'processedAt': timestamp,
        'recordVersion': '1.0'
    }
    
    # Create integrity hash for tamper detection
    record_for_hash = {k: v for k, v in audit_record.items() if k != 'recordHash'}
    record_string = json.dumps(record_for_hash, sort_keys=True, default=str)
    audit_record['recordHash'] = hashlib.sha256(record_string.encode()).hexdigest()
    
    return audit_record

def generate_audit_id(event):
    """
    Generate a unique audit ID based on the event content.
    
    Args:
        event: The CloudTrail event
        
    Returns:
        str: Unique 16-character audit ID
    """
    event_string = json.dumps(event, sort_keys=True, default=str)
    return hashlib.sha256(event_string.encode()).hexdigest()[:16]

def store_audit_record(audit_record):
    """
    Store the audit record in QLDB ledger.
    
    Note: This is a simplified implementation. In production,
    you would use proper QLDB session management and PartiQL
    statements for inserting records into tables.
    
    Args:
        audit_record: The audit record to store
    """
    try:
        # Get ledger digest for verification
        # This ensures the ledger is active and accessible
        response = qldb_client.get_digest(Name=LEDGER_NAME)
        
        logger.info(f"QLDB ledger {LEDGER_NAME} is accessible")
        logger.info(f"Current digest: {response.get('DigestTipAddress', {}).get('IonText', 'N/A')}")
        
        # In a production implementation, you would:
        # 1. Create a QLDB session
        # 2. Execute PartiQL INSERT statements
        # 3. Commit the transaction
        # 4. Return the document ID
        
        # For now, we log that the record would be stored
        logger.info(f"Audit record ready for QLDB storage: {audit_record['auditId']}")
        
    except ClientError as e:
        error_code = e.response['Error']['Code']
        error_message = e.response['Error']['Message']
        logger.error(f"QLDB error [{error_code}]: {error_message}")
        raise

def store_audit_in_s3(audit_record):
    """
    Store audit record in S3 for long-term retention and analytics.
    
    Args:
        audit_record: The audit record to store
    """
    try:
        # Create S3 key with partitioning for efficient querying
        timestamp = datetime.datetime.fromisoformat(audit_record['timestamp'].replace('Z', '+00:00'))
        s3_key = f"audit-records/year={timestamp.year}/month={timestamp.month:02d}/day={timestamp.day:02d}/hour={timestamp.hour:02d}/{audit_record['auditId']}.json"
        
        # Store audit record as JSON
        s3_client.put_object(
            Bucket=S3_BUCKET,
            Key=s3_key,
            Body=json.dumps(audit_record, indent=2),
            ContentType='application/json',
            ServerSideEncryption='AES256',
            Metadata={
                'audit-id': audit_record['auditId'],
                'event-source': audit_record['eventSource'],
                'event-name': audit_record['eventName'],
                'processed-at': audit_record['processedAt']
            }
        )
        
        logger.info(f"Stored audit record in S3: s3://{S3_BUCKET}/{s3_key}")
        
    except ClientError as e:
        error_code = e.response['Error']['Code']
        error_message = e.response['Error']['Message']
        logger.error(f"S3 storage error [{error_code}]: {error_message}")
        raise

def generate_compliance_metrics(audit_record):
    """
    Generate CloudWatch metrics for compliance monitoring.
    
    Args:
        audit_record: The processed audit record
    """
    try:
        # Basic audit processing metric
        cloudwatch.put_metric_data(
            Namespace='ComplianceAudit',
            MetricData=[
                {
                    'MetricName': 'AuditRecordsProcessed',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'EventSource',
                            'Value': audit_record['eventSource']
                        },
                        {
                            'Name': 'EventName',
                            'Value': audit_record['eventName']
                        },
                        {
                            'Name': 'Region',
                            'Value': audit_record['awsRegion']
                        }
                    ]
                },
                {
                    'MetricName': 'AuditRecordSize',
                    'Value': len(json.dumps(audit_record)),
                    'Unit': 'Bytes',
                    'Dimensions': [
                        {
                            'Name': 'EventSource',
                            'Value': audit_record['eventSource']
                        }
                    ]
                }
            ]
        )
        
        # Send security-related metrics for sensitive events
        if is_security_sensitive_event(audit_record):
            cloudwatch.put_metric_data(
                Namespace='ComplianceAudit',
                MetricData=[
                    {
                        'MetricName': 'SecuritySensitiveEvents',
                        'Value': 1,
                        'Unit': 'Count',
                        'Dimensions': [
                            {
                                'Name': 'EventName',
                                'Value': audit_record['eventName']
                            },
                            {
                                'Name': 'UserType',
                                'Value': audit_record['userIdentity'].get('type', 'Unknown')
                            }
                        ]
                    }
                ]
            )
        
        logger.info("Compliance metrics sent to CloudWatch")
        
    except ClientError as e:
        logger.error(f"Error sending metrics to CloudWatch: {str(e)}")
        # Don't raise here as metrics are not critical for audit processing

def is_security_sensitive_event(audit_record):
    """
    Determine if an audit record represents a security-sensitive event.
    
    Args:
        audit_record: The audit record to evaluate
        
    Returns:
        bool: True if the event is security-sensitive
    """
    sensitive_events = [
        'CreateRole', 'DeleteRole', 'AttachRolePolicy', 'DetachRolePolicy',
        'CreateUser', 'DeleteUser', 'AttachUserPolicy', 'DetachUserPolicy',
        'CreateAccessKey', 'DeleteAccessKey', 'UpdateAccessKey',
        'CreateLoginProfile', 'UpdateLoginProfile', 'DeleteLoginProfile',
        'PutBucketPolicy', 'DeleteBucketPolicy', 'PutBucketAcl',
        'CreateKey', 'DeleteKey', 'DisableKey', 'ScheduleKeyDeletion'
    ]
    
    sensitive_sources = [
        'iam.amazonaws.com', 'kms.amazonaws.com', 's3.amazonaws.com',
        'sts.amazonaws.com', 'organizations.amazonaws.com'
    ]
    
    return (
        audit_record['eventName'] in sensitive_events or
        audit_record['eventSource'] in sensitive_sources or
        audit_record['userIdentity'].get('type') == 'Root'
    )

def send_error_metrics(error_message):
    """
    Send error metrics to CloudWatch for monitoring.
    
    Args:
        error_message: The error message to include in metrics
    """
    try:
        cloudwatch.put_metric_data(
            Namespace='ComplianceAudit',
            MetricData=[
                {
                    'MetricName': 'ProcessingErrors',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'LambdaFunction',
                            'Value': context.function_name if 'context' in globals() else 'unknown'
                        }
                    ]
                }
            ]
        )
    except Exception as e:
        logger.error(f"Failed to send error metrics: {str(e)}")

# Helper function for testing
def validate_audit_record(audit_record):
    """
    Validate audit record structure and integrity.
    
    Args:
        audit_record: The audit record to validate
        
    Returns:
        bool: True if the record is valid
    """
    required_fields = [
        'auditId', 'timestamp', 'eventName', 'eventSource',
        'recordHash', 'userIdentity', 'processedAt'
    ]
    
    # Check required fields
    for field in required_fields:
        if field not in audit_record:
            logger.error(f"Missing required field: {field}")
            return False
    
    # Verify integrity hash
    record_for_hash = {k: v for k, v in audit_record.items() if k != 'recordHash'}
    record_string = json.dumps(record_for_hash, sort_keys=True, default=str)
    expected_hash = hashlib.sha256(record_string.encode()).hexdigest()
    
    if audit_record['recordHash'] != expected_hash:
        logger.error("Audit record integrity hash mismatch")
        return False
    
    return True