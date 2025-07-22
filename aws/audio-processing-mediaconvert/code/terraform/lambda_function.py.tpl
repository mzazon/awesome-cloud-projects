import json
import boto3
import os
from urllib.parse import unquote_plus

def lambda_handler(event, context):
    """
    Lambda function to process S3 events and trigger MediaConvert jobs.
    
    This function is triggered when audio files are uploaded to the input S3 bucket.
    It validates the file type and creates a MediaConvert job using the configured template.
    """
    
    # Initialize MediaConvert client with the regional endpoint
    mediaconvert = boto3.client('mediaconvert', 
        endpoint_url=os.environ.get('MEDIACONVERT_ENDPOINT', '${mediaconvert_endpoint}'))
    
    # Process each S3 event record
    for record in event['Records']:
        try:
            # Extract S3 event information
            bucket = record['s3']['bucket']['name']
            key = unquote_plus(record['s3']['object']['key'])
            
            print(f"Processing file: s3://{bucket}/{key}")
            
            # Validate file extension for audio processing
            if not key.lower().endswith(('.mp3', '.wav', '.flac', '.m4a', '.aac')):
                print(f"Skipping non-audio file: {key}")
                continue
            
            # Skip files that are too small (likely corrupted or empty)
            if 'object' in record['s3'] and 'size' in record['s3']['object']:
                file_size = record['s3']['object']['size']
                if file_size < 1024:  # Less than 1KB
                    print(f"Skipping file {key} - too small ({file_size} bytes)")
                    continue
            
            # Create MediaConvert job settings
            job_settings = {
                "JobTemplate": os.environ.get('TEMPLATE_ARN', '${template_arn}'),
                "Role": os.environ.get('MEDIACONVERT_ROLE_ARN', '${mediaconvert_role_arn}'),
                "Settings": {
                    "Inputs": [
                        {
                            "FileInput": f"s3://{bucket}/{key}",
                            "AudioSelectors": {
                                "Audio Selector 1": {
                                    "Tracks": [1],
                                    "DefaultSelection": "DEFAULT"
                                }
                            }
                        }
                    ]
                },
                "StatusUpdateInterval": "SECONDS_60",
                "UserMetadata": {
                    "OriginalFile": key,
                    "SourceBucket": bucket,
                    "ProcessedBy": "AudioProcessingPipeline"
                }
            }
            
            # Create the MediaConvert job
            response = mediaconvert.create_job(**job_settings)
            job_id = response['Job']['Id']
            
            print(f"Successfully created MediaConvert job {job_id} for {key}")
            
        except Exception as e:
            print(f"Error processing file {key}: {str(e)}")
            # Continue processing other files even if one fails
            continue
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Processing completed for all files',
            'processedRecords': len(event['Records'])
        })
    }