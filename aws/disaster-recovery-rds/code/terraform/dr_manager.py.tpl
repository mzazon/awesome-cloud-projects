"""
AWS RDS Disaster Recovery Manager Lambda Function

This function handles automated disaster recovery monitoring and response for RDS databases.
It processes CloudWatch alarms and can initiate appropriate recovery actions.

Environment Variables:
- PRIMARY_TOPIC_ARN: SNS topic ARN for primary region notifications
- SECONDARY_TOPIC_ARN: SNS topic ARN for secondary region notifications
- SOURCE_DB_ID: Source database identifier
- REPLICA_DB_ID: Read replica database identifier
"""

import json
import boto3
import datetime
import os
import logging
from typing import Dict, Any, Optional

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for disaster recovery automation.
    
    Args:
        event: Lambda event containing SNS message
        context: Lambda runtime context
        
    Returns:
        Dict with status code and response body
    """
    try:
        # Parse the SNS event
        logger.info(f"Received event: {json.dumps(event)}")
        
        # Extract SNS message
        if 'Records' not in event or len(event['Records']) == 0:
            logger.warning("No SNS records found in event")
            return create_response(200, "No SNS records to process")
        
        # Process each SNS record
        for record in event['Records']:
            if record.get('EventSource') == 'aws:sns':
                message_body = json.loads(record['Sns']['Message'])
                process_cloudwatch_alarm(message_body)
        
        return create_response(200, "Successfully processed all alarm notifications")
        
    except Exception as e:
        logger.error(f"Error processing disaster recovery event: {str(e)}")
        send_error_notification(str(e))
        return create_response(500, f"Error processing event: {str(e)}")

def process_cloudwatch_alarm(alarm_message: Dict[str, Any]) -> None:
    """
    Process CloudWatch alarm message and take appropriate action.
    
    Args:
        alarm_message: Parsed CloudWatch alarm message
    """
    alarm_name = alarm_message.get('AlarmName', '')
    new_state = alarm_message.get('NewStateValue', '')
    old_state = alarm_message.get('OldStateValue', '')
    reason = alarm_message.get('NewStateReason', '')
    timestamp = alarm_message.get('StateChangeTime', '')
    
    logger.info(f"Processing alarm: {alarm_name}, State: {old_state} -> {new_state}")
    
    # Only process ALARM state transitions
    if new_state != 'ALARM':
        logger.info(f"Alarm {alarm_name} is not in ALARM state, no action needed")
        return
    
    # Route to specific handlers based on alarm type
    if 'HighCPU' in alarm_name:
        handle_high_cpu_alarm(alarm_name, reason, timestamp)
    elif 'ReplicaLag' in alarm_name:
        handle_replica_lag_alarm(alarm_name, reason, timestamp)
    elif 'DatabaseConnections' in alarm_name:
        handle_connection_alarm(alarm_name, reason, timestamp)
    else:
        handle_generic_alarm(alarm_name, new_state, reason, timestamp)

def handle_high_cpu_alarm(alarm_name: str, reason: str, timestamp: str) -> None:
    """
    Handle high CPU utilization alarms.
    
    Args:
        alarm_name: Name of the triggered alarm
        reason: Reason for the alarm state change
        timestamp: When the alarm state changed
    """
    logger.warning(f"High CPU alarm triggered: {alarm_name}")
    
    # Determine if this is primary or replica database
    db_type = "Primary Database" if os.environ['SOURCE_DB_ID'] in alarm_name else "Read Replica"
    
    message = f"""
🚨 HIGH CPU UTILIZATION ALERT

Database: {db_type}
Alarm: {alarm_name}
Time: {timestamp}
Reason: {reason}

Recommended Actions:
1. Review current database workload and active connections
2. Analyze slow query logs for optimization opportunities
3. Consider scaling up the instance if sustained high CPU
4. Monitor for potential cascading effects on other systems

