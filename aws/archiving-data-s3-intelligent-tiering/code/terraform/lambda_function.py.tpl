import json
import boto3
import os
from datetime import datetime, timedelta
from decimal import Decimal

def lambda_handler(event, context):
    """
    Lambda function to monitor sustainability metrics for S3 Intelligent-Tiering
    This function calculates storage efficiency and estimates carbon footprint reduction
    """
    s3 = boto3.client('s3')
    cloudwatch = boto3.client('cloudwatch')
    
    bucket_name = os.environ['ARCHIVE_BUCKET']
    
    try:
        # Get bucket tagging to identify sustainability goals
        tags_response = s3.get_bucket_tagging(Bucket=bucket_name)
        tags = {tag['Key']: tag['Value'] for tag in tags_response['TagSet']}
        
        # Calculate storage metrics
        storage_metrics = calculate_storage_efficiency(s3, bucket_name)
        
        # Estimate carbon footprint reduction
        carbon_metrics = calculate_carbon_impact(storage_metrics)
        
        # Publish custom CloudWatch metrics
        publish_sustainability_metrics(cloudwatch, storage_metrics, carbon_metrics)
        
        # Generate sustainability report
        report = generate_sustainability_report(storage_metrics, carbon_metrics, tags)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Sustainability analysis completed',
                'report': report
            }, default=decimal_default)
        }
        
    except Exception as e:
        print(f"Error in sustainability monitoring: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def calculate_storage_efficiency(s3, bucket_name):
    """Calculate storage efficiency metrics"""
    try:
        # Get bucket size metrics from CloudWatch (simplified for demo)
        total_objects = 0
        total_size = 0
        storage_classes = {}
        
        # Use S3 list objects to get current metrics
        paginator = s3.get_paginator('list_objects_v2')
        
        for page in paginator.paginate(Bucket=bucket_name):
            if 'Contents' in page:
                for obj in page['Contents']:
                    total_objects += 1
                    total_size += obj['Size']
                    
                    # Track storage class distribution
                    storage_class = obj.get('StorageClass', 'STANDARD')
                    storage_classes[storage_class] = storage_classes.get(storage_class, 0) + 1
        
        return {
            'total_objects': total_objects,
            'total_size_gb': round(total_size / (1024**3), 2),
            'average_object_size_mb': round((total_size / total_objects) / (1024**2), 2) if total_objects > 0 else 0,
            'storage_class_distribution': storage_classes
        }
    except Exception as e:
        print(f"Error calculating storage metrics: {str(e)}")
        return {
            'total_objects': 0, 
            'total_size_gb': 0, 
            'average_object_size_mb': 0,
            'storage_class_distribution': {}
        }

def calculate_carbon_impact(storage_metrics):
    """
    Estimate carbon footprint reduction through intelligent tiering
    Based on AWS sustainability data and energy consumption patterns
    """
    # AWS estimates for carbon impact per GB per month (simplified model)
    # These are approximate values based on AWS sustainability reports
    carbon_factors = {
        'STANDARD': 0.000385,           # Standard storage baseline
        'INTELLIGENT_TIERING': 0.000308, # 20% reduction from automated optimization
        'STANDARD_IA': 0.000308,        # Infrequent access tier
        'GLACIER': 0.000154,            # 60% reduction
        'DEEP_ARCHIVE': 0.000077,       # 80% reduction
        'GLACIER_IR': 0.000231          # Glacier Instant Retrieval
    }
    
    total_size_gb = storage_metrics['total_size_gb']
    storage_distribution = storage_metrics['storage_class_distribution']
    
    if total_size_gb == 0:
        return {
            'estimated_monthly_carbon_kg': 0,
            'estimated_monthly_savings_kg': 0,
            'carbon_reduction_percentage': 0
        }
    
    # Calculate actual carbon footprint based on storage class distribution
    actual_carbon = 0
    total_objects = storage_metrics['total_objects']
    
    for storage_class, object_count in storage_distribution.items():
        if storage_class in carbon_factors:
            # Estimate size proportion for this storage class
            size_proportion = object_count / total_objects if total_objects > 0 else 0
            class_size_gb = total_size_gb * size_proportion
            actual_carbon += class_size_gb * carbon_factors[storage_class]
        else:
            # Default to standard storage carbon factor for unknown classes
            size_proportion = object_count / total_objects if total_objects > 0 else 0
            class_size_gb = total_size_gb * size_proportion
            actual_carbon += class_size_gb * carbon_factors['STANDARD']
    
    # Calculate savings compared to all standard storage
    baseline_carbon = total_size_gb * carbon_factors['STANDARD']
    carbon_saved = baseline_carbon - actual_carbon
    
    return {
        'estimated_monthly_carbon_kg': round(actual_carbon, 4),
        'estimated_monthly_savings_kg': round(carbon_saved, 4),
        'carbon_reduction_percentage': round((carbon_saved / baseline_carbon) * 100, 1) if baseline_carbon > 0 else 0,
        'baseline_carbon_kg': round(baseline_carbon, 4)
    }

def publish_sustainability_metrics(cloudwatch, storage_metrics, carbon_metrics):
    """Publish custom metrics to CloudWatch for dashboard visualization"""
    try:
        metrics = [
            {
                'MetricName': 'TotalStorageGB',
                'Value': storage_metrics['total_size_gb'],
                'Unit': 'Count'
            },
            {
                'MetricName': 'TotalObjects',
                'Value': storage_metrics['total_objects'],
                'Unit': 'Count'
            },
            {
                'MetricName': 'AverageObjectSizeMB',
                'Value': storage_metrics['average_object_size_mb'],
                'Unit': 'Count'
            },
            {
                'MetricName': 'EstimatedMonthlyCarbonKg',
                'Value': carbon_metrics['estimated_monthly_carbon_kg'],
                'Unit': 'Count'
            },
            {
                'MetricName': 'CarbonSavingsKg',
                'Value': carbon_metrics['estimated_monthly_savings_kg'],
                'Unit': 'Count'
            },
            {
                'MetricName': 'CarbonReductionPercentage',
                'Value': carbon_metrics['carbon_reduction_percentage'],
                'Unit': 'Percent'
            }
        ]
        
        # Publish storage class distribution metrics
        for storage_class, count in storage_metrics['storage_class_distribution'].items():
            metrics.append({
                'MetricName': f'StorageClass_{storage_class}_Count',
                'Value': count,
                'Unit': 'Count'
            })
        
        # Publish all metrics to CloudWatch
        for metric in metrics:
            cloudwatch.put_metric_data(
                Namespace='SustainableArchive',
                MetricData=[{
                    'MetricName': metric['MetricName'],
                    'Value': metric['Value'],
                    'Unit': metric['Unit'],
                    'Timestamp': datetime.utcnow()
                }]
            )
            
        print(f"Published {len(metrics)} sustainability metrics to CloudWatch")
        
    except Exception as e:
        print(f"Error publishing metrics: {str(e)}")

def generate_sustainability_report(storage_metrics, carbon_metrics, tags):
    """Generate comprehensive sustainability report"""
    return {
        'timestamp': datetime.utcnow().isoformat(),
        'sustainability_goal': tags.get('SustainabilityGoal', 'Not specified'),
        'storage_efficiency': {
            'total_objects': storage_metrics['total_objects'],
            'total_storage_gb': storage_metrics['total_size_gb'],
            'average_object_size_mb': storage_metrics['average_object_size_mb'],
            'storage_class_distribution': storage_metrics['storage_class_distribution']
        },
        'environmental_impact': {
            'estimated_monthly_carbon_kg': carbon_metrics['estimated_monthly_carbon_kg'],
            'monthly_carbon_savings_kg': carbon_metrics['estimated_monthly_savings_kg'],
            'carbon_reduction_percentage': carbon_metrics['carbon_reduction_percentage'],
            'baseline_carbon_kg': carbon_metrics['baseline_carbon_kg']
        },
        'recommendations': generate_recommendations(storage_metrics, carbon_metrics),
        'optimization_status': assess_optimization_status(carbon_metrics)
    }

def generate_recommendations(storage_metrics, carbon_metrics):
    """Generate optimization recommendations based on analysis"""
    recommendations = []
    
    # Analyze object size efficiency
    if storage_metrics['average_object_size_mb'] < 1:
        recommendations.append({
            'category': 'Object Size Optimization',
            'recommendation': 'Consider using S3 Object Lambda to aggregate small objects for better efficiency',
            'priority': 'Medium',
            'potential_benefit': 'Reduced request costs and improved transfer efficiency'
        })
    
    # Analyze carbon reduction effectiveness
    if carbon_metrics['carbon_reduction_percentage'] < 20:
        recommendations.append({
            'category': 'Carbon Footprint Reduction',
            'recommendation': 'Enable Deep Archive Access tier for longer retention periods',
            'priority': 'High',
            'potential_benefit': 'Up to 80% carbon footprint reduction for rarely accessed data'
        })
    elif carbon_metrics['carbon_reduction_percentage'] < 40:
        recommendations.append({
            'category': 'Carbon Footprint Optimization',
            'recommendation': 'Review access patterns to optimize tier transition policies',
            'priority': 'Medium',
            'potential_benefit': 'Additional 10-20% carbon footprint reduction'
        })
    
    # Storage distribution analysis
    distribution = storage_metrics['storage_class_distribution']
    total_objects = storage_metrics['total_objects']
    
    if total_objects > 0:
        standard_percentage = (distribution.get('STANDARD', 0) / total_objects) * 100
        if standard_percentage > 70:
            recommendations.append({
                'category': 'Storage Class Optimization',
                'recommendation': 'High percentage of objects in Standard storage - monitor for automatic tiering opportunities',
                'priority': 'Low',
                'potential_benefit': 'Automatic cost and carbon reduction as objects age'
            })
    
    # General recommendations
    recommendations.append({
        'category': 'Monitoring',
        'recommendation': 'Review S3 Storage Lens reports monthly for additional optimization opportunities',
        'priority': 'Low',
        'potential_benefit': 'Continuous optimization and trend analysis'
    })
    
    return recommendations

def assess_optimization_status(carbon_metrics):
    """Assess the current optimization status based on carbon reduction"""
    reduction_percentage = carbon_metrics['carbon_reduction_percentage']
    
    if reduction_percentage >= 60:
        return {
            'status': 'Excellent',
            'description': 'Achieving significant carbon footprint reduction through intelligent tiering'
        }
    elif reduction_percentage >= 40:
        return {
            'status': 'Good',
            'description': 'Good carbon footprint reduction, with opportunities for further optimization'
        }
    elif reduction_percentage >= 20:
        return {
            'status': 'Fair',
            'description': 'Moderate carbon footprint reduction, consider enabling additional archive tiers'
        }
    else:
        return {
            'status': 'Needs Improvement',
            'description': 'Limited carbon footprint reduction, review intelligent tiering configuration'
        }

def decimal_default(obj):
    """JSON serializer for Decimal objects"""
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError(f"Object of type {type(obj)} is not JSON serializable")