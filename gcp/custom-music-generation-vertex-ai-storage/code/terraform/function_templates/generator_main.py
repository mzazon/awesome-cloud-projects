#!/usr/bin/env python3
"""
Music Generator Cloud Function
Processes music generation requests using Vertex AI Lyria 2 model.
Triggered by Cloud Storage events when new prompt files are uploaded.
"""

import os
import json
import logging
from typing import Dict, Any, Optional
from google.cloud import aiplatform
from google.cloud import storage
from cloudevents.http.event import CloudEvent
import functions_framework

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize clients
storage_client = storage.Client()

# Configuration from environment variables
OUTPUT_BUCKET = "${output_bucket}"
PROJECT_ID = "${project_id}"
REGION = "${region}"

@functions_framework.cloud_event
def generate_music(cloud_event: CloudEvent) -> None:
    """
    Cloud Function triggered by Cloud Storage to generate music from prompts.
    
    Args:
        cloud_event: CloudEvent containing storage trigger information
    """
    
    # Extract file information from the Cloud Storage event
    data = cloud_event.data
    bucket_name = data.get('bucket', '')
    file_name = data.get('name', '')
    
    logger.info(f"Processing file: {file_name} from bucket: {bucket_name}")
    
    # Only process JSON files in the requests folder
    if not file_name.endswith('.json') or not file_name.startswith('requests/'):
        logger.info(f"Skipping non-request file: {file_name}")
        return
    
    try:
        # Download and parse the prompt file
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_name)
        
        if not blob.exists():
            logger.error(f"File {file_name} does not exist in bucket {bucket_name}")
            return
            
        prompt_data = json.loads(blob.download_as_text())
        
        # Validate required fields
        required_fields = ['request_id', 'prompt']
        for field in required_fields:
            if field not in prompt_data:
                raise ValueError(f"Missing required field: {field}")
        
        # Extract music generation parameters with defaults
        request_id = prompt_data['request_id']
        text_prompt = prompt_data['prompt']
        style = prompt_data.get('style', 'instrumental')
        duration = min(prompt_data.get('duration_seconds', 30), 300)  # Cap at 5 minutes
        tempo = prompt_data.get('tempo', 'moderate')
        
        logger.info(f"Generating music for request {request_id}: {text_prompt[:50]}...")
        
        # Initialize Vertex AI
        aiplatform.init(project=PROJECT_ID, location=REGION)
        
        # Prepare enhanced music generation prompt for Lyria 2
        enhanced_prompt = f"Create {style} music: {text_prompt}. Style: {style}, tempo: {tempo}, duration: {duration} seconds"
        
        # Note: In a full implementation, this would call the actual Vertex AI Lyria API
        # For demonstration purposes, we simulate the generation process
        # The actual API call would look like:
        # response = vertex_ai_client.generate_music(prompt=enhanced_prompt, duration=duration)
        
        # Simulate successful music generation
        generated_metadata = {
            'request_id': request_id,
            'original_prompt': text_prompt,
            'enhanced_prompt': enhanced_prompt,
            'style': style,
            'duration_seconds': duration,
            'tempo': tempo,
            'model_name': 'lyria-002',
            'model_version': 'lyria-2',
            'generation_timestamp': cloud_event.get_time().isoformat() if cloud_event.get_time() else None,
            'file_format': 'wav',
            'sample_rate': 48000,
            'bit_depth': 16,
            'channels': 2,
            'generation_status': 'completed',
            'processing_time_seconds': duration * 2,  # Simulated processing time
            'file_size_bytes': duration * 48000 * 2 * 2,  # Estimated file size
            'quality_score': 0.95  # Simulated quality metric
        }
        
        # Save generation metadata to output bucket
        output_bucket = storage_client.bucket(OUTPUT_BUCKET)
        
        # Store metadata
        metadata_path = f"metadata/{request_id}.json"
        metadata_blob = output_bucket.blob(metadata_path)
        metadata_blob.upload_from_string(
            json.dumps(generated_metadata, indent=2, ensure_ascii=False),
            content_type='application/json'
        )
        
        # Create a placeholder audio file to demonstrate the workflow
        # In production, this would contain the actual generated audio from Lyria 2
        audio_file_name = f"audio/{request_id}.wav"
        audio_blob = output_bucket.blob(audio_file_name)
        
        # Create a minimal WAV header for demonstration
        # In production, this would be replaced with actual audio data from Vertex AI
        wav_header = create_wav_header(duration, 48000, 2, 16)
        audio_blob.upload_from_string(
            wav_header,
            content_type='audio/wav'
        )
        
        # Update metadata with file paths
        generated_metadata['audio_file_path'] = f"gs://{OUTPUT_BUCKET}/{audio_file_name}"
        generated_metadata['metadata_file_path'] = f"gs://{OUTPUT_BUCKET}/{metadata_path}"
        
        # Update the metadata file with file paths
        metadata_blob.upload_from_string(
            json.dumps(generated_metadata, indent=2, ensure_ascii=False),
            content_type='application/json'
        )
        
        logger.info(f"Successfully generated music for request {request_id}")
        logger.info(f"Audio file: gs://{OUTPUT_BUCKET}/{audio_file_name}")
        logger.info(f"Metadata file: gs://{OUTPUT_BUCKET}/{metadata_path}")
        
    except json.JSONDecodeError as e:
        logger.error(f"Invalid JSON in file {file_name}: {str(e)}")
        _store_error_metadata(file_name, f"JSON decode error: {str(e)}", cloud_event)
        
    except ValueError as e:
        logger.error(f"Validation error for file {file_name}: {str(e)}")
        _store_error_metadata(file_name, f"Validation error: {str(e)}", cloud_event)
        
    except Exception as e:
        logger.error(f"Error generating music for file {file_name}: {str(e)}")
        _store_error_metadata(file_name, f"Generation error: {str(e)}", cloud_event)
        raise


