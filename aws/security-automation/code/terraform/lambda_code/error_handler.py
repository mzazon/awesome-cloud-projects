import json
import boto3
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Handle failed automation events
    """
    try:
        logger.error(f"Automation failure: {json.dumps(event)}")
        
        # Send failure notification
        sns = boto3.client('sns')
        sns.publish(
            TopicArn=os.environ.get('SNS_TOPIC_ARN'),
            Subject='Security Automation Failure',
            Message=f'Automation failure detected: {json.dumps(event, indent=2)}'
        )
        
        return {'statusCode': 200, 'body': 'Error handled'}
        
    except Exception as e:
        logger.error(f"Error in error handler: {str(e)}")
        raise