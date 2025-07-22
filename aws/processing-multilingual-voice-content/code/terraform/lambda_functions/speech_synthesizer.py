import json
import boto3
import os
import re
from datetime import datetime

polly = boto3.client('polly')
dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')

# Environment variables
JOBS_TABLE_NAME = os.environ.get('JOBS_TABLE_NAME', '${jobs_table_name}')
VOICE_PREFERENCES = json.loads(os.environ.get('VOICE_PREFERENCES', '${voice_preferences}'))

def lambda_handler(event, context):
    """
    Lambda function for synthesizing speech using Amazon Polly.
    
    This function converts translated text into speech using appropriate voices
    for each language, applying SSML enhancements for better audio quality.
    
    Args:
        event: Lambda event containing translation results
        context: Lambda context
        
    Returns:
        dict: Response with audio file locations or error details
    """
    
    try:
        # Extract parameters from event
        job_id = event.get('job_id')
        bucket = event.get('bucket')
        translations = event.get('translations', {})
        
        # Validate required parameters
        if not job_id or not bucket or not translations:
            raise ValueError("Missing required parameters: job_id, bucket, and translations")
        
        # Initialize DynamoDB table
        table = dynamodb.Table(JOBS_TABLE_NAME)
        
        # Update job status to synthesizing
        table.update_item(
            Key={'JobId': job_id},
            UpdateExpression='SET #status = :status, #stage = :stage, UpdatedAt = :updated_at',
            ExpressionAttributeNames={
                '#status': 'Status',
                '#stage': 'Stage'
            },
            ExpressionAttributeValues={
                ':status': 'SYNTHESIZING',
                ':stage': 'speech_synthesis',
                ':updated_at': datetime.now().isoformat()
            }
        )
        
        print(f"Starting speech synthesis for job {job_id} with {len(translations)} translations")
        
        audio_outputs = {}
        synthesis_summary = {
            'total_languages': len(translations),
            'successful_synthesis': 0,
            'failed_synthesis': 0,
            'total_audio_duration': 0
        }
        
        # Process each translation
        for target_lang, translation_data in translations.items():
            if 'translated_text' not in translation_data:
                print(f"Skipping {target_lang} - no translated text available")
                audio_outputs[target_lang] = {
                    'error': 'No translated text available',
                    'synthesis_skipped': True
                }
                synthesis_summary['failed_synthesis'] += 1
                continue
            
            try:
                print(f"Synthesizing speech for {target_lang}")
                
                # Select appropriate voice for the language
                voice_id = select_voice_for_language(target_lang)
                
                # Prepare text for synthesis with SSML enhancements
                text_to_synthesize = prepare_text_for_synthesis(
                    translation_data['translated_text'],
                    target_lang
                )
                
                # Determine optimal settings for the voice
                engine_type = 'neural' if supports_neural_voice(voice_id) else 'standard'
                text_type = 'ssml' if text_to_synthesize.startswith('<speak>') else 'text'
                
                print(f"Using voice {voice_id} with {engine_type} engine for {target_lang}")
                
                # Synthesize speech
                synthesis_response = polly.synthesize_speech(
                    Text=text_to_synthesize,
                    VoiceId=voice_id,
                    OutputFormat='mp3',
                    Engine=engine_type,
                    TextType=text_type,
                    SampleRate='22050'  # High quality audio
                )
                
                # Generate audio file key
                audio_key = f"audio-output/{job_id}/{target_lang}.mp3"
                
                # Save audio to S3
                audio_stream = synthesis_response['AudioStream'].read()
                s3.put_object(
                    Bucket=bucket,
                    Key=audio_key,
                    Body=audio_stream,
                    ContentType='audio/mpeg',
                    Metadata={
                        'job-id': job_id,
                        'language': target_lang,
                        'voice-id': voice_id,
                        'engine': engine_type,
                        'text-length': str(len(translation_data['translated_text']))
                    }
                )
                
                # Calculate estimated duration (approximate)
                estimated_duration = estimate_audio_duration(
                    translation_data['translated_text'],
                    target_lang
                )
                
                audio_outputs[target_lang] = {
                    'audio_uri': f"s3://{bucket}/{audio_key}",
                    'audio_key': audio_key,
                    'voice_id': voice_id,
                    'engine': engine_type,
                    'text_length': len(translation_data['translated_text']),
                    'audio_format': 'mp3',
                    'sample_rate': '22050',
                    'estimated_duration_seconds': estimated_duration,
                    'synthesis_time': datetime.now().isoformat()
                }
                
                synthesis_summary['successful_synthesis'] += 1
                synthesis_summary['total_audio_duration'] += estimated_duration
                
                print(f"Successfully synthesized speech for {target_lang}: {len(audio_stream)} bytes")
                
            except Exception as synthesis_error:
                error_message = str(synthesis_error)
                print(f"Speech synthesis failed for {target_lang}: {error_message}")
                
                audio_outputs[target_lang] = {
                    'error': error_message,
                    'synthesis_failed': True,
                    'failure_time': datetime.now().isoformat()
                }
                
                synthesis_summary['failed_synthesis'] += 1
        
        # Update job status to completed
        final_status = 'COMPLETED' if synthesis_summary['successful_synthesis'] > 0 else 'FAILED'
        
        table.update_item(
            Key={'JobId': job_id},
            UpdateExpression='SET #status = :status, #stage = :stage, AudioOutputs = :outputs, SynthesisSummary = :summary, CompletedAt = :completed_at, UpdatedAt = :updated_at',
            ExpressionAttributeNames={
                '#status': 'Status',
                '#stage': 'Stage'
            },
            ExpressionAttributeValues={
                ':status': final_status,
                ':stage': 'completed',
                ':outputs': audio_outputs,
                ':summary': synthesis_summary,
                ':completed_at': datetime.now().isoformat(),
                ':updated_at': datetime.now().isoformat()
            }
        )
        
        print(f"Speech synthesis completed for job {job_id}: {synthesis_summary['successful_synthesis']} successful, {synthesis_summary['failed_synthesis']} failed")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Speech synthesis completed successfully',
                'job_id': job_id,
                'audio_outputs': audio_outputs,
                'synthesis_summary': synthesis_summary,
                'stage': 'completed'
            })
        }
        
    except Exception as e:
        error_message = str(e)
        print(f"Error in speech synthesis: {error_message}")
        
        # Update DynamoDB with error status
        try:
            job_id = event.get('job_id') if event else None
            if job_id:
                table = dynamodb.Table(JOBS_TABLE_NAME)
                table.update_item(
                    Key={'JobId': job_id},
                    UpdateExpression='SET #status = :status, #error = :error, FailedAt = :failed_at',
                    ExpressionAttributeNames={
                        '#status': 'Status',
                        '#error': 'Error'
                    },
                    ExpressionAttributeValues={
                        ':status': 'FAILED',
                        ':error': error_message,
                        ':failed_at': datetime.now().isoformat()
                    }
                )
        except Exception as db_error:
            print(f"Failed to update DynamoDB with error: {str(db_error)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_message,
                'job_id': job_id if 'job_id' in locals() else None,
                'stage': 'speech_synthesis'
            })
        }

