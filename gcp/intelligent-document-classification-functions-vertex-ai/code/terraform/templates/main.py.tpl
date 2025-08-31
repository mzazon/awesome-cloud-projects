import os
import json
from google.cloud import storage
import vertexai
from vertexai.generative_models import GenerativeModel
from google.cloud import logging
import functions_framework

# Initialize clients
storage_client = storage.Client()
logging_client = logging.Client()
logger = logging_client.logger("document-classifier")

# Initialize Vertex AI
project_id = "${project_id}"
vertex_location = "${vertex_location}"
vertexai.init(project=project_id, location=vertex_location)

# Configuration from Terraform variables
CLASSIFIED_BUCKET = "${classified_bucket}"
INBOX_BUCKET = "${inbox_bucket}"
DOCUMENT_CATEGORIES = ${categories}

@functions_framework.cloud_event
def classify_document(cloud_event):
    """Cloud Function triggered by Cloud Storage uploads."""
    
    try:
        # Extract file information from event
        bucket_name = cloud_event.data["bucket"]
        file_name = cloud_event.data["name"]
        
        logger.log_text(f"Processing document: {file_name} from bucket: {bucket_name}")
        
        # Skip if already processed or is a .keep file
        if file_name.endswith('.keep') or 'classified/' in file_name:
            logger.log_text(f"Skipping {file_name} - already processed or system file")
            return
        
        # Download and read document content
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_name)
        
        # Check if file exists
        if not blob.exists():
            logger.log_text(f"File {file_name} does not exist in bucket {bucket_name}")
            return
        
        # Read text content (assuming text files for demo)
        try:
            document_content = blob.download_as_text(encoding='utf-8')
            logger.log_text(f"Successfully read content from {file_name}, length: {len(document_content)} characters")
        except UnicodeDecodeError:
            try:
                # Try with different encoding
                document_content = blob.download_as_text(encoding='latin-1')
                logger.log_text(f"Successfully read content from {file_name} with latin-1 encoding")
            except Exception as e:
                logger.log_text(f"Error reading file {file_name}: {str(e)}")
                # Move to 'other' category if can't read
                move_to_classified_folder(file_name, 'other')
                return
        except Exception as e:
            logger.log_text(f"Error reading file {file_name}: {str(e)}")
            return
        
        # Classify document using Vertex AI Gemini
        classification = classify_with_gemini(document_content, file_name)
        logger.log_text(f"Classification result for {file_name}: {classification}")
        
        # Move document to appropriate folder
        move_to_classified_folder(file_name, classification)
        
        logger.log_text(f"Successfully classified {file_name} as {classification}")
        
        # Publish event to Pub/Sub for downstream processing (optional)
        publish_classification_event(file_name, classification)
        
    except Exception as e:
        error_msg = f"Error processing document {file_name if 'file_name' in locals() else 'unknown'}: {str(e)}"
        logger.log_text(error_msg)
        # Don't re-raise to avoid infinite retries
        return

def classify_with_gemini(content, filename):
    """Use Vertex AI Gemini to classify document content."""
    
    try:
        model = GenerativeModel("gemini-1.5-flash")
        
        # Prepare category list for prompt
        category_list = ", ".join(DOCUMENT_CATEGORIES)
        
        prompt = f"""
        Analyze the following document content and classify it into one of these categories:
        {category_list}
        
        Category Definitions:
        - contracts: Legal agreements, terms of service, contracts, service agreements, NDAs
        - invoices: Bills, invoices, payment requests, receipts, purchase orders
        - reports: Business reports, analytics, summaries, presentations, quarterly reports
        - other: Any other document type that doesn't fit the above categories
        
        Document filename: {filename}
        Document content (first 2000 characters): {content[:2000]}
        
        Instructions:
        1. Analyze the content carefully
        2. Look for keywords and patterns that indicate document type
        3. Consider the filename as additional context
        4. Respond with only the category name in lowercase
        5. If uncertain, choose 'other'
        
        Response format: Return only one word - the category name.
        """
        
        logger.log_text(f"Sending classification request to Gemini for {filename}")
        response = model.generate_content(prompt)
        classification = response.text.strip().lower()
        
        # Validate classification against available categories
        if classification not in DOCUMENT_CATEGORIES:
            logger.log_text(f"Invalid classification '{classification}' returned by Gemini, defaulting to 'other'")
            classification = 'other'
        
        logger.log_text(f"Gemini classified {filename} as: {classification}")
        return classification
        
    except Exception as e:
        error_msg = f"Error with Gemini classification for {filename}: {str(e)}"
        logger.log_text(error_msg)
        return 'other'

def move_to_classified_folder(filename, classification):
    """Move document to appropriate classified folder."""
    
    try:
        # Source and destination
        source_bucket = storage_client.bucket(INBOX_BUCKET)
        dest_bucket = storage_client.bucket(CLASSIFIED_BUCKET)
        
        source_blob = source_bucket.blob(filename)
        dest_blob_name = f"{classification}/{filename}"
        
        # Check if source file exists
        if not source_blob.exists():
            logger.log_text(f"Source file {filename} no longer exists in {INBOX_BUCKET}")
            return
        
        # Copy to classified bucket
        dest_bucket.copy_blob(source_blob, dest_bucket, dest_blob_name)
        logger.log_text(f"Copied {filename} to {CLASSIFIED_BUCKET}/{dest_blob_name}")
        
        # Delete from inbox after successful copy
        source_blob.delete()
        logger.log_text(f"Deleted {filename} from inbox bucket {INBOX_BUCKET}")
        
        logger.log_text(f"Successfully moved {filename} to {classification} folder")
        
    except Exception as e:
        error_msg = f"Error moving {filename} to {classification} folder: {str(e)}"
        logger.log_text(error_msg)
        raise

def publish_classification_event(filename, classification):
    """Publish classification event to Pub/Sub for downstream processing."""
    
    try:
        from google.cloud import pubsub_v1
        
        publisher = pubsub_v1.PublisherClient()
        topic_path = publisher.topic_path(project_id, f"{os.environ.get('RESOURCE_PREFIX', 'doc-classifier')}-events")
        
        # Prepare event data
        event_data = {
            "filename": filename,
            "classification": classification,
            "timestamp": str(int(time.time())),
            "bucket": CLASSIFIED_BUCKET,
            "path": f"{classification}/{filename}"
        }
        
        # Publish message
        data = json.dumps(event_data).encode('utf-8')
        future = publisher.publish(topic_path, data)
        
        logger.log_text(f"Published classification event for {filename}: {event_data}")
        
    except Exception as e:
        # Don't fail the main process if event publishing fails
        logger.log_text(f"Failed to publish classification event for {filename}: {str(e)}")

# Health check endpoint for monitoring
@functions_framework.http
def health_check(request):
    """Health check endpoint for monitoring."""
    
    try:
        # Basic health checks
        health_status = {
            "status": "healthy",
            "timestamp": str(int(time.time())),
            "vertex_ai_location": vertex_location,
            "classified_bucket": CLASSIFIED_BUCKET,
            "inbox_bucket": INBOX_BUCKET,
            "categories": DOCUMENT_CATEGORIES
        }
        
        return json.dumps(health_status), 200, {'Content-Type': 'application/json'}
        
    except Exception as e:
        error_response = {
            "status": "unhealthy",
            "error": str(e),
            "timestamp": str(int(time.time()))
        }
        return json.dumps(error_response), 500, {'Content-Type': 'application/json'}