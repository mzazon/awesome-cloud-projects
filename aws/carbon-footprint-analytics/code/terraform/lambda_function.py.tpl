"""
AWS Sustainability Data Processor Lambda Function
Processes carbon footprint and cost data for intelligent sustainability analytics

This function integrates with:
- AWS Customer Carbon Footprint Tool (via manual exports and future APIs)
- AWS Cost Explorer API for cost correlation analysis
- Amazon S3 for data lake storage
- Amazon CloudWatch for metrics and monitoring

Template Variables:
- bucket_name: S3 bucket for data storage
- kms_key_id: KMS key for encryption
- region: AWS region for service calls
"""

import json
import boto3
import pandas as pd
from datetime import datetime, timedelta, timezone
import logging
import os
import traceback
from typing import Dict, List, Any, Optional
import uuid

# Configure logging
logger = logging.getLogger()
log_level = os.environ.get('LOG_LEVEL', 'INFO').upper()
logger.setLevel(getattr(logging, log_level))

# Constants from Terraform template
BUCKET_NAME = "${bucket_name}"
KMS_KEY_ID = "${kms_key_id}"
REGION = "${region}"
COST_EXPLORER_REGION = "us-east-1"  # Cost Explorer API only available in us-east-1


class SustainabilityDataProcessor:
    """
    Main class for processing sustainability and cost data
    """
    
    def __init__(self):
        """Initialize AWS service clients"""
        try:
            # Initialize AWS clients
            self.s3_client = boto3.client('s3', region_name=REGION)
            self.ce_client = boto3.client('ce', region_name=COST_EXPLORER_REGION)
            self.cloudwatch = boto3.client('cloudwatch', region_name=REGION)
            
            # Get environment configuration
            self.environment = os.environ.get('ENVIRONMENT', 'dev')
            self.enable_xray = os.environ.get('ENABLE_XRAY', 'true').lower() == 'true'
            
            logger.info(f"SustainabilityDataProcessor initialized for environment: {self.environment}")
            
        except Exception as e:
            logger.error(f"Failed to initialize SustainabilityDataProcessor: {str(e)}")
            raise
    
    def get_cost_and_usage_data(self, start_date: str, end_date: str) -> Dict[str, Any]:
        """
        Retrieve cost and usage data from AWS Cost Explorer
        
        Args:
            start_date: Start date in YYYY-MM-DD format
            end_date: End date in YYYY-MM-DD format
            
        Returns:
            Dict containing cost and usage data
        """
        try:
            logger.info(f"Fetching cost data from {start_date} to {end_date}")
            
            # Get cost and usage data with service and region grouping
            cost_response = self.ce_client.get_cost_and_usage(
                TimePeriod={
                    'Start': start_date,
                    'End': end_date
                },
                Granularity='MONTHLY',
                Metrics=['UnblendedCost', 'UsageQuantity'],
                GroupBy=[
                    {'Type': 'DIMENSION', 'Key': 'SERVICE'},
                    {'Type': 'DIMENSION', 'Key': 'REGION'}
                ]
            )
            
            logger.info(f"Successfully retrieved cost data with {len(cost_response['ResultsByTime'])} time periods")
            return cost_response
            
        except Exception as e:
            logger.error(f"Error fetching cost data: {str(e)}")
            raise
    
    def get_rightsizing_recommendations(self) -> Dict[str, Any]:
        """
        Get rightsizing recommendations for cost and carbon optimization
        
        Returns:
            Dict containing rightsizing recommendations
        """
        try:
            logger.info("Fetching rightsizing recommendations")
            
            recommendations = self.ce_client.get_rightsizing_recommendation(
                Service='AmazonEC2',
                Configuration={
                    'BenefitsConsidered': True,
                    'RecommendationTarget': 'CROSS_INSTANCE_FAMILY'
                }
            )
            
            logger.info(f"Retrieved {len(recommendations.get('RightsizingRecommendations', []))} rightsizing recommendations")
            return recommendations
            
        except Exception as e:
            logger.warning(f"Error fetching rightsizing recommendations: {str(e)}")
            return {'RightsizingRecommendations': []}
    
    def get_carbon_intensity_estimates(self, cost_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Calculate estimated carbon intensity based on service usage and regions
        
        Note: This provides estimates based on service types and regions.
        Actual carbon footprint data comes from AWS Customer Carbon Footprint Tool.
        
        Args:
            cost_data: Cost and usage data from Cost Explorer
            
        Returns:
            Dict containing carbon intensity estimates
        """
        try:
            logger.info("Calculating carbon intensity estimates")
            
            # AWS regions with approximate carbon intensity factors (gCO2e/kWh)
            # These are estimates - actual values come from AWS Customer Carbon Footprint Tool
            region_carbon_intensity = {
                'us-east-1': 390,      # Virginia (US East)
                'us-west-2': 320,      # Oregon (US West)
                'eu-west-1': 300,      # Ireland
                'eu-central-1': 400,   # Frankfurt
                'ap-southeast-1': 500, # Singapore
                'ap-northeast-1': 470, # Tokyo
                'ca-central-1': 130,   # Canada (Central) - hydroelectric
                'eu-north-1': 50,      # Stockholm - renewable energy
                'default': 400         # Global average estimate
            }
            
            # Service carbon impact multipliers (relative estimates)
            service_multipliers = {
                'Amazon Elastic Compute Cloud - Compute': 1.0,
                'Amazon Relational Database Service': 0.8,
                'Amazon Simple Storage Service': 0.1,
                'AWS Lambda': 0.2,
                'Amazon ElastiCache': 0.7,
                'Amazon Elastic Block Store': 0.1,
                'default': 0.5
            }
            
            carbon_estimates = {
                'methodology': 'Estimated based on service types and regional grid carbon intensity',
                'note': 'Actual carbon footprint data available via AWS Customer Carbon Footprint Tool',
                'data_source': 'Cost Explorer API with carbon intensity modeling',
                'regional_estimates': {},
                'service_estimates': {},
                'total_estimated_impact': 0
            }
            
            total_carbon_estimate = 0
            
            # Process cost data to estimate carbon impact
            for time_period in cost_data.get('ResultsByTime', []):
                period_start = time_period['TimePeriod']['Start']
                
                for group in time_period.get('Groups', []):
                    service = group['Keys'][0] if len(group['Keys']) > 0 else 'Unknown'
                    region = group['Keys'][1] if len(group['Keys']) > 1 else 'default'
                    
                    # Get cost amount
                    cost_amount = float(group['Metrics']['UnblendedCost']['Amount'])
                    
                    if cost_amount > 0:
                        # Estimate carbon impact based on cost, service type, and region
                        region_intensity = region_carbon_intensity.get(region, region_carbon_intensity['default'])
                        service_multiplier = service_multipliers.get(service, service_multipliers['default'])
                        
                        # Simple estimation: cost * service_multiplier * region_intensity / 1000
                        estimated_carbon = cost_amount * service_multiplier * (region_intensity / 1000)
                        total_carbon_estimate += estimated_carbon
                        
                        # Store estimates by region and service
                        if region not in carbon_estimates['regional_estimates']:
                            carbon_estimates['regional_estimates'][region] = 0
                        carbon_estimates['regional_estimates'][region] += estimated_carbon
                        
                        if service not in carbon_estimates['service_estimates']:
                            carbon_estimates['service_estimates'][service] = 0
                        carbon_estimates['service_estimates'][service] += estimated_carbon
            
            carbon_estimates['total_estimated_impact'] = total_carbon_estimate
            
            logger.info(f"Calculated carbon intensity estimates with total impact: {total_carbon_estimate:.2f} estimated kgCO2e")
            return carbon_estimates
            
        except Exception as e:
            logger.error(f"Error calculating carbon intensity estimates: {str(e)}")
            return {'error': str(e)}
    
    def process_sustainability_insights(self, cost_data: Dict[str, Any], 
                                      recommendations: Dict[str, Any],
                                      carbon_estimates: Dict[str, Any]) -> Dict[str, Any]:
        """
        Process and correlate sustainability insights from multiple data sources
        
        Args:
            cost_data: Cost and usage data
            recommendations: Rightsizing recommendations
            carbon_estimates: Carbon intensity estimates
            
        Returns:
            Dict containing processed sustainability insights
        """
        try:
            logger.info("Processing sustainability insights")
            
            insights = {
                'analysis_timestamp': datetime.now(timezone.utc).isoformat(),
                'data_period': {
                    'start': None,
                    'end': None,
                    'analysis_scope': 'Last 6 months'
                },
                'cost_summary': {
                    'total_cost': 0,
                    'services_analyzed': 0,
                    'regions_analyzed': 0
                },
                'sustainability_opportunities': [],
                'regional_optimization': {},
                'service_optimization': {},
                'carbon_footprint_notes': {
                    'data_source': 'AWS Customer Carbon Footprint Tool (manual export recommended)',
                    'availability': 'Monthly data with 3-month delay',
                    'scope': 'Scope 2 emissions for AWS services',
                    'methodology': 'Location-based and Market-based methods available'
                }
            }
            
            # Process cost data summary
            services = set()
            regions = set()
            total_cost = 0
            
            if cost_data.get('ResultsByTime'):
                insights['data_period']['start'] = cost_data['ResultsByTime'][0]['TimePeriod']['Start']
                insights['data_period']['end'] = cost_data['ResultsByTime'][-1]['TimePeriod']['End']
                
                for time_period in cost_data['ResultsByTime']:
                    for group in time_period.get('Groups', []):
                        if len(group['Keys']) >= 2:
                            service = group['Keys'][0]
                            region = group['Keys'][1]
                            cost = float(group['Metrics']['UnblendedCost']['Amount'])
                            
                            services.add(service)
                            regions.add(region)
                            total_cost += cost
            
            insights['cost_summary']['total_cost'] = total_cost
            insights['cost_summary']['services_analyzed'] = len(services)
            insights['cost_summary']['regions_analyzed'] = len(regions)
            
            # Process rightsizing recommendations for sustainability opportunities
            for recommendation in recommendations.get('RightsizingRecommendations', []):
                current_instance = recommendation.get('CurrentInstance', {})
                recommended_instance = recommendation.get('ModifyRecommendation', {})
                
                if current_instance and recommended_instance:
                    opportunity = {
                        'type': 'Instance Rightsizing',
                        'resource_id': current_instance.get('ResourceId', 'Unknown'),
                        'current_type': current_instance.get('InstanceType', 'Unknown'),
                        'recommended_type': recommended_instance.get('InstanceType', 'Unknown'),
                        'estimated_monthly_savings': recommendation.get('EstimatedMonthlySavings', 0),
                        'sustainability_benefit': 'Reduced compute resources = lower carbon footprint'
                    }
                    insights['sustainability_opportunities'].append(opportunity)
            
            # Add carbon optimization opportunities based on regional data
            if carbon_estimates.get('regional_estimates'):
                for region, estimated_carbon in carbon_estimates['regional_estimates'].items():
                    if region != 'default' and estimated_carbon > 0:
                        insights['regional_optimization'][region] = {
                            'estimated_carbon_impact': estimated_carbon,
                            'recommendation': 'Consider migrating workloads to lower carbon intensity regions',
                            'suggested_regions': ['eu-north-1', 'ca-central-1', 'us-west-2']
                        }
            
            logger.info(f"Processed {len(insights['sustainability_opportunities'])} sustainability opportunities")
            return insights
            
        except Exception as e:
            logger.error(f"Error processing sustainability insights: {str(e)}")
            return {'error': str(e)}
    
    def save_to_s3(self, data: Dict[str, Any], key_prefix: str) -> str:
        """
        Save processed data to S3 with proper partitioning and encryption
        
        Args:
            data: Data to save
            key_prefix: S3 key prefix for organization
            
        Returns:
            S3 key where data was saved
        """
        try:
            # Create timestamped key with partitioning
            now = datetime.now(timezone.utc)
            s3_key = f"{key_prefix}/{now.strftime('%Y/%m/%d')}/processed_data_{now.strftime('%H%M%S')}_{uuid.uuid4().hex[:8]}.json"
            
            # Save to S3 with KMS encryption
            self.s3_client.put_object(
                Bucket=BUCKET_NAME,
                Key=s3_key,
                Body=json.dumps(data, indent=2, default=str),
                ContentType='application/json',
                ServerSideEncryption='aws:kms',
                SSEKMSKeyId=KMS_KEY_ID,
                Metadata={
                    'processing-timestamp': now.isoformat(),
                    'data-type': 'sustainability-analytics',
                    'processor-version': '1.0',
                    'environment': self.environment
                }
            )
            
            logger.info(f"Successfully saved data to S3: s3://{BUCKET_NAME}/{s3_key}")
            return s3_key
            
        except Exception as e:
            logger.error(f"Error saving data to S3: {str(e)}")
            raise
    
    def send_cloudwatch_metrics(self, insights: Dict[str, Any]):
        """
        Send custom metrics to CloudWatch for monitoring and alerting
        
        Args:
            insights: Processed sustainability insights
        """
        try:
            metrics = []
            
            # Success metric
            metrics.append({
                'MetricName': 'DataProcessingSuccess',
                'Value': 1,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': self.environment},
                    {'Name': 'DataType', 'Value': 'SustainabilityAnalytics'}
                ]
            })
            
            # Cost metrics
            if insights.get('cost_summary', {}).get('total_cost'):
                metrics.append({
                    'MetricName': 'TotalCostAnalyzed',
                    'Value': insights['cost_summary']['total_cost'],
                    'Unit': 'None',
                    'Dimensions': [
                        {'Name': 'Environment', 'Value': self.environment}
                    ]
                })
            
            # Sustainability opportunities
            opportunities_count = len(insights.get('sustainability_opportunities', []))
            if opportunities_count > 0:
                metrics.append({
                    'MetricName': 'SustainabilityOpportunities',
                    'Value': opportunities_count,
                    'Unit': 'Count',
                    'Dimensions': [
                        {'Name': 'Environment', 'Value': self.environment}
                    ]
                })
            
            # Send metrics to CloudWatch
            if metrics:
                self.cloudwatch.put_metric_data(
                    Namespace='SustainabilityAnalytics',
                    MetricData=metrics
                )
                logger.info(f"Successfully sent {len(metrics)} metrics to CloudWatch")
            
        except Exception as e:
            logger.warning(f"Error sending CloudWatch metrics: {str(e)}")


def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Main Lambda handler for sustainability data processing
    
    Args:
        event: Lambda event data
        context: Lambda context object
        
    Returns:
        Dict containing processing results
    """
    logger.info(f"Processing sustainability data - Event: {json.dumps(event, default=str)}")
    
    try:
        # Initialize processor
        processor = SustainabilityDataProcessor()
        
        # Calculate date range for analysis (last 6 months)
        end_date = datetime.now(timezone.utc)
        start_date = end_date - timedelta(days=180)
        
        start_date_str = start_date.strftime('%Y-%m-%d')
        end_date_str = end_date.strftime('%Y-%m-%d')
        
        logger.info(f"Processing sustainability data from {start_date_str} to {end_date_str}")
        
        # Fetch cost and usage data
        cost_data = processor.get_cost_and_usage_data(start_date_str, end_date_str)
        
        # Get rightsizing recommendations
        recommendations = processor.get_rightsizing_recommendations()
        
        # Calculate carbon intensity estimates
        carbon_estimates = processor.get_carbon_intensity_estimates(cost_data)
        
        # Process sustainability insights
        insights = processor.process_sustainability_insights(
            cost_data, recommendations, carbon_estimates
        )
        
        # Create comprehensive analytics payload
        analytics_data = {
            'metadata': {
                'processing_timestamp': datetime.now(timezone.utc).isoformat(),
                'processor_version': '1.0',
                'environment': processor.environment,
                'aws_region': REGION,
                'trigger_source': event.get('trigger_source', 'unknown'),
                'analysis_period': f"{start_date_str} to {end_date_str}"
            },
            'raw_cost_data': cost_data,
            'rightsizing_recommendations': recommendations,
            'carbon_intensity_estimates': carbon_estimates,
            'sustainability_insights': insights,
            'aws_carbon_footprint_info': {
                'tool_location': 'AWS Billing Console > Customer Carbon Footprint Tool',
                'data_availability': 'Monthly data available with 3-month delay',
                'data_export_recommendation': 'Use AWS Data Exports or manual CSV download for programmatic access',
                'scope_coverage': 'Scope 2 emissions for AWS service electricity consumption',
                'methodology': 'Both location-based (LBM) and market-based (MBM) methods available'
            }
        }
        
        # Save to S3 data lake
        s3_key = processor.save_to_s3(analytics_data, 'sustainability-analytics')
        
        # Send CloudWatch metrics
        processor.send_cloudwatch_metrics(insights)
        
        # Return success response
        response = {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Sustainability data processed successfully',
                'data_location': f's3://{BUCKET_NAME}/{s3_key}',
                'processing_summary': {
                    'cost_analysis_period': f"{start_date_str} to {end_date_str}",
                    'total_cost_analyzed': insights.get('cost_summary', {}).get('total_cost', 0),
                    'services_analyzed': insights.get('cost_summary', {}).get('services_analyzed', 0),
                    'sustainability_opportunities': len(insights.get('sustainability_opportunities', [])),
                    'estimated_carbon_impact': carbon_estimates.get('total_estimated_impact', 0)
                }
            }, default=str)
        }
        
        logger.info(f"Successfully processed sustainability data: {response['body']}")
        return response
        
    except Exception as e:
        error_message = f"Error processing sustainability data: {str(e)}"
        error_traceback = traceback.format_exc()
        
        logger.error(f"{error_message}\n{error_traceback}")
        
        # Send error metric to CloudWatch
        try:
            processor = SustainabilityDataProcessor()
            processor.cloudwatch.put_metric_data(
                Namespace='SustainabilityAnalytics',
                MetricData=[
                    {
                        'MetricName': 'DataProcessingError',
                        'Value': 1,
                        'Unit': 'Count',
                        'Dimensions': [
                            {'Name': 'Environment', 'Value': os.environ.get('ENVIRONMENT', 'dev')},
                            {'Name': 'ErrorType', 'Value': type(e).__name__}
                        ]
                    }
                ]
            )
        except Exception as metric_error:
            logger.error(f"Failed to send error metric: {str(metric_error)}")
        
        # Return error response
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_message,
                'timestamp': datetime.now(timezone.utc).isoformat()
            })
        }