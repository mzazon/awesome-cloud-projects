# Cloud Function for AI-powered API test case generation
# This function uses Vertex AI Gemini to analyze API specifications and generate comprehensive test cases

import json
import os
import logging
from typing import Dict, Any, List, Optional
from google.cloud import aiplatform
from google.cloud import storage
import functions_framework
import vertexai
from vertexai.generative_models import GenerativeModel

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Vertex AI with project and location
PROJECT_ID = "${project_id}"
LOCATION = "${location}"
BUCKET_NAME = "${bucket_name}"
GEMINI_MODEL = "${gemini_model}"

# Initialize Vertex AI
vertexai.init(project=PROJECT_ID, location=LOCATION)

@functions_framework.http
def generate_test_cases(request):
    """
    Generate comprehensive API test cases using Vertex AI Gemini
    
    Args:
        request: HTTP request with JSON payload containing:
            - api_specification: OpenAPI/Swagger specification or description
            - endpoints: Optional list of specific endpoints to test
            - test_types: Optional list of test types (functional, security, performance)
            - request_id: Optional unique identifier for this request
    
    Returns:
        JSON response with generated test cases and storage location
    """
    
    # Set CORS headers for web clients
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization'
    }
    
    # Handle preflight OPTIONS request
    if request.method == 'OPTIONS':
        return ('', 204, headers)
    
    # Only accept POST requests
    if request.method != 'POST':
        return ({'error': 'Only POST method supported'}, 405, headers)
    
    try:
        # Parse and validate request data
        request_json = request.get_json(silent=True)
        if not request_json:
            logger.error("No JSON data in request")
            return ({'error': 'Invalid JSON in request body'}, 400, headers)
        
        # Extract parameters with defaults
        api_spec = request_json.get('api_specification', '')
        target_endpoints = request_json.get('endpoints', [])
        test_types = request_json.get('test_types', ['functional', 'security', 'performance'])
        request_id = request_json.get('request_id', 'unknown')
        
        # Validate required parameters
        if not api_spec:
            logger.error("API specification is required")
            return ({'error': 'API specification required'}, 400, headers)
        
        if len(api_spec) > 50000:  # Reasonable limit for API specs
            logger.error("API specification too large")
            return ({'error': 'API specification too large (max 50KB)'}, 400, headers)
        
        logger.info(f"Processing test generation request: {request_id}")
        logger.info(f"Target endpoints: {target_endpoints}")
        logger.info(f"Test types: {test_types}")
        
        # Generate test cases using Gemini AI
        test_cases = generate_ai_test_cases(api_spec, target_endpoints, test_types)
        
        # Store generated test cases in Cloud Storage
        storage_location = store_test_cases(test_cases, request_id)
        
        # Prepare response
        response = {
            'status': 'success',
            'test_cases_generated': True,
            'test_count': len(test_cases.get('test_cases', [])),
            'storage_location': storage_location,
            'ai_response': json.dumps(test_cases, indent=2),
            'request_id': request_id,
            'model_used': GEMINI_MODEL
        }
        
        logger.info(f"Successfully generated {len(test_cases.get('test_cases', []))} test cases")
        return (response, 200, headers)
        
    except ValueError as e:
        logger.error(f"Validation error: {str(e)}")
        return ({'error': f'Invalid input: {str(e)}'}, 400, headers)
    
    except Exception as e:
        logger.error(f"Unexpected error in test generation: {str(e)}")
        return ({'error': f'Test generation failed: {str(e)}'}, 500, headers)


