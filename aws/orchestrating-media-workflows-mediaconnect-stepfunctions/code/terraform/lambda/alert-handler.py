import json
import boto3
from datetime import datetime
import os

# Initialize AWS clients
sns = boto3.client('sns')

def lambda_handler(event, context):
    """
    Lambda function to handle media workflow alerts.
    
    Processes monitoring results and sends detailed notifications
    through SNS when stream quality issues are detected.
    
    Args:
        event: Contains monitoring results from stream monitor
        context: Lambda runtime context
        
    Returns:
        Dict containing notification status and message ID
    """
    try:
        # Extract monitoring results from event
        monitoring_result = event
        
        # Get SNS topic ARN from environment or event
        sns_topic_arn = event.get('sns_topic_arn') or os.environ.get('SNS_TOPIC_ARN')
        if not sns_topic_arn:
            raise ValueError("SNS topic ARN not provided in event or environment")
        
        flow_name = monitoring_result.get('flow_name', 'Unknown Flow')
        flow_arn = monitoring_result.get('flow_arn', 'Unknown ARN')
        timestamp = monitoring_result.get('timestamp', datetime.utcnow().isoformat())
        issues = monitoring_result.get('issues', [])
        healthy = monitoring_result.get('healthy', True)
        flow_status = monitoring_result.get('flow_status', 'UNKNOWN')
        current_bitrate = monitoring_result.get('current_bitrate')
        
        # Only send alerts if flow is unhealthy
        if not healthy and issues:
            # Construct alert message subject
            critical_issues = [issue for issue in issues if issue.get('severity') == 'CRITICAL']
            high_issues = [issue for issue in issues if issue.get('severity') == 'HIGH']
            
            if critical_issues:
                severity_level = "CRITICAL"
            elif high_issues:
                severity_level = "HIGH"
            else:
                severity_level = "MEDIUM"
            
            subject = f"[{severity_level}] MediaConnect Alert: {flow_name}"
            
            # Build detailed message body
            message_lines = [
                f"MediaConnect Stream Alert",
                f"========================",
                "",
                f"Flow Name: {flow_name}",
                f"Flow Status: {flow_status}",
                f"Alert Time: {timestamp}",
                f"Severity: {severity_level}",
                "",
                "Issues Detected:",
                "================",
            ]
            
            # Add each issue with details
            for i, issue in enumerate(issues, 1):
                message_lines.extend([
                    f"{i}. {issue['metric']} [{issue['severity']}]",
                    f"   Description: {issue['description']}",
                    f"   Current Value: {issue['value']}",
                    f"   Threshold: {issue['threshold']}",
                    ""
                ])
            
            # Add current stream metrics if available
            if current_bitrate is not None:
                message_lines.extend([
                    "Current Stream Metrics:",
                    "======================",
                    f"Bitrate: {current_bitrate:.0f} bps ({current_bitrate/1000000:.2f} Mbps)",
                    ""
                ])
            
            # Add recommended actions
            message_lines.extend([
                "Recommended Actions:",
                "===================",
                "1. Check source encoder stability and configuration",
                "2. Verify network connectivity between source and MediaConnect",
                "3. Review CloudWatch dashboard for detailed metrics trends",
                "4. Inspect source equipment for hardware issues",
                "5. Consider switching to backup source if available",
                "",
                "Console Links:",
                "==============",
            ])
            
            # Extract region from context
            region = context.invoked_function_arn.split(':')[3]
            flow_id = flow_arn.split('/')[-1] if '/' in flow_arn else flow_arn.split(':')[-1]
            
            message_lines.extend([
                f"MediaConnect Flow: https://console.aws.amazon.com/mediaconnect/home?region={region}#/flows/{flow_id}",
                f"CloudWatch Metrics: https://console.aws.amazon.com/cloudwatch/home?region={region}#metricsV2:query=AWS/MediaConnect",
                f"Step Functions: https://console.aws.amazon.com/states/home?region={region}",
                "",
                "This alert was generated automatically by the media monitoring workflow.",
                f"For technical support, reference Flow ARN: {flow_arn}"
            ])
            
            message = "\n".join(message_lines)
            
            # Send SNS notification
            response = sns.publish(
                TopicArn=sns_topic_arn,
                Subject=subject,
                Message=message,
                MessageAttributes={
                    'severity': {
                        'DataType': 'String',
                        'StringValue': severity_level
                    },
                    'flow_name': {
                        'DataType': 'String',
                        'StringValue': flow_name
                    },
                    'flow_status': {
                        'DataType': 'String',
                        'StringValue': flow_status
                    },
                    'issue_count': {
                        'DataType': 'Number',
                        'StringValue': str(len(issues))
                    }
                }
            )
            
            # Log successful notification
            print(f"Alert sent for flow {flow_name} with {len(issues)} issues")
            print(f"SNS Message ID: {response['MessageId']}")
            
            return {
                'statusCode': 200,
                'notification_sent': True,
                'message_id': response['MessageId'],
                'severity': severity_level,
                'issue_count': len(issues),
                'flow_name': flow_name
            }
        
        else:
            # Flow is healthy - no notification needed
            print(f"Flow {flow_name} is healthy - no alert sent")
            
            return {
                'statusCode': 200,
                'notification_sent': False,
                'reason': 'Flow is healthy',
                'flow_name': flow_name,
                'flow_status': flow_status
            }
            
    except Exception as e:
        error_message = f"Error sending media alert: {str(e)}"
        print(error_message)
        
        # Try to send error notification if possible
        try:
            if sns_topic_arn:
                error_subject = f"Media Alert System Error"
                error_body = f"""
Media Alert System Error
========================

An error occurred while processing a media workflow alert:

Error: {str(e)}
Time: {datetime.utcnow().isoformat()}
Flow: {event.get('flow_name', 'Unknown')}

Please check the Lambda function logs for more details.
Function: {context.function_name}
Request ID: {context.aws_request_id}
"""
                
                sns.publish(
                    TopicArn=sns_topic_arn,
                    Subject=error_subject,
                    Message=error_body
                )
        except:
            pass  # Don't fail if error notification also fails
        
        return {
            'statusCode': 500,
            'notification_sent': False,
            'error': error_message,
            'flow_name': event.get('flow_name', 'Unknown')
        }