import json
import boto3
import logging
import os
import re
from datetime import datetime
from typing import Dict, Any, List

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

# Initialize AWS clients
sns = boto3.client('sns')
s3 = boto3.client('s3')

# Environment variables
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN', '${sns_topic_arn}')
S3_BUCKET_NAME = os.environ.get('S3_BUCKET_NAME')
SECURITY_LOG_PREFIX = os.environ.get('SECURITY_LOG_PREFIX', 'security-logs')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for processing security events from AppFabric.
    
    This function processes security events triggered by S3 object creation
    from AppFabric ingestion and generates intelligent alerts based on
    threat detection logic.
    
    Args:
        event: Lambda event payload containing EventBridge or S3 events
        context: Lambda runtime context
        
    Returns:
        Response dictionary with status and processing results
    """
    
    try:
        logger.info(f"Processing security event: {json.dumps(event, default=str)}")
        
        # Initialize processing counters
        processed_events = 0
        alerts_generated = 0
        
        # Handle EventBridge events from S3
        if 'detail' in event and event.get('source') == 'aws.s3':
            processed_events += 1
            alerts_generated += process_s3_security_event(event)
            
        # Handle direct S3 events (fallback)
        elif 'Records' in event:
            for record in event['Records']:
                if record.get('eventSource') == 'aws:s3':
                    processed_events += 1
                    alerts_generated += process_s3_security_log(record)
        
        # Handle custom EventBridge events
        elif 'source' in event and event['source'] != 'aws.s3':
            processed_events += 1
            alerts_generated += process_custom_security_event(event)
            
        else:
            logger.warning(f"Unhandled event format: {event.keys()}")
        
        logger.info(f"Processing complete: {processed_events} events processed, {alerts_generated} alerts generated")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Security events processed successfully',
                'processed_events': processed_events,
                'alerts_generated': alerts_generated
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing security event: {str(e)}", exc_info=True)
        
        # Send error alert
        error_alert = create_alert_message(
            alert_type='PROCESSING_ERROR',
            severity='HIGH',
            message=f"Lambda function error: {str(e)}",
            additional_data={'event': event}
        )
        send_security_alert(error_alert)
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Failed to process security event',
                'message': str(e)
            })
        }

def process_s3_security_event(event: Dict[str, Any]) -> int:
    """
    Process S3 security events from EventBridge.
    
    Args:
        event: EventBridge event containing S3 object details
        
    Returns:
        Number of alerts generated (0 or 1)
    """
    
    try:
        detail = event.get('detail', {})
        bucket_name = detail.get('bucket', {}).get('name', '')
        object_key = detail.get('object', {}).get('key', '')
        
        logger.info(f"Processing S3 event: s3://{bucket_name}/{object_key}")
        
        # Extract application information from S3 key
        app_info = extract_application_info(object_key)
        
        # Analyze the security log file
        security_analysis = analyze_security_log_file(bucket_name, object_key)
        
        # Determine if alert is needed based on analysis
        if should_generate_alert(security_analysis, app_info):
            alert_message = create_alert_message(
                alert_type='NEW_SECURITY_LOG',
                severity=determine_alert_severity(security_analysis),
                message=f"New security log processed from {app_info['application']}",
                additional_data={
                    's3_location': f"s3://{bucket_name}/{object_key}",
                    'application': app_info['application'],
                    'log_analysis': security_analysis,
                    'timestamp': datetime.utcnow().isoformat()
                }
            )
            
            send_security_alert(alert_message)
            return 1
            
        logger.info("No alert generated - normal security log processing")
        return 0
        
    except Exception as e:
        logger.error(f"Error processing S3 security event: {str(e)}")
        return 0

def process_s3_security_log(record: Dict[str, Any]) -> int:
    """
    Process S3 security logs from direct S3 events (fallback handler).
    
    Args:
        record: S3 event record
        
    Returns:
        Number of alerts generated (0 or 1)
    """
    
    try:
        bucket = record['s3']['bucket']['name']
        key = record['s3']['object']['key']
        
        logger.info(f"Processing S3 log file: s3://{bucket}/{key}")
        
        # Extract application name from S3 key path
        app_name = extract_application_name(key)
        
        # Generate informational alert for new security log
        alert_message = create_alert_message(
            alert_type='NEW_SECURITY_LOG',
            severity='INFO',
            message=f"New security log received from {app_name}",
            additional_data={
                's3_location': f"s3://{bucket}/{key}",
                'application': app_name,
                'timestamp': datetime.utcnow().isoformat()
            }
        )
        
        send_security_alert(alert_message)
        return 1
        
    except Exception as e:
        logger.error(f"Error processing S3 security log: {str(e)}")
        return 0

def process_custom_security_event(event: Dict[str, Any]) -> int:
    """
    Process custom security events from EventBridge.
    
    Args:
        event: Custom EventBridge security event
        
    Returns:
        Number of alerts generated (0 or 1)
    """
    
    try:
        event_type = event.get('detail-type', 'Unknown')
        source = event.get('source', 'Unknown')
        detail = event.get('detail', {})
        
        logger.info(f"Processing custom event: {event_type} from {source}")
        
        # Apply threat detection logic
        threat_analysis = analyze_security_event(event)
        
        if threat_analysis['is_suspicious']:
            alert_message = create_alert_message(
                alert_type='SUSPICIOUS_ACTIVITY',
                severity=threat_analysis['severity'],
                message=threat_analysis['description'],
                additional_data={
                    'event_type': event_type,
                    'source': source,
                    'threat_indicators': threat_analysis['indicators'],
                    'details': detail,
                    'timestamp': datetime.utcnow().isoformat()
                }
            )
            
            send_security_alert(alert_message)
            return 1
            
        return 0
        
    except Exception as e:
        logger.error(f"Error processing custom security event: {str(e)}")
        return 0

def analyze_security_log_file(bucket_name: str, object_key: str) -> Dict[str, Any]:
    """
    Analyze security log file for threat indicators.
    
    Args:
        bucket_name: S3 bucket name
        object_key: S3 object key
        
    Returns:
        Dictionary containing security analysis results
    """
    
    try:
        # Download and analyze log file content
        response = s3.get_object(Bucket=bucket_name, Key=object_key)
        log_content = response['Body'].read().decode('utf-8')
        
        # Parse JSON log entries
        log_entries = []
        for line in log_content.strip().split('\n'):
            if line.strip():
                try:
                    log_entries.append(json.loads(line))
                except json.JSONDecodeError:
                    logger.warning(f"Failed to parse log line: {line[:100]}...")
        
        # Analyze log entries for security indicators
        analysis = {
            'total_entries': len(log_entries),
            'failed_logins': 0,
            'suspicious_activities': [],
            'high_risk_events': 0,
            'unique_users': set(),
            'unique_ips': set()
        }
        
        for entry in log_entries:
            # Extract common OCSF fields
            activity_name = entry.get('activity_name', '').lower()
            severity = entry.get('severity_id', 1)
            user_name = entry.get('actor', {}).get('user', {}).get('name', '')
            src_ip = entry.get('src_endpoint', {}).get('ip', '')
            
            if user_name:
                analysis['unique_users'].add(user_name)
            if src_ip:
                analysis['unique_ips'].add(src_ip)
            
            # Detect security events
            if 'login' in activity_name and 'fail' in activity_name:
                analysis['failed_logins'] += 1
                
            if severity >= 4:  # High severity events
                analysis['high_risk_events'] += 1
                
            # Check for suspicious patterns
            if is_suspicious_log_entry(entry):
                analysis['suspicious_activities'].append({
                    'activity': activity_name,
                    'user': user_name,
                    'ip': src_ip,
                    'timestamp': entry.get('time')
                })
        
        # Convert sets to counts for JSON serialization
        analysis['unique_users'] = len(analysis['unique_users'])
        analysis['unique_ips'] = len(analysis['unique_ips'])
        
        return analysis
        
    except Exception as e:
        logger.error(f"Error analyzing log file s3://{bucket_name}/{object_key}: {str(e)}")
        return {
            'error': str(e),
            'total_entries': 0,
            'analysis_failed': True
        }

def is_suspicious_log_entry(entry: Dict[str, Any]) -> bool:
    """
    Determine if a log entry contains suspicious activity indicators.
    
    Args:
        entry: Individual log entry dictionary
        
    Returns:
        Boolean indicating if entry is suspicious
    """
    
    # Define suspicious activity patterns
    suspicious_keywords = [
        'privilege_escalation',
        'unauthorized_access',
        'brute_force',
        'data_exfiltration',
        'malware',
        'suspicious_login',
        'account_takeover'
    ]
    
    # Convert entry to lowercase string for pattern matching
    entry_text = json.dumps(entry).lower()
    
    # Check for suspicious keywords
    for keyword in suspicious_keywords:
        if keyword in entry_text:
            return True
    
    # Check for high-risk activity IDs (OCSF standard)
    high_risk_activities = [3005, 3006, 4001, 4002]  # Example OCSF activity IDs
    if entry.get('activity_id') in high_risk_activities:
        return True
    
    # Check for multiple failed attempts from same source
    if (entry.get('activity_name', '').lower().find('fail') != -1 and
        entry.get('src_endpoint', {}).get('ip')):
        return True
    
    return False

def analyze_security_event(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Analyze custom security events for threat patterns.
    
    Args:
        event: EventBridge security event
        
    Returns:
        Dictionary containing threat analysis results
    """
    
    detail = event.get('detail', {})
    event_text = json.dumps(detail).lower()
    
    # Define threat indicators
    threat_indicators = []
    severity = 'LOW'
    is_suspicious = False
    
    # High-severity threat patterns
    high_severity_patterns = [
        'failed_login_attempt',
        'privilege_escalation',
        'data_exfiltration',
        'malware_detection',
        'brute_force_attack'
    ]
    
    # Medium-severity patterns
    medium_severity_patterns = [
        'unusual_access_pattern',
        'suspicious_file_access',
        'unauthorized_api_call',
        'multiple_failed_attempts'
    ]
    
    # Check for threat patterns
    for pattern in high_severity_patterns:
        if pattern in event_text:
            threat_indicators.append(pattern)
            severity = 'HIGH'
            is_suspicious = True
    
    if not is_suspicious:
        for pattern in medium_severity_patterns:
            if pattern in event_text:
                threat_indicators.append(pattern)
                severity = 'MEDIUM'
                is_suspicious = True
    
    # Additional analysis based on event metadata
    if detail.get('responseElements', {}).get('errorCode'):
        threat_indicators.append('api_error')
        is_suspicious = True
    
    return {
        'is_suspicious': is_suspicious,
        'severity': severity,
        'indicators': threat_indicators,
        'description': f"Detected {len(threat_indicators)} threat indicators in security event"
    }

