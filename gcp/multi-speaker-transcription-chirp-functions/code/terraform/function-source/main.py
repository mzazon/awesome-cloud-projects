"""
Multi-Speaker Audio Transcription with Chirp 3 and Speaker Diarization
Cloud Function for processing audio files uploaded to Cloud Storage
"""

import json
import os
import logging
from typing import Dict, List, Any, Optional
from google.cloud import speech_v2 as speech
from google.cloud import storage
from google.cloud import pubsub_v1
import functions_framework

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuration from environment variables and Terraform template
SPEECH_MODEL = "${speech_model}"
ENABLE_DIARIZATION = ${enable_speaker_diarization}
MIN_SPEAKER_COUNT = ${min_speaker_count}
MAX_SPEAKER_COUNT = ${max_speaker_count}
LANGUAGE_CODES = ${language_codes}

def get_environment_config() -> Dict[str, Any]:
    """Get configuration from environment variables."""
    return {
        'output_bucket': os.environ.get('OUTPUT_BUCKET'),
        'speech_model': os.environ.get('SPEECH_MODEL', SPEECH_MODEL),
        'enable_diarization': os.environ.get('ENABLE_DIARIZATION', 'true').lower() == 'true',
        'min_speaker_count': int(os.environ.get('MIN_SPEAKER_COUNT', MIN_SPEAKER_COUNT)),
        'max_speaker_count': int(os.environ.get('MAX_SPEAKER_COUNT', MAX_SPEAKER_COUNT)),
        'language_codes': json.loads(os.environ.get('LANGUAGE_CODES', json.dumps(LANGUAGE_CODES))),
        'notification_topic': os.environ.get('NOTIFICATION_TOPIC', ''),
        'project_id': os.environ.get('GCP_PROJECT', os.environ.get('GOOGLE_CLOUD_PROJECT'))
    }

def transcribe_audio_with_diarization(
    audio_uri: str, 
    output_bucket: str, 
    filename: str,
    config: Dict[str, Any]
) -> Dict[str, Any]:
    """
    Transcribe audio with speaker diarization using Chirp 3 model.
    
    Args:
        audio_uri: GCS URI of the audio file
        output_bucket: Name of the output bucket
        filename: Original filename
        config: Configuration dictionary
        
    Returns:
        Dictionary containing transcription results
    """
    logger.info(f"Starting transcription for: {filename}")
    logger.info(f"Using model: {config['speech_model']}")
    logger.info(f"Diarization enabled: {config['enable_diarization']}")
    
    # Initialize Speech-to-Text v2 client
    client = speech.SpeechClient()
    
    # Configure recognition settings
    recognition_config = speech.RecognitionConfig(
        auto_decoding_config=speech.AutoDetectDecodingConfig(),
        language_codes=config['language_codes'],
        model=config['speech_model'],
        features=speech.RecognitionFeatures(
            enable_speaker_diarization=config['enable_diarization'],
            diarization_speaker_count_min=config['min_speaker_count'],
            diarization_speaker_count_max=config['max_speaker_count'],
            enable_automatic_punctuation=True,
            enable_word_time_offsets=True,
            enable_word_confidence=True,
        ),
    )
    
    # Create recognizer name
    recognizer_name = f"projects/{config['project_id']}/locations/global/recognizers/_"
    
    # Configure batch recognition request
    request = speech.BatchRecognizeRequest(
        recognizer=recognizer_name,
        config=recognition_config,
        files=[
            speech.BatchRecognizeFileMetadata(
                uri=audio_uri,
            )
        ],
    )
    
    try:
        # Perform batch recognition operation
        logger.info("Submitting batch recognition request...")
        operation = client.batch_recognize(request=request)
        
        logger.info("Waiting for transcription to complete...")
        response = operation.result(timeout=600)  # 10 minute timeout
        
        # Process results with speaker labels
        transcript_data = {
            "filename": filename,
            "audio_uri": audio_uri,
            "speech_model": config['speech_model'],
            "language_codes": config['language_codes'],
            "diarization_enabled": config['enable_diarization'],
            "speakers": {},
            "full_transcript": "",
            "word_details": [],
            "processing_status": "completed",
            "speaker_count": 0
        }
        
        # Process recognition results
        for result_uri, result in response.results.items():
            logger.info(f"Processing results for: {result_uri}")
            
            for alternative in result.alternatives:
                confidence = getattr(alternative, 'confidence', 0.0)
                transcript_data["confidence"] = confidence
                transcript_data["full_transcript"] += alternative.transcript + " "
                
                # Process speaker-labeled words
                for word in alternative.words:
                    speaker_tag = getattr(word, 'speaker_tag', 1) if config['enable_diarization'] else 1
                    word_text = word.word
                    start_time = word.start_offset.total_seconds()
                    end_time = word.end_offset.total_seconds()
                    word_confidence = getattr(word, 'confidence', 0.0)
                    
                    # Group words by speaker
                    if speaker_tag not in transcript_data["speakers"]:
                        transcript_data["speakers"][speaker_tag] = []
                    
                    transcript_data["speakers"][speaker_tag].append({
                        "word": word_text,
                        "start_time": start_time,
                        "end_time": end_time,
                        "confidence": word_confidence
                    })
                    
                    transcript_data["word_details"].append({
                        "word": word_text,
                        "speaker": speaker_tag,
                        "start_time": start_time,
                        "end_time": end_time,
                        "confidence": word_confidence
                    })
        
        # Calculate speaker statistics
        transcript_data["speaker_count"] = len(transcript_data["speakers"])
        
        # Add speaker statistics
        for speaker_id, words in transcript_data["speakers"].items():
            if words:
                duration = words[-1]['end_time'] - words[0]['start_time']
                word_count = len(words)
                avg_confidence = sum(w['confidence'] for w in words) / word_count if word_count > 0 else 0.0
                
                transcript_data["speakers"][speaker_id] = {
                    "words": words,
                    "word_count": word_count,
                    "duration_seconds": duration,
                    "average_confidence": avg_confidence
                }
        
        logger.info(f"Transcription completed. Speakers detected: {transcript_data['speaker_count']}")
        
        # Save results to output bucket
        save_transcription_results(transcript_data, output_bucket)
        
        # Send notification if configured
        if config['notification_topic']:
            send_notification(transcript_data, config)
        
        return transcript_data
        
    except Exception as e:
        logger.error(f"Error during transcription: {str(e)}")
        error_data = {
            "filename": filename,
            "audio_uri": audio_uri,
            "processing_status": "failed",
            "error": str(e)
        }
        save_error_result(error_data, output_bucket)
        raise e

