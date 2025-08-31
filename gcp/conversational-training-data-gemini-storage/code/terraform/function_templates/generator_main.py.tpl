import json
import os
from google.cloud import storage
import vertexai
from vertexai.generative_models import GenerativeModel
import logging
import uuid
from typing import Dict, List
import random
import functions_framework

# Initialize logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@functions_framework.http
def generate_conversations(request):
    """Cloud Function to generate conversational training data using Gemini."""
    
    try:
        # Set CORS headers for browser compatibility
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type',
        }
        
        # Handle preflight request
        if request.method == 'OPTIONS':
            return ('', 204, headers)
            
        # Initialize Vertex AI
        project_id = os.getenv('GCP_PROJECT', os.getenv('GOOGLE_CLOUD_PROJECT'))
        region = os.getenv('FUNCTION_REGION', '${vertex_ai_region}')
        vertexai.init(project=project_id, location=region)
        
        # Initialize storage client
        storage_client = storage.Client()
        bucket_name = os.getenv('BUCKET_NAME', '${bucket_name}')
        bucket = storage_client.bucket(bucket_name)
        
        # Load conversation templates
        try:
            template_blob = bucket.blob('templates/conversation_templates.json')
            templates = json.loads(template_blob.download_as_text())
        except Exception as e:
            logger.error(f"Failed to load templates: {e}")
            return (json.dumps({'status': 'error', 'message': f'Failed to load templates: {e}'}), 500, headers)
        
        # Initialize Gemini model
        model = GenerativeModel("${gemini_model}")
        
        # Parse request parameters
        request_json = request.get_json(silent=True) or {}
        num_conversations = min(request_json.get('num_conversations', 10), 50)  # Limit to 50 for safety
        scenario = request_json.get('scenario', 'customer_support')
        
        # Find matching template
        template = next((t for t in templates['templates'] 
                        if t['scenario'] == scenario), templates['templates'][0])
        
        conversations = []
        
        for i in range(num_conversations):
            # Generate conversation prompt
            intent = random.choice(template['user_intents'])
            prompt = f"""
            Generate a realistic conversation between a user and an AI assistant for the following scenario:
            
            Context: {template['context']}
            User Intent: {intent}
            Conversation Length: {template['conversation_length']}
            Tone: {template['tone']}
            
            Format the conversation as a JSON object with the following structure:
            {{
                "conversation_id": "unique_id",
                "scenario": "{scenario}",
                "intent": "{intent}",
                "messages": [
                    {{"role": "user", "content": "user message"}},
                    {{"role": "assistant", "content": "assistant response"}},
                    ...
                ]
            }}
            
            Make the conversation natural, diverse, and realistic. Vary the language, 
            specific details, and conversation flow while maintaining the core intent and tone.
            Ensure the conversation has between 4-8 message exchanges total.
            """
            
            # Generate conversation using Gemini
            try:
                response = model.generate_content(
                    prompt,
                    generation_config={
                        "temperature": 0.8,
                        "top_p": 0.9,
                        "max_output_tokens": 1024
                    }
                )
                
                # Parse and store conversation
                response_text = response.text.strip()
                if response_text.startswith('```json'):
                    response_text = response_text[7:]
                if response_text.endswith('```'):
                    response_text = response_text[:-3]
                    
                conversation = json.loads(response_text.strip())
                conversation['conversation_id'] = str(uuid.uuid4())
                conversation['generated_timestamp'] = str(uuid.uuid1().time)
                conversation['generation_metadata'] = {
                    'model': '${gemini_model}',
                    'temperature': 0.8,
                    'region': region
                }
                conversations.append(conversation)
                
                logger.info(f"Generated conversation {i+1}/{num_conversations} for scenario: {scenario}")
                
            except json.JSONDecodeError as e:
                logger.warning(f"Failed to parse conversation {i+1}: {e}, skipping...")
                continue
            except Exception as e:
                logger.warning(f"Failed to generate conversation {i+1}: {e}, skipping...")
                continue
        
        # Save conversations to Cloud Storage
        output_file = f"raw-conversations/{scenario}_{uuid.uuid4()}.json"
        try:
            blob = bucket.blob(output_file)
            blob.upload_from_string(
                json.dumps({"conversations": conversations, "generation_metadata": {
                    "total_requested": num_conversations,
                    "total_generated": len(conversations),
                    "scenario": scenario,
                    "template_used": template,
                    "generation_timestamp": str(uuid.uuid1().time)
                }}, indent=2),
                content_type='application/json'
            )
        except Exception as e:
            logger.error(f"Failed to save conversations: {e}")
            return (json.dumps({'status': 'error', 'message': f'Failed to save conversations: {e}'}), 500, headers)
        
        result = {
            'status': 'success',
            'conversations_generated': len(conversations),
            'conversations_requested': num_conversations,
            'output_file': f"gs://{bucket_name}/{output_file}",
            'scenario': scenario,
            'template_used': template['scenario']
        }
        
        logger.info(f"Successfully generated {len(conversations)} conversations for scenario: {scenario}")
        return (json.dumps(result), 200, headers)
        
    except Exception as e:
        logger.error(f"Error generating conversations: {str(e)}")
        error_result = {'status': 'error', 'message': str(e)}
        return (json.dumps(error_result), 500, headers)