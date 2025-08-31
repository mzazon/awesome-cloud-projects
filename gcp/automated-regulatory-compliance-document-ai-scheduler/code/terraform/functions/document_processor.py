import json
import base64
from google.cloud import documentai
from google.cloud import storage
from google.cloud import logging
import functions_framework
import os
import re
from datetime import datetime

# Initialize clients
storage_client = storage.Client()
documentai_client = documentai.DocumentProcessorServiceClient()
logging_client = logging.Client()
logger = logging_client.logger('compliance-processor')

PROJECT_ID = os.environ.get('PROJECT_ID', '${project_id}')
REGION = os.environ.get('REGION', '${region}')
PROCESSOR_ID = os.environ.get('PROCESSOR_ID', '${processor_id}')
PROCESSED_BUCKET = os.environ.get('PROCESSED_BUCKET', '${processed_bucket}')

@functions_framework.cloud_event
def process_compliance_document(cloud_event):
    """Process uploaded document with Document AI and apply compliance rules."""
    
    try:
        # Parse Cloud Storage event
        data = cloud_event.data
        bucket_name = data['bucket']
        file_name = data['name']
        
        logger.log_text(f"Processing document: {file_name}")
        
        # Download document from Cloud Storage
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_name)
        document_content = blob.download_as_bytes()
        
        # Process document with Document AI
        processor_name = PROCESSOR_ID
        
        # Handle different document types
        mime_type = get_mime_type(file_name)
        document = documentai.Document(content=document_content, mime_type=mime_type)
        request = documentai.ProcessRequest(name=processor_name, document=document)
        
        result = documentai_client.process_document(request=request)
        
        # Extract compliance-relevant data
        compliance_data = extract_compliance_data(result.document)
        
        # Apply compliance validation rules
        validation_results = validate_compliance_data(compliance_data, file_name)
        
        # Store processed results
        output_data = {
            'document_name': file_name,
            'processed_timestamp': datetime.utcnow().isoformat(),
            'extracted_data': compliance_data,
            'validation_results': validation_results,
            'compliance_status': validation_results.get('overall_status', 'UNKNOWN')
        }
        
        # Save to processed bucket
        output_bucket = storage_client.bucket(PROCESSED_BUCKET)
        output_blob_name = f"processed/{file_name.split('.')[0]}_processed.json"
        output_blob = output_bucket.blob(output_blob_name)
        output_blob.upload_from_string(json.dumps(output_data, indent=2))
        
        logger.log_text(f"Document processed successfully: {output_blob_name}")
        
        return {'status': 'success', 'processed_file': output_blob_name}
        
    except Exception as e:
        error_msg = f"Error processing document {file_name}: {str(e)}"
        logger.log_text(error_msg, severity='ERROR')
        raise Exception(error_msg)

def get_mime_type(file_name):
    """Determine MIME type based on file extension."""
    extension = file_name.lower().split('.')[-1]
    mime_types = {
        'pdf': 'application/pdf',
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'png': 'image/png',
        'tif': 'image/tiff',
        'tiff': 'image/tiff'
    }
    return mime_types.get(extension, 'application/pdf')

def extract_compliance_data(document):
    """Extract key compliance-related information from Document AI results."""
    compliance_data = {
        'entities': [],
        'key_value_pairs': {},
        'tables': [],
        'text_content': document.text[:5000]  # Limit text content
    }
    
    # Extract form fields (key-value pairs)
    for page in document.pages:
        for form_field in page.form_fields:
            field_name = get_text(form_field.field_name, document)
            field_value = get_text(form_field.field_value, document)
            
            if field_name and field_value:
                compliance_data['key_value_pairs'][field_name.strip()] = field_value.strip()
    
    # Extract entities (dates, amounts, names)
    for entity in document.entities:
        if entity.confidence > 0.5:  # Only include high-confidence entities
            compliance_data['entities'].append({
                'type': entity.type_,
                'mention': entity.mention_text,
                'confidence': entity.confidence
            })
    
    # Extract table data
    for page in document.pages:
        for table in page.tables:
            table_data = []
            for row in table.body_rows:
                row_data = []
                for cell in row.cells:
                    cell_text = get_text(cell.layout, document)
                    row_data.append(cell_text.strip())
                table_data.append(row_data)
            if table_data:
                compliance_data['tables'].append(table_data)
    
    return compliance_data

def validate_compliance_data(data, document_name):
    """Apply compliance validation rules to extracted data."""
    validation_results = {
        'overall_status': 'COMPLIANT',
        'violations': [],
        'warnings': [],
        'checks_performed': []
    }
    
    # Check for required fields based on document type
    required_fields = ['Date', 'Amount', 'Signature', 'Company Name']
    
    for field in required_fields:
        field_found = any(field.lower() in key.lower() for key in data['key_value_pairs'].keys())
        
        if field_found:
            validation_results['checks_performed'].append(f"Required field '{field}' found")
        else:
            validation_results['violations'].append(f"Missing required field: {field}")
            validation_results['overall_status'] = 'NON_COMPLIANT'
    
    # Validate date formats for compliance reporting
    for key, value in data['key_value_pairs'].items():
        if 'date' in key.lower() and value:
            if not validate_date_format(value):
                validation_results['warnings'].append(f"Date format may be invalid: {key}={value}")
    
    # Check for compliance indicators in text
    compliance_keywords = ['SOX', 'HIPAA', 'GDPR', 'compliance', 'audit', 'regulation']
    text_content = data.get('text_content', '').lower()
    
    found_keywords = [kw for kw in compliance_keywords if kw.lower() in text_content]
    if found_keywords:
        validation_results['checks_performed'].append(f"Compliance keywords found: {', '.join(found_keywords)}")
    
    return validation_results

def validate_date_format(date_string):
    """Validate common date formats for compliance documents."""
    if not date_string or len(date_string.strip()) == 0:
        return False
        
    date_patterns = [
        r'\d{4}-\d{2}-\d{2}',  # YYYY-MM-DD
        r'\d{2}/\d{2}/\d{4}',  # MM/DD/YYYY
        r'\d{2}-\d{2}-\d{4}',  # MM-DD-YYYY
        r'\d{1,2}/\d{1,2}/\d{4}',  # M/D/YYYY
        r'[A-Za-z]+ \d{1,2}, \d{4}'  # Month DD, YYYY
    ]
    
    return any(re.search(pattern, date_string.strip()) for pattern in date_patterns)

def get_text(element, document):
    """Extract text from Document AI text segments."""
    if not element or not element.text_anchor:
        return ""
    
    response = ""
    for segment in element.text_anchor.text_segments:
        start_index = int(segment.start_index) if segment.start_index else 0
        end_index = int(segment.end_index) if segment.end_index else len(document.text)
        response += document.text[start_index:end_index]
    
    return response