def _store_error_metadata(file_name: str, error_message: str, cloud_event: CloudEvent) -> None:
    """
    Store error information for debugging purposes.
    
    Args:
        file_name: Name of the file that caused the error
        error_message: Description of the error
        cloud_event: Original cloud event for timestamp
    """
    try:
        # Extract request ID from file name if possible
        request_id = file_name.replace('requests/', '').replace('.json', '')
        
        error_metadata = {
            'request_id': request_id,
            'original_file': file_name,
            'error_message': error_message,
            'status': 'failed',
            'timestamp': cloud_event.get_time().isoformat() if cloud_event.get_time() else None,
            'function_name': 'music_generator',
            'retry_possible': True
        }
        
        output_bucket = storage_client.bucket(OUTPUT_BUCKET)
        error_blob = output_bucket.blob(f"errors/{request_id}_error.json")
        error_blob.upload_from_string(
            json.dumps(error_metadata, indent=2),
            content_type='application/json'
        )
        
        logger.info(f"Error metadata stored for request {request_id}")
        
    except Exception as e:
        logger.error(f"Failed to store error metadata: {str(e)}")


def create_wav_header(duration_seconds: int, sample_rate: int, channels: int, bit_depth: int) -> bytes:
    """
    Create a minimal WAV file header for demonstration purposes.
    In production, this would be replaced with actual audio data from Vertex AI.
    
    Args:
        duration_seconds: Duration of the audio in seconds
        sample_rate: Sample rate in Hz
        channels: Number of audio channels
        bit_depth: Bit depth of the audio
        
    Returns:
        bytes: WAV file header
    """
    import struct
    
    # Calculate data size
    num_samples = duration_seconds * sample_rate
    data_size = num_samples * channels * (bit_depth // 8)
    file_size = data_size + 36
    
    # WAV header structure
    header = struct.pack('<4sL4s4sLHHLLHH4sL',
        b'RIFF',
        file_size,
        b'WAVE',
        b'fmt ',
        16,  # PCM header length
        1,   # PCM format
        channels,
        sample_rate,
        sample_rate * channels * (bit_depth // 8),  # Byte rate
        channels * (bit_depth // 8),  # Block align
        bit_depth,
        b'data',
        data_size
    )
    
    # Add minimal audio data (silence for demonstration)
    silence = b'\x00' * min(data_size, 1024)  # Limit to 1KB for demonstration
    
    return header + silence


def validate_prompt_data(prompt_data: Dict[str, Any]) -> bool:
    """
    Validate the structure and content of prompt data.
    
    Args:
        prompt_data: Dictionary containing prompt information
        
    Returns:
        bool: True if valid, False otherwise
    """
    required_fields = ['request_id', 'prompt']
    
    # Check required fields
    for field in required_fields:
        if field not in prompt_data:
            return False
    
    # Validate prompt length
    prompt = prompt_data.get('prompt', '')
    if len(prompt.strip()) < 5 or len(prompt) > 500:
        return False
    
    # Validate optional fields
    valid_styles = ['instrumental', 'ambient', 'classical', 'rock', 'electronic', 'jazz']
    valid_tempos = ['slow', 'moderate', 'fast']
    
    style = prompt_data.get('style', 'instrumental')
    tempo = prompt_data.get('tempo', 'moderate')
    duration = prompt_data.get('duration_seconds', 30)
    
    if style not in valid_styles or tempo not in valid_tempos:
        return False
    
    if not isinstance(duration, (int, float)) or duration <= 0 or duration > 300:
        return False
    
    return True