"""
AWS Lambda Function for Automated Data Quality Monitoring
Triggers Deequ quality monitoring jobs on EMR cluster
"""

import json
import os
import time
import boto3
from datetime import datetime

def lambda_handler(event, context):
    """
    Lambda function handler to trigger automated data quality monitoring
    
    Args:
        event (dict): Lambda event data
        context: Lambda context object
        
    Returns:
        dict: Response with status and details
    """
    
    # Initialize AWS clients
    emr_client = boto3.client('emr')
    
    try:
        # Get configuration from environment variables
        cluster_id = os.environ.get('CLUSTER_ID')
        s3_bucket = os.environ.get('S3_BUCKET')
        sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
        
        # Validate required environment variables
        if not all([cluster_id, s3_bucket, sns_topic_arn]):
            raise ValueError("Missing required environment variables: CLUSTER_ID, S3_BUCKET, SNS_TOPIC_ARN")
        
        # Get parameters from event (with defaults)
        data_path = event.get('data_path', f's3://{s3_bucket}/raw-data/')
        job_name = event.get('job_name', f'AutomatedDataQualityMonitoring_{int(time.time())}')
        
        print(f"Starting automated data quality monitoring job: {job_name}")
        print(f"Cluster ID: {cluster_id}")
        print(f"Data path: {data_path}")
        print(f"S3 bucket: {s3_bucket}")
        
        # Check cluster status
        cluster_response = emr_client.describe_cluster(ClusterId=cluster_id)
        cluster_state = cluster_response['Cluster']['State']
        
        if cluster_state not in ['WAITING', 'RUNNING']:
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': f'Cluster is not ready. Current state: {cluster_state}',
                    'cluster_id': cluster_id
                })
            }
        
        # Configure Spark step
        step_config = {
            "Name": job_name,
            "ActionOnFailure": "CONTINUE",
            "HadoopJarStep": {
                "Jar": "command-runner.jar",
                "Args": [
                    "spark-submit",
                    "--deploy-mode", "cluster",
                    "--master", "yarn",
                    "--conf", "spark.sql.adaptive.enabled=true",
                    "--conf", "spark.sql.adaptive.coalescePartitions.enabled=true",
                    "--conf", "spark.serializer=org.apache.spark.serializer.KryoSerializer",
                    "--conf", "spark.dynamicAllocation.enabled=true",
                    "--conf", "spark.dynamicAllocation.minExecutors=1",
                    "--conf", "spark.dynamicAllocation.maxExecutors=10",
                    f"s3://{s3_bucket}/scripts/deequ-quality-monitor.py",
                    s3_bucket,
                    data_path,
                    sns_topic_arn
                ]
            }
        }
        
        # Submit the step to EMR
        step_response = emr_client.add_steps(
            ClusterId=cluster_id,
            Steps=[step_config]
        )
        
        step_id = step_response['StepIds'][0]
        
        print(f"Successfully submitted step: {step_id}")
        
        # Prepare response
        response_body = {
            'message': 'Data quality monitoring job submitted successfully',
            'job_name': job_name,
            'cluster_id': cluster_id,
            'step_id': step_id,
            'data_path': data_path,
            'timestamp': datetime.now().isoformat(),
            'status': 'SUBMITTED'
        }
        
        return {
            'statusCode': 200,
            'body': json.dumps(response_body),
            'headers': {
                'Content-Type': 'application/json'
            }
        }
        
    except Exception as e:
        error_message = f"Error in automated monitoring: {str(e)}"
        print(f"ERROR: {error_message}")
        
        # Send error notification if SNS topic is available
        try:
            sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
            if sns_topic_arn:
                sns_client = boto3.client('sns')
                
                error_alert = {
                    'timestamp': datetime.now().isoformat(),
                    'alert_type': 'LAMBDA_ERROR',
                    'severity': 'HIGH',
                    'function_name': context.function_name,
                    'error_message': str(e),
                    'event_data': event,
                    'recommended_action': 'Check Lambda function logs and EMR cluster status'
                }
                
                sns_client.publish(
                    TopicArn=sns_topic_arn,
                    Message=json.dumps(error_alert, indent=2),
                    Subject='🚨 Lambda Function Error - Automated Data Quality Monitoring'
                )
        except:
            pass  # Don't fail if error notification fails
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_message,
                'timestamp': datetime.now().isoformat()
            }),
            'headers': {
                'Content-Type': 'application/json'
            }
        }

def get_step_status(cluster_id, step_id):
    """
    Get the status of a specific EMR step
    
    Args:
        cluster_id (str): EMR cluster ID
        step_id (str): EMR step ID
        
    Returns:
        dict: Step status information
    """
    emr_client = boto3.client('emr')
    
    try:
        response = emr_client.describe_step(
            ClusterId=cluster_id,
            StepId=step_id
        )
        
        step = response['Step']
        
        return {
            'step_id': step_id,
            'name': step['Name'],
            'state': step['Status']['State'],
            'state_change_reason': step['Status'].get('StateChangeReason', ''),
            'creation_time': step['Status']['Timeline']['CreationDateTime'].isoformat(),
            'start_time': step['Status']['Timeline'].get('StartDateTime', ''),
            'end_time': step['Status']['Timeline'].get('EndDateTime', '')
        }
        
    except Exception as e:
        return {
            'error': f"Failed to get step status: {str(e)}",
            'step_id': step_id
        }

def monitor_step_progress(event, context):
    """
    Monitor the progress of a running EMR step
    Used as a separate Lambda function or invoked periodically
    
    Args:
        event (dict): Event containing cluster_id and step_id
        context: Lambda context
        
    Returns:
        dict: Step progress information
    """
    cluster_id = event.get('cluster_id')
    step_id = event.get('step_id')
    
    if not cluster_id or not step_id:
        return {
            'statusCode': 400,
            'body': json.dumps({
                'error': 'Missing cluster_id or step_id in event'
            })
        }
    
    step_status = get_step_status(cluster_id, step_id)
    
    return {
        'statusCode': 200,
        'body': json.dumps(step_status),
        'headers': {
            'Content-Type': 'application/json'
        }
    }