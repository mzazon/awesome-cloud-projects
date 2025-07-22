import json
import boto3
import os
from data_utils import DataProcessor, DataValidator

def lambda_handler(event, context):
    processor = DataProcessor()
    validator = DataValidator()
    
    # Parse EventBridge event
    detail = event['detail']
    process_id = detail['processId']
    bucket = detail['bucket']
    key = detail['key']
    data_type = detail['dataType']
    
    try:
        # Download the file for validation
        s3_response = processor.s3_client.get_object(Bucket=bucket, Key=key)
        file_content = s3_response['Body'].read().decode('utf-8')
        
        validation_results = {
            'processId': process_id,
            'validationPassed': True,
            'validationErrors': [],
            'qualityScore': 0
        }
        
        if data_type == 'json':
            try:
                data = json.loads(file_content)
                
                # Validate required fields (example schema)
                required_fields = ['id', 'timestamp', 'data']
                if not processor.validate_json_structure(data, required_fields):
                    validation_results['validationPassed'] = False
                    validation_results['validationErrors'].append('Missing required fields')
                
                # Calculate quality score
                validation_results['qualityScore'] = processor.calculate_data_quality_score(data)
                
                # Additional field validations
                if 'email' in data and not validator.is_valid_email(data['email']):
                    validation_results['validationErrors'].append('Invalid email format')
                
                if 'phone' in data and not validator.is_valid_phone(data['phone']):
                    validation_results['validationErrors'].append('Invalid phone format')
                
            except json.JSONDecodeError:
                validation_results['validationPassed'] = False
                validation_results['validationErrors'].append('Invalid JSON format')
        
        elif data_type == 'csv':
            # Basic CSV validation
            lines = file_content.strip().split('\n')
            if len(lines) < 2:  # Header + at least one data row
                validation_results['validationPassed'] = False
                validation_results['validationErrors'].append('CSV file must have header and data rows')
            else:
                validation_results['qualityScore'] = 85.0  # Default score for valid CSV
        
        # Determine destination based on validation
        if validation_results['validationPassed'] and validation_results['qualityScore'] >= 70:
            destination_bucket = os.environ['PROCESSED_BUCKET']
            destination_prefix = 'validated/'
            status = 'validated'
        else:
            destination_bucket = os.environ['QUARANTINE_BUCKET']
            destination_prefix = 'quarantine/'
            status = 'quarantined'
        
        # Copy file to appropriate destination
        destination_key = f"{destination_prefix}{key}"
        processor.s3_client.copy_object(
            CopySource={'Bucket': bucket, 'Key': key},
            Bucket=destination_bucket,
            Key=destination_key
        )
        
        # Update metadata
        metadata = {
            'Status': status,
            'ProcessingStage': 'validation',
            'ValidationPassed': validation_results['validationPassed'],
            'QualityScore': validation_results['qualityScore'],
            'ValidationErrors': validation_results['validationErrors'],
            'DestinationBucket': destination_bucket,
            'DestinationKey': destination_key
        }
        
        processor.store_metadata(
            table_name=os.environ['METADATA_TABLE'],
            process_id=process_id,
            metadata=metadata
        )
        
        # Publish validation event
        processor.publish_custom_event(
            event_bus=os.environ['CUSTOM_EVENT_BUS'],
            source='datalake.validation',
            detail_type='Data Validated',
            detail=validation_results
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps(validation_results)
        }
        
    except Exception as e:
        print(f"Error validating data: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }