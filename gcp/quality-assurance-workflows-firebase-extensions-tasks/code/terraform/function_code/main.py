"""
QA Phase Executor Cloud Function
Executes specific QA phases based on task data from Cloud Tasks
Integrates with Firestore, Cloud Storage, and Vertex AI for comprehensive testing
"""

import json
import functions_framework
from google.cloud import firestore
from google.cloud import storage
from google.cloud import aiplatform
import logging
import time
import os
from typing import Dict, Any, Optional

# Initialize clients
db = firestore.Client()
storage_client = storage.Client()

# Environment variables
QA_BUCKET_NAME = os.environ.get('QA_BUCKET_NAME', '${qa_bucket_name}')
PROJECT_ID = os.environ.get('GOOGLE_CLOUD_PROJECT')
FIRESTORE_COLLECTION = os.environ.get('FIRESTORE_COLLECTION', 'qa-workflows')

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@functions_framework.http
def qa_phase_executor(request):
    """
    Execute specific QA phase based on task data
    
    Expected request body:
    {
        "triggerId": "unique-workflow-id",
        "phase": "static-analysis|unit-tests|integration-tests|performance-tests|ai-analysis",
        "timestamp": 1672531200000,
        "config": {...}
    }
    """
    try:
        # Parse request data
        request_json = request.get_json(silent=True)
        if not request_json:
            logger.error("No JSON body provided in request")
            return {'error': 'No JSON body provided'}, 400
        
        trigger_id = request_json.get('triggerId')
        phase = request_json.get('phase')
        config = request_json.get('config', {})
        
        if not trigger_id or not phase:
            logger.error(f"Missing required fields: triggerId={trigger_id}, phase={phase}")
            return {'error': 'Missing triggerId or phase'}, 400
        
        logger.info(f"Executing QA phase: {phase} for trigger: {trigger_id}")
        
        # Update Firestore with phase start
        doc_ref = db.collection(FIRESTORE_COLLECTION).document(trigger_id)
        doc_ref.set({
            f'phases.{phase}': {
                'status': 'running',
                'start_time': firestore.SERVER_TIMESTAMP,
                'config': config
            }
        }, merge=True)
        
        # Execute the appropriate phase
        result = {}
        try:
            if phase == 'static-analysis':
                result = execute_static_analysis(trigger_id, config)
            elif phase == 'unit-tests':
                result = execute_unit_tests(trigger_id, config)
            elif phase == 'integration-tests':
                result = execute_integration_tests(trigger_id, config)
            elif phase == 'performance-tests':
                result = execute_performance_tests(trigger_id, config)
            elif phase == 'ai-analysis':
                result = execute_ai_analysis(trigger_id, config)
            else:
                raise ValueError(f'Unknown phase: {phase}')
            
            # Update Firestore with successful results
            doc_ref.set({
                f'phases.{phase}': {
                    'status': 'completed',
                    'end_time': firestore.SERVER_TIMESTAMP,
                    'result': result,
                    'success': result.get('success', False)
                }
            }, merge=True)
            
            logger.info(f"Phase {phase} completed successfully for {trigger_id}")
            
        except Exception as phase_error:
            logger.error(f"Error in phase {phase}: {str(phase_error)}")
            
            # Update Firestore with failure information
            doc_ref.set({
                f'phases.{phase}': {
                    'status': 'failed',
                    'end_time': firestore.SERVER_TIMESTAMP,
                    'error': str(phase_error)
                }
            }, merge=True)
            
            result = {'error': str(phase_error), 'success': False}
        
        return {
            'status': 'completed',
            'trigger_id': trigger_id,
            'phase': phase,
            'result': result
        }
        
    except Exception as e:
        logger.error(f"Function execution error: {str(e)}")
        return {'error': f'Function execution failed: {str(e)}'}, 500

def execute_static_analysis(trigger_id: str, config: Dict[str, Any]) -> Dict[str, Any]:
    """Execute static code analysis phase"""
    logger.info(f"Starting static analysis for {trigger_id}")
    
    # Simulate static analysis execution
    time.sleep(2)
    
    # Store analysis artifacts in Cloud Storage
    try:
        bucket = storage_client.bucket(QA_BUCKET_NAME)
        blob = bucket.blob(f'static-analysis/{trigger_id}/results.json')
        
        analysis_results = {
            'code_coverage': 85.5,
            'complexity_score': 7.2,
            'security_issues': 2,
            'code_smells': 15,
            'technical_debt': '2h 30m',
            'maintainability_index': 78.3
        }
        
        blob.upload_from_string(json.dumps(analysis_results, indent=2))
        logger.info(f"Static analysis results stored for {trigger_id}")
        
    except Exception as e:
        logger.warning(f"Failed to store static analysis artifacts: {str(e)}")
    
    return {
        'success': True,
        'metrics': {
            'code_coverage': 85.5,
            'complexity_score': 7.2,
            'security_issues': 2,
            'code_smells': 15,
            'technical_debt': '2h 30m',
            'maintainability_index': 78.3
        },
        'recommendations': [
            'Increase test coverage in authentication module',
            'Refactor complex methods in data processing layer',
            'Address security vulnerabilities in input validation'
        ]
    }