def select_voice_for_language(language_code):
    """
    Select the most appropriate Polly voice for a given language.
    
    Args:
        language_code: ISO language code
        
    Returns:
        str: Polly voice ID
    """
    # Use configured voice preferences first
    if language_code in VOICE_PREFERENCES:
        return VOICE_PREFERENCES[language_code]
    
    # Fallback to default voice mapping
    default_voices = {
        'en': 'Joanna',    # English - Neural voice
        'es': 'Lupe',      # Spanish - Neural voice
        'fr': 'Lea',       # French - Neural voice
        'de': 'Vicki',     # German - Neural voice
        'it': 'Bianca',    # Italian - Neural voice
        'pt': 'Camila',    # Portuguese - Neural voice
        'ja': 'Takumi',    # Japanese - Neural voice
        'ko': 'Seoyeon',   # Korean - Standard voice
        'zh': 'Zhiyu',     # Chinese - Neural voice
        'ar': 'Zeina',     # Arabic - Standard voice
        'hi': 'Aditi',     # Hindi - Standard voice
        'ru': 'Tatyana',   # Russian - Standard voice
        'nl': 'Lotte',     # Dutch - Standard voice
        'sv': 'Astrid'     # Swedish - Standard voice
    }
    
    return default_voices.get(language_code, 'Joanna')

