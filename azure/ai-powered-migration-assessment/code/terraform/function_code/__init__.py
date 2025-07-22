"""
Azure Function for AI-Powered Migration Assessment
This function processes migration assessment data using Azure OpenAI Service
to generate intelligent modernization recommendations.
"""

import azure.functions as func
import json
import logging
import os
from azure.storage.blob import BlobServiceClient
from openai import AzureOpenAI
import datetime
import traceback
from typing import Dict, Any, List

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def main(req: func.HttpRequest) -> func.HttpResponse:
    """
    Main function to process migration assessment data and generate AI insights.
    
    Args:
        req: HTTP request containing assessment data
        
    Returns:
        HTTP response with AI-generated insights
    """
    logger.info('Migration AI Assessment function triggered')
    
    try:
        # Validate request method
        if req.method != 'POST':
            return func.HttpResponse(
                json.dumps({
                    "status": "error",
                    "message": "Only POST method is supported"
                }),
                status_code=405,
                mimetype="application/json"
            )
        
        # Get assessment data from request
        try:
            assessment_data = req.get_json()
            if not assessment_data:
                return func.HttpResponse(
                    json.dumps({
                        "status": "error",
                        "message": "No assessment data provided in request body"
                    }),
                    status_code=400,
                    mimetype="application/json"
                )
        except Exception as e:
            logger.error(f"Error parsing request JSON: {str(e)}")
            return func.HttpResponse(
                json.dumps({
                    "status": "error",
                    "message": "Invalid JSON in request body"
                }),
                status_code=400,
                mimetype="application/json"
            )
        
        # Validate required environment variables
        required_env_vars = ["OPENAI_ENDPOINT", "OPENAI_KEY", "OPENAI_MODEL_DEPLOYMENT", "STORAGE_CONNECTION_STRING"]
        missing_vars = [var for var in required_env_vars if not os.environ.get(var)]
        
        if missing_vars:
            logger.error(f"Missing environment variables: {missing_vars}")
            return func.HttpResponse(
                json.dumps({
                    "status": "error",
                    "message": f"Missing required environment variables: {', '.join(missing_vars)}"
                }),
                status_code=500,
                mimetype="application/json"
            )
        
        # Initialize OpenAI client
        try:
            client = AzureOpenAI(
                api_key=os.environ["OPENAI_KEY"],
                api_version="2024-06-01",
                azure_endpoint=os.environ["OPENAI_ENDPOINT"]
            )
        except Exception as e:
            logger.error(f"Error initializing OpenAI client: {str(e)}")
            return func.HttpResponse(
                json.dumps({
                    "status": "error",
                    "message": "Failed to initialize OpenAI client"
                }),
                status_code=500,
                mimetype="application/json"
            )
        
        # Process assessment data and generate AI insights
        try:
            ai_insights = generate_ai_insights(client, assessment_data)
        except Exception as e:
            logger.error(f"Error generating AI insights: {str(e)}")
            return func.HttpResponse(
                json.dumps({
                    "status": "error",
                    "message": f"Failed to generate AI insights: {str(e)}"
                }),
                status_code=500,
                mimetype="application/json"
            )
        
        # Store insights in blob storage
        try:
            blob_url = store_insights_in_blob(ai_insights, assessment_data)
        except Exception as e:
            logger.error(f"Error storing insights in blob: {str(e)}")
            # Continue even if blob storage fails
            blob_url = None
        
        # Prepare response
        response_data = {
            "status": "success",
            "insights": ai_insights,
            "blob_url": blob_url,
            "timestamp": datetime.datetime.utcnow().isoformat() + "Z",
            "message": "AI assessment completed successfully"
        }
        
        logger.info("AI assessment processing completed successfully")
        
        return func.HttpResponse(
            json.dumps(response_data, indent=2),
            status_code=200,
            mimetype="application/json"
        )
        
    except Exception as e:
        logger.error(f"Unexpected error in migration assessment: {str(e)}")
        logger.error(f"Traceback: {traceback.format_exc()}")
        
        return func.HttpResponse(
            json.dumps({
                "status": "error",
                "message": f"Unexpected error processing assessment: {str(e)}",
                "timestamp": datetime.datetime.utcnow().isoformat() + "Z"
            }),
            status_code=500,
            mimetype="application/json"
        )

