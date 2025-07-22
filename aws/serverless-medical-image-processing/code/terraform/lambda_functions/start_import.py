"""
Lambda function to start DICOM import jobs in AWS HealthImaging.

This function is triggered by S3 events when DICOM files are uploaded.
It initiates the import process by creating a HealthImaging import job.
"""

import json
import boto3
import os
import logging
from typing import Dict, Any, List
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
medical_imaging = boto3.client('medical-imaging')
s3 = boto3.client('s3')


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    AWS Lambda handler for starting DICOM import jobs.
    
    This function processes S3 events and initiates HealthImaging import jobs
    for uploaded DICOM files.
    
    Args:
        event: S3 event notification containing upload details
        context: Lambda context object
        
    Returns:
        Dict containing job status and details
    """
    logger.info(f"Processing event: {json.dumps(event, default=str)}")
    
    # Get environment variables
    datastore_id = os.environ.get('DATASTORE_ID', '${datastore_id}')
    output_bucket = os.environ.get('OUTPUT_BUCKET', '${output_bucket}')
    lambda_role_arn = os.environ.get('LAMBDA_ROLE_ARN', '${lambda_role_arn}')
    
    try:
        # Process each S3 event record
        results = []
        
        for record in event.get('Records', []):
            # Extract S3 event details
            bucket = record['s3']['bucket']['name']
            key = record['s3']['object']['key']
            
            logger.info(f"Processing file: s3://{bucket}/{key}")
            
            # Validate that the file is a DICOM file
            if not key.lower().endswith('.dcm'):
                logger.warning(f"Skipping non-DICOM file: {key}")
                continue
            
            # Prepare import job parameters
            # Use the directory containing the DICOM file as the input path
            input_directory = '/'.join(key.split('/')[:-1]) if '/' in key else ''
            input_s3_uri = f"s3://{bucket}/{input_directory}/" if input_directory else f"s3://{bucket}/"
            output_s3_uri = f"s3://{output_bucket}/import-results/"
            
            logger.info(f"Input S3 URI: {input_s3_uri}")
            logger.info(f"Output S3 URI: {output_s3_uri}")
            
            # Start the DICOM import job
            try:
                response = medical_imaging.start_dicom_import_job(
                    dataStoreId=datastore_id,
                    inputS3Uri=input_s3_uri,
                    outputS3Uri=output_s3_uri,
                    dataAccessRoleArn=lambda_role_arn
                )
                
                job_result = {
                    'jobId': response['jobId'],
                    'dataStoreId': response['dataStoreId'],
                    'status': 'SUBMITTED',
                    'inputFile': key,
                    'inputBucket': bucket,
                    'timestamp': context.aws_request_id
                }
                
                results.append(job_result)
                
                logger.info(f"Successfully started import job: {response['jobId']}")
                
            except ClientError as e:
                error_msg = f"Failed to start import job for {key}: {str(e)}"
                logger.error(error_msg)
                
                # Return error information but don't fail the entire function
                results.append({
                    'error': error_msg,
                    'inputFile': key,
                    'inputBucket': bucket,
                    'timestamp': context.aws_request_id
                })
        
        # Return success response with all results
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Import jobs processed',
                'results': results,
                'processedCount': len(results)
            }),
            'headers': {
                'Content-Type': 'application/json'
            }
        }
        
    except Exception as e:
        error_msg = f"Unexpected error processing S3 event: {str(e)}"
        logger.error(error_msg)
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_msg,
                'requestId': context.aws_request_id
            }),
            'headers': {
                'Content-Type': 'application/json'
            }
        }


def validate_s3_event(event: Dict[str, Any]) -> List[Dict[str, Any]]:
    """
    Validate and extract S3 event records.
    
    Args:
        event: Lambda event object
        
    Returns:
        List of valid S3 records
        
    Raises:
        ValueError: If event format is invalid
    """
    if 'Records' not in event:
        raise ValueError("Invalid event format: missing Records")
    
    valid_records = []
    for record in event['Records']:
        if record.get('eventSource') == 'aws:s3':
            valid_records.append(record)
    
    if not valid_records:
        raise ValueError("No valid S3 records found in event")
    
    return valid_records


def get_dicom_metadata(bucket: str, key: str) -> Dict[str, Any]:
    """
    Extract basic metadata from DICOM file in S3.
    
    Args:
        bucket: S3 bucket name
        key: S3 object key
        
    Returns:
        Dictionary containing basic metadata
    """
    try:
        # Get object metadata
        response = s3.head_object(Bucket=bucket, Key=key)
        
        return {
            'size': response.get('ContentLength', 0),
            'lastModified': response.get('LastModified', '').isoformat() if response.get('LastModified') else '',
            'contentType': response.get('ContentType', 'application/octet-stream'),
            'etag': response.get('ETag', '').strip('"')
        }
        
    except ClientError as e:
        logger.warning(f"Could not retrieve metadata for {key}: {str(e)}")
        return {}