# Multi-Language Customer Support Automation - Cloud Function
# This function orchestrates Google Cloud AI services to process customer audio
# through speech-to-text, sentiment analysis, translation, and text-to-speech

import functions_framework
import json
import logging
import os
import base64
import datetime
from typing import Dict, Any, Optional

# Google Cloud client libraries
from google.cloud import speech
from google.cloud import translate_v2 as translate
from google.cloud import language_v1
from google.cloud import texttospeech
from google.cloud import firestore
from google.cloud import storage

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Google Cloud clients
try:
    speech_client = speech.SpeechClient()
    translate_client = translate.Client()
    language_client = language_v1.LanguageServiceClient()
    tts_client = texttospeech.TextToSpeechClient()
    db = firestore.Client()
    storage_client = storage.Client()
    logger.info("Successfully initialized Google Cloud clients")
except Exception as e:
    logger.error(f"Failed to initialize Google Cloud clients: {str(e)}")
    raise

# Environment variables
BUCKET_NAME = os.environ.get('BUCKET_NAME', '${bucket_name}')
PROJECT_ID = os.environ.get('PROJECT_ID', 'default-project')
FIRESTORE_DATABASE = os.environ.get('FIRESTORE_DATABASE', '(default)')

# Language mappings for voice selection
VOICE_MAPPING = {
    'en': {
        'language_code': 'en-US',
        'name': 'en-US-Neural2-J',
        'ssml_gender': texttospeech.SsmlVoiceGender.FEMALE
    },
    'es': {
        'language_code': 'es-ES',
        'name': 'es-ES-Neural2-F',
        'ssml_gender': texttospeech.SsmlVoiceGender.FEMALE
    },
    'fr': {
        'language_code': 'fr-FR',
        'name': 'fr-FR-Neural2-C',
        'ssml_gender': texttospeech.SsmlVoiceGender.FEMALE
    },
    'de': {
        'language_code': 'de-DE',
        'name': 'de-DE-Neural2-F',
        'ssml_gender': texttospeech.SsmlVoiceGender.FEMALE
    },
    'it': {
        'language_code': 'it-IT',
        'name': 'it-IT-Neural2-A',
        'ssml_gender': texttospeech.SsmlVoiceGender.FEMALE
    },
    'pt': {
        'language_code': 'pt-BR',
        'name': 'pt-BR-Neural2-C',
        'ssml_gender': texttospeech.SsmlVoiceGender.FEMALE
    },
    'ja': {
        'language_code': 'ja-JP',
        'name': 'ja-JP-Neural2-B',
        'ssml_gender': texttospeech.SsmlVoiceGender.FEMALE
    },
    'ko': {
        'language_code': 'ko-KR',
        'name': 'ko-KR-Neural2-A',
        'ssml_gender': texttospeech.SsmlVoiceGender.FEMALE
    },
    'zh': {
        'language_code': 'cmn-CN',
        'name': 'cmn-CN-Standard-A',
        'ssml_gender': texttospeech.SsmlVoiceGender.FEMALE
    }
}

def extract_language_code(full_code: str) -> str:
    """Extract the primary language code from a full language code (e.g., 'en' from 'en-US')."""
    return full_code.split('-')[0].lower()