def generate_ai_insights(client: AzureOpenAI, assessment_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Generate AI insights from assessment data using Azure OpenAI.
    
    Args:
        client: Azure OpenAI client
        assessment_data: Migration assessment data
        
    Returns:
        Dictionary containing AI-generated insights
    """
    
    # Create detailed analysis prompt
    analysis_prompt = create_analysis_prompt(assessment_data)
    
    # Call OpenAI API
    response = client.chat.completions.create(
        model=os.environ["OPENAI_MODEL_DEPLOYMENT"],
        messages=[
            {
                "role": "system", 
                "content": get_system_prompt()
            },
            {
                "role": "user", 
                "content": analysis_prompt
            }
        ],
        max_tokens=3000,
        temperature=0.1,
        top_p=1.0,
        frequency_penalty=0,
        presence_penalty=0
    )
    
    # Parse AI response
    ai_response = response.choices[0].message.content
    
    # Try to parse as JSON, fallback to text if not valid JSON
    try:
        ai_insights = json.loads(ai_response)
    except json.JSONDecodeError:
        ai_insights = {
            "analysis_text": ai_response,
            "format": "text",
            "recommendations": extract_recommendations_from_text(ai_response)
        }
    
    # Add metadata
    ai_insights["metadata"] = {
        "model_used": os.environ["OPENAI_MODEL_DEPLOYMENT"],
        "tokens_used": response.usage.total_tokens,
        "processing_time": datetime.datetime.utcnow().isoformat() + "Z",
        "assessment_servers_count": len(assessment_data.get("servers", [])),
        "assessment_project": assessment_data.get("project", "Unknown")
    }
    
    return ai_insights

def create_analysis_prompt(assessment_data: Dict[str, Any]) -> str:
    """
    Create a detailed analysis prompt for the AI model.
    
    Args:
        assessment_data: Migration assessment data
        
    Returns:
        Formatted prompt string
    """
    
    prompt = f"""
    Analyze the following Azure migration assessment data and provide comprehensive modernization recommendations:

    Assessment Data:
    {json.dumps(assessment_data, indent=2)}

    Please provide your analysis in the following JSON format:
    {{
        "executive_summary": "High-level summary of findings and recommendations",
        "workload_analysis": {{
            "total_servers": number,
            "readiness_assessment": "Overall readiness for Azure migration",
            "complexity_score": "Low/Medium/High",
            "estimated_effort": "Estimated migration effort in weeks"
        }},
        "modernization_opportunities": [
            {{
                "server_name": "server name",
                "current_state": "current configuration",
                "recommended_action": "specific modernization recommendation",
                "azure_service": "recommended Azure service",
                "business_impact": "expected business impact",
                "effort_level": "Low/Medium/High"
            }}
        ],
        "cost_optimization": {{
            "current_estimated_cost": "current monthly cost estimate",
            "optimized_cost": "optimized monthly cost estimate",
            "savings_potential": "potential monthly savings",
            "cost_optimization_strategies": [
                "specific cost optimization recommendations"
            ]
        }},
        "security_considerations": {{
            "current_security_posture": "assessment of current security",
            "azure_security_improvements": [
                "specific security improvements with Azure services"
            ],
            "compliance_recommendations": [
                "compliance and governance recommendations"
            ]
        }},
        "performance_optimization": {{
            "performance_bottlenecks": [
                "identified performance issues"
            ],
            "optimization_recommendations": [
                "specific performance optimization strategies"
            ],
            "azure_performance_services": [
                "Azure services to improve performance"
            ]
        }},
        "risk_assessment": {{
            "migration_risks": [
                "identified risks during migration"
            ],
            "mitigation_strategies": [
                "specific risk mitigation approaches"
            ],
            "success_factors": [
                "key factors for successful migration"
            ]
        }},
        "implementation_roadmap": {{
            "phase1": "immediate actions (0-3 months)",
            "phase2": "short-term improvements (3-6 months)",
            "phase3": "long-term optimization (6-12 months)"
        }},
        "next_steps": [
            "specific actionable next steps"
        ]
    }}

    Focus on practical, actionable recommendations that leverage Azure's native services for modernization, cost optimization, and improved performance.
    """
    
    return prompt

def get_system_prompt() -> str:
    """
    Get the system prompt for the AI model.
    
    Returns:
        System prompt string
    """
    return """
    You are an expert Azure migration architect with deep knowledge of:
    - Azure infrastructure services and best practices
    - Cloud modernization strategies and patterns
    - Cost optimization techniques
    - Security and compliance frameworks
    - Performance optimization approaches
    - Risk assessment and mitigation strategies

    Your role is to analyze migration assessment data and provide intelligent, actionable recommendations for:
    1. Workload modernization opportunities
    2. Cost optimization strategies
    3. Security and compliance improvements
    4. Performance optimization techniques
    5. Risk mitigation approaches
    6. Implementation roadmaps

    Always provide specific, practical recommendations that organizations can implement.
    Focus on Azure-native services and proven cloud patterns.
    Consider both technical and business perspectives in your analysis.
    Provide clear rationale for your recommendations.
    """

def extract_recommendations_from_text(text: str) -> List[str]:
    """
    Extract recommendations from text response when JSON parsing fails.
    
    Args:
        text: AI response text
        
    Returns:
        List of extracted recommendations
    """
    recommendations = []
    
    # Simple extraction logic - look for numbered lists or bullet points
    lines = text.split('\n')
    for line in lines:
        line = line.strip()
        if line.startswith(('1.', '2.', '3.', '4.', '5.', '-', '*')):
            recommendations.append(line)
    
    return recommendations if recommendations else ["Review the full analysis text for detailed recommendations"]

def store_insights_in_blob(insights: Dict[str, Any], assessment_data: Dict[str, Any]) -> str:
    """
    Store AI insights in Azure Blob Storage.
    
    Args:
        insights: AI-generated insights
        assessment_data: Original assessment data
        
    Returns:
        Blob URL where insights are stored
    """
    
    # Initialize blob service client
    blob_service_client = BlobServiceClient.from_connection_string(
        os.environ["STORAGE_CONNECTION_STRING"]
    )
    
    # Create blob name with timestamp
    timestamp = datetime.datetime.utcnow().strftime("%Y%m%d_%H%M%S")
    project_name = assessment_data.get("project", "unknown").replace(" ", "_")
    blob_name = f"assessment_{project_name}_{timestamp}.json"
    
    # Prepare data to store
    storage_data = {
        "assessment_data": assessment_data,
        "ai_insights": insights,
        "processing_metadata": {
            "processed_at": datetime.datetime.utcnow().isoformat() + "Z",
            "function_version": "1.0",
            "model_used": os.environ.get("OPENAI_MODEL_DEPLOYMENT", "unknown")
        }
    }
    
    # Upload to blob storage
    blob_client = blob_service_client.get_blob_client(
        container="ai-insights",
        blob=blob_name
    )
    
    blob_client.upload_blob(
        json.dumps(storage_data, indent=2),
        overwrite=True,
        content_type="application/json"
    )
    
    return blob_client.url