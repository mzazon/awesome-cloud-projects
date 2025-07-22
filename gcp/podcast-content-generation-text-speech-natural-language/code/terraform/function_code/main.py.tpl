"""
Cloud Function for Podcast Content Generation
Analyzes text content using Natural Language API and generates speech using Text-to-Speech API
"""

import json
import os
import base64
from google.cloud import language_v1
from google.cloud import texttospeech
from google.cloud import storage
from flask import Flask, request
import functions_framework

# Initialize clients (these are cached across invocations)
language_client = language_v1.LanguageServiceClient()
tts_client = texttospeech.TextToSpeechClient()
storage_client = storage.Client()

@functions_framework.http
def analyze_and_generate(request):
    """Cloud Function to analyze text and generate podcast audio"""
    
    try:
        # Handle CORS preflight requests
        if request.method == 'OPTIONS':
            headers = {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'POST',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Max-Age': '3600'
            }
            return ('', 204, headers)
        
        # Set CORS headers for the main request
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Content-Type': 'application/json'
        }
        
        # Parse request data
        request_json = request.get_json(silent=True)
        if not request_json:
            return ({'error': 'No JSON data provided'}, 400, headers)
        
        bucket_name = request_json.get('bucket_name', '${bucket_name}')
        file_name = request_json.get('file_name')
        
        if not file_name:
            return ({'error': 'file_name parameter is required'}, 400, headers)
        
        # Download text content from Cloud Storage
        try:
            bucket = storage_client.bucket(bucket_name)
            blob = bucket.blob(f"input/{file_name}")
            
            if not blob.exists():
                return ({'error': f'File {file_name} not found in input folder'}, 404, headers)
                
            text_content = blob.download_as_text()
        except Exception as e:
            return ({'error': f'Failed to download file: {str(e)}'}, 500, headers)
        
        # Analyze sentiment and entities using Natural Language API
        document = language_v1.Document(
            content=text_content,
            type_=language_v1.Document.Type.PLAIN_TEXT
        )
        
        try:
            # Perform sentiment analysis
            sentiment_response = language_client.analyze_sentiment(
                request={"document": document}
            )
            
            # Extract entities
            entities_response = language_client.analyze_entities(
                request={"document": document}
            )
        except Exception as e:
            return ({'error': f'Natural Language API error: {str(e)}'}, 500, headers)
        
        # Generate SSML based on analysis
        ssml_content = create_ssml_from_analysis(
            text_content, 
            sentiment_response.document_sentiment,
            entities_response.entities
        )
        
        # Configure voice based on sentiment
        voice_config = configure_voice_for_sentiment(
            sentiment_response.document_sentiment.score
        )
        
        try:
            # Generate speech using Text-to-Speech API
            synthesis_input = texttospeech.SynthesisInput(ssml=ssml_content)
            response = tts_client.synthesize_speech(
                input=synthesis_input,
                voice=voice_config,
                audio_config=texttospeech.AudioConfig(
                    audio_encoding=texttospeech.AudioEncoding.MP3,
                    speaking_rate=1.0,
                    pitch=0.0
                )
            )
        except Exception as e:
            return ({'error': f'Text-to-Speech API error: {str(e)}'}, 500, headers)
        
        # Save audio file to Cloud Storage
        try:
            audio_blob = bucket.blob(f"audio/{file_name.replace('.txt', '.mp3')}")
            audio_blob.upload_from_string(response.audio_content, content_type='audio/mpeg')
        except Exception as e:
            return ({'error': f'Failed to save audio file: {str(e)}'}, 500, headers)
        
        # Save analysis metadata
        metadata = {
            "file_name": file_name,
            "sentiment_score": sentiment_response.document_sentiment.score,
            "sentiment_magnitude": sentiment_response.document_sentiment.magnitude,
            "entities": [
                {
                    "name": entity.name, 
                    "type": entity.type_.name,
                    "salience": entity.salience
                } 
                for entity in entities_response.entities[:10]  # Top 10 entities
            ],
            "processing_timestamp": os.environ.get('TIMESTAMP'),
            "audio_file": f"audio/{file_name.replace('.txt', '.mp3')}",
            "voice_config": {
                "language_code": voice_config.language_code,
                "name": voice_config.name,
                "gender": voice_config.ssml_gender.name
            },
            "text_length": len(text_content),
            "ssml_enhanced": True
        }
        
        try:
            metadata_blob = bucket.blob(f"processed/{file_name.replace('.txt', '_analysis.json')}")
            metadata_blob.upload_from_string(
                json.dumps(metadata, indent=2),
                content_type='application/json'
            )
        except Exception as e:
            return ({'error': f'Failed to save metadata: {str(e)}'}, 500, headers)
        
        # Return success response
        response_data = {
            "status": "success", 
            "metadata": metadata,
            "message": f"Successfully processed {file_name} and generated podcast audio"
        }
        
        return (response_data, 200, headers)
        
    except Exception as e:
        # Handle any unexpected errors
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Content-Type': 'application/json'
        }
        return ({'error': f'Unexpected error: {str(e)}'}, 500, headers)


