import json
import boto3
import os
from datetime import datetime, timedelta
from decimal import Decimal
import logging

# Set up logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Main handler for cost analysis using Trusted Advisor APIs
    """
    logger.info("Starting cost optimization analysis...")
    
    # Initialize AWS clients
    support_client = boto3.client('support', region_name='us-east-1')
    ce_client = boto3.client('ce')
    dynamodb = boto3.resource('dynamodb')
    lambda_client = boto3.client('lambda')
    s3_client = boto3.client('s3')
    sns_client = boto3.client('sns')
    
    # Get environment variables
    table_name = os.environ['COST_OPT_TABLE']
    remediation_function = os.environ['REMEDIATION_FUNCTION_NAME']
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    s3_bucket_name = os.environ['S3_BUCKET_NAME']
    enable_auto_remediation = os.environ.get('ENABLE_AUTO_REMEDIATION', 'false').lower() == 'true'
    cost_alert_threshold = float(os.environ.get('COST_ALERT_THRESHOLD', '100.0'))
    high_savings_threshold = float(os.environ.get('HIGH_SAVINGS_THRESHOLD', '50.0'))
    
    table = dynamodb.Table(table_name)
    
    # Configuration for auto-remediation
    auto_remediation_checks = ${auto_remediation_checks}
    
    try:
        # Get list of cost optimization checks
        cost_checks = get_cost_optimization_checks(support_client)
        logger.info(f"Found {len(cost_checks)} cost optimization checks")
        
        # Process each check
        optimization_opportunities = []
        for check in cost_checks:
            logger.info(f"Processing check: {check['name']}")
            
            # Get check results
            check_result = support_client.describe_trusted_advisor_check_result(
                checkId=check['id'],
                language='en'
            )
            
            # Process flagged resources
            flagged_resources = check_result['result']['flaggedResources']
            
            for resource in flagged_resources:
                opportunity = {
                    'check_id': check['id'],
                    'check_name': check['name'],
                    'resource_id': resource['resourceId'],
                    'status': resource['status'],
                    'metadata': resource['metadata'],
                    'estimated_savings': extract_estimated_savings(resource),
                    'timestamp': datetime.now().isoformat()
                }
                
                # Store in DynamoDB
                store_optimization_opportunity(table, opportunity)
                
                # Add to opportunities list
                optimization_opportunities.append(opportunity)
        
        # Get additional cost insights from Cost Explorer
        cost_insights = get_cost_explorer_insights(ce_client)
        
        # Trigger remediation for auto-approved actions
        auto_remediation_results = []
        if enable_auto_remediation:
            for opportunity in optimization_opportunities:
                if should_auto_remediate(opportunity, auto_remediation_checks):
                    logger.info(f"Triggering auto-remediation for: {opportunity['resource_id']}")
                    
                    remediation_payload = {
                        'opportunity': opportunity,
                        'action': 'auto_remediate'
                    }
                    
                    try:
                        response = lambda_client.invoke(
                            FunctionName=remediation_function,
                            InvocationType='Event',
                            Payload=json.dumps(remediation_payload)
                        )
                        
                        auto_remediation_results.append({
                            'resource_id': opportunity['resource_id'],
                            'remediation_triggered': True,
                            'lambda_response': response['StatusCode']
                        })
                    except Exception as e:
                        logger.error(f"Error triggering remediation for {opportunity['resource_id']}: {str(e)}")
                        auto_remediation_results.append({
                            'resource_id': opportunity['resource_id'],
                            'remediation_triggered': False,
                            'error': str(e)
                        })
        
        # Generate summary report
        report = generate_cost_optimization_report(
            optimization_opportunities, 
            cost_insights, 
            auto_remediation_results
        )
        
        # Store report in S3
        report_key = f"cost-optimization-reports/{datetime.now().strftime('%Y/%m/%d')}/analysis-{int(datetime.now().timestamp())}.json"
        s3_client.put_object(
            Bucket=s3_bucket_name,
            Key=report_key,
            Body=json.dumps(report, indent=2, default=str),
            ContentType='application/json'
        )
        
        # Send notification if significant savings found
        total_savings = calculate_total_savings(optimization_opportunities)
        if total_savings > cost_alert_threshold:
            send_cost_optimization_notification(
                sns_client, 
                sns_topic_arn, 
                report, 
                total_savings,
                high_savings_threshold
            )
        
        logger.info("Cost optimization analysis completed successfully")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Cost optimization analysis completed successfully',
                'opportunities_found': len(optimization_opportunities),
                'auto_remediations_triggered': len(auto_remediation_results),
                'total_potential_savings': total_savings,
                'report_s3_key': report_key,
                'analysis_timestamp': datetime.now().isoformat()
            }, default=str)
        }
        
    except Exception as e:
        logger.error(f"Error in cost analysis: {str(e)}")
        
        # Send error notification
        error_notification = {
            'error': str(e),
            'timestamp': datetime.now().isoformat(),
            'function': 'cost_optimization_analysis'
        }
        
        try:
            sns_client.publish(
                TopicArn=sns_topic_arn,
                Message=json.dumps(error_notification, indent=2),
                Subject='Cost Optimization Analysis Error'
            )
        except Exception as sns_error:
            logger.error(f"Error sending SNS notification: {str(sns_error)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'timestamp': datetime.now().isoformat()
            })
        }

def get_cost_optimization_checks(support_client):
    """Get all cost optimization related Trusted Advisor checks"""
    try:
        response = support_client.describe_trusted_advisor_checks(language='en')
        
        cost_checks = []
        for check in response['checks']:
            if 'cost' in check['category'].lower():
                cost_checks.append({
                    'id': check['id'],
                    'name': check['name'],
                    'category': check['category'],
                    'description': check['description']
                })
        
        return cost_checks
    except Exception as e:
        logger.error(f"Error getting Trusted Advisor checks: {str(e)}")
        return []

def extract_estimated_savings(resource):
    """Extract estimated savings from resource metadata"""
    try:
        # Trusted Advisor stores savings in different metadata positions
        # depending on the check type
        metadata = resource.get('metadata', [])
        
        # Common patterns for savings extraction
        for item in metadata:
            if '$' in str(item) and any(keyword in str(item).lower() 
                                      for keyword in ['save', 'saving', 'cost']):
                # Extract numeric value
                import re
                savings_match = re.search(r'\$[\d,]+\.?\d*', str(item))
                if savings_match:
                    return float(savings_match.group().replace('$', '').replace(',', ''))
        
        return 0.0
    except Exception as e:
        logger.warning(f"Error extracting savings: {str(e)}")
        return 0.0

def store_optimization_opportunity(table, opportunity):
    """Store optimization opportunity in DynamoDB"""
    try:
        table.put_item(
            Item={
                'ResourceId': opportunity['resource_id'],
                'CheckId': opportunity['check_id'],
                'CheckName': opportunity['check_name'],
                'Status': opportunity['status'],
                'EstimatedSavings': Decimal(str(opportunity['estimated_savings'])),
                'Timestamp': opportunity['timestamp'],
                'Metadata': json.dumps(opportunity['metadata']),
                'TTL': int((datetime.now() + timedelta(days=90)).timestamp())  # Auto-expire after 90 days
            }
        )
    except Exception as e:
        logger.error(f"Error storing opportunity in DynamoDB: {str(e)}")

def get_cost_explorer_insights(ce_client):
    """Get additional cost insights from Cost Explorer"""
    end_date = datetime.now()
    start_date = end_date - timedelta(days=30)
    
    try:
        response = ce_client.get_cost_and_usage(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity='MONTHLY',
            Metrics=['BlendedCost'],
            GroupBy=[
                {'Type': 'DIMENSION', 'Key': 'SERVICE'}
            ]
        )
        
        return response['ResultsByTime']
    except Exception as e:
        logger.error(f"Error getting Cost Explorer insights: {str(e)}")
        return []

def should_auto_remediate(opportunity, auto_remediation_checks):
    """Determine if opportunity should be auto-remediated"""
    # Only auto-remediate for specific checks with high confidence
    return (any(check in opportunity['check_name'] for check in auto_remediation_checks) and 
            opportunity['status'] == 'warning' and
            opportunity['estimated_savings'] > 0)

def generate_cost_optimization_report(opportunities, cost_insights, auto_remediations):
    """Generate comprehensive cost optimization report"""
    total_savings = calculate_total_savings(opportunities)
    
    report = {
        'summary': {
            'total_opportunities': len(opportunities),
            'total_potential_savings': total_savings,
            'auto_remediations_applied': len(auto_remediations),
            'analysis_date': datetime.now().isoformat(),
            'high_value_opportunities': len([op for op in opportunities if op['estimated_savings'] > 50])
        },
        'top_opportunities': sorted(opportunities, 
                                  key=lambda x: x['estimated_savings'], 
                                  reverse=True)[:10],
        'savings_by_category': categorize_savings(opportunities),
        'cost_trends': cost_insights,
        'auto_remediation_results': auto_remediations,
        'recommendations': generate_recommendations(opportunities)
    }
    
    return report

def calculate_total_savings(opportunities):
    """Calculate total potential savings"""
    return sum(op['estimated_savings'] for op in opportunities)

def categorize_savings(opportunities):
    """Categorize savings by service type"""
    categories = {}
    for op in opportunities:
        service = extract_service_from_check(op['check_name'])
        if service not in categories:
            categories[service] = {'count': 0, 'total_savings': 0}
        categories[service]['count'] += 1
        categories[service]['total_savings'] += op['estimated_savings']
    
    return categories

def extract_service_from_check(check_name):
    """Extract AWS service from check name"""
    if 'EC2' in check_name:
        return 'EC2'
    elif 'RDS' in check_name:
        return 'RDS'
    elif 'EBS' in check_name:
        return 'EBS'
    elif 'S3' in check_name:
        return 'S3'
    elif 'ElastiCache' in check_name:
        return 'ElastiCache'
    elif 'Lambda' in check_name:
        return 'Lambda'
    elif 'CloudFront' in check_name:
        return 'CloudFront'
    else:
        return 'Other'

def generate_recommendations(opportunities):
    """Generate actionable recommendations based on opportunities"""
    recommendations = []
    
    # Group opportunities by service
    service_opportunities = {}
    for op in opportunities:
        service = extract_service_from_check(op['check_name'])
        if service not in service_opportunities:
            service_opportunities[service] = []
        service_opportunities[service].append(op)
    
    # Generate service-specific recommendations
    for service, ops in service_opportunities.items():
        total_service_savings = sum(op['estimated_savings'] for op in ops)
        
        if total_service_savings > 0:
            recommendations.append({
                'service': service,
                'priority': 'high' if total_service_savings > 100 else 'medium',
                'potential_savings': total_service_savings,
                'resource_count': len(ops),
                'recommendation': f"Review and optimize {len(ops)} {service} resources with potential savings of ${total_service_savings:.2f}"
            })
    
    return sorted(recommendations, key=lambda x: x['potential_savings'], reverse=True)

def send_cost_optimization_notification(sns_client, topic_arn, report, total_savings, high_savings_threshold):
    """Send notification about cost optimization opportunities"""
    try:
        notification = {
            'subject': f'Cost Optimization Alert: ${total_savings:.2f} in potential savings found',
            'summary': report['summary'],
            'top_opportunities': report['top_opportunities'][:5],  # Top 5 opportunities
            'priority': 'high' if total_savings > high_savings_threshold else 'medium',
            'timestamp': datetime.now().isoformat()
        }
        
        subject = f"Cost Optimization Alert: ${total_savings:.2f} in Potential Savings"
        
        sns_client.publish(
            TopicArn=topic_arn,
            Message=json.dumps(notification, indent=2, default=str),
            Subject=subject
        )
    except Exception as e:
        logger.error(f"Error sending cost optimization notification: {str(e)}")