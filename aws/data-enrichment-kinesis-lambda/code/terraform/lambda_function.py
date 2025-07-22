import json
import boto3
import base64
import datetime
import os
import logging
from decimal import Decimal

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    AWS Lambda function to enrich streaming data from Kinesis.
    
    This function:
    1. Receives batches of records from Kinesis Data Streams
    2. Enriches each record with user profile data from DynamoDB
    3. Stores enriched data in S3 with time-based partitioning
    4. Handles errors gracefully and provides comprehensive logging
    
    Args:
        event: Lambda event containing Kinesis records
        context: Lambda runtime context
        
    Returns:
        String indicating processing status
    """
    
    # Get environment variables
    table_name = os.environ.get('TABLE_NAME')
    bucket_name = os.environ.get('BUCKET_NAME')
    
    if not table_name or not bucket_name:
        logger.error("Missing required environment variables: TABLE_NAME or BUCKET_NAME")
        raise ValueError("Missing required environment variables")
    
    table = dynamodb.Table(table_name)
    
    # Track processing statistics
    processed_records = 0
    failed_records = 0
    
    logger.info(f"Processing {len(event['Records'])} records from Kinesis")
    
    for record in event['Records']:
        try:
            # Decode Kinesis data
            payload = base64.b64decode(record['kinesis']['data'])
            data = json.loads(payload.decode('utf-8'))
            
            logger.info(f"Processing record: {record['kinesis']['sequenceNumber']}")
            
            # Enrich data with user profile
            user_id = data.get('user_id')
            if user_id:
                try:
                    # Lookup user profile in DynamoDB
                    response = table.get_item(Key={'user_id': user_id})
                    
                    if 'Item' in response:
                        # Add user profile data to event
                        user_profile = response['Item']
                        data['user_name'] = user_profile.get('name', 'Unknown')
                        data['user_email'] = user_profile.get('email', 'Unknown')
                        data['user_segment'] = user_profile.get('segment', 'Unknown')
                        data['user_location'] = user_profile.get('location', 'Unknown')
                        data['enrichment_status'] = 'success'
                        logger.info(f"Successfully enriched data for user_id: {user_id}")
                    else:
                        # User not found in lookup table
                        data['user_name'] = 'Unknown'
                        data['user_email'] = 'Unknown'
                        data['user_segment'] = 'Unknown'
                        data['user_location'] = 'Unknown'
                        data['enrichment_status'] = 'user_not_found'
                        logger.warning(f"User profile not found for user_id: {user_id}")
                        
                except Exception as e:
                    logger.error(f"Error enriching user data for user_id {user_id}: {str(e)}")
                    data['enrichment_error'] = str(e)
                    data['enrichment_status'] = 'error'
            else:
                # No user_id in the record
                data['enrichment_status'] = 'no_user_id'
                logger.warning("No user_id found in record")
            
            # Add processing metadata
            data['processing_timestamp'] = datetime.datetime.utcnow().isoformat()
            data['enriched'] = True
            data['lambda_request_id'] = context.aws_request_id
            data['kinesis_sequence_number'] = record['kinesis']['sequenceNumber']
            
            # Create time-based partition for S3 storage
            timestamp = datetime.datetime.utcnow()
            partition_key = timestamp.strftime('%Y/%m/%d/%H')
            
            # Generate unique filename
            filename = f"{record['kinesis']['sequenceNumber']}_{timestamp.strftime('%Y%m%d_%H%M%S_%f')}.json"
            s3_key = f"enriched-data/{partition_key}/{filename}"
            
            # Store enriched data in S3
            try:
                s3.put_object(
                    Bucket=bucket_name,
                    Key=s3_key,
                    Body=json.dumps(data, indent=2, default=str),
                    ContentType='application/json',
                    Metadata={
                        'processing_timestamp': data['processing_timestamp'],
                        'enrichment_status': data['enrichment_status'],
                        'source': 'kinesis-lambda-enrichment'
                    }
                )
                
                processed_records += 1
                logger.info(f"Successfully stored enriched data to S3: {s3_key}")
                
            except Exception as e:
                failed_records += 1
                logger.error(f"Error storing enriched data to S3: {str(e)}")
                # Re-raise to trigger retry mechanism
                raise
                
        except Exception as e:
            failed_records += 1
            logger.error(f"Error processing record {record['kinesis']['sequenceNumber']}: {str(e)}")
            # Continue processing other records instead of failing the entire batch
            continue
    
    # Log processing summary
    logger.info(f"Processing complete. Processed: {processed_records}, Failed: {failed_records}")
    
    # Return processing summary
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f"Successfully processed {processed_records} records, {failed_records} failed",
            'processed_records': processed_records,
            'failed_records': failed_records,
            'total_records': len(event['Records'])
        })
    }