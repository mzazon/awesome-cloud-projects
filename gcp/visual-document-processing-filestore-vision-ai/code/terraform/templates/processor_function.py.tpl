#!/usr/bin/env python3
"""
Cloud Function for processing documents with Vision AI and publishing results.
This function demonstrates document analysis, text extraction, and result publishing.
"""

import os
import json
import base64
import logging
import io
from datetime import datetime
from typing import Dict, Any, List, Optional

from google.cloud import vision
from google.cloud import pubsub_v1
from google.cloud import storage
import functions_framework
from PIL import Image, ImageDraw, ImageFont

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize clients
vision_client = vision.ImageAnnotatorClient()
publisher = pubsub_v1.PublisherClient()
storage_client = storage.Client()

# Configuration from environment variables
PROJECT_ID = "${project_id}"
RESULTS_TOPIC = "${results_topic}"
RESULTS_BUCKET = "${results_bucket}"

# Construct topic path
results_topic_path = publisher.topic_path(PROJECT_ID, RESULTS_TOPIC)


@functions_framework.cloud_event
def process_document(cloud_event) -> None:
    """
    Process documents with Vision AI and publish results.
    
    This function receives document processing messages from Pub/Sub,
    analyzes documents using Cloud Vision AI, extracts text and metadata,
    and publishes results for downstream processing.
    
    Args:
        cloud_event: Cloud Event containing Pub/Sub message
    """
    
    try:
        logger.info(f"Vision processor function triggered at {datetime.utcnow().isoformat()}")
        
        # Decode Pub/Sub message
        message_data = decode_pubsub_message(cloud_event)
        
        if not message_data:
            logger.error("Failed to decode Pub/Sub message")
            return
        
        # Extract document information
        processing_id = message_data.get('processing_id', 'unknown')
        filename = message_data.get('filename', 'unknown')
        filepath = message_data.get('filepath', '')
        category = message_data.get('category', 'unknown')
        
        logger.info(f"Processing document: {filename} (ID: {processing_id})")
        
        # Process document with Vision AI
        results = analyze_document_with_vision_ai(message_data)
        
        # Save results to Cloud Storage
        save_results_to_storage(results)
        
        # Publish results to Pub/Sub
        publish_results(results)
        
        logger.info(f"Successfully processed document: {filename}")
        
    except Exception as e:
        logger.error(f"Error in document processing function: {str(e)}")
        
        # Publish error results
        try:
            error_results = create_error_results(message_data, str(e))
            publish_results(error_results)
        except Exception as error_publish_error:
            logger.error(f"Failed to publish error results: {str(error_publish_error)}")
        
        raise


def decode_pubsub_message(cloud_event) -> Optional[Dict[str, Any]]:
    """
    Decode Pub/Sub message from cloud event.
    
    Args:
        cloud_event: Cloud Event containing the message
        
    Returns:
        Decoded message data or None if failed
    """
    
    try:
        # Extract and decode message data
        pubsub_message = base64.b64decode(cloud_event.data["message"]["data"])
        message_data = json.loads(pubsub_message.decode('utf-8'))
        
        logger.info(f"Decoded message for file: {message_data.get('filename', 'unknown')}")
        return message_data
        
    except Exception as e:
        logger.error(f"Failed to decode Pub/Sub message: {str(e)}")
        return None


