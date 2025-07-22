"""
Async Results Processor Lambda Function
Processes completion notifications from Amazon Textract async jobs
"""
import json
import boto3
import os
from datetime import datetime
from botocore.exceptions import ClientError

# Initialize AWS clients
textract = boto3.client('textract')
s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

# Environment variables
OUTPUT_BUCKET = os.environ['OUTPUT_BUCKET']
METADATA_TABLE = os.environ['METADATA_TABLE']

def lambda_handler(event, context):
    """
    Lambda handler for processing async Textract job completion
    
    Args:
        event: SNS notification from Textract
        context: Lambda runtime context
        
    Returns:
        dict: Processing status
    """
    try:
        # Parse SNS message
        sns_message = json.loads(event['Records'][0]['Sns']['Message'])
        
        job_id = sns_message['JobId']
        status = sns_message['Status']
        api = sns_message.get('API', 'Unknown')
        
        print(f"Processing async job completion: {job_id}, status: {status}, API: {api}")
        
        if status == 'SUCCEEDED':
            # Get results from Textract
            extracted_data = get_textract_results(job_id, api)
            
            # Save results to S3
            output_key = f"async-results/{job_id}-analysis.json"
            save_results_to_s3(extracted_data, output_key)
            
            # Update DynamoDB
            update_document_metadata(job_id, 'completed', f"s3://{OUTPUT_BUCKET}/{output_key}", extracted_data)
            
            print(f"Successfully processed async job {job_id}")
            
        elif status == 'FAILED':
            # Handle failed job
            error_message = sns_message.get('StatusMessage', 'Unknown error')
            print(f"Async job {job_id} failed: {error_message}")
            
            # Update DynamoDB with failed status
            update_document_metadata(job_id, 'failed', None, None, error_message)
            
        else:
            print(f"Unexpected job status: {status} for job {job_id}")
            
        return {
            'statusCode': 200,
            'body': {
                'jobId': job_id,
                'status': status,
                'processed': True
            }
        }
        
    except Exception as e:
        print(f"Error processing async results: {str(e)}")
        return {
            'statusCode': 500,
            'body': {
                'error': str(e),
                'errorType': type(e).__name__
            }
        }

def get_textract_results(job_id, api):
    """
    Retrieve results from completed Textract job
    
    Args:
        job_id (str): Textract job ID
        api (str): Textract API used (AnalyzeDocument or DetectDocumentText)
        
    Returns:
        dict: Extracted and structured data
    """
    try:
        print(f"Retrieving results for job {job_id} using {api}")
        
        # Determine which API to use for getting results
        if api == 'StartDocumentAnalysis':
            response = textract.get_document_analysis(JobId=job_id)
        elif api == 'StartDocumentTextDetection':
            response = textract.get_document_text_detection(JobId=job_id)
        else:
            # Default to document analysis
            response = textract.get_document_analysis(JobId=job_id)
            
        # Handle paginated results
        all_blocks = response['Blocks']
        next_token = response.get('NextToken')
        
        while next_token:
            print(f"Fetching additional pages for job {job_id}")
            if api == 'StartDocumentAnalysis':
                response = textract.get_document_analysis(JobId=job_id, NextToken=next_token)
            else:
                response = textract.get_document_text_detection(JobId=job_id, NextToken=next_token)
                
            all_blocks.extend(response['Blocks'])
            next_token = response.get('NextToken')
            
        print(f"Retrieved {len(all_blocks)} blocks for job {job_id}")
        
        # Extract structured data
        extracted_data = extract_structured_data({'Blocks': all_blocks}, job_id)
        return extracted_data
        
    except ClientError as e:
        print(f"AWS service error retrieving results: {str(e)}")
        raise
    except Exception as e:
        print(f"Unexpected error retrieving results: {str(e)}")
        raise

