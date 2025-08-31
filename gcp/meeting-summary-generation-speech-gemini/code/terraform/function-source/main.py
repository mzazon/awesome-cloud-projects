"""
Meeting Summary Generation Cloud Function
Processes uploaded audio files using Speech-to-Text and Vertex AI Gemini
"""

import functions_framework
import json
import os
from google.cloud import speech
from google.cloud import storage
import vertexai
from vertexai.generative_models import GenerativeModel
import logging

# Initialize clients
storage_client = storage.Client()
speech_client = speech.SpeechClient()

# Initialize Vertex AI with configuration from Terraform variables
project_id = os.environ.get('GCP_PROJECT')
vertex_ai_location = os.environ.get('VERTEX_AI_LOCATION', '${vertex_ai_location}')
gemini_model_name = os.environ.get('GEMINI_MODEL', '${gemini_model}')
speech_language = os.environ.get('SPEECH_LANGUAGE', '${speech_language_code}')
speaker_count_min = int(os.environ.get('SPEAKER_COUNT_MIN', '${speaker_count_min}'))
speaker_count_max = int(os.environ.get('SPEAKER_COUNT_MAX', '${speaker_count_max}'))

# Initialize Vertex AI
vertexai.init(project=project_id, location=vertex_ai_location)
model = GenerativeModel(gemini_model_name)

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


@functions_framework.cloud_event
def process_meeting(cloud_event):
    """Process uploaded meeting audio file with comprehensive error handling"""
    try:
        # Get file information from Cloud Storage event
        event_data = cloud_event.data
        bucket_name = event_data.get('bucket')
        file_name = event_data.get('name')
        
        if not bucket_name or not file_name:
            logger.error("Missing bucket name or file name in event data")
            return
        
        # Skip non-audio files and folder markers
        if (not file_name.lower().endswith(('.wav', '.mp3', '.flac', '.m4a')) or 
            file_name.endswith('/.keep') or 
            file_name.startswith(('transcripts/', 'summaries/'))):
            logger.info(f"Skipping non-audio file or folder marker: {file_name}")
            return
        
        logger.info(f"Processing audio file: {file_name} from bucket: {bucket_name}")
        
        # Step 1: Transcribe audio using Speech-to-Text
        transcript = transcribe_audio(bucket_name, file_name)
        
        if not transcript:
            logger.error("Transcription failed or returned empty result")
            return
        
        # Step 2: Generate summary using Gemini
        summary = generate_meeting_summary(transcript, file_name)
        
        # Step 3: Save results to Cloud Storage
        save_results(bucket_name, file_name, transcript, summary)
        
        logger.info(f"Successfully processed meeting: {file_name}")
        
    except Exception as e:
        logger.error(f"Error processing meeting {file_name}: {str(e)}", exc_info=True)
        raise


