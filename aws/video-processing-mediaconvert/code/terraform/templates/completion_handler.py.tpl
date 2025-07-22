import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Lambda function to handle MediaConvert job completion events.
    Processes EventBridge notifications when video transcoding jobs complete.
    """
    print(f"Received MediaConvert job completion event: {json.dumps(event, indent=2)}")
    
    # Extract job details from the event
    try:
        job_id = event['detail']['jobId']
        status = event['detail']['status']
        timestamp = event['detail']['timestamp']
        
        # Get additional job details if available
        queue = event['detail'].get('queue', 'Unknown')
        job_template = event['detail'].get('jobTemplate', 'None')
        
        print(f"Processing job completion - Job ID: {job_id}, Status: {status}")
        print(f"Job completed at: {timestamp}")
        print(f"Queue: {queue}, Template: {job_template}")
        
        # Handle different job statuses
        if status == 'COMPLETE':
            print(f"✅ Job {job_id} completed successfully!")
            
            # Extract output details if available
            if 'outputGroupDetails' in event['detail']:
                output_details = event['detail']['outputGroupDetails']
                print(f"Output details: {json.dumps(output_details, indent=2)}")
                
                # Process each output group
                for output_group in output_details:
                    output_details_list = output_group.get('outputDetails', [])
                    for output_detail in output_details_list:
                        output_uri = output_detail.get('outputFilePaths', [])
                        if output_uri:
                            print(f"✅ Output file created: {output_uri[0]}")
            
            # Here you can add additional processing logic for successful jobs:
            # - Send success notifications (SNS, SES, Slack)
            # - Update database records
            # - Trigger downstream workflows
            # - Generate thumbnails or preview images
            # - Update content management systems
            
            # Example: Send notification (uncomment and configure as needed)
            # send_success_notification(job_id, output_details)
            
        elif status == 'ERROR':
            print(f"❌ Job {job_id} failed with error")
            
            # Extract error details if available
            if 'errorCode' in event['detail']:
                error_code = event['detail']['errorCode']
                error_message = event['detail'].get('errorMessage', 'No error message provided')
                print(f"Error code: {error_code}")
                print(f"Error message: {error_message}")
            
            # Here you can add error handling logic:
            # - Send error notifications
            # - Log errors to monitoring systems
            # - Implement retry logic
            # - Update job status in database
            
            # Example: Send error notification (uncomment and configure as needed)
            # send_error_notification(job_id, error_code, error_message)
            
        else:
            print(f"⚠️  Job {job_id} completed with unknown status: {status}")
        
        # Log completion statistics for monitoring
        completion_time = datetime.now().isoformat()
        print(f"Event processed at: {completion_time}")
        
    except KeyError as e:
        print(f"❌ Missing expected field in event: {e}")
        print(f"Event structure: {json.dumps(event, indent=2)}")
        raise
    except Exception as e:
        print(f"❌ Error processing job completion event: {str(e)}")
        raise
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Job completion event processed successfully',
            'job_id': job_id,
            'status': status,
            'processed_at': datetime.now().isoformat()
        })
    }

def send_success_notification(job_id, output_details):
    """
    Send success notification for completed video processing job.
    This is a placeholder function - implement based on your notification requirements.
    """
    # Example SNS notification
    # sns = boto3.client('sns')
    # message = f"Video processing job {job_id} completed successfully!"
    # sns.publish(
    #     TopicArn='arn:aws:sns:region:account:topic-name',
    #     Message=message,
    #     Subject='Video Processing Complete'
    # )
    
    print(f"Success notification sent for job {job_id}")

def send_error_notification(job_id, error_code, error_message):
    """
    Send error notification for failed video processing job.
    This is a placeholder function - implement based on your notification requirements.
    """
    # Example SNS notification
    # sns = boto3.client('sns')
    # message = f"Video processing job {job_id} failed with error: {error_code} - {error_message}"
    # sns.publish(
    #     TopicArn='arn:aws:sns:region:account:error-topic-name',
    #     Message=message,
    #     Subject='Video Processing Error'
    # )
    
    print(f"Error notification sent for job {job_id}")