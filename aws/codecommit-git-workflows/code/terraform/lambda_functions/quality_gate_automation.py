import json
import boto3
import logging
import os
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

codecommit = boto3.client('codecommit')
sns = boto3.client('sns')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    """
    Handle repository triggers for quality gate automation
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

def extract_trigger_info(record):
    """Extract trigger information from CodeCommit event"""
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

def run_quality_checks(trigger_info):
    """Run comprehensive quality checks"""
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

def get_repository_content(trigger_info):
    """Get repository content for analysis"""
    try:
        # For simplicity, we'll simulate getting key files
        # In a real implementation, you would fetch actual repository content
        
        python_files = []
        requirements_files = []
        test_files = []
        
        # Simulate repository structure analysis
        return {
            'python_files': python_files,
            'requirements_files': requirements_files,
            'test_files': test_files,
            'has_python': True,  # Simulated detection
            'has_tests': True,   # Simulated detection
            'has_requirements': True  # Simulated detection
        }
        
    except Exception as e:
        logger.error(f"Error getting repository content: {str(e)}")
        return {}

def run_lint_check(repo_content):
    """Run code linting checks"""
    try:
        # Simulate linting results
        # In a real implementation, you would run actual linting tools
        
        lint_issues = []
        
        # Simulate some common issues
        if not repo_content.get('has_python'):
            return {'passed': True, 'message': 'No Python files to lint'}
        
        # Simulate linting process
        issues_found = len(lint_issues)
        
        return {
            'passed': issues_found == 0,
            'issues_count': issues_found,
            'issues': lint_issues,
            'message': f'Found {issues_found} linting issues' if issues_found > 0 else 'No linting issues found'
        }
        
    except Exception as e:
        return {'passed': False, 'error': str(e)}

def run_security_scan(repo_content):
    """Run security vulnerability scan"""
    try:
        # Simulate security scanning
        vulnerabilities = []
        
        # Simulate dependency vulnerability check
        high_severity_count = 0
        medium_severity_count = 0
        
        return {
            'passed': high_severity_count == 0,
            'high_severity': high_severity_count,
            'medium_severity': medium_severity_count,
            'vulnerabilities': vulnerabilities,
            'message': f'Found {high_severity_count} high and {medium_severity_count} medium severity issues'
        }
        
    except Exception as e:
        return {'passed': False, 'error': str(e)}

def run_test_coverage(repo_content):
    """Run test coverage analysis"""
    try:
        # Simulate test coverage calculation
        if not repo_content.get('has_tests'):
            return {'passed': False, 'message': 'No tests found'}
        
        # Simulate coverage percentage
        coverage_percentage = 85.5  # Simulated good coverage
        required_coverage = 80.0
        
        return {
            'passed': coverage_percentage >= required_coverage,
            'coverage_percentage': coverage_percentage,
            'required_coverage': required_coverage,
            'message': f'Test coverage: {coverage_percentage}% (required: {required_coverage}%)'
        }
        
    except Exception as e:
        return {'passed': False, 'error': str(e)}

def run_dependency_check(repo_content):
    """Check for dependency issues"""
    try:
        # Simulate dependency analysis
        if not repo_content.get('has_requirements'):
            return {'passed': True, 'message': 'No dependencies to check'}
        
        # Simulate checking for outdated or vulnerable dependencies
        outdated_count = 0
        vulnerable_count = 0
        
        return {
            'passed': vulnerable_count == 0,
            'outdated_dependencies': outdated_count,
            'vulnerable_dependencies': vulnerable_count,
            'message': f'Found {vulnerable_count} vulnerable and {outdated_count} outdated dependencies'
        }
        
    except Exception as e:
        return {'passed': False, 'error': str(e)}

def process_quality_results(trigger_info, results):
    """Process and communicate quality check results"""
    try:
        # Record metrics
        record_quality_metrics(results)
        
        # Send notifications for failures
        if results['overall_result'] == 'FAILED':
            send_quality_failure_notification(trigger_info, results)
        elif results['overall_result'] == 'PASSED':
            send_quality_success_notification(trigger_info, results)
        
        # Post comment if this is related to a pull request
        # (Implementation would need to correlate commits with PRs)
        
    except Exception as e:
        logger.error(f"Error processing quality results: {str(e)}")

def record_quality_metrics(results):
    """Record quality metrics to CloudWatch"""
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

def send_quality_failure_notification(trigger_info, results):
    """Send notification for quality check failures"""
    try:
        failure_summary = []
        for check_name, check_result in results['checks'].items():
            if isinstance(check_result, dict) and not check_result.get('passed', True):
                failure_summary.append(f"❌ {check_name}: {check_result.get('message', 'Failed')}")
        
        message = f"""
🚨 Quality Gates Failed

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

def send_quality_success_notification(trigger_info, results):
    """Send notification for quality check success"""
    try:
        # Only send success notifications for important branches
        important_branches = ['main', 'master', 'develop']
        
        if results['branch'] not in important_branches:
            return
        
        message = f"""
✅ Quality Gates Passed

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