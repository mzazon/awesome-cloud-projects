#!/usr/bin/env python3
"""
Cloud Function for monitoring Filestore documents and triggering processing pipeline.
This function demonstrates document detection and Pub/Sub message publishing.
"""

import os
import json
import hashlib
import logging
from datetime import datetime
from typing import Dict, Any, Optional

from google.cloud import pubsub_v1
from google.cloud import storage
import functions_framework

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Pub/Sub client
publisher = pubsub_v1.PublisherClient()

# Configuration from environment variables
PROJECT_ID = "${project_id}"
PUBSUB_TOPIC = "${pubsub_topic}"
FILESTORE_IP = "${filestore_ip}"
FILESTORE_SHARE = "${filestore_share}"

# Construct topic path
topic_path = publisher.topic_path(PROJECT_ID, PUBSUB_TOPIC)


@functions_framework.cloud_event
def monitor_documents(cloud_event) -> None:
    """
    Monitor Filestore for new documents and publish processing messages.
    
    In a production environment, this function would:
    1. Monitor the actual Filestore mount point for new files
    2. Use file system events or periodic scanning
    3. Track processed files to avoid duplicates
    4. Handle various document formats and validation
    
    For demonstration purposes, this function simulates document detection
    and publishes sample messages to trigger the processing pipeline.
    
    Args:
        cloud_event: Cloud Event triggering the function
    """
    
    try:
        logger.info(f"Document monitor function triggered at {datetime.utcnow().isoformat()}")
        logger.info(f"Monitoring Filestore at IP: {FILESTORE_IP}, Share: {FILESTORE_SHARE}")
        
        # In production, you would scan the actual Filestore mount
        # filestore_path = f"/mnt/filestore/{FILESTORE_SHARE}"
        
        # For demonstration, simulate finding new documents
        simulated_documents = generate_sample_documents()
        
        published_count = 0
        for document in simulated_documents:
            try:
                # Create document processing message
                message_data = create_processing_message(document)
                
                # Publish to Pub/Sub
                publish_message(message_data)
                published_count += 1
                
                logger.info(f"Successfully published message for document: {document['filename']}")
                
            except Exception as doc_error:
                logger.error(f"Failed to process document {document.get('filename', 'unknown')}: {str(doc_error)}")
                continue
        
        logger.info(f"Document monitoring completed. Published {published_count} messages.")
        
    except Exception as e:
        logger.error(f"Error in document monitoring function: {str(e)}")
        raise


def generate_sample_documents() -> list:
    """
    Generate sample document entries for demonstration.
    In production, this would scan the actual Filestore directory.
    
    Returns:
        List of document dictionaries with file information
    """
    
    base_path = f"/mnt/filestore/{FILESTORE_SHARE}"
    
    sample_documents = [
        {
            "filename": "invoice_001.pdf",
            "filepath": f"{base_path}/invoices/invoice_001.pdf",
            "category": "invoice",
            "size_bytes": 245760,
            "mime_type": "application/pdf"
        },
        {
            "filename": "receipt_002.jpg", 
            "filepath": f"{base_path}/receipts/receipt_002.jpg",
            "category": "receipt",
            "size_bytes": 132048,
            "mime_type": "image/jpeg"
        },
        {
            "filename": "contract_003.png",
            "filepath": f"{base_path}/contracts/contract_003.png", 
            "category": "contract",
            "size_bytes": 891024,
            "mime_type": "image/png"
        },
        {
            "filename": "form_004.tiff",
            "filepath": f"{base_path}/forms/form_004.tiff",
            "category": "form", 
            "size_bytes": 512000,
            "mime_type": "image/tiff"
        }
    ]
    
    return sample_documents


def create_processing_message(document: Dict[str, Any]) -> Dict[str, Any]:
    """
    Create a structured message for document processing.
    
    Args:
        document: Document information dictionary
        
    Returns:
        Processing message dictionary
    """
    
    # Generate unique processing ID
    processing_id = hashlib.md5(
        f"{document['filepath']}{datetime.utcnow().isoformat()}".encode()
    ).hexdigest()
    
    message_data = {
        "processing_id": processing_id,
        "filename": document["filename"],
        "filepath": document["filepath"],
        "category": document.get("category", "unknown"),
        "size_bytes": document.get("size_bytes", 0),
        "mime_type": document.get("mime_type", "application/octet-stream"),
        "timestamp": datetime.utcnow().isoformat(),
        "filestore_ip": FILESTORE_IP,
        "filestore_share": FILESTORE_SHARE,
        "source": "filestore-monitor",
        "priority": get_document_priority(document),
        "metadata": {
            "detected_at": datetime.utcnow().isoformat(),
            "monitor_version": "1.0",
            "project_id": PROJECT_ID
        }
    }
    
    return message_data


def get_document_priority(document: Dict[str, Any]) -> str:
    """
    Determine processing priority based on document characteristics.
    
    Args:
        document: Document information
        
    Returns:
        Priority level (high, medium, low)
    """
    
    category = document.get("category", "").lower()
    size_bytes = document.get("size_bytes", 0)
    
    # Priority logic - can be customized based on business needs
    if category in ["invoice", "contract"]:
        return "high"
    elif category in ["receipt", "form"]:
        return "medium" 
    elif size_bytes > 1000000:  # Files larger than 1MB
        return "low"
    else:
        return "medium"


def publish_message(message_data: Dict[str, Any]) -> None:
    """
    Publish message to Pub/Sub topic.
    
    Args:
        message_data: Message data to publish
        
    Raises:
        Exception: If message publishing fails
    """
    
    try:
        # Convert message to JSON bytes
        message_json = json.dumps(message_data, indent=None, separators=(',', ':'))
        message_bytes = message_json.encode('utf-8')
        
        # Add message attributes for routing and filtering
        attributes = {
            "document_category": message_data.get("category", "unknown"),
            "priority": message_data.get("priority", "medium"),
            "mime_type": message_data.get("mime_type", "application/octet-stream"),
            "source": "filestore-monitor"
        }
        
        # Publish message
        future = publisher.publish(
            topic_path, 
            message_bytes,
            **attributes
        )
        
        # Wait for publish confirmation
        message_id = future.result(timeout=30)
        
        logger.info(f"Published message with ID: {message_id} for document: {message_data['filename']}")
        
    except Exception as e:
        logger.error(f"Failed to publish message for document {message_data.get('filename', 'unknown')}: {str(e)}")
        raise


def validate_environment() -> bool:
    """
    Validate that all required environment variables are set.
    
    Returns:
        True if environment is valid, False otherwise
    """
    
    required_vars = {
        "PROJECT_ID": PROJECT_ID,
        "PUBSUB_TOPIC": PUBSUB_TOPIC,
        "FILESTORE_IP": FILESTORE_IP,
        "FILESTORE_SHARE": FILESTORE_SHARE
    }
    
    missing_vars = []
    for var_name, var_value in required_vars.items():
        if not var_value or var_value.startswith("$"):
            missing_vars.append(var_name)
    
    if missing_vars:
        logger.error(f"Missing required environment variables: {', '.join(missing_vars)}")
        return False
    
    return True


# Initialize and validate environment on module load
if not validate_environment():
    logger.error("Environment validation failed. Function may not work correctly.")