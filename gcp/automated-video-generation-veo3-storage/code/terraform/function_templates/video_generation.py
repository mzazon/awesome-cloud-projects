import json
import os
import logging
import time
import uuid
from google.cloud import storage
from google import genai
from google.genai import types
import functions_framework

# Initialize Google Gen AI client for Vertex AI
PROJECT_ID = "${project_id}"
REGION = "${region}"

@functions_framework.http
def generate_video(request):
    """Cloud Function to generate videos using Veo 3"""
    try:
        # Initialize client with Vertex AI
        client = genai.Client(vertexai=True, project=PROJECT_ID, location=REGION)
        
        # Parse request data
        request_json = request.get_json(silent=True)
        if not request_json:
            return {'error': 'No JSON data provided'}, 400
        
        prompt = request_json.get('prompt')
        output_bucket = request_json.get('output_bucket')
        resolution = request_json.get('resolution', '1080p')
        
        if not prompt or not output_bucket:
            return {'error': 'Missing required parameters'}, 400
        
        # Generate unique filename and GCS path
        video_id = str(uuid.uuid4())
        filename = f"generated_video_{video_id}.mp4"
        output_gcs_uri = f"gs://{output_bucket}/videos/{filename}"
        
        logging.info(f"Generating video for prompt: {prompt[:100]}...")
        
        # Generate video using Veo 3
        operation = client.models.generate_videos(
            model="veo-3.0-generate-preview",
            prompt=prompt,
            config=types.GenerateVideosConfig(
                aspect_ratio="16:9",
                output_gcs_uri=output_gcs_uri,
                number_of_videos=1,
                duration_seconds=8,
                person_generation="allow_adult",
            ),
        )
        
        # Poll for completion
        max_wait_time = 300  # 5 minutes
        start_time = time.time()
        
        while not operation.done and (time.time() - start_time) < max_wait_time:
            time.sleep(15)
            operation = client.operations.get(operation)
        
        if not operation.done:
            return {'error': 'Video generation timed out'}, 500
        
        if operation.response and operation.result.generated_videos:
            video_uri = operation.result.generated_videos[0].video.uri
            
            # Save metadata
            video_metadata = {
                "video_id": video_id,
                "prompt": prompt,
                "resolution": resolution,
                "video_uri": video_uri,
                "generated_at": time.time(),
                "status": "completed",
                "duration_seconds": 8
            }
            
            storage_client = storage.Client()
            bucket = storage_client.bucket(output_bucket)
            metadata_blob = bucket.blob(f"metadata/{video_id}.json")
            metadata_blob.upload_from_string(
                json.dumps(video_metadata, indent=2),
                content_type='application/json'
            )
            
            logging.info(f"Video generation completed: {filename}")
            
            return {
                'status': 'success',
                'video_id': video_id,
                'filename': filename,
                'video_uri': video_uri,
                'metadata': video_metadata
            }
        else:
            return {'error': 'Video generation failed'}, 500
        
    except Exception as e:
        logging.error(f"Error generating video: {str(e)}")
        return {'error': str(e)}, 500

@functions_framework.http
def process_brief(request):
    """Process creative brief and trigger video generation"""
    try:
        request_json = request.get_json(silent=True)
        brief_file = request_json.get('brief_file')
        input_bucket = request_json.get('input_bucket')
        output_bucket = request_json.get('output_bucket')
        
        # Download and parse creative brief
        storage_client = storage.Client()
        bucket = storage_client.bucket(input_bucket)
        blob = bucket.blob(brief_file)
        brief_content = json.loads(blob.download_as_text())
        
        # Extract video parameters from brief
        prompt = brief_content.get('video_prompt')
        resolution = brief_content.get('resolution', '1080p')
        
        # Create mock request for generate_video function
        video_request = {
            'prompt': prompt,
            'output_bucket': output_bucket,
            'resolution': resolution
        }
        
        # Create mock Flask request object
        class MockRequest:
            def __init__(self, json_data):
                self._json = json_data
            
            def get_json(self, silent=True):
                return self._json
        
        mock_request = MockRequest(video_request)
        result = generate_video(mock_request)
        
        return {
            'status': 'success',
            'brief_processed': brief_file,
            'video_result': result
        }
        
    except Exception as e:
        logging.error(f"Error processing brief: {str(e)}")
        return {'error': str(e)}, 500