def should_generate_alert(analysis: Dict[str, Any], app_info: Dict[str, Any]) -> bool:
    """
    Determine if an alert should be generated based on security analysis.
    
    Args:
        analysis: Security analysis results
        app_info: Application information extracted from log path
        
    Returns:
        Boolean indicating if alert should be generated
    """
    
    # Generate alerts for high-risk scenarios
    if analysis.get('analysis_failed', False):
        return True
        
    if analysis.get('failed_logins', 0) > 5:
        return True
        
    if analysis.get('high_risk_events', 0) > 0:
        return True
        
    if len(analysis.get('suspicious_activities', [])) > 0:
        return True
        
    # Alert for unusual activity patterns
    if (analysis.get('unique_ips', 0) > 10 and 
        analysis.get('total_entries', 0) < 50):
        return True
    
    return False

def determine_alert_severity(analysis: Dict[str, Any]) -> str:
    """
    Determine alert severity based on security analysis.
    
    Args:
        analysis: Security analysis results
        
    Returns:
        Alert severity string (HIGH, MEDIUM, LOW, INFO)
    """
    
    if analysis.get('analysis_failed', False):
        return 'HIGH'
        
    if analysis.get('high_risk_events', 0) > 0:
        return 'HIGH'
        
    if analysis.get('failed_logins', 0) > 10:
        return 'HIGH'
        
    if len(analysis.get('suspicious_activities', [])) > 2:
        return 'MEDIUM'
        
    if analysis.get('failed_logins', 0) > 0:
        return 'MEDIUM'
        
    return 'INFO'

