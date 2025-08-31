import functions_framework
from google.cloud import documentai_v1 as documentai
from google.cloud import aiplatform
from google.cloud import storage
import json
import os
import re
from typing import Dict, List

# Initialize clients
storage_client = storage.Client()
docai_client = documentai.DocumentProcessorServiceClient()

@functions_framework.cloud_event
def analyze_contract_security(cloud_event):
    """Analyze smart contract for security vulnerabilities using Document AI and Vertex AI"""
    
    # Extract file information from Cloud Storage event
    data = cloud_event.data
    bucket_name = data['bucket']
    file_name = data['name']
    
    print(f"Processing contract file: {file_name}")
    
    # Skip non-contract files and audit reports
    if not file_name.endswith(('.sol', '.txt', '.md', '.pdf')) or 'audit-reports/' in file_name:
        print(f"Skipping non-contract file: {file_name}")
        return
    
    # Download contract file from Cloud Storage
    bucket = storage_client.bucket(bucket_name)
    blob = bucket.blob(file_name)
    
    try:
        # Extract text using Document AI
        extracted_text = process_with_document_ai(blob)
        
        # Analyze for security vulnerabilities using Vertex AI
        vulnerability_report = analyze_with_vertex_ai(extracted_text, file_name)
        
        # Save audit report to Cloud Storage
        save_audit_report(bucket, file_name, vulnerability_report)
        
        print(f"Security analysis completed for: {file_name}")
        
    except Exception as e:
        print(f"Error processing {file_name}: {str(e)}")
        error_report = {
            "contract_name": file_name,
            "error": str(e),
            "status": "Analysis Failed"
        }
        save_audit_report(bucket, file_name, error_report)

def process_with_document_ai(blob) -> str:
    """Extract text from contract file using Document AI"""
    
    project_id = os.environ.get('GCP_PROJECT')
    location = os.environ.get('PROCESSOR_LOCATION', 'us-central1')
    processor_id = os.environ.get('PROCESSOR_ID')
    
    # Read file content
    file_content = blob.download_as_bytes()
    
    # Create Document AI request
    name = processor_id  # Already in full format from Terraform
    
    request = documentai.ProcessRequest(
        name=name,
        raw_document=documentai.RawDocument(
            content=file_content,
            mime_type=get_mime_type(blob.name)
        )
    )
    
    # Process document
    result = docai_client.process_document(request=request)
    document = result.document
    
    return document.text

def get_mime_type(filename: str) -> str:
    """Determine MIME type based on file extension"""
    
    if filename.endswith('.pdf'):
        return 'application/pdf'
    elif filename.endswith(('.sol', '.txt', '.md')):
        return 'text/plain'
    else:
        return 'application/octet-stream'

def analyze_with_vertex_ai(contract_text: str, filename: str) -> Dict:
    """Analyze contract for security vulnerabilities using Vertex AI"""
    
    # Initialize Vertex AI
    aiplatform.init(
        project=os.environ.get('GCP_PROJECT'), 
        location=os.environ.get('PROCESSOR_LOCATION', 'us-central1')
    )
    
    # Security analysis prompt based on OWASP Smart Contract Top 10
    security_prompt = f"""
    Analyze the following smart contract for security vulnerabilities based on the OWASP Smart Contract Top 10 (2025):

    Contract File: {filename}
    Contract Code:
    {contract_text}

    Please identify and analyze potential vulnerabilities in these categories:
    1. Access Control Flaws - Check for missing or improper access modifiers
    2. Logic Errors - Look for calculation errors, race conditions, or flawed business logic
    3. Lack of Input Validation - Identify missing input checks and validation
    4. Reentrancy Vulnerabilities - Check for state changes after external calls
    5. Integer Overflow/Underflow - Look for arithmetic operations without safe math
    6. Gas Limit Issues - Identify unbounded loops or expensive operations
    7. Timestamp Dependence - Check for reliance on block.timestamp
    8. Front-running Vulnerabilities - Look for transaction ordering dependencies
    9. Denial of Service - Identify potential DoS attack vectors
    10. Cryptographic Issues - Check for weak randomness or poor key management

    For each vulnerability found, provide:
    - Severity Level (Critical/High/Medium/Low)
    - Line numbers or code sections affected
    - Detailed explanation of the vulnerability
    - Recommended remediation steps
    - Code examples of secure alternatives

    Format your response as JSON with the following structure:
    {{
        "contract_name": "{filename}",
        "overall_risk_score": "1-10",
        "vulnerabilities_found": [
            {{
                "type": "vulnerability_type",
                "severity": "Critical/High/Medium/Low",
                "location": "line_numbers_or_function_name",
                "description": "detailed_explanation",
                "remediation": "recommended_fix",
                "code_example": "secure_alternative_code"
            }}
        ],
        "recommendations": ["list", "of", "general", "recommendations"],
        "compliance_status": "Pass/Fail/Needs Review",
        "analysis_timestamp": "{filename} analyzed on $(date)"
    }}
    """
    
    try:
        # Use Gemini for analysis
        from vertexai.generative_models import GenerativeModel
        
        model = GenerativeModel("${vertex_ai_model}")
        response = model.generate_content(security_prompt)
        
        # Parse response as JSON
        try:
            # Clean the response text to extract JSON
            response_text = response.text.strip()
            
            # Find JSON content between code blocks if present
            if "```json" in response_text:
                start = response_text.find("```json") + 7
                end = response_text.find("```", start)
                response_text = response_text[start:end].strip()
            elif "```" in response_text:
                start = response_text.find("```") + 3
                end = response_text.rfind("```")
                response_text = response_text[start:end].strip()
            
            vulnerability_report = json.loads(response_text)
            
        except json.JSONDecodeError as e:
            print(f"JSON parsing error: {str(e)}")
            # Fallback if response isn't valid JSON
            vulnerability_report = {
                "contract_name": filename,
                "overall_risk_score": "5",
                "vulnerabilities_found": [
                    {
                        "type": "Analysis Output",
                        "severity": "Unknown",
                        "location": "Full Contract",
                        "description": response.text,
                        "remediation": "Review the analysis above for detailed findings",
                        "code_example": "See recommendations in description"
                    }
                ],
                "recommendations": ["Review the analysis above for detailed findings"],
                "compliance_status": "Needs Review",
                "analysis_timestamp": f"{filename} analyzed with parsing errors"
            }
        
        return vulnerability_report
        
    except Exception as e:
        print(f"Error in Vertex AI analysis: {str(e)}")
        return {
            "contract_name": filename,
            "error": str(e),
            "status": "Analysis Failed",
            "analysis_timestamp": f"{filename} analysis failed"
        }

def save_audit_report(bucket, original_filename: str, report: Dict):
    """Save security audit report to Cloud Storage"""
    
    # Create report filename
    base_name = original_filename.replace('/', '_').split('.')[0]
    report_filename = f"audit-reports/{base_name}_security_audit.json"
    
    # Upload report to Cloud Storage
    report_blob = bucket.blob(report_filename)
    report_blob.upload_from_string(
        json.dumps(report, indent=2),
        content_type='application/json'
    )
    
    print(f"Audit report saved: {report_filename}")
    
    # Log summary to Cloud Logging
    if 'vulnerabilities_found' in report:
        vuln_count = len(report['vulnerabilities_found'])
        risk_score = report.get('overall_risk_score', 'Unknown')
        print(f"Contract analysis summary - File: {original_filename}, Vulnerabilities: {vuln_count}, Risk Score: {risk_score}")
    elif 'error' in report:
        print(f"Contract analysis failed - File: {original_filename}, Error: {report['error']}")