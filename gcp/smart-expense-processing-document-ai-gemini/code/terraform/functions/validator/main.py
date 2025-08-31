"""
Smart Expense Validation using Gemini AI
Cloud Function for validating expenses against corporate policies
"""

import json
import os
import logging
from typing import Dict, Any, List
import functions_framework
from google.cloud import aiplatform
import vertexai
from vertexai.generative_models import GenerativeModel

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Vertex AI
PROJECT_ID = "${project_id}"
REGION = "${region}"

def init_vertex_ai():
    """Initialize Vertex AI client"""
    try:
        vertexai.init(project=PROJECT_ID, location=REGION)
        return True
    except Exception as e:
        logger.error(f"Failed to initialize Vertex AI: {str(e)}")
        return False

def create_validation_prompt(expense_data: Dict[str, Any]) -> str:
    """Create a structured prompt for Gemini to validate expense data"""
    
    prompt = f"""
You are an AI expense auditor for a corporate expense management system. Analyze the following expense submission and determine if it complies with company policy.

EXPENSE DETAILS:
- Vendor: {expense_data.get('vendor_name', 'Unknown')}
- Amount: ${expense_data.get('total_amount', 0)}
- Date: {expense_data.get('expense_date', 'Unknown')}
- Category: {expense_data.get('category', 'Unknown')}
- Description: {expense_data.get('description', 'None provided')}
- Employee: {expense_data.get('employee_email', 'Unknown')}

CORPORATE EXPENSE POLICY:
1. Meals: Maximum $75 per day
2. Hotels: Maximum $300 per night
3. Transportation: Must be reasonable for business travel
4. Equipment: Requires manager pre-approval for amounts over $500
5. Entertainment: Maximum $150, must have clear business purpose
6. General: All expenses must be business-related and reasonable

VALIDATION CRITERIA:
- Check if expense amount exceeds category limits
- Assess if expense appears business-related based on vendor and description
- Identify any red flags (unusual amounts, suspicious vendors, etc.)
- Consider if expense timing and pattern seem reasonable

Please respond with a JSON object containing:
{{
    "approved": boolean,
    "confidence": float (0.0-1.0),
    "policy_violations": [list of specific policy violations],
    "recommendations": [list of actionable recommendations],
    "risk_score": integer (0-100, where 0 is lowest risk),
    "requires_manager_approval": boolean,
    "business_justification_score": float (0.0-1.0),
    "explanation": "Brief explanation of the decision"
}}

Be thorough but concise in your analysis. Focus on policy compliance and business appropriateness.
"""
    return prompt

def validate_with_gemini(expense_data: Dict[str, Any]) -> Dict[str, Any]:
    """Use Gemini to validate expense against corporate policies"""
    try:
        # Initialize Vertex AI if not already done
        if not init_vertex_ai():
            return create_fallback_validation(expense_data)
        
        # Create the generative model
        model = GenerativeModel("gemini-2.0-flash-exp")
        
        # Generate validation prompt
        prompt = create_validation_prompt(expense_data)
        
        # Get validation from Gemini
        response = model.generate_content(
            prompt,
            generation_config={
                "temperature": 0.1,  # Low temperature for consistent results
                "top_p": 0.8,
                "top_k": 40,
                "max_output_tokens": 1024,
            }
        )
        
        # Parse the JSON response
        try:
            validation_result = json.loads(response.text.strip())
            
            # Ensure all required fields are present
            required_fields = ['approved', 'confidence', 'policy_violations', 'recommendations', 'risk_score']
            for field in required_fields:
                if field not in validation_result:
                    logger.warning(f"Missing required field: {field}")
                    return create_fallback_validation(expense_data)
            
            return validation_result
            
        except json.JSONDecodeError:
            logger.error(f"Failed to parse Gemini response as JSON: {response.text}")
            return create_fallback_validation(expense_data)
            
    except Exception as e:
        logger.error(f"Error during Gemini validation: {str(e)}")
        return create_fallback_validation(expense_data)

