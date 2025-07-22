import json
import boto3
import os
from datetime import datetime

translate = boto3.client('translate')
dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')

# Environment variables
JOBS_TABLE_NAME = os.environ.get('JOBS_TABLE_NAME', '${jobs_table_name}')

def lambda_handler(event, context):
    """
    Lambda function for processing text translation using Amazon Translate.
    
    This function translates transcribed text into multiple target languages,
    applying custom terminology when available for consistent translations.
    
    Args:
        event: Lambda event containing transcription results and target languages
        context: Lambda context
        
    Returns:
        dict: Response with translation results or error details
    """
    
    try:
        # Extract parameters from event
        job_id = event.get('job_id')
        bucket = event.get('bucket')
        source_language = event.get('source_language')
        target_languages = event.get('target_languages', ['es', 'fr', 'de', 'pt'])
        transcription_uri = event.get('transcription_uri')
        
        # Validate required parameters
        if not job_id or not bucket or not source_language or not transcription_uri:
            raise ValueError("Missing required parameters: job_id, bucket, source_language, and transcription_uri")
        
        # Initialize DynamoDB table
        table = dynamodb.Table(JOBS_TABLE_NAME)
        
        # Update job status to translating
        table.update_item(
            Key={'JobId': job_id},
            UpdateExpression='SET #status = :status, #stage = :stage, SourceLanguage = :source_lang, UpdatedAt = :updated_at',
            ExpressionAttributeNames={
                '#status': 'Status',
                '#stage': 'Stage'
            },
            ExpressionAttributeValues={
                ':status': 'TRANSLATING',
                ':stage': 'translation',
                ':source_lang': source_language,
                ':updated_at': datetime.now().isoformat()
            }
        )
        
        print(f"Starting translation for job {job_id} from {source_language} to {target_languages}")
        
        # Download transcription results from S3
        try:
            # Parse S3 URI to extract bucket and key
            if transcription_uri.startswith('s3://'):
                s3_parts = transcription_uri.replace('s3://', '').split('/', 1)
                transcription_bucket = s3_parts[0]
                transcription_key = s3_parts[1]
            else:
                # Assume it's a relative key in the same bucket
                transcription_bucket = bucket
                transcription_key = transcription_uri
            
            transcription_obj = s3.get_object(Bucket=transcription_bucket, Key=transcription_key)
            transcription_data = json.loads(transcription_obj['Body'].read().decode('utf-8'))
            
            # Extract transcript text
            transcript = transcription_data['results']['transcripts'][0]['transcript']
            
            if not transcript or transcript.strip() == '':
                raise ValueError("Empty transcript received from transcription service")
            
            print(f"Transcript length: {len(transcript)} characters")
            
        except Exception as s3_error:
            raise ValueError(f"Failed to download transcription results: {str(s3_error)}")
        
        # Map source language code for Translate service
        source_lang_code = map_transcribe_to_translate_language(source_language)
        
        translations = {}
        translation_summary = {
            'total_languages': len(target_languages),
            'successful_translations': 0,
            'failed_translations': 0,
            'source_text_length': len(transcript)
        }
        
        # Process each target language
        for target_lang in target_languages:
            if target_lang == source_lang_code:
                # Skip translation if target language is the same as source
                translations[target_lang] = {
                    'translated_text': transcript,
                    'source_language': source_lang_code,
                    'target_language': target_lang,
                    'translation_skipped': True,
                    'reason': 'Source and target languages are the same'
                }
                translation_summary['successful_translations'] += 1
                continue
            
            try:
                print(f"Translating to {target_lang}")
                
                # Prepare translation parameters
                translate_params = {
                    'Text': transcript,
                    'SourceLanguageCode': source_lang_code,
                    'TargetLanguageCode': target_lang
                }
                
                # Check for custom terminology
                terminology_name = f"custom-terms-{source_lang_code}-{target_lang}"
                try:
                    translate.get_terminology(Name=terminology_name)
                    translate_params['TerminologyNames'] = [terminology_name]
                    print(f"Applied custom terminology: {terminology_name}")
                except translate.exceptions.ResourceNotFoundException:
                    print(f"Custom terminology {terminology_name} not found, continuing without it")
                except Exception as term_error:
                    print(f"Error checking custom terminology: {str(term_error)}")
                
                # Perform translation
                result = translate.translate_text(**translate_params)
                
                translations[target_lang] = {
                    'translated_text': result['TranslatedText'],
                    'source_language': source_lang_code,
                    'target_language': target_lang,
                    'applied_terminologies': result.get('AppliedTerminologies', []),
                    'translation_time': datetime.now().isoformat(),
                    'character_count': len(result['TranslatedText'])
                }
                
                translation_summary['successful_translations'] += 1
                print(f"Successfully translated to {target_lang}: {len(result['TranslatedText'])} characters")
                
            except Exception as translation_error:
                error_message = str(translation_error)
                print(f"Translation failed for {target_lang}: {error_message}")
                
                translations[target_lang] = {
                    'error': error_message,
                    'source_language': source_lang_code,
                    'target_language': target_lang,
                    'translation_failed': True,
                    'failure_time': datetime.now().isoformat()
                }
                
                translation_summary['failed_translations'] += 1
        
        # Store translation results in S3
        translations_result = {
            'job_id': job_id,
            'original_text': transcript,
            'source_language': source_lang_code,
            'translations': translations,
            'translation_summary': translation_summary,
            'timestamp': datetime.now().isoformat()
        }
        
        translations_key = f"translations/{job_id}/translations.json"
        s3.put_object(
            Bucket=bucket,
            Key=translations_key,
            Body=json.dumps(translations_result, indent=2),
            ContentType='application/json'
        )
        
        # Update DynamoDB with translation results
        table.update_item(
            Key={'JobId': job_id},
            UpdateExpression='SET TranslationResults = :results, TranslationSummary = :summary, UpdatedAt = :updated_at',
            ExpressionAttributeValues={
                ':results': translations_key,
                ':summary': translation_summary,
                ':updated_at': datetime.now().isoformat()
            }
        )
        
        print(f"Translation completed for job {job_id}: {translation_summary['successful_translations']} successful, {translation_summary['failed_translations']} failed")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Translation completed successfully',
                'job_id': job_id,
                'source_language': source_lang_code,
                'translations': translations,
                'translations_uri': translations_key,
                'translation_summary': translation_summary,
                'stage': 'translation'
            })
        }
        
    except Exception as e:
        error_message = str(e)
        print(f"Error in translation processing: {error_message}")
        
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
                'stage': 'translation'
            })
        }