def create_ssml_from_analysis(text, sentiment, entities):
    """Create SSML markup based on content analysis"""
    
    # Base SSML structure with opening tags
    ssml = '<speak>'
    
    # Add intro pause for podcast-style delivery
    ssml += '<break time="1s"/>'
    
    # Adjust speaking rate and emphasis based on sentiment
    if sentiment.score > 0.25:
        # Positive content - more energetic delivery
        ssml += '<prosody rate="105%" pitch="+2st" volume="medium">'
    elif sentiment.score < -0.25:
        # Negative content - more serious, slower delivery
        ssml += '<prosody rate="95%" pitch="-1st" volume="soft">'
    else:
        # Neutral content - balanced delivery
        ssml += '<prosody rate="100%" pitch="0st" volume="medium">'
    
    # Process text with intelligent emphasis for entities
    processed_text = text
    
    # Emphasize important entities (people, organizations, locations)
    for entity in entities:
        if entity.type_.name in ['PERSON', 'ORGANIZATION', 'LOCATION'] and entity.salience > 0.1:
            emphasis_level = "strong" if entity.salience > 0.3 else "moderate"
            processed_text = processed_text.replace(
                entity.name, 
                f'<emphasis level="{emphasis_level}">{entity.name}</emphasis>'
            )
    
    # Add breathing pauses at sentence boundaries for natural delivery
    processed_text = processed_text.replace('. ', '.<break time="0.5s"/> ')
    processed_text = processed_text.replace('! ', '!<break time="0.7s"/> ')
    processed_text = processed_text.replace('? ', '?<break time="0.7s"/> ')
    
    # Add paragraph-level pauses
    processed_text = processed_text.replace('\n\n', '<break time="1.5s"/>')
    
    # Handle special punctuation
    processed_text = processed_text.replace('...', '<break time="0.8s"/>')
    processed_text = processed_text.replace(' -- ', '<break time="0.3s"/> -- <break time="0.3s"/>')
    
    # Add the processed text and close tags
    ssml += processed_text
    ssml += '</prosody><break time="1s"/></speak>'
    
    return ssml


def configure_voice_for_sentiment(sentiment_score):
    """Configure voice characteristics based on sentiment analysis"""
    
    if sentiment_score > 0.25:
        # Positive content - use more energetic female voice
        return texttospeech.VoiceSelectionParams(
            language_code="en-US",
            name="en-US-Neural2-C",
            ssml_gender=texttospeech.SsmlVoiceGender.FEMALE
        )
    elif sentiment_score < -0.25:
        # Negative content - use more serious male voice
        return texttospeech.VoiceSelectionParams(
            language_code="en-US",
            name="en-US-Neural2-D",
            ssml_gender=texttospeech.SsmlVoiceGender.MALE
        )
    else:
        # Neutral content - use balanced female voice
        return texttospeech.VoiceSelectionParams(
            language_code="en-US",
            name="en-US-Neural2-A",
            ssml_gender=texttospeech.SsmlVoiceGender.FEMALE
        )


# Health check endpoint for monitoring
@functions_framework.http
def health_check(request):
    """Simple health check endpoint"""
    return {"status": "healthy", "service": "podcast-generator"}


# Entry point for Cloud Functions
if __name__ == "__main__":
    # For local testing
    from flask import Flask
    app = Flask(__name__)
    app.add_url_rule('/', 'analyze_and_generate', analyze_and_generate, methods=['POST', 'OPTIONS'])
    app.add_url_rule('/health', 'health_check', health_check, methods=['GET'])
    app.run(host='0.0.0.0', port=8080, debug=True)