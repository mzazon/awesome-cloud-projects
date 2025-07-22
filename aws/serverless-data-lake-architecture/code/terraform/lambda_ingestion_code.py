import json
import boto3
import os
from datetime import datetime
from data_utils import DataProcessor

def lambda_handler(event, context):
    processor = DataProcessor()
    
    # Extract event information
    bucket = event['Records'][0]['s3']['bucket']['name']
    key = event['Records'][0]['s3']['object']['key']
    
    # Generate process ID
    process_id = processor.generate_process_id(bucket, datetime.utcnow().isoformat())
    
    try:
        # Download and process the file
        s3_response = processor.s3_client.get_object(Bucket=bucket, Key=key)
        file_content = s3_response['Body'].read().decode('utf-8')
        
        # Determine file type and process accordingly
        if key.endswith('.json'):
            data = json.loads(file_content)
            data_type = 'json'
        elif key.endswith('.csv'):
            # For CSV files, we'll pass the raw content
            data = {'raw_content': file_content, 'type': 'csv'}
            data_type = 'csv'
        else:
            data = {'raw_content': file_content, 'type': 'unknown'}
            data_type = 'unknown'
        
        # Store metadata
        metadata = {
            'SourceBucket': bucket,
            'SourceKey': key,
            'FileSize': len(file_content),
            'DataType': data_type,
            'Status': 'ingested',
            'ProcessingStage': 'ingestion'
        }
        
        processor.store_metadata(
            table_name=os.environ['METADATA_TABLE'],
            process_id=process_id,
            metadata=metadata
        )
        
        # Publish ingestion event
        event_detail = {
            'processId': process_id,
            'bucket': bucket,
            'key': key,
            'dataType': data_type,
            'fileSize': len(file_content)
        }
        
        processor.publish_custom_event(
            event_bus=os.environ['CUSTOM_EVENT_BUS'],
            source='datalake.ingestion',
            detail_type='Data Received',
            detail=event_detail
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'processId': process_id,
                'message': 'Data ingested successfully'
            })
        }
        
    except Exception as e:
        print(f"Error processing file: {str(e)}")
        
        # Store error metadata
        error_metadata = {
            'SourceBucket': bucket,
            'SourceKey': key,
            'Status': 'failed',
            'ProcessingStage': 'ingestion',
            'ErrorMessage': str(e)
        }
        
        processor.store_metadata(
            table_name=os.environ['METADATA_TABLE'],
            process_id=process_id,
            metadata=error_metadata
        )
        
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }