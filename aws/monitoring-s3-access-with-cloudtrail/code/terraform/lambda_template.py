import json
import boto3
import logging
from datetime import datetime
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Lambda function for advanced S3 security monitoring and analysis.
    
    This function analyzes CloudTrail events for suspicious S3 activities and sends
    alerts when potential security threats are detected.
    """
    try:
        logger.info(f"Received event: {json.dumps(event, indent=2)}")
        
        # Process EventBridge event
        if 'source' in event and event['source'] == 'aws.s3':
            analyze_s3_event(event['detail'])
        
        # Process CloudWatch Logs event
        elif 'awslogs' in event:
            process_cloudwatch_logs(event)
        
        # Process direct CloudTrail event
        elif 'Records' in event:
            for record in event['Records']:
                if 'eventSource' in record and record['eventSource'] == 's3.amazonaws.com':
                    analyze_s3_event(record)
        
        return {
            'statusCode': 200,
            'body': json.dumps('Security monitoring completed successfully')
        }
        
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        logger.error(f"Event: {json.dumps(event, indent=2)}")
        raise

def analyze_s3_event(event_detail):
    """
    Analyze S3 event for suspicious patterns and security threats.
    """
    try:
        event_name = event_detail.get('eventName', '')
        source_ip = event_detail.get('sourceIPAddress', '')
        user_identity = event_detail.get('userIdentity', {})
        event_time = event_detail.get('eventTime', '')
        aws_region = event_detail.get('awsRegion', '')
        resources = event_detail.get('resources', [])
        
        logger.info(f"Analyzing S3 event: {event_name} from {source_ip}")
        
        # Analyze for suspicious patterns
        threat_level = analyze_threat_level(event_name, source_ip, user_identity, event_detail)
        
        if threat_level > 0:
            send_security_alert(event_detail, threat_level)
            
        # Log the analysis
        log_security_analysis(event_detail, threat_level)
        
    except Exception as e:
        logger.error(f"Error analyzing S3 event: {str(e)}")
        raise

def analyze_threat_level(event_name, source_ip, user_identity, event_detail):
    """
    Analyze the threat level of an S3 event based on various security indicators.
    Returns: 0 = No threat, 1 = Low, 2 = Medium, 3 = High, 4 = Critical
    """
    threat_level = 0
    threat_indicators = []
    
    # High-risk administrative actions
    high_risk_actions = [
        'DeleteBucket', 'PutBucketPolicy', 'PutBucketAcl', 'PutBucketEncryption',
        'PutBucketPublicAccessBlock', 'DeleteBucketPolicy', 'PutBucketCors'
    ]
    
    # Medium-risk data operations
    medium_risk_actions = [
        'DeleteObject', 'PutObjectAcl', 'RestoreObject'
    ]
    
    # Check for high-risk administrative actions
    if event_name in high_risk_actions:
        threat_level = max(threat_level, 3)
        threat_indicators.append(f"High-risk administrative action: {event_name}")
    
    # Check for medium-risk data operations
    elif event_name in medium_risk_actions:
        threat_level = max(threat_level, 2)
        threat_indicators.append(f"Medium-risk data operation: {event_name}")
    
    # Check for error codes indicating unauthorized access
    error_code = event_detail.get('errorCode', '')
    if error_code in ['AccessDenied', 'SignatureDoesNotMatch', 'InvalidUserID.NotFound']:
        threat_level = max(threat_level, 2)
        threat_indicators.append(f"Unauthorized access attempt: {error_code}")
    
    # Check for suspicious source IP patterns
    if source_ip:
        if is_suspicious_ip(source_ip):
            threat_level = max(threat_level, 2)
            threat_indicators.append(f"Suspicious source IP: {source_ip}")
    
    # Check for unusual user identity patterns
    user_type = user_identity.get('type', '')
    if user_type == 'Root':
        threat_level = max(threat_level, 1)
        threat_indicators.append("Root user access detected")
    
    # Check for unusual timing patterns (e.g., access outside business hours)
    if is_unusual_timing(event_detail.get('eventTime', '')):
        threat_level = max(threat_level, 1)
        threat_indicators.append("Access outside normal business hours")
    
    # Check for bulk operations that might indicate data exfiltration
    if is_bulk_operation(event_name, event_detail):
        threat_level = max(threat_level, 2)
        threat_indicators.append("Potential bulk data operation detected")
    
    # Log threat indicators
    if threat_indicators:
        logger.info(f"Threat indicators found: {threat_indicators}")
    
    return threat_level

def is_suspicious_ip(ip_address):
    """
    Check if the IP address is from a suspicious location or known threat source.
    This is a simplified implementation - in production, you might integrate with
    threat intelligence feeds or GeoIP databases.
    """
    # Check for access from non-corporate IP ranges
    # This is a simplified check - customize based on your environment
    corporate_ip_prefixes = ['10.', '172.16.', '192.168.']
    
    # Check if IP is from corporate network
    if any(ip_address.startswith(prefix) for prefix in corporate_ip_prefixes):
        return False
    
    # Check for known cloud provider IP ranges (you might want to maintain a whitelist)
    cloud_prefixes = ['aws.', 'amazon.', 'cloudfront.']
    if any(prefix in ip_address for prefix in cloud_prefixes):
        return False
    
    # Flag external IPs for review
    return True

def is_unusual_timing(event_time):
    """
    Check if the event occurred outside normal business hours.
    """
    try:
        if not event_time:
            return False
        
        # Parse the event time
        event_dt = datetime.fromisoformat(event_time.replace('Z', '+00:00'))
        
        # Check if it's outside business hours (9 AM - 6 PM UTC)
        # Customize this based on your organization's schedule
        if event_dt.hour < 9 or event_dt.hour > 18:
            return True
        
        # Check if it's a weekend
        if event_dt.weekday() >= 5:  # Saturday = 5, Sunday = 6
            return True
        
        return False
        
    except Exception as e:
        logger.error(f"Error parsing event time: {str(e)}")
        return False

def is_bulk_operation(event_name, event_detail):
    """
    Detect patterns that might indicate bulk data operations.
    """
    # This is a simplified implementation
    # In production, you might track operation frequency over time
    
    bulk_indicators = [
        'GetObject' in event_name and 'batch' in str(event_detail).lower(),
        'PutObject' in event_name and 'batch' in str(event_detail).lower(),
        'CopyObject' in event_name
    ]
    
    return any(bulk_indicators)

def send_security_alert(event_detail, threat_level):
    """
    Send security alert via SNS based on threat level.
    """
    try:
        sns_topic_arn = os.environ.get('SNS_TOPIC_ARN', '${sns_topic_arn}')
        
        if not sns_topic_arn or sns_topic_arn == '${sns_topic_arn}':
            logger.warning("SNS topic ARN not configured, skipping alert")
            return
        
        sns = boto3.client('sns')
        
        # Determine threat level description
        threat_levels = {
            1: "LOW",
            2: "MEDIUM", 
            3: "HIGH",
            4: "CRITICAL"
        }
        
        threat_description = threat_levels.get(threat_level, "UNKNOWN")
        
        # Build alert message
        subject = f"S3 Security Alert - {threat_description} Threat Detected"
        
        message = f"""