def extract_application_info(s3_key: str) -> Dict[str, str]:
    """
    Extract application information from AppFabric S3 key path.
    
    AppFabric S3 key format: app-bundle-id/app-name/yyyy/mm/dd/hour/file
    
    Args:
        s3_key: S3 object key from AppFabric
        
    Returns:
        Dictionary containing application information
    """
    
    try:
        path_parts = s3_key.split('/')
        
        if len(path_parts) >= 2:
            bundle_id = path_parts[0] if path_parts[0] else 'unknown-bundle'
            app_name = path_parts[1] if path_parts[1] else 'unknown-app'
        else:
            bundle_id = 'unknown-bundle'
            app_name = extract_application_name(s3_key)
        
        return {
            'bundle_id': bundle_id,
            'application': app_name,
            'full_path': s3_key
        }
        
    except Exception as e:
        logger.error(f"Error extracting app info from key {s3_key}: {str(e)}")
        return {
            'bundle_id': 'unknown-bundle',
            'application': 'unknown-app',
            'full_path': s3_key
        }

def extract_application_name(s3_key: str) -> str:
    """
    Extract application name from S3 key path (fallback method).
    
    Args:
        s3_key: S3 object key
        
    Returns:
        Application name string
    """
    
    # Try to extract from common patterns
    key_lower = s3_key.lower()
    
    if 'slack' in key_lower:
        return 'Slack'
    elif 'microsoft' in key_lower or 'office' in key_lower or '365' in key_lower:
        return 'Microsoft 365'
    elif 'salesforce' in key_lower:
        return 'Salesforce'
    elif 'okta' in key_lower:
        return 'Okta'
    elif 'google' in key_lower:
        return 'Google Workspace'
    else:
        # Extract from path structure
        path_parts = s3_key.split('/')
        if len(path_parts) > 1:
            return path_parts[1].replace('-', ' ').title()
        else:
            return 'Unknown Application'

