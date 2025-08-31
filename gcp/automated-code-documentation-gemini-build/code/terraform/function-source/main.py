# Documentation processing Cloud Function using Vertex AI Gemini
# This function generates various types of documentation from code using AI

import json
import os
from google.cloud import storage
import vertexai
from vertexai.generative_models import GenerativeModel
import functions_framework
import datetime
from typing import Dict, Any

# Initialize Vertex AI with project and location
vertexai.init(
    project=os.environ.get('GOOGLE_CLOUD_PROJECT'), 
    location=os.environ.get('GOOGLE_CLOUD_REGION', 'us-central1')
)

@functions_framework.http
def generate_docs(request) -> Dict[str, Any]:
    """
    Generate documentation using Gemini AI based on request parameters.
    
    Args:
        request: HTTP request containing JSON with:
            - repo_path: Path to the code file
            - file_content: Content of the code file
            - doc_type: Type of documentation (api, readme, comments)
    
    Returns:
        JSON response with status and storage path or error message
    """
    
    try:
        # Parse and validate request data
        request_json = request.get_json()
        if not request_json:
            return {
                'status': 'error',
                'message': 'Request must contain JSON data'
            }, 400
        
        repo_path = request_json.get('repo_path', '')
        file_content = request_json.get('file_content', '')
        doc_type = request_json.get('doc_type', 'api')
        
        # Validate required fields
        if not repo_path:
            return {
                'status': 'error',
                'message': 'repo_path is required'
            }, 400
            
        if not file_content:
            return {
                'status': 'error',
                'message': 'file_content is required'
            }, 400
        
        # Validate documentation type
        valid_doc_types = ['api', 'readme', 'comments']
        if doc_type not in valid_doc_types:
            return {
                'status': 'error',
                'message': f'doc_type must be one of: {", ".join(valid_doc_types)}'
            }, 400
        
        # Initialize Gemini model
        model_name = os.environ.get('GEMINI_MODEL', '${gemini_model}')
        model = GenerativeModel(model_name)
        
        # Generate documentation prompt based on type
        prompt = generate_prompt(doc_type, file_content, repo_path)
        
        # Generate documentation with Gemini
        response = model.generate_content(
            prompt,
            generation_config={
                'temperature': 0.3,  # Lower temperature for more consistent output
                'max_output_tokens': 2048,
                'top_p': 0.8,
                'top_k': 40
            }
        )
        
        if not response.text:
            return {
                'status': 'error',
                'message': 'Failed to generate documentation content'
            }, 500
        
        generated_docs = response.text
        
        # Save to Cloud Storage
        storage_path = save_to_storage(generated_docs, doc_type, repo_path)
        
        return {
            'status': 'success',
            'message': f'Documentation generated and stored at {storage_path}',
            'storage_path': storage_path,
            'doc_type': doc_type,
            'repo_path': repo_path,
            'timestamp': datetime.datetime.now().isoformat()
        }
        
    except Exception as e:
        print(f"Error generating documentation: {str(e)}")
        return {
            'status': 'error',
            'message': f'Internal error: {str(e)}'
        }, 500

def generate_prompt(doc_type: str, file_content: str, repo_path: str) -> str:
    """
    Generate appropriate prompts for different documentation types.
    
    Args:
        doc_type: Type of documentation to generate
        file_content: Content of the code file
        repo_path: Path to the repository file
    
    Returns:
        Formatted prompt string for Gemini AI
    """
    
    base_instructions = """
Please generate clear, professional, and comprehensive documentation.
Use proper Markdown formatting with appropriate headers, code blocks, and lists.
Ensure the documentation is accurate and helpful for developers.
"""
    
    if doc_type == 'api':
        return f"""
{base_instructions}

Analyze the following code and generate comprehensive API documentation in Markdown format.
Include:
- Function/method descriptions with clear explanations
- Parameter details with types and descriptions
- Return value information with types
- Usage examples with sample code
- Error handling information where applicable
- Notes about dependencies or requirements

File: {repo_path}
Code:
{file_content}

Generate clear, professional API documentation:
"""
    
    elif doc_type == 'readme':
        return f"""
{base_instructions}

Analyze the following code repository structure and generate a comprehensive README.md file.
Include:
- Project title and brief description
- Installation instructions
- Usage examples and getting started guide
- API overview (if applicable)
- Configuration options
- Contributing guidelines
- License information placeholder
- Contact or support information

Repository information: {repo_path}
Repository structure and key files:
{file_content}

Generate a professional README.md file:
"""
    
    else:  # code comments
        return f"""
{base_instructions}

Analyze the following code and add comprehensive inline comments explaining the functionality.
Requirements:
- Maintain the original code structure exactly
- Add clear, helpful comments that explain what the code does
- Include docstrings for functions and classes
- Explain complex algorithms or business logic
- Add type hints where appropriate
- Preserve all existing comments and improve them if needed

File: {repo_path}
Code:
{file_content}

Return the code with added comprehensive comments:
"""

def save_to_storage(content: str, doc_type: str, repo_path: str) -> str:
    """
    Save generated documentation to Cloud Storage.
    
    Args:
        content: Generated documentation content
        doc_type: Type of documentation
        repo_path: Original repository path
    
    Returns:
        Storage path where the content was saved
    """
    
    try:
        # Initialize storage client
        storage_client = storage.Client()
        bucket_name = os.environ.get('BUCKET_NAME')
        
        if not bucket_name:
            raise ValueError('BUCKET_NAME environment variable not set')
        
        bucket = storage_client.bucket(bucket_name)
        
        # Create filename with timestamp and proper organization
        timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        
        # Clean the repo path for filename use
        clean_path = repo_path.replace('/', '_').replace('\\', '_')
        filename = f"{doc_type}/{clean_path}_{timestamp}.md"
        
        # Create and upload blob
        blob = bucket.blob(filename)
        blob.upload_from_string(
            content,
            content_type='text/markdown'
        )
        
        # Set metadata
        blob.metadata = {
            'doc_type': doc_type,
            'repo_path': repo_path,
            'generated_at': datetime.datetime.now().isoformat(),
            'generator': 'gemini-doc-automation'
        }
        blob.patch()
        
        return f'gs://{bucket_name}/{filename}'
        
    except Exception as e:
        print(f"Error saving to storage: {str(e)}")
        raise

# Health check endpoint for monitoring
@functions_framework.http
def health_check(request):
    """Simple health check endpoint for monitoring the function."""
    return {
        'status': 'healthy',
        'timestamp': datetime.datetime.now().isoformat(),
        'service': 'documentation-generator'
    }