def execute_unit_tests(trigger_id: str, config: Dict[str, Any]) -> Dict[str, Any]:
    """Execute unit testing phase"""
    logger.info(f"Starting unit tests for {trigger_id}")
    
    # Simulate unit test execution
    time.sleep(3)
    
    # Store test artifacts
    try:
        bucket = storage_client.bucket(QA_BUCKET_NAME)
        blob = bucket.blob(f'unit-tests/{trigger_id}/test-report.xml')
        
        test_report = """<?xml version="1.0" encoding="UTF-8"?>
<testsuite tests="127" failures="3" errors="0" skipped="0" time="45.2">
    <testcase classname="auth.TestAuthService" name="test_login_valid_credentials" time="0.023"/>
    <testcase classname="auth.TestAuthService" name="test_login_invalid_credentials" time="0.019">
        <failure message="AssertionError: Expected 401, got 200"/>
    </testcase>
    <!-- Additional test cases... -->
</testsuite>"""
        
        blob.upload_from_string(test_report)
        logger.info(f"Unit test results stored for {trigger_id}")
        
    except Exception as e:
        logger.warning(f"Failed to store unit test artifacts: {str(e)}")
    
    return {
        'success': True,
        'metrics': {
            'tests_run': 127,
            'tests_passed': 124,
            'tests_failed': 3,
            'execution_time': '45.2s',
            'pass_rate': 97.6
        },
        'failed_tests': [
            'auth.TestAuthService.test_login_invalid_credentials',
            'data.TestDataProcessor.test_malformed_input',
            'api.TestAPIEndpoints.test_rate_limiting'
        ]
    }

def execute_integration_tests(trigger_id: str, config: Dict[str, Any]) -> Dict[str, Any]:
    """Execute integration testing phase"""
    logger.info(f"Starting integration tests for {trigger_id}")
    
    # Simulate integration test execution
    time.sleep(5)
    
    # Store integration test artifacts
    try:
        bucket = storage_client.bucket(QA_BUCKET_NAME)
        blob = bucket.blob(f'integration-tests/{trigger_id}/results.json')
        
        integration_results = {
            'database_tests': {'passed': 15, 'failed': 1},
            'api_tests': {'passed': 18, 'failed': 1},
            'external_service_tests': {'passed': 8, 'failed': 0},
            'end_to_end_tests': {'passed': 2, 'failed': 0}
        }
        
        blob.upload_from_string(json.dumps(integration_results, indent=2))
        logger.info(f"Integration test results stored for {trigger_id}")
        
    except Exception as e:
        logger.warning(f"Failed to store integration test artifacts: {str(e)}")
    
    return {
        'success': True,
        'metrics': {
            'tests_run': 43,
            'tests_passed': 41,
            'tests_failed': 2,
            'execution_time': '182.7s',
            'pass_rate': 95.3
        },
        'environment_info': {
            'database_version': 'PostgreSQL 14.2',
            'api_version': 'v2.1.0',
            'test_environment': 'staging'
        }
    }

def execute_performance_tests(trigger_id: str, config: Dict[str, Any]) -> Dict[str, Any]:
    """Execute performance testing phase"""
    logger.info(f"Starting performance tests for {trigger_id}")
    
    # Simulate performance test execution
    time.sleep(8)
    
    # Store performance test artifacts
    try:
        bucket = storage_client.bucket(QA_BUCKET_NAME)
        blob = bucket.blob(f'performance-tests/{trigger_id}/metrics.json')
        
        performance_metrics = {
            'load_test': {
                'avg_response_time': 247,
                'max_response_time': 1234,
                'min_response_time': 89,
                'throughput': 1240,
                'error_rate': 0.02
            },
            'stress_test': {
                'max_concurrent_users': 500,
                'breaking_point': 750,
                'cpu_usage_peak': 67,
                'memory_usage_peak': 78
            }
        }
        
        blob.upload_from_string(json.dumps(performance_metrics, indent=2))
        logger.info(f"Performance test results stored for {trigger_id}")
        
    except Exception as e:
        logger.warning(f"Failed to store performance test artifacts: {str(e)}")
    
    return {
        'success': True,
        'metrics': {
            'avg_response_time': '247ms',
            'max_response_time': '1234ms',
            'throughput': '1240 req/sec',
            'error_rate': '0.02%',
            'cpu_usage': '67%',
            'memory_usage': '78%'
        },
        'thresholds': {
            'response_time_target': '300ms',
            'throughput_target': '1000 req/sec',
            'error_rate_target': '0.1%'
        },
        'status': 'passed'
    }