def transcribe_audio(bucket_name, file_name):
    """Transcribe audio file using Speech-to-Text API with advanced features"""
    try:
        # Configure audio source
        audio = speech.RecognitionAudio(
            uri=f"gs://{bucket_name}/{file_name}"
        )
        
        # Configure recognition settings with Terraform variables
        config = speech.RecognitionConfig(
            encoding=speech.RecognitionConfig.AudioEncoding.ENCODING_UNSPECIFIED,
            sample_rate_hertz=16000,
            language_code=speech_language,
            enable_automatic_punctuation=True,
            enable_speaker_diarization=True,
            diarization_speaker_count_min=speaker_count_min,
            diarization_speaker_count_max=speaker_count_max,
            model="latest_long",
            use_enhanced=True,
            # Alternative language codes can be specified for multi-language detection
            alternative_language_codes=["en-GB", "es-US", "fr-FR"],
            profanity_filter=False,
            enable_word_time_offsets=True,
            enable_word_confidence=True,
        )
        
        logger.info(f"Starting transcription for {file_name} with language {speech_language}")
        
        # Perform long-running transcription
        operation = speech_client.long_running_recognize(
            config=config, audio=audio
        )
        
        logger.info("Waiting for Speech-to-Text operation to complete...")
        response = operation.result(timeout=600)  # 10 minute timeout
        
        # Extract transcript with speaker labels and confidence scores
        transcript_parts = []
        total_confidence = 0
        word_count = 0
        
        for result in response.results:
            alternative = result.alternatives[0]
            
            # Track overall confidence
            total_confidence += alternative.confidence
            
            # Process speaker diarization if available
            if hasattr(alternative, 'words') and alternative.words:
                current_speaker = None
                speaker_words = []
                
                for word_info in alternative.words:
                    word_count += 1
                    
                    if word_info.speaker_tag != current_speaker:
                        # Save previous speaker segment
                        if speaker_words:
                            segment = f"Speaker {current_speaker}: {' '.join(speaker_words)}"
                            transcript_parts.append(segment)
                        
                        # Start new speaker segment
                        current_speaker = word_info.speaker_tag
                        speaker_words = [word_info.word]
                    else:
                        speaker_words.append(word_info.word)
                
                # Add final speaker segment
                if speaker_words:
                    segment = f"Speaker {current_speaker}: {' '.join(speaker_words)}"
                    transcript_parts.append(segment)
            else:
                # Fallback for files without speaker diarization
                transcript_parts.append(f"Speaker: {alternative.transcript}")
        
        # Combine all transcript parts
        full_transcript = '\n\n'.join(transcript_parts)
        
        # Calculate average confidence
        avg_confidence = total_confidence / len(response.results) if response.results else 0
        
        # Add metadata to transcript
        metadata = f"""# Transcription Metadata
- File: {file_name}
- Language: {speech_language}
- Speakers: {speaker_count_min}-{speaker_count_max}
- Average Confidence: {avg_confidence:.2f}
- Word Count: {word_count}
- Model: latest_long

# Transcript
"""
        
        full_transcript_with_metadata = metadata + full_transcript
        
        logger.info(f"Transcription completed: {len(full_transcript)} characters, "
                   f"confidence: {avg_confidence:.2f}, words: {word_count}")
        
        return full_transcript_with_metadata
        
    except Exception as e:
        logger.error(f"Transcription error for {file_name}: {str(e)}", exc_info=True)
        return None


def generate_meeting_summary(transcript, file_name):
    """Generate structured meeting summary using Vertex AI Gemini"""
    try:
        # Construct comprehensive prompt for Gemini
        prompt = f"""
You are an expert meeting analyst. Please analyze this meeting transcript and create a comprehensive, structured summary.

**Meeting Information:**
- File: {file_name}
- Processing Date: {os.environ.get('FUNCTION_EXECUTION_ID', 'Unknown')}

**Instructions:**
1. Create a professional summary following the exact structure below
2. Extract specific, actionable information
3. Identify speakers by their roles when possible
4. Use bullet points for clarity
5. Be concise but comprehensive

**Required Structure:**

## Meeting Summary for: {file_name}

### Executive Summary
[2-3 sentence overview of the meeting purpose and key outcomes]

### Key Topics Discussed
- [List main topics with brief descriptions]
- [Include any technical discussions or decisions]
- [Note any challenges or issues raised]

### Important Decisions Made
- [List specific decisions with context]
- [Include rationale when mentioned]
- [Note any pending decisions]

### Action Items
- [Specific task] - Assigned to: [Person/Team] - Due: [Date/Timeframe]
- [Include all actionable items with clear ownership]
- [Note any dependencies between tasks]

### Key Insights and Concerns
- [Important insights shared during the meeting]
- [Risks, challenges, or concerns raised]
- [Opportunities or positive developments]

### Next Steps
- [Immediate follow-up actions]
- [Future meetings or milestones]
- [Communication plans]

### Meeting Participants
[If identifiable from transcript, list key participants and roles]

### Additional Notes
[Any other relevant information that doesn't fit above categories]

**Transcript to Analyze:**
{transcript}

Please format your response in clean markdown with the exact section headers shown above.
Be professional, accurate, and focus on actionable information.
"""
        
        logger.info(f"Generating summary for {file_name} using {gemini_model_name}")
        
        # Generate content using Gemini
        generation_config = {
            "max_output_tokens": 8192,
            "temperature": 0.2,  # Lower temperature for more consistent output
            "top_p": 0.8,
            "top_k": 40
        }
        
        response = model.generate_content(
            prompt,
            generation_config=generation_config,
        )
        
        if not response or not response.text:
            logger.error("Gemini returned empty response")
            return generate_fallback_summary(transcript, file_name)
        
        summary = response.text
        
        # Add generation metadata
        metadata_footer = f"""

---
*Generated by Vertex AI Gemini ({gemini_model_name}) on {vertex_ai_location}*
*Function: Meeting Summary Generation v1.1*
"""
        
        summary_with_metadata = summary + metadata_footer
        
        logger.info(f"Summary generated successfully: {len(summary)} characters")
        return summary_with_metadata
        
    except Exception as e:
        logger.error(f"Summary generation error for {file_name}: {str(e)}", exc_info=True)
        return generate_fallback_summary(transcript, file_name)


