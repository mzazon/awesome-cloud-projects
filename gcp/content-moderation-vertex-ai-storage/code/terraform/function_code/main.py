import json
import base64
import time
from google.cloud import storage
from google.cloud import aiplatform
from google.cloud import pubsub_v1
import vertexai
from vertexai.generative_models import GenerativeModel, Part, SafetySetting
import functions_framework
import os
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize clients
PROJECT_ID = "${project_id}"
REGION = "${region}"
QUARANTINE_BUCKET = "${quarantine_bucket}"
APPROVED_BUCKET = "${approved_bucket}"

vertexai.init(project=PROJECT_ID, location=REGION)
storage_client = storage.Client()
publisher = pubsub_v1.PublisherClient()

# Initialize Gemini model for multimodal analysis
model = GenerativeModel('gemini-1.5-pro')

@functions_framework.cloud_event
def moderate_content(cloud_event):
    """Cloud Function triggered by Cloud Storage uploads."""
    try:
        # Parse the Cloud Storage event
        data = cloud_event.data
        bucket_name = data['bucket']
        file_name = data['name']
        
        logger.info(f"Processing file: {file_name} from bucket: {bucket_name}")
        
        # Download the file
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_name)
        
        # Check if it's an image or text file
        content_type = blob.content_type or ''
        file_extension = file_name.lower().split('.')[-1] if '.' in file_name else ''
        
        moderation_result = None
        
        if content_type.startswith('image/') or file_extension in ['jpg', 'jpeg', 'png', 'gif', 'webp']:
            moderation_result = moderate_image(blob)
        elif content_type.startswith('text/') or file_extension in ['txt', 'md', 'json']:
            moderation_result = moderate_text(blob)
        else:
            logger.warning(f"Unsupported file type: {content_type}")
            return
        
        # Process moderation result
        if moderation_result:
            process_moderation_result(blob, file_name, moderation_result)
            
    except Exception as e:
        logger.error(f"Error processing file: {str(e)}")
        raise

def moderate_image(blob):
    """Analyze image content using Vertex AI Vision."""
    try:
        # Download image data
        image_data = blob.download_as_bytes()
        
        # Create image part for Gemini
        image_part = Part.from_data(image_data, mime_type=blob.content_type)
        
        # Moderation prompt
        prompt = """
        Analyze this image for content moderation. Check for:
        1. Adult/sexual content
        2. Violence or graphic content
        3. Hate symbols or offensive imagery
        4. Illegal substances
        5. Weapons or dangerous items
        
        Respond with a JSON object containing:
        - "safe": boolean (true if content is safe)
        - "categories": array of detected harmful categories
        - "confidence": float (0-1)
        - "reasoning": brief explanation
        """
        
        # Configure safety settings
        safety_settings = [
            SafetySetting(
                category=SafetySetting.HarmCategory.HARM_CATEGORY_HATE_SPEECH,
                threshold=SafetySetting.HarmBlockThreshold.BLOCK_LOW_AND_ABOVE
            ),
            SafetySetting(
                category=SafetySetting.HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT,
                threshold=SafetySetting.HarmBlockThreshold.BLOCK_LOW_AND_ABOVE
            ),
            SafetySetting(
                category=SafetySetting.HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT,
                threshold=SafetySetting.HarmBlockThreshold.BLOCK_LOW_AND_ABOVE
            ),
            SafetySetting(
                category=SafetySetting.HarmCategory.HARM_CATEGORY_HARASSMENT,
                threshold=SafetySetting.HarmBlockThreshold.BLOCK_LOW_AND_ABOVE
            )
        ]
        
        # Generate response
        response = model.generate_content(
            [prompt, image_part],
            safety_settings=safety_settings,
            generation_config={
                'max_output_tokens': 1024,
                'temperature': 0.1
            }
        )
        
        # Parse JSON response
        result_text = response.text.strip()
        if result_text.startswith('```json'):
            result_text = result_text[7:-3]
        
        return json.loads(result_text)
        
    except Exception as e:
        logger.error(f"Error moderating image: {str(e)}")
        return {"safe": False, "categories": ["processing_error"], "confidence": 0.0, "reasoning": str(e)}

def moderate_text(blob):
    """Analyze text content using Vertex AI Language."""
    try:
        # Download and decode text
        text_content = blob.download_as_text()
        
        # Moderation prompt
        prompt = f"""
        Analyze this text for content moderation. Check for:
        1. Hate speech or harassment
        2. Threats or violent language
        3. Adult/sexual content
        4. Spam or misleading information
        5. Personal information exposure
        
        Text to analyze:
        "{text_content}"
        
        Respond with a JSON object containing:
        - "safe": boolean (true if content is safe)
        - "categories": array of detected harmful categories
        - "confidence": float (0-1)
        - "reasoning": brief explanation
        """
        
        # Generate response
        response = model.generate_content(
            prompt,
            generation_config={
                'max_output_tokens': 1024,
                'temperature': 0.1
            }
        )
        
        # Parse JSON response
        result_text = response.text.strip()
        if result_text.startswith('```json'):
            result_text = result_text[7:-3]
        
        return json.loads(result_text)
        
    except Exception as e:
        logger.error(f"Error moderating text: {str(e)}")
        return {"safe": False, "categories": ["processing_error"], "confidence": 0.0, "reasoning": str(e)}

def process_moderation_result(blob, file_name, result):
    """Process moderation result and move file accordingly."""
    try:
        source_bucket = blob.bucket
        
        if result.get('safe', False) and result.get('confidence', 0) > 0.7:
            # Move to approved bucket
            destination_bucket = storage_client.bucket(APPROVED_BUCKET)
            logger.info(f"Moving {file_name} to approved bucket")
        else:
            # Move to quarantine bucket
            destination_bucket = storage_client.bucket(QUARANTINE_BUCKET)
            logger.info(f"Moving {file_name} to quarantine bucket")
        
        # Copy file with metadata
        new_blob = source_bucket.copy_blob(blob, destination_bucket, file_name)
        
        # Add moderation metadata
        new_blob.metadata = {
            'moderation_result': json.dumps(result),
            'original_bucket': source_bucket.name,
            'processed_timestamp': str(int(time.time()))
        }
        new_blob.patch()
        
        # Delete original file
        blob.delete()
        
        logger.info(f"Successfully processed {file_name}")
        
    except Exception as e:
        logger.error(f"Error processing moderation result: {str(e)}")
        raise