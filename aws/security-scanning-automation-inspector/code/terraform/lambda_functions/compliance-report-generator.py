#!/usr/bin/env python3
"""
AWS Lambda Function: Compliance Report Generator
===============================================

This Lambda function generates comprehensive compliance reports from AWS Security Hub
findings, providing regular security posture assessments and trend analysis for
regulatory compliance and security management purposes.

Features:
- Generates CSV and JSON format compliance reports
- Analyzes findings trends over time
- Provides severity distribution statistics
- Supports custom date ranges for reporting
- Stores reports in S3 with proper lifecycle management
- Includes executive summary and detailed findings

Environment Variables:
- S3_BUCKET: S3 bucket name for storing compliance reports
"""

import json
import boto3
import csv
import logging
import os
from datetime import datetime, timedelta
from io import StringIO
from typing import Dict, List, Any, Optional, Tuple
from botocore.exceptions import ClientError, BotoCoreError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS service clients
securityhub = boto3.client('securityhub')
s3 = boto3.client('s3')

# Constants
S3_BUCKET = os.environ.get('S3_BUCKET', '')
REPORT_FORMATS = ['csv', 'json']
DEFAULT_REPORT_DAYS = 7
MAX_FINDINGS_PER_REQUEST = 100

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler function for generating compliance reports.
    
    Args:
        event: EventBridge scheduled event or manual invocation
        context: Lambda context object
        
    Returns:
        Dict containing report generation results
    """
    try:
        logger.info(f"Starting compliance report generation: {json.dumps(event, default=str)}")
        
        # Parse report parameters from event
        report_config = parse_report_configuration(event)
        
        # Validate S3 bucket configuration
        if not S3_BUCKET:
            logger.error("S3_BUCKET environment variable not configured")
            return create_response(500, "S3 bucket not configured")
        
        # Generate compliance report
        report_data = generate_compliance_report(report_config)
        
        # Save reports to S3
        report_urls = save_reports_to_s3(report_data, report_config)
        
        # Create response with report details
        response_message = f"Compliance report generated successfully with {report_data['summary']['total_findings']} findings"
        logger.info(response_message)
        
        return create_response(200, response_message, {
            'report_config': report_config,
            'report_summary': report_data['summary'],
            'report_urls': report_urls,
            'generation_timestamp': datetime.utcnow().isoformat() + 'Z'
        })
        
    except Exception as e:
        error_msg = f"Critical error generating compliance report: {str(e)}"
        logger.error(error_msg, exc_info=True)
        return create_response(500, error_msg)

def parse_report_configuration(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Parse report configuration from the incoming event.
    
    Args:
        event: Lambda event containing report parameters
        
    Returns:
        Dict containing report configuration
    """
    try:
        # Default configuration
        config = {
            'report_days': DEFAULT_REPORT_DAYS,
            'formats': REPORT_FORMATS,
            'include_resolved': False,
            'severity_filter': None,
            'resource_type_filter': None,
            'compliance_status_filter': None
        }
        
        # Override with event parameters if provided
        event_detail = event.get('detail', {})
        
        # Extract report parameters
        if 'report_days' in event_detail:
            config['report_days'] = int(event_detail['report_days'])
        
        if 'formats' in event_detail:
            config['formats'] = event_detail['formats']
        
        if 'include_resolved' in event_detail:
            config['include_resolved'] = bool(event_detail['include_resolved'])
        
        if 'severity_filter' in event_detail:
            config['severity_filter'] = event_detail['severity_filter']
        
        if 'resource_type_filter' in event_detail:
            config['resource_type_filter'] = event_detail['resource_type_filter']
        
        if 'compliance_status_filter' in event_detail:
            config['compliance_status_filter'] = event_detail['compliance_status_filter']
        
        logger.info(f"Report configuration: {json.dumps(config)}")
        return config
        
    except Exception as e:
        logger.error(f"Error parsing report configuration: {str(e)}")
        # Return default configuration on error
        return {
            'report_days': DEFAULT_REPORT_DAYS,
            'formats': REPORT_FORMATS,
            'include_resolved': False,
            'severity_filter': None,
            'resource_type_filter': None,
            'compliance_status_filter': None
        }

