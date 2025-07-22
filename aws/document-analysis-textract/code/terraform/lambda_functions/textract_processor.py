"""
Textract Processor Lambda Function
Processes documents using Amazon Textract with both sync and async patterns
"""
import json
import boto3
import uuid
import os
from datetime import datetime
from botocore.exceptions import ClientError

# Initialize AWS clients
textract = boto3.client('textract')
s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')

# Environment variables
OUTPUT_BUCKET = os.environ['OUTPUT_BUCKET']
METADATA_TABLE = os.environ['METADATA_TABLE']
SNS_TOPIC_ARN = os.environ['SNS_TOPIC_ARN']
EXECUTION_ROLE_ARN = os.environ['EXECUTION_ROLE_ARN']

def lambda_handler(event, context):
    """
    Lambda handler for Textract document processing
    
    Args:
        event: Document processing request
        context: Lambda runtime context
        
    Returns:
        dict: Processing results
    """
    try:
        # Extract input parameters
        if 'body' in event:
            # From Step Functions
            body = event['body'] if isinstance(event['body'], dict) else json.loads(event['body'])
        else:
            # Direct invocation
            body = event
            
        bucket = body['bucket']
        key = body['key']
        processing_type = body['processingType']
        document_type = body['documentType']
        
        document_id = str(uuid.uuid4())
        
        print(f"Processing document {document_id}: {processing_type} processing for {document_type}")
        
        # Process document based on type
        if processing_type == 'sync':
            result = process_sync_document(bucket, key, document_type, document_id)
        else:
            result = process_async_document(bucket, key, document_type, document_id)
        
        # Store metadata in DynamoDB
        store_metadata(document_id, bucket, key, document_type, result)
        
        # Send notification
        send_notification(document_id, document_type, result.get('status', 'completed'))
        
        return {
            'statusCode': 200,
            'body': {
                'documentId': document_id,
                'processingType': processing_type,
                'result': result
            }
        }
        
    except Exception as e:
        print(f"Error processing document: {str(e)}")
        return {
            'statusCode': 500,
            'body': {
                'error': str(e),
                'errorType': type(e).__name__
            }
        }

def process_sync_document(bucket, key, document_type, document_id):
    """
    Process single-page document synchronously
    
    Args:
        bucket (str): S3 bucket name
        key (str): S3 object key
        document_type (str): Type of document
        document_id (str): Unique document identifier
        
    Returns:
        dict: Processing results
    """
    try:
        print(f"Starting synchronous processing for {document_id}")
        
        # Determine features based on document type
        features = get_textract_features(document_type)
        
        # Call Textract analyze document
        response = textract.analyze_document(
            Document={'S3Object': {'Bucket': bucket, 'Name': key}},
            FeatureTypes=features
        )
        
        # Extract and structure data
        extracted_data = extract_structured_data(response)
        
        # Save results to S3
        output_key = f"results/{document_id}-analysis.json"
        save_results_to_s3(extracted_data, output_key)
        
        print(f"Synchronous processing completed for {document_id}")
        
        return {
            'status': 'completed',
            'outputLocation': f"s3://{OUTPUT_BUCKET}/{output_key}",
            'extractedData': extracted_data,
            'textractJobId': None,
            'processingTime': datetime.utcnow().isoformat()
        }
        
    except ClientError as e:
        print(f"AWS service error in sync processing: {str(e)}")
        raise
    except Exception as e:
        print(f"Unexpected error in sync processing: {str(e)}")
        raise

def process_async_document(bucket, key, document_type, document_id):
    """
    Start asynchronous document processing
    
    Args:
        bucket (str): S3 bucket name
        key (str): S3 object key
        document_type (str): Type of document
        document_id (str): Unique document identifier
        
    Returns:
        dict: Processing job information
    """
    try:
        print(f"Starting asynchronous processing for {document_id}")
        
        # Determine features based on document type
        features = get_textract_features(document_type)
        
        # Start async document analysis
        response = textract.start_document_analysis(
            DocumentLocation={'S3Object': {'Bucket': bucket, 'Name': key}},
            FeatureTypes=features,
            NotificationChannel={
                'SNSTopicArn': SNS_TOPIC_ARN,
                'RoleArn': EXECUTION_ROLE_ARN
            },
            JobTag=document_id
        )
        
        job_id = response['JobId']
        print(f"Asynchronous job started: {job_id} for document {document_id}")
        
        return {
            'status': 'in_progress',
            'jobId': job_id,
            'outputLocation': None,
            'extractedData': None,
            'processingTime': datetime.utcnow().isoformat()
        }
        
    except ClientError as e:
        print(f"AWS service error in async processing: {str(e)}")
        raise
    except Exception as e:
        print(f"Unexpected error in async processing: {str(e)}")
        raise

def get_textract_features(document_type):
    """
    Determine Textract features based on document type
    
    Args:
        document_type (str): Type of document
        
    Returns:
        list: List of Textract features to enable
    """
    # Default features for most documents
    features = ['TABLES']
    
    # Add forms analysis for specific document types
    if document_type in ['invoice', 'form', 'contract']:
        features.append('FORMS')
        
    # Add signatures analysis for contracts
    if document_type == 'contract':
        features.append('SIGNATURES')
        
    return features

