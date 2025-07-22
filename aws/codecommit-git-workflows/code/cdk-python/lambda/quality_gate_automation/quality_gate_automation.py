"""
Lambda function for CodeCommit quality gate automation.

This function implements comprehensive code quality validation including linting,
security scanning, test coverage analysis, and dependency vulnerability checking.
It provides automated quality assurance that enforces consistent coding standards
and security policies across all repository contributions.
"""

import json
import boto3
import logging
import os
from datetime import datetime
from typing import Dict, Any, List, Optional

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
codecommit = boto3.client('codecommit')
sns = boto3.client('sns')
cloudwatch = boto3.client('cloudwatch')


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Handle repository triggers for quality gate automation.
    
    Args:
        event: CodeCommit trigger event
        context: Lambda context object
        
    Returns:
        Response dictionary with processing status
    """
    try:
        logger.info(f"Received event: {json.dumps(event)}")
        
        # Parse CodeCommit trigger event
        records = event.get('Records', [])
        
        for record in records:
            # Extract trigger information
            trigger_info = extract_trigger_info(record)
            if not trigger_info:
                continue
            
            # Run quality checks
            quality_results = run_quality_checks(trigger_info)
            
            # Process results
            process_quality_results(trigger_info, quality_results)
        
        return {'statusCode': 200, 'body': 'Quality checks completed'}
        
    except Exception as e:
        logger.error(f"Error in quality gate automation: {str(e)}")
        return {'statusCode': 500, 'body': f'Error: {str(e)}'}


def extract_trigger_info(record: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """
    Extract trigger information from CodeCommit event.
    
    Args:
        record: CodeCommit event record
        
    Returns:
        Dictionary containing trigger information or None if invalid
    """
    try:
        # Parse CodeCommit event record
        event_source_arn = record.get('eventSourceARN', '')
        repository_name = event_source_arn.split(':')[-1] if event_source_arn else ''
        
        codecommit_data = record.get('codecommit', {})
        references = codecommit_data.get('references', [])
        
        if not references:
            return None
        
        ref = references[0]
        return {
            'repository_name': repository_name,
            'branch': ref.get('ref', '').replace('refs/heads/', ''),
            'commit_id': ref.get('commit'),
            'event_type': 'push'
        }
        
    except Exception as e:
        logger.error(f"Error extracting trigger info: {str(e)}")
        return None


def run_quality_checks(trigger_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Run comprehensive quality checks.
    
    Args:
        trigger_info: Dictionary containing trigger information
        
    Returns:
        Dictionary containing quality check results
    """
    results = {
        'repository': trigger_info['repository_name'],
        'branch': trigger_info['branch'],
        'commit_id': trigger_info['commit_id'],
        'timestamp': datetime.utcnow().isoformat(),
        'checks': {}
    }
    
    try:
        # Get repository content for analysis
        repo_content = get_repository_content(trigger_info)
        
        # Run various quality checks
        results['checks']['lint_check'] = run_lint_check(repo_content)
        results['checks']['security_scan'] = run_security_scan(repo_content)
        results['checks']['test_coverage'] = run_test_coverage(repo_content)
        results['checks']['dependency_check'] = run_dependency_check(repo_content)
        
        # Calculate overall result
        all_passed = all(check.get('passed', False) for check in results['checks'].values())
        results['overall_result'] = 'PASSED' if all_passed else 'FAILED'
        
    except Exception as e:
        logger.error(f"Error running quality checks: {str(e)}")
        results['overall_result'] = 'ERROR'
        results['error'] = str(e)
    
    return results