def save_transcription_results(transcript_data: Dict[str, Any], output_bucket: str) -> None:
    """Save transcription results to Cloud Storage."""
    storage_client = storage.Client()
    bucket = storage_client.bucket(output_bucket)
    
    filename = transcript_data["filename"]
    
    # Save JSON transcript
    json_filename = f"transcripts/{filename}_transcript.json"
    blob = bucket.blob(json_filename)
    blob.upload_from_string(
        json.dumps(transcript_data, indent=2),
        content_type="application/json"
    )
    logger.info(f"Saved JSON transcript: {json_filename}")
    
    # Save readable transcript
    readable_transcript = generate_readable_transcript(transcript_data)
    txt_filename = f"transcripts/{filename}_readable.txt"
    blob = bucket.blob(txt_filename)
    blob.upload_from_string(readable_transcript, content_type="text/plain")
    logger.info(f"Saved readable transcript: {txt_filename}")
    
    # Save speaker summary
    speaker_summary = generate_speaker_summary(transcript_data)
    summary_filename = f"transcripts/{filename}_speaker_summary.txt"
    blob = bucket.blob(summary_filename)
    blob.upload_from_string(speaker_summary, content_type="text/plain")
    logger.info(f"Saved speaker summary: {summary_filename}")

def save_error_result(error_data: Dict[str, Any], output_bucket: str) -> None:
    """Save error information to Cloud Storage."""
    storage_client = storage.Client()
    bucket = storage_client.bucket(output_bucket)
    
    filename = error_data["filename"]
    error_filename = f"errors/{filename}_error.json"
    blob = bucket.blob(error_filename)
    blob.upload_from_string(
        json.dumps(error_data, indent=2),
        content_type="application/json"
    )
    logger.info(f"Saved error result: {error_filename}")

