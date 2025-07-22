import json
import boto3
import logging
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
pinpoint = boto3.client('pinpoint')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda function to analyze A/B test results and determine the winning treatment.
    
    This function:
    1. Retrieves campaign analytics from Pinpoint
    2. Calculates conversion rates for each treatment
    3. Determines statistical significance
    4. Identifies the winning treatment
    5. Returns results for further action
    
    Args:
        event: Lambda event containing campaign and application details
        context: Lambda context object
        
    Returns:
        Dictionary containing analysis results and winner selection
    """
    
    try:
        # Extract parameters from event
        application_id = event.get('application_id', '${application_id}')
        campaign_id = event.get('campaign_id')
        
        if not campaign_id:
            logger.error("Campaign ID is required")
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': 'Campaign ID is required',
                    'message': 'Please provide campaign_id in the event payload'
                })
            }
        
        logger.info(f"Analyzing campaign {campaign_id} for application {application_id}")
        
        # Get campaign details
        campaign_response = pinpoint.get_campaign(
            ApplicationId=application_id,
            CampaignId=campaign_id
        )
        
        campaign = campaign_response['CampaignResponse']
        logger.info(f"Campaign: {campaign['Name']}, State: {campaign['State']}")
        
        # Get campaign activities/analytics
        activities_response = pinpoint.get_campaign_activities(
            ApplicationId=application_id,
            CampaignId=campaign_id
        )
        
        activities = activities_response['ActivitiesResponse']['Item']
        logger.info(f"Retrieved {len(activities)} campaign activities")
        
        # Analyze each treatment
        treatments = []
        
        for activity in activities:
            treatment_name = activity.get('TreatmentName', 'Control')
            
            # Extract key metrics
            delivered_count = activity.get('DeliveredCount', 0)
            opened_count = activity.get('OpenedCount', 0)
            clicked_count = activity.get('ClickedCount', 0)
            
            # Calculate rates
            open_rate = (opened_count / delivered_count) if delivered_count > 0 else 0
            click_rate = (clicked_count / delivered_count) if delivered_count > 0 else 0
            
            # Get conversion events (this would require custom event tracking)
            conversion_count = get_conversion_events(
                application_id, 
                campaign_id, 
                treatment_name
            )
            
            conversion_rate = (conversion_count / delivered_count) if delivered_count > 0 else 0
            
            treatment_data = {
                'name': treatment_name,
                'delivered_count': delivered_count,
                'opened_count': opened_count,
                'clicked_count': clicked_count,
                'conversion_count': conversion_count,
                'open_rate': open_rate,
                'click_rate': click_rate,
                'conversion_rate': conversion_rate,
                'activity_id': activity.get('Id')
            }
            
            treatments.append(treatment_data)
            
            logger.info(f"Treatment {treatment_name}: "
                       f"Delivered={delivered_count}, "
                       f"Open Rate={open_rate:.2%}, "
                       f"Click Rate={click_rate:.2%}, "
                       f"Conversion Rate={conversion_rate:.2%}")
        
        # Determine winner based on conversion rate
        winner = determine_winner(treatments)
        
        # Calculate statistical significance
        significance_results = calculate_statistical_significance(treatments)
        
        # Prepare results
        results = {
            'campaign_id': campaign_id,
            'application_id': application_id,
            'campaign_name': campaign['Name'],
            'analysis_timestamp': datetime.utcnow().isoformat(),
            'treatments': treatments,
            'winner': winner,
            'statistical_significance': significance_results,
            'recommendations': generate_recommendations(winner, treatments, significance_results)
        }
        
        # Log results to CloudWatch
        log_results_to_cloudwatch(application_id, campaign_id, results)
        
        logger.info(f"Analysis complete. Winner: {winner['name'] if winner else 'No clear winner'}")
        
        return {
            'statusCode': 200,
            'body': json.dumps(results, default=str)
        }
        
    except Exception as e:
        logger.error(f"Error analyzing campaign: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Internal server error',
                'message': str(e)
            })
        }

def get_conversion_events(application_id: str, campaign_id: str, treatment_name: str) -> int:
    """
    Get conversion events for a specific treatment.
    
    This is a placeholder implementation. In a real scenario, you would:
    1. Query your event tracking system (Kinesis, CloudWatch Events, etc.)
    2. Count conversion events attributed to this campaign and treatment
    3. Return the count
    
    Args:
        application_id: Pinpoint application ID
        campaign_id: Campaign ID
        treatment_name: Treatment name
        
    Returns:
        Number of conversion events
    """
    
    # Placeholder implementation
    # In practice, you would query your event tracking system
    # For now, we'll simulate some conversion data
    
    import random
    
    # Simulate conversion events based on treatment
    if treatment_name == 'Control':
        return random.randint(10, 50)
    elif treatment_name == 'Personalized':
        return random.randint(15, 60)
    elif treatment_name == 'Urgent':
        return random.randint(20, 70)
    else:
        return random.randint(5, 30)

def determine_winner(treatments: List[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    """
    Determine the winning treatment based on conversion rate.
    
    Args:
        treatments: List of treatment data
        
    Returns:
        Winning treatment data or None if no clear winner
    """
    
    if not treatments:
        return None
    
    # Filter treatments with sufficient data
    min_delivered = 50  # Minimum number of delivered messages for reliability
    valid_treatments = [t for t in treatments if t['delivered_count'] >= min_delivered]
    
    if not valid_treatments:
        logger.warning("No treatments have sufficient data for analysis")
        return None
    
    # Find treatment with highest conversion rate
    winner = max(valid_treatments, key=lambda t: t['conversion_rate'])
    
    # Ensure winner has significantly better performance
    second_best = sorted(valid_treatments, key=lambda t: t['conversion_rate'])[-2] if len(valid_treatments) > 1 else None
    
    if second_best:
        improvement = ((winner['conversion_rate'] - second_best['conversion_rate']) / 
                      second_best['conversion_rate']) if second_best['conversion_rate'] > 0 else 0
        
        # Require at least 10% improvement to declare a winner
        if improvement < 0.1:
            logger.info("No treatment shows significant improvement")
            return None
    
    return winner

def calculate_statistical_significance(treatments: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Calculate statistical significance of results.
    
    This is a simplified implementation. In production, you would use
    proper statistical tests like chi-square or t-tests.
    
    Args:
        treatments: List of treatment data
        
    Returns:
        Statistical significance results
    """
    
    # Simplified significance calculation
    # In practice, use proper statistical methods
    
    total_delivered = sum(t['delivered_count'] for t in treatments)
    total_conversions = sum(t['conversion_count'] for t in treatments)
    
    # Calculate sample size adequacy
    min_sample_size = 100  # Minimum for basic significance
    adequate_sample = total_delivered >= min_sample_size
    
    # Calculate confidence based on sample size
    if total_delivered >= 1000:
        confidence = 0.95
    elif total_delivered >= 500:
        confidence = 0.90
    elif total_delivered >= 100:
        confidence = 0.80
    else:
        confidence = 0.70
    
    return {
        'total_delivered': total_delivered,
        'total_conversions': total_conversions,
        'adequate_sample_size': adequate_sample,
        'confidence_level': confidence,
        'note': 'This is a simplified significance calculation. Use proper statistical methods in production.'
    }

