import json
import boto3
import os
from datetime import datetime, timedelta
from decimal import Decimal
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
ce_client = boto3.client('ce')
dynamodb = boto3.resource('dynamodb')
s3_client = boto3.client('s3')
sns_client = boto3.client('sns')
ssm_client = boto3.client('ssm')

# Environment variables
TABLE_NAME = os.environ['DYNAMODB_TABLE']
S3_BUCKET = os.environ['S3_BUCKET']
SNS_TOPIC_ARN = os.environ['SNS_TOPIC_ARN']
PROJECT_NAME = os.environ.get('PROJECT_NAME', 'carbon-optimizer')

# Configuration from template variables
CARBON_OPTIMIZATION_THRESHOLD = ${carbon_optimization_threshold}
HIGH_IMPACT_COST_THRESHOLD = ${high_impact_cost_threshold}

table = dynamodb.Table(TABLE_NAME)

def lambda_handler(event, context):
    """
    Main handler for carbon footprint optimization analysis
    """
    try:
        logger.info("Starting carbon footprint optimization analysis")
        
        # Determine analysis type from event
        analysis_type = event.get('analysis_type', 'monthly')
        detailed = event.get('detailed', True)
        
        # Get current date range for analysis
        end_date = datetime.now().date()
        if analysis_type == 'weekly':
            start_date = end_date - timedelta(days=7)
        else:
            start_date = end_date - timedelta(days=30)
        
        logger.info(f"Analyzing period from {start_date} to {end_date}")
        
        # Fetch cost and usage data
        cost_data = get_cost_and_usage_data(start_date, end_date)
        
        # Analyze carbon footprint correlations
        carbon_analysis = analyze_carbon_footprint(cost_data)
        
        # Store metrics in DynamoDB
        store_metrics(carbon_analysis, analysis_type)
        
        # Generate optimization recommendations
        recommendations = generate_recommendations(carbon_analysis)
        
        # Send notifications if significant findings
        if recommendations['high_impact_actions']:
            send_optimization_notifications(recommendations, analysis_type)
        
        # Store analysis results in S3 for historical tracking
        store_analysis_results(carbon_analysis, recommendations, analysis_type)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Carbon footprint {analysis_type} analysis completed successfully',
                'analysis_period': f'{start_date} to {end_date}',
                'total_cost': float(carbon_analysis['total_cost']),
                'estimated_carbon_kg': float(carbon_analysis['estimated_carbon_kg']),
                'recommendations_count': len(recommendations['all_actions']),
                'high_impact_count': len(recommendations['high_impact_actions']),
                'potential_savings': {
                    'cost_usd': float(recommendations['estimated_savings']['cost']),
                    'carbon_kg': float(recommendations['estimated_savings']['carbon_kg'])
                }
            })
        }
        
    except Exception as e:
        logger.error(f"Error in carbon footprint analysis: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def get_cost_and_usage_data(start_date, end_date):
    """
    Retrieve cost and usage data from Cost Explorer
    """
    try:
        logger.info("Fetching cost and usage data from Cost Explorer")
        response = ce_client.get_cost_and_usage(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity='DAILY',
            Metrics=['BlendedCost', 'UsageQuantity'],
            GroupBy=[
                {'Type': 'DIMENSION', 'Key': 'SERVICE'},
                {'Type': 'DIMENSION', 'Key': 'REGION'}
            ]
        )
        
        logger.info(f"Retrieved {len(response['ResultsByTime'])} time periods of cost data")
        return response['ResultsByTime']
        
    except Exception as e:
        logger.error(f"Error retrieving cost data: {str(e)}")
        raise

def analyze_carbon_footprint(cost_data):
    """
    Analyze carbon footprint patterns based on cost and usage data
    """
    logger.info("Analyzing carbon footprint patterns")
    
    analysis = {
        'total_cost': 0,
        'estimated_carbon_kg': 0,
        'services': {},
        'regions': {},
        'optimization_potential': 0,
        'analysis_timestamp': datetime.now().isoformat()
    }
    
    # Carbon intensity factors (kg CO2e per USD) by service type
    # Based on AWS sustainability data and industry benchmarks
    carbon_factors = {
        'Amazon Elastic Compute Cloud - Compute': 0.5,
        'Amazon Simple Storage Service': 0.1,
        'Amazon Relational Database Service': 0.7,
        'AWS Lambda': 0.05,
        'Amazon CloudFront': 0.02,
        'Amazon DynamoDB': 0.15,
        'Amazon Simple Queue Service': 0.03,
        'Amazon Simple Notification Service': 0.03,
        'Amazon Elastic Container Service': 0.4,
        'Amazon Elastic Kubernetes Service': 0.45,
        'Amazon Redshift': 0.8,
        'Amazon ElastiCache': 0.3,
        'AWS Glue': 0.2,
        'Amazon Kinesis': 0.25,
        'Amazon EMR': 0.6
    }
    
    # Regional carbon intensity factors (kg CO2e per kWh)
    # Based on regional grid carbon intensity
    regional_factors = {
        'us-east-1': 0.4,      # Virginia - renewable energy mix
        'us-west-2': 0.2,      # Oregon - high renewable content
        'us-west-1': 0.35,     # N. California - moderate renewables
        'us-east-2': 0.45,     # Ohio - higher fossil fuel mix
        'eu-west-1': 0.3,      # Ireland - moderate renewable mix
        'eu-central-1': 0.35,  # Frankfurt - mixed energy sources
        'ap-southeast-1': 0.7, # Singapore - higher carbon intensity
        'ap-southeast-2': 0.8, # Sydney - higher carbon intensity
        'ap-northeast-1': 0.5, # Tokyo - mixed energy sources
        'ca-central-1': 0.15,  # Canada - high renewable content
        'global': 0.4          # Global average for services without region
    }
    
    for time_period in cost_data:
        date = time_period['TimePeriod']['Start']
        
        for group in time_period.get('Groups', []):
            if len(group['Keys']) >= 2:
                service = group['Keys'][0]
                region = group['Keys'][1] if group['Keys'][1] else 'global'
            else:
                service = group['Keys'][0] if group['Keys'] else 'Unknown'
                region = 'global'
            
            # Extract cost information
            cost_metrics = group.get('Metrics', {})
            cost = float(cost_metrics.get('BlendedCost', {}).get('Amount', 0))
            
            if cost == 0:
                continue
                
            analysis['total_cost'] += cost
            
            # Calculate estimated carbon footprint
            service_factor = carbon_factors.get(service, 0.3)  # Default factor
            regional_factor = regional_factors.get(region, 0.5)  # Default factor
            
            estimated_carbon = cost * service_factor * regional_factor
            analysis['estimated_carbon_kg'] += estimated_carbon
            
            # Track by service
            if service not in analysis['services']:
                analysis['services'][service] = {
                    'cost': 0, 
                    'carbon_kg': 0, 
                    'optimization_score': 0,
                    'usage_days': 0
                }
            
            analysis['services'][service]['cost'] += cost
            analysis['services'][service]['carbon_kg'] += estimated_carbon
            analysis['services'][service]['usage_days'] += 1
            
            # Calculate optimization score (higher is better opportunity)
            if cost > 0:
                analysis['services'][service]['optimization_score'] = (
                    estimated_carbon / cost
                )
            
            # Track by region
            if region not in analysis['regions']:
                analysis['regions'][region] = {
                    'cost': 0,
                    'carbon_kg': 0,
                    'services_count': 0
                }
            
            analysis['regions'][region]['cost'] += cost
            analysis['regions'][region]['carbon_kg'] += estimated_carbon
            analysis['regions'][region]['services_count'] += 1
    
    # Calculate overall optimization potential
    total_optimization_potential = 0
    for service, metrics in analysis['services'].items():
        if metrics['optimization_score'] > CARBON_OPTIMIZATION_THRESHOLD:
            total_optimization_potential += metrics['cost']
    
    analysis['optimization_potential'] = total_optimization_potential
    
    logger.info(f"Analysis complete: ${analysis['total_cost']:.2f} cost, {analysis['estimated_carbon_kg']:.2f} kg CO2e estimated")
    
    return analysis

def generate_recommendations(analysis):
    """
    Generate carbon footprint optimization recommendations
    """
    logger.info("Generating optimization recommendations")
    
    recommendations = {
        'all_actions': [],
        'high_impact_actions': [],
        'estimated_savings': {'cost': 0, 'carbon_kg': 0},
        'regional_insights': [],
        'service_priorities': []
    }
    
    # Analyze services with high carbon intensity
    sorted_services = sorted(
        analysis['services'].items(),
        key=lambda x: x[1]['optimization_score'],
        reverse=True
    )
    
    for service, metrics in sorted_services:
        if metrics['optimization_score'] > CARBON_OPTIMIZATION_THRESHOLD:
            recommendation = {
                'service': service,
                'current_cost': metrics['cost'],
                'current_carbon_kg': metrics['carbon_kg'],
                'optimization_score': metrics['optimization_score'],
                'action': determine_optimization_action(service, metrics),
                'estimated_cost_savings': metrics['cost'] * 0.2,  # 20% savings potential
                'estimated_carbon_reduction': metrics['carbon_kg'] * 0.3,  # 30% reduction potential
                'priority': get_recommendation_priority(metrics)
            }
            
            recommendations['all_actions'].append(recommendation)
            
            if metrics['cost'] > HIGH_IMPACT_COST_THRESHOLD:
                recommendations['high_impact_actions'].append(recommendation)
                recommendations['estimated_savings']['cost'] += recommendation['estimated_cost_savings']
                recommendations['estimated_savings']['carbon_kg'] += recommendation['estimated_carbon_reduction']
    
    # Generate regional insights
    for region, metrics in analysis['regions'].items():
        if metrics['carbon_kg'] > 10:  # Significant carbon impact threshold
            recommendations['regional_insights'].append({
                'region': region,
                'carbon_impact': metrics['carbon_kg'],
                'cost': metrics['cost'],
                'services_count': metrics['services_count'],
                'recommendation': get_regional_recommendation(region, metrics)
            })
    
    # Service optimization priorities
    recommendations['service_priorities'] = [
        {
            'service': service,
            'priority_score': metrics['optimization_score'] * metrics['cost'],
            'action_required': metrics['optimization_score'] > CARBON_OPTIMIZATION_THRESHOLD
        }
        for service, metrics in sorted_services[:10]  # Top 10 services
    ]
    
    logger.info(f"Generated {len(recommendations['all_actions'])} recommendations, {len(recommendations['high_impact_actions'])} high-impact")
    
    return recommendations

def determine_optimization_action(service, metrics):
    """
    Determine specific optimization action for a service
    """
    action_map = {
        'Amazon Elastic Compute Cloud - Compute': 'Consider rightsizing instances, migrating to Graviton processors, or implementing auto-scaling',
        'Amazon Simple Storage Service': 'Implement Intelligent Tiering, lifecycle policies, and consider Glacier/Deep Archive for infrequent access',
        'Amazon Relational Database Service': 'Evaluate Aurora Serverless v2, instance rightsizing, or read replica optimization',
        'AWS Lambda': 'Optimize memory allocation, enable ARM-based Graviton2 runtime, and implement Provisioned Concurrency efficiently',
        'Amazon CloudFront': 'Review caching strategies, origin optimization, and consider regional edge locations',
        'Amazon DynamoDB': 'Implement on-demand billing for variable workloads or optimize provisioned capacity',
        'Amazon Redshift': 'Consider Redshift Serverless, resize clusters, or implement automatic scaling',
        'Amazon ElastiCache': 'Rightsize cache clusters and consider reserved instances for steady workloads',
        'Amazon EMR': 'Use Spot instances, optimize cluster sizing, and consider Graviton-based instances',
        'Amazon Elastic Container Service': 'Implement Fargate Spot, optimize task definitions, and use ARM-based instances'
    }
    
    base_action = action_map.get(service, 'Review resource utilization and consider sustainable alternatives')
    
    # Add specific guidance based on usage patterns
    if metrics['cost'] > 500:
        return f"{base_action}. High cost impact - prioritize immediate review."
    elif metrics['optimization_score'] > 1.0:
        return f"{base_action}. High carbon intensity - focus on efficiency improvements."
    else:
        return base_action

def get_recommendation_priority(metrics):
    """
    Calculate recommendation priority based on cost and carbon impact
    """
    cost_factor = min(metrics['cost'] / 1000, 1.0)  # Normalize to 0-1
    carbon_factor = min(metrics['optimization_score'], 1.0)  # Normalize to 0-1
    
    priority_score = (cost_factor * 0.6) + (carbon_factor * 0.4)
    
    if priority_score > 0.7:
        return 'Critical'
    elif priority_score > 0.4:
        return 'High'
    elif priority_score > 0.2:
        return 'Medium'
    else:
        return 'Low'

def get_regional_recommendation(region, metrics):
    """
    Generate region-specific recommendations
    """
    low_carbon_regions = ['us-west-2', 'ca-central-1', 'eu-north-1']
    
    if region in low_carbon_regions:
        return f"Already in low-carbon region. Optimize resource efficiency."
    else:
        return f"Consider migrating workloads to lower-carbon regions like us-west-2 (Oregon) or ca-central-1 (Canada)."

def store_metrics(analysis, analysis_type):
    """
    Store analysis results in DynamoDB
    """
    timestamp = datetime.now().isoformat()
    
    try:
        # Store overall metrics
        table.put_item(
            Item={
                'MetricType': f'{analysis_type.upper()}_ANALYSIS',
                'Timestamp': timestamp,
                'TotalCost': Decimal(str(round(analysis['total_cost'], 2))),
                'EstimatedCarbonKg': Decimal(str(round(analysis['estimated_carbon_kg'], 2))),
                'ServiceCount': len(analysis['services']),
                'OptimizationPotential': Decimal(str(round(analysis['optimization_potential'], 2))),
                'AnalysisType': analysis_type
            }
        )
        
        # Store service-specific metrics
        for service, metrics in analysis['services'].items():
            # Clean service name for DynamoDB
            clean_service_name = service.replace(' ', '_').replace('-', '_').upper()
            
            table.put_item(
                Item={
                    'MetricType': f'SERVICE_{clean_service_name}'[:50],  # DynamoDB key limit
                    'Timestamp': timestamp,
                    'ServiceName': service,
                    'Cost': Decimal(str(round(metrics['cost'], 2))),
                    'CarbonKg': Decimal(str(round(metrics['carbon_kg'], 2))),
                    'CarbonIntensity': Decimal(str(round(metrics['optimization_score'], 4))),
                    'UsageDays': metrics['usage_days'],
                    'AnalysisType': analysis_type
                }
            )
        
        logger.info("Metrics stored successfully in DynamoDB")
        
    except Exception as e:
        logger.error(f"Error storing metrics: {str(e)}")
        raise

def store_analysis_results(analysis, recommendations, analysis_type):
    """
    Store detailed analysis results in S3 for historical tracking
    """
    timestamp = datetime.now().strftime('%Y-%m-%d-%H-%M-%S')
    key = f"analysis-results/{analysis_type}/{timestamp}.json"
    
    results = {
        'analysis': analysis,
        'recommendations': recommendations,
        'metadata': {
            'analysis_type': analysis_type,
            'timestamp': timestamp,
            'project': PROJECT_NAME
        }
    }
    
    try:
        s3_client.put_object(
            Bucket=S3_BUCKET,
            Key=key,
            Body=json.dumps(results, default=str, indent=2),
            ContentType='application/json'
        )
        logger.info(f"Analysis results stored in S3: {key}")
        
    except Exception as e:
        logger.error(f"Error storing analysis results in S3: {str(e)}")

def send_optimization_notifications(recommendations, analysis_type):
    """
    Send notifications about optimization opportunities
    """
    high_impact_count = len(recommendations['high_impact_actions'])
    
    if high_impact_count == 0:
        return
    
    message = f"""
🌱 Carbon Footprint Optimization Report ({analysis_type.title()} Analysis)

📊 High-Impact Opportunities Found: {high_impact_count}

💰 Estimated Monthly Savings:
   • Cost: ${recommendations['estimated_savings']['cost']:.2f}
   • Carbon: {recommendations['estimated_savings']['carbon_kg']:.2f} kg CO2e

🔝 Top Recommendations:
"""
    
    for i, action in enumerate(recommendations['high_impact_actions'][:5], 1):
        message += f"""
{i}. {action['service']}
   📈 Current Impact: ${action['current_cost']:.2f}, {action['current_carbon_kg']:.2f} kg CO2e
   🎯 Priority: {action['priority']}
   💡 Action: {action['action'][:100]}...
"""
    
    # Add regional insights if available
    if recommendations['regional_insights']:
        message += f"""
🌍 Regional Insights:
"""
        for insight in recommendations['regional_insights'][:3]:
            message += f"   • {insight['region']}: {insight['carbon_impact']:.2f} kg CO2e\n"
    
    message += f"""

🔗 View detailed analysis in CloudWatch Dashboard
📝 This is an automated report from {PROJECT_NAME}
"""
    
    try:
        sns_client.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=f'🌱 Carbon Footprint Optimization Report - {high_impact_count} High-Impact Opportunities',
            Message=message
        )
        logger.info("Optimization notification sent successfully")
        
    except Exception as e:
        logger.error(f"Error sending notification: {str(e)}")