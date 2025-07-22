"""
Document Query Lambda Function
Provides API interface for querying document processing results and metadata
"""
import json
import boto3
import os
from datetime import datetime
from decimal import Decimal
from botocore.exceptions import ClientError

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')

# Environment variables
METADATA_TABLE = os.environ['METADATA_TABLE']

def lambda_handler(event, context):
    """
    Lambda handler for document query operations
    
    Args:
        event: Query parameters
        context: Lambda runtime context
        
    Returns:
        dict: Query results
    """
    try:
        # Parse query parameters
        query_params = event.get('queryStringParameters') or event
        
        document_id = query_params.get('documentId')
        document_type = query_params.get('documentType')
        status = query_params.get('status')
        limit = int(query_params.get('limit', 50))
        include_summary = query_params.get('includeSummary', 'false').lower() == 'true'
        
        print(f"Query request: documentId={document_id}, documentType={document_type}, status={status}")
        
        # Validate parameters
        if limit > 100:
            limit = 100
            
        table = dynamodb.Table(METADATA_TABLE)
        
        # Execute appropriate query
        if document_id:
            result = query_by_document_id(table, document_id, include_summary)
        elif document_type:
            result = query_by_document_type(table, document_type, status, limit)
        elif status:
            result = scan_by_status(table, status, limit)
        else:
            result = scan_all_documents(table, limit)
            
        # Process result for JSON serialization
        processed_result = process_dynamodb_result(result)
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'success': True,
                'data': processed_result,
                'query_timestamp': datetime.utcnow().isoformat()
            }, default=decimal_default)
        }
        
    except Exception as e:
        print(f"Error processing query: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'success': False,
                'error': str(e),
                'errorType': type(e).__name__
            })
        }

def query_by_document_id(table, document_id, include_summary):
    """
    Query specific document by ID
    
    Args:
        table: DynamoDB table resource
        document_id (str): Document identifier
        include_summary (bool): Whether to include detailed summary
        
    Returns:
        dict: Document details or None if not found
    """
    try:
        response = table.get_item(Key={'documentId': document_id})
        
        if 'Item' not in response:
            return None
            
        item = response['Item']
        
        # Add additional details if requested
        if include_summary and item.get('outputLocation'):
            item['detailedSummary'] = get_detailed_summary(item['outputLocation'])
            
        return item
        
    except ClientError as e:
        print(f"Error querying document {document_id}: {str(e)}")
        raise

def query_by_document_type(table, document_type, status, limit):
    """
    Query documents by type using GSI
    
    Args:
        table: DynamoDB table resource
        document_type (str): Type of document
        status (str): Optional status filter
        limit (int): Maximum results to return
        
    Returns:
        list: List of matching documents
    """
    try:
        query_params = {
            'IndexName': 'DocumentTypeIndex',
            'KeyConditionExpression': 'documentType = :dt',
            'ExpressionAttributeValues': {':dt': document_type},
            'Limit': limit,
            'ScanIndexForward': False  # Latest first
        }
        
        # Add status filter if specified
        if status:
            query_params['FilterExpression'] = 'processingStatus = :status'
            query_params['ExpressionAttributeValues'][':status'] = status
            
        response = table.query(**query_params)
        return response['Items']
        
    except ClientError as e:
        print(f"Error querying by document type {document_type}: {str(e)}")
        raise

def scan_by_status(table, status, limit):
    """
    Scan documents by status
    
    Args:
        table: DynamoDB table resource
        status (str): Processing status
        limit (int): Maximum results to return
        
    Returns:
        list: List of matching documents
    """
    try:
        response = table.scan(
            FilterExpression='processingStatus = :status',
            ExpressionAttributeValues={':status': status},
            Limit=limit
        )
        return response['Items']
        
    except ClientError as e:
        print(f"Error scanning by status {status}: {str(e)}")
        raise

def scan_all_documents(table, limit):
    """
    Get all documents with pagination
    
    Args:
        table: DynamoDB table resource
        limit (int): Maximum results to return
        
    Returns:
        list: List of all documents
    """
    try:
        response = table.scan(Limit=limit)
        return response['Items']
        
    except ClientError as e:
        print(f"Error scanning all documents: {str(e)}")
        raise