def create_alert_message(alert_type: str, severity: str, message: str, 
                        additional_data: Dict[str, Any] = None) -> Dict[str, Any]:
    """
    Create standardized alert message structure.
    
    Args:
        alert_type: Type of security alert
        severity: Alert severity level
        message: Alert message description
        additional_data: Additional alert context data
        
    Returns:
        Standardized alert message dictionary
    """
    
    alert = {
        'alert_id': f"{alert_type}_{int(datetime.utcnow().timestamp())}",
        'alert_type': alert_type,
        'severity': severity,
        'message': message,
        'timestamp': datetime.utcnow().isoformat(),
        'source': 'aws-appfabric-security-monitor'
    }
    
    if additional_data:
        alert.update(additional_data)
    
    return alert

def send_security_alert(alert_message: Dict[str, Any]) -> bool:
    """
    Send security alert via SNS with multiple message formats.
    
    Args:
        alert_message: Security alert message dictionary
        
    Returns:
        Boolean indicating successful message sending
    """
    
    try:
        # Prepare multi-format message for SNS
        message = {
            'default': json.dumps(alert_message, indent=2, default=str),
            'email': format_email_alert(alert_message),
            'sms': format_sms_alert(alert_message)
        }
        
        # Send message via SNS
        response = sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Message=json.dumps(message, default=str),
            MessageStructure='json',
            Subject=f"🚨 Security Alert: {alert_message['alert_type']} ({alert_message['severity']})"
        )
        
        logger.info(f"Security alert sent successfully: {alert_message['alert_id']}")
        logger.debug(f"SNS response: {response}")
        
        return True
        
    except Exception as e:
        logger.error(f"Failed to send security alert: {str(e)}")
        return False

def format_email_alert(alert: Dict[str, Any]) -> str:
    """
    Format security alert for email delivery.
    
    Args:
        alert: Security alert dictionary
        
    Returns:
        Formatted email message string
    """
    
    email_body = f"""
🚨 SECURITY ALERT: {alert['alert_type']}

Severity: {alert['severity']}
Timestamp: {alert['timestamp']}
Alert ID: {alert.get('alert_id', 'N/A')}

Message: {alert['message']}

Application: {alert.get('application', 'N/A')}
Source: {alert.get('source', 'N/A')}
"""
    
    # Add additional details if available
    if 's3_location' in alert:
        email_body += f"\nS3 Location: {alert['s3_location']}"
        
    if 'log_analysis' in alert:
        analysis = alert['log_analysis']
        email_body += f"""
        
Security Analysis:
- Total Log Entries: {analysis.get('total_entries', 0)}
- Failed Logins: {analysis.get('failed_logins', 0)}
- High Risk Events: {analysis.get('high_risk_events', 0)}
- Unique Users: {analysis.get('unique_users', 0)}
- Unique IPs: {analysis.get('unique_ips', 0)}
- Suspicious Activities: {len(analysis.get('suspicious_activities', []))}
"""
    
    if 'threat_indicators' in alert:
        email_body += f"\nThreat Indicators: {', '.join(alert['threat_indicators'])}"
    
    email_body += "\n\nThis is an automated security alert from your SaaS monitoring system."
    email_body += "\nPlease investigate this alert promptly and take appropriate action."
    
    return email_body

def format_sms_alert(alert: Dict[str, Any]) -> str:
    """
    Format security alert for SMS delivery.
    
    Args:
        alert: Security alert dictionary
        
    Returns:
        Formatted SMS message string (under 160 characters)
    """
    
    app_name = alert.get('application', 'Unknown')
    severity = alert['severity']
    alert_type = alert['alert_type'].replace('_', ' ')
    
    return f"SECURITY ALERT: {alert_type} - {severity} severity detected in {app_name} at {alert['timestamp'][:16]}"