def generate_ai_test_cases(api_spec: str, target_endpoints: List[str], test_types: List[str]) -> Dict[str, Any]:
    """
    Use Vertex AI Gemini to generate comprehensive test cases
    
    Args:
        api_spec: API specification or description
        target_endpoints: List of specific endpoints to target
        test_types: Types of tests to generate
    
    Returns:
        Dictionary containing generated test cases
    """
    try:
        # Initialize Gemini model
        model = GenerativeModel(GEMINI_MODEL)
        
        # Create comprehensive prompt for test generation
        prompt = create_test_generation_prompt(api_spec, target_endpoints, test_types)
        
        logger.info(f"Generating test cases with {GEMINI_MODEL}")
        
        # Generate test cases using Gemini
        response = model.generate_content(
            prompt,
            generation_config={
                "max_output_tokens": 8192,
                "temperature": 0.2,
                "top_p": 0.8,
                "top_k": 40
            }
        )
        
        # Parse AI response
        ai_response_text = response.text
        logger.info(f"Received AI response: {len(ai_response_text)} characters")
        
        # Try to parse as JSON
        try:
            test_cases = json.loads(ai_response_text)
            
            # Validate structure
            if not isinstance(test_cases, dict) or 'test_cases' not in test_cases:
                raise ValueError("Invalid test case structure from AI")
            
            # Add metadata to each test case
            for i, test_case in enumerate(test_cases.get('test_cases', [])):
                test_case['generated_at'] = get_current_timestamp()
                test_case['model_used'] = GEMINI_MODEL
                if 'id' not in test_case:
                    test_case['id'] = f"test-{i+1:03d}"
            
            return test_cases
            
        except json.JSONDecodeError:
            # If AI response isn't valid JSON, wrap it in a structure
            logger.warning("AI response not valid JSON, creating structured response")
            return {
                "test_cases": [{
                    "id": "test-001",
                    "name": "AI Generated Test Suite",
                    "description": "Test cases generated by AI (raw format)",
                    "endpoint": target_endpoints[0] if target_endpoints else "/api/test",
                    "method": "GET",
                    "headers": {},
                    "payload": {},
                    "expected_status": 200,
                    "expected_response": {},
                    "test_type": "functional",
                    "priority": "medium",
                    "ai_response": ai_response_text,
                    "generated_at": get_current_timestamp(),
                    "model_used": GEMINI_MODEL
                }],
                "metadata": {
                    "total_tests": 1,
                    "ai_model": GEMINI_MODEL,
                    "raw_response": ai_response_text
                }
            }
        
    except Exception as e:
        logger.error(f"Error in AI test generation: {str(e)}")
        # Return a fallback test case structure
        return create_fallback_test_cases(target_endpoints, test_types, str(e))


def create_test_generation_prompt(api_spec: str, target_endpoints: List[str], test_types: List[str]) -> str:
    """
    Create a comprehensive prompt for AI test case generation
    
    Args:
        api_spec: API specification
        target_endpoints: Target endpoints
        test_types: Types of tests to generate
    
    Returns:
        Formatted prompt string
    """
    
    endpoint_section = ""
    if target_endpoints:
        endpoint_section = f"Focus specifically on these endpoints: {', '.join(target_endpoints)}"
    else:
        endpoint_section = "Generate tests for all endpoints found in the specification"
    
    prompt = f"""
You are an expert API testing engineer. Analyze the following API specification and generate comprehensive, realistic test cases in valid JSON format.

API Specification:
{api_spec}

Requirements:
- {endpoint_section}
- Generate tests for these types: {', '.join(test_types)}
- Create both positive and negative test scenarios
- Include edge cases and boundary conditions
- Focus on real-world testing scenarios

For each test type:
- Functional: Test core API functionality, data validation, business logic
- Security: Test authentication, authorization, input validation, injection attacks
- Performance: Test response times, concurrent requests, large payloads

Return ONLY valid JSON in this exact format:
{{
  "test_cases": [
    {{
      "id": "unique_test_id",
      "name": "descriptive_test_name",
      "description": "detailed test description",
      "endpoint": "full_endpoint_url_or_path",
      "method": "HTTP_METHOD",
      "headers": {{}},
      "payload": {{}},
      "expected_status": 200,
      "expected_response": {{}},
      "test_type": "functional|security|performance",
      "priority": "high|medium|low",
      "timeout": 30
    }}
  ],
  "metadata": {{
    "total_tests": 0,
    "test_types_covered": [],
    "endpoints_covered": []
  }}
}}

Generate at least 5-10 comprehensive test cases covering different scenarios, endpoints, and test types.
Ensure all JSON is valid and properly escaped.
"""
    
    return prompt


