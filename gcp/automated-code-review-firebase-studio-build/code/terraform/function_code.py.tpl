# Cloud Function for Automated Code Review using Gemini AI
# This function processes code changes and provides intelligent review feedback

import json
import os
from datetime import datetime
from google.cloud import tasks_v2
from google.cloud import storage
from google.cloud import logging
import google.generativeai as genai
import functions_framework

# Configuration from template variables
PROJECT_ID = "${project_id}"
REGION = "${region}"
GEMINI_MODEL = "${gemini_model}"
DEBUG_MODE = ${debug_mode}

# Initialize logging client
logging_client = logging.Client()
logger = logging_client.logger('code-review-function')

@functions_framework.http
def analyze_code(request):
    """Analyze code changes and provide review feedback using Gemini AI."""
    
    try:
        # Parse request data
        request_data = request.get_json(silent=True)
        if not request_data:
            logger.error("No JSON data provided in request")
            return {'error': 'No data provided'}, 400
        
        repo_name = request_data.get('repo_name')
        commit_sha = request_data.get('commit_sha')
        file_changes = request_data.get('file_changes', [])
        
        if not repo_name or not commit_sha:
            logger.error("Missing required fields: repo_name or commit_sha")
            return {'error': 'Missing required fields'}, 400
        
        # Configure Gemini AI for code review
        api_key = os.environ.get('GEMINI_API_KEY')
        if not api_key and os.environ.get('GEMINI_ENABLED', 'true').lower() == 'true':
            logger.warning("GEMINI_API_KEY environment variable not set, using mock analysis")
            return generate_mock_analysis(repo_name, commit_sha, file_changes)
            
        if api_key:
            genai.configure(api_key=api_key)
            model = genai.GenerativeModel(GEMINI_MODEL)
        
        review_results = []
        
        for file_change in file_changes:
            file_path = file_change.get('file_path')
            diff_content = file_change.get('diff')
            
            if not file_path or not diff_content:
                continue
            
            try:
                if api_key:
                    # Generate AI-powered review using Gemini
                    prompt = f"""
                    As an expert code reviewer, analyze this code change and provide thorough feedback:
                    
                    File: {file_path}
                    Changes:
                    {diff_content}
                    
                    Please provide a detailed review covering:
                    1. Code quality and adherence to best practices
                    2. Potential bugs, security vulnerabilities, or logic errors
                    3. Performance implications and optimization opportunities
                    4. Code readability and maintainability
                    5. Test coverage recommendations
                    6. Documentation completeness
                    
                    Format your response as structured feedback with specific line references where applicable.
                    Focus on actionable recommendations that improve code quality.
                    """
                    
                    response = model.generate_content(prompt)
                    review_feedback = response.text
                else:
                    # Fallback analysis when Gemini is not available
                    review_feedback = generate_basic_analysis(file_path, diff_content)
                
                review_results.append({
                    'file_path': file_path,
                    'review_feedback': review_feedback,
                    'timestamp': datetime.utcnow().isoformat(),
                    'commit_sha': commit_sha,
                    'status': 'analyzed',
                    'ai_powered': api_key is not None
                })
                
                logger.info(f"Successfully analyzed file: {file_path}")
                
            except Exception as e:
                logger.error(f"Analysis failed for {file_path}: {str(e)}")
                review_results.append({
                    'file_path': file_path,
                    'error': f'Analysis failed: {str(e)}',
                    'commit_sha': commit_sha,
                    'status': 'error'
                })
        
        response_data = {
            'status': 'success',
            'repo_name': repo_name,
            'commit_sha': commit_sha,
            'review_results': review_results,
            'total_files_analyzed': len([r for r in review_results if r.get('status') == 'analyzed']),
            'timestamp': datetime.utcnow().isoformat(),
            'debug_mode': DEBUG_MODE
        }
        
        logger.info(f"Code review completed for {repo_name}:{commit_sha}")
        return response_data
        
    except Exception as e:
        logger.error(f"Unhandled error in analyze_code: {str(e)}")
        return {'error': 'Internal server error'}, 500

def generate_mock_analysis(repo_name, commit_sha, file_changes):
    """Generate mock analysis when Gemini AI is not available."""
    
    review_results = []
    
    for file_change in file_changes:
        file_path = file_change.get('file_path', 'unknown')
        diff_content = file_change.get('diff', '')
        
        # Basic static analysis
        feedback = generate_basic_analysis(file_path, diff_content)
        
        review_results.append({
            'file_path': file_path,
            'review_feedback': feedback,
            'timestamp': datetime.utcnow().isoformat(),
            'commit_sha': commit_sha,
            'status': 'analyzed',
            'ai_powered': False
        })
    
    return {
        'status': 'success',
        'repo_name': repo_name,
        'commit_sha': commit_sha,
        'review_results': review_results,
        'total_files_analyzed': len(review_results),
        'timestamp': datetime.utcnow().isoformat(),
        'note': 'Using mock analysis - Gemini AI not configured'
    }

def generate_basic_analysis(file_path, diff_content):
    """Generate basic code analysis without AI."""
    
    analysis_points = []
    
    # File extension based analysis
    if file_path.endswith('.py'):
        analysis_points.append("Python file detected - ensure PEP 8 compliance")
        if 'import' in diff_content:
            analysis_points.append("Review import statements for optimization")
    elif file_path.endswith('.js') or file_path.endswith('.ts'):
        analysis_points.append("JavaScript/TypeScript file - check for ESLint compliance")
        if 'console.log' in diff_content:
            analysis_points.append("Consider removing console.log statements in production")
    elif file_path.endswith('.yaml') or file_path.endswith('.yml'):
        analysis_points.append("YAML configuration file - validate syntax and structure")
    
    # Common code patterns
    if 'TODO' in diff_content or 'FIXME' in diff_content:
        analysis_points.append("TODO/FIXME comments found - address before merging")
    
    if 'password' in diff_content.lower() or 'secret' in diff_content.lower():
        analysis_points.append("⚠️ Potential security issue: hardcoded credentials detected")
    
    if len(diff_content.split('\n')) > 100:
        analysis_points.append("Large changeset detected - consider breaking into smaller commits")
    
    # Default analysis if no specific patterns found
    if not analysis_points:
        analysis_points.append("Code changes look reasonable - consider adding tests if not present")
    
    return "\n".join([f"• {point}" for point in analysis_points])