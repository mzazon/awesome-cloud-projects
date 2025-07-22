"""
Reserved Instance Recommendations Lambda Function

This function generates RI purchase recommendations using AWS Cost Explorer API
and analyzes potential cost savings opportunities.

Author: AWS RI Management System
Version: 1.0
"""

import json
import boto3
import datetime
import os
import logging
from botocore.exceptions import ClientError
from typing import Dict, List, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for RI recommendations generation.
    
    Args:
        event: Lambda event data
        context: Lambda context object
        
    Returns:
        Response with recommendations results
    """
    # Initialize AWS clients
    ce = boto3.client('ce')
    s3 = boto3.client('s3')
    sns = boto3.client('sns')
    
    # Get environment variables
    bucket_name = os.environ.get('S3_BUCKET_NAME')
    sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
    slack_webhook_url = os.environ.get('SLACK_WEBHOOK_URL', '')
    
    # Validate required environment variables
    if not bucket_name or not sns_topic_arn:
        logger.error("Missing required environment variables")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Missing required environment variables'})
        }
    
    try:
        logger.info("Starting RI recommendations analysis")
        
        # Services to analyze for RI recommendations
        services = [
            'Amazon Elastic Compute Cloud - Compute',
            'Amazon Relational Database Service'
        ]
        
        all_recommendations = []
        total_estimated_savings = 0
        
        for service in services:
            try:
                logger.info(f"Getting RI recommendations for {service}")
                
                # Get RI recommendations from Cost Explorer
                response = ce.get_reservation_purchase_recommendation(
                    Service=service,
                    LookbackPeriodInDays='SIXTY_DAYS',
                    TermInYears='ONE_YEAR',
                    PaymentOption='PARTIAL_UPFRONT'
                )
                
                # Process recommendations for this service
                service_recommendations = process_service_recommendations(response, service)
                all_recommendations.extend(service_recommendations)
                
                # Calculate total savings
                for rec in service_recommendations:
                    total_estimated_savings += rec['estimated_monthly_savings']
                    
            except ClientError as e:
                if e.response['Error']['Code'] == 'DataUnavailableException':
                    logger.warning(f"No recommendation data available for {service}")
                    continue
                else:
                    raise e
        
        # Generate comprehensive report
        today = datetime.date.today()
        report_data = {
            'report_date': today.strftime('%Y-%m-%d'),
            'analysis_period': 'Last 60 days',
            'total_recommendations': len(all_recommendations),
            'total_estimated_monthly_savings': round(total_estimated_savings, 2),
            'total_estimated_annual_savings': round(total_estimated_savings * 12, 2),
            'recommendations': all_recommendations,
            'summary_by_service': generate_service_summary(all_recommendations),
            'purchase_guidance': generate_purchase_guidance(all_recommendations)
        }
        
        # Save recommendations to S3
        report_key = f"ri-recommendations/{today.strftime('%Y-%m-%d')}_recommendations.json"
        
        try:
            s3.put_object(
                Bucket=bucket_name,
                Key=report_key,
                Body=json.dumps(report_data, indent=2, default=str),
                ContentType='application/json',
                ServerSideEncryption='AES256'
            )
            logger.info(f"Recommendations saved to S3: s3://{bucket_name}/{report_key}")
        except ClientError as e:
            logger.error(f"Failed to save recommendations to S3: {e}")
        
        # Send notification if there are recommendations
        if all_recommendations:
            try:
                send_recommendations_notification(
                    sns, sns_topic_arn, report_data, bucket_name, report_key, slack_webhook_url
                )
                logger.info("Sent recommendations notification")
            except Exception as e:
                logger.error(f"Failed to send notification: {e}")
        
        logger.info(f"RI recommendations analysis completed. Found {len(all_recommendations)} recommendations")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'RI recommendations analysis completed successfully',
                'report_location': f"s3://{bucket_name}/{report_key}",
                'recommendations_count': len(all_recommendations),
                'estimated_monthly_savings': total_estimated_savings,
                'estimated_annual_savings': total_estimated_savings * 12
            })
        }
        
    except ClientError as e:
        error_code = e.response['Error']['Code']
        error_message = e.response['Error']['Message']
        logger.error(f"AWS API error ({error_code}): {error_message}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f"AWS API error: {error_message}",
                'error_code': error_code
            })
        }
        
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': f"Unexpected error: {str(e)}"})
        }

def process_service_recommendations(response: Dict, service: str) -> List[Dict]:
    """
    Process RI recommendations for a specific service.
    
    Args:
        response: Cost Explorer API response
        service: AWS service name
        
    Returns:
        List of processed recommendation dictionaries
    """
    recommendations = []
    
    for recommendation in response.get('Recommendations', []):
        try:
            rec_details = recommendation['RecommendationDetails']
            
            # Common fields for all services
            rec_data = {
                'service': service,
                'recommended_instances': int(rec_details['RecommendedNumberOfInstancesToPurchase']),
                'estimated_monthly_savings': float(rec_details['EstimatedMonthlySavingsAmount']),
                'estimated_monthly_on_demand_cost': float(rec_details['EstimatedMonthlyOnDemandCost']),
                'upfront_cost': float(rec_details['UpfrontCost']),
                'recurring_monthly_cost': float(rec_details['RecurringStandardMonthlyCost']),
                'estimated_break_even_months': calculate_break_even_months(rec_details),
                'estimated_annual_savings': float(rec_details['EstimatedMonthlySavingsAmount']) * 12,
                'savings_percentage': calculate_savings_percentage(rec_details),
                'recommendation_reason': get_recommendation_reason(recommendation)
            }
            
            # Service-specific fields
            if service == 'Amazon Elastic Compute Cloud - Compute':
                ec2_details = recommendation['InstanceDetails']['EC2InstanceDetails']
                rec_data.update({
                    'instance_type': ec2_details['InstanceType'],
                    'region': ec2_details['Region'],
                    'availability_zone': ec2_details.get('AvailabilityZone', 'Any'),
                    'platform': ec2_details.get('Platform', 'Linux/UNIX'),
                    'tenancy': ec2_details.get('Tenancy', 'default'),
                    'offering_class': ec2_details.get('OfferingClass', 'standard'),
                    'instance_family': ec2_details['InstanceType'].split('.')[0]
                })
                
            elif service == 'Amazon Relational Database Service':
                rds_details = recommendation['InstanceDetails']['RDSInstanceDetails']
                rec_data.update({
                    'instance_type': rds_details['InstanceType'],
                    'database_engine': rds_details['DatabaseEngine'],
                    'region': rds_details['Region'],
                    'deployment_option': rds_details.get('DeploymentOption', 'Single-AZ'),
                    'license_model': rds_details.get('LicenseModel', 'No License Required'),
                    'instance_family': rds_details['InstanceType'].split('.')[0]
                })
            
            recommendations.append(rec_data)
            
        except (KeyError, ValueError) as e:
            logger.warning(f"Failed to process recommendation: {e}")
            continue
    
    return recommendations

def calculate_break_even_months(rec_details: Dict) -> float:
    """
    Calculate break-even period in months for RI purchase.
    
    Args:
        rec_details: Recommendation details from Cost Explorer
        
    Returns:
        Break-even period in months
    """
    try:
        upfront_cost = float(rec_details['UpfrontCost'])
        monthly_savings = float(rec_details['EstimatedMonthlySavingsAmount'])
        
        if monthly_savings <= 0:
            return float('inf')
        
        return round(upfront_cost / monthly_savings, 1)
    except (ValueError, ZeroDivisionError):
        return float('inf')

def calculate_savings_percentage(rec_details: Dict) -> float:
    """
    Calculate savings percentage for RI purchase.
    
    Args:
        rec_details: Recommendation details from Cost Explorer
        
    Returns:
        Savings percentage
    """
    try:
        monthly_savings = float(rec_details['EstimatedMonthlySavingsAmount'])
        on_demand_cost = float(rec_details['EstimatedMonthlyOnDemandCost'])
        
        if on_demand_cost <= 0:
            return 0.0
        
        return round((monthly_savings / on_demand_cost) * 100, 1)
    except (ValueError, ZeroDivisionError):
        return 0.0

def get_recommendation_reason(recommendation: Dict) -> str:
    """
    Extract or generate recommendation reason.
    
    Args:
        recommendation: Full recommendation object
        
    Returns:
        Recommendation reason string
    """
    # Try to get reason from recommendation metadata
    metadata = recommendation.get('RecommendationDetails', {}).get('RecommendationDetailData', {})
    
    if metadata:
        return "Based on historical usage pattern analysis"
    
    return "Recommended based on 60-day usage analysis"

def generate_service_summary(recommendations: List[Dict]) -> Dict:
    """
    Generate summary statistics by service.
    
    Args:
        recommendations: List of all recommendations
        
    Returns:
        Summary dictionary by service
    """
    summary = {}
    
    for rec in recommendations:
        service = rec['service']
        if service not in summary:
            summary[service] = {
                'count': 0,
                'total_savings': 0,
                'total_upfront_cost': 0,
                'instance_types': set()
            }
        
        summary[service]['count'] += 1
        summary[service]['total_savings'] += rec['estimated_monthly_savings']
        summary[service]['total_upfront_cost'] += rec['upfront_cost']
        summary[service]['instance_types'].add(rec.get('instance_type', 'Unknown'))
    
    # Convert sets to lists for JSON serialization
    for service in summary:
        summary[service]['instance_types'] = list(summary[service]['instance_types'])
        summary[service]['total_savings'] = round(summary[service]['total_savings'], 2)
        summary[service]['total_upfront_cost'] = round(summary[service]['total_upfront_cost'], 2)
    
    return summary

def generate_purchase_guidance(recommendations: List[Dict]) -> List[str]:
    """
    Generate actionable purchase guidance.
    
    Args:
        recommendations: List of all recommendations
        
    Returns:
        List of guidance strings
    """
    if not recommendations:
        return ["No RI purchase recommendations available at this time"]
    
    guidance = []
    
    # Prioritize by savings amount
    high_savings = [r for r in recommendations if r['estimated_monthly_savings'] > 100]
    if high_savings:
        guidance.append(f"Priority: Consider {len(high_savings)} high-impact recommendations with >$100/month savings")
    
    # Break-even analysis
    quick_payback = [r for r in recommendations if r['estimated_break_even_months'] < 6]
    if quick_payback:
        guidance.append(f"Quick payback: {len(quick_payback)} recommendations break even in <6 months")
    
    # Instance family analysis
    instance_families = {}
    for rec in recommendations:
        family = rec.get('instance_family', 'Unknown')
        if family not in instance_families:
            instance_families[family] = 0
        instance_families[family] += rec['recommended_instances']
    
    if instance_families:
        top_family = max(instance_families.items(), key=lambda x: x[1])
        guidance.append(f"Most recommended instance family: {top_family[0]} ({top_family[1]} instances)")
    
    # General guidance
    guidance.extend([
        "Consider convertible RIs for flexibility in changing requirements",
        "Start with partial upfront payment for balance of savings and cash flow",
        "Monitor utilization after purchase to ensure optimal ROI",
        "Review recommendations monthly as usage patterns change"
    ])
    
    return guidance

def send_recommendations_notification(sns_client, topic_arn: str, report_data: Dict, bucket_name: str, report_key: str, slack_webhook_url: str = "") -> None:
    """
    Send recommendations notification via SNS and optionally Slack.
    
    Args:
        sns_client: Boto3 SNS client
        topic_arn: SNS topic ARN
        report_data: Complete report data
        bucket_name: S3 bucket name
        report_key: S3 object key
        slack_webhook_url: Optional Slack webhook URL
    """
    recommendations = report_data['recommendations']
    total_savings = report_data['total_estimated_monthly_savings']
    annual_savings = report_data['total_estimated_annual_savings']
    
    # Prepare SNS message
    message = f"Reserved Instance Purchase Recommendations\\n\\n"
    message += f"Total Recommendations: {len(recommendations)}\\n"
    message += f"Estimated Monthly Savings: ${total_savings:.2f}\\n"
    message += f"Estimated Annual Savings: ${annual_savings:.2f}\\n\\n"
    
    # Show top 5 recommendations
    top_recommendations = sorted(recommendations, key=lambda x: x['estimated_monthly_savings'], reverse=True)[:5]
    
    message += "TOP RECOMMENDATIONS:\\n"
    for i, rec in enumerate(top_recommendations, 1):
        service_short = "EC2" if "Compute" in rec['service'] else "RDS"
        message += f"{i}. {service_short}: {rec.get('instance_type', 'N/A')} "
        message += f"(${rec['estimated_monthly_savings']:.2f}/month savings)\\n"
    
    if len(recommendations) > 5:
        message += f"... and {len(recommendations) - 5} more recommendations\\n"
    
    message += f"\\nFull report: s3://{bucket_name}/{report_key}\\n"
    message += f"Report generated at: {datetime.datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S')} UTC"
    
    # Send SNS notification
    sns_client.publish(
        TopicArn=topic_arn,
        Subject="Reserved Instance Purchase Recommendations",
        Message=message
    )
    
    # Send Slack notification if webhook URL provided
    if slack_webhook_url:
        try:
            import urllib3
            http = urllib3.PoolManager()
            
            slack_message = {
                "text": f"💰 New Reserved Instance Recommendations Available",
                "attachments": [
                    {
                        "color": "good",
                        "fields": [
                            {
                                "title": "Total Recommendations",
                                "value": str(len(recommendations)),
                                "short": True
                            },
                            {
                                "title": "Monthly Savings",
                                "value": f"${total_savings:.2f}",
                                "short": True
                            },
                            {
                                "title": "Annual Savings",
                                "value": f"${annual_savings:.2f}",
                                "short": True
                            }
                        ],
                        "text": f"View full report: s3://{bucket_name}/{report_key}"
                    }
                ]
            }
            
            http.request(
                'POST',
                slack_webhook_url,
                body=json.dumps(slack_message),
                headers={'Content-Type': 'application/json'}
            )
            
        except Exception as e:
            logger.warning(f"Failed to send Slack notification: {e}")