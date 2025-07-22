#!/usr/bin/env python3
"""
Document Processing Service for Google Cloud
This Cloud Run service processes documents using Document AI and stores results in Cloud Storage.
"""

import os
import json
import base64
import logging
from typing import Dict, Any, Optional
from flask import Flask, request, jsonify
from google.cloud import documentai_v1 as documentai
from google.cloud import storage
from google.cloud.exceptions import GoogleCloudError

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Initialize Flask application
app = Flask(__name__)

# Environment variables (injected by Terraform)
PROJECT_ID = "${project_id}"
REGION = "${region}"
PROCESSOR_ID = "${processor_id}"

# Initialize Google Cloud clients
try:
    document_ai_client = documentai.DocumentProcessorServiceClient()
    storage_client = storage.Client()
    logger.info("Google Cloud clients initialized successfully")
except Exception as e:
    logger.error(f"Failed to initialize Google Cloud clients: {e}")
    raise


@app.route('/', methods=['GET'])
def health_check():
    """Health check endpoint for Cloud Run service"""
    return jsonify({
        'status': 'healthy',
        'service': 'document-processor',
        'version': '1.0.0',
        'project_id': PROJECT_ID,
        'region': REGION
    }), 200


@app.route('/', methods=['POST'])
def process_document():
    """
    Main endpoint that processes Pub/Sub messages containing document upload events
    """
    try:
        # Parse Pub/Sub message envelope
        envelope = request.get_json(silent=True)
        if not envelope:
            logger.warning("Received request without JSON body")
            return jsonify({'error': 'No JSON body provided'}), 400
        
        # Extract message data
        pubsub_message = envelope.get('message', {})
        data = pubsub_message.get('data', '')
        
        if not data:
            logger.warning("Received Pub/Sub message without data")
            return jsonify({'error': 'No message data provided'}), 400
        
        # Decode base64 message data
        try:
            message_data = json.loads(base64.b64decode(data).decode('utf-8'))
            logger.info(f"Decoded Pub/Sub message: {message_data.get('name', 'unknown')}")
        except (json.JSONDecodeError, UnicodeDecodeError, ValueError) as e:
            logger.error(f"Failed to decode message data: {e}")
            return jsonify({'error': 'Invalid message data format'}), 400
        
        # Extract bucket and object information
        bucket_name = message_data.get('bucket')
        object_name = message_data.get('name')
        
        if not bucket_name or not object_name:
            logger.warning(f"Missing bucket or object info: bucket={bucket_name}, object={object_name}")
            return jsonify({'error': 'Missing bucket or object information'}), 400
        
        # Skip processing for files in the processed folder
        if object_name.startswith('processed/') or object_name.startswith('source/'):
            logger.info(f"Skipping processing for file in excluded folder: {object_name}")
            return jsonify({'message': 'File skipped - in excluded folder'}), 200
        
        # Process the document
        try:
            result = process_with_documentai(bucket_name, object_name)
            
            logger.info(f"Successfully processed document: {object_name}")
            logger.info(f"Extracted {len(result.get('entities', []))} entities")
            
            return jsonify({
                'status': 'success',
                'message': f'Document {object_name} processed successfully',
                'entities_count': len(result.get('entities', [])),
                'text_length': len(result.get('text', ''))
            }), 200
            
        except Exception as e:
            logger.error(f"Error processing document {object_name}: {str(e)}")
            return jsonify({
                'error': f'Document processing failed: {str(e)}',
                'object_name': object_name
            }), 500
    
    except Exception as e:
        logger.error(f"Unexpected error in process_document: {str(e)}")
        return jsonify({'error': 'Internal server error'}), 500


