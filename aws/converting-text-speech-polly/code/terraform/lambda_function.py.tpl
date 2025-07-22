"""
Amazon Polly Text-to-Speech Lambda Function
This function processes text input and converts it to speech using Amazon Polly.
Supports both S3 event triggers and direct API invocation.
"""

import boto3
import json
import os
import uuid
from urllib.parse import unquote_plus
from typing import Dict, Any, Optional
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
polly = boto3.client('polly')
s3 = boto3.client('s3')

# Environment variables
BUCKET_NAME = os.environ.get('BUCKET_NAME', '${bucket_name}')
DEFAULT_VOICE_ID = os.environ.get('DEFAULT_VOICE_ID', '${default_voice_id}')
AWS_REGION = os.environ.get('AWS_REGION', 'us-east-1')

def validate_voice_id(voice_id: str) -> bool:
    """Validate if the provided voice ID is supported by Amazon Polly."""
    try:
        response = polly.describe_voices()
        valid_voices = [voice['Id'] for voice in response['Voices']]
        return voice_id in valid_voices
    except Exception as e:
        logger.error(f"Error validating voice ID: {str(e)}")
        return False

def synthesize_speech(text: str, voice_id: str = DEFAULT_VOICE_ID, 
                     output_format: str = 'mp3', 
                     engine: str = 'neural',
                     lexicon_names: Optional[list] = None,
                     text_type: str = 'text') -> Dict[str, Any]:
    """
    Synthesize speech using Amazon Polly.
    
    Args:
        text: The text to convert to speech
        voice_id: Amazon Polly voice ID
        output_format: Audio output format (mp3, ogg_vorbis, pcm)
        engine: Polly engine type (neural, standard, long-form, generative)
        lexicon_names: List of custom lexicon names to apply
        text_type: Type of text input (text, ssml)
    
    Returns:
        Dictionary containing synthesis result or error information
    """
    try:
        # Validate voice ID
        if not validate_voice_id(voice_id):
            logger.warning(f"Invalid voice ID: {voice_id}, using default: {DEFAULT_VOICE_ID}")
            voice_id = DEFAULT_VOICE_ID

        # Prepare synthesis parameters
        synthesis_params = {
            'Text': text,
            'OutputFormat': output_format,
            'VoiceId': voice_id,
            'Engine': engine,
            'TextType': text_type
        }

        # Add lexicon names if provided
        if lexicon_names:
            synthesis_params['LexiconNames'] = lexicon_names

        # Perform synthesis
        logger.info(f"Synthesizing speech for {len(text)} characters using voice {voice_id}")
        response = polly.synthesize_speech(**synthesis_params)

        return {
            'success': True,
            'audio_stream': response['AudioStream'],
            'content_type': response.get('ContentType', 'audio/mpeg'),
            'request_characters': response.get('RequestCharacters', len(text))
        }

    except Exception as e:
        logger.error(f"Error in speech synthesis: {str(e)}")
        return {
            'success': False,
            'error': str(e)
        }

def save_audio_to_s3(audio_stream: bytes, bucket: str, key: str, 
                    content_type: str = 'audio/mpeg') -> Dict[str, Any]:
    """
    Save audio content to S3 bucket.
    
    Args:
        audio_stream: Audio data bytes
        bucket: S3 bucket name
        key: S3 object key
        content_type: MIME type for the audio file
    
    Returns:
        Dictionary containing upload result
    """
    try:
        # Upload to S3 with appropriate metadata
        s3.put_object(
            Bucket=bucket,
            Key=key,
            Body=audio_stream,
            ContentType=content_type,
            Metadata={
                'generated-by': 'amazon-polly',
                'processing-timestamp': str(uuid.uuid4()),
                'content-length': str(len(audio_stream))
            }
        )

        logger.info(f"Audio file uploaded to s3://{bucket}/{key}")
        return {
            'success': True,
            's3_url': f"s3://{bucket}/{key}",
            'https_url': f"https://{bucket}.s3.{AWS_REGION}.amazonaws.com/{key}",
            'size_bytes': len(audio_stream)
        }

    except Exception as e:
        logger.error(f"Error uploading to S3: {str(e)}")
        return {
            'success': False,
            'error': str(e)
        }

