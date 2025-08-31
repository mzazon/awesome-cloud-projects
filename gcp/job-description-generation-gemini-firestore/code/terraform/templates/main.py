import json
import vertexai
from vertexai.generative_models import GenerativeModel
from google.cloud import firestore
from flask import Flask, request, jsonify
import functions_framework
import os

# Initialize Vertex AI
PROJECT_ID = "${project_id}"
REGION = "${region}"
vertexai.init(project=PROJECT_ID, location=REGION)

# Initialize Firestore client
db = firestore.Client()

def generate_job_description(role_id, custom_requirements=None):
    """Generate job description using Gemini AI model."""
    try:
        # Retrieve company culture data
        culture_ref = db.collection('company_culture').document('default')
        culture_doc = culture_ref.get()
        
        if not culture_doc.exists:
            return {"error": "Company culture data not found"}
        
        culture_data = culture_doc.to_dict()
        
        # Retrieve job template
        template_ref = db.collection('job_templates').document(role_id)
        template_doc = template_ref.get()
        
        if not template_doc.exists:
            return {"error": f"Job template '{role_id}' not found"}
        
        template_data = template_doc.to_dict()
        
        # Initialize Gemini model
        model = GenerativeModel(os.environ.get('GEMINI_MODEL', 'gemini-1.5-flash'))
        
        # Construct comprehensive prompt
        prompt = f"""
        Create a comprehensive, professional job description for {template_data['title']} at {culture_data['company_name']}.
        
        Company Information:
        - Mission: {culture_data['mission']}
        - Values: {', '.join(culture_data['values'])}
        - Culture: {culture_data['culture_description']}
        - Work Environment: {culture_data['work_environment']}
        
        Role Details:
        - Department: {template_data['department']}
        - Level: {template_data['level']}
        - Experience Required: {template_data['experience_years']}
        - Education: {template_data['education']}
        - Required Skills: {', '.join(template_data['required_skills'])}
        - Nice to Have: {', '.join(template_data['nice_to_have'])}
        - Key Responsibilities: {'; '.join(template_data['responsibilities'])}
        
        Benefits to Include:
        {'; '.join(culture_data['benefits'])}
        
        Custom Requirements: {custom_requirements or 'None specified'}
        
        Please generate a complete job description that includes:
        1. Engaging job title and company overview
        2. Role summary and key responsibilities
        3. Required qualifications and preferred skills
        4. Benefits and compensation philosophy
        5. Equal opportunity employer statement
        6. Application instructions
        
        Use professional, inclusive language that attracts diverse candidates while clearly communicating expectations.
        """
        
        # Generate content with Gemini
        response = model.generate_content(prompt)
        
        # Store generated job description
        job_doc = {
            'role_id': role_id,
            'title': template_data['title'],
            'generated_description': response.text,
            'custom_requirements': custom_requirements,
            'created_at': firestore.SERVER_TIMESTAMP,
            'company_name': culture_data['company_name']
        }
        
        # Save to Firestore
        job_ref = db.collection('generated_jobs').add(job_doc)
        
        return {
            'success': True,
            'job_id': job_ref[1].id,
            'description': response.text,
            'role': template_data['title']
        }
        
    except Exception as e:
        return {'error': str(e)}

@functions_framework.http
def generate_job_description_http(request):
    """HTTP Cloud Function entry point."""
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)
    
    headers = {'Access-Control-Allow-Origin': '*'}
    
    try:
        request_json = request.get_json(silent=True)
        if not request_json or 'role_id' not in request_json:
            return jsonify({'error': 'Missing role_id parameter'}), 400, headers
        
        role_id = request_json['role_id']
        custom_requirements = request_json.get('custom_requirements')
        
        result = generate_job_description(role_id, custom_requirements)
        
        if 'error' in result:
            return jsonify(result), 400, headers
        
        return jsonify(result), 200, headers
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500, headers