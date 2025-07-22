import json
import boto3
import cfnresponse
import logging
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.${log_level})

# Initialize AWS clients
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Lambda function to handle custom resource operations
    """
    try:
        logger.info(f"Received event: {json.dumps(event)}")
        
        # Extract event properties
        request_type = event['RequestType']
        resource_properties = event.get('ResourceProperties', {})
        physical_resource_id = event.get('PhysicalResourceId', 'CustomResource')
        
        # Initialize response data
        response_data = {}
        
        if request_type == 'Create':
            logger.info("Processing CREATE request")
            response_data = handle_create(resource_properties, physical_resource_id)
            
        elif request_type == 'Update':
            logger.info("Processing UPDATE request")
            response_data = handle_update(resource_properties, physical_resource_id)
            
        elif request_type == 'Delete':
            logger.info("Processing DELETE request")
            response_data = handle_delete(resource_properties, physical_resource_id)
            
        else:
            logger.error(f"Unknown request type: {request_type}")
            cfnresponse.send(event, context, cfnresponse.FAILED, {}, physical_resource_id)
            return
        
        # Send success response
        cfnresponse.send(event, context, cfnresponse.SUCCESS, response_data, physical_resource_id)
        
    except Exception as e:
        logger.error(f"Error processing request: {str(e)}")
        cfnresponse.send(event, context, cfnresponse.FAILED, {}, physical_resource_id)

def handle_create(properties, physical_resource_id):
    """
    Handle resource creation
    """
    try:
        # Get configuration from properties
        bucket_name = properties.get('BucketName')
        file_name = properties.get('FileName', 'custom-resource-data.json')
        data_content = properties.get('DataContent', {})
        
        # Create data object
        data_object = {
            'created_at': datetime.utcnow().isoformat(),
            'resource_id': physical_resource_id,
            'configuration': data_content,
            'operation': 'CREATE'
        }
        
        # Upload to S3
        s3.put_object(
            Bucket=bucket_name,
            Key=file_name,
            Body=json.dumps(data_object, indent=2),
            ContentType='application/json'
        )
        
        logger.info(f"Created object {file_name} in bucket {bucket_name}")
        
        # Return response data
        return {
            'BucketName': bucket_name,
            'FileName': file_name,
            'DataUrl': f"https://{bucket_name}.s3.amazonaws.com/{file_name}",
            'CreatedAt': data_object['created_at']
        }
        
    except Exception as e:
        logger.error(f"Error in handle_create: {str(e)}")
        raise

def handle_update(properties, physical_resource_id):
    """
    Handle resource updates
    """
    try:
        # Get configuration from properties
        bucket_name = properties.get('BucketName')
        file_name = properties.get('FileName', 'custom-resource-data.json')
        data_content = properties.get('DataContent', {})
        
        # Try to get existing object
        try:
            response = s3.get_object(Bucket=bucket_name, Key=file_name)
            existing_data = json.loads(response['Body'].read())
        except s3.exceptions.NoSuchKey:
            existing_data = {}
        
        # Update data object
        data_object = {
            'created_at': existing_data.get('created_at', datetime.utcnow().isoformat()),
            'updated_at': datetime.utcnow().isoformat(),
            'resource_id': physical_resource_id,
            'configuration': data_content,
            'operation': 'UPDATE'
        }
        
        # Upload updated object to S3
        s3.put_object(
            Bucket=bucket_name,
            Key=file_name,
            Body=json.dumps(data_object, indent=2),
            ContentType='application/json'
        )
        
        logger.info(f"Updated object {file_name} in bucket {bucket_name}")
        
        # Return response data
        return {
            'BucketName': bucket_name,
            'FileName': file_name,
            'DataUrl': f"https://{bucket_name}.s3.amazonaws.com/{file_name}",
            'UpdatedAt': data_object['updated_at']
        }
        
    except Exception as e:
        logger.error(f"Error in handle_update: {str(e)}")
        raise

def handle_delete(properties, physical_resource_id):
    """
    Handle resource deletion
    """
    try:
        # Get configuration from properties
        bucket_name = properties.get('BucketName')
        file_name = properties.get('FileName', 'custom-resource-data.json')
        
        # Delete object from S3
        try:
            s3.delete_object(Bucket=bucket_name, Key=file_name)
            logger.info(f"Deleted object {file_name} from bucket {bucket_name}")
        except Exception as e:
            logger.warning(f"Could not delete object: {str(e)}")
        
        # Return response data
        return {
            'BucketName': bucket_name,
            'FileName': file_name,
            'DeletedAt': datetime.utcnow().isoformat()
        }
        
    except Exception as e:
        logger.error(f"Error in handle_delete: {str(e)}")
        raise