def process_with_documentai(bucket_name: str, object_name: str) -> Dict[str, Any]:
    """
    Process a document using Document AI and store results
    
    Args:
        bucket_name: Name of the Cloud Storage bucket
        object_name: Name of the object in the bucket
        
    Returns:
        Dictionary containing extracted data
        
    Raises:
        GoogleCloudError: If Document AI processing fails
        Exception: For other processing errors
    """
    try:
        # Construct processor name
        processor_name = f"projects/{PROJECT_ID}/locations/{REGION}/processors/{PROCESSOR_ID}"
        logger.info(f"Using Document AI processor: {processor_name}")
        
        # Download document from Cloud Storage
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(object_name)
        
        if not blob.exists():
            raise FileNotFoundError(f"Object {object_name} not found in bucket {bucket_name}")
        
        # Get document content and MIME type
        document_content = blob.download_as_bytes()
        content_type = blob.content_type or 'application/octet-stream'
        
        logger.info(f"Downloaded document: {object_name} ({len(document_content)} bytes)")
        
        # Determine MIME type for Document AI
        mime_type = get_mime_type(object_name, content_type)
        
        # Create Document AI request
        raw_document = documentai.RawDocument(
            content=document_content,
            mime_type=mime_type
        )
        
        request = documentai.ProcessRequest(
            name=processor_name,
            raw_document=raw_document
        )
        
        # Process document with Document AI
        logger.info(f"Processing document with Document AI...")
        result = document_ai_client.process_document(request=request)
        
        if not result.document:
            raise ValueError("Document AI returned empty result")
        
        # Extract structured data from the result
        extracted_data = extract_document_data(result.document, object_name)
        
        # Save results to Cloud Storage
        save_processing_results(bucket, object_name, extracted_data)
        
        logger.info(f"Document processing completed for: {object_name}")
        return extracted_data
        
    except GoogleCloudError as e:
        logger.error(f"Google Cloud error processing {object_name}: {e}")
        raise
    except Exception as e:
        logger.error(f"Unexpected error processing {object_name}: {e}")
        raise


def extract_document_data(document: documentai.Document, source_file: str) -> Dict[str, Any]:
    """
    Extract structured data from Document AI result
    
    Args:
        document: Document AI document object
        source_file: Original file name
        
    Returns:
        Dictionary with extracted data
    """
    extracted_data = {
        'source_file': source_file,
        'document_text': document.text,
        'entities': [],
        'form_fields': [],
        'tables': [],
        'confidence_scores': {},
        'processing_timestamp': None
    }
    
    # Import datetime here to avoid circular imports
    from datetime import datetime, timezone
    extracted_data['processing_timestamp'] = datetime.now(timezone.utc).isoformat()
    
    # Extract form fields from the first page
    if document.pages:
        page = document.pages[0]
        
        # Extract form fields (key-value pairs)
        for form_field in page.form_fields:
            field_name = ""
            field_value = ""
            field_confidence = 0.0
            
            # Extract field name
            if form_field.field_name and form_field.field_name.text_anchor:
                field_name = get_text_from_anchor(document.text, form_field.field_name.text_anchor)
            
            # Extract field value
            if form_field.field_value and form_field.field_value.text_anchor:
                field_value = get_text_from_anchor(document.text, form_field.field_value.text_anchor)
                field_confidence = form_field.field_value.confidence
            
            if field_name and field_value:
                extracted_data['form_fields'].append({
                    'name': field_name.strip(),
                    'value': field_value.strip(),
                    'confidence': field_confidence
                })
        
        # Extract tables
        for table in page.tables:
            table_data = []
            for row in table.body_rows:
                row_data = []
                for cell in row.cells:
                    cell_text = ""
                    if cell.layout and cell.layout.text_anchor:
                        cell_text = get_text_from_anchor(document.text, cell.layout.text_anchor)
                    row_data.append(cell_text.strip())
                table_data.append(row_data)
            
            if table_data:
                extracted_data['tables'].append({
                    'rows': table_data,
                    'row_count': len(table_data),
                    'column_count': len(table_data[0]) if table_data else 0
                })
    
    # Extract entities (if available)
    for entity in document.entities:
        entity_data = {
            'type': entity.type_,
            'mention_text': entity.mention_text,
            'confidence': entity.confidence,
            'normalized_value': {}
        }
        
        # Add normalized value if available
        if entity.normalized_value:
            if entity.normalized_value.text:
                entity_data['normalized_value']['text'] = entity.normalized_value.text
            if entity.normalized_value.money_value:
                entity_data['normalized_value']['money'] = {
                    'currency_code': entity.normalized_value.money_value.currency_code,
                    'units': str(entity.normalized_value.money_value.units),
                    'nanos': entity.normalized_value.money_value.nanos
                }
            if entity.normalized_value.date_value:
                entity_data['normalized_value']['date'] = {
                    'year': entity.normalized_value.date_value.year,
                    'month': entity.normalized_value.date_value.month,
                    'day': entity.normalized_value.date_value.day
                }
        
        extracted_data['entities'].append(entity_data)
    
    # Calculate overall confidence scores
    if extracted_data['form_fields']:
        field_confidences = [field['confidence'] for field in extracted_data['form_fields'] if field['confidence'] > 0]
        if field_confidences:
            extracted_data['confidence_scores']['average_field_confidence'] = sum(field_confidences) / len(field_confidences)
    
    if extracted_data['entities']:
        entity_confidences = [entity['confidence'] for entity in extracted_data['entities'] if entity['confidence'] > 0]
        if entity_confidences:
            extracted_data['confidence_scores']['average_entity_confidence'] = sum(entity_confidences) / len(entity_confidences)
    
    logger.info(f"Extracted {len(extracted_data['form_fields'])} form fields, {len(extracted_data['entities'])} entities, {len(extracted_data['tables'])} tables")
    return extracted_data