This is an automated alert from the RDS Disaster Recovery system.
    """.strip()
    
    send_notification(
        subject=f"🚨 RDS High CPU Alert - {db_type}",
        message=message,
        urgency="high"
    )

def handle_replica_lag_alarm(alarm_name: str, reason: str, timestamp: str) -> None:
    """
    Handle read replica lag alarms.
    
    Args:
        alarm_name: Name of the triggered alarm
        reason: Reason for the alarm state change
        timestamp: When the alarm state changed
    """
    logger.warning(f"Replica lag alarm triggered: {alarm_name}")
    
    # Get current replica lag metrics
    replica_lag_info = get_replica_lag_metrics()
    
    message = f"""
⚠️ READ REPLICA LAG ALERT

Replica: {os.environ['REPLICA_DB_ID']}
Alarm: {alarm_name}
Time: {timestamp}
Reason: {reason}
Current Lag: {replica_lag_info.get('current_lag', 'Unknown')} seconds

Impact Assessment:
- Read replica may have stale data
- Failover readiness is compromised
- Application read operations may return outdated information

Recommended Actions:
1. Check primary database load and optimize queries
2. Verify network connectivity between regions
3. Monitor primary database performance metrics
4. Consider temporary read traffic reduction
5. Evaluate need for larger replica instance class

This lag may affect disaster recovery capabilities. Monitor closely.
    """.strip()
    
    send_notification(
        subject="⚠️ RDS Replica Lag Alert - DR Capability Impacted",
        message=message,
        urgency="high"
    )

def handle_connection_alarm(alarm_name: str, reason: str, timestamp: str) -> None:
    """
    Handle database connection alarms (potential failover scenario).
    
    Args:
        alarm_name: Name of the triggered alarm
        reason: Reason for the alarm state change
        timestamp: When the alarm state changed
    """
    logger.error(f"Database connection alarm triggered: {alarm_name}")
    
    # Check database status
    db_status = check_database_status(os.environ['SOURCE_DB_ID'])
    
    message = f"""
🔴 CRITICAL DATABASE CONNECTION ALERT

Database: {os.environ['SOURCE_DB_ID']}
Alarm: {alarm_name}
Time: {timestamp}
Reason: {reason}
Database Status: {db_status.get('status', 'Unknown')}

POTENTIAL DISASTER RECOVERY SCENARIO

This alert indicates possible primary database failure or connectivity issues.
Immediate investigation required.

Disaster Recovery Options:
1. Verify primary database health and connectivity
2. Check application connection strings and network paths
3. If primary is unavailable, consider promoting read replica:
   
   aws rds promote-read-replica \\
       --db-instance-identifier {os.environ['REPLICA_DB_ID']} \\
       --region {get_replica_region()}

⚠️ WARNING: Promoting read replica will break replication and requires 
application reconfiguration to point to the new primary database.

Contact the database team immediately for manual intervention.
    """.strip()
    
    send_notification(
        subject="🔴 CRITICAL: RDS Connection Failure - Manual Intervention Required",
        message=message,
        urgency="critical"
    )

def handle_generic_alarm(alarm_name: str, state: str, reason: str, timestamp: str) -> None:
    """
    Handle generic alarm notifications.
    
    Args:
        alarm_name: Name of the triggered alarm
        state: Current alarm state
        reason: Reason for the alarm state change
        timestamp: When the alarm state changed
    """
    logger.info(f"Generic alarm triggered: {alarm_name}")
    
    message = f"""
📊 RDS MONITORING ALERT

Alarm: {alarm_name}
State: {state}
Time: {timestamp}
Reason: {reason}