def create_fallback_validation(expense_data: Dict[str, Any]) -> Dict[str, Any]:
    """Create a fallback validation using simple rule-based logic"""
    
    amount = float(expense_data.get('total_amount', 0))
    category = expense_data.get('category', '').lower()
    
    policy_violations = []
    approved = True
    risk_score = 20  # Base risk score
    
    # Apply simple policy rules
    if category == 'meals' and amount > 75:
        policy_violations.append(f"Meal expense ${amount} exceeds daily limit of $75")
        approved = False
        risk_score += 30
    elif category == 'hotels' and amount > 300:
        policy_violations.append(f"Hotel expense ${amount} exceeds nightly limit of $300")
        approved = False
        risk_score += 25
    elif category == 'equipment' and amount > 500:
        policy_violations.append(f"Equipment expense ${amount} exceeds $500 threshold and requires pre-approval")
        approved = False
        risk_score += 20
    elif category == 'entertainment' and amount > 150:
        policy_violations.append(f"Entertainment expense ${amount} exceeds limit of $150")
        approved = False
        risk_score += 15
    
    # Additional risk factors
    if amount > 1000:
        risk_score += 20
    if not expense_data.get('description'):
        risk_score += 10
        policy_violations.append("Missing expense description")
    
    # Determine recommendations
    recommendations = []
    if not approved:
        recommendations.append("Submit for manager review")
    if risk_score > 50:
        recommendations.append("Additional documentation may be required")
    if not policy_violations:
        recommendations.append("Expense appears to comply with company policy")
    
    return {
        "approved": approved,
        "confidence": 0.85,
        "policy_violations": policy_violations,
        "recommendations": recommendations,
        "risk_score": min(risk_score, 100),
        "requires_manager_approval": not approved or amount > 500,
        "business_justification_score": 0.8 if approved else 0.4,
        "explanation": f"Fallback validation - {'Approved' if approved else 'Requires review'} based on policy rules"
    }

@functions_framework.http
def validate_expense(request):
    """HTTP Cloud Function to validate expenses using AI."""
    
    # Handle CORS for web requests
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)
    
    # Set CORS headers for actual requests
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Content-Type': 'application/json'
    }
    
    try:
        # Validate request method
        if request.method != 'POST':
            return json.dumps({"error": "Only POST method is allowed"}), 405, headers
        
        # Parse request data
        expense_data = request.get_json(silent=True)
        if not expense_data:
            return json.dumps({"error": "No expense data provided"}), 400, headers
        
        # Validate required fields
        required_fields = ['vendor_name', 'total_amount', 'category']
        missing_fields = [field for field in required_fields if field not in expense_data]
        if missing_fields:
            return json.dumps({
                "error": f"Missing required fields: {', '.join(missing_fields)}"
            }), 400, headers
        
        # Log the validation request
        logger.info(f"Processing expense validation for: {expense_data.get('employee_email', 'unknown')}")
        
        # Perform validation using Gemini or fallback
        validation_result = validate_with_gemini(expense_data)
        
        # Add metadata to the response
        validation_result.update({
            "timestamp": expense_data.get('timestamp') or 'unknown',
            "processed_by": "expense-validator-function",
            "validation_version": "1.1"
        })
        
        # Log the result
        logger.info(f"Validation result: {'Approved' if validation_result['approved'] else 'Rejected'} "
                   f"(confidence: {validation_result['confidence']}, risk: {validation_result['risk_score']})")
        
        return json.dumps(validation_result), 200, headers
        
    except ValueError as e:
        logger.error(f"Validation error: {str(e)}")
        return json.dumps({"error": f"Validation error: {str(e)}"}), 400, headers
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        return json.dumps({"error": "Internal server error"}), 500, headers

def health_check():
    """Simple health check function"""
    try:
        # Test Vertex AI initialization
        init_success = init_vertex_ai()
        return {
            "status": "healthy" if init_success else "degraded",
            "vertex_ai": "available" if init_success else "unavailable",
            "timestamp": "unknown"
        }
    except Exception as e:
        return {
            "status": "unhealthy",
            "error": str(e),
            "timestamp": "unknown"
        }

# Entry point for testing
if __name__ == "__main__":
    # Test data for local development
    test_expense = {
        "vendor_name": "Test Restaurant",
        "total_amount": 45.50,
        "expense_date": "2025-01-15",
        "category": "meals",
        "description": "Business lunch with client",
        "employee_email": "test@company.com"
    }
    
    print("Testing expense validation...")
    result = validate_with_gemini(test_expense)
    print(json.dumps(result, indent=2))