def get_text_from_anchor(document_text: str, text_anchor: documentai.Document.TextAnchor) -> str:
    """
    Extract text from document using text anchor
    
    Args:
        document_text: Full document text
        text_anchor: Text anchor object
        
    Returns:
        Extracted text segment
    """
    if not text_anchor.text_segments:
        return ""
    
    # Use the first text segment
    segment = text_anchor.text_segments[0]
    start_index = int(segment.start_index) if segment.start_index else 0
    end_index = int(segment.end_index) if segment.end_index else len(document_text)
    
    return document_text[start_index:end_index]


def save_processing_results(bucket: storage.Bucket, object_name: str, extracted_data: Dict[str, Any]) -> None:
    """
    Save processing results to Cloud Storage
    
    Args:
        bucket: Cloud Storage bucket object
        object_name: Original object name
        extracted_data: Extracted data to save
    """
    try:
        # Create result file name
        base_name = object_name.rsplit('.', 1)[0] if '.' in object_name else object_name
        result_object_name = f"processed/{base_name}.json"
        
        # Create blob and upload results
        result_blob = bucket.blob(result_object_name)
        result_blob.upload_from_string(
            json.dumps(extracted_data, indent=2, ensure_ascii=False),
            content_type='application/json'
        )
        
        logger.info(f"Results saved to: gs://{bucket.name}/{result_object_name}")
        
    except Exception as e:
        logger.error(f"Failed to save results for {object_name}: {e}")
        raise


def get_mime_type(file_name: str, content_type: str) -> str:
    """
    Determine MIME type for Document AI based on file extension and content type
    
    Args:
        file_name: Name of the file
        content_type: Content type from Cloud Storage
        
    Returns:
        MIME type for Document AI
    """
    # Document AI supported MIME types
    supported_types = {
        '.pdf': 'application/pdf',
        '.tif': 'image/tiff',
        '.tiff': 'image/tiff',
        '.jpg': 'image/jpeg',
        '.jpeg': 'image/jpeg',
        '.png': 'image/png',
        '.bmp': 'image/bmp',
        '.webp': 'image/webp',
        '.gif': 'image/gif'
    }
    
    # Check file extension first
    for ext, mime_type in supported_types.items():
        if file_name.lower().endswith(ext):
            return mime_type
    
    # Fall back to content type if supported
    if content_type in supported_types.values():
        return content_type
    
    # Default to PDF for unknown types
    logger.warning(f"Unknown file type for {file_name}, defaulting to application/pdf")
    return 'application/pdf'


@app.errorhandler(Exception)
def handle_error(error):
    """Global error handler for the Flask application"""
    logger.error(f"Unhandled error: {str(error)}")
    return jsonify({
        'error': 'Internal server error',
        'message': str(error)
    }), 500


if __name__ == '__main__':
    # Run the Flask application
    port = int(os.environ.get('PORT', 8080))
    app.run(host='0.0.0.0', port=port, debug=False)