def map_transcribe_to_translate_language(transcribe_lang):
    """
    Map Transcribe language codes to Amazon Translate language codes.
    
    Args:
        transcribe_lang: Language code from Transcribe service
        
    Returns:
        str: Language code compatible with Translate service
    """
    mapping = {
        'en-US': 'en', 'en-GB': 'en', 'en-AU': 'en',
        'es-US': 'es', 'es-ES': 'es',
        'fr-FR': 'fr', 'fr-CA': 'fr',
        'de-DE': 'de', 'it-IT': 'it',
        'pt-BR': 'pt', 'pt-PT': 'pt',
        'ja-JP': 'ja', 'ko-KR': 'ko',
        'zh-CN': 'zh', 'zh-TW': 'zh-TW',
        'ar-AE': 'ar', 'ar-SA': 'ar',
        'hi-IN': 'hi', 'ru-RU': 'ru',
        'nl-NL': 'nl', 'sv-SE': 'sv'
    }
    return mapping.get(transcribe_lang, transcribe_lang.split('-')[0])

def validate_language_code(lang_code):
    """
    Validate that a language code is supported by Amazon Translate.
    
    Args:
        lang_code: Language code to validate
        
    Returns:
        bool: True if language is supported, False otherwise
    """
    supported_languages = [
        'en', 'es', 'fr', 'de', 'it', 'pt', 'ja', 'ko', 'zh', 'zh-TW',
        'ar', 'hi', 'ru', 'nl', 'sv', 'da', 'no', 'fi', 'pl', 'cs',
        'hu', 'ro', 'bg', 'hr', 'sk', 'sl', 'et', 'lv', 'lt', 'mt',
        'el', 'he', 'tr', 'fa', 'ur', 'th', 'vi', 'id', 'ms', 'tl'
    ]
    return lang_code in supported_languages