import functions_framework
import json
import os
from google.cloud import aiplatform
from google.cloud import texttospeech
from google.cloud import firestore
from google.cloud import storage
import vertexai
from vertexai.generative_models import GenerativeModel

# Initialize clients
db = firestore.Client()
tts_client = texttospeech.TextToSpeechClient()
storage_client = storage.Client()

@functions_framework.http
def generate_content(request):
    """Generate educational content from curriculum outline."""
    
    # Parse request
    request_json = request.get_json()
    outline = request_json.get('outline', '')
    topic = request_json.get('topic', 'Educational Content')
    voice_name = request_json.get('voice_name', 'en-US-Studio-M')
    
    if not outline:
        return {'error': 'Curriculum outline is required'}, 400
    
    try:
        # Initialize Vertex AI
        vertexai.init(project="${project_id}")
        model = GenerativeModel('gemini-2.5-flash')
        
        # Generate educational content using Gemini
        prompt = f"""
        Create comprehensive educational content based on this curriculum outline:
        
        {outline}
        
        Generate:
        1. A detailed lesson plan (200-300 words)
        2. Key learning objectives (3-5 bullet points)
        3. Explanatory content suitable for audio narration (400-500 words)
        4. Practice questions (3-5 questions)
        
        Format the response as structured, educational content that flows naturally when read aloud.
        Focus on clarity, engagement, and pedagogical best practices.
        """
        
        response = model.generate_content(prompt)
        generated_content = response.text
        
        # Store content in Firestore
        doc_ref = db.collection('educational_content').add({
            'topic': topic,
            'outline': outline,
            'generated_content': generated_content,
            'timestamp': firestore.SERVER_TIMESTAMP,
            'status': 'content_generated'
        })[1]
        
        # Generate audio using Text-to-Speech
        synthesis_input = texttospeech.SynthesisInput(text=generated_content)
        voice = texttospeech.VoiceSelectionParams(
            language_code='en-US',
            name=voice_name
        )
        audio_config = texttospeech.AudioConfig(
            audio_encoding=texttospeech.AudioEncoding.MP3,
            speaking_rate=0.9,
            pitch=0.0
        )
        
        tts_response = tts_client.synthesize_speech(
            input=synthesis_input,
            voice=voice,
            audio_config=audio_config
        )
        
        # Upload audio to Cloud Storage
        bucket_name = "${bucket_name}"
        bucket = storage_client.bucket(bucket_name)
        audio_filename = f"lessons/{doc_ref.id}.mp3"
        blob = bucket.blob(audio_filename)
        blob.upload_from_string(tts_response.audio_content, content_type='audio/mpeg')
        
        # Update Firestore with audio URL
        doc_ref.update({
            'audio_url': f"gs://{bucket_name}/{audio_filename}",
            'status': 'completed'
        })
        
        return {
            'status': 'success',
            'document_id': doc_ref.id,
            'content_preview': generated_content[:200] + '...',
            'audio_url': f"gs://{bucket_name}/{audio_filename}"
        }
        
    except Exception as e:
        return {'error': str(e)}, 500