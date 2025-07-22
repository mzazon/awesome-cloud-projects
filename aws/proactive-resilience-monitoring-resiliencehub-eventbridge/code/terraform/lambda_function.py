"""
AWS Lambda function for processing Resilience Hub events
This function processes EventBridge events triggered by resilience assessment changes,
analyzes resilience scores, and initiates automated remediation workflows.
"""

import json
import boto3
import logging
import os
from datetime import datetime
from typing import Dict, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.getenv('LOG_LEVEL', 'INFO'))

# Initialize AWS clients
ssm = boto3.client('ssm')
cloudwatch = boto3.client('cloudwatch')
sns = boto3.client('sns')


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for processing Resilience Hub events.
    
    Args:
        event: EventBridge event containing resilience assessment data
        context: Lambda context object
        
    Returns:
        Dictionary containing processing results
    """
    logger.info(f"Received resilience event: {json.dumps(event, default=str)}")
    
    try:
        # Parse EventBridge event data
        event_detail = event.get('detail', {})
        app_name = event_detail.get('applicationName', 'unknown')
        assessment_status = event_detail.get('assessmentStatus', 'UNKNOWN')
        resilience_score = float(event_detail.get('resilienceScore', 0))
        
        # Extract additional event information
        event_source = event.get('source', 'aws.resiliencehub')
        detail_type = event.get('detail-type', 'Unknown')
        event_time = event.get('time', datetime.utcnow().isoformat())
        
        logger.info(f"Processing event for application: {app_name}, "
                   f"status: {assessment_status}, score: {resilience_score}%")
        
        # Send metrics to CloudWatch
        send_resilience_metrics(app_name, assessment_status, resilience_score, event_time)
        
        # Determine and execute appropriate actions based on resilience score
        action_taken = process_resilience_score(
            app_name, resilience_score, assessment_status, context
        )
        
        # Log successful processing
        logger.info(f"Successfully processed resilience event for {app_name}. "
                   f"Action taken: {action_taken}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Event processed successfully',
                'application': app_name,
                'resilience_score': resilience_score,
                'assessment_status': assessment_status,
                'action_taken': action_taken,
                'event_source': event_source,
                'detail_type': detail_type,
                'processing_time': datetime.utcnow().isoformat()
            }, default=str)
        }
        
    except Exception as e:
        logger.error(f"Error processing resilience event: {str(e)}", exc_info=True)
        
        # Send error metrics to CloudWatch
        send_error_metrics(str(e))
        
        # Re-raise the exception to trigger Lambda error handling
        raise e


def send_resilience_metrics(app_name: str, status: str, score: float, event_time: str) -> None:
    """
    Send resilience metrics to CloudWatch.
    
    Args:
        app_name: Name of the application
        status: Assessment status
        score: Resilience score (0-100)
        event_time: ISO timestamp of the event
    """
    try:
        metrics_data = [
            {
                'MetricName': 'ResilienceScore',
                'Dimensions': [
                    {
                        'Name': 'ApplicationName',
                        'Value': app_name
                    }
                ],
                'Value': score,
                'Unit': 'Percent',
                'Timestamp': datetime.fromisoformat(event_time.replace('Z', '+00:00'))
            },
            {
                'MetricName': 'AssessmentEvents',
                'Dimensions': [
                    {
                        'Name': 'ApplicationName',
                        'Value': app_name
                    },
                    {
                        'Name': 'Status',
                        'Value': status
                    }
                ],
                'Value': 1,
                'Unit': 'Count',
                'Timestamp': datetime.utcnow()
            }
        ]
        
        # Add score category metric for easier dashboard filtering
        score_category = get_score_category(score)
        metrics_data.append({
            'MetricName': 'ResilienceScoreCategory',
            'Dimensions': [
                {
                    'Name': 'ApplicationName',
                    'Value': app_name
                },
                {
                    'Name': 'Category',
                    'Value': score_category
                }
            ],
            'Value': 1,
            'Unit': 'Count',
            'Timestamp': datetime.utcnow()
        })
        
        # Send metrics to CloudWatch
        cloudwatch.put_metric_data(
            Namespace='ResilienceHub/Monitoring',
            MetricData=metrics_data
        )
        
        logger.info(f"Successfully sent {len(metrics_data)} metrics to CloudWatch")
        
    except Exception as e:
        logger.error(f"Failed to send metrics to CloudWatch: {str(e)}")


def process_resilience_score(app_name: str, score: float, status: str, context: Any) -> str:
    """
    Process resilience score and take appropriate actions.
    
    Args:
        app_name: Name of the application
        score: Resilience score (0-100)
        status: Assessment status
        context: Lambda context object
        
    Returns:
        Description of the action taken
    """
    try:
        # Define thresholds
        critical_threshold = float(os.getenv('CRITICAL_THRESHOLD', '70'))
        warning_threshold = float(os.getenv('WARNING_THRESHOLD', '80'))
        
        if score < critical_threshold:
            return handle_critical_resilience_score(app_name, score, status, context)
        elif score < warning_threshold:
            return handle_warning_resilience_score(app_name, score, status)
        else:
            return handle_healthy_resilience_score(app_name, score, status)
            
    except Exception as e:
        logger.error(f"Error processing resilience score: {str(e)}")
        return f"Error processing score: {str(e)}"


def handle_critical_resilience_score(app_name: str, score: float, status: str, context: Any) -> str:
    """
    Handle critically low resilience scores.
    
    Args:
        app_name: Name of the application
        score: Resilience score
        status: Assessment status
        context: Lambda context object
        
    Returns:
        Description of actions taken
    """
    logger.warning(f"CRITICAL: Resilience score {score}% below threshold for {app_name}")
    
    # Create detailed alert message
    alert_message = {
        'severity': 'CRITICAL',
        'application': app_name,
        'resilience_score': score,
        'status': status,
        'timestamp': datetime.utcnow().isoformat(),
        'action': 'immediate_attention_required',
        'recommendations': [
            'Review application architecture for single points of failure',
            'Verify backup and recovery procedures',
            'Check Multi-AZ configurations',
            'Validate disaster recovery plans',
            'Consider implementing additional redundancy'
        ],
        'next_steps': [
            'Run detailed resilience assessment',
            'Review infrastructure dependencies',
            'Validate monitoring and alerting',
            'Test failover procedures'
        ]
    }
    
    # Send SNS notification
    send_sns_notification(alert_message, 'CRITICAL')
    
    # Trigger Systems Manager automation for immediate remediation
    trigger_remediation_automation(app_name, score, 'critical')
    
    return f"Critical alert sent and remediation initiated for score {score}%"


def handle_warning_resilience_score(app_name: str, score: float, status: str) -> str:
    """
    Handle warning-level resilience scores.
    
    Args:
        app_name: Name of the application
        score: Resilience score
        status: Assessment status
        
    Returns:
        Description of actions taken
    """
    logger.warning(f"WARNING: Resilience score {score}% below optimal for {app_name}")
    
    # Create warning alert message
    alert_message = {
        'severity': 'WARNING',
        'application': app_name,
        'resilience_score': score,
        'status': status,
        'timestamp': datetime.utcnow().isoformat(),
        'action': 'proactive_improvement_recommended',
        'recommendations': [
            'Review recent changes that may impact resilience',
            'Validate backup configurations',
            'Check monitoring coverage',
            'Review capacity planning'
        ]
    }
    
    # Send SNS notification
    send_sns_notification(alert_message, 'WARNING')
    
    return f"Warning alert sent for score {score}%"


def handle_healthy_resilience_score(app_name: str, score: float, status: str) -> str:
    """
    Handle healthy resilience scores.
    
    Args:
        app_name: Name of the application
        score: Resilience score
        status: Assessment status
        
    Returns:
        Description of actions taken
    """
    logger.info(f"HEALTHY: Resilience score {score}% above threshold for {app_name}")
    
    # Log positive metric
    cloudwatch.put_metric_data(
        Namespace='ResilienceHub/Monitoring',
        MetricData=[
            {
                'MetricName': 'HealthyAssessments',
                'Dimensions': [
                    {
                        'Name': 'ApplicationName',
                        'Value': app_name
                    }
                ],
                'Value': 1,
                'Unit': 'Count',
                'Timestamp': datetime.utcnow()
            }
        ]
    )
    
    return f"Resilience score {score}% is healthy, no action required"


def send_sns_notification(message: Dict[str, Any], severity: str) -> None:
    """
    Send SNS notification for resilience events.
    
    Args:
        message: Alert message dictionary
        severity: Severity level (CRITICAL, WARNING, INFO)
    """
    try:
        topic_arn = os.getenv('SNS_TOPIC_ARN')
        if not topic_arn:
            logger.warning("SNS_TOPIC_ARN environment variable not set, skipping notification")
            return
        
        # Format message for SNS
        subject = f"[{severity}] Resilience Alert - {message['application']}"
        formatted_message = json.dumps(message, indent=2, default=str)
        
        # Publish to SNS
        response = sns.publish(
            TopicArn=topic_arn,
            Subject=subject,
            Message=formatted_message,
            MessageAttributes={
                'severity': {
                    'DataType': 'String',
                    'StringValue': severity
                },
                'application': {
                    'DataType': 'String',
                    'StringValue': message['application']
                }
            }
        )
        
        logger.info(f"SNS notification sent successfully. MessageId: {response['MessageId']}")
        
    except Exception as e:
        logger.error(f"Failed to send SNS notification: {str(e)}")


def trigger_remediation_automation(app_name: str, score: float, severity: str) -> None:
    """
    Trigger Systems Manager automation for remediation.
    
    Args:
        app_name: Name of the application
        score: Resilience score
        severity: Severity level
    """
    try:
        # Create automation execution parameters
        automation_params = {
            'ApplicationName': [app_name],
            'ResilienceScore': [str(score)],
            'Severity': [severity],
            'Timestamp': [datetime.utcnow().isoformat()]
        }
        
        # Start automation execution
        # Note: This uses a generic AWS document. In production, you would
        # create custom automation documents for specific remediation actions
        response = ssm.start_automation_execution(
            DocumentName='AWSSupport-TroubleshootConnectivityToRDS',  # Example document
            Parameters=automation_params
        )
        
        logger.info(f"Started automation execution: {response['AutomationExecutionId']}")
        
        # Log automation metric
        cloudwatch.put_metric_data(
            Namespace='ResilienceHub/Monitoring',
            MetricData=[
                {
                    'MetricName': 'AutomationExecutions',
                    'Dimensions': [
                        {
                            'Name': 'ApplicationName',
                            'Value': app_name
                        },
                        {
                            'Name': 'Severity',
                            'Value': severity
                        }
                    ],
                    'Value': 1,
                    'Unit': 'Count',
                    'Timestamp': datetime.utcnow()
                }
            ]
        )
        
    except Exception as e:
        logger.error(f"Failed to trigger automation: {str(e)}")


def send_error_metrics(error_message: str) -> None:
    """
    Send error metrics to CloudWatch.
    
    Args:
        error_message: Error message description
    """
    try:
        cloudwatch.put_metric_data(
            Namespace='ResilienceHub/Monitoring',
            MetricData=[
                {
                    'MetricName': 'ProcessingErrors',
                    'Value': 1,
                    'Unit': 'Count',
                    'Timestamp': datetime.utcnow()
                },
                {
                    'MetricName': 'LambdaErrors',
                    'Dimensions': [
                        {
                            'Name': 'ErrorType',
                            'Value': type(Exception).__name__
                        }
                    ],
                    'Value': 1,
                    'Unit': 'Count',
                    'Timestamp': datetime.utcnow()
                }
            ]
        )
        
    except Exception as e:
        logger.error(f"Failed to send error metrics: {str(e)}")


def get_score_category(score: float) -> str:
    """
    Categorize resilience score for metrics.
    
    Args:
        score: Resilience score (0-100)
        
    Returns:
        Score category string
    """
    if score >= 90:
        return 'Excellent'
    elif score >= 80:
        return 'Good'
    elif score >= 70:
        return 'Fair'
    elif score >= 60:
        return 'Poor'
    else:
        return 'Critical'