def generate_compliance_report(config: Dict[str, Any]) -> Dict[str, Any]:
    """
    Generate comprehensive compliance report with findings and analytics.
    
    Args:
        config: Report configuration parameters
        
    Returns:
        Dict containing report data and analytics
    """
    try:
        logger.info(f"Generating compliance report with config: {json.dumps(config)}")
        
        # Calculate date range for the report
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(days=config['report_days'])
        
        # Fetch findings from Security Hub
        findings = fetch_security_hub_findings(start_time, end_time, config)
        
        # Generate analytics and summary
        summary = generate_report_summary(findings, config)
        
        # Create detailed findings analysis
        findings_analysis = analyze_findings(findings)
        
        # Generate trend data
        trend_data = generate_trend_analysis(findings, config['report_days'])
        
        report_data = {
            'metadata': {
                'report_date': end_time.isoformat() + 'Z',
                'report_period': {
                    'start': start_time.isoformat() + 'Z',
                    'end': end_time.isoformat() + 'Z',
                    'days': config['report_days']
                },
                'configuration': config
            },
            'summary': summary,
            'findings': findings,
            'analysis': findings_analysis,
            'trends': trend_data
        }
        
        logger.info(f"Report generated with {len(findings)} findings")
        return report_data
        
    except Exception as e:
        logger.error(f"Error generating compliance report: {str(e)}")
        raise

def fetch_security_hub_findings(start_time: datetime, end_time: datetime, 
                               config: Dict[str, Any]) -> List[Dict[str, Any]]:
    """
    Fetch Security Hub findings for the specified time period and filters.
    
    Args:
        start_time: Start of the reporting period
        end_time: End of the reporting period
        config: Report configuration with filters
        
    Returns:
        List of Security Hub findings
    """
    try:
        findings = []
        next_token = None
        
        # Build filters for the Security Hub query
        filters = {
            'CreatedAt': [
                {
                    'Start': start_time.isoformat() + 'Z',
                    'End': end_time.isoformat() + 'Z'
                }
            ]
        }
        
        # Add record state filter
        if not config.get('include_resolved', False):
            filters['RecordState'] = [{'Value': 'ACTIVE', 'Comparison': 'EQUALS'}]
        
        # Add severity filter if specified
        if config.get('severity_filter'):
            filters['SeverityLabel'] = [
                {'Value': severity, 'Comparison': 'EQUALS'} 
                for severity in config['severity_filter']
            ]
        
        # Add resource type filter if specified
        if config.get('resource_type_filter'):
            filters['ResourceType'] = [
                {'Value': resource_type, 'Comparison': 'EQUALS'} 
                for resource_type in config['resource_type_filter']
            ]
        
        # Add compliance status filter if specified
        if config.get('compliance_status_filter'):
            filters['ComplianceStatus'] = [
                {'Value': status, 'Comparison': 'EQUALS'} 
                for status in config['compliance_status_filter']
            ]
        
        # Paginate through all findings
        while True:
            try:
                request_params = {
                    'Filters': filters,
                    'MaxResults': MAX_FINDINGS_PER_REQUEST
                }
                
                if next_token:
                    request_params['NextToken'] = next_token
                
                response = securityhub.get_findings(**request_params)
                
                findings.extend(response.get('Findings', []))
                next_token = response.get('NextToken')
                
                logger.info(f"Fetched {len(response.get('Findings', []))} findings, total: {len(findings)}")
                
                if not next_token:
                    break
                    
            except ClientError as e:
                logger.error(f"Error fetching findings: {str(e)}")
                break
        
        logger.info(f"Total findings fetched: {len(findings)}")
        return findings
        
    except Exception as e:
        logger.error(f"Error in fetch_security_hub_findings: {str(e)}")
        raise

