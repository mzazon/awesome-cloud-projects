import json
from google.cloud import speech
from google.cloud import storage
import functions_framework
import os

@functions_framework.http
def transcribe_audio(request):
    """Transcribe audio file using Speech-to-Text API."""
    try:
        request_json = request.get_json()
        if not request_json:
            return {'error': 'No JSON body provided', 'status': 'error'}
            
        bucket_name = request_json.get('bucket')
        file_name = request_json.get('file')
        
        if not bucket_name or not file_name:
            return {'error': 'Missing required fields: bucket and file', 'status': 'error'}
        
        # Initialize clients
        speech_client = speech.SpeechClient()
        storage_client = storage.Client()
        
        # Get audio file from Cloud Storage
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_name)
        
        if not blob.exists():
            return {'error': f'File {file_name} not found in bucket {bucket_name}', 'status': 'error'}
            
        audio_content = blob.download_as_bytes()
        
        # Configure speech recognition with optimized settings
        audio = speech.RecognitionAudio(content=audio_content)
        
        # Determine encoding from file extension
        encoding = speech.RecognitionConfig.AudioEncoding.ENCODING_UNSPECIFIED
        if file_name.lower().endswith('.wav'):
            encoding = speech.RecognitionConfig.AudioEncoding.LINEAR16
        elif file_name.lower().endswith('.mp3'):
            encoding = speech.RecognitionConfig.AudioEncoding.MP3
        elif file_name.lower().endswith('.flac'):
            encoding = speech.RecognitionConfig.AudioEncoding.FLAC
        elif file_name.lower().endswith('.webm'):
            encoding = speech.RecognitionConfig.AudioEncoding.WEBM_OPUS
            
        config = speech.RecognitionConfig(
            encoding=encoding,
            sample_rate_hertz=48000,
            language_code="${language_code}",
            enable_automatic_punctuation=True,
            enable_spoken_punctuation=True,
            enable_word_confidence=True,
            enable_word_time_offsets=True,
            model="${speech_model}",
            use_enhanced=${enable_enhanced}
        )
        
        # Perform transcription
        response = speech_client.recognize(config=config, audio=audio)
        
        # Process results with detailed confidence tracking
        transcription = ""
        confidence_scores = []
        word_details = []
        
        for result in response.results:
            alternative = result.alternatives[0]
            transcription += alternative.transcript + " "
            confidence_scores.append(alternative.confidence)
            
            # Extract word-level details for analysis
            for word in alternative.words:
                word_details.append({
                    'word': word.word,
                    'confidence': word.confidence,
                    'start_time': word.start_time.total_seconds(),
                    'end_time': word.end_time.total_seconds()
                })
        
        # Calculate overall confidence
        overall_confidence = sum(confidence_scores) / len(confidence_scores) if confidence_scores else 0
        
        return {
            'transcription': transcription.strip(),
            'confidence': round(overall_confidence, 3),
            'word_count': len(word_details),
            'word_details': word_details,
            'status': 'success'
        }
        
    except Exception as e:
        import traceback
        return {
            'error': str(e),
            'traceback': traceback.format_exc(),
            'status': 'error'
        }