def supports_neural_voice(voice_id):
    """
    Check if a voice supports neural engine.
    
    Args:
        voice_id: Polly voice ID
        
    Returns:
        bool: True if neural voice is supported
    """
    neural_voices = {
        'Joanna', 'Matthew', 'Ivy', 'Justin', 'Kendra', 'Kimberly', 'Salli',
        'Joey', 'Lupe', 'Lucia', 'Lea', 'Vicki', 'Bianca', 'Camila',
        'Takumi', 'Zhiyu', 'Ruth', 'Stephen', 'Olivia', 'Amy', 'Emma',
        'Brian', 'Arthur', 'Ayanda', 'Aria', 'Arlet', 'Hannah', 'Liam',
        'Lisa', 'Mads', 'Naja', 'Sofie', 'Laura', 'Suvi', 'Ida',
        'Seoyeon', 'Hiujin', 'Kazuha', 'Tomoko'
    }
    
    return voice_id in neural_voices

def prepare_text_for_synthesis(text, language_code):
    """
    Prepare text for speech synthesis with SSML enhancements.
    
    Args:
        text: Text to be synthesized
        language_code: Target language code
        
    Returns:
        str: Enhanced text with SSML markup
    """
    # Clean and normalize text
    text = text.strip()
    
    # Don't add SSML for very short texts
    if len(text) < 50:
        return text
    
    # Add basic SSML for longer texts
    if len(text) > 200:
        # Add pauses at sentence boundaries for better comprehension
        text = re.sub(r'\.(\s+)', r'.<break time="500ms"/>\1', text)
        text = re.sub(r'!(\s+)', r'!<break time="500ms"/>\1', text)
        text = re.sub(r'\?(\s+)', r'?<break time="500ms"/>\1', text)
        
        # Add emphasis for important words (basic heuristic)
        text = re.sub(r'\b(important|critical|urgent|warning|note|attention)\b', 
                     r'<emphasis level="strong">\1</emphasis>', text, flags=re.IGNORECASE)
    
    # Language-specific enhancements
    if language_code == 'en':
        # English: Add prosody for better flow
        text = f'<prosody rate="medium" pitch="medium">{text}</prosody>'
    elif language_code == 'es':
        # Spanish: Slightly slower rate for clarity
        text = f'<prosody rate="slow" pitch="medium">{text}</prosody>'
    elif language_code == 'fr':
        # French: Medium rate with slight pitch variation
        text = f'<prosody rate="medium" pitch="+2%">{text}</prosody>'
    elif language_code == 'de':
        # German: Slower rate for complex compound words
        text = f'<prosody rate="slow" pitch="medium">{text}</prosody>'
    elif language_code == 'ja':
        # Japanese: Slower rate for proper pronunciation
        text = f'<prosody rate="slow" pitch="medium">{text}</prosody>'
    elif language_code == 'zh':
        # Chinese: Medium rate with careful pronunciation
        text = f'<prosody rate="medium" pitch="medium">{text}</prosody>'
    
    # Wrap in speak tags if SSML was added
    if '<' in text and '>' in text:
        text = f'<speak>{text}</speak>'
    
    return text

def estimate_audio_duration(text, language_code):
    """
    Estimate audio duration based on text length and language.
    
    Args:
        text: Text to be synthesized
        language_code: Target language code
        
    Returns:
        int: Estimated duration in seconds
    """
    # Average speaking rates by language (words per minute)
    speaking_rates = {
        'en': 150,  # English
        'es': 160,  # Spanish
        'fr': 140,  # French
        'de': 130,  # German
        'it': 155,  # Italian
        'pt': 150,  # Portuguese
        'ja': 120,  # Japanese
        'ko': 125,  # Korean
        'zh': 110,  # Chinese
        'ar': 140,  # Arabic
        'hi': 135,  # Hindi
        'ru': 145,  # Russian
        'nl': 150,  # Dutch
        'sv': 145   # Swedish
    }
    
    # Estimate word count (rough approximation)
    word_count = len(text.split())
    
    # Get speaking rate for the language
    wpm = speaking_rates.get(language_code, 150)  # Default to English rate
    
    # Calculate duration in seconds
    duration_seconds = (word_count / wpm) * 60
    
    # Add buffer for pauses and SSML processing
    duration_seconds *= 1.2
    
    return int(duration_seconds)