def analyze_document_with_vision_ai(message_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Analyze document using Cloud Vision AI.
    
    Args:
        message_data: Document processing message
        
    Returns:
        Processing results with extracted information
    """
    
    try:
        processing_id = message_data.get('processing_id', 'unknown')
        filename = message_data.get('filename', 'unknown')
        category = message_data.get('category', 'unknown')
        
        logger.info(f"Starting Vision AI analysis for: {filename}")
        
        # Create or load document image
        # In production, this would read from the actual Filestore path
        image_content = create_sample_document_image(filename, category)
        
        # Create Vision AI image object
        image = vision.Image(content=image_content)
        
        # Configure Vision AI features to extract
        features = [
            vision.Feature(type_=vision.Feature.Type.TEXT_DETECTION),
            vision.Feature(type_=vision.Feature.Type.DOCUMENT_TEXT_DETECTION),
            vision.Feature(type_=vision.Feature.Type.LABEL_DETECTION),
            vision.Feature(type_=vision.Feature.Type.OBJECT_LOCALIZATION),
            vision.Feature(type_=vision.Feature.Type.SAFE_SEARCH_DETECTION)
        ]
        
        # Perform comprehensive document analysis
        response = vision_client.annotate_image({
            'image': image,
            'features': features
        })
        
        # Extract and process results
        results = extract_vision_results(response, message_data)
        
        logger.info(f"Vision AI analysis completed for: {filename}")
        return results
        
    except Exception as e:
        logger.error(f"Vision AI analysis failed for {filename}: {str(e)}")
        raise


def extract_vision_results(response, message_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Extract and structure results from Vision AI response.
    
    Args:
        response: Vision AI response object
        message_data: Original processing message
        
    Returns:
        Structured processing results
    """
    
    # Extract text using OCR
    extracted_text = ""
    if response.text_annotations:
        extracted_text = response.text_annotations[0].description
    
    # Extract document text with structure
    document_text = ""
    word_count = 0
    if response.full_text_annotation:
        document_text = response.full_text_annotation.text
        word_count = len(document_text.split()) if document_text else 0
    
    # Extract labels and confidence scores
    labels = []
    confidence_scores = []
    for label in response.label_annotations[:10]:  # Top 10 labels
        labels.append(label.description)
        confidence_scores.append(float(label.score))
    
    # Extract objects
    objects = []
    for obj in response.localized_object_annotations[:5]:  # Top 5 objects
        objects.append({
            "name": obj.name,
            "confidence": float(obj.score),
            "bounding_box": {
                "vertices": [
                    {"x": vertex.x, "y": vertex.y} 
                    for vertex in obj.bounding_poly.normalized_vertices
                ]
            }
        })
    
    # Safe search detection
    safe_search = {}
    if response.safe_search_annotation:
        safe_search = {
            "adult": response.safe_search_annotation.adult.name,
            "spoof": response.safe_search_annotation.spoof.name,
            "medical": response.safe_search_annotation.medical.name,
            "violence": response.safe_search_annotation.violence.name,
            "racy": response.safe_search_annotation.racy.name
        }
    
    # Classify document type based on extracted content
    document_type = classify_document_advanced(extracted_text, labels, message_data.get('category', 'unknown'))
    
    # Create comprehensive results
    results = {
        "processing_id": message_data.get('processing_id', 'unknown'),
        "filename": message_data.get('filename', 'unknown'),
        "original_category": message_data.get('category', 'unknown'),
        "detected_document_type": document_type,
        "processing_timestamp": datetime.utcnow().isoformat(),
        "status": "completed",
        
        # Text extraction results
        "text_extraction": {
            "extracted_text": extracted_text[:2000] if extracted_text else "",  # Limit for demo
            "document_text": document_text[:2000] if document_text else "",     # Limit for demo
            "word_count": word_count,
            "character_count": len(extracted_text) if extracted_text else 0,
            "has_text": bool(extracted_text)
        },
        
        # Vision analysis results
        "vision_analysis": {
            "labels": labels,
            "confidence_scores": confidence_scores,
            "detected_objects": objects,
            "safe_search": safe_search
        },
        
        # Document characteristics
        "document_characteristics": {
            "complexity_score": calculate_complexity_score(extracted_text, labels),
            "readability_score": calculate_readability_score(extracted_text),
            "language_detected": detect_language(extracted_text),
            "has_tables": "table" in ' '.join(labels).lower(),
            "has_forms": "form" in ' '.join(labels).lower() or "receipt" in ' '.join(labels).lower()
        },
        
        # Processing metadata
        "processing_metadata": {
            "vision_api_version": "v1",
            "processor_version": "1.0",
            "processing_duration_ms": 1500,  # Simulated
            "project_id": PROJECT_ID,
            "bucket": RESULTS_BUCKET
        },
        
        # Quality metrics
        "quality_metrics": {
            "text_confidence": calculate_text_confidence(response),
            "image_quality": assess_image_quality(labels),
            "processing_success": True
        }
    }
    
    return results


def create_sample_document_image(filename: str, category: str) -> bytes:
    """
    Create a sample document image for demonstration.
    In production, this would read from the actual Filestore path.
    
    Args:
        filename: Name of the document file
        category: Document category
        
    Returns:
        Image content as bytes
    """
    
    try:
        # Create image based on document category
        img = Image.new('RGB', (800, 600), color='white')
        draw = ImageDraw.Draw(img)
        
        # Create category-specific content
        if category == "invoice":
            sample_text = [
                "INVOICE #INV-2025-001",
                "",
                "Date: 2025-01-15",
                "Bill To: Acme Corporation",
                "123 Business Street",
                "Business City, BC 12345",
                "",
                "Description                  Qty    Rate      Amount",
                "------------------------------------------------",
                "Professional Services        10    $150.00   $1,500.00",
                "Cloud Infrastructure         1     $500.00   $500.00",
                "Support Services             5     $100.00   $500.00",
                "",
                "                           Subtotal: $2,500.00",
                "                               Tax: $250.00",
                "                             Total: $2,750.00",
                "",
                "Payment Terms: Net 30 days",
                "Thank you for your business!"
            ]
        elif category == "receipt":
            sample_text = [
                "RECEIPT",
                "",
                "TechMart Electronics",
                "456 Shopping Blvd",
                "Mall City, MC 67890",
                "Phone: (555) 123-4567",
                "",
                "Date: 01/15/2025",
                "Time: 14:30:25",
                "Transaction #: TXN789012",
                "",
                "Item                        Price",
                "--------------------------------",
                "Wireless Keyboard           $45.99",
                "USB Mouse                   $19.99",
                "Monitor Stand               $29.99",
                "",
                "Subtotal:                   $95.97",
                "Sales Tax (8.5%):           $8.16",
                "Total:                     $104.13",
                "",
                "Payment Method: Credit Card",
                "Card: **** **** **** 1234",
                "",
                "Thank you for shopping!"
            ]
        elif category == "contract":
            sample_text = [
                "SERVICE AGREEMENT",
                "",
                "This Agreement is entered into on January 15, 2025",
                "between TechServices Inc. (\"Service Provider\")",
                "and Acme Corporation (\"Client\").",
                "",
                "1. SCOPE OF SERVICES",
                "Service Provider agrees to provide cloud",
                "infrastructure management and support services",
                "as detailed in Exhibit A.",
                "",
                "2. TERM",
                "This Agreement shall commence on February 1, 2025",
                "and continue for a period of twelve (12) months.",
                "",
                "3. COMPENSATION",
                "Client agrees to pay Service Provider a monthly",
                "fee of $5,000.00 for the services provided.",
                "",
                "4. CONFIDENTIALITY",
                "Both parties agree to maintain confidentiality",
                "of proprietary information shared during",
                "the performance of this Agreement.",
                "",
                "By signing below, parties agree to the terms."
            ]
        else:
            sample_text = [
                f"DOCUMENT: {filename}",
                "",
                f"Category: {category.title()}",
                f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
                "",
                "This is a sample document for demonstration",
                "purposes. In a production environment, this",
                "would be the actual document content loaded",
                "from the Filestore instance.",
                "",
                "The Vision AI service can extract text,",
                "detect objects, classify documents, and",
                "perform various types of analysis on",
                "uploaded documents.",
                "",
                "Sample content for processing:",
                "- Text extraction and OCR",
                "- Object and label detection",
                "- Document classification",
                "- Quality assessment",
                "- Language detection"
            ]
        
        # Draw text on image
        y_position = 30
        line_height = 24
        
        for line in sample_text:
            if line.strip():  # Non-empty lines
                draw.text((40, y_position), line, fill='black')
            y_position += line_height
            
            # Prevent text from going off the image
            if y_position > 550:
                break
        
        # Convert to bytes
        img_byte_arr = io.BytesIO()
        img.save(img_byte_arr, format='PNG')
        return img_byte_arr.getvalue()
        
    except Exception as e:
        logger.error(f"Failed to create sample image: {str(e)}")
        # Return a minimal image if creation fails
        img = Image.new('RGB', (400, 300), color='white')
        draw = ImageDraw.Draw(img)
        draw.text((50, 150), f"Sample Document: {filename}", fill='black')
        img_byte_arr = io.BytesIO()
        img.save(img_byte_arr, format='PNG')
        return img_byte_arr.getvalue()


def classify_document_advanced(text: str, labels: List[str], original_category: str) -> str:
    """
    Advanced document classification based on text content and labels.
    
    Args:
        text: Extracted text content
        labels: Detected labels from Vision AI
        original_category: Original category from file monitor
        
    Returns:
        Classified document type
    """
    
    if not text:
        return original_category
    
    text_lower = text.lower()
    labels_text = ' '.join(labels).lower()
    
    # Invoice detection
    if any(keyword in text_lower for keyword in ['invoice', 'bill to', 'amount due', 'payment terms', 'tax', 'subtotal']):
        return "invoice"
    
    # Receipt detection
    if any(keyword in text_lower for keyword in ['receipt', 'transaction', 'total:', 'payment method', 'thank you for']):
        return "receipt"
    
    # Contract detection
    if any(keyword in text_lower for keyword in ['agreement', 'contract', 'terms and conditions', 'party', 'signature']):
        return "contract"
    
    # Form detection
    if any(keyword in text_lower for keyword in ['application', 'form', 'please complete', 'signature required']):
        return "form"
    
    # Business letter detection
    if any(keyword in text_lower for keyword in ['dear', 'sincerely', 'regards', 'letter']):
        return "letter"
    
    # Report detection
    if any(keyword in text_lower for keyword in ['report', 'analysis', 'summary', 'findings', 'conclusion']):
        return "report"
    
    # Label-based classification fallback
    if 'text' in labels_text and 'document' in labels_text:
        return "document"
    
    return original_category


def calculate_complexity_score(text: str, labels: List[str]) -> float:
    """Calculate document complexity score (0-1)."""
    if not text:
        return 0.0
    
    score = 0.0
    
    # Text complexity factors
    word_count = len(text.split())
    if word_count > 100:
        score += 0.3
    if word_count > 500:
        score += 0.2
    
    # Structure complexity
    if 'table' in ' '.join(labels).lower():
        score += 0.2
    if any(char in text for char in ['$', '%', '#']):
        score += 0.1
    
    # Content complexity
    sentences = text.count('.') + text.count('!') + text.count('?')
    if sentences > 10:
        score += 0.2
    
    return min(score, 1.0)


def calculate_readability_score(text: str) -> float:
    """Calculate basic readability score (0-1)."""
    if not text:
        return 0.0
    
    words = text.split()
    if not words:
        return 0.0
    
    # Simple readability based on average word length
    avg_word_length = sum(len(word) for word in words) / len(words)
    
    # Normalize score (lower average word length = higher readability)
    readability = max(0, 1 - (avg_word_length - 4) / 6)
    return min(readability, 1.0)


def detect_language(text: str) -> str:
    """Basic language detection."""
    if not text:
        return "unknown"
    
    # Simple heuristic - in production, use proper language detection
    common_english_words = ['the', 'and', 'of', 'to', 'a', 'in', 'that', 'have', 'for', 'not', 'with', 'he', 'as', 'you', 'do', 'at']
    
    text_lower = text.lower()
    english_word_count = sum(1 for word in common_english_words if word in text_lower)
    
    if english_word_count >= 3:
        return "en"
    else:
        return "unknown"


def calculate_text_confidence(response) -> float:
    """Calculate overall text confidence from Vision AI response."""
    if not response.text_annotations:
        return 0.0
    
    # Use the confidence from text detection
    if hasattr(response.text_annotations[0], 'confidence'):
        return float(response.text_annotations[0].confidence)
    else:
        # Fallback: estimate based on number of detected elements
        return min(0.95, 0.5 + (len(response.text_annotations) * 0.05))


def assess_image_quality(labels: List[str]) -> str:
    """Assess image quality based on detected labels."""
    labels_text = ' '.join(labels).lower()
    
    if 'text' in labels_text and 'document' in labels_text:
        return "high"
    elif 'text' in labels_text:
        return "medium"
    else:
        return "low"


def save_results_to_storage(results: Dict[str, Any]) -> None:
    """
    Save processing results to Cloud Storage.
    
    Args:
        results: Processing results to save
    """
    
    try:
        processing_id = results.get('processing_id', 'unknown')
        filename = results.get('filename', 'unknown')
        
        # Create bucket reference
        bucket = storage_client.bucket(RESULTS_BUCKET)
        
        # Create blob path
        blob_path = f"processed/{processing_id}/{filename}.json"
        blob = bucket.blob(blob_path)
        
        # Upload results as JSON
        results_json = json.dumps(results, indent=2, ensure_ascii=False)
        blob.upload_from_string(
            results_json,
            content_type='application/json'
        )
        
        logger.info(f"Saved results to: gs://{RESULTS_BUCKET}/{blob_path}")
        
    except Exception as e:
        logger.error(f"Failed to save results to storage: {str(e)}")
        raise


def publish_results(results: Dict[str, Any]) -> None:
    """
    Publish processing results to Pub/Sub.
    
    Args:
        results: Processing results to publish
    """
    
    try:
        # Convert results to JSON
        results_json = json.dumps(results, ensure_ascii=False, separators=(',', ':'))
        results_bytes = results_json.encode('utf-8')
        
        # Create message attributes
        attributes = {
            "document_type": results.get("detected_document_type", "unknown"),
            "status": results.get("status", "unknown"),
            "processing_id": results.get("processing_id", "unknown"),
            "has_text": str(results.get("text_extraction", {}).get("has_text", False)).lower(),
            "source": "vision-processor"
        }
        
        # Publish message
        future = publisher.publish(
            results_topic_path,
            results_bytes,
            **attributes
        )
        
        # Wait for confirmation
        message_id = future.result(timeout=30)
        
        logger.info(f"Published results with message ID: {message_id}")
        
    except Exception as e:
        logger.error(f"Failed to publish results: {str(e)}")
        raise


def create_error_results(message_data: Dict[str, Any], error_message: str) -> Dict[str, Any]:
    """
    Create error results for failed processing.
    
    Args:
        message_data: Original processing message
        error_message: Error description
        
    Returns:
        Error results dictionary
    """
    
    return {
        "processing_id": message_data.get('processing_id', 'unknown'),
        "filename": message_data.get('filename', 'unknown'),
        "status": "failed",
        "error_message": error_message,
        "processing_timestamp": datetime.utcnow().isoformat(),
        "processing_metadata": {
            "processor_version": "1.0",
            "project_id": PROJECT_ID,
            "error_type": "processing_error"
        }
    }