def generate_readable_transcript(transcript_data: Dict[str, Any]) -> str:
    """Generate human-readable transcript with speaker labels."""
    output = f"Multi-Speaker Transcription Results\n"
    output += f"===================================\n\n"
    output += f"File: {transcript_data['filename']}\n"
    output += f"Model: {transcript_data['speech_model']}\n"
    output += f"Language Codes: {', '.join(transcript_data['language_codes'])}\n"
    output += f"Speakers Detected: {transcript_data['speaker_count']}\n"
    output += f"Overall Confidence: {transcript_data.get('confidence', 'N/A'):.2f}\n\n"
    
    if transcript_data.get('diarization_enabled', False):
        # Group consecutive words by speaker for better readability
        current_speaker = None
        current_segment = []
        current_start_time = None
        
        for word_detail in transcript_data["word_details"]:
            if word_detail["speaker"] != current_speaker:
                if current_segment and current_speaker is not None:
                    segment_text = ' '.join(current_segment)
                    output += f"Speaker {current_speaker} ({current_start_time:.1f}s): {segment_text}\n\n"
                
                current_speaker = word_detail["speaker"]
                current_segment = [word_detail["word"]]
                current_start_time = word_detail["start_time"]
            else:
                current_segment.append(word_detail["word"])
        
        # Add final segment
        if current_segment and current_speaker is not None:
            segment_text = ' '.join(current_segment)
            output += f"Speaker {current_speaker} ({current_start_time:.1f}s): {segment_text}\n\n"
    else:
        # No diarization - show full transcript
        output += f"Transcript:\n{transcript_data['full_transcript']}\n\n"
    
    return output

def generate_speaker_summary(transcript_data: Dict[str, Any]) -> str:
    """Generate summary statistics for each speaker."""
    output = f"Speaker Analysis Summary\n"
    output += f"=======================\n\n"
    output += f"File: {transcript_data['filename']}\n"
    output += f"Total Speakers: {transcript_data['speaker_count']}\n\n"
    
    if transcript_data.get('diarization_enabled', False) and transcript_data['speakers']:
        for speaker_id, speaker_data in transcript_data['speakers'].items():
            if isinstance(speaker_data, dict):
                output += f"Speaker {speaker_id}:\n"
                output += f"  - Words spoken: {speaker_data.get('word_count', 0)}\n"
                output += f"  - Speaking time: {speaker_data.get('duration_seconds', 0):.1f} seconds\n"
                output += f"  - Average confidence: {speaker_data.get('average_confidence', 0):.2f}\n\n"
    else:
        output += "Speaker diarization was not enabled or no speakers detected.\n"
    
    return output

def send_notification(transcript_data: Dict[str, Any], config: Dict[str, Any]) -> None:
    """Send notification about transcription completion."""
    try:
        publisher = pubsub_v1.PublisherClient()
        topic_path = config['notification_topic']
        
        message_data = {
            "event_type": "transcription_completed",
            "filename": transcript_data["filename"],
            "speaker_count": transcript_data["speaker_count"],
            "processing_status": transcript_data["processing_status"],
            "model_used": transcript_data["speech_model"]
        }
        
        # Publish message
        future = publisher.publish(topic_path, json.dumps(message_data).encode('utf-8'))
        logger.info(f"Notification sent to topic: {topic_path}")
        
    except Exception as e:
        logger.warning(f"Failed to send notification: {str(e)}")

@functions_framework.cloud_event
def process_audio_upload(cloud_event) -> None:
    """
    Cloud Function triggered by Cloud Storage uploads.
    
    Args:
        cloud_event: CloudEvent containing the storage event data
    """
    # Extract event data
    data = cloud_event.data
    bucket_name = data["bucket"]
    file_name = data["name"]
    
    logger.info(f"Processing file upload: {file_name} in bucket: {bucket_name}")
    
    # Only process audio files
    audio_extensions = ['.wav', '.mp3', '.flac', '.m4a', '.ogg', '.aiff', '.au']
    if not any(file_name.lower().endswith(ext) for ext in audio_extensions):
        logger.info(f"Skipping non-audio file: {file_name}")
        return
    
    # Skip processing files in output directories
    if file_name.startswith(('transcripts/', 'errors/', 'samples/')):
        logger.info(f"Skipping file in system directory: {file_name}")
        return
    
    # Get configuration
    config = get_environment_config()
    
    if not config['output_bucket']:
        logger.error("OUTPUT_BUCKET environment variable not set")
        return
    
    # Construct audio URI
    audio_uri = f"gs://{bucket_name}/{file_name}"
    
    try:
        logger.info(f"Starting transcription process for: {file_name}")
        
        # Process transcription
        result = transcribe_audio_with_diarization(
            audio_uri, 
            config['output_bucket'], 
            file_name,
            config
        )
        
        logger.info(f"Successfully processed: {file_name}")
        logger.info(f"Speakers detected: {result['speaker_count']}")
        logger.info(f"Total words: {len(result['word_details'])}")
        
    except Exception as e:
        logger.error(f"Error processing {file_name}: {str(e)}")
        # Re-raise to trigger Cloud Functions error reporting
        raise e