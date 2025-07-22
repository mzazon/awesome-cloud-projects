import json
import boto3
import os

def lambda_handler(event, context):
    """
    Trigger video analysis workflow when new video is uploaded to S3
    """
    try:
        stepfunctions = boto3.client('stepfunctions')
        
        # Extract S3 event information
        for record in event['Records']:
            bucket = record['s3']['bucket']['name']
            key = record['s3']['object']['key']
            
            # Only process video files
            if not key.lower().endswith(('.mp4', '.avi', '.mov', '.mkv', '.wmv')):
                print(f"Skipping non-video file: {key}")
                continue
            
            # Start Step Functions execution
            response = stepfunctions.start_execution(
                stateMachineArn='${state_machine_arn}',
                input=json.dumps({
                    'Records': [record]
                })
            )
            
            print(f"Started analysis for {bucket}/{key}: {response['executionArn']}")
        
        return {
            'statusCode': 200,
            'body': 'Video analysis workflow triggered successfully'
        }
        
    except Exception as e:
        print(f"Error triggering workflow: {str(e)}")
        return {
            'statusCode': 500,
            'body': str(e)
        }