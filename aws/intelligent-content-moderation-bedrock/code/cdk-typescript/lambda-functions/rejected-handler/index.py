import json
import boto3
from datetime import datetime
import os
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3 = boto3.client('s3')
sns = boto3.client('sns')

def lambda_handler(event, context):
    """
    AWS Lambda function to handle rejected content workflow
    
    Args:
        event: EventBridge event containing content moderation results
        context: Lambda runtime context
        
    Returns:
        dict: Response containing status code and message
    """
    try:
        # Parse EventBridge event
        detail = event['detail']
        source_bucket = detail['bucket']
        source_key = detail['key']
        
        logger.info(f"Processing rejected content: s3://{source_bucket}/{source_key}")
        
        # Get target bucket from environment
        target_bucket = os.environ['REJECTED_BUCKET']
        
        # Create target key with date-based partitioning
        target_key = f"rejected/{datetime.utcnow().strftime('%Y/%m/%d')}/{source_key}"
        
        # Copy content to rejected bucket with metadata
        copy_source = {'Bucket': source_bucket, 'Key': source_key}
        s3.copy_object(
            CopySource=copy_source,
            Bucket=target_bucket,
            Key=target_key,
            MetadataDirective='REPLACE',
            Metadata={
                'moderation-decision': detail['decision'],
                'moderation-confidence': str(detail['confidence']),
                'moderation-reason': detail['reason'],
                'processed-timestamp': datetime.utcnow().isoformat()
            }
        )
        
        # Send notification with high priority for rejected content
        message = f"""
Content Moderation Result: REJECTED

File: {source_key}
Confidence: {detail['confidence']:.2f}
Reason: {detail['reason']}
Categories: {', '.join(detail.get('categories', []))}
Timestamp: {detail['timestamp']}

Target Location: s3://{target_bucket}/{target_key}

ACTION REQUIRED: Review rejected content and update content policies if needed.
        """
        
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject=f'Content Rejected: {source_key}',
            Message=message
        )
        
        logger.info(f"Content rejected and moved to: s3://{target_bucket}/{target_key}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Content processed for rejected workflow',
                'target_location': f's3://{target_bucket}/{target_key}'
            })
        }
        
    except Exception as e:
        logger.error(f"Error in rejected handler: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }