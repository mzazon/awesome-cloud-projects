import json
import boto3
import datetime
import os
from typing import Dict, List

def lambda_handler(event, context):
    """
    BC Compliance Reporter Lambda Function
    
    Generates monthly compliance reports based on business continuity
    testing activities. Analyzes test execution history and creates
    comprehensive reports for audit and compliance purposes.
    """
    s3 = boto3.client('s3')
    ssm = boto3.client('ssm')
    
    try:
        # Generate monthly compliance report
        report_data = generate_compliance_report(s3, ssm)
        
        # Store compliance report as JSON
        report_key = f"compliance-reports/{datetime.datetime.utcnow().strftime('%Y-%m')}/bc-compliance-report.json"
        
        s3.put_object(
            Bucket=os.environ['RESULTS_BUCKET'],
            Key=report_key,
            Body=json.dumps(report_data, indent=2),
            ContentType='application/json'
        )
        
        # Generate and store HTML report
        html_report = generate_html_report(report_data)
        
        html_key = f"compliance-reports/{datetime.datetime.utcnow().strftime('%Y-%m')}/bc-compliance-report.html"
        s3.put_object(
            Bucket=os.environ['RESULTS_BUCKET'],
            Key=html_key,
            Body=html_report,
            ContentType='text/html'
        )
        
        # Generate executive summary
        executive_summary = generate_executive_summary(report_data)
        
        summary_key = f"compliance-reports/{datetime.datetime.utcnow().strftime('%Y-%m')}/executive-summary.txt"
        s3.put_object(
            Bucket=os.environ['RESULTS_BUCKET'],
            Key=summary_key,
            Body=executive_summary,
            ContentType='text/plain'
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'reportGenerated': True,
                'reportLocation': report_key,
                'htmlReportLocation': html_key,
                'executiveSummaryLocation': summary_key,
                'complianceStatus': report_data['complianceStatus']
            })
        }
        
    except Exception as e:
        print(f'Error generating compliance report: {str(e)}')
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f'Failed to generate compliance report: {str(e)}'
            })
        }

def generate_compliance_report(s3, ssm):
    """Generate comprehensive compliance report data"""
    # Calculate report period (last 30 days)
    end_date = datetime.datetime.utcnow()
    start_date = end_date - datetime.timedelta(days=30)
    
    report = {
        'reportPeriod': {
            'start': start_date.isoformat(),
            'end': end_date.isoformat()
        },
        'generatedAt': end_date.isoformat(),
        'testingSummary': {
            'dailyTests': 0,
            'weeklyTests': 0,
            'monthlyTests': 0,
            'totalTests': 0,
            'successfulTests': 0,
            'failedTests': 0,
            'testCoverage': {
                'backupValidation': 0,
                'databaseRecovery': 0,
                'applicationFailover': 0
            }
        },
        'complianceMetrics': {
            'testingFrequency': 'COMPLIANT',
            'documentationComplete': 'COMPLIANT',
            'notificationSystem': 'COMPLIANT',
            'auditTrail': 'COMPLIANT'
        },
        'complianceStatus': 'COMPLIANT',
        'recommendations': [],
        'auditTrail': []
    }
    
    try:
        # Analyze test execution history from S3
        test_results = analyze_test_results(s3, start_date, end_date)
        report['testingSummary'].update(test_results)
        
        # Analyze Systems Manager automation executions
        automation_data = analyze_automation_executions(ssm, start_date, end_date)
        report['auditTrail'].extend(automation_data)
        
        # Determine overall compliance status
        report['complianceStatus'] = determine_compliance_status(report)
        
        # Generate recommendations
        report['recommendations'] = generate_recommendations(report)
        
    except Exception as e:
        print(f'Error analyzing test data: {str(e)}')
        report['complianceStatus'] = 'UNKNOWN'
        report['recommendations'].append(f'Unable to fully analyze test data: {str(e)}')
    
    return report

