import json
import os
from google.cloud import storage
import functions_framework
from flask import Request, jsonify

@functions_framework.http
def deliver_quiz(request: Request):
    """Deliver quiz to students with proper formatting."""
    
    if request.method == 'OPTIONS':
        return _handle_cors()
    
    try:
        # Get quiz ID from request
        quiz_id = request.args.get('quiz_id')
        if not quiz_id:
            return jsonify({'error': 'Quiz ID required'}), 400
        
        # Retrieve quiz from storage
        quiz_data = _get_quiz_from_storage(quiz_id)
        if not quiz_data:
            return jsonify({'error': 'Quiz not found'}), 404
        
        # Format quiz for delivery (remove answers for student view)
        student_quiz = _format_for_students(quiz_data)
        
        response = jsonify({
            'quiz_id': quiz_id,
            'quiz': student_quiz,
            'status': 'success'
        })
        response.headers.add('Access-Control-Allow-Origin', '*')
        return response
        
    except Exception as e:
        error_response = jsonify({'error': str(e)})
        error_response.headers.add('Access-Control-Allow-Origin', '*')
        return error_response, 500

def _get_quiz_from_storage(quiz_id: str):
    """Retrieve quiz from Cloud Storage."""
    
    storage_client = storage.Client()
    bucket_name = os.environ.get('BUCKET_NAME', '${bucket_name}')
    bucket = storage_client.bucket(bucket_name)
    
    blob_name = f"quizzes/{quiz_id}.json"
    blob = bucket.blob(blob_name)
    
    if not blob.exists():
        return None
    
    quiz_content = blob.download_as_text()
    return json.loads(quiz_content)

def _format_for_students(quiz_data):
    """Remove correct answers for student delivery."""
    
    formatted_quiz = {
        'title': quiz_data.get('title', 'Quiz'),
        'questions': []
    }
    
    for i, question in enumerate(quiz_data.get('questions', [])):
        student_question = {
            'id': i,
            'type': question['type'],
            'question': question['question']
        }
        
        if question['type'] == 'multiple_choice':
            student_question['options'] = question['options']
        
        formatted_quiz['questions'].append(student_question)
    
    return formatted_quiz

def _handle_cors():
    """Handle CORS preflight requests."""
    response = jsonify({'status': 'ok'})
    response.headers.add('Access-Control-Allow-Origin', '*')
    response.headers.add('Access-Control-Allow-Methods', 'GET, OPTIONS')
    response.headers.add('Access-Control-Allow-Headers', 'Content-Type')
    return response