SECURITY ALERT - S3 Activity Monitoring

Threat Level: {threat_description}
Event Name: {event_detail.get('eventName', 'Unknown')}
Source IP: {event_detail.get('sourceIPAddress', 'Unknown')}
User Identity: {event_detail.get('userIdentity', {}).get('type', 'Unknown')}
Event Time: {event_detail.get('eventTime', 'Unknown')}
AWS Region: {event_detail.get('awsRegion', 'Unknown')}
Error Code: {event_detail.get('errorCode', 'None')}

Resources Affected:
{json.dumps(event_detail.get('resources', []), indent=2)}

Request Parameters:
{json.dumps(event_detail.get('requestParameters', {}), indent=2)}

Response Elements:
{json.dumps(event_detail.get('responseElements', {}), indent=2)}

Event ID: {event_detail.get('eventID', 'Unknown')}

Please investigate this activity immediately.

This alert was generated by the S3 Security Monitoring system.
        """
        
        # Send SNS notification
        response = sns.publish(
            TopicArn=sns_topic_arn,
            Subject=subject,
            Message=message
        )
        
        logger.info(f"Security alert sent successfully: {response['MessageId']}")
        
    except Exception as e:
        logger.error(f"Error sending security alert: {str(e)}")
        raise

def log_security_analysis(event_detail, threat_level):
    """
    Log security analysis results for audit and forensic purposes.
    """
    analysis_log = {
        'timestamp': datetime.utcnow().isoformat(),
        'event_id': event_detail.get('eventID', 'Unknown'),
        'event_name': event_detail.get('eventName', 'Unknown'),
        'source_ip': event_detail.get('sourceIPAddress', 'Unknown'),
        'user_identity': event_detail.get('userIdentity', {}),
        'threat_level': threat_level,
        'aws_region': event_detail.get('awsRegion', 'Unknown'),
        'error_code': event_detail.get('errorCode', 'None'),
        'resources': event_detail.get('resources', [])
    }
    
    logger.info(f"Security analysis completed: {json.dumps(analysis_log, indent=2)}")

def process_cloudwatch_logs(event):
    """
    Process CloudWatch Logs event if needed.
    """
    try:
        # Decode CloudWatch Logs data
        import gzip
        import base64
        
        cw_data = event['awslogs']['data']
        cw_logs = json.loads(gzip.decompress(base64.b64decode(cw_data)))
        
        for log_event in cw_logs['logEvents']:
            # Parse the log event as JSON (CloudTrail format)
            try:
                log_data = json.loads(log_event['message'])
                if log_data.get('eventSource') == 's3.amazonaws.com':
                    analyze_s3_event(log_data)
            except json.JSONDecodeError:
                # Skip non-JSON log events
                continue
                
    except Exception as e:
        logger.error(f"Error processing CloudWatch Logs: {str(e)}")
        raise