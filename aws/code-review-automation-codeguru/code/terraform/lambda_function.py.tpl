import json
import boto3
import os
from typing import Dict, List, Any

def handler(event, context):
    """
    Lambda function to enforce code quality gates based on CodeGuru Reviewer recommendations.
    
    This function analyzes CodeGuru recommendations and determines if code changes
    meet quality standards based on severity thresholds.
    """
    
    # Initialize AWS clients
    codeguru_client = boto3.client('codeguru-reviewer')
    
    # Get configuration from environment variables
    max_severity_threshold = os.environ.get('MAX_SEVERITY_THRESHOLD', '${max_severity_threshold}')
    
    try:
        # Extract code review ARN from event
        code_review_arn = event.get('code_review_arn')
        if not code_review_arn:
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': 'Missing code_review_arn in event',
                    'success': False
                })
            }
        
        # Get code review details
        code_review_response = codeguru_client.describe_code_review(
            CodeReviewArn=code_review_arn
        )
        
        # Get recommendations
        recommendations_response = codeguru_client.list_recommendations(
            CodeReviewArn=code_review_arn
        )
        
        recommendations = recommendations_response.get('RecommendationSummaries', [])
        
        # Analyze recommendations by severity
        severity_counts = analyze_recommendations(recommendations)
        
        # Determine if quality gate passes
        quality_gate_result = evaluate_quality_gate(severity_counts, max_severity_threshold)
        
        # Prepare response
        response_body = {
            'code_review_arn': code_review_arn,
            'code_review_state': code_review_response['CodeReview']['State'],
            'severity_counts': severity_counts,
            'max_severity_threshold': max_severity_threshold,
            'quality_gate_passed': quality_gate_result['passed'],
            'quality_gate_message': quality_gate_result['message'],
            'recommendations_count': len(recommendations),
            'success': True
        }
        
        return {
            'statusCode': 200 if quality_gate_result['passed'] else 422,
            'body': json.dumps(response_body, indent=2)
        }
        
    except Exception as e:
        error_response = {
            'error': str(e),
            'success': False
        }
        
        return {
            'statusCode': 500,
            'body': json.dumps(error_response)
        }

def analyze_recommendations(recommendations: List[Dict[str, Any]]) -> Dict[str, int]:
    """
    Analyze recommendations and count by severity level.
    
    Args:
        recommendations: List of CodeGuru recommendations
        
    Returns:
        Dictionary with severity level counts
    """
    severity_counts = {
        'INFO': 0,
        'LOW': 0,
        'MEDIUM': 0,
        'HIGH': 0,
        'CRITICAL': 0
    }
    
    for recommendation in recommendations:
        severity = recommendation.get('Severity', 'INFO')
        if severity in severity_counts:
            severity_counts[severity] += 1
    
    return severity_counts

def evaluate_quality_gate(severity_counts: Dict[str, int], max_threshold: str) -> Dict[str, Any]:
    """
    Evaluate if code meets quality gate criteria.
    
    Args:
        severity_counts: Dictionary with severity level counts
        max_threshold: Maximum allowed severity level
        
    Returns:
        Dictionary with quality gate result
    """
    # Define severity hierarchy (higher index = more severe)
    severity_levels = ['INFO', 'LOW', 'MEDIUM', 'HIGH', 'CRITICAL']
    threshold_index = severity_levels.index(max_threshold)
    
    # Check for violations above threshold
    violations = []
    for i, severity in enumerate(severity_levels):
        if i > threshold_index and severity_counts[severity] > 0:
            violations.append(f"{severity_counts[severity]} {severity} severity issues")
    
    if violations:
        return {
            'passed': False,
            'message': f"Quality gate failed: Found {', '.join(violations)} (threshold: {max_threshold})"
        }
    else:
        total_issues = sum(severity_counts.values())
        return {
            'passed': True,
            'message': f"Quality gate passed: {total_issues} total issues, none above {max_threshold} severity"
        }

def provide_recommendation_feedback(codeguru_client, code_review_arn: str, recommendations: List[Dict[str, Any]]):
    """
    Provide feedback on recommendations to improve CodeGuru's ML models.
    
    Args:
        codeguru_client: Boto3 CodeGuru client
        code_review_arn: ARN of the code review
        recommendations: List of recommendations to provide feedback on
    """
    for recommendation in recommendations:
        try:
            # Provide thumbs up feedback for all recommendations by default
            # In a real implementation, you might have more sophisticated logic
            codeguru_client.put_recommendation_feedback(
                CodeReviewArn=code_review_arn,
                RecommendationId=recommendation['RecommendationId'],
                Reactions=['ThumbsUp']
            )
        except Exception as e:
            print(f"Failed to provide feedback for recommendation {recommendation['RecommendationId']}: {str(e)}")