def generate_report_summary(findings: List[Dict[str, Any]], config: Dict[str, Any]) -> Dict[str, Any]:
    """
    Generate summary statistics for the compliance report.
    
    Args:
        findings: List of Security Hub findings
        config: Report configuration
        
    Returns:
        Dict containing summary statistics
    """
    try:
        summary = {
            'total_findings': len(findings),
            'severity_distribution': {},
            'resource_type_distribution': {},
            'compliance_status_distribution': {},
            'top_finding_types': {},
            'critical_stats': {
                'critical_count': 0,
                'high_count': 0,
                'unresolved_critical': 0,
                'unresolved_high': 0
            }
        }
        
        # Analyze findings
        for finding in findings:
            severity = finding.get('Severity', {}).get('Label', 'UNKNOWN')
            resource_type = finding.get('Resources', [{}])[0].get('Type', 'Unknown') if finding.get('Resources') else 'Unknown'
            compliance_status = finding.get('Compliance', {}).get('Status', 'Unknown')
            finding_type = finding.get('Type', 'Unknown')
            record_state = finding.get('RecordState', 'UNKNOWN')
            
            # Severity distribution
            summary['severity_distribution'][severity] = summary['severity_distribution'].get(severity, 0) + 1
            
            # Resource type distribution
            summary['resource_type_distribution'][resource_type] = summary['resource_type_distribution'].get(resource_type, 0) + 1
            
            # Compliance status distribution
            summary['compliance_status_distribution'][compliance_status] = summary['compliance_status_distribution'].get(compliance_status, 0) + 1
            
            # Finding type distribution
            summary['top_finding_types'][finding_type] = summary['top_finding_types'].get(finding_type, 0) + 1
            
            # Critical statistics
            if severity == 'CRITICAL':
                summary['critical_stats']['critical_count'] += 1
                if record_state == 'ACTIVE':
                    summary['critical_stats']['unresolved_critical'] += 1
            elif severity == 'HIGH':
                summary['critical_stats']['high_count'] += 1
                if record_state == 'ACTIVE':
                    summary['critical_stats']['unresolved_high'] += 1
        
        # Sort top finding types
        summary['top_finding_types'] = dict(
            sorted(summary['top_finding_types'].items(), key=lambda x: x[1], reverse=True)[:10]
        )
        
        logger.info(f"Generated summary for {summary['total_findings']} findings")
        return summary
        
    except Exception as e:
        logger.error(f"Error generating report summary: {str(e)}")
        raise