def generate_recommendations(winner: Optional[Dict[str, Any]], 
                           treatments: List[Dict[str, Any]], 
                           significance: Dict[str, Any]) -> List[str]:
    """
    Generate actionable recommendations based on analysis.
    
    Args:
        winner: Winning treatment data
        treatments: All treatment data
        significance: Statistical significance results
        
    Returns:
        List of recommendations
    """
    
    recommendations = []
    
    if not winner:
        recommendations.append("No clear winner identified. Consider running the test longer.")
        recommendations.append("Ensure sufficient sample size for reliable results.")
        return recommendations
    
    if not significance['adequate_sample_size']:
        recommendations.append("Sample size may be too small for reliable results.")
        recommendations.append("Consider extending the test duration.")
    
    if significance['confidence_level'] < 0.90:
        recommendations.append("Low confidence level. Consider increasing sample size.")
    
    recommendations.append(f"Winner: {winner['name']} with {winner['conversion_rate']:.2%} conversion rate")
    
    # Compare with other treatments
    for treatment in treatments:
        if treatment['name'] != winner['name']:
            improvement = ((winner['conversion_rate'] - treatment['conversion_rate']) / 
                          treatment['conversion_rate']) if treatment['conversion_rate'] > 0 else 0
            recommendations.append(f"{winner['name']} performed {improvement:.1%} better than {treatment['name']}")
    
    recommendations.append("Consider implementing the winning treatment for your main campaign.")
    
    return recommendations

def log_results_to_cloudwatch(application_id: str, campaign_id: str, results: Dict[str, Any]) -> None:
    """
    Log analysis results to CloudWatch for monitoring.
    
    Args:
        application_id: Pinpoint application ID
        campaign_id: Campaign ID
        results: Analysis results
    """
    
    try:
        # Create custom metrics for monitoring
        if results['winner']:
            winner = results['winner']
            
            cloudwatch.put_metric_data(
                Namespace='Pinpoint/ABTesting',
                MetricData=[
                    {
                        'MetricName': 'WinnerConversionRate',
                        'Value': winner['conversion_rate'],
                        'Unit': 'Percent',
                        'Dimensions': [
                            {
                                'Name': 'ApplicationId',
                                'Value': application_id
                            },
                            {
                                'Name': 'CampaignId',
                                'Value': campaign_id
                            },
                            {
                                'Name': 'TreatmentName',
                                'Value': winner['name']
                            }
                        ]
                    },
                    {
                        'MetricName': 'TotalDelivered',
                        'Value': winner['delivered_count'],
                        'Unit': 'Count',
                        'Dimensions': [
                            {
                                'Name': 'ApplicationId',
                                'Value': application_id
                            },
                            {
                                'Name': 'CampaignId',
                                'Value': campaign_id
                            }
                        ]
                    }
                ]
            )
        
        logger.info("Results logged to CloudWatch")
        
    except Exception as e:
        logger.error(f"Error logging to CloudWatch: {str(e)}")

# Example usage for testing
if __name__ == "__main__":
    # Test event
    test_event = {
        'application_id': '${application_id}',
        'campaign_id': 'test-campaign-id'
    }
    
    # Mock context
    class MockContext:
        def __init__(self):
            self.aws_request_id = 'test-request-id'
            self.function_name = 'test-function'
    
    result = lambda_handler(test_event, MockContext())
    print(json.dumps(result, indent=2, default=str))