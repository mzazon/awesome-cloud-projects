"""
Cloud Function for processing compliance documents using Document AI
Processes uploaded compliance documents and extracts structured data for reporting
"""

import json
import base64
import os
from typing import Dict, Any, Optional
from google.cloud import documentai
from google.cloud import storage
from google.cloud import logging
import functions_framework


# Initialize clients
doc_client = documentai.DocumentProcessorServiceClient()
storage_client = storage.Client()
logging_client = logging.Client()
logger = logging_client.logger("compliance-processor")

# Environment variables
PROJECT_ID = os.environ.get('PROJECT_ID', '${project_id}')
REGION = os.environ.get('REGION', '${region}')
PROCESSOR_ID = os.environ.get('PROCESSOR_ID', '${processor_id}')


@functions_framework.cloud_event
def process_compliance_document(cloud_event) -> None:
    """
    Process uploaded compliance documents using Document AI
    
    This function is triggered when documents are uploaded to the compliance bucket.
    It extracts structured data from documents and stores the results for reporting.
    
    Args:
        cloud_event: CloudEvent containing the storage trigger information
    """
    try:
        # Extract event data
        data = cloud_event.data
        bucket_name = data['bucket']
        file_name = data['name']
        
        logger.log_text(f"Processing document upload: {file_name} in bucket: {bucket_name}")
        
        # Skip processing for non-document files and already processed files
        if not _is_processable_document(file_name):
            logger.log_text(f"Skipping non-document file: {file_name}")
            return
            
        if file_name.startswith('processed/') or file_name.startswith('functions/'):
            logger.log_text(f"Skipping internal file: {file_name}")
            return
        
        # Process the document
        extracted_data = _process_document_with_ai(bucket_name, file_name)
        
        if extracted_data:
            # Save extracted data for compliance reporting
            _save_processed_data(bucket_name, file_name, extracted_data)
            logger.log_text(f"Successfully processed compliance document: {file_name}")
        else:
            logger.log_text(f"No data extracted from document: {file_name}")
            
    except Exception as e:
        logger.log_text(f"Error processing document {file_name}: {str(e)}", severity="ERROR")
        raise


def _is_processable_document(file_name: str) -> bool:
    """Check if the file is a processable document type"""
    processable_extensions = ('.pdf', '.png', '.jpg', '.jpeg', '.tiff', '.gif', '.bmp')
    return file_name.lower().endswith(processable_extensions)


def _process_document_with_ai(bucket_name: str, file_name: str) -> Optional[Dict[str, Any]]:
    """
    Process document using Document AI and extract structured data
    
    Args:
        bucket_name: Name of the storage bucket
        file_name: Name of the document file
        
    Returns:
        Dictionary containing extracted compliance data
    """
    try:
        # Download document from storage
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_name)
        document_content = blob.download_as_bytes()
        
        # Determine MIME type based on file extension
        mime_type = _get_mime_type(file_name)
        
        # Create Document AI request
        raw_document = documentai.RawDocument(
            content=document_content,
            mime_type=mime_type
        )
        
        # Process document with Document AI
        request = documentai.ProcessRequest(
            name=PROCESSOR_ID,
            raw_document=raw_document
        )
        
        result = doc_client.process_document(request=request)
        document = result.document
        
        # Extract compliance-relevant information
        extracted_data = {
            "document_name": file_name,
            "upload_timestamp": blob.time_created.isoformat() if blob.time_created else None,
            "file_size_bytes": blob.size,
            "mime_type": mime_type,
            "extraction_timestamp": _get_current_timestamp(),
            "extraction_confidence": _calculate_confidence(document),
            "text_content": document.text[:5000],  # First 5000 chars for compliance review
            "entities": _extract_entities(document),
            "form_fields": _extract_form_fields(document),
            "compliance_metadata": _extract_compliance_metadata(document, file_name)
        }
        
        return extracted_data
        
    except Exception as e:
        logger.log_text(f"Error in Document AI processing: {str(e)}", severity="ERROR")
        return None


def _get_mime_type(file_name: str) -> str:
    """Determine MIME type based on file extension"""
    extension = file_name.lower().split('.')[-1]
    mime_types = {
        'pdf': 'application/pdf',
        'png': 'image/png',
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'tiff': 'image/tiff',
        'gif': 'image/gif',
        'bmp': 'image/bmp'
    }
    return mime_types.get(extension, 'application/pdf')


def _calculate_confidence(document) -> float:
    """Calculate overall extraction confidence from Document AI results"""
    if not document.pages:
        return 0.0
        
    confidences = []
    
    # Collect confidence scores from form fields
    for page in document.pages:
        if page.form_fields:
            for field in page.form_fields:
                if field.field_name and field.field_name.confidence:
                    confidences.append(field.field_name.confidence)
                if field.field_value and field.field_value.confidence:
                    confidences.append(field.field_value.confidence)
    
    # Collect confidence scores from entities
    for entity in document.entities:
        if entity.confidence:
            confidences.append(entity.confidence)
    
    return sum(confidences) / len(confidences) if confidences else 0.0


