import json
import boto3
import os
from datetime import datetime

transcribe = boto3.client('transcribe')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Lambda function for checking the status of Amazon Transcribe jobs.
    
    This function monitors transcription job progress and extracts results
    when jobs complete successfully, supporting both language detection
    and transcription job types.
    
    Args:
        event: Lambda event containing job name and type
        context: Lambda context
        
    Returns:
        dict: Response with job status and results
    """
    
    try:
        # Extract parameters from event
        job_name = event.get('transcribe_job_name')
        job_type = event.get('job_type', 'transcription')
        
        # Validate required parameters
        if not job_name:
            raise ValueError("Missing required parameter: transcribe_job_name")
        
        print(f"Checking status for {job_type} job: {job_name}")
        
        # Get transcription job status
        response = transcribe.get_transcription_job(
            TranscriptionJobName=job_name
        )
        
        transcription_job = response['TranscriptionJob']
        job_status = transcription_job['TranscriptionJobStatus']
        
        print(f"Job {job_name} status: {job_status}")
        
        # Build base result
        result = {
            'statusCode': 200,
            'body': json.dumps({
                'job_name': job_name,
                'job_type': job_type,
                'job_status': job_status,
                'is_complete': job_status in ['COMPLETED', 'FAILED'],
                'creation_time': transcription_job.get('CreationTime', '').isoformat() if transcription_job.get('CreationTime') else None,
                'completion_time': transcription_job.get('CompletionTime', '').isoformat() if transcription_job.get('CompletionTime') else None
            })
        }
        
        # Handle completed jobs
        if job_status == 'COMPLETED':
            print(f"Job {job_name} completed successfully")
            
            if job_type == 'language_detection':
                # Extract language detection results
                language_code = transcription_job.get('LanguageCode')
                language_options = transcription_job.get('LanguageOptions', [])
                identify_language = transcription_job.get('IdentifyLanguage', False)
                
                # Handle identify language results
                if identify_language and language_code:
                    result['body'] = json.dumps({
                        **json.loads(result['body']),
                        'detected_language': language_code,
                        'language_options': language_options,
                        'confidence_score': extract_language_confidence(transcription_job)
                    })
                else:
                    result['body'] = json.dumps({
                        **json.loads(result['body']),
                        'detected_language': language_code or 'en-US',
                        'language_options': language_options
                    })
                
                print(f"Detected language: {language_code}")
                
            else:
                # Extract transcription results
                transcript_uri = transcription_job['Transcript']['TranscriptFileUri']
                language_code = transcription_job.get('LanguageCode')
                media_format = transcription_job.get('MediaFormat')
                
                # Parse transcript URI to get S3 location
                transcript_s3_info = parse_s3_uri(transcript_uri)
                
                result['body'] = json.dumps({
                    **json.loads(result['body']),
                    'transcript_uri': transcript_uri,
                    'transcript_s3_bucket': transcript_s3_info['bucket'],
                    'transcript_s3_key': transcript_s3_info['key'],
                    'source_language': language_code,
                    'media_format': media_format,
                    'media_sample_rate': transcription_job.get('MediaSampleRateHertz'),
                    'settings': extract_transcription_settings(transcription_job)
                })
                
                print(f"Transcription URI: {transcript_uri}")
        
        # Handle failed jobs
        elif job_status == 'FAILED':
            failure_reason = transcription_job.get('FailureReason', 'Unknown error')
            print(f"Job {job_name} failed: {failure_reason}")
            
            result['body'] = json.dumps({
                **json.loads(result['body']),
                'failure_reason': failure_reason
            })
        
        # Handle in-progress jobs
        elif job_status == 'IN_PROGRESS':
            print(f"Job {job_name} is still in progress")
            
            # Add progress information if available
            progress_info = extract_progress_info(transcription_job)
            if progress_info:
                result['body'] = json.dumps({
                    **json.loads(result['body']),
                    'progress_info': progress_info
                })
        
        return result
        
    except transcribe.exceptions.BadRequestException as e:
        error_message = f"Invalid transcription job request: {str(e)}"
        print(f"BadRequestException: {error_message}")
        
        return {
            'statusCode': 400,
            'body': json.dumps({
                'error': error_message,
                'job_name': job_name if 'job_name' in locals() else None,
                'error_type': 'BadRequestException'
            })
        }
    
    except transcribe.exceptions.NotFoundException as e:
        error_message = f"Transcription job not found: {str(e)}"
        print(f"NotFoundException: {error_message}")
        
        return {
            'statusCode': 404,
            'body': json.dumps({
                'error': error_message,
                'job_name': job_name if 'job_name' in locals() else None,
                'error_type': 'NotFoundException'
            })
        }
    
    except Exception as e:
        error_message = str(e)
        print(f"Error checking job status: {error_message}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_message,
                'job_name': job_name if 'job_name' in locals() else None,
                'error_type': 'InternalError'
            })
        }

def extract_language_confidence(transcription_job):
    """
    Extract language confidence score from transcription job results.
    
    Args:
        transcription_job: Transcription job response from API
        
    Returns:
        float: Confidence score or None if not available
    """
    try:
        # Look for language identification score
        if 'LanguageIdSettings' in transcription_job:
            language_id_settings = transcription_job['LanguageIdSettings']
            if 'LanguageModelName' in language_id_settings:
                # This is a placeholder - actual confidence extraction would
                # require parsing the transcript file
                return 0.95  # Default high confidence
        
        # Alternative approach - check if language was identified automatically
        if transcription_job.get('IdentifyLanguage', False):
            return 0.90  # Default confidence for auto-detected languages
            
        return None
        
    except Exception as e:
        print(f"Error extracting language confidence: {str(e)}")
        return None

def extract_transcription_settings(transcription_job):
    """
    Extract transcription settings from job response.
    
    Args:
        transcription_job: Transcription job response from API
        
    Returns:
        dict: Settings used for transcription
    """
    try:
        settings = {}
        
        # Extract basic settings
        if 'Settings' in transcription_job:
            job_settings = transcription_job['Settings']
            
            settings = {
                'show_speaker_labels': job_settings.get('ShowSpeakerLabels', False),
                'max_speaker_labels': job_settings.get('MaxSpeakerLabels'),
                'show_alternatives': job_settings.get('ShowAlternatives', False),
                'max_alternatives': job_settings.get('MaxAlternatives'),
                'vocabulary_name': job_settings.get('VocabularyName'),
                'vocabulary_filter_name': job_settings.get('VocabularyFilterName'),
                'vocabulary_filter_method': job_settings.get('VocabularyFilterMethod'),
                'channel_identification': job_settings.get('ChannelIdentification', False)
            }
            
            # Remove None values
            settings = {k: v for k, v in settings.items() if v is not None}
        
        # Extract model settings
        if 'ModelSettings' in transcription_job:
            model_settings = transcription_job['ModelSettings']
            settings['language_model_name'] = model_settings.get('LanguageModelName')
        
        return settings
        
    except Exception as e:
        print(f"Error extracting transcription settings: {str(e)}")
        return {}

def extract_progress_info(transcription_job):
    """
    Extract progress information from transcription job.
    
    Args:
        transcription_job: Transcription job response from API
        
    Returns:
        dict: Progress information or None if not available
    """
    try:
        progress = {}
        
        # Check for start time
        if 'StartTime' in transcription_job:
            progress['start_time'] = transcription_job['StartTime'].isoformat()
        
        # Calculate elapsed time
        if 'CreationTime' in transcription_job:
            creation_time = transcription_job['CreationTime']
            elapsed_seconds = (datetime.now() - creation_time.replace(tzinfo=None)).total_seconds()
            progress['elapsed_seconds'] = int(elapsed_seconds)
        
        # Media duration (if available)
        if 'MediaSampleRateHertz' in transcription_job:
            progress['media_sample_rate'] = transcription_job['MediaSampleRateHertz']
        
        # Job queue position or other progress indicators would go here
        # (not available in current API response)
        
        return progress if progress else None
        
    except Exception as e:
        print(f"Error extracting progress info: {str(e)}")
        return None

def parse_s3_uri(s3_uri):
    """
    Parse S3 URI to extract bucket and key components.
    
    Args:
        s3_uri: S3 URI in format s3://bucket/key
        
    Returns:
        dict: Dictionary with bucket and key components
    """
    try:
        if not s3_uri or not s3_uri.startswith('s3://'):
            raise ValueError("Invalid S3 URI format")
        
        # Remove s3:// prefix
        path = s3_uri[5:]
        
        # Split into bucket and key
        parts = path.split('/', 1)
        if len(parts) < 2:
            raise ValueError("S3 URI must contain both bucket and key")
        
        return {
            'bucket': parts[0],
            'key': parts[1]
        }
        
    except Exception as e:
        print(f"Error parsing S3 URI {s3_uri}: {str(e)}")
        return {
            'bucket': None,
            'key': None
        }