def store_test_cases(test_cases: Dict[str, Any], request_id: str) -> str:
    """
    Store generated test cases in Cloud Storage
    
    Args:
        test_cases: Generated test cases dictionary
        request_id: Unique request identifier
    
    Returns:
        GCS URI of stored test cases
    """
    try:
        # Initialize storage client
        storage_client = storage.Client()
        bucket = storage_client.bucket(BUCKET_NAME)
        
        # Create blob path
        timestamp = get_current_timestamp()
        blob_name = f"test-specifications/generated-tests-{request_id}-{timestamp}.json"
        blob = bucket.blob(blob_name)
        
        # Convert test cases to JSON string
        test_cases_json = json.dumps(test_cases, indent=2, ensure_ascii=False)
        
        # Upload to storage
        blob.upload_from_string(
            test_cases_json,
            content_type='application/json'
        )
        
        # Set metadata
        blob.metadata = {
            'request_id': request_id,
            'generated_at': timestamp,
            'model_used': GEMINI_MODEL,
            'test_count': str(len(test_cases.get('test_cases', [])))
        }
        blob.patch()
        
        storage_uri = f"gs://{BUCKET_NAME}/{blob_name}"
        logger.info(f"Stored test cases at: {storage_uri}")
        
        return storage_uri
        
    except Exception as e:
        logger.error(f"Error storing test cases: {str(e)}")
        raise


def create_fallback_test_cases(target_endpoints: List[str], test_types: List[str], error_msg: str) -> Dict[str, Any]:
    """
    Create fallback test cases when AI generation fails
    
    Args:
        target_endpoints: Target endpoints
        test_types: Test types requested
        error_msg: Error message from AI generation
    
    Returns:
        Fallback test cases dictionary
    """
    fallback_tests = []
    
    # Create basic test cases for each endpoint
    for i, endpoint in enumerate(target_endpoints[:3]):  # Limit to 3 endpoints
        for j, test_type in enumerate(test_types[:2]):  # Limit to 2 test types
            test_id = f"fallback-{i+1:02d}-{j+1:02d}"
            fallback_tests.append({
                "id": test_id,
                "name": f"Fallback {test_type.title()} Test - {endpoint}",
                "description": f"Basic {test_type} test generated as fallback",
                "endpoint": endpoint,
                "method": "GET",
                "headers": {"Content-Type": "application/json"},
                "payload": {},
                "expected_status": 200,
                "expected_response": {},
                "test_type": test_type,
                "priority": "medium",
                "timeout": 30,
                "generated_at": get_current_timestamp(),
                "model_used": "fallback",
                "note": f"Fallback test due to AI generation error: {error_msg}"
            })
    
    # If no endpoints provided, create generic tests
    if not fallback_tests:
        for i, test_type in enumerate(test_types):
            test_id = f"fallback-generic-{i+1:02d}"
            fallback_tests.append({
                "id": test_id,
                "name": f"Generic {test_type.title()} Test",
                "description": f"Generic {test_type} test case",
                "endpoint": "/api/health",
                "method": "GET",
                "headers": {},
                "payload": {},
                "expected_status": 200,
                "expected_response": {"status": "ok"},
                "test_type": test_type,
                "priority": "low",
                "timeout": 30,
                "generated_at": get_current_timestamp(),
                "model_used": "fallback"
            })
    
    return {
        "test_cases": fallback_tests,
        "metadata": {
            "total_tests": len(fallback_tests),
            "generation_method": "fallback",
            "error": error_msg,
            "ai_model": GEMINI_MODEL
        }
    }


def get_current_timestamp() -> str:
    """Get current timestamp in ISO format"""
    from datetime import datetime
    return datetime.utcnow().isoformat() + 'Z'


def validate_test_case(test_case: Dict[str, Any]) -> bool:
    """
    Validate a test case structure
    
    Args:
        test_case: Test case dictionary to validate
    
    Returns:
        True if valid, False otherwise
    """
    required_fields = ['id', 'name', 'endpoint', 'method', 'expected_status']
    
    for field in required_fields:
        if field not in test_case:
            logger.warning(f"Test case missing required field: {field}")
            return False
    
    # Validate HTTP method
    valid_methods = ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'HEAD', 'OPTIONS']
    if test_case.get('method', '').upper() not in valid_methods:
        logger.warning(f"Invalid HTTP method: {test_case.get('method')}")
        return False
    
    # Validate status code
    status = test_case.get('expected_status')
    if not isinstance(status, int) or status < 100 or status > 599:
        logger.warning(f"Invalid status code: {status}")
        return False
    
    return True