def generate_fallback_summary(transcript, file_name):
    """Generate a basic fallback summary if Gemini fails"""
    logger.info("Generating fallback summary")
    
    # Extract basic information from transcript
    lines = transcript.split('\n')
    speaker_count = len(set(line.split(':')[0] for line in lines if ':' in line))
    word_count = len(transcript.split())
    
    fallback_summary = f"""# Meeting Summary for: {file_name}

## Processing Information
- **Status**: Fallback summary generated due to AI processing error
- **Transcript Length**: {word_count} words
- **Estimated Speakers**: {speaker_count}
- **Processing Date**: {os.environ.get('FUNCTION_EXECUTION_ID', 'Unknown')}

## Raw Transcript Available
The complete transcript has been saved and is available for manual review.
Please check the transcripts folder for the full audio-to-text conversion.

## Next Steps
1. Review the raw transcript for detailed meeting content
2. Manually extract action items and decisions
3. Consider re-processing with updated AI models if available

## Technical Details
- **AI Model**: {gemini_model_name} (failed)
- **Speech Language**: {speech_language}
- **Function Version**: 1.1

---
*This is a fallback summary. For complete meeting details, please review the full transcript.*
"""
    
    return fallback_summary


def save_results(bucket_name, audio_file, transcript, summary):
    """Save transcription and summary results to Cloud Storage with error handling"""
    try:
        bucket = storage_client.bucket(bucket_name)
        
        # Generate clean filename base (remove extension and path)
        base_filename = os.path.splitext(os.path.basename(audio_file))[0]
        
        # Save full transcript with metadata
        transcript_filename = f"transcripts/{base_filename}_transcript.txt"
        transcript_blob = bucket.blob(transcript_filename)
        transcript_blob.upload_from_string(
            transcript,
            content_type='text/plain; charset=utf-8'
        )
        
        # Set metadata for transcript
        transcript_blob.metadata = {
            'source_file': audio_file,
            'processing_function': 'meeting-summary-generation',
            'content_type': 'transcript',
            'version': '1.1'
        }
        transcript_blob.patch()
        
        # Save meeting summary
        summary_filename = f"summaries/{base_filename}_summary.md"
        summary_blob = bucket.blob(summary_filename)
        summary_blob.upload_from_string(
            summary,
            content_type='text/markdown; charset=utf-8'
        )
        
        # Set metadata for summary
        summary_blob.metadata = {
            'source_file': audio_file,
            'processing_function': 'meeting-summary-generation',
            'content_type': 'summary',
            'ai_model': gemini_model_name,
            'version': '1.1'
        }
        summary_blob.patch()
        
        logger.info(f"Results saved successfully:")
        logger.info(f"  Transcript: gs://{bucket_name}/{transcript_filename}")
        logger.info(f"  Summary: gs://{bucket_name}/{summary_filename}")
        
    except Exception as e:
        logger.error(f"Error saving results for {audio_file}: {str(e)}", exc_info=True)
        raise


def health_check():
    """Health check function for monitoring"""
    try:
        # Test basic service connectivity
        storage_client.list_buckets(max_results=1)
        speech_client.list_phrase_sets(parent=f"projects/{project_id}/locations/global")
        
        return {
            'status': 'healthy',
            'project_id': project_id,
            'vertex_ai_location': vertex_ai_location,
            'gemini_model': gemini_model_name,
            'speech_language': speech_language
        }
    except Exception as e:
        logger.error(f"Health check failed: {str(e)}")
        return {
            'status': 'unhealthy',
            'error': str(e)
        }


# Optional HTTP endpoint for health checks (if needed)
@functions_framework.http
def health(request):
    """HTTP endpoint for health checks"""
    result = health_check()
    return json.dumps(result), 200 if result['status'] == 'healthy' else 500