def analyze_test_results(s3, start_date, end_date):
    """Analyze test results stored in S3 bucket"""
    results = {
        'dailyTests': 0,
        'weeklyTests': 0,
        'monthlyTests': 0,
        'totalTests': 0,
        'successfulTests': 0,
        'failedTests': 0,
        'testCoverage': {
            'backupValidation': 0,
            'databaseRecovery': 0,
            'applicationFailover': 0
        }
    }
    
    try:
        # List objects in test-results/ prefix
        paginator = s3.get_paginator('list_objects_v2')
        pages = paginator.paginate(
            Bucket=os.environ['RESULTS_BUCKET'],
            Prefix='test-results/'
        )
        
        for page in pages:
            for obj in page.get('Contents', []):
                # Parse object key to extract test information
                if obj['Key'].endswith('results.json'):
                    try:
                        # Check if object was created within report period
                        if start_date <= obj['LastModified'].replace(tzinfo=None) <= end_date:
                            # Get test result object
                            response = s3.get_object(
                                Bucket=os.environ['RESULTS_BUCKET'],
                                Key=obj['Key']
                            )
                            test_data = json.loads(response['Body'].read())
                            
                            # Count test types
                            test_type = test_data.get('testType', 'unknown')
                            if test_type == 'daily':
                                results['dailyTests'] += 1
                            elif test_type == 'weekly':
                                results['weeklyTests'] += 1
                            elif test_type == 'monthly':
                                results['monthlyTests'] += 1
                            
                            results['totalTests'] += 1
                            
                            # Analyze individual test results
                            for test_result in test_data.get('results', []):
                                if test_result.get('status') == 'started':
                                    results['successfulTests'] += 1
                                    
                                    # Count test coverage
                                    test_name = test_result.get('test', '')
                                    if 'backup' in test_name:
                                        results['testCoverage']['backupValidation'] += 1
                                    elif 'database' in test_name:
                                        results['testCoverage']['databaseRecovery'] += 1
                                    elif 'application' in test_name:
                                        results['testCoverage']['applicationFailover'] += 1
                                else:
                                    results['failedTests'] += 1
                    except Exception as e:
                        print(f'Error processing test result {obj["Key"]}: {str(e)}')
                        continue
    except Exception as e:
        print(f'Error analyzing S3 test results: {str(e)}')
    
    return results

def analyze_automation_executions(ssm, start_date, end_date):
    """Analyze Systems Manager automation executions"""
    audit_trail = []
    
    try:
        # Get automation executions for BC documents
        document_names = [
            'BC-BackupValidation',
            'BC-DatabaseRecovery', 
            'BC-ApplicationFailover'
        ]
        
        for doc_name_prefix in document_names:
            try:
                response = ssm.describe_automation_executions(
                    MaxResults=50,
                    Filters=[
                        {
                            'Key': 'DocumentNamePrefix',
                            'Values': [doc_name_prefix]
                        },
                        {
                            'Key': 'ExecutionStatus',
                            'Values': ['Success', 'Failed', 'Cancelled', 'TimedOut']
                        }
                    ]
                )
                
                for execution in response.get('AutomationExecutions', []):
                    execution_time = execution.get('ExecutionStartTime')
                    if execution_time and start_date <= execution_time.replace(tzinfo=None) <= end_date:
                        audit_trail.append({
                            'executionId': execution['AutomationExecutionId'],
                            'documentName': execution['DocumentName'],
                            'status': execution['AutomationExecutionStatus'],
                            'startTime': execution_time.isoformat(),
                            'endTime': execution.get('ExecutionEndTime', '').isoformat() if execution.get('ExecutionEndTime') else None
                        })
            except Exception as e:
                print(f'Error getting executions for {doc_name_prefix}: {str(e)}')
                continue
                
    except Exception as e:
        print(f'Error analyzing automation executions: {str(e)}')
    
    return audit_trail

def determine_compliance_status(report):
    """Determine overall compliance status based on testing metrics"""
    testing_summary = report['testingSummary']
    
    # Check if we have sufficient testing
    if testing_summary['totalTests'] < 30:  # Expect ~30 daily tests per month
        return 'NON_COMPLIANT'
    
    # Check success rate
    total_tests = testing_summary['totalTests']
    if total_tests > 0:
        success_rate = testing_summary['successfulTests'] / total_tests
        if success_rate < 0.8:  # 80% success rate threshold
            return 'NON_COMPLIANT'
    
    # Check test coverage
    coverage = testing_summary['testCoverage']
    if coverage['backupValidation'] == 0:
        return 'NON_COMPLIANT'
    
    return 'COMPLIANT'

def generate_recommendations(report):
    """Generate recommendations based on compliance analysis"""
    recommendations = []
    
    testing_summary = report['testingSummary']
    
    # Test frequency recommendations
    if testing_summary['dailyTests'] < 25:
        recommendations.append("Increase daily backup validation testing frequency to ensure consistent coverage")
    
    if testing_summary['weeklyTests'] < 4:
        recommendations.append("Ensure weekly comprehensive testing is executing as scheduled")
    
    if testing_summary['monthlyTests'] < 1:
        recommendations.append("Verify monthly full disaster recovery testing is configured and executing")
    
    # Test success rate recommendations
    if testing_summary['failedTests'] > 0:
        recommendations.append("Investigate and resolve test failures to improve success rate")
    
    # Coverage recommendations
    coverage = testing_summary['testCoverage']
    if coverage['databaseRecovery'] == 0:
        recommendations.append("Configure and execute database recovery testing")
    
    if coverage['applicationFailover'] == 0:
        recommendations.append("Configure and execute application failover testing")
    
    if not recommendations:
        recommendations.append("All compliance metrics are within acceptable thresholds. Continue current testing schedule.")
    
    return recommendations