def detect_speech_language(audio_data: bytes) -> tuple[str, str]:
    """
    Detect the language of the speech using Google Cloud Speech-to-Text.
    
    Args:
        audio_data: The audio data in bytes
        
    Returns:
        Tuple of (transcript, detected_language_code)
    """
    try:
        audio = speech.RecognitionAudio(content=audio_data)
        config = speech.RecognitionConfig(
            encoding=speech.RecognitionConfig.AudioEncoding.WEBM_OPUS,
            sample_rate_hertz=48000,
            language_code="en-US",  # Primary language
            alternative_language_codes=[
                "es-ES", "fr-FR", "de-DE", "it-IT", "pt-BR", 
                "ja-JP", "ko-KR", "zh-CN"
            ],
            enable_automatic_punctuation=True,
            enable_word_time_offsets=True,
            enable_speaker_diarization=True,
            diarization_config=speech.SpeakerDiarizationConfig(
                enable_speaker_diarization=True,
                min_speaker_count=1,
                max_speaker_count=2,
            ),
            model="latest_long"
        )
        
        response = speech_client.recognize(config=config, audio=audio)
        
        if not response.results:
            logger.warning("No speech detected in audio")
            return "", "en-US"
        
        result = response.results[0]
        transcript = result.alternatives[0].transcript
        detected_language = result.language_code if hasattr(result, 'language_code') else "en-US"
        
        logger.info(f"Speech detected: '{transcript[:50]}...', Language: {detected_language}")
        return transcript, detected_language
        
    except Exception as e:
        logger.error(f"Error in speech recognition: {str(e)}")
        raise

def analyze_sentiment(text: str) -> dict:
    """
    Analyze sentiment and extract entities from text using Cloud Natural Language.
    
    Args:
        text: The text to analyze
        
    Returns:
        Dictionary with sentiment scores and entities
    """
    try:
        document = language_v1.Document(
            content=text,
            type_=language_v1.Document.Type.PLAIN_TEXT
        )
        
        # Analyze sentiment
        sentiment_response = language_client.analyze_sentiment(
            request={'document': document}
        )
        
        # Extract entities
        entities_response = language_client.analyze_entities(
            request={'document': document}
        )
        
        sentiment_score = sentiment_response.document_sentiment.score
        sentiment_magnitude = sentiment_response.document_sentiment.magnitude
        
        entities = []
        for entity in entities_response.entities:
            entities.append({
                'name': entity.name,
                'type': entity.type_.name,
                'salience': entity.salience
            })
        
        logger.info(f"Sentiment analysis: score={sentiment_score:.3f}, magnitude={sentiment_magnitude:.3f}")
        
        return {
            'sentiment_score': sentiment_score,
            'sentiment_magnitude': sentiment_magnitude,
            'entities': entities
        }
        
    except Exception as e:
        logger.error(f"Error in sentiment analysis: {str(e)}")
        raise

def translate_text(text: str, target_language: str, source_language: str = None) -> str:
    """
    Translate text using Cloud Translation.
    
    Args:
        text: Text to translate
        target_language: Target language code
        source_language: Source language code (auto-detect if None)
        
    Returns:
        Translated text
    """
    try:
        if source_language:
            result = translate_client.translate(
                text,
                target_language=target_language,
                source_language=source_language
            )
        else:
            result = translate_client.translate(
                text,
                target_language=target_language
            )
        
        translated_text = result['translatedText']
        detected_source = result.get('detectedSourceLanguage', source_language)
        
        logger.info(f"Translation: {detected_source} -> {target_language}")
        return translated_text
        
    except Exception as e:
        logger.error(f"Error in translation: {str(e)}")
        return text  # Return original text if translation fails

def generate_response_text(sentiment_score: float, entities: list) -> str:
    """
    Generate appropriate response text based on sentiment analysis.
    
    Args:
        sentiment_score: Sentiment score from -1.0 to 1.0
        entities: List of extracted entities
        
    Returns:
        Response text
    """
    # Extract entity names for personalization
    person_names = [entity['name'] for entity in entities if entity['type'] == 'PERSON']
    products = [entity['name'] for entity in entities if entity['type'] == 'CONSUMER_GOOD']
    
    # Personalization prefix
    greeting = ""
    if person_names:
        greeting = f"Hello {person_names[0]}, "
    
    # Sentiment-based responses
    if sentiment_score < -0.5:
        response = f"{greeting}I understand you're experiencing significant frustration. Let me escalate this to our priority support team to resolve this issue immediately."
    elif sentiment_score < -0.2:
        response = f"{greeting}I can see you're having some concerns. Let me help you resolve this issue as quickly as possible."
    elif sentiment_score > 0.5:
        response = f"{greeting}Thank you for your positive feedback! I'm delighted to help you further. How else can I assist you today?"
    elif sentiment_score > 0.2:
        response = f"{greeting}I'm glad to help you with this. What specific assistance do you need?"
    else:
        response = f"{greeting}I understand your inquiry. Let me provide you with the support you need."
    
    # Add product-specific context if available
    if products:
        response += f" Regarding your {products[0]} inquiry, I'll make sure we address all your questions."
    
    return response

