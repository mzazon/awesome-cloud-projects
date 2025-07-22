import json
import boto3
import uuid
from datetime import datetime
import os

def lambda_handler(event, context):
    """
    Initialize video analysis job from S3 event
    """
    try:
        # Extract video information from S3 event
        s3_bucket = event['Records'][0]['s3']['bucket']['name']
        s3_key = event['Records'][0]['s3']['object']['key']
        
        # Generate unique job ID
        job_id = str(uuid.uuid4())
        
        # Initialize DynamoDB record
        dynamodb = boto3.resource('dynamodb')
        table = dynamodb.Table('${analysis_table}')
        
        # Store initial job information
        table.put_item(
            Item={
                'VideoId': f"{s3_bucket}/{s3_key}",
                'Timestamp': int(datetime.now().timestamp()),
                'JobId': job_id,
                'JobStatus': 'INITIATED',
                'S3Bucket': s3_bucket,
                'S3Key': s3_key,
                'CreatedAt': datetime.now().isoformat()
            }
        )
        
        return {
            'statusCode': 200,
            'body': {
                'jobId': job_id,
                'videoId': f"{s3_bucket}/{s3_key}",
                's3Bucket': s3_bucket,
                's3Key': s3_key,
                'status': 'INITIATED'
            }
        }
        
    except Exception as e:
        print(f"Error initializing video analysis: {str(e)}")
        return {
            'statusCode': 500,
            'body': {
                'error': str(e)
            }
        }