def _extract_entities(document) -> list:
    """Extract entities from Document AI results for compliance analysis"""
    entities = []
    
    for entity in document.entities:
        entity_data = {
            "type": entity.type_,
            "mention_text": entity.mention_text,
            "confidence": entity.confidence,
            "normalized_value": entity.normalized_value.text if entity.normalized_value else None
        }
        entities.append(entity_data)
    
    return entities


def _extract_form_fields(document) -> list:
    """Extract form fields for compliance document analysis"""
    form_fields = []
    
    for page in document.pages:
        if page.form_fields:
            for field in page.form_fields:
                field_data = {
                    "field_name": field.field_name.text_anchor.content if field.field_name and field.field_name.text_anchor else None,
                    "field_value": field.field_value.text_anchor.content if field.field_value and field.field_value.text_anchor else None,
                    "confidence": field.field_name.confidence if field.field_name else 0.0
                }
                form_fields.append(field_data)
    
    return form_fields


def _extract_compliance_metadata(document, file_name: str) -> Dict[str, Any]:
    """Extract compliance-specific metadata from the document"""
    metadata = {
        "document_type": _classify_document_type(file_name, document.text),
        "compliance_framework": _identify_compliance_framework(document.text),
        "contains_sensitive_data": _detect_sensitive_data(document.text),
        "policy_version": _extract_policy_version(document.text),
        "effective_date": _extract_effective_date(document.text),
        "page_count": len(document.pages)
    }
    
    return metadata


def _classify_document_type(file_name: str, text: str) -> str:
    """Classify the type of compliance document"""
    text_lower = text.lower()
    file_lower = file_name.lower()
    
    if any(keyword in text_lower for keyword in ['policy', 'procedure', 'standard']):
        return "Policy Document"
    elif any(keyword in text_lower for keyword in ['contract', 'agreement', 'terms']):
        return "Contract"
    elif any(keyword in text_lower for keyword in ['audit', 'assessment', 'review']):
        return "Audit Document"
    elif any(keyword in file_lower for keyword in ['soc', 'iso', 'hipaa', 'pci']):
        return "Compliance Certificate"
    else:
        return "General Document"


def _identify_compliance_framework(text: str) -> list:
    """Identify compliance frameworks mentioned in the document"""
    text_lower = text.lower()
    frameworks = []
    
    framework_keywords = {
        'SOC2': ['soc 2', 'soc2', 'service organization control'],
        'ISO27001': ['iso 27001', 'iso27001', 'information security management'],
        'HIPAA': ['hipaa', 'health insurance portability'],
        'PCI': ['pci dss', 'payment card industry'],
        'GDPR': ['gdpr', 'general data protection regulation']
    }
    
    for framework, keywords in framework_keywords.items():
        if any(keyword in text_lower for keyword in keywords):
            frameworks.append(framework)
    
    return frameworks


def _detect_sensitive_data(text: str) -> bool:
    """Detect if document contains sensitive data indicators"""
    sensitive_indicators = [
        'confidential', 'sensitive', 'private', 'restricted',
        'ssn', 'social security', 'credit card', 'personal information',
        'phi', 'pii', 'protected health information'
    ]
    
    text_lower = text.lower()
    return any(indicator in text_lower for indicator in sensitive_indicators)


def _extract_policy_version(text: str) -> Optional[str]:
    """Extract policy version from document text"""
    import re
    
    # Look for version patterns
    version_patterns = [
        r'version\s*:?\s*(\d+\.?\d*\.?\d*)',
        r'v\s*(\d+\.?\d*\.?\d*)',
        r'revision\s*:?\s*(\d+\.?\d*\.?\d*)'
    ]
    
    for pattern in version_patterns:
        match = re.search(pattern, text, re.IGNORECASE)
        if match:
            return match.group(1)
    
    return None


def _extract_effective_date(text: str) -> Optional[str]:
    """Extract effective date from document text"""
    import re
    
    # Look for date patterns
    date_patterns = [
        r'effective\s+date\s*:?\s*(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})',
        r'effective\s*:?\s*(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})',
        r'date\s*:?\s*(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})'
    ]
    
    for pattern in date_patterns:
        match = re.search(pattern, text, re.IGNORECASE)
        if match:
            return match.group(1)
    
    return None


def _save_processed_data(bucket_name: str, file_name: str, extracted_data: Dict[str, Any]) -> None:
    """Save processed compliance data to storage for reporting"""
    try:
        bucket = storage_client.bucket(bucket_name)
        
        # Create output file name
        base_name = file_name.split('/')[-1].split('.')[0]
        output_file_name = f"processed/{base_name}_processed.json"
        
        # Save extracted data
        output_blob = bucket.blob(output_file_name)
        output_blob.upload_from_string(
            json.dumps(extracted_data, indent=2, ensure_ascii=False),
            content_type='application/json'
        )
        
        logger.log_text(f"Saved processed data to: {output_file_name}")
        
    except Exception as e:
        logger.log_text(f"Error saving processed data: {str(e)}", severity="ERROR")
        raise


def _get_current_timestamp() -> str:
    """Get current timestamp in ISO format"""
    from datetime import datetime
    return datetime.utcnow().isoformat() + "Z"