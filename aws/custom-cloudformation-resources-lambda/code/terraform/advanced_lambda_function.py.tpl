import json
import boto3
import cfnresponse
import logging
import traceback
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.${log_level})

# Initialize AWS clients
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Advanced Lambda function with comprehensive error handling
    """
    physical_resource_id = event.get('PhysicalResourceId', 'AdvancedCustomResource')
    
    try:
        logger.info(f"Received event: {json.dumps(event, default=str)}")
        
        # Validate required properties
        resource_properties = event.get('ResourceProperties', {})
        required_props = ['BucketName']
        
        for prop in required_props:
            if prop not in resource_properties:
                raise ValueError(f"Missing required property: {prop}")
        
        # Extract event properties
        request_type = event['RequestType']
        
        # Route to appropriate handler
        if request_type == 'Create':
            response_data = handle_create_advanced(resource_properties, physical_resource_id)
        elif request_type == 'Update':
            response_data = handle_update_advanced(resource_properties, physical_resource_id)
        elif request_type == 'Delete':
            response_data = handle_delete_advanced(resource_properties, physical_resource_id)
        else:
            raise ValueError(f"Unknown request type: {request_type}")
        
        # Add standard response data
        response_data['PhysicalResourceId'] = physical_resource_id
        response_data['RequestId'] = event['RequestId']
        response_data['LogicalResourceId'] = event['LogicalResourceId']
        
        logger.info(f"Operation completed successfully: {response_data}")
        cfnresponse.send(event, context, cfnresponse.SUCCESS, response_data, physical_resource_id)
        
    except Exception as e:
        logger.error(f"Error processing request: {str(e)}")
        logger.error(f"Traceback: {traceback.format_exc()}")
        
        # Send failure response with error details
        error_data = {
            'Error': str(e),
            'RequestId': event.get('RequestId', 'unknown'),
            'LogicalResourceId': event.get('LogicalResourceId', 'unknown')
        }
        cfnresponse.send(event, context, cfnresponse.FAILED, error_data, physical_resource_id)

def handle_create_advanced(properties, physical_resource_id):
    """
    Advanced create handler with validation and error handling
    """
    bucket_name = properties['BucketName']
    file_name = properties.get('FileName', 'advanced-data.json')
    data_content = properties.get('DataContent', {})
    
    # Validate bucket exists
    try:
        s3.head_bucket(Bucket=bucket_name)
    except Exception as e:
        raise ValueError(f"Cannot access bucket {bucket_name}: {str(e)}")
    
    # Parse JSON data if string
    if isinstance(data_content, str):
        try:
            data_content = json.loads(data_content)
        except json.JSONDecodeError as e:
            raise ValueError(f"Invalid JSON in DataContent: {str(e)}")
    
    # Create comprehensive data object
    data_object = {
        'metadata': {
            'created_at': datetime.utcnow().isoformat(),
            'resource_id': physical_resource_id,
            'operation': 'CREATE',
            'version': '1.0'
        },
        'configuration': data_content,
        'validation': {
            'bucket_accessible': True,
            'data_format': 'valid'
        }
    }
    
    # Upload to S3 with error handling
    try:
        s3.put_object(
            Bucket=bucket_name,
            Key=file_name,
            Body=json.dumps(data_object, indent=2),
            ContentType='application/json',
            Metadata={
                'resource-id': physical_resource_id,
                'operation': 'CREATE'
            }
        )
    except Exception as e:
        raise RuntimeError(f"Failed to upload to S3: {str(e)}")
    
    return {
        'BucketName': bucket_name,
        'FileName': file_name,
        'DataUrl': f"https://{bucket_name}.s3.amazonaws.com/{file_name}",
        'CreatedAt': data_object['metadata']['created_at'],
        'Status': 'SUCCESS'
    }

def handle_update_advanced(properties, physical_resource_id):
    """
    Advanced update handler
    """
    bucket_name = properties['BucketName']
    file_name = properties.get('FileName', 'advanced-data.json')
    data_content = properties.get('DataContent', {})
    
    # Parse JSON data if string
    if isinstance(data_content, str):
        try:
            data_content = json.loads(data_content)
        except json.JSONDecodeError as e:
            raise ValueError(f"Invalid JSON in DataContent: {str(e)}")
    
    # Get existing data
    existing_data = {}
    try:
        response = s3.get_object(Bucket=bucket_name, Key=file_name)
        existing_data = json.loads(response['Body'].read())
    except s3.exceptions.NoSuchKey:
        logger.warning(f"Object {file_name} not found, creating new one")
    
    # Update data object
    data_object = {
        'metadata': {
            'created_at': existing_data.get('metadata', {}).get('created_at', datetime.utcnow().isoformat()),
            'updated_at': datetime.utcnow().isoformat(),
            'resource_id': physical_resource_id,
            'operation': 'UPDATE',
            'version': '2.0'
        },
        'configuration': data_content,
        'validation': {
            'bucket_accessible': True,
            'data_format': 'valid'
        }
    }
    
    # Upload updated object
    s3.put_object(
        Bucket=bucket_name,
        Key=file_name,
        Body=json.dumps(data_object, indent=2),
        ContentType='application/json',
        Metadata={
            'resource-id': physical_resource_id,
            'operation': 'UPDATE'
        }
    )
    
    return {
        'BucketName': bucket_name,
        'FileName': file_name,
        'DataUrl': f"https://{bucket_name}.s3.amazonaws.com/{file_name}",
        'UpdatedAt': data_object['metadata']['updated_at'],
        'Status': 'SUCCESS'
    }

def handle_delete_advanced(properties, physical_resource_id):
    """
    Advanced delete handler with cleanup verification
    """
    bucket_name = properties['BucketName']
    file_name = properties.get('FileName', 'advanced-data.json')
    
    # Delete object with verification
    try:
        s3.delete_object(Bucket=bucket_name, Key=file_name)
        logger.info(f"Deleted object {file_name} from bucket {bucket_name}")
        
        # Verify deletion
        try:
            s3.head_object(Bucket=bucket_name, Key=file_name)
            logger.warning(f"Object {file_name} still exists after deletion")
        except s3.exceptions.NoSuchKey:
            logger.info(f"Confirmed: Object {file_name} successfully deleted")
            
    except s3.exceptions.NoSuchKey:
        logger.info(f"Object {file_name} does not exist, deletion not needed")
    except Exception as e:
        logger.error(f"Error during deletion: {str(e)}")
        # Don't fail on cleanup errors during deletion
    
    return {
        'BucketName': bucket_name,
        'FileName': file_name,
        'DeletedAt': datetime.utcnow().isoformat(),
        'Status': 'SUCCESS'
    }