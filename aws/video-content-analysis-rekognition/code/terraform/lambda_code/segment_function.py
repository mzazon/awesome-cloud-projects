import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Start segment detection analysis using Amazon Rekognition
    """
    try:
        rekognition = boto3.client('rekognition')
        dynamodb = boto3.resource('dynamodb')
        table = dynamodb.Table('${analysis_table}')
        
        # Extract job information
        job_id = event['jobId']
        s3_bucket = event['s3Bucket']
        s3_key = event['s3Key']
        video_id = event['videoId']
        
        # Start segment detection job
        response = rekognition.start_segment_detection(
            Video={
                'S3Object': {
                    'Bucket': s3_bucket,
                    'Name': s3_key
                }
            },
            SegmentTypes=['TECHNICAL_CUE', 'SHOT'],
            NotificationChannel={
                'SNSTopicArn': '${sns_topic_arn}',
                'RoleArn': '${rekognition_role_arn}'
            }
        )
        
        segment_job_id = response['JobId']
        
        # Update DynamoDB with segment job ID
        table.update_item(
            Key={
                'VideoId': video_id,
                'Timestamp': int(datetime.now().timestamp())
            },
            UpdateExpression='SET SegmentJobId = :sjid, JobStatus = :status',
            ExpressionAttributeValues={
                ':sjid': segment_job_id,
                ':status': 'SEGMENT_DETECTION_IN_PROGRESS'
            }
        )
        
        return {
            'statusCode': 200,
            'body': {
                'jobId': job_id,
                'segmentJobId': segment_job_id,
                'videoId': video_id,
                'status': 'SEGMENT_DETECTION_IN_PROGRESS'
            }
        }
        
    except Exception as e:
        print(f"Error starting segment detection: {str(e)}")
        return {
            'statusCode': 500,
            'body': {
                'error': str(e)
            }
        }