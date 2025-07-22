import json
import boto3

sns = boto3.client('sns')

def lambda_handler(event, context):
    try:
        topic_arn = event['topicArn']
        message = event['message']
        subject = event.get('subject', 'Order Notification')
        
        response = sns.publish(
            TopicArn=topic_arn,
            Subject=subject,
            Message=json.dumps(message, indent=2)
        )
        
        return {
            'statusCode': 200,
            'status': 'NOTIFICATION_SENT',
            'messageId': response['MessageId'],
            'message': 'Notification sent successfully'
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'status': 'NOTIFICATION_FAILED',
            'error': str(e)
        }