def synthesize_speech(text: str, language_code: str) -> bytes:
    """
    Convert text to speech using Cloud Text-to-Speech.
    
    Args:
        text: Text to convert to speech
        language_code: Language code for voice selection
        
    Returns:
        Audio content as bytes
    """
    try:
        # Extract primary language for voice mapping
        primary_lang = extract_language_code(language_code)
        voice_config = VOICE_MAPPING.get(primary_lang, VOICE_MAPPING['en'])
        
        synthesis_input = texttospeech.SynthesisInput(text=text)
        
        voice = texttospeech.VoiceSelectionParams(
            language_code=voice_config['language_code'],
            name=voice_config['name'],
            ssml_gender=voice_config['ssml_gender']
        )
        
        audio_config = texttospeech.AudioConfig(
            audio_encoding=texttospeech.AudioEncoding.MP3,
            speaking_rate=1.0,
            pitch=0.0
        )
        
        response = tts_client.synthesize_speech(
            input=synthesis_input,
            voice=voice,
            audio_config=audio_config
        )
        
        logger.info(f"Generated speech for language: {language_code}")
        return response.audio_content
        
    except Exception as e:
        logger.error(f"Error in text-to-speech: {str(e)}")
        raise

def store_conversation(customer_id: str, session_id: str, conversation_data: dict) -> None:
    """
    Store conversation data in Firestore.
    
    Args:
        customer_id: Customer identifier
        session_id: Session identifier
        conversation_data: Dictionary with conversation details
    """
    try:
        doc_ref = db.collection('conversations').document()
        
        conversation_record = {
            'customer_id': customer_id,
            'session_id': session_id,
            'timestamp': datetime.datetime.utcnow(),
            'processed': True,
            **conversation_data
        }
        
        doc_ref.set(conversation_record)
        logger.info(f"Stored conversation for customer: {customer_id}, session: {session_id}")
        
    except Exception as e:
        logger.error(f"Error storing conversation: {str(e)}")
        # Don't raise - conversation storage failure shouldn't break the pipeline

