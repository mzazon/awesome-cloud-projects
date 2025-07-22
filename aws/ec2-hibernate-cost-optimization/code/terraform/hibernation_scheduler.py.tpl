import json
import boto3
import os
from datetime import datetime

def handler(event, context):
    """
    Lambda function to schedule hibernation of EC2 instances
    This function can be triggered by CloudWatch Events or manually
    """
    
    # Initialize AWS clients
    ec2 = boto3.client('ec2')
    sns = boto3.client('sns')
    cloudwatch = boto3.client('cloudwatch')
    
    # Get environment variables
    instance_id = os.environ.get('INSTANCE_ID')
    sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
    
    if not instance_id:
        return {
            'statusCode': 400,
            'body': json.dumps('INSTANCE_ID environment variable not set')
        }
    
    try:
        # Get instance details
        response = ec2.describe_instances(InstanceIds=[instance_id])
        instance = response['Reservations'][0]['Instances'][0]
        instance_state = instance['State']['Name']
        
        print(f"Instance {instance_id} current state: {instance_state}")
        
        # Check if hibernation is supported
        hibernation_enabled = instance.get('HibernationOptions', {}).get('Configured', False)
        if not hibernation_enabled:
            message = f"Instance {instance_id} does not support hibernation"
            print(message)
            return {
                'statusCode': 400,
                'body': json.dumps(message)
            }
        
        # Determine action based on event type or current state
        action = event.get('action', 'auto')
        
        if action == 'hibernate' or (action == 'auto' and instance_state == 'running'):
            # Check CPU utilization before hibernating
            cpu_utilization = get_cpu_utilization(cloudwatch, instance_id)
            
            if cpu_utilization is not None and cpu_utilization < 10:  # Low CPU threshold
                # Hibernate the instance
                print(f"Hibernating instance {instance_id} due to low CPU utilization: {cpu_utilization}%")
                
                ec2.stop_instances(InstanceIds=[instance_id], Hibernate=True)
                
                message = f"Instance {instance_id} hibernation initiated. CPU utilization: {cpu_utilization}%"
                send_notification(sns, sns_topic_arn, "EC2 Instance Hibernated", message)
                
                return {
                    'statusCode': 200,
                    'body': json.dumps(message)
                }
            else:
                message = f"Instance {instance_id} CPU utilization ({cpu_utilization}%) is above threshold. Skipping hibernation."
                print(message)
                return {
                    'statusCode': 200,
                    'body': json.dumps(message)
                }
        
        elif action == 'resume' or (action == 'auto' and instance_state == 'stopped'):
            # Resume the instance
            print(f"Resuming instance {instance_id}")
            
            ec2.start_instances(InstanceIds=[instance_id])
            
            message = f"Instance {instance_id} resume initiated"
            send_notification(sns, sns_topic_arn, "EC2 Instance Resumed", message)
            
            return {
                'statusCode': 200,
                'body': json.dumps(message)
            }
        
        else:
            message = f"No action taken for instance {instance_id}. Current state: {instance_state}, Action: {action}"
            print(message)
            return {
                'statusCode': 200,
                'body': json.dumps(message)
            }
    
    except Exception as e:
        error_message = f"Error processing instance {instance_id}: {str(e)}"
        print(error_message)
        
        if sns_topic_arn:
            send_notification(sns, sns_topic_arn, "EC2 Hibernation Error", error_message)
        
        return {
            'statusCode': 500,
            'body': json.dumps(error_message)
        }

def get_cpu_utilization(cloudwatch, instance_id):
    """Get average CPU utilization for the instance over the last 15 minutes"""
    try:
        from datetime import datetime, timedelta
        
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(minutes=15)
        
        response = cloudwatch.get_metric_statistics(
            Namespace='AWS/EC2',
            MetricName='CPUUtilization',
            Dimensions=[
                {
                    'Name': 'InstanceId',
                    'Value': instance_id
                }
            ],
            StartTime=start_time,
            EndTime=end_time,
            Period=300,  # 5 minute periods
            Statistics=['Average']
        )
        
        if response['Datapoints']:
            # Get the average of all datapoints
            avg_cpu = sum(dp['Average'] for dp in response['Datapoints']) / len(response['Datapoints'])
            return round(avg_cpu, 2)
        else:
            print(f"No CPU metrics found for instance {instance_id}")
            return None
            
    except Exception as e:
        print(f"Error getting CPU utilization: {str(e)}")
        return None

def send_notification(sns, topic_arn, subject, message):
    """Send SNS notification"""
    if not topic_arn:
        print("SNS topic ARN not configured, skipping notification")
        return
    
    try:
        sns.publish(
            TopicArn=topic_arn,
            Subject=subject,
            Message=f"{message}\n\nTimestamp: {datetime.utcnow().isoformat()}Z"
        )
        print(f"Notification sent: {subject}")
    except Exception as e:
        print(f"Error sending notification: {str(e)}")

def lambda_handler(event, context):
    """AWS Lambda entry point"""
    return handler(event, context)

# Example event formats:
# Manual hibernation: {"action": "hibernate"}
# Manual resume: {"action": "resume"}
# Automatic based on state: {"action": "auto"}
# CloudWatch Events: {"source": "aws.events", "detail-type": "Scheduled Event"}