Please review the CloudWatch dashboard for detailed metrics and trends.
    """.strip()
    
    send_notification(
        subject=f"📊 RDS Monitoring Alert - {alarm_name}",
        message=message,
        urgency="medium"
    )

def get_replica_lag_metrics() -> Dict[str, Any]:
    """
    Get current replica lag metrics from CloudWatch.
    
    Returns:
        Dict containing replica lag information
    """
    try:
        cloudwatch = boto3.client('cloudwatch', region_name=get_replica_region())
        
        response = cloudwatch.get_metric_statistics(
            Namespace='AWS/RDS',
            MetricName='ReplicaLag',
            Dimensions=[
                {
                    'Name': 'DBInstanceIdentifier',
                    'Value': os.environ['REPLICA_DB_ID']
                }
            ],
            StartTime=datetime.datetime.utcnow() - datetime.timedelta(minutes=10),
            EndTime=datetime.datetime.utcnow(),
            Period=300,
            Statistics=['Average']
        )
        
        if response['Datapoints']:
            latest_datapoint = sorted(response['Datapoints'], key=lambda x: x['Timestamp'])[-1]
            return {
                'current_lag': round(latest_datapoint['Average'], 2),
                'timestamp': latest_datapoint['Timestamp'].isoformat()
            }
    except Exception as e:
        logger.error(f"Error getting replica lag metrics: {str(e)}")
    
    return {'current_lag': 'Unknown', 'timestamp': 'Unknown'}

def check_database_status(db_identifier: str) -> Dict[str, Any]:
    """
    Check the current status of a database instance.
    
    Args:
        db_identifier: Database instance identifier
        
    Returns:
        Dict containing database status information
    """
    try:
        rds = boto3.client('rds')
        
        response = rds.describe_db_instances(DBInstanceIdentifier=db_identifier)
        
        if response['DBInstances']:
            db = response['DBInstances'][0]
            return {
                'status': db['DBInstanceStatus'],
                'endpoint': db.get('Endpoint', {}).get('Address', 'Unknown'),
                'engine': db['Engine'],
                'multi_az': db['MultiAZ']
            }
    except Exception as e:
        logger.error(f"Error checking database status: {str(e)}")
    
    return {'status': 'Unknown'}

def send_notification(subject: str, message: str, urgency: str = "medium") -> None:
    """
    Send notification via SNS.
    
    Args:
        subject: Email subject line
        message: Message body
        urgency: Urgency level (low, medium, high, critical)
    """
    try:
        sns = boto3.client('sns')
        
        # Add urgency indicator to subject
        urgency_indicators = {
            "low": "ℹ️",
            "medium": "⚠️", 
            "high": "🚨",
            "critical": "🔴"
        }
        
        formatted_subject = f"{urgency_indicators.get(urgency, '📊')} {subject}"
        
        # Send to primary topic
        sns.publish(
            TopicArn=os.environ['PRIMARY_TOPIC_ARN'],
            Subject=formatted_subject,
            Message=message
        )
        
        logger.info(f"Notification sent successfully: {subject}")
        
    except Exception as e:
        logger.error(f"Error sending notification: {str(e)}")

def send_error_notification(error_message: str) -> None:
    """
    Send error notification when Lambda function fails.
    
    Args:
        error_message: Error message to send
    """
    try:
        message = f"""
🔴 DISASTER RECOVERY LAMBDA ERROR

The RDS Disaster Recovery Lambda function encountered an error and may not be 
processing alarms correctly.

Error: {error_message}
Time: {datetime.datetime.utcnow().isoformat()}
Function: {os.environ.get('AWS_LAMBDA_FUNCTION_NAME', 'Unknown')}

Please check CloudWatch Logs for detailed error information and ensure the 
disaster recovery system is functioning properly.
        """.strip()
        
        send_notification(
            subject="🔴 CRITICAL: DR Lambda Function Error",
            message=message,
            urgency="critical"
        )
    except Exception as e:
        logger.error(f"Failed to send error notification: {str(e)}")

def get_replica_region() -> str:
    """
    Get the region where the read replica is deployed.
    This should be configured based on your deployment.
    
    Returns:
        AWS region name for the read replica
    """
    # This would typically be passed as an environment variable
    # For this template, we'll use a placeholder
    return os.environ.get('REPLICA_REGION', 'us-west-2')

def create_response(status_code: int, message: str) -> Dict[str, Any]:
    """
    Create standardized Lambda response.
    
    Args:
        status_code: HTTP status code
        message: Response message
        
    Returns:
        Formatted Lambda response
    """
    return {
        'statusCode': status_code,
        'body': json.dumps({
            'message': message,
            'timestamp': datetime.datetime.utcnow().isoformat()
        })
    }