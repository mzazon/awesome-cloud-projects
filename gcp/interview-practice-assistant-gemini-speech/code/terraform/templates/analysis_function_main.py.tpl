import json
import vertexai
from vertexai.generative_models import GenerativeModel
import functions_framework
import os

@functions_framework.http
def analyze_interview_response(request):
    """Analyze interview response using Gemini."""
    try:
        request_json = request.get_json()
        if not request_json:
            return {'error': 'No JSON body provided', 'status': 'error'}
            
        transcription = request_json.get('transcription')
        question = request_json.get('question', 'Tell me about yourself')
        confidence = request_json.get('confidence', 0.0)
        
        if not transcription:
            return {'error': 'Missing required field: transcription', 'status': 'error'}
        
        # Initialize Vertex AI with project context
        project_id = os.environ.get('GCP_PROJECT')
        location = "${region}"
        vertexai.init(project=project_id, location=location)
        
        # Configure Gemini model with safety settings
        model = GenerativeModel("${gemini_model}")
        
        # Create comprehensive analysis prompt
        prompt = f"""
        You are an expert interview coach with 15+ years of experience. 
        Analyze this interview response and provide detailed, actionable feedback.
        
        Interview Question: {question}
        
        Candidate Response: {transcription}
        Speech Confidence Score: {confidence:.2f}/1.0
        
        Please provide analysis in this structured format:
        
        **Content Analysis (Weight: 40%)**
        - Content Quality Score: X/10
        - Key Strengths: [List 2-3 specific strengths]
        - Areas for Improvement: [List 2-3 specific areas]
        - Relevance to Question: [How well the response addressed the question]
        
        **Communication Skills (Weight: 30%)**
        - Clarity and Articulation: [Based on confidence score and content]
        - Structure and Organization: [Logical flow assessment]
        - Professional Language: [Word choice and tone evaluation]
        - Confidence Indicators: [Verbal confidence markers]
        
        **Interview Best Practices (Weight: 30%)**
        - STAR Method Usage: [Situation, Task, Action, Result framework]
        - Quantifiable Results: [Use of metrics and specific examples]
        - Company/Role Alignment: [Relevance to typical job requirements]
        - Follow-up Potential: [Opens discussion for next questions]
        
        **Specific Recommendations**
        1. [Most important improvement with example]
        2. [Communication enhancement with technique]
        3. [Content strengthening with framework]
        
        **Sample Improved Response**
        [Provide a 2-3 sentence example of how to enhance the response]
        
        **Overall Interview Score: X/10**
        
        Keep feedback constructive, specific, and encouraging. Focus on actionable improvements.
        """
        
        # Generate analysis with safety settings
        response = model.generate_content(
            prompt,
            generation_config={
                "temperature": 0.3,
                "top_p": 0.8,
                "max_output_tokens": 2048
            }
        )
        
        return {
            'analysis': response.text,
            'question': question,
            'transcription': transcription,
            'confidence_score': confidence,
            'model_used': "${gemini_model}",
            'status': 'success'
        }
        
    except Exception as e:
        import traceback
        return {
            'error': str(e),
            'traceback': traceback.format_exc(),
            'status': 'error'
        }