import json
import os
from datetime import datetime
from google.cloud import storage
import functions_framework
from flask import Request, jsonify

@functions_framework.http
def score_quiz(request: Request):
    """Score submitted quiz and provide feedback."""
    
    if request.method == 'OPTIONS':
        return _handle_cors()
    
    try:
        # Parse submission data
        request_json = request.get_json(silent=True)
        if not request_json:
            return jsonify({'error': 'No submission data'}), 400
        
        quiz_id = request_json.get('quiz_id')
        student_answers = request_json.get('answers', {})
        student_id = request_json.get('student_id', 'anonymous')
        
        # Get original quiz with answers
        quiz_data = _get_quiz_from_storage(quiz_id)
        if not quiz_data:
            return jsonify({'error': 'Quiz not found'}), 404
        
        # Calculate score and feedback
        results = _calculate_score(quiz_data, student_answers)
        
        # Store results
        result_id = _store_results(quiz_id, student_id, student_answers, results)
        
        response = jsonify({
            'result_id': result_id,
            'score': results['score'],
            'total_questions': results['total_questions'],
            'percentage': results['percentage'],
            'feedback': results['feedback'],
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

def _calculate_score(quiz_data, student_answers):
    """Calculate score and provide detailed feedback."""
    
    questions = quiz_data.get('questions', [])
    correct_count = 0
    total_questions = len(questions)
    feedback = []
    
    for i, question in enumerate(questions):
        question_id = str(i)
        student_answer = student_answers.get(question_id)
        
        is_correct = False
        explanation = question.get('explanation', 'No explanation available')
        
        if question['type'] == 'multiple_choice':
            correct_answer = question['correct_answer']
            is_correct = student_answer == correct_answer
            
        elif question['type'] == 'true_false':
            correct_answer = question['correct_answer']
            is_correct = student_answer == correct_answer
            
        elif question['type'] == 'short_answer':
            # Simple text matching for short answers
            correct_answer = question.get('sample_answer', '').lower()
            student_text = str(student_answer).lower() if student_answer else ''
            is_correct = correct_answer in student_text or student_text in correct_answer
        
        if is_correct:
            correct_count += 1
        
        feedback.append({
            'question_id': i,
            'question': question['question'],
            'correct': is_correct,
            'explanation': explanation
        })
    
    percentage = (correct_count / total_questions * 100) if total_questions > 0 else 0
    
    return {
        'score': correct_count,
        'total_questions': total_questions,
        'percentage': round(percentage, 2),
        'feedback': feedback
    }

def _store_results(quiz_id, student_id, answers, results):
    """Store quiz results in Cloud Storage."""
    
    storage_client = storage.Client()
    bucket_name = os.environ.get('BUCKET_NAME', '${bucket_name}')
    bucket = storage_client.bucket(bucket_name)
    
    result_id = f"result_{os.urandom(8).hex()}"
    blob_name = f"results/{result_id}.json"
    
    result_data = {
        'result_id': result_id,
        'quiz_id': quiz_id,
        'student_id': student_id,
        'timestamp': datetime.utcnow().isoformat(),
        'answers': answers,
        'results': results
    }
    
    blob = bucket.blob(blob_name)
    blob.upload_from_string(
        json.dumps(result_data, indent=2),
        content_type='application/json'
    )
    
    return result_id

def _handle_cors():
    """Handle CORS preflight requests."""
    response = jsonify({'status': 'ok'})
    response.headers.add('Access-Control-Allow-Origin', '*')
    response.headers.add('Access-Control-Allow-Methods', 'POST, OPTIONS')
    response.headers.add('Access-Control-Allow-Headers', 'Content-Type')
    return response