@functions_framework.http
def process_customer_audio(request) -> tuple[dict, int]:
    """
    Main Cloud Function entry point for processing customer audio.
    
    Args:
        request: HTTP request object
        
    Returns:
        Tuple of (response_dict, status_code)
    """
    try:
        # Enable CORS
        if request.method == 'OPTIONS':
            headers = {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'POST',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Max-Age': '3600'
            }
            return ('', 204, headers)
        
        # Parse request JSON
        request_json = request.get_json(silent=True)
        if not request_json:
            logger.error("No JSON data in request")
            return {'error': 'Invalid JSON data'}, 400
        
        # Extract required fields
        audio_data_b64 = request_json.get('audio_data')
        customer_id = request_json.get('customer_id', 'anonymous')
        session_id = request_json.get('session_id', f'session-{datetime.datetime.utcnow().isoformat()}')
        
        if not audio_data_b64:
            logger.error("No audio_data provided in request")
            return {'error': 'audio_data is required'}, 400
        
        # Decode audio data
        try:
            audio_data = base64.b64decode(audio_data_b64)
        except Exception as e:
            logger.error(f"Failed to decode audio data: {str(e)}")
            return {'error': 'Invalid base64 audio data'}, 400
        
        logger.info(f"Processing audio for customer: {customer_id}, session: {session_id}")
        
        # Step 1: Speech-to-Text with language detection
        transcript, detected_language = detect_speech_language(audio_data)
        
        if not transcript:
            return {'error': 'No speech detected in audio'}, 400
        
        # Step 2: Sentiment Analysis
        sentiment_analysis = analyze_sentiment(transcript)
        
        # Step 3: Translation to English (if needed)
        primary_lang = extract_language_code(detected_language)
        if primary_lang != 'en':
            translated_text = translate_text(transcript, 'en', primary_lang)
        else:
            translated_text = transcript
        
        # Step 4: Generate response based on sentiment and entities
        response_text = generate_response_text(
            sentiment_analysis['sentiment_score'],
            sentiment_analysis['entities']
        )
        
        # Step 5: Translate response back to customer language (if needed)
        if primary_lang != 'en':
            final_response = translate_text(response_text, primary_lang, 'en')
        else:
            final_response = response_text
        
        # Step 6: Text-to-Speech
        audio_response = synthesize_speech(final_response, detected_language)
        
        # Step 7: Store conversation in Firestore
        conversation_data = {
            'original_text': transcript,
            'detected_language': detected_language,
            'translated_text': translated_text,
            'sentiment_score': sentiment_analysis['sentiment_score'],
            'sentiment_magnitude': sentiment_analysis['sentiment_magnitude'],
            'entities': sentiment_analysis['entities'],
            'response_text': final_response,
        }
        
        store_conversation(customer_id, session_id, conversation_data)
        
        # Log metrics for monitoring
        logger.info(json.dumps({
            'customer_id': customer_id,
            'session_id': session_id,
            'detected_language': detected_language,
            'sentiment_score': sentiment_analysis['sentiment_score'],
            'sentiment_magnitude': sentiment_analysis['sentiment_magnitude'],
            'entity_count': len(sentiment_analysis['entities']),
            'transcript_length': len(transcript),
            'response_length': len(final_response)
        }))
        
        # Prepare response
        response_data = {
            'transcript': transcript,
            'detected_language': detected_language,
            'sentiment_score': sentiment_analysis['sentiment_score'],
            'sentiment_magnitude': sentiment_analysis['sentiment_magnitude'],
            'entities': sentiment_analysis['entities'],
            'response_text': final_response,
            'audio_response': base64.b64encode(audio_response).decode('utf-8'),
            'session_id': session_id,
            'timestamp': datetime.datetime.utcnow().isoformat()
        }
        
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Content-Type': 'application/json'
        }
        
        return (response_data, 200, headers)
        
    except Exception as e:
        logger.error(f"Error processing customer audio: {str(e)}", exc_info=True)
        
        error_response = {
            'error': 'Internal server error',
            'details': str(e) if os.environ.get('DEBUG') == 'true' else 'Contact support',
            'timestamp': datetime.datetime.utcnow().isoformat()
        }
        
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Content-Type': 'application/json'
        }
        
        return (error_response, 500, headers)

# Health check endpoint
@functions_framework.http
def health_check(request) -> tuple[dict, int]:
    """
    Simple health check endpoint for monitoring.
    
    Args:
        request: HTTP request object
        
    Returns:
        Tuple of (response_dict, status_code)
    """
    try:
        # Test basic client connectivity
        _ = db.collection('health').limit(1).get()
        
        health_data = {
            'status': 'healthy',
            'timestamp': datetime.datetime.utcnow().isoformat(),
            'services': {
                'speech': 'available',
                'translation': 'available',
                'natural_language': 'available',
                'text_to_speech': 'available',
                'firestore': 'available'
            }
        }
        
        return (health_data, 200)
        
    except Exception as e:
        logger.error(f"Health check failed: {str(e)}")
        
        health_data = {
            'status': 'unhealthy',
            'timestamp': datetime.datetime.utcnow().isoformat(),
            'error': str(e)
        }
        
        return (health_data, 503)