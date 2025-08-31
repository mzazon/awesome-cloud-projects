import functions_framework
from vertexai.generative_models import GenerativeModel
from google.cloud import firestore
from flask import jsonify
import vertexai
import os

# Initialize services
PROJECT_ID = "${project_id}"
REGION = "${region}"
vertexai.init(project=PROJECT_ID, location=REGION)
db = firestore.Client()

@functions_framework.http
def validate_compliance(request):
    """Validate job description for compliance issues."""
    headers = {'Access-Control-Allow-Origin': '*'}
    
    try:
        request_json = request.get_json(silent=True)
        if not request_json or 'job_description' not in request_json:
            return jsonify({'error': 'Missing job_description'}), 400, headers
        
        job_description = request_json['job_description']
        
        model = GenerativeModel(os.environ.get('GEMINI_MODEL', 'gemini-1.5-flash'))
        
        compliance_prompt = f"""
        Review this job description for compliance with employment law and best practices:
        
        {job_description}
        
        Check for:
        1. Discriminatory language or requirements
        2. Age, gender, or other protected class bias
        3. Missing equal opportunity statement
        4. Unreasonable or illegal requirements
        5. Accessibility and inclusive language
        
        Provide a compliance score (1-10) and specific recommendations for improvement.
        Format response as JSON with 'score', 'issues', and 'recommendations' fields.
        """
        
        response = model.generate_content(compliance_prompt)
        
        return jsonify({
            'success': True,
            'compliance_review': response.text
        }), 200, headers
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500, headers