def process_s3_event(event_record: Dict[str, Any]) -> Dict[str, Any]:
    """
    Process S3 event to extract text content and synthesize speech.
    
    Args:
        event_record: S3 event record
    
    Returns:
        Dictionary containing processing result
    """
    try:
        # Extract bucket and object key from event
        bucket = event_record['s3']['bucket']['name']
        key = unquote_plus(event_record['s3']['object']['key'])
        
        logger.info(f"Processing S3 object: s3://{bucket}/{key}")

        # Read text content from S3
        response = s3.get_object(Bucket=bucket, Key=key)
        text_content = response['Body'].read().decode('utf-8')

        # Extract metadata from S3 object if available
        metadata = response.get('Metadata', {})
        voice_id = metadata.get('voice-id', DEFAULT_VOICE_ID)
        output_format = metadata.get('output-format', 'mp3')
        engine = metadata.get('engine', 'neural')

        # Synthesize speech
        synthesis_result = synthesize_speech(
            text=text_content,
            voice_id=voice_id,
            output_format=output_format,
            engine=engine
        )

        if not synthesis_result['success']:
            return synthesis_result

        # Generate output key
        base_name = os.path.splitext(key)[0]
        output_key = f"audio/{base_name}_{voice_id}.{output_format}"

        # Save to S3
        audio_stream = synthesis_result['audio_stream'].read()
        upload_result = save_audio_to_s3(
            audio_stream=audio_stream,
            bucket=BUCKET_NAME,
            key=output_key,
            content_type=synthesis_result['content_type']
        )

        return {
            'success': True,
            'source_file': f"s3://{bucket}/{key}",
            'audio_file': upload_result.get('s3_url'),
            'characters_processed': len(text_content),
            'voice_used': voice_id,
            'file_size_bytes': upload_result.get('size_bytes')
        }

    except Exception as e:
        logger.error(f"Error processing S3 event: {str(e)}")
        return {
            'success': False,
            'error': str(e)
        }

def process_direct_invocation(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Process direct Lambda invocation with text content.
    
    Args:
        event: Lambda event containing text and parameters
    
    Returns:
        Dictionary containing processing result
    """
    try:
        # Extract parameters from event
        text_content = event.get('text', 'Hello from Amazon Polly!')
        voice_id = event.get('voice_id', DEFAULT_VOICE_ID)
        output_format = event.get('output_format', 'mp3')
        engine = event.get('engine', 'neural')
        lexicon_names = event.get('lexicon_names', [])
        text_type = event.get('text_type', 'text')

        logger.info(f"Processing direct invocation with {len(text_content)} characters")

        # Synthesize speech
        synthesis_result = synthesize_speech(
            text=text_content,
            voice_id=voice_id,
            output_format=output_format,
            engine=engine,
            lexicon_names=lexicon_names if lexicon_names else None,
            text_type=text_type
        )

        if not synthesis_result['success']:
            return synthesis_result

        # Generate unique output key
        request_id = str(uuid.uuid4())
        output_key = f"audio/direct_{request_id}_{voice_id}.{output_format}"

        # Save to S3
        audio_stream = synthesis_result['audio_stream'].read()
        upload_result = save_audio_to_s3(
            audio_stream=audio_stream,
            bucket=BUCKET_NAME,
            key=output_key,
            content_type=synthesis_result['content_type']
        )

        return {
            'success': True,
            'audio_file': upload_result.get('s3_url'),
            'https_url': upload_result.get('https_url'),
            'characters_processed': len(text_content),
            'voice_used': voice_id,
            'engine_used': engine,
            'file_size_bytes': upload_result.get('size_bytes'),
            'request_id': request_id
        }

    except Exception as e:
        logger.error(f"Error processing direct invocation: {str(e)}")
        return {
            'success': False,
            'error': str(e)
        }

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler function.
    
    Args:
        event: Lambda event data
        context: Lambda context object
    
    Returns:
        Response dictionary
    """
    logger.info(f"Lambda function invoked with event: {json.dumps(event, default=str)}")

    try:
        # Determine event source and process accordingly
        if 'Records' in event:
            # S3 event trigger
            results = []
            for record in event['Records']:
                if record.get('eventSource') == 'aws:s3':
                    result = process_s3_event(record)
                    results.append(result)
            
            # Return combined results
            success_count = sum(1 for r in results if r.get('success'))
            return {
                'statusCode': 200 if success_count == len(results) else 207,
                'body': json.dumps({
                    'message': f'Processed {len(results)} files, {success_count} successful',
                    'results': results
                })
            }
        else:
            # Direct invocation
            result = process_direct_invocation(event)
            return {
                'statusCode': 200 if result.get('success') else 500,
                'body': json.dumps(result)
            }

    except Exception as e:
        logger.error(f"Unexpected error in lambda_handler: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'success': False,
                'error': f"Internal server error: {str(e)}"
            })
        }