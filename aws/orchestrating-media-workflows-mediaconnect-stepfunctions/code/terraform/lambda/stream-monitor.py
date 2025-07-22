import json
import boto3
from datetime import datetime, timedelta
import os

# Initialize AWS clients
cloudwatch = boto3.client('cloudwatch')
mediaconnect = boto3.client('mediaconnect')

def lambda_handler(event, context):
    """
    Lambda function to monitor MediaConnect flow health metrics.
    
    Analyzes packet loss and jitter metrics from CloudWatch to determine
    stream health and identify quality issues that require attention.
    
    Args:
        event: Contains flow_arn and sns_topic_arn
        context: Lambda runtime context
        
    Returns:
        Dict containing monitoring results and health status
    """
    try:
        # Extract flow ARN from event
        flow_arn = event.get('flow_arn')
        if not flow_arn:
            raise ValueError("flow_arn is required in event payload")
        
        # Get flow details from MediaConnect
        flow_response = mediaconnect.describe_flow(FlowArn=flow_arn)
        flow_name = flow_response['Flow']['Name']
        flow_status = flow_response['Flow']['Status']
        
        # Define time range for metrics (last 5 minutes)
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(minutes=5)
        
        # Initialize issues list
        issues = []
        
        # Check source packet loss metrics
        packet_loss_response = cloudwatch.get_metric_statistics(
            Namespace='AWS/MediaConnect',
            MetricName='SourcePacketLossPercent',
            Dimensions=[
                {'Name': 'FlowARN', 'Value': flow_arn}
            ],
            StartTime=start_time,
            EndTime=end_time,
            Period=300,
            Statistics=['Average', 'Maximum']
        )
        
        # Analyze packet loss metrics
        if packet_loss_response['Datapoints']:
            latest_packet_loss = sorted(
                packet_loss_response['Datapoints'], 
                key=lambda x: x['Timestamp']
            )[-1]
            
            if latest_packet_loss['Maximum'] > 0.1:  # 0.1% threshold
                issues.append({
                    'metric': 'PacketLoss',
                    'value': latest_packet_loss['Maximum'],
                    'threshold': 0.1,
                    'severity': 'HIGH',
                    'description': f"Packet loss of {latest_packet_loss['Maximum']:.3f}% exceeds threshold"
                })
        
        # Check source jitter metrics
        jitter_response = cloudwatch.get_metric_statistics(
            Namespace='AWS/MediaConnect',
            MetricName='SourceJitter',
            Dimensions=[
                {'Name': 'FlowARN', 'Value': flow_arn}
            ],
            StartTime=start_time,
            EndTime=end_time,
            Period=300,
            Statistics=['Average', 'Maximum']
        )
        
        # Analyze jitter metrics
        if jitter_response['Datapoints']:
            latest_jitter = sorted(
                jitter_response['Datapoints'], 
                key=lambda x: x['Timestamp']
            )[-1]
            
            if latest_jitter['Maximum'] > 50:  # 50ms threshold
                issues.append({
                    'metric': 'Jitter',
                    'value': latest_jitter['Maximum'],
                    'threshold': 50,
                    'severity': 'MEDIUM',
                    'description': f"Jitter of {latest_jitter['Maximum']:.1f}ms exceeds threshold"
                })
        
        # Check source bitrate for additional context
        bitrate_response = cloudwatch.get_metric_statistics(
            Namespace='AWS/MediaConnect',
            MetricName='SourceBitrate',
            Dimensions=[
                {'Name': 'FlowARN', 'Value': flow_arn}
            ],
            StartTime=start_time,
            EndTime=end_time,
            Period=300,
            Statistics=['Average']
        )
        
        current_bitrate = None
        if bitrate_response['Datapoints']:
            latest_bitrate = sorted(
                bitrate_response['Datapoints'], 
                key=lambda x: x['Timestamp']
            )[-1]
            current_bitrate = latest_bitrate['Average']
        
        # Check flow status
        if flow_status != 'ACTIVE':
            issues.append({
                'metric': 'FlowStatus',
                'value': flow_status,
                'threshold': 'ACTIVE',
                'severity': 'CRITICAL',
                'description': f"Flow status is {flow_status} instead of ACTIVE"
            })
        
        # Determine overall health
        is_healthy = len(issues) == 0
        
        # Prepare response
        response = {
            'statusCode': 200,
            'flow_name': flow_name,
            'flow_arn': flow_arn,
            'flow_status': flow_status,
            'timestamp': end_time.isoformat(),
            'issues': issues,
            'healthy': is_healthy,
            'current_bitrate': current_bitrate,
            'monitoring_period_minutes': 5
        }
        
        # Log monitoring results
        print(f"Monitoring results for flow {flow_name}: {'HEALTHY' if is_healthy else 'ISSUES DETECTED'}")
        if issues:
            for issue in issues:
                print(f"  - {issue['metric']}: {issue['description']} [{issue['severity']}]")
        
        return response
        
    except Exception as e:
        error_message = f"Error monitoring MediaConnect flow: {str(e)}"
        print(error_message)
        
        return {
            'statusCode': 500,
            'error': error_message,
            'flow_arn': event.get('flow_arn', 'unknown'),
            'timestamp': datetime.utcnow().isoformat(),
            'healthy': False,
            'issues': [{
                'metric': 'MonitoringError',
                'value': str(e),
                'threshold': 'none',
                'severity': 'CRITICAL',
                'description': f"Failed to monitor flow: {str(e)}"
            }]
        }