def generate_html_report(report_data):
    """Generate HTML version of compliance report"""
    compliance_class = "compliant" if report_data['complianceStatus'] == 'COMPLIANT' else "non-compliant"
    
    html = f"""
<!DOCTYPE html>
<html>
<head>
    <title>Business Continuity Compliance Report</title>
    <style>
        body {{ font-family: Arial, sans-serif; margin: 20px; }}
        .header {{ background-color: #f0f0f0; padding: 20px; border-radius: 5px; }}
        .summary {{ margin: 20px 0; }}
        .compliant {{ color: green; font-weight: bold; }}
        .non-compliant {{ color: red; font-weight: bold; }}
        table {{ border-collapse: collapse; width: 100%; margin: 10px 0; }}
        th, td {{ border: 1px solid #ddd; padding: 8px; text-align: left; }}
        th {{ background-color: #f2f2f2; }}
        .recommendations {{ background-color: #fff3cd; padding: 15px; border-radius: 5px; }}
        .metric-box {{ display: inline-block; margin: 10px; padding: 15px; border: 1px solid #ddd; border-radius: 5px; }}
    </style>
</head>
<body>
    <div class="header">
        <h1>Business Continuity Testing Compliance Report</h1>
        <p><strong>Report Period:</strong> {report_data['reportPeriod']['start']} to {report_data['reportPeriod']['end']}</p>
        <p><strong>Generated:</strong> {report_data['generatedAt']}</p>
        <p><strong>Compliance Status:</strong> <span class="{compliance_class}">{report_data['complianceStatus']}</span></p>
    </div>
    
    <div class="summary">
        <h2>Testing Summary</h2>
        <div class="metric-box">
            <h4>Total Tests</h4>
            <p style="font-size: 24px; margin: 0;">{report_data['testingSummary']['totalTests']}</p>
        </div>
        <div class="metric-box">
            <h4>Successful Tests</h4>
            <p style="font-size: 24px; margin: 0; color: green;">{report_data['testingSummary']['successfulTests']}</p>
        </div>
        <div class="metric-box">
            <h4>Failed Tests</h4>
            <p style="font-size: 24px; margin: 0; color: red;">{report_data['testingSummary']['failedTests']}</p>
        </div>
    </div>
    
    <h3>Test Breakdown</h3>
    <table>
        <tr>
            <th>Test Type</th>
            <th>Count</th>
        </tr>
        <tr>
            <td>Daily Tests</td>
            <td>{report_data['testingSummary']['dailyTests']}</td>
        </tr>
        <tr>
            <td>Weekly Tests</td>
            <td>{report_data['testingSummary']['weeklyTests']}</td>
        </tr>
        <tr>
            <td>Monthly Tests</td>
            <td>{report_data['testingSummary']['monthlyTests']}</td>
        </tr>
    </table>
    
    <h3>Test Coverage</h3>
    <table>
        <tr>
            <th>Test Category</th>
            <th>Executions</th>
        </tr>
        <tr>
            <td>Backup Validation</td>
            <td>{report_data['testingSummary']['testCoverage']['backupValidation']}</td>
        </tr>
        <tr>
            <td>Database Recovery</td>
            <td>{report_data['testingSummary']['testCoverage']['databaseRecovery']}</td>
        </tr>
        <tr>
            <td>Application Failover</td>
            <td>{report_data['testingSummary']['testCoverage']['applicationFailover']}</td>
        </tr>
    </table>
    
    <div class="recommendations">
        <h3>Recommendations</h3>
        <ul>
"""
    
    for recommendation in report_data['recommendations']:
        html += f"            <li>{recommendation}</li>\n"
    
    html += """
        </ul>
    </div>
    
    <p><em>This report was automatically generated by the Business Continuity Testing Framework.</em></p>
</body>
</html>
"""
    
    return html

def generate_executive_summary(report_data):
    """Generate executive summary text"""
    total_tests = report_data['testingSummary']['totalTests']
    successful_tests = report_data['testingSummary']['successfulTests']
    success_rate = (successful_tests / total_tests * 100) if total_tests > 0 else 0
    
    summary = f"""
BUSINESS CONTINUITY TESTING - EXECUTIVE SUMMARY
Report Period: {report_data['reportPeriod']['start']} to {report_data['reportPeriod']['end']}

COMPLIANCE STATUS: {report_data['complianceStatus']}

KEY METRICS:
- Total Tests Executed: {total_tests}
- Success Rate: {success_rate:.1f}%
- Daily Tests: {report_data['testingSummary']['dailyTests']}
- Weekly Tests: {report_data['testingSummary']['weeklyTests']}
- Monthly Tests: {report_data['testingSummary']['monthlyTests']}

TEST COVERAGE:
- Backup Validation: {report_data['testingSummary']['testCoverage']['backupValidation']} executions
- Database Recovery: {report_data['testingSummary']['testCoverage']['databaseRecovery']} executions
- Application Failover: {report_data['testingSummary']['testCoverage']['applicationFailover']} executions

RECOMMENDATIONS:
"""
    
    for i, recommendation in enumerate(report_data['recommendations'], 1):
        summary += f"{i}. {recommendation}\n"
    
    summary += f"""
This automated testing framework ensures regular validation of business continuity 
procedures and maintains audit trails for compliance purposes. All test results 
and documentation are stored in S3 with appropriate lifecycle policies.

Generated: {report_data['generatedAt']}
"""
    
    return summary