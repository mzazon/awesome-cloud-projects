import json
import os
import time
from google.cloud import speech
from google.cloud import workflows_v1
from google.cloud import tasks_v2
from google.cloud import storage
import functions_framework

@functions_framework.http
def process_voice_command(request):
    """Process uploaded audio file and trigger workflows"""
    try:
        # Get request data
        data = request.get_json()
        if not data:
            return {'error': 'No data provided'}, 400
        
        # Handle test mode for development
        if data.get('test_mode'):
            return handle_test_mode(data)
        
        # Validate required parameters
        if 'audio_uri' not in data:
            return {'error': 'Missing audio_uri parameter'}, 400
        
        audio_uri = data['audio_uri']
        
        # Initialize Speech-to-Text client
        speech_client = speech.SpeechClient()
        
        # Configure speech recognition
        config = speech.RecognitionConfig(
            encoding=speech.RecognitionConfig.AudioEncoding.LINEAR16,
            sample_rate_hertz=16000,
            language_code="${language_code}",
            enable_automatic_punctuation=True,
            model="${speech_model}",
            use_enhanced=True
        )
        
        audio = speech.RecognitionAudio(uri=audio_uri)
        
        # Perform speech recognition
        response = speech_client.recognize(config=config, audio=audio)
        
        if not response.results:
            return {'error': 'No speech detected in audio'}, 400
        
        # Extract transcript and confidence
        transcript = response.results[0].alternatives[0].transcript.lower()
        confidence = response.results[0].alternatives[0].confidence
        
        # Validate confidence threshold
        if confidence < 0.7:
            return {
                'error': 'Low confidence in speech recognition',
                'transcript': transcript,
                'confidence': confidence
            }, 400
        
        # Analyze intent from transcript
        intent_data = analyze_intent(transcript)
        
        # Trigger workflow if intent is recognized
        if intent_data['intent'] != 'unknown':
            workflow_result = trigger_workflow(intent_data)
            return {
                'transcript': transcript,
                'confidence': confidence,
                'intent': intent_data,
                'workflow_triggered': workflow_result,
                'timestamp': time.time()
            }
        else:
            return {
                'transcript': transcript,
                'confidence': confidence,
                'error': 'Intent not recognized',
                'available_intents': ['create_task', 'schedule_task', 'generate_report']
            }, 400
            
    except Exception as e:
        return {
            'error': f'Processing failed: {str(e)}',
            'timestamp': time.time()
        }, 500

def handle_test_mode(data):
    """Handle test mode requests for development"""
    test_command = data.get('text_command', 'create task test')
    
    # Simulate speech recognition results
    intent_data = analyze_intent(test_command.lower())
    
    if intent_data['intent'] != 'unknown':
        workflow_result = trigger_workflow(intent_data)
        return {
            'transcript': test_command,
            'confidence': 1.0,
            'intent': intent_data,
            'workflow_triggered': workflow_result,
            'test_mode': True,
            'timestamp': time.time()
        }
    else:
        return {
            'transcript': test_command,
            'confidence': 1.0,
            'error': 'Intent not recognized in test mode',
            'available_intents': ['create_task', 'schedule_task', 'generate_report'],
            'test_mode': True
        }, 400

def analyze_intent(transcript):
    """Advanced intent recognition from transcript"""
    intent_data = {
        'intent': 'unknown',
        'action': None,
        'parameters': {},
        'confidence': 0.0
    }
    
    # Task creation intents
    if any(phrase in transcript for phrase in ['create task', 'new task', 'add task', 'make task']):
        intent_data['intent'] = 'create_task'
        intent_data['action'] = 'task_creation'
        intent_data['confidence'] = 0.9
        
        # Extract task parameters
        if 'urgent' in transcript or 'priority' in transcript or 'important' in transcript:
            intent_data['parameters']['priority'] = 'high'
        elif 'low priority' in transcript or 'when possible' in transcript:
            intent_data['parameters']['priority'] = 'low'
        else:
            intent_data['parameters']['priority'] = 'normal'
        
        # Extract category
        if 'meeting' in transcript:
            intent_data['parameters']['category'] = 'meeting'
        elif 'email' in transcript:
            intent_data['parameters']['category'] = 'email'
        elif 'call' in transcript or 'phone' in transcript:
            intent_data['parameters']['category'] = 'call'
        elif 'document' in transcript or 'report' in transcript:
            intent_data['parameters']['category'] = 'document'
        else:
            intent_data['parameters']['category'] = 'general'
        
        # Extract description
        intent_data['parameters']['description'] = transcript
    
    # Scheduling intents
    elif any(phrase in transcript for phrase in ['schedule', 'remind me', 'set reminder']):
        intent_data['intent'] = 'schedule_task'
        intent_data['action'] = 'task_scheduling'
        intent_data['confidence'] = 0.8
        
        # Extract timing (simplified)
        if 'tomorrow' in transcript:
            intent_data['parameters']['schedule_time'] = 'tomorrow'
        elif 'next week' in transcript:
            intent_data['parameters']['schedule_time'] = 'next_week'
        elif 'hour' in transcript:
            intent_data['parameters']['schedule_time'] = 'one_hour'
        else:
            intent_data['parameters']['schedule_time'] = 'default'
        
        intent_data['parameters']['description'] = transcript
    
    # Report generation intents
    elif any(phrase in transcript for phrase in ['report', 'status', 'summary', 'generate']):
        intent_data['intent'] = 'generate_report'
        intent_data['action'] = 'report_generation'
        intent_data['confidence'] = 0.7
        
        # Extract report type
        if 'daily' in transcript:
            intent_data['parameters']['report_type'] = 'daily'
        elif 'weekly' in transcript:
            intent_data['parameters']['report_type'] = 'weekly'
        elif 'task' in transcript:
            intent_data['parameters']['report_type'] = 'task_status'
        else:
            intent_data['parameters']['report_type'] = 'general'
        
        intent_data['parameters']['description'] = transcript
    
    return intent_data

def trigger_workflow(intent_data):
    """Trigger Cloud Workflow based on intent"""
    try:
        project_id = "${project_id}"
        location = "${region}"
        workflow_name = "${workflow_name}"
        
        # Initialize Workflows client
        workflows_client = workflows_v1.ExecutionsClient()
        
        # Prepare workflow execution
        parent = f"projects/{project_id}/locations/{location}/workflows/{workflow_name}"
        execution = {
            "argument": json.dumps(intent_data)
        }
        
        # Execute workflow
        operation = workflows_client.create_execution(
            parent=parent,
            execution=execution
        )
        
        return {
            'status': 'triggered',
            'execution_name': operation.name,
            'workflow_name': workflow_name
        }
        
    except Exception as e:
        return {
            'status': 'failed',
            'error': str(e)
        }