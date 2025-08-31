import json
import os
from typing import Dict, List, Any
from google.cloud import aiplatform
from google.cloud import storage
import vertexai
from vertexai.generative_models import GenerativeModel
import functions_framework
from flask import Request, jsonify

# Initialize Vertex AI
PROJECT_ID = os.environ.get('GCP_PROJECT', os.environ.get('GOOGLE_CLOUD_PROJECT'))
REGION = os.environ.get('REGION', '${region}')

vertexai.init(project=PROJECT_ID, location=REGION)
model = GenerativeModel("gemini-1.5-flash-002")

@functions_framework.http
def generate_quiz(request: Request) -> Any:
    """Generate quiz from uploaded content using Vertex AI."""
    
    if request.method == 'OPTIONS':
        return _handle_cors()
    
    try:
        # Parse request data
        request_json = request.get_json(silent=True)
        if not request_json:
            return jsonify({'error': 'No JSON data provided'}), 400
        
        content_text = request_json.get('content', '')
        question_count = request_json.get('question_count', 5)
        difficulty = request_json.get('difficulty', 'medium')
        
        if not content_text:
            return jsonify({'error': 'Content text is required'}), 400
        
        # Generate quiz using Vertex AI
        quiz = _generate_quiz_with_ai(content_text, question_count, difficulty)
        
        # Store quiz in Cloud Storage
        quiz_id = _store_quiz(quiz)
        
        response = jsonify({
            'quiz_id': quiz_id,
            'quiz': quiz,
            'status': 'success'
        })
        response.headers.add('Access-Control-Allow-Origin', '*')
        return response
        
    except Exception as e:
        error_response = jsonify({'error': str(e), 'status': 'error'})
        error_response.headers.add('Access-Control-Allow-Origin', '*')
        return error_response, 500

def _generate_quiz_with_ai(content: str, count: int, difficulty: str) -> Dict:
    """Use Vertex AI to generate quiz questions from content."""
    
    prompt = f"""
    Based on the following educational content, generate {count} quiz questions at {difficulty} difficulty level.
    
    Create a mix of question types:
    - Multiple choice (4 options each)
    - True/False
    - Short answer
    
    Content:
    {content[:4000]}  # Limit content to stay within token limits
    
    Return the response as valid JSON with this structure:
    {{
        "title": "Quiz Title",
        "questions": [
            {{
                "type": "multiple_choice",
                "question": "Question text",
                "options": ["A", "B", "C", "D"],
                "correct_answer": 0,
                "explanation": "Why this answer is correct"
            }},
            {{
                "type": "true_false",
                "question": "Question text",
                "correct_answer": true,
                "explanation": "Explanation"
            }},
            {{
                "type": "short_answer",
                "question": "Question text",
                "sample_answer": "Expected answer",
                "explanation": "Explanation"
            }}
        ]
    }}
    """
    
    response = model.generate_content(prompt)
    
    try:
        # Clean response text and parse as JSON
        response_text = response.text.strip()
        if response_text.startswith('```json'):
            response_text = response_text[7:-3].strip()
        elif response_text.startswith('```'):
            response_text = response_text[3:-3].strip()
        
        quiz_data = json.loads(response_text)
        
        # Validate quiz structure
        if 'questions' not in quiz_data or not quiz_data['questions']:
            raise ValueError("Invalid quiz structure")
            
        return quiz_data
        
    except (json.JSONDecodeError, ValueError) as e:
        print(f"Error parsing AI response: {e}. Using fallback quiz.")
        # Fallback if AI doesn't return valid JSON
        return {
            "title": "Generated Quiz",
            "questions": [{
                "type": "multiple_choice",
                "question": "What is the main topic of the provided content?",
                "options": ["Topic A", "Topic B", "Topic C", "Topic D"],
                "correct_answer": 0,
                "explanation": "Based on content analysis"
            }]
        }

def _store_quiz(quiz_data: Dict) -> str:
    """Store generated quiz in Cloud Storage."""
    
    storage_client = storage.Client()
    bucket_name = os.environ.get('BUCKET_NAME', '${bucket_name}')
    bucket = storage_client.bucket(bucket_name)
    
    # Generate unique quiz ID
    quiz_id = f"quiz_{os.urandom(8).hex()}"
    blob_name = f"quizzes/{quiz_id}.json"
    
    blob = bucket.blob(blob_name)
    blob.upload_from_string(
        json.dumps(quiz_data, indent=2),
        content_type='application/json'
    )
    
    return quiz_id

def _handle_cors():
    """Handle CORS preflight requests."""
    response = jsonify({'status': 'ok'})
    response.headers.add('Access-Control-Allow-Origin', '*')
    response.headers.add('Access-Control-Allow-Methods', 'POST, OPTIONS')
    response.headers.add('Access-Control-Allow-Headers', 'Content-Type')
    return response