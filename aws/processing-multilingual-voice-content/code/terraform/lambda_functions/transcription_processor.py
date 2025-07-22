import json
import boto3
import os
from datetime import datetime

transcribe = boto3.client('transcribe')
dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')

# Environment variables
JOBS_TABLE_NAME = os.environ.get('JOBS_TABLE_NAME', '${jobs_table_name}')

def lambda_handler(event, context):
    """
    Lambda function for processing speech transcription using Amazon Transcribe.
    
    This function configures and starts transcription jobs based on detected languages,
    applying language-specific settings and custom vocabularies when available.
    
    Args:
        event: Lambda event containing job details and language information
        context: Lambda context
        
    Returns:
        dict: Response with transcription job information or error details
    """
    
    try:
        # Extract parameters from event
        job_id = event.get('job_id')
        bucket = event.get('bucket')
        key = event.get('key')
        detected_language = event.get('detected_language', 'en-US')
        
        # Validate required parameters
        if not job_id or not bucket or not key:
            raise ValueError("Missing required parameters: job_id, bucket, and key")
        
        # Initialize DynamoDB table
        table = dynamodb.Table(JOBS_TABLE_NAME)
        
        # Update job status to transcribing
        table.update_item(
            Key={'JobId': job_id},
            UpdateExpression='SET #status = :status, #stage = :stage, DetectedLanguage = :lang, UpdatedAt = :updated_at',
            ExpressionAttributeNames={
                '#status': 'Status',
                '#stage': 'Stage'
            },
            ExpressionAttributeValues={
                ':status': 'TRANSCRIBING',
                ':stage': 'transcription',
                ':lang': detected_language,
                ':updated_at': datetime.now().isoformat()
            }
        )
        
        print(f"Starting transcription for job {job_id} with language {detected_language}")
        
        # Generate unique transcription job name
        job_name = f"transcribe-{job_id}"
        
        # Base transcription configuration
        transcribe_config = {
            'TranscriptionJobName': job_name,
            'Media': {'MediaFileUri': f"s3://{bucket}/{key}"},
            'OutputBucketName': bucket,
            'OutputKey': f"transcriptions/{job_id}/",
            'LanguageCode': detected_language
        }
        
        # Apply language-specific settings
        settings = {}
        
        # Enhanced settings for English languages
        if detected_language.startswith('en'):
            settings.update({
                'ShowSpeakerLabels': True,
                'MaxSpeakerLabels': 10,
                'ShowAlternatives': True,
                'MaxAlternatives': 3,
                'VocabularyFilterMethod': 'remove'
            })
        
        # Enhanced settings for Spanish languages
        elif detected_language.startswith('es'):
            settings.update({
                'ShowSpeakerLabels': True,
                'MaxSpeakerLabels': 5,
                'ShowAlternatives': True,
                'MaxAlternatives': 2
            })
        
        # General settings for other languages
        else:
            settings.update({
                'ShowAlternatives': True,
                'MaxAlternatives': 2
            })
        
        # Check for custom vocabulary and apply if available
        vocab_name = f"custom-vocab-{detected_language.split('-')[0]}"
        try:
            transcribe.get_vocabulary(VocabularyName=vocab_name)
            settings['VocabularyName'] = vocab_name
            print(f"Applied custom vocabulary: {vocab_name}")
        except transcribe.exceptions.BadRequestException:
            print(f"Custom vocabulary {vocab_name} not found, continuing without it")
        except Exception as vocab_error:
            print(f"Error checking custom vocabulary: {str(vocab_error)}")
        
        # Add settings to transcription config
        if settings:
            transcribe_config['Settings'] = settings
        
        # Start transcription job
        transcribe_response = transcribe.start_transcription_job(**transcribe_config)
        
        print(f"Transcription job started: {job_name}")
        
        # Update DynamoDB with transcription job information
        table.update_item(
            Key={'JobId': job_id},
            UpdateExpression='SET TranscriptionJobName = :job_name, TranscriptionSettings = :settings, UpdatedAt = :updated_at',
            ExpressionAttributeValues={
                ':job_name': job_name,
                ':settings': json.dumps(settings),
                ':updated_at': datetime.now().isoformat()
            }
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Transcription job started successfully',
                'job_id': job_id,
                'transcribe_job_name': job_name,
                'detected_language': detected_language,
                'bucket': bucket,
                'stage': 'transcription',
                'settings_applied': settings
            })
        }
        
    except Exception as e:
        error_message = str(e)
        print(f"Error in transcription processing: {error_message}")
        
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
                'stage': 'transcription'
            })
        }

def map_language_code(transcribe_lang):
    """
    Map Transcribe language codes to standardized codes.
    
    Args:
        transcribe_lang: Language code from Transcribe
        
    Returns:
        str: Standardized language code
    """
    mapping = {
        'en-US': 'en-US', 'en-GB': 'en-GB', 'en-AU': 'en-AU',
        'es-US': 'es-US', 'es-ES': 'es-ES',
        'fr-FR': 'fr-FR', 'fr-CA': 'fr-CA',
        'de-DE': 'de-DE', 'it-IT': 'it-IT',
        'pt-BR': 'pt-BR', 'pt-PT': 'pt-PT',
        'ja-JP': 'ja-JP', 'ko-KR': 'ko-KR',
        'zh-CN': 'zh-CN', 'zh-TW': 'zh-TW',
        'ar-AE': 'ar-AE', 'ar-SA': 'ar-SA',
        'hi-IN': 'hi-IN', 'ru-RU': 'ru-RU',
        'nl-NL': 'nl-NL', 'sv-SE': 'sv-SE'
    }
    return mapping.get(transcribe_lang, transcribe_lang)