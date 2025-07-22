"""
Cost Reporter Lambda Function for Cost Governance
Generates comprehensive cost governance reports and analytics
"""

import json
import boto3
import logging
import os
from datetime import datetime, timedelta
from typing import Dict, List, Any, Optional
import csv
from io import StringIO

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for cost governance reporting
    
    Args:
        event: Lambda event data
        context: Lambda context object
        
    Returns:
        Dict containing execution results
    """
    logger.info(f"Starting cost governance report generation. Event: {json.dumps(event)}")
    
    # Initialize AWS clients
    s3 = boto3.client('s3')
    sns = boto3.client('sns')
    ec2 = boto3.client('ec2')
    config_client = boto3.client('config')
    
    try:
        # Get configuration from environment variables
        sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
        reports_bucket = os.environ.get('REPORTS_BUCKET')
        
        if not sns_topic_arn or not reports_bucket:
            raise ValueError("Required environment variables not set")
        
        # Generate comprehensive cost governance report
        report_data = generate_cost_governance_report(ec2, config_client)
        
        # Save detailed report to S3
        report_key = save_report_to_s3(s3, reports_bucket, report_data)
        
        # Generate and save CSV summary
        csv_key = save_csv_summary_to_s3(s3, reports_bucket, report_data)
        
        # Send summary notification
        send_summary_notification(sns, sns_topic_arn, report_data, reports_bucket, report_key)
        
        logger.info(f"Cost governance report generated successfully: {report_key}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Cost governance report generated successfully',
                'report_location': f"s3://{reports_bucket}/{report_key}",
                'csv_location': f"s3://{reports_bucket}/{csv_key}",
                'summary': report_data['Summary']
            }, default=str)
        }
    
    except Exception as e:
        logger.error(f"Error generating cost governance report: {str(e)}")
        
        # Send error notification
        try:
            error_message = {
                'Alert': 'Error in Cost Governance Reporting',
                'Timestamp': datetime.utcnow().isoformat(),
                'Error': str(e),
                'Function': context.function_name if context else 'Unknown',
                'RequestId': context.aws_request_id if context else 'Unknown'
            }
            
            sns.publish(
                TopicArn=os.environ.get('SNS_TOPIC_ARN', ''),
                Subject='Cost Governance Error: Report Generation Failed',
                Message=json.dumps(error_message, indent=2)
            )
        except:
            pass  # Avoid cascading errors
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Failed to generate cost governance report'
            })
        }


def generate_cost_governance_report(ec2_client, config_client) -> Dict[str, Any]:
    """
    Generate comprehensive cost governance report data
    
    Args:
        ec2_client: EC2 boto3 client
        config_client: Config boto3 client
        
    Returns:
        Dict containing complete report data
    """
    report_data = {
        'ReportDate': datetime.utcnow().isoformat(),
        'ReportPeriod': {
            'StartDate': (datetime.utcnow() - timedelta(days=7)).isoformat(),
            'EndDate': datetime.utcnow().isoformat()
        },
        'Summary': {},
        'Details': {},
        'Recommendations': [],
        'CostOptimizationOpportunities': []
    }
    
    try:
        # Get Config compliance summary
        config_summary = get_config_compliance_summary(config_client)
        report_data['Summary']['ConfigCompliance'] = config_summary
        
        # Get EC2 resource analysis
        ec2_analysis = analyze_ec2_resources(ec2_client)
        report_data['Summary']['EC2Analysis'] = ec2_analysis['summary']
        report_data['Details']['EC2Resources'] = ec2_analysis['details']
        
        # Get EBS volume analysis
        ebs_analysis = analyze_ebs_volumes(ec2_client)
        report_data['Summary']['EBSAnalysis'] = ebs_analysis['summary']
        report_data['Details']['EBSVolumes'] = ebs_analysis['details']
        
        # Calculate total estimated savings
        total_savings = calculate_total_savings_opportunity(report_data)
        report_data['Summary']['TotalEstimatedMonthlySavings'] = total_savings
        
        # Generate recommendations
        recommendations = generate_recommendations(report_data)
        report_data['Recommendations'] = recommendations
        
        # Identify top cost optimization opportunities
        cost_opportunities = identify_cost_opportunities(report_data)
        report_data['CostOptimizationOpportunities'] = cost_opportunities
        
    except Exception as e:
        logger.error(f"Error generating report data: {str(e)}")
        raise
    
    return report_data


def get_config_compliance_summary(config_client) -> Dict[str, Any]:
    """
    Get AWS Config compliance summary
    
    Args:
        config_client: Config boto3 client
        
    Returns:
        Dict containing compliance summary
    """
    try:
        compliance_summary = config_client.get_compliance_summary_by_config_rule()
        
        total_compliant = 0
        total_non_compliant = 0
        rules_summary = []
        
        for rule in compliance_summary.get('ComplianceSummary', []):
            rule_name = rule.get('ConfigRuleName', 'Unknown')
            compliant = rule.get('ComplianceSummary', {}).get('CompliantResourceCount', {}).get('CappedCount', 0)
            non_compliant = rule.get('ComplianceSummary', {}).get('NonCompliantResourceCount', {}).get('CappedCount', 0)
            
            total_compliant += compliant
            total_non_compliant += non_compliant
            
            rules_summary.append({
                'RuleName': rule_name,
                'CompliantResources': compliant,
                'NonCompliantResources': non_compliant,
                'ComplianceRate': f"{(compliant / (compliant + non_compliant) * 100):.1f}%" if (compliant + non_compliant) > 0 else "N/A"
            })
        
        return {
            'TotalRules': len(rules_summary),
            'TotalCompliantResources': total_compliant,
            'TotalNonCompliantResources': total_non_compliant,
            'OverallComplianceRate': f"{(total_compliant / (total_compliant + total_non_compliant) * 100):.1f}%" if (total_compliant + total_non_compliant) > 0 else "N/A",
            'RulesSummary': rules_summary
        }
    
    except Exception as e:
        logger.error(f"Error getting Config compliance summary: {str(e)}")
        return {
            'TotalRules': 0,
            'TotalCompliantResources': 0,
            'TotalNonCompliantResources': 0,
            'OverallComplianceRate': "Error",
            'RulesSummary': [],
            'Error': str(e)
        }


def analyze_ec2_resources(ec2_client) -> Dict[str, Any]:
    """
    Analyze EC2 instances for cost optimization opportunities
    
    Args:
        ec2_client: EC2 boto3 client
        
    Returns:
        Dict containing EC2 analysis results
    """
    try:
        instances_response = ec2_client.describe_instances()
        
        running_instances = 0
        stopped_instances = 0
        idle_instances = 0
        terminated_instances = 0
        instance_details = []
        total_estimated_cost = 0
        
        for reservation in instances_response['Reservations']:
            for instance in reservation['Instances']:
                state = instance['State']['Name']
                instance_type = instance['InstanceType']
                instance_id = instance['InstanceId']
                launch_time = instance['LaunchTime']
                
                # Get instance tags
                tags = {tag['Key']: tag['Value'] for tag in instance.get('Tags', [])}
                instance_name = tags.get('Name', 'Unnamed')
                
                # Estimate monthly cost
                estimated_cost = estimate_instance_monthly_cost(instance_type)
                
                instance_detail = {
                    'InstanceId': instance_id,
                    'Name': instance_name,
                    'InstanceType': instance_type,
                    'State': state,
                    'LaunchTime': launch_time.isoformat(),
                    'EstimatedMonthlyCost': estimated_cost,
                    'Tags': tags
                }
                
                if state == 'running':
                    running_instances += 1
                    total_estimated_cost += estimated_cost
                    
                    # Check if tagged as idle
                    if tags.get('CostOptimization:Status') == 'Idle':
                        idle_instances += 1
                        instance_detail['OptimizationOpportunity'] = 'Idle - Consider stopping or right-sizing'
                        instance_detail['PotentialMonthlySavings'] = estimated_cost * 0.8
                
                elif state == 'stopped':
                    stopped_instances += 1
                    instance_detail['OptimizationOpportunity'] = 'Stopped - Consider terminating if not needed'
                
                elif state == 'terminated':
                    terminated_instances += 1
                
                instance_details.append(instance_detail)
        
        return {
            'summary': {
                'TotalInstances': len(instance_details),
                'RunningInstances': running_instances,
                'StoppedInstances': stopped_instances,
                'IdleInstances': idle_instances,
                'TerminatedInstances': terminated_instances,
                'EstimatedMonthlyRunningCost': f'${total_estimated_cost:.2f}',
                'IdleInstancesSavingsOpportunity': f'${idle_instances * 50:.2f}'  # Rough estimate
            },
            'details': instance_details
        }
    
    except Exception as e:
        logger.error(f"Error analyzing EC2 resources: {str(e)}")
        return {
            'summary': {'Error': str(e)},
            'details': []
        }


def analyze_ebs_volumes(ec2_client) -> Dict[str, Any]:
    """
    Analyze EBS volumes for cost optimization opportunities
    
    Args:
        ec2_client: EC2 boto3 client
        
    Returns:
        Dict containing EBS analysis results
    """
    try:
        volumes_response = ec2_client.describe_volumes()
        
        total_volumes = len(volumes_response['Volumes'])
        attached_volumes = 0
        unattached_volumes = 0
        scheduled_for_deletion = 0
        total_storage_gb = 0
        unattached_storage_gb = 0
        total_estimated_cost = 0
        unattached_estimated_cost = 0
        volume_details = []
        
        for volume in volumes_response['Volumes']:
            volume_id = volume['VolumeId']
            size = volume['Size']
            volume_type = volume['VolumeType']
            state = volume['State']
            create_time = volume['CreateTime']
            
            # Get volume tags
            tags = {tag['Key']: tag['Value'] for tag in volume.get('Tags', [])}
            volume_name = tags.get('Name', 'Unnamed')
            
            # Calculate estimated monthly cost
            monthly_cost = calculate_volume_monthly_cost(size, volume_type)
            total_estimated_cost += monthly_cost
            total_storage_gb += size
            
            volume_detail = {
                'VolumeId': volume_id,
                'Name': volume_name,
                'Size': size,
                'Type': volume_type,
                'State': state,
                'CreateTime': create_time.isoformat(),
                'EstimatedMonthlyCost': f'${monthly_cost:.2f}',
                'Tags': tags
            }
            
            if state == 'in-use':
                attached_volumes += 1
                volume_detail['Status'] = 'Attached'
            
            elif state == 'available':
                unattached_volumes += 1
                unattached_storage_gb += size
                unattached_estimated_cost += monthly_cost
                volume_detail['Status'] = 'Unattached'
                volume_detail['OptimizationOpportunity'] = 'Unattached - Consider deletion after backup'
                
                # Check if scheduled for deletion
                if tags.get('CostOptimization:ScheduledDeletion') == 'true':
                    scheduled_for_deletion += 1
                    volume_detail['ScheduledForDeletion'] = True
                    backup_snapshot = tags.get('CostOptimization:BackupSnapshot')
                    if backup_snapshot:
                        volume_detail['BackupSnapshot'] = backup_snapshot
            
            volume_details.append(volume_detail)
        
        return {
            'summary': {
                'TotalVolumes': total_volumes,
                'AttachedVolumes': attached_volumes,
                'UnattachedVolumes': unattached_volumes,
                'ScheduledForDeletion': scheduled_for_deletion,
                'TotalStorageGB': total_storage_gb,
                'UnattachedStorageGB': unattached_storage_gb,
                'TotalEstimatedMonthlyCost': f'${total_estimated_cost:.2f}',
                'UnattachedVolumesEstimatedMonthlyCost': f'${unattached_estimated_cost:.2f}',
                'PotentialMonthlySavings': f'${unattached_estimated_cost:.2f}'
            },
            'details': volume_details
        }
    
    except Exception as e:
        logger.error(f"Error analyzing EBS volumes: {str(e)}")
        return {
            'summary': {'Error': str(e)},
            'details': []
        }


def calculate_total_savings_opportunity(report_data: Dict[str, Any]) -> float:
    """
    Calculate total estimated monthly savings opportunity
    
    Args:
        report_data: Complete report data
        
    Returns:
        Total estimated monthly savings in USD
    """
    total_savings = 0.0
    
    try:
        # Extract savings from EBS analysis
        ebs_summary = report_data.get('Summary', {}).get('EBSAnalysis', {})
        ebs_savings_str = ebs_summary.get('PotentialMonthlySavings', '$0.00')
        ebs_savings = float(ebs_savings_str.replace('$', '').replace(',', ''))
        total_savings += ebs_savings
        
        # Extract savings from EC2 idle instances
        ec2_summary = report_data.get('Summary', {}).get('EC2Analysis', {})
        idle_savings_str = ec2_summary.get('IdleInstancesSavingsOpportunity', '$0.00')
        idle_savings = float(idle_savings_str.replace('$', '').replace(',', ''))
        total_savings += idle_savings
        
    except (ValueError, TypeError) as e:
        logger.error(f"Error calculating total savings: {str(e)}")
    
    return total_savings


def generate_recommendations(report_data: Dict[str, Any]) -> List[Dict[str, Any]]:
    """
    Generate cost optimization recommendations based on analysis
    
    Args:
        report_data: Complete report data
        
    Returns:
        List of recommendations
    """
    recommendations = []
    
    try:
        ec2_summary = report_data.get('Summary', {}).get('EC2Analysis', {})
        ebs_summary = report_data.get('Summary', {}).get('EBSAnalysis', {})
        
        # Idle instances recommendation
        idle_instances = ec2_summary.get('IdleInstances', 0)
        if idle_instances > 0:
            recommendations.append({
                'Priority': 'High',
                'Category': 'Compute Optimization',
                'Title': 'Address Idle EC2 Instances',
                'Description': f'Found {idle_instances} idle EC2 instances with low CPU utilization',
                'Recommendation': 'Review idle instances for right-sizing, scheduling, or termination',
                'EstimatedSavings': ec2_summary.get('IdleInstancesSavingsOpportunity', '$0'),
                'Effort': 'Medium',
                'Risk': 'Low'
            })
        
        # Unattached volumes recommendation
        unattached_volumes = ebs_summary.get('UnattachedVolumes', 0)
        if unattached_volumes > 0:
            recommendations.append({
                'Priority': 'High',
                'Category': 'Storage Optimization',
                'Title': 'Clean Up Unattached EBS Volumes',
                'Description': f'Found {unattached_volumes} unattached EBS volumes consuming storage costs',
                'Recommendation': 'Review unattached volumes and delete after creating backups',
                'EstimatedSavings': ebs_summary.get('PotentialMonthlySavings', '$0'),
                'Effort': 'Low',
                'Risk': 'Low'
            })
        
        # Config compliance recommendation
        config_summary = report_data.get('Summary', {}).get('ConfigCompliance', {})
        non_compliant = config_summary.get('TotalNonCompliantResources', 0)
        if non_compliant > 0:
            recommendations.append({
                'Priority': 'Medium',
                'Category': 'Governance',
                'Title': 'Improve Config Rule Compliance',
                'Description': f'Found {non_compliant} non-compliant resources',
                'Recommendation': 'Review and remediate non-compliant resources to improve cost efficiency',
                'EstimatedSavings': 'Variable',
                'Effort': 'Medium',
                'Risk': 'Low'
            })
        
        # General recommendations
        recommendations.extend([
            {
                'Priority': 'Medium',
                'Category': 'Monitoring',
                'Title': 'Implement Regular Cost Reviews',
                'Description': 'Establish weekly cost governance reviews',
                'Recommendation': 'Schedule regular review meetings to assess cost optimization progress',
                'EstimatedSavings': '5-10% ongoing',
                'Effort': 'Low',
                'Risk': 'None'
            },
            {
                'Priority': 'Low',
                'Category': 'Automation',
                'Title': 'Enhance Automation Coverage',
                'Description': 'Expand cost governance automation to additional services',
                'Recommendation': 'Consider adding RDS, Lambda, and other service monitoring',
                'EstimatedSavings': '10-15% potential',
                'Effort': 'High',
                'Risk': 'Low'
            }
        ])
        
    except Exception as e:
        logger.error(f"Error generating recommendations: {str(e)}")
    
    return recommendations


def identify_cost_opportunities(report_data: Dict[str, Any]) -> List[Dict[str, Any]]:
    """
    Identify top cost optimization opportunities
    
    Args:
        report_data: Complete report data
        
    Returns:
        List of cost optimization opportunities
    """
    opportunities = []
    
    try:
        # Analyze EC2 instances for optimization
        ec2_details = report_data.get('Details', {}).get('EC2Resources', [])
        for instance in ec2_details:
            if instance.get('OptimizationOpportunity'):
                opportunities.append({
                    'Type': 'EC2 Instance',
                    'ResourceId': instance['InstanceId'],
                    'ResourceName': instance['Name'],
                    'Opportunity': instance['OptimizationOpportunity'],
                    'MonthlySavings': instance.get('PotentialMonthlySavings', 0),
                    'CurrentCost': instance['EstimatedMonthlyCost'],
                    'Action': 'Review and optimize'
                })
        
        # Analyze EBS volumes for optimization
        ebs_details = report_data.get('Details', {}).get('EBSVolumes', [])
        for volume in ebs_details:
            if volume.get('OptimizationOpportunity'):
                opportunities.append({
                    'Type': 'EBS Volume',
                    'ResourceId': volume['VolumeId'],
                    'ResourceName': volume['Name'],
                    'Opportunity': volume['OptimizationOpportunity'],
                    'MonthlySavings': volume['EstimatedMonthlyCost'],
                    'CurrentCost': volume['EstimatedMonthlyCost'],
                    'Action': 'Create backup and delete'
                })
        
        # Sort by potential savings (descending)
        opportunities.sort(key=lambda x: float(str(x.get('MonthlySavings', 0)).replace('$', '').replace(',', '')), reverse=True)
        
    except Exception as e:
        logger.error(f"Error identifying cost opportunities: {str(e)}")
    
    return opportunities[:10]  # Return top 10 opportunities


def save_report_to_s3(s3_client, bucket: str, report_data: Dict[str, Any]) -> str:
    """
    Save detailed report to S3
    
    Args:
        s3_client: S3 boto3 client
        bucket: S3 bucket name
        report_data: Report data to save
        
    Returns:
        S3 key of saved report
    """
    timestamp = datetime.utcnow()
    report_key = f"cost-governance-reports/{timestamp.strftime('%Y/%m/%d')}/detailed-report-{timestamp.strftime('%Y%m%d-%H%M%S')}.json"
    
    s3_client.put_object(
        Bucket=bucket,
        Key=report_key,
        Body=json.dumps(report_data, indent=2, default=str),
        ContentType='application/json',
        Metadata={
            'ReportType': 'CostGovernanceDetailed',
            'GeneratedDate': timestamp.isoformat(),
            'Version': '1.0'
        }
    )
    
    return report_key


def save_csv_summary_to_s3(s3_client, bucket: str, report_data: Dict[str, Any]) -> str:
    """
    Save CSV summary to S3
    
    Args:
        s3_client: S3 boto3 client
        bucket: S3 bucket name
        report_data: Report data to save
        
    Returns:
        S3 key of saved CSV
    """
    timestamp = datetime.utcnow()
    csv_key = f"cost-governance-reports/{timestamp.strftime('%Y/%m/%d')}/summary-{timestamp.strftime('%Y%m%d-%H%M%S')}.csv"
    
    # Create CSV content
    csv_buffer = StringIO()
    writer = csv.writer(csv_buffer)
    
    # Write summary data
    writer.writerow(['Metric', 'Value'])
    writer.writerow(['Report Date', report_data['ReportDate']])
    writer.writerow(['Total Estimated Monthly Savings', f"${report_data['Summary'].get('TotalEstimatedMonthlySavings', 0):.2f}"])
    
    # EC2 Summary
    ec2_summary = report_data.get('Summary', {}).get('EC2Analysis', {})
    writer.writerow(['Running Instances', ec2_summary.get('RunningInstances', 0)])
    writer.writerow(['Idle Instances', ec2_summary.get('IdleInstances', 0)])
    writer.writerow(['Stopped Instances', ec2_summary.get('StoppedInstances', 0)])
    
    # EBS Summary
    ebs_summary = report_data.get('Summary', {}).get('EBSAnalysis', {})
    writer.writerow(['Total Volumes', ebs_summary.get('TotalVolumes', 0)])
    writer.writerow(['Unattached Volumes', ebs_summary.get('UnattachedVolumes', 0)])
    writer.writerow(['Unattached Storage GB', ebs_summary.get('UnattachedStorageGB', 0)])
    
    s3_client.put_object(
        Bucket=bucket,
        Key=csv_key,
        Body=csv_buffer.getvalue(),
        ContentType='text/csv',
        Metadata={
            'ReportType': 'CostGovernanceSummary',
            'GeneratedDate': timestamp.isoformat(),
            'Version': '1.0'
        }
    )
    
    return csv_key


def send_summary_notification(sns_client, topic_arn: str, report_data: Dict[str, Any], bucket: str, report_key: str):
    """
    Send summary notification via SNS
    
    Args:
        sns_client: SNS boto3 client
        topic_arn: SNS topic ARN
        report_data: Report data
        bucket: S3 bucket name
        report_key: S3 key for detailed report
    """
    summary = report_data.get('Summary', {})
    
    message = {
        'Alert': 'Weekly Cost Governance Report',
        'ReportDate': report_data['ReportDate'],
        'ExecutiveSummary': {
            'TotalEstimatedMonthlySavings': f"${summary.get('TotalEstimatedMonthlySavings', 0):.2f}",
            'EC2Analysis': summary.get('EC2Analysis', {}),
            'EBSAnalysis': summary.get('EBSAnalysis', {}),
            'ConfigCompliance': summary.get('ConfigCompliance', {})
        },
        'TopRecommendations': report_data.get('Recommendations', [])[:3],
        'ReportsLocation': {
            'DetailedReport': f"s3://{bucket}/{report_key}",
            'CSVSummary': f"s3://{bucket}/{report_key.replace('.json', '.csv')}"
        },
        'NextActions': [
            'Review detailed report for specific optimization opportunities',
            'Address high-priority recommendations first',
            'Schedule follow-up review in one week'
        ]
    }
    
    sns_client.publish(
        TopicArn=topic_arn,
        Subject=f"Cost Governance Report - ${summary.get('TotalEstimatedMonthlySavings', 0):.2f} Monthly Savings Opportunity",
        Message=json.dumps(message, indent=2, default=str)
    )


def estimate_instance_monthly_cost(instance_type: str) -> float:
    """
    Estimate monthly cost for EC2 instance type
    
    Args:
        instance_type: EC2 instance type
        
    Returns:
        Estimated monthly cost in USD
    """
    # Simplified cost estimates (US East 1, Linux/Unix, On-Demand)
    cost_estimates = {
        't3.nano': 3.80, 't3.micro': 7.59, 't3.small': 15.18, 't3.medium': 30.37,
        't3.large': 60.74, 't3.xlarge': 121.47, 't3.2xlarge': 242.94,
        'm5.large': 69.35, 'm5.xlarge': 138.70, 'm5.2xlarge': 277.40,
        'c5.large': 61.56, 'c5.xlarge': 123.12, 'c5.2xlarge': 246.24,
        'r5.large': 90.50, 'r5.xlarge': 181.00, 'r5.2xlarge': 362.00
    }
    
    return cost_estimates.get(instance_type, 100.0)


def calculate_volume_monthly_cost(size_gb: int, volume_type: str) -> float:
    """
    Calculate monthly cost for EBS volume
    
    Args:
        size_gb: Volume size in GB
        volume_type: EBS volume type
        
    Returns:
        Monthly cost in USD
    """
    cost_per_gb_month = {
        'gp2': 0.10, 'gp3': 0.08, 'io1': 0.125, 'io2': 0.125,
        'st1': 0.045, 'sc1': 0.025, 'standard': 0.05
    }
    
    cost_per_gb = cost_per_gb_month.get(volume_type.lower(), 0.10)
    return size_gb * cost_per_gb