def analyze_findings(findings: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Perform detailed analysis of security findings.
    
    Args:
        findings: List of Security Hub findings
        
    Returns:
        Dict containing detailed analysis results
    """
    try:
        analysis = {
            'compliance_trends': {},
            'resource_analysis': {},
            'remediation_status': {},
            'age_analysis': {},
            'risk_assessment': {}
        }
        
        current_time = datetime.utcnow()
        
        for finding in findings:
            # Compliance trends analysis
            compliance_status = finding.get('Compliance', {}).get('Status', 'Unknown')
            standard_name = finding.get('ProductFields', {}).get('StandardsArn', 'Unknown')
            
            if standard_name not in analysis['compliance_trends']:
                analysis['compliance_trends'][standard_name] = {'PASSED': 0, 'FAILED': 0, 'WARNING': 0, 'NOT_AVAILABLE': 0}
            
            analysis['compliance_trends'][standard_name][compliance_status] = analysis['compliance_trends'][standard_name].get(compliance_status, 0) + 1
            
            # Resource analysis
            resources = finding.get('Resources', [])
            for resource in resources:
                resource_type = resource.get('Type', 'Unknown')
                if resource_type not in analysis['resource_analysis']:
                    analysis['resource_analysis'][resource_type] = {
                        'total_findings': 0,
                        'critical_findings': 0,
                        'high_findings': 0,
                        'unique_resources': set()
                    }
                
                analysis['resource_analysis'][resource_type]['total_findings'] += 1
                analysis['resource_analysis'][resource_type]['unique_resources'].add(resource.get('Id', ''))
                
                severity = finding.get('Severity', {}).get('Label', '')
                if severity == 'CRITICAL':
                    analysis['resource_analysis'][resource_type]['critical_findings'] += 1
                elif severity == 'HIGH':
                    analysis['resource_analysis'][resource_type]['high_findings'] += 1
            
            # Age analysis
            created_at_str = finding.get('CreatedAt', '')
            if created_at_str:
                try:
                    created_at = datetime.fromisoformat(created_at_str.replace('Z', '+00:00'))
                    age_days = (current_time - created_at.replace(tzinfo=None)).days
                    
                    age_category = get_age_category(age_days)
                    analysis['age_analysis'][age_category] = analysis['age_analysis'].get(age_category, 0) + 1
                except Exception as e:
                    logger.warning(f"Error parsing date {created_at_str}: {str(e)}")
        
        # Convert sets to counts for JSON serialization
        for resource_type in analysis['resource_analysis']:
            unique_count = len(analysis['resource_analysis'][resource_type]['unique_resources'])
            analysis['resource_analysis'][resource_type]['unique_resources'] = unique_count
        
        logger.info("Completed detailed findings analysis")
        return analysis
        
    except Exception as e:
        logger.error(f"Error in analyze_findings: {str(e)}")
        raise

def get_age_category(age_days: int) -> str:
    """
    Categorize finding age for analysis.
    
    Args:
        age_days: Age of the finding in days
        
    Returns:
        Age category string
    """
    if age_days <= 1:
        return "0-1 days"
    elif age_days <= 7:
        return "2-7 days"
    elif age_days <= 30:
        return "8-30 days"
    elif age_days <= 90:
        return "31-90 days"
    else:
        return "90+ days"

def generate_trend_analysis(findings: List[Dict[str, Any]], report_days: int) -> Dict[str, Any]:
    """
    Generate trend analysis for findings over the reporting period.
    
    Args:
        findings: List of Security Hub findings
        report_days: Number of days in the reporting period
        
    Returns:
        Dict containing trend analysis
    """
    try:
        trends = {
            'daily_findings': {},
            'severity_trends': {},
            'compliance_trends': {}
        }
        
        # Initialize daily findings tracker
        current_date = datetime.utcnow().date()
        for i in range(report_days):
            date_key = (current_date - timedelta(days=i)).strftime('%Y-%m-%d')
            trends['daily_findings'][date_key] = 0
        
        # Analyze findings by day
        for finding in findings:
            created_at_str = finding.get('CreatedAt', '')
            if created_at_str:
                try:
                    created_at = datetime.fromisoformat(created_at_str.replace('Z', '+00:00'))
                    date_key = created_at.date().strftime('%Y-%m-%d')
                    
                    if date_key in trends['daily_findings']:
                        trends['daily_findings'][date_key] += 1
                except Exception as e:
                    logger.warning(f"Error parsing date {created_at_str}: {str(e)}")
        
        logger.info("Generated trend analysis")
        return trends
        
    except Exception as e:
        logger.error(f"Error generating trend analysis: {str(e)}")
        raise

def save_reports_to_s3(report_data: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, str]:
    """
    Save compliance reports to S3 in multiple formats.
    
    Args:
        report_data: Complete report data
        config: Report configuration
        
    Returns:
        Dict mapping format to S3 URL
    """
    try:
        report_urls = {}
        timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
        
        for format_type in config['formats']:
            if format_type == 'csv':
                s3_key, url = save_csv_report(report_data, timestamp)
                report_urls['csv'] = url
            elif format_type == 'json':
                s3_key, url = save_json_report(report_data, timestamp)
                report_urls['json'] = url
        
        logger.info(f"Saved reports to S3: {list(report_urls.keys())}")
        return report_urls
        
    except Exception as e:
        logger.error(f"Error saving reports to S3: {str(e)}")
        raise

def save_csv_report(report_data: Dict[str, Any], timestamp: str) -> Tuple[str, str]:
    """
    Save compliance report in CSV format to S3.
    
    Args:
        report_data: Report data to save
        timestamp: Timestamp for file naming
        
    Returns:
        Tuple of (S3 key, S3 URL)
    """
    try:
        csv_buffer = StringIO()
        writer = csv.writer(csv_buffer)
        
        # Write header
        writer.writerow([
            'Finding ID', 'Title', 'Severity', 'Resource Type', 'Resource ID',
            'Compliance Status', 'Record State', 'Created Date', 'Updated Date',
            'Account ID', 'Region', 'Standard', 'Description'
        ])
        
        # Write findings data
        for finding in report_data['findings']:
            writer.writerow([
                finding.get('Id', ''),
                finding.get('Title', ''),
                finding.get('Severity', {}).get('Label', ''),
                finding.get('Resources', [{}])[0].get('Type', '') if finding.get('Resources') else '',
                finding.get('Resources', [{}])[0].get('Id', '') if finding.get('Resources') else '',
                finding.get('Compliance', {}).get('Status', ''),
                finding.get('RecordState', ''),
                finding.get('CreatedAt', ''),
                finding.get('UpdatedAt', ''),
                finding.get('AwsAccountId', ''),
                finding.get('Region', ''),
                finding.get('ProductFields', {}).get('StandardsArn', ''),
                finding.get('Description', '')[:500]  # Limit description length
            ])
        
        # Save to S3
        s3_key = f"compliance-reports/security-findings-{timestamp}.csv"
        
        s3.put_object(
            Bucket=S3_BUCKET,
            Key=s3_key,
            Body=csv_buffer.getvalue(),
            ContentType='text/csv',
            ServerSideEncryption='AES256'
        )
        
        s3_url = f"s3://{S3_BUCKET}/{s3_key}"
        logger.info(f"CSV report saved to {s3_url}")
        
        return s3_key, s3_url
        
    except Exception as e:
        logger.error(f"Error saving CSV report: {str(e)}")
        raise

def save_json_report(report_data: Dict[str, Any], timestamp: str) -> Tuple[str, str]:
    """
    Save compliance report in JSON format to S3.
    
    Args:
        report_data: Report data to save
        timestamp: Timestamp for file naming
        
    Returns:
        Tuple of (S3 key, S3 URL)
    """
    try:
        # Save to S3
        s3_key = f"compliance-reports/security-report-{timestamp}.json"
        
        s3.put_object(
            Bucket=S3_BUCKET,
            Key=s3_key,
            Body=json.dumps(report_data, default=str, indent=2),
            ContentType='application/json',
            ServerSideEncryption='AES256'
        )
        
        s3_url = f"s3://{S3_BUCKET}/{s3_key}"
        logger.info(f"JSON report saved to {s3_url}")
        
        return s3_key, s3_url
        
    except Exception as e:
        logger.error(f"Error saving JSON report: {str(e)}")
        raise

def create_response(status_code: int, message: str, data: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    """
    Create a standardized Lambda response.
    
    Args:
        status_code: HTTP status code
        message: Response message
        data: Optional additional data
        
    Returns:
        Formatted response dictionary
    """
    response = {
        'statusCode': status_code,
        'body': json.dumps({
            'message': message,
            'timestamp': datetime.utcnow().isoformat() + 'Z'
        }, default=str)
    }
    
    if data:
        body = json.loads(response['body'])
        body.update(data)
        response['body'] = json.dumps(body, default=str)
    
    return response