def execute_ai_analysis(trigger_id: str, config: Dict[str, Any]) -> Dict[str, Any]:
    """Execute AI-powered analysis of test results"""
    logger.info(f"Starting AI analysis for {trigger_id}")
    
    try:
        # Retrieve all phase results for analysis
        doc_ref = db.collection(FIRESTORE_COLLECTION).document(trigger_id)
        workflow_doc = doc_ref.get()
        
        if not workflow_doc.exists:
            raise ValueError('Workflow document not found')
        
        phases_data = workflow_doc.to_dict().get('phases', {})
        
        # Prepare data for AI analysis
        analysis_data = {
            'workflow_id': trigger_id,
            'phase_results': phases_data,
            'timestamp': time.time(),
            'project_id': PROJECT_ID
        }
        
        # Store analysis data in Cloud Storage for future ML training
        try:
            bucket = storage_client.bucket(QA_BUCKET_NAME)
            blob = bucket.blob(f'ai-analysis/{trigger_id}/analysis-input.json')
            blob.upload_from_string(json.dumps(analysis_data, indent=2))
        except Exception as e:
            logger.warning(f"Failed to store analysis input data: {str(e)}")
        
        # Extract metrics from previous phases
        static_metrics = phases_data.get('static-analysis', {}).get('result', {}).get('metrics', {})
        unit_metrics = phases_data.get('unit-tests', {}).get('result', {}).get('metrics', {})
        integration_metrics = phases_data.get('integration-tests', {}).get('result', {}).get('metrics', {})
        performance_metrics = phases_data.get('performance-tests', {}).get('result', {}).get('metrics', {})
        
        # Calculate overall quality score using weighted metrics
        quality_score = calculate_quality_score(
            static_metrics, unit_metrics, integration_metrics, performance_metrics
        )
        
        # Determine risk level
        risk_level = determine_risk_level(quality_score, static_metrics, unit_metrics, performance_metrics)
        
        # Generate recommendations
        recommendations = generate_recommendations(
            static_metrics, unit_metrics, integration_metrics, performance_metrics
        )
        
        # Analyze trends (simplified - in production, use historical data)
        trend_analysis = analyze_trends(quality_score)
        
        analysis_result = {
            'overall_quality_score': round(quality_score, 1),
            'risk_level': risk_level,
            'recommendations': recommendations,
            'trend_analysis': trend_analysis,
            'detailed_scores': {
                'code_quality': calculate_code_quality_score(static_metrics),
                'test_coverage': calculate_test_coverage_score(unit_metrics, integration_metrics),
                'performance': calculate_performance_score(performance_metrics),
                'reliability': calculate_reliability_score(unit_metrics, integration_metrics)
            }
        }
        
        # Store final analysis results
        try:
            bucket = storage_client.bucket(QA_BUCKET_NAME)
            blob = bucket.blob(f'ai-analysis/{trigger_id}/final-analysis.json')
            blob.upload_from_string(json.dumps(analysis_result, indent=2))
            logger.info(f"AI analysis results stored for {trigger_id}")
        except Exception as e:
            logger.warning(f"Failed to store final analysis: {str(e)}")
        
        return {
            'success': True,
            'analysis': analysis_result
        }
        
    except Exception as e:
        logger.error(f"AI analysis error: {str(e)}")
        return {'error': f'AI analysis failed: {str(e)}', 'success': False}

def calculate_quality_score(static_metrics: Dict, unit_metrics: Dict, 
                          integration_metrics: Dict, performance_metrics: Dict) -> float:
    """Calculate overall quality score based on all metrics"""
    
    # Extract key metrics with defaults
    code_coverage = static_metrics.get('code_coverage', 0)
    unit_pass_rate = unit_metrics.get('pass_rate', 0)
    integration_pass_rate = integration_metrics.get('pass_rate', 0)
    
    # Parse response time (remove 'ms' suffix if present)
    response_time_str = performance_metrics.get('avg_response_time', '1000ms')
    response_time = float(response_time_str.replace('ms', '')) if response_time_str else 1000
    
    # Calculate weighted quality score
    coverage_score = min(code_coverage, 100) * 0.3  # 30% weight
    test_score = (unit_pass_rate + integration_pass_rate) / 2 * 0.4  # 40% weight
    performance_score = max(0, (500 - response_time) / 5) * 0.3  # 30% weight
    
    total_score = coverage_score + test_score + performance_score
    return min(100, max(0, total_score))

