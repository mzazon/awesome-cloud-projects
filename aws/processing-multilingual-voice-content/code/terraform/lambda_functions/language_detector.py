import json
import boto3
import uuid
import os
from datetime import datetime

transcribe = boto3.client('transcribe')
dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')

# Environment variables
JOBS_TABLE_NAME = os.environ.get('JOBS_TABLE_NAME', '${jobs_table_name}')

def lambda_handler(event, context):
    """
    Lambda function for detecting language in audio files using Amazon Transcribe.
    
    This function starts a transcription job with language identification enabled
    and updates the job status in DynamoDB.
    
    Args:
        event: Lambda event containing bucket, key, and job_id
        context: Lambda context
        
    Returns:
        dict: Response with job information or error details
    """
    
    try:
        # Extract parameters from event
        bucket = event.get('bucket')
        key = event.get('key')
        job_id = event.get('job_id', str(uuid.uuid4()))
        
        # Validate required parameters
        if not bucket or not key:
            raise ValueError("Missing required parameters: bucket and key")
        
        # Initialize DynamoDB table
        table = dynamodb.Table(JOBS_TABLE_NAME)
        
        # Update job status to language detection
        table.put_item(
            Item={
                'JobId': job_id,
                'Status': 'LANGUAGE_DETECTION',
                'InputFile': f"s3://{bucket}/{key}",
                'Timestamp': int(datetime.now().timestamp()),
                'Stage': 'language_detection',
                'CreatedAt': datetime.now().isoformat()
            }
        )
        
        print(f"Starting language detection for job {job_id}")
        
        # Generate unique transcription job name
        job_name = f"lang-detect-{job_id}"
        
        # Start transcription job with language identification
        transcribe_response = transcribe.start_transcription_job(
            TranscriptionJobName=job_name,
            Media={'MediaFileUri': f"s3://{bucket}/{key}"},
            IdentifyLanguage=True,
            OutputBucketName=bucket,
            OutputKey=f"language-detection/{job_id}/",
            Settings={
                'ShowSpeakerLabels': False,  # Not needed for language detection
                'MaxSpeakerLabels': 2,
                'ShowAlternatives': False
            }
        )
        
        print(f"Language detection job started: {job_name}")
        
        # Update DynamoDB with transcription job information
        table.update_item(
            Key={'JobId': job_id},
            UpdateExpression='SET TranscriptionJobName = :job_name, UpdatedAt = :updated_at',
            ExpressionAttributeValues={
                ':job_name': job_name,
                ':updated_at': datetime.now().isoformat()
            }
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Language detection job started successfully',
                'job_id': job_id,
                'transcribe_job_name': job_name,
                'bucket': bucket,
                'key': key,
                'stage': 'language_detection'
            })
        }
        
    except Exception as e:
        error_message = str(e)
        print(f"Error in language detection: {error_message}")
        
        # Update DynamoDB with error status
        try:
            table = dynamodb.Table(JOBS_TABLE_NAME)
            table.put_item(
                Item={
                    'JobId': job_id if 'job_id' in locals() else str(uuid.uuid4()),
                    'Status': 'FAILED',
                    'Error': error_message,
                    'Timestamp': int(datetime.now().timestamp()),
                    'Stage': 'language_detection',
                    'FailedAt': datetime.now().isoformat()
                }
            )
        except Exception as db_error:
            print(f"Failed to update DynamoDB with error: {str(db_error)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_message,
                'job_id': job_id if 'job_id' in locals() else None,
                'stage': 'language_detection'
            })
        }