def get_detailed_summary(output_location):
    """
    Get detailed summary from S3 results file
    
    Args:
        output_location (str): S3 URL of results file
        
    Returns:
        dict: Detailed summary information
    """
    try:
        # Parse S3 URL
        if not output_location.startswith('s3://'):
            return {'error': 'Invalid S3 URL'}
            
        # Extract bucket and key
        s3_parts = output_location[5:].split('/', 1)
        if len(s3_parts) != 2:
            return {'error': 'Invalid S3 URL format'}
            
        bucket, key = s3_parts
        
        # Get object from S3
        response = s3.get_object(Bucket=bucket, Key=key)
        results_data = json.loads(response['Body'].read().decode('utf-8'))
        
        # Extract summary information
        summary = {
            'text_preview': get_text_preview(results_data.get('text_lines', [])),
            'table_summary': get_table_summary(results_data.get('tables', [])),
            'form_summary': get_form_summary(results_data.get('forms', [])),
            'processing_stats': results_data.get('processing_statistics', {}),
            'confidence_distribution': calculate_confidence_distribution(results_data.get('text_lines', []))
        }
        
        return summary
        
    except Exception as e:
        print(f"Error getting detailed summary: {str(e)}")
        return {'error': f'Failed to load summary: {str(e)}'}

def get_text_preview(text_lines):
    """
    Generate text preview from extracted lines
    
    Args:
        text_lines (list): List of text line objects
        
    Returns:
        dict: Text preview information
    """
    if not text_lines:
        return {'preview': '', 'total_characters': 0}
        
    # Combine first few lines for preview
    preview_lines = text_lines[:5]
    preview_text = ' '.join(line.get('text', '') for line in preview_lines)
    
    # Truncate if too long
    if len(preview_text) > 200:
        preview_text = preview_text[:197] + '...'
        
    total_chars = sum(len(line.get('text', '')) for line in text_lines)
    
    return {
        'preview': preview_text,
        'total_characters': total_chars,
        'total_lines': len(text_lines)
    }

def get_table_summary(tables):
    """
    Generate summary of extracted tables
    
    Args:
        tables (list): List of table objects
        
    Returns:
        dict: Table summary information
    """
    if not tables:
        return {'total_tables': 0}
        
    total_cells = sum(table.get('cell_count', 0) for table in tables)
    avg_confidence = sum(table.get('confidence', 0) for table in tables) / len(tables)
    
    return {
        'total_tables': len(tables),
        'total_cells': total_cells,
        'average_confidence': round(avg_confidence, 2)
    }

def get_form_summary(forms):
    """
    Generate summary of extracted forms
    
    Args:
        forms (list): List of form objects
        
    Returns:
        dict: Form summary information
    """
    if not forms:
        return {'total_forms': 0}
        
    total_fields = len(forms)
    filled_fields = sum(1 for form in forms if form.get('value_text', '').strip())
    avg_confidence = sum(form.get('confidence', 0) for form in forms) / len(forms)
    
    return {
        'total_forms': total_fields,
        'filled_fields': filled_fields,
        'fill_rate': round(filled_fields / total_fields * 100, 1) if total_fields > 0 else 0,
        'average_confidence': round(avg_confidence, 2)
    }

def calculate_confidence_distribution(text_lines):
    """
    Calculate confidence score distribution
    
    Args:
        text_lines (list): List of text line objects
        
    Returns:
        dict: Confidence distribution statistics
    """
    if not text_lines:
        return {}
        
    confidences = [line.get('confidence', 0) for line in text_lines]
    
    # Calculate distribution
    high_confidence = sum(1 for c in confidences if c >= 90)
    medium_confidence = sum(1 for c in confidences if 70 <= c < 90)
    low_confidence = sum(1 for c in confidences if c < 70)
    
    total = len(confidences)
    
    return {
        'high_confidence_percent': round(high_confidence / total * 100, 1) if total > 0 else 0,
        'medium_confidence_percent': round(medium_confidence / total * 100, 1) if total > 0 else 0,
        'low_confidence_percent': round(low_confidence / total * 100, 1) if total > 0 else 0,
        'average_confidence': round(sum(confidences) / total, 2) if total > 0 else 0,
        'min_confidence': min(confidences) if confidences else 0,
        'max_confidence': max(confidences) if confidences else 0
    }

def process_dynamodb_result(result):
    """
    Process DynamoDB result for JSON serialization
    
    Args:
        result: DynamoDB query/scan result
        
    Returns:
        Processed result ready for JSON serialization
    """
    if isinstance(result, list):
        return [process_item(item) for item in result]
    elif isinstance(result, dict):
        return process_item(result)
    else:
        return result

def process_item(item):
    """
    Process individual DynamoDB item
    
    Args:
        item (dict): DynamoDB item
        
    Returns:
        dict: Processed item
    """
    processed = {}
    for key, value in item.items():
        if isinstance(value, Decimal):
            # Convert Decimal to float for JSON serialization
            processed[key] = float(value)
        elif isinstance(value, dict):
            processed[key] = process_item(value)
        elif isinstance(value, list):
            processed[key] = [process_item(v) if isinstance(v, dict) else v for v in value]
        else:
            processed[key] = value
    return processed

def decimal_default(obj):
    """
    JSON serializer for Decimal objects
    
    Args:
        obj: Object to serialize
        
    Returns:
        Serializable representation
    """
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError(f"Object of type {type(obj)} is not JSON serializable")