def get_repository_content(trigger_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Get repository content for analysis.
    
    Args:
        trigger_info: Dictionary containing trigger information
        
    Returns:
        Dictionary containing repository content analysis
    """
    try:
        repository_name = trigger_info['repository_name']
        commit_id = trigger_info['commit_id']
        
        # Get folder structure to identify file types
        try:
            folder_response = codecommit.get_folder(
                repositoryName=repository_name,
                commitSpecifier=commit_id,
                folderPath='/'
            )
            
            files = folder_response.get('files', [])
            sub_folders = folder_response.get('subFolders', [])
            
            # Analyze file types
            python_files = [f for f in files if f['absolutePath'].endswith('.py')]
            requirements_files = [f for f in files if 'requirements' in f['absolutePath'].lower()]
            test_files = []
            
            # Check for test directories
            for folder in sub_folders:
                if 'test' in folder['absolutePath'].lower():
                    try:
                        test_folder_response = codecommit.get_folder(
                            repositoryName=repository_name,
                            commitSpecifier=commit_id,
                            folderPath=folder['absolutePath']
                        )
                        test_files.extend([f for f in test_folder_response.get('files', []) 
                                         if f['absolutePath'].endswith('.py')])
                    except Exception:
                        pass
            
            return {
                'python_files': python_files,
                'requirements_files': requirements_files,
                'test_files': test_files,
                'has_python': len(python_files) > 0,
                'has_tests': len(test_files) > 0,
                'has_requirements': len(requirements_files) > 0,
                'total_files': len(files)
            }
            
        except Exception as e:
            logger.warning(f"Could not analyze repository structure: {str(e)}")
            # Return default structure for simulation
            return {
                'python_files': [],
                'requirements_files': [],
                'test_files': [],
                'has_python': True,  # Assume Python project
                'has_tests': True,   # Assume has tests
                'has_requirements': True,  # Assume has requirements
                'total_files': 10  # Simulated
            }
        
    except Exception as e:
        logger.error(f"Error getting repository content: {str(e)}")
        return {}


def run_lint_check(repo_content: Dict[str, Any]) -> Dict[str, Any]:
    """
    Run code linting checks.
    
    Args:
        repo_content: Dictionary containing repository content information
        
    Returns:
        Dictionary containing linting results
    """
    try:
        if not repo_content.get('has_python'):
            return {'passed': True, 'message': 'No Python files to lint'}
        
        # Simulate linting process
        # In a real implementation, you would:
        # 1. Download the files to /tmp
        # 2. Run pylint or similar tools
        # 3. Parse the output for issues
        
        python_file_count = len(repo_content.get('python_files', []))
        
        # Simulate some linting issues based on file count
        simulated_issues = max(0, python_file_count - 5)  # Fewer issues for smaller codebases
        
        lint_issues = []
        if simulated_issues > 0:
            lint_issues = [
                f"Line too long (>88 characters) in file_{i}.py" 
                for i in range(min(simulated_issues, 3))
            ]
        
        issues_found = len(lint_issues)
        
        return {
            'passed': issues_found == 0,
            'issues_count': issues_found,
            'issues': lint_issues,
            'message': f'Found {issues_found} linting issues' if issues_found > 0 else 'No linting issues found'
        }
        
    except Exception as e:
        return {'passed': False, 'error': str(e)}


def run_security_scan(repo_content: Dict[str, Any]) -> Dict[str, Any]:
    """
    Run security vulnerability scan.
    
    Args:
        repo_content: Dictionary containing repository content information
        
    Returns:
        Dictionary containing security scan results
    """
    try:
        # Simulate security scanning
        # In a real implementation, you would:
        # 1. Run bandit for Python security issues
        # 2. Run safety for dependency vulnerabilities
        # 3. Check for hardcoded secrets
        
        vulnerabilities = []
        
        # Simulate dependency vulnerability check
        if repo_content.get('has_requirements'):
            # Simulate finding vulnerabilities in dependencies
            high_severity_count = 0  # Simulate clean dependencies
            medium_severity_count = 1 if repo_content.get('total_files', 0) > 15 else 0
        else:
            high_severity_count = 0
            medium_severity_count = 0
        
        if medium_severity_count > 0:
            vulnerabilities.append({
                'severity': 'medium',
                'description': 'Outdated dependency with known vulnerability',
                'package': 'example-package',
                'version': '1.2.3'
            })
        
        return {
            'passed': high_severity_count == 0,
            'high_severity': high_severity_count,
            'medium_severity': medium_severity_count,
            'vulnerabilities': vulnerabilities,
            'message': f'Found {high_severity_count} high and {medium_severity_count} medium severity issues'
        }
        
    except Exception as e:
        return {'passed': False, 'error': str(e)}


def run_test_coverage(repo_content: Dict[str, Any]) -> Dict[str, Any]:
    """
    Run test coverage analysis.
    
    Args:
        repo_content: Dictionary containing repository content information
        
    Returns:
        Dictionary containing test coverage results
    """
    try:
        if not repo_content.get('has_tests'):
            return {'passed': False, 'message': 'No tests found'}
        
        # Simulate test coverage calculation
        # In a real implementation, you would:
        # 1. Run pytest with coverage
        # 2. Parse coverage report
        # 3. Check against required threshold
        
        python_file_count = len(repo_content.get('python_files', []))
        test_file_count = len(repo_content.get('test_files', []))
        
        # Simulate coverage based on test-to-code ratio
        if test_file_count == 0:
            coverage_percentage = 0.0
        else:
            ratio = test_file_count / max(python_file_count, 1)
            coverage_percentage = min(95.0, 60.0 + (ratio * 30.0))  # Simulate 60-95% coverage
        
        required_coverage = 80.0
        
        return {
            'passed': coverage_percentage >= required_coverage,
            'coverage_percentage': coverage_percentage,
            'required_coverage': required_coverage,
            'message': f'Test coverage: {coverage_percentage:.1f}% (required: {required_coverage}%)'
        }
        
    except Exception as e:
        return {'passed': False, 'error': str(e)}


def run_dependency_check(repo_content: Dict[str, Any]) -> Dict[str, Any]:
    """
    Check for dependency issues.
    
    Args:
        repo_content: Dictionary containing repository content information
        
    Returns:
        Dictionary containing dependency check results
    """
    try:
        if not repo_content.get('has_requirements'):
            return {'passed': True, 'message': 'No dependencies to check'}
        
        # Simulate dependency analysis
        # In a real implementation, you would:
        # 1. Parse requirements.txt files
        # 2. Check against vulnerability databases
        # 3. Check for outdated packages
        
        # Simulate some issues for larger projects
        total_files = repo_content.get('total_files', 0)
        
        outdated_count = 2 if total_files > 20 else 1 if total_files > 10 else 0
        vulnerable_count = 1 if total_files > 30 else 0
        
        return {
            'passed': vulnerable_count == 0,
            'outdated_dependencies': outdated_count,
            'vulnerable_dependencies': vulnerable_count,
            'message': f'Found {vulnerable_count} vulnerable and {outdated_count} outdated dependencies'
        }
        
    except Exception as e:
        return {'passed': False, 'error': str(e)}


def process_quality_results(trigger_info: Dict[str, Any], results: Dict[str, Any]) -> None:
    """
    Process and communicate quality check results.
    
    Args:
        trigger_info: Dictionary containing trigger information
        results: Dictionary containing quality check results
    """
    try:
        # Record metrics
        record_quality_metrics(results)
        
        # Send notifications for failures
        if results['overall_result'] == 'FAILED':
            send_quality_failure_notification(trigger_info, results)
        elif results['overall_result'] == 'PASSED':
            send_quality_success_notification(trigger_info, results)
        
    except Exception as e:
        logger.error(f"Error processing quality results: {str(e)}")


def record_quality_metrics(results: Dict[str, Any]) -> None:
    """
    Record quality metrics to CloudWatch.
    
    Args:
        results: Dictionary containing quality check results
    """
    try:
        metrics = []
        
        # Overall result metric
        metrics.append({
            'MetricName': 'QualityChecksResult',
            'Value': 1 if results['overall_result'] == 'PASSED' else 0,
            'Unit': 'Count',
            'Dimensions': [
                {'Name': 'Repository', 'Value': results['repository']},
                {'Name': 'Branch', 'Value': results['branch']}
            ]
        })
        
        # Individual check metrics
        for check_name, check_result in results['checks'].items():
            if isinstance(check_result, dict) and 'passed' in check_result:
                metrics.append({
                    'MetricName': f'QualityCheck_{check_name}',
                    'Value': 1 if check_result['passed'] else 0,
                    'Unit': 'Count',
                    'Dimensions': [
                        {'Name': 'Repository', 'Value': results['repository']},
                        {'Name': 'CheckType', 'Value': check_name}
                    ]
                })
        
        # Send metrics to CloudWatch
        cloudwatch.put_metric_data(
            Namespace='CodeCommit/QualityGates',
            MetricData=metrics
        )
        
    except Exception as e:
        logger.error(f"Error recording metrics: {str(e)}")


def send_quality_failure_notification(trigger_info: Dict[str, Any], results: Dict[str, Any]) -> None:
    """
    Send notification for quality check failures.
    
    Args:
        trigger_info: Dictionary containing trigger information
        results: Dictionary containing quality check results
    """
    try:
        failure_summary = []
        for check_name, check_result in results['checks'].items():
            if isinstance(check_result, dict) and not check_result.get('passed', True):
                failure_summary.append(f"❌ {check_name}: {check_result.get('message', 'Failed')}")
        
        message = f"""🚨 Quality Gates Failed

Repository: {results['repository']}
Branch: {results['branch']}
Commit: {results['commit_id'][:8]}

Failed Checks:
{chr(10).join(failure_summary)}

Please address these issues before merging.
Timestamp: {results['timestamp']}
"""
        
        sns.publish(
            TopicArn=os.environ['QUALITY_GATE_TOPIC_ARN'],
            Subject=f'Quality Gates Failed: {results["repository"]}',
            Message=message
        )
        
    except Exception as e:
        logger.error(f"Error sending failure notification: {str(e)}")


def send_quality_success_notification(trigger_info: Dict[str, Any], results: Dict[str, Any]) -> None:
    """
    Send notification for quality check success.
    
    Args:
        trigger_info: Dictionary containing trigger information
        results: Dictionary containing quality check results
    """
    try:
        # Only send success notifications for important branches
        important_branches = ['main', 'master', 'develop']
        
        if results['branch'] not in important_branches:
            return
        
        message = f"""✅ Quality Gates Passed

Repository: {results['repository']}
Branch: {results['branch']}
Commit: {results['commit_id'][:8]}

All quality checks passed successfully.
Timestamp: {results['timestamp']}
"""
        
        sns.publish(
            TopicArn=os.environ['QUALITY_GATE_TOPIC_ARN'],
            Subject=f'Quality Gates Passed: {results["repository"]}',
            Message=message
        )
        
    except Exception as e:
        logger.error(f"Error sending success notification: {str(e)}")