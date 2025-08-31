import json
import requests
from google.cloud import storage
import functions_framework
import os
import time

@functions_framework.http
def orchestrate_interview_analysis(request):
    """Orchestrate the complete interview analysis workflow."""
    try:
        request_json = request.get_json()
        if not request_json:
            return {'error': 'No JSON body provided', 'status': 'error'}
            
        bucket_name = request_json.get('bucket')
        file_name = request_json.get('file')
        question = request_json.get('question', 'Tell me about yourself')
        
        # Validate inputs
        if not bucket_name or not file_name:
            return {'error': 'Missing required fields: bucket and file', 'status': 'error'}
        
        # Get function URLs dynamically
        region = "${region}"
        project = "${project_id}"
        function_prefix = "${function_prefix}"
        
        speech_url = f"https://{region}-{project}.cloudfunctions.net/{function_prefix}-speech"
        analysis_url = f"https://{region}-{project}.cloudfunctions.net/{function_prefix}-analysis"
        
        # Step 1: Transcribe audio with retry logic
        speech_payload = {
            'bucket': bucket_name,
            'file': file_name
        }
        
        max_retries = 3
        speech_result = None
        
        for attempt in range(max_retries):
            try:
                speech_response = requests.post(
                    speech_url, 
                    json=speech_payload,
                    timeout=120,
                    headers={'Content-Type': 'application/json'}
                )
                speech_result = speech_response.json()
                
                if speech_result.get('status') == 'success':
                    break
                elif attempt == max_retries - 1:
                    return {
                        'error': 'Transcription failed after retries', 
                        'details': speech_result,
                        'status': 'error'
                    }
                time.sleep(2 ** attempt)  # Exponential backoff
                
            except requests.exceptions.RequestException as e:
                if attempt == max_retries - 1:
                    return {
                        'error': f'Network error in transcription: {str(e)}',
                        'status': 'error'
                    }
                time.sleep(2 ** attempt)
        
        # Validate speech result
        if not speech_result or speech_result.get('status') != 'success':
            return {
                'error': 'Speech transcription failed',
                'details': speech_result,
                'status': 'error'
            }
        
        # Step 2: Analyze with Gemini
        analysis_payload = {
            'transcription': speech_result['transcription'],
            'question': question,
            'confidence': speech_result.get('confidence', 0.0)
        }
        
        try:
            analysis_response = requests.post(
                analysis_url, 
                json=analysis_payload,
                timeout=120,
                headers={'Content-Type': 'application/json'}
            )
            analysis_result = analysis_response.json()
            
            if analysis_result.get('status') != 'success':
                return {
                    'error': 'Analysis failed', 
                    'details': analysis_result,
                    'status': 'error'
                }
            
        except requests.exceptions.RequestException as e:
            return {
                'error': f'Network error in analysis: {str(e)}',
                'status': 'error'
            }
        
        # Return complete results with metadata
        return {
            'transcription': speech_result['transcription'],
            'confidence': speech_result['confidence'],
            'word_count': speech_result.get('word_count', 0),
            'analysis': analysis_result['analysis'],
            'question': question,
            'processing_time': time.time(),
            'model_info': {
                'speech_model': 'Speech-to-Text API',
                'analysis_model': analysis_result.get('model_used', 'Gemini')
            },
            'status': 'complete'
        }
        
    except Exception as e:
        import traceback
        return {
            'error': f'Orchestration error: {str(e)}',
            'traceback': traceback.format_exc(),
            'status': 'error'
        }