import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Start content moderation analysis using Amazon Rekognition
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
        
        # Start content moderation job
        response = rekognition.start_content_moderation(
            Video={
                'S3Object': {
                    'Bucket': s3_bucket,
                    'Name': s3_key
                }
            },
            MinConfidence=${min_confidence},
            NotificationChannel={
                'SNSTopicArn': '${sns_topic_arn}',
                'RoleArn': '${rekognition_role_arn}'
            }
        )
        
        moderation_job_id = response['JobId']
        
        # Update DynamoDB with moderation job ID
        table.update_item(
            Key={
                'VideoId': video_id,
                'Timestamp': int(datetime.now().timestamp())
            },
            UpdateExpression='SET ModerationJobId = :mjid, JobStatus = :status',
            ExpressionAttributeValues={
                ':mjid': moderation_job_id,
                ':status': 'MODERATION_IN_PROGRESS'
            }
        )
        
        return {
            'statusCode': 200,
            'body': {
                'jobId': job_id,
                'moderationJobId': moderation_job_id,
                'videoId': video_id,
                'status': 'MODERATION_IN_PROGRESS'
            }
        }
        
    except Exception as e:
        print(f"Error starting content moderation: {str(e)}")
        return {
            'statusCode': 500,
            'body': {
                'error': str(e)
            }
        }