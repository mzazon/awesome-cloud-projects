#!/usr/bin/env python3
"""
FSx Cost Reporting Lambda Function

This function analyzes FSx usage metrics and generates detailed cost 
optimization reports, saving them to S3 for analysis and tracking.
"""

import json
import boto3
import datetime
import csv
import logging
import os
from io import StringIO
from typing import Dict, List, Optional
from botocore.exceptions import ClientError

# Configure logging
log_level = os.environ.get('LOG_LEVEL', 'INFO')
logging.basicConfig(level=getattr(logging, log_level))
logger = logging.getLogger(__name__)

# AWS clients
fsx_client = boto3.client('fsx')
cloudwatch = boto3.client('cloudwatch')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Main Lambda handler function for FSx cost reporting
    """
    logger.info("Starting FSx cost report generation")
    
    try:
        # Get environment variables
        s3_bucket_name = os.environ.get('S3_BUCKET_NAME', '${s3_bucket_name}')
        
        if not s3_bucket_name or s3_bucket_name.startswith('$'):
            logger.error("S3_BUCKET_NAME environment variable not properly set")
            return create_error_response("Missing S3_BUCKET_NAME environment variable")
        
        # Get all FSx file systems (or filter by specific one if provided)
        file_systems_response = fsx_client.describe_file_systems()
        file_systems = file_systems_response.get('FileSystems', [])
        
        if not file_systems:
            logger.warning("No FSx file systems found")
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'No FSx file systems found',
                    'reports_generated': 0
                })
            }
        
        reports_generated = 0
        total_estimated_cost = 0.0
        
        # Process each FSx file system
        for fs in file_systems:
            if fs.get('FileSystemType') == 'OpenZFS':
                fs_id = fs['FileSystemId']
                logger.info(f"Processing FSx file system: {fs_id}")
                
                # Collect usage metrics
                usage_data = collect_usage_metrics(fs_id)
                
                # Generate cost report
                report = generate_cost_report(fs, usage_data)
                
                # Save report to S3
                report_path = save_report_to_s3(s3_bucket_name, fs_id, report)
                
                if report_path:
                    reports_generated += 1
                    total_estimated_cost += report.get('estimated_monthly_cost', 0)
                    logger.info(f"Successfully generated report for {fs_id}: {report_path}")
        
        # Generate summary report
        if reports_generated > 0:
            summary_path = generate_summary_report(s3_bucket_name, file_systems, total_estimated_cost)
            logger.info(f"Generated summary report: {summary_path}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Cost reports generated successfully',
                'reports_generated': reports_generated,
                'total_estimated_monthly_cost': round(total_estimated_cost, 2),
                's3_bucket': s3_bucket_name
            })
        }
        
    except ClientError as e:
        error_msg = f"AWS API error: {e.response['Error']['Code']} - {e.response['Error']['Message']}"
        logger.error(error_msg)
        return create_error_response(error_msg)
    except Exception as e:
        error_msg = f"Unexpected error: {str(e)}"
        logger.error(error_msg, exc_info=True)
        return create_error_response(error_msg)

def collect_usage_metrics(file_system_id: str) -> Dict:
    """Collect comprehensive usage metrics for cost analysis"""
    end_time = datetime.datetime.utcnow()
    start_time = end_time - datetime.timedelta(days=7)  # 7-day analysis window
    
    metrics = {}
    
    # Define metrics to collect
    metric_definitions = {
        'StorageUtilization': {'unit': 'Percent', 'description': 'Storage capacity utilization'},
        'FileServerCacheHitRatio': {'unit': 'Percent', 'description': 'Cache hit ratio for performance analysis'},
        'NetworkThroughputUtilization': {'unit': 'Percent', 'description': 'Network throughput utilization'},
        'DataReadBytes': {'unit': 'Bytes', 'description': 'Total bytes read from file system'},
        'DataWriteBytes': {'unit': 'Bytes', 'description': 'Total bytes written to file system'},
        'TotalReadTime': {'unit': 'Seconds', 'description': 'Total time spent on read operations'},
        'TotalWriteTime': {'unit': 'Seconds', 'description': 'Total time spent on write operations'}
    }
    
    for metric_name, metric_info in metric_definitions.items():
        try:
            response = cloudwatch.get_metric_statistics(
                Namespace='AWS/FSx',
                MetricName=metric_name,
                Dimensions=[
                    {
                        'Name': 'FileSystemId',
                        'Value': file_system_id
                    }
                ],
                StartTime=start_time,
                EndTime=end_time,
                Period=3600,  # 1-hour periods for better granularity
                Statistics=['Average', 'Maximum', 'Sum']
            )
            
            datapoints = response.get('Datapoints', [])
            if datapoints:
                metrics[metric_name] = {
                    'datapoints': datapoints,
                    'unit': metric_info['unit'],
                    'description': metric_info['description'],
                    'average': sum(dp['Average'] for dp in datapoints) / len(datapoints),
                    'maximum': max(dp['Maximum'] for dp in datapoints),
                    'total': sum(dp.get('Sum', 0) for dp in datapoints) if metric_info['unit'] == 'Bytes' else None
                }
            else:
                logger.warning(f"No data available for metric {metric_name}")
                
        except ClientError as e:
            logger.warning(f"Could not retrieve metric {metric_name}: {e}")
    
    return metrics

def generate_cost_report(file_system: Dict, usage_data: Dict) -> Dict:
    """Generate comprehensive cost optimization report"""
    fs_id = file_system['FileSystemId']
    storage_capacity = file_system.get('StorageCapacity', 0)
    throughput_capacity = file_system.get('ThroughputCapacity', 0)
    storage_type = file_system.get('StorageType', 'SSD')
    deployment_type = file_system.get('DeploymentType', 'SINGLE_AZ_1')
    
    # Base pricing assumptions (approximate, varies by region)
    # These should be updated based on current AWS pricing
    pricing = {
        'throughput_cost_per_mbps': 0.30,  # USD per MBps per month
        'storage_cost_ssd': 0.15,          # USD per GiB per month for SSD
        'storage_cost_intelligent_tiering': 0.08,  # USD per GiB per month for Intelligent Tiering
        'backup_cost': 0.05,               # USD per GiB per month for backups
        'data_transfer_cost': 0.09         # USD per GB for data transfer out
    }
    
    # Calculate base costs
    base_throughput_cost = throughput_capacity * pricing['throughput_cost_per_mbps']
    
    # Storage cost depends on storage type
    if storage_type == 'INTELLIGENT_TIERING':
        storage_cost = storage_capacity * pricing['storage_cost_intelligent_tiering']
        storage_type_savings = (storage_capacity * pricing['storage_cost_ssd']) - storage_cost
    else:
        storage_cost = storage_capacity * pricing['storage_cost_ssd']
        storage_type_savings = 0
    
    # Backup cost estimation (if backups are enabled)
    backup_retention_days = file_system.get('AutomaticBackupRetentionDays', 0)
    backup_cost = 0
    if backup_retention_days > 0:
        # Estimate backup size as 10% of storage capacity (conservative estimate)
        backup_size = storage_capacity * 0.1
        backup_cost = backup_size * pricing['backup_cost']
    
    monthly_cost = base_throughput_cost + storage_cost + backup_cost
    
    # Analyze usage efficiency
    storage_metrics = usage_data.get('StorageUtilization', {})
    cache_metrics = usage_data.get('FileServerCacheHitRatio', {})
    throughput_metrics = usage_data.get('NetworkThroughputUtilization', {})
    
    avg_storage_utilization = storage_metrics.get('average', 0)
    avg_cache_hit_ratio = cache_metrics.get('average', 0)
    avg_throughput_utilization = throughput_metrics.get('average', 0)
    
    # Calculate data transfer metrics
    read_bytes = usage_data.get('DataReadBytes', {}).get('total', 0)
    write_bytes = usage_data.get('DataWriteBytes', {}).get('total', 0)
    total_data_gb = (read_bytes + write_bytes) / (1024**3) if read_bytes or write_bytes else 0
    
    # Generate report
    report = {
        'file_system_id': fs_id,
        'report_date': datetime.datetime.utcnow().isoformat(),
        'file_system_config': {
            'storage_capacity_gb': storage_capacity,
            'throughput_capacity_mbps': throughput_capacity,
            'storage_type': storage_type,
            'deployment_type': deployment_type,
            'backup_retention_days': backup_retention_days
        },
        'estimated_monthly_cost': monthly_cost,
        'cost_breakdown': {
            'throughput_cost': base_throughput_cost,
            'storage_cost': storage_cost,
            'backup_cost': backup_cost,
            'estimated_data_transfer_cost': total_data_gb * pricing['data_transfer_cost'] * 0.1  # Assume 10% goes out
        },
        'usage_efficiency': {
            'average_storage_utilization': round(avg_storage_utilization, 2),
            'average_cache_hit_ratio': round(avg_cache_hit_ratio, 2),
            'average_throughput_utilization': round(avg_throughput_utilization, 2),
            'total_data_processed_gb': round(total_data_gb, 2),
            'storage_efficiency_score': calculate_efficiency_score(avg_storage_utilization, avg_cache_hit_ratio, avg_throughput_utilization)
        },
        'cost_optimization_opportunities': [],
        'intelligent_tiering_savings': storage_type_savings if storage_type != 'INTELLIGENT_TIERING' else 0
    }
    
    # Generate optimization recommendations
    recommendations = generate_optimization_recommendations(report)
    report['cost_optimization_opportunities'] = recommendations
    
    return report

def calculate_efficiency_score(storage_util: float, cache_hit_ratio: float, throughput_util: float) -> int:
    """Calculate an efficiency score from 0-100 based on utilization metrics"""
    # Ideal ranges: Storage: 60-80%, Cache Hit: 80-95%, Throughput: 40-70%
    storage_score = 100 if 60 <= storage_util <= 80 else max(0, 100 - abs(storage_util - 70) * 2)
    cache_score = 100 if 80 <= cache_hit_ratio <= 95 else max(0, 100 - abs(cache_hit_ratio - 87.5) * 2)
    throughput_score = 100 if 40 <= throughput_util <= 70 else max(0, 100 - abs(throughput_util - 55) * 2)
    
    # Weighted average (storage utilization is most important for cost)
    efficiency_score = int((storage_score * 0.5) + (cache_score * 0.3) + (throughput_score * 0.2))
    return max(0, min(100, efficiency_score))

def generate_optimization_recommendations(report: Dict) -> List[Dict]:
    """Generate specific cost optimization recommendations"""
    recommendations = []
    
    efficiency = report['usage_efficiency']
    costs = report['cost_breakdown']
    config = report['file_system_config']
    
    # Storage utilization recommendations
    if efficiency['average_storage_utilization'] < 50:
        potential_savings = costs['storage_cost'] * 0.3  # Estimate 30% savings
        recommendations.append({
            'type': 'storage_optimization',
            'priority': 'high',
            'description': f'Low storage utilization ({efficiency["average_storage_utilization"]:.1f}%) - consider reducing capacity',
            'potential_monthly_savings': round(potential_savings, 2),
            'action': 'Review current storage allocation and consider downsizing'
        })
    
    # Intelligent Tiering recommendation
    if config['storage_type'] != 'INTELLIGENT_TIERING' and report['intelligent_tiering_savings'] > 10:
        recommendations.append({
            'type': 'intelligent_tiering',
            'priority': 'high',
            'description': 'Switch to Intelligent Tiering for automatic cost optimization',
            'potential_monthly_savings': round(report['intelligent_tiering_savings'], 2),
            'action': 'Migrate to Intelligent Tiering storage class'
        })
    
    # Cache optimization recommendations
    if efficiency['average_cache_hit_ratio'] < 70:
        recommendations.append({
            'type': 'cache_optimization',
            'priority': 'medium',
            'description': f'Low cache hit ratio ({efficiency["average_cache_hit_ratio"]:.1f}%) affecting performance',
            'potential_monthly_savings': 0,  # Performance improvement rather than cost savings
            'action': 'Analyze access patterns and consider cache configuration adjustments'
        })
    
    # Throughput optimization recommendations
    if efficiency['average_throughput_utilization'] < 20:
        potential_savings = costs['throughput_cost'] * 0.25  # Estimate 25% savings
        recommendations.append({
            'type': 'throughput_optimization',
            'priority': 'medium',
            'description': f'Low throughput utilization ({efficiency["average_throughput_utilization"]:.1f}%) - consider rightsizing',
            'potential_monthly_savings': round(potential_savings, 2),
            'action': 'Review throughput requirements and consider reducing provisioned capacity'
        })
    elif efficiency['average_throughput_utilization'] > 80:
        recommendations.append({
            'type': 'throughput_scaling',
            'priority': 'high',
            'description': f'High throughput utilization ({efficiency["average_throughput_utilization"]:.1f}%) may impact performance',
            'potential_monthly_savings': 0,
            'action': 'Consider increasing throughput capacity to avoid performance bottlenecks'
        })
    
    # Backup optimization
    if config['backup_retention_days'] > 30 and costs['backup_cost'] > 5:
        potential_savings = costs['backup_cost'] * 0.4  # Estimate 40% savings
        recommendations.append({
            'type': 'backup_optimization',
            'priority': 'low',
            'description': f'Long backup retention ({config["backup_retention_days"]} days) increases costs',
            'potential_monthly_savings': round(potential_savings, 2),
            'action': 'Review backup retention requirements and consider reducing retention period'
        })
    
    return recommendations

def save_report_to_s3(bucket_name: str, file_system_id: str, report: Dict) -> Optional[str]:
    """Save detailed cost report to S3 as CSV"""
    try:
        # Create CSV report
        csv_buffer = StringIO()
        writer = csv.writer(csv_buffer)
        
        # Write header information
        writer.writerow(['FSx Cost Optimization Report'])
        writer.writerow(['Generated:', report['report_date']])
        writer.writerow(['File System ID:', report['file_system_id']])
        writer.writerow([])
        
        # Write configuration section
        writer.writerow(['CONFIGURATION'])
        for key, value in report['file_system_config'].items():
            writer.writerow([key.replace('_', ' ').title(), value])
        writer.writerow([])
        
        # Write cost breakdown
        writer.writerow(['COST BREAKDOWN (USD/Month)'])
        writer.writerow(['Total Estimated Cost', f"${report['estimated_monthly_cost']:.2f}"])
        for key, value in report['cost_breakdown'].items():
            writer.writerow([key.replace('_', ' ').title(), f"${value:.2f}"])
        writer.writerow([])
        
        # Write usage efficiency
        writer.writerow(['USAGE EFFICIENCY'])
        for key, value in report['usage_efficiency'].items():
            if key == 'storage_efficiency_score':
                writer.writerow([key.replace('_', ' ').title(), f"{value}/100"])
            elif 'percentage' in key or 'ratio' in key or 'utilization' in key:
                writer.writerow([key.replace('_', ' ').title(), f"{value}%"])
            else:
                writer.writerow([key.replace('_', ' ').title(), value])
        writer.writerow([])
        
        # Write recommendations
        writer.writerow(['COST OPTIMIZATION RECOMMENDATIONS'])
        writer.writerow(['Type', 'Priority', 'Description', 'Potential Savings (USD/Month)', 'Recommended Action'])
        for rec in report['cost_optimization_opportunities']:
            writer.writerow([
                rec['type'].replace('_', ' ').title(),
                rec['priority'].upper(),
                rec['description'],
                f"${rec['potential_monthly_savings']:.2f}" if rec['potential_monthly_savings'] > 0 else "N/A",
                rec['action']
            ])
        
        # Save to S3
        timestamp = datetime.datetime.utcnow().strftime('%Y%m%d_%H%M%S')
        key = f"cost-reports/{file_system_id}/report_{timestamp}.csv"
        
        s3.put_object(
            Bucket=bucket_name,
            Key=key,
            Body=csv_buffer.getvalue(),
            ContentType='text/csv',
            Metadata={
                'file-system-id': file_system_id,
                'report-type': 'cost-optimization',
                'generated-by': 'fsx-cost-reporting-lambda'
            }
        )
        
        logger.info(f"Report saved to s3://{bucket_name}/{key}")
        return key
        
    except ClientError as e:
        logger.error(f"Error saving report to S3: {e}")
        return None

def generate_summary_report(bucket_name: str, file_systems: List[Dict], total_cost: float) -> Optional[str]:
    """Generate a summary report across all file systems"""
    try:
        csv_buffer = StringIO()
        writer = csv.writer(csv_buffer)
        
        # Write summary header
        writer.writerow(['FSx Cost Summary Report'])
        writer.writerow(['Generated:', datetime.datetime.utcnow().isoformat()])
        writer.writerow(['Total File Systems:', len(file_systems)])
        writer.writerow(['Total Estimated Monthly Cost:', f"${total_cost:.2f}"])
        writer.writerow([])
        
        # Write file system summary
        writer.writerow(['FILE SYSTEM SUMMARY'])
        writer.writerow(['File System ID', 'Storage Type', 'Storage Capacity (GB)', 'Throughput Capacity (Mbps)', 'Deployment Type'])
        
        for fs in file_systems:
            if fs.get('FileSystemType') == 'OpenZFS':
                writer.writerow([
                    fs['FileSystemId'],
                    fs.get('StorageType', 'SSD'),
                    fs.get('StorageCapacity', 0),
                    fs.get('ThroughputCapacity', 0),
                    fs.get('DeploymentType', 'SINGLE_AZ_1')
                ])
        
        # Save to S3
        timestamp = datetime.datetime.utcnow().strftime('%Y%m%d_%H%M%S')
        key = f"cost-reports/summary/summary_{timestamp}.csv"
        
        s3.put_object(
            Bucket=bucket_name,
            Key=key,
            Body=csv_buffer.getvalue(),
            ContentType='text/csv',
            Metadata={
                'report-type': 'cost-summary',
                'generated-by': 'fsx-cost-reporting-lambda'
            }
        )
        
        return key
        
    except ClientError as e:
        logger.error(f"Error saving summary report to S3: {e}")
        return None

def create_error_response(error_message: str) -> Dict:
    """Create standardized error response"""
    return {
        'statusCode': 500,
        'body': json.dumps({
            'error': error_message,
            'timestamp': datetime.datetime.utcnow().isoformat()
        })
    }