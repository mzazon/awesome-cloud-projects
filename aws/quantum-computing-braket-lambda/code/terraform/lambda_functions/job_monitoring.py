# Job Monitoring Lambda Function for Quantum Computing Pipeline
# This function monitors quantum job status and triggers post-processing

import json
import boto3
import time
from datetime import datetime, timedelta
import os

braket = boto3.client('braket')
s3 = boto3.client('s3')
cloudwatch = boto3.client('cloudwatch')
lambda_client = boto3.client('lambda')

def lambda_handler(event, context):
    """Monitor quantum job status and trigger post-processing."""
    try:
        # Extract job information
        job_arn = event.get('job_arn')
        job_name = event.get('job_name')
        output_bucket = event.get('output_bucket')
        
        if not job_arn:
            raise ValueError("job_arn is required")
        
        print(f"Monitoring quantum job: {job_name}")
        
        # Get job status from Braket
        job_details = braket.get_job(jobArn=job_arn)
        job_status = job_details['status']
        
        print(f"Job status: {job_status}")
        
        # Handle different job states
        if job_status == 'COMPLETED':
            # Job completed successfully
            result = handle_completed_job(job_details, output_bucket)
            
            # Trigger post-processing
            trigger_post_processing(job_name, output_bucket)
            
        elif job_status == 'FAILED':
            # Job failed
            result = handle_failed_job(job_details, output_bucket)
            
        elif job_status in ['RUNNING', 'QUEUED']:
            # Job still in progress
            result = handle_running_job(job_details)
            
            # Schedule next monitoring check
            schedule_next_check(job_arn, job_name, output_bucket)
            
        elif job_status == 'CANCELLED':
            # Job was cancelled
            result = handle_cancelled_job(job_details, output_bucket)
        
        else:
            result = {'status': job_status, 'message': f'Unknown job status: {job_status}'}
        
        # Send metrics to CloudWatch
        send_job_metrics(job_details)
        
        return {
            'statusCode': 200,
            'body': json.dumps(result)
        }
        
    except Exception as e:
        print(f"Error monitoring quantum job: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def handle_completed_job(job_details, output_bucket):
    """Handle completed quantum job."""
    job_name = job_details['jobName']
    end_time = job_details.get('endedAt', datetime.utcnow().isoformat())
    
    # Calculate job duration
    start_time = datetime.fromisoformat(job_details['startedAt'].replace('Z', '+00:00'))
    end_time_dt = datetime.fromisoformat(end_time.replace('Z', '+00:00'))
    duration = (end_time_dt - start_time).total_seconds()
    
    # Store job completion metadata
    completion_data = {
        'job_name': job_name,
        'status': 'COMPLETED',
        'duration_seconds': duration,
        'completed_at': end_time,
        'output_location': job_details.get('outputDataConfig', {}).get('s3Path'),
        'billing_duration': job_details.get('billableDuration', 0)
    }
    
    s3.put_object(
        Bucket=output_bucket,
        Key=f'jobs/{job_name}/completion_status.json',
        Body=json.dumps(completion_data, indent=2)
    )
    
    print(f"Job {job_name} completed in {duration:.2f} seconds")
    
    return {
        'status': 'COMPLETED',
        'duration': duration,
        'message': f'Quantum job completed successfully'
    }

def handle_failed_job(job_details, output_bucket):
    """Handle failed quantum job."""
    job_name = job_details['jobName']
    failure_reason = job_details.get('failureReason', 'Unknown failure')
    
    failure_data = {
        'job_name': job_name,
        'status': 'FAILED',
        'failure_reason': failure_reason,
        'failed_at': job_details.get('endedAt', datetime.utcnow().isoformat())
    }
    
    s3.put_object(
        Bucket=output_bucket,
        Key=f'jobs/{job_name}/failure_status.json',
        Body=json.dumps(failure_data, indent=2)
    )
    
    print(f"Job {job_name} failed: {failure_reason}")
    
    return {
        'status': 'FAILED',
        'failure_reason': failure_reason,
        'message': 'Quantum job failed'
    }

def handle_running_job(job_details):
    """Handle running quantum job."""
    job_name = job_details['jobName']
    started_at = job_details.get('startedAt')
    
    if started_at:
        start_time = datetime.fromisoformat(started_at.replace('Z', '+00:00'))
        elapsed = (datetime.utcnow().replace(tzinfo=start_time.tzinfo) - start_time).total_seconds()
        print(f"Job {job_name} running for {elapsed:.2f} seconds")
    
    return {
        'status': 'RUNNING',
        'message': 'Quantum job is still running'
    }

def handle_cancelled_job(job_details, output_bucket):
    """Handle cancelled quantum job."""
    job_name = job_details['jobName']
    
    cancellation_data = {
        'job_name': job_name,
        'status': 'CANCELLED',
        'cancelled_at': job_details.get('endedAt', datetime.utcnow().isoformat())
    }
    
    s3.put_object(
        Bucket=output_bucket,
        Key=f'jobs/{job_name}/cancellation_status.json',
        Body=json.dumps(cancellation_data, indent=2)
    )
    
    return {
        'status': 'CANCELLED',
        'message': 'Quantum job was cancelled'
    }

def trigger_post_processing(job_name, output_bucket):
    """Trigger post-processing Lambda function."""
    try:
        project_name = os.environ.get('PROJECT_NAME', '${project_name}')
        lambda_client.invoke(
            FunctionName=f'{project_name}-post-processing',
            InvocationType='Event',
            Payload=json.dumps({
                'job_name': job_name,
                'output_bucket': output_bucket
            })
        )
        print(f"Post-processing triggered for job {job_name}")
    except Exception as e:
        print(f"Error triggering post-processing: {str(e)}")

def schedule_next_check(job_arn, job_name, output_bucket):
    """Schedule next monitoring check."""
    # Note: In production, use EventBridge for scheduled monitoring
    print(f"Next monitoring check scheduled for job {job_name}")

def send_job_metrics(job_details):
    """Send job metrics to CloudWatch."""
    try:
        status = job_details['status']
        job_name = job_details['jobName']
        
        metrics = [
            {
                'MetricName': 'JobStatusUpdate',
                'Value': 1,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'JobStatus', 'Value': status},
                    {'Name': 'JobName', 'Value': job_name}
                ]
            }
        ]
        
        if status == 'COMPLETED' and 'billableDuration' in job_details:
            metrics.append({
                'MetricName': 'JobDuration',
                'Value': job_details['billableDuration'],
                'Unit': 'Seconds',
                'Dimensions': [
                    {'Name': 'JobName', 'Value': job_name}
                ]
            })
        
        cloudwatch.put_metric_data(
            Namespace='QuantumPipeline',
            MetricData=metrics
        )
        
    except Exception as e:
        print(f"Error sending metrics: {str(e)}")