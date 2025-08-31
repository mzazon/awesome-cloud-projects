import json
import os
from datetime import datetime
from google.cloud import storage
import vertexai
from vertexai.generative_models import GenerativeModel
import functions_framework

def initialize_services():
    """Initialize Google Cloud services"""
    project_id = "${project_id}"
    bucket_name = "${bucket_name}"
    location = "${location}"
    
    # Initialize Vertex AI
    vertexai.init(project=project_id, location=location)
    
    # Initialize storage client
    storage_client = storage.Client()
    bucket = storage_client.bucket(bucket_name)
    
    return bucket, project_id

def load_content_template(bucket):
    """Load content template from Cloud Storage"""
    try:
        blob = bucket.blob("templates/content-template.json")
        template_data = blob.download_as_text()
        return json.loads(template_data)["newsletter_template"]
    except Exception as e:
        print(f"Error loading template: {e}")
        # Fallback template
        return {
            "subject_line": "Generate an engaging subject line about {topic}",
            "intro": "Write a brief introduction paragraph about {topic} in a professional yet friendly tone",
            "main_content": "Create 2-3 paragraphs of informative content about {topic}, including practical tips or insights",
            "call_to_action": "Write a compelling call-to-action related to {topic}",
            "tone": "professional, engaging, informative",
            "target_audience": "business professionals and marketing teams",
            "word_limit": 300
        }

def generate_newsletter_content(topic, template):
    """Generate newsletter content using Gemini"""
    try:
        model = GenerativeModel("gemini-1.5-flash")
        
        prompt = f"""
        Create newsletter content based on this template and topic:
        Topic: {topic}
        
        Template Requirements:
        - Subject Line: {template['subject_line'].replace('{topic}', topic)}
        - Introduction: {template['intro'].replace('{topic}', topic)}
        - Main Content: {template['main_content'].replace('{topic}', topic)}
        - Call to Action: {template['call_to_action'].replace('{topic}', topic)}
        
        Additional Guidelines:
        - Tone: {template['tone']}
        - Target Audience: {template['target_audience']}
        - Word Limit: {template['word_limit']} words
        
        Please provide the content in JSON format with keys: subject_line, intro, main_content, call_to_action
        Make sure the response is valid JSON that can be parsed.
        """
        
        response = model.generate_content(prompt)
        return response.text
    except Exception as e:
        print(f"Error generating content: {e}")
        raise

def store_content_result(bucket, topic, content, template):
    """Store generated content in Cloud Storage"""
    try:
        # Create timestamp for filename
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"newsletter_{topic.replace(' ', '_').lower()}_{timestamp}.json"
        
        # Store result in Cloud Storage
        blob = bucket.blob(f"generated-content/{filename}")
        result_data = {
            "topic": topic,
            "generated_at": timestamp,
            "content": content,
            "template_used": template,
            "metadata": {
                "function_version": "1.0",
                "model_used": "gemini-1.5-flash",
                "project_id": "${project_id}"
            }
        }
        blob.upload_from_string(json.dumps(result_data, indent=2))
        return filename, f"gs://${bucket_name}/generated-content/{filename}"
    except Exception as e:
        print(f"Error storing content: {e}")
        raise

@functions_framework.http
def generate_newsletter(request):
    """HTTP Cloud Function to generate newsletter content"""
    try:
        # Initialize services
        bucket, project_id = initialize_services()
        
        # Get request data
        request_json = request.get_json(silent=True)
        request_args = request.args
        
        # Extract topic from request
        if request_json and 'topic' in request_json:
            topic = request_json['topic']
        elif request_args and 'topic' in request_args:
            topic = request_args['topic']
        else:
            topic = 'Weekly Marketing Insights'  # Default topic
        
        print(f"Generating newsletter content for topic: {topic}")
        
        # Load template
        template = load_content_template(bucket)
        
        # Generate content
        generated_content = generate_newsletter_content(topic, template)
        
        # Store result
        filename, storage_path = store_content_result(bucket, topic, generated_content, template)
        
        # Log success
        print(f"Successfully generated and stored newsletter content: {filename}")
        
        return {
            "status": "success",
            "message": f"Newsletter content generated successfully for topic: {topic}",
            "topic": topic,
            "filename": filename,
            "storage_path": storage_path,
            "generated_at": datetime.now().isoformat(),
            "function_info": {
                "project_id": project_id,
                "bucket_name": "${bucket_name}",
                "model_used": "gemini-1.5-flash"
            }
        }, 200
        
    except Exception as e:
        error_msg = f"Error generating newsletter: {str(e)}"
        print(error_msg)
        return {
            "status": "error",
            "message": error_msg,
            "error_type": type(e).__name__
        }, 500

# Health check endpoint
@functions_framework.http
def health_check(request):
    """Health check endpoint for monitoring"""
    if request.path == '/health':
        return {"status": "healthy", "timestamp": datetime.now().isoformat()}, 200
    else:
        return generate_newsletter(request)