def extract_structured_data(response):
    """
    Extract structured data from Textract response
    
    Args:
        response (dict): Textract API response
        
    Returns:
        dict: Structured extracted data
    """
    blocks = response['Blocks']
    
    # Initialize data structures
    lines = []
    tables = []
    forms = []
    
    # Extract different types of content
    for block in blocks:
        if block['BlockType'] == 'LINE':
            lines.append({
                'id': block['Id'],
                'text': block.get('Text', ''),
                'confidence': round(block.get('Confidence', 0), 2),
                'geometry': extract_geometry(block.get('Geometry', {}))
            })
        elif block['BlockType'] == 'TABLE':
            tables.append(extract_table_data(block, blocks))
        elif block['BlockType'] == 'KEY_VALUE_SET':
            if block.get('EntityTypes') and 'KEY' in block['EntityTypes']:
                forms.append(extract_form_data(block, blocks))
    
    # Calculate overall statistics
    total_confidence = sum(line['confidence'] for line in lines) / len(lines) if lines else 0
    
    return {
        'text_lines': lines,
        'tables': tables,
        'forms': forms,
        'document_metadata': response.get('DocumentMetadata', {}),
        'processing_statistics': {
            'total_lines': len(lines),
            'total_tables': len(tables),
            'total_forms': len(forms),
            'average_confidence': round(total_confidence, 2)
        },
        'extraction_timestamp': datetime.utcnow().isoformat()
    }

def extract_geometry(geometry):
    """
    Extract and simplify geometry information
    
    Args:
        geometry (dict): Textract geometry data
        
    Returns:
        dict: Simplified geometry information
    """
    if not geometry:
        return {}
        
    bbox = geometry.get('BoundingBox', {})
    return {
        'left': round(bbox.get('Left', 0), 4),
        'top': round(bbox.get('Top', 0), 4),
        'width': round(bbox.get('Width', 0), 4),
        'height': round(bbox.get('Height', 0), 4)
    }

def extract_table_data(table_block, all_blocks):
    """
    Extract table structure and data
    
    Args:
        table_block (dict): Table block from Textract
        all_blocks (list): All blocks from Textract response
        
    Returns:
        dict: Table structure and data
    """
    # This is a simplified table extraction
    # In production, implement more sophisticated table parsing
    return {
        'id': table_block['Id'],
        'confidence': round(table_block.get('Confidence', 0), 2),
        'geometry': extract_geometry(table_block.get('Geometry', {})),
        'row_count': table_block.get('RowIndex', 0),
        'column_count': table_block.get('ColumnIndex', 0)
    }

def extract_form_data(form_block, all_blocks):
    """
    Extract form key-value pairs
    
    Args:
        form_block (dict): Form block from Textract
        all_blocks (list): All blocks from Textract response
        
    Returns:
        dict: Form key-value data
    """
    # This is a simplified form extraction
    # In production, implement more sophisticated form parsing
    return {
        'id': form_block['Id'],
        'confidence': round(form_block.get('Confidence', 0), 2),
        'entity_types': form_block.get('EntityTypes', []),
        'geometry': extract_geometry(form_block.get('Geometry', {}))
    }

def save_results_to_s3(data, output_key):
    """
    Save extracted data to S3
    
    Args:
        data (dict): Extracted data to save
        output_key (str): S3 key for output file
    """
    try:
        s3.put_object(
            Bucket=OUTPUT_BUCKET,
            Key=output_key,
            Body=json.dumps(data, indent=2, default=str),
            ContentType='application/json',
            Metadata={
                'extraction-timestamp': datetime.utcnow().isoformat(),
                'extractor': 'textract-processor-lambda'
            }
        )
        print(f"Results saved to s3://{OUTPUT_BUCKET}/{output_key}")
    except Exception as e:
        print(f"Error saving results to S3: {str(e)}")
        raise

def store_metadata(document_id, bucket, key, document_type, result):
    """
    Store document metadata in DynamoDB
    
    Args:
        document_id (str): Unique document identifier
        bucket (str): S3 bucket name
        key (str): S3 object key
        document_type (str): Type of document
        result (dict): Processing results
    """
    try:
        table = dynamodb.Table(METADATA_TABLE)
        
        item = {
            'documentId': document_id,
            'bucket': bucket,
            'key': key,
            'documentType': document_type,
            'processingStatus': result.get('status', 'completed'),
            'jobId': result.get('jobId'),
            'outputLocation': result.get('outputLocation'),
            'processingTime': result.get('processingTime'),
            'timestamp': datetime.utcnow().isoformat(),
            'ttl': int(datetime.utcnow().timestamp()) + (30 * 24 * 3600)  # 30 days TTL
        }
        
        # Add extracted data for sync processing
        if result.get('extractedData'):
            item['extractedDataSummary'] = {
                'total_lines': result['extractedData'].get('processing_statistics', {}).get('total_lines', 0),
                'total_tables': result['extractedData'].get('processing_statistics', {}).get('total_tables', 0),
                'total_forms': result['extractedData'].get('processing_statistics', {}).get('total_forms', 0),
                'average_confidence': result['extractedData'].get('processing_statistics', {}).get('average_confidence', 0)
            }
        
        table.put_item(Item=item)
        print(f"Metadata stored for document {document_id}")
        
    except Exception as e:
        print(f"Error storing metadata: {str(e)}")
        # Don't raise here - metadata storage failure shouldn't fail the whole process

def send_notification(document_id, document_type, status):
    """
    Send processing notification via SNS
    
    Args:
        document_id (str): Document identifier
        document_type (str): Type of document
        status (str): Processing status
    """
    try:
        message = {
            'documentId': document_id,
            'documentType': document_type,
            'status': status,
            'timestamp': datetime.utcnow().isoformat(),
            'service': 'textract-processor'
        }
        
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Message=json.dumps(message, indent=2),
            Subject=f'Document Processing {status.title()}',
            MessageAttributes={
                'documentType': {
                    'DataType': 'String',
                    'StringValue': document_type
                },
                'status': {
                    'DataType': 'String',
                    'StringValue': status
                }
            }
        )
        print(f"Notification sent for document {document_id}")
        
    except Exception as e:
        print(f"Error sending notification: {str(e)}")
        # Don't raise here - notification failure shouldn't fail the whole process