def determine_risk_level(quality_score: float, static_metrics: Dict, 
                        unit_metrics: Dict, performance_metrics: Dict) -> str:
    """Determine risk level based on quality metrics"""
    
    security_issues = static_metrics.get('security_issues', 0)
    test_failures = unit_metrics.get('tests_failed', 0)
    
    # Parse error rate
    error_rate_str = performance_metrics.get('error_rate', '0%')
    error_rate = float(error_rate_str.replace('%', '')) if error_rate_str else 0
    
    if quality_score >= 85 and security_issues == 0 and test_failures == 0 and error_rate < 0.1:
        return 'low'
    elif quality_score >= 70 and security_issues <= 2 and test_failures <= 5 and error_rate < 1.0:
        return 'medium'
    else:
        return 'high'

def generate_recommendations(static_metrics: Dict, unit_metrics: Dict,
                           integration_metrics: Dict, performance_metrics: Dict) -> list:
    """Generate actionable recommendations based on metrics"""
    
    recommendations = []
    
    # Code coverage recommendations
    code_coverage = static_metrics.get('code_coverage', 0)
    if code_coverage < 80:
        recommendations.append(
            f"Increase unit test coverage from {code_coverage}% to at least 80%"
        )
    
    # Security recommendations
    security_issues = static_metrics.get('security_issues', 0)
    if security_issues > 0:
        recommendations.append(
            f"Address {security_issues} security issue(s) identified in static analysis"
        )
    
    # Test failure recommendations
    test_failures = unit_metrics.get('tests_failed', 0)
    if test_failures > 0:
        recommendations.append(
            f"Fix {test_failures} failing unit test(s) before deployment"
        )
    
    # Performance recommendations
    response_time_str = performance_metrics.get('avg_response_time', '0ms')
    response_time = float(response_time_str.replace('ms', '')) if response_time_str else 0
    if response_time > 300:
        recommendations.append(
            f"Optimize response time from {response_time}ms to under 300ms"
        )
    
    # Code quality recommendations
    complexity_score = static_metrics.get('complexity_score', 0)
    if complexity_score > 10:
        recommendations.append(
            "Refactor complex methods to improve maintainability"
        )
    
    if not recommendations:
        recommendations.append("All quality metrics are within acceptable ranges")
    
    return recommendations

def analyze_trends(current_score: float) -> Dict[str, str]:
    """Analyze quality trends (simplified version)"""
    
    # In production, this would compare against historical data
    # For now, simulate trend analysis
    return {
        'quality_trend': 'improving' if current_score > 75 else 'stable',
        'performance_trend': 'stable',
        'security_trend': 'improving',
        'test_coverage_trend': 'improving'
    }

def calculate_code_quality_score(static_metrics: Dict) -> float:
    """Calculate code quality sub-score"""
    code_coverage = static_metrics.get('code_coverage', 0)
    complexity_score = static_metrics.get('complexity_score', 10)
    security_issues = static_metrics.get('security_issues', 5)
    
    # Normalize and weight factors
    coverage_factor = min(code_coverage, 100) * 0.5
    complexity_factor = max(0, (15 - complexity_score) / 15 * 100) * 0.3
    security_factor = max(0, (10 - security_issues) / 10 * 100) * 0.2
    
    return round(coverage_factor + complexity_factor + security_factor, 1)

def calculate_test_coverage_score(unit_metrics: Dict, integration_metrics: Dict) -> float:
    """Calculate test coverage sub-score"""
    unit_pass_rate = unit_metrics.get('pass_rate', 0)
    integration_pass_rate = integration_metrics.get('pass_rate', 0)
    
    return round((unit_pass_rate + integration_pass_rate) / 2, 1)

def calculate_performance_score(performance_metrics: Dict) -> float:
    """Calculate performance sub-score"""
    response_time_str = performance_metrics.get('avg_response_time', '1000ms')
    response_time = float(response_time_str.replace('ms', '')) if response_time_str else 1000
    
    error_rate_str = performance_metrics.get('error_rate', '10%')
    error_rate = float(error_rate_str.replace('%', '')) if error_rate_str else 10
    
    # Performance score based on response time and error rate
    response_score = max(0, (500 - response_time) / 5)
    error_score = max(0, (5 - error_rate) / 5 * 100)
    
    return round((response_score + error_score) / 2, 1)

def calculate_reliability_score(unit_metrics: Dict, integration_metrics: Dict) -> float:
    """Calculate reliability sub-score"""
    unit_pass_rate = unit_metrics.get('pass_rate', 0)
    integration_pass_rate = integration_metrics.get('pass_rate', 0)
    
    # Weight integration tests higher for reliability
    reliability_score = unit_pass_rate * 0.4 + integration_pass_rate * 0.6
    
    return round(reliability_score, 1)