def extract_structured_data(response, job_id):
    """
    Extract structured data from Textract response
    
    Args:
        response (dict): Textract API response
        job_id (str): Textract job ID
        
    Returns:
        dict: Structured extracted data
    """
    blocks = response['Blocks']
    
    # Initialize data structures
    lines = []
    tables = []
    forms = []
    
    # Track processing statistics
    page_count = 0
    total_confidence = 0
    confidence_count = 0
    
    # Extract different types of content
    for block in blocks:
        if block['BlockType'] == 'PAGE':
            page_count += 1
        elif block['BlockType'] == 'LINE':
            confidence = block.get('Confidence', 0)
            total_confidence += confidence
            confidence_count += 1
            
            lines.append({
                'id': block['Id'],
                'text': block.get('Text', ''),
                'confidence': round(confidence, 2),
                'page': block.get('Page', 1),
                'geometry': extract_geometry(block.get('Geometry', {}))
            })
        elif block['BlockType'] == 'TABLE':
            tables.append(extract_table_data(block, blocks))
        elif block['BlockType'] == 'KEY_VALUE_SET':
            if block.get('EntityTypes') and 'KEY' in block['EntityTypes']:
                forms.append(extract_form_data(block, blocks))
    
    # Calculate statistics
    average_confidence = round(total_confidence / confidence_count, 2) if confidence_count > 0 else 0
    
    return {
        'text_lines': lines,
        'tables': tables,
        'forms': forms,
        'job_metadata': {
            'job_id': job_id,
            'page_count': page_count,
            'completion_time': datetime.utcnow().isoformat()
        },
        'processing_statistics': {
            'total_lines': len(lines),
            'total_tables': len(tables),
            'total_forms': len(forms),
            'total_pages': page_count,
            'average_confidence': average_confidence
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
    Extract table structure and data with enhanced processing
    
    Args:
        table_block (dict): Table block from Textract
        all_blocks (list): All blocks from Textract response
        
    Returns:
        dict: Enhanced table structure and data
    """
    table_id = table_block['Id']
    
    # Find all cells belonging to this table
    cells = []
    for block in all_blocks:
        if (block['BlockType'] == 'CELL' and 
            'Relationships' in block and
            any(rel['Type'] == 'CHILD' for rel in block.get('Relationships', []))):
            
            # Check if this cell belongs to our table
            if any(rel['Type'] == 'CHILD' and table_id in rel.get('Ids', []) 
                   for rel in table_block.get('Relationships', [])):
                cells.append({
                    'row': block.get('RowIndex', 0),
                    'column': block.get('ColumnIndex', 0),
                    'confidence': round(block.get('Confidence', 0), 2),
                    'text': get_cell_text(block, all_blocks)
                })
    
    return {
        'id': table_id,
        'confidence': round(table_block.get('Confidence', 0), 2),
        'geometry': extract_geometry(table_block.get('Geometry', {})),
        'cell_count': len(cells),
        'cells': sorted(cells, key=lambda x: (x['row'], x['column']))
    }

def extract_form_data(form_block, all_blocks):
    """
    Extract form key-value pairs with enhanced processing
    
    Args:
        form_block (dict): Form block from Textract
        all_blocks (list): All blocks from Textract response
        
    Returns:
        dict: Enhanced form key-value data
    """
    # Find the corresponding value block
    value_text = ""
    if 'Relationships' in form_block:
        for relationship in form_block['Relationships']:
            if relationship['Type'] == 'VALUE':
                value_ids = relationship.get('Ids', [])
                for value_id in value_ids:
                    value_block = next((b for b in all_blocks if b['Id'] == value_id), None)
                    if value_block:
                        value_text = get_block_text(value_block, all_blocks)
                        break
    
    return {
        'id': form_block['Id'],
        'confidence': round(form_block.get('Confidence', 0), 2),
        'key_text': get_block_text(form_block, all_blocks),
        'value_text': value_text,
        'entity_types': form_block.get('EntityTypes', []),
        'geometry': extract_geometry(form_block.get('Geometry', {}))
    }

def get_cell_text(cell_block, all_blocks):
    """
    Extract text from a table cell
    
    Args:
        cell_block (dict): Cell block from Textract
        all_blocks (list): All blocks from Textract response
        
    Returns:
        str: Cell text content
    """
    text_parts = []
    
    if 'Relationships' in cell_block:
        for relationship in cell_block['Relationships']:
            if relationship['Type'] == 'CHILD':
                for child_id in relationship.get('Ids', []):
                    child_block = next((b for b in all_blocks if b['Id'] == child_id), None)
                    if child_block and child_block['BlockType'] == 'WORD':
                        text_parts.append(child_block.get('Text', ''))
    
    return ' '.join(text_parts)

def get_block_text(block, all_blocks):
    """
    Extract text from a block and its children
    
    Args:
        block (dict): Block from Textract
        all_blocks (list): All blocks from Textract response
        
    Returns:
        str: Block text content
    """
    if block.get('Text'):
        return block['Text']
    
    text_parts = []
    if 'Relationships' in block:
        for relationship in block['Relationships']:
            if relationship['Type'] == 'CHILD':
                for child_id in relationship.get('Ids', []):
                    child_block = next((b for b in all_blocks if b['Id'] == child_id), None)
                    if child_block:
                        if child_block['BlockType'] == 'WORD':
                            text_parts.append(child_block.get('Text', ''))
                        elif child_block.get('Text'):
                            text_parts.append(child_block['Text'])
    
    return ' '.join(text_parts)

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
                'extractor': 'async-results-processor-lambda',
                'job-id': data.get('job_metadata', {}).get('job_id', 'unknown')
            }
        )
        print(f"Async results saved to s3://{OUTPUT_BUCKET}/{output_key}")
    except Exception as e:
        print(f"Error saving async results to S3: {str(e)}")
        raise

def update_document_metadata(job_id, status, output_location, extracted_data=None, error_message=None):
    """
    Update document metadata in DynamoDB
    
    Args:
        job_id (str): Textract job ID
        status (str): Processing status
        output_location (str): S3 location of results
        extracted_data (dict): Extracted data summary
        error_message (str): Error message if failed
    """
    try:
        table = dynamodb.Table(METADATA_TABLE)
        
        # Find document by job ID
        response = table.scan(
            FilterExpression='jobId = :jid',
            ExpressionAttributeValues={':jid': job_id},
            ProjectionExpression='documentId'
        )
        
        if not response['Items']:
            print(f"No document found for job ID {job_id}")
            return
            
        document_id = response['Items'][0]['documentId']
        
        # Prepare update parameters
        update_expression = 'SET processingStatus = :status, completedAt = :timestamp'
        expression_values = {
            ':status': status,
            ':timestamp': datetime.utcnow().isoformat()
        }
        
        if output_location:
            update_expression += ', outputLocation = :location'
            expression_values[':location'] = output_location
            
        if extracted_data and extracted_data.get('processing_statistics'):
            update_expression += ', extractedDataSummary = :summary'
            expression_values[':summary'] = extracted_data['processing_statistics']
            
        if error_message:
            update_expression += ', errorMessage = :error'
            expression_values[':error'] = error_message
        
        # Update the document
        table.update_item(
            Key={'documentId': document_id},
            UpdateExpression=update_expression,
            ExpressionAttributeValues=expression_values
        )
        
        print(f"Updated metadata for document {document_id} (job {job_id})")
        
    except Exception as e:
        print(f"Error updating document metadata: {str(e)}")
        # Don't raise here - metadata update failure shouldn't fail the whole process