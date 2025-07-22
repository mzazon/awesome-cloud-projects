import json
import boto3
import datetime
import os
from decimal import Decimal

def lambda_handler(event, context):
    """
    Lambda function to analyze Savings Plans recommendations using AWS Cost Explorer API.
    
    This function analyzes historical usage patterns and generates personalized
    Savings Plans recommendations for cost optimization.
    
    Args:
        event: Lambda event containing analysis parameters
        context: Lambda context object
        
    Returns:
        dict: Analysis results with recommendations and savings potential
    """
    
    # Initialize AWS clients
    ce_client = boto3.client('ce')
    s3_client = boto3.client('s3')
    
    # Get analysis parameters from event or environment variables
    lookback_days = event.get('lookback_days', os.environ.get('DEFAULT_LOOKBACK_DAYS', 'SIXTY_DAYS'))
    term_years = event.get('term_years', os.environ.get('DEFAULT_TERM_YEARS', 'ONE_YEAR'))
    payment_option = event.get('payment_option', os.environ.get('DEFAULT_PAYMENT_OPTION', 'NO_UPFRONT'))
    bucket_name = event.get('bucket_name', os.environ.get('S3_BUCKET_NAME', '${s3_bucket_name}'))
    
    # Initialize results structure
    results = {
        'analysis_date': datetime.datetime.now().isoformat(),
        'parameters': {
            'lookback_days': lookback_days,
            'term_years': term_years,
            'payment_option': payment_option,
            'bucket_name': bucket_name
        },
        'recommendations': [],
        'errors': []
    }
    
    # Define Savings Plans types to analyze
    savings_plans_types = ['COMPUTE_SP', 'EC2_INSTANCE_SP', 'SAGEMAKER_SP']
    
    print(f"Starting Savings Plans analysis with parameters: {results['parameters']}")
    
    # Analyze each Savings Plans type
    for sp_type in savings_plans_types:
        try:
            print(f"Analyzing {sp_type} recommendations...")
            
            # Get Savings Plans recommendations from Cost Explorer
            response = ce_client.get_savings_plans_purchase_recommendation(
                SavingsPlansType=sp_type,
                TermInYears=term_years,
                PaymentOption=payment_option,
                LookbackPeriodInDays=lookback_days,
                PageSize=10
            )
            
            # Process recommendation data
            if 'SavingsPlansPurchaseRecommendation' in response:
                rec = response['SavingsPlansPurchaseRecommendation']
                summary = rec.get('SavingsPlansPurchaseRecommendationSummary', {})
                
                # Create recommendation summary
                recommendation = {
                    'savings_plan_type': sp_type,
                    'summary': {
                        'estimated_monthly_savings': summary.get('EstimatedMonthlySavingsAmount', '0'),
                        'estimated_roi': summary.get('EstimatedROI', '0'),
                        'estimated_savings_percentage': summary.get('EstimatedSavingsPercentage', '0'),
                        'hourly_commitment': summary.get('HourlyCommitmentToPurchase', '0'),
                        'total_recommendations': summary.get('TotalRecommendationCount', '0')
                    },
                    'details': []
                }
                
                # Process detailed recommendations
                for detail in rec.get('SavingsPlansPurchaseRecommendationDetails', []):
                    detail_record = {
                        'account_id': detail.get('AccountId', ''),
                        'currency_code': detail.get('CurrencyCode', 'USD'),
                        'estimated_monthly_savings': detail.get('EstimatedMonthlySavingsAmount', '0'),
                        'estimated_roi': detail.get('EstimatedROI', '0'),
                        'hourly_commitment': detail.get('HourlyCommitmentToPurchase', '0'),
                        'upfront_cost': detail.get('UpfrontCost', '0'),
                        'savings_plans_details': detail.get('SavingsPlansDetails', {})
                    }
                    recommendation['details'].append(detail_record)
                
                results['recommendations'].append(recommendation)
                print(f"Successfully analyzed {sp_type}: {len(recommendation['details'])} recommendations found")
                
            else:
                print(f"No recommendations found for {sp_type}")
                results['recommendations'].append({
                    'savings_plan_type': sp_type,
                    'summary': {
                        'estimated_monthly_savings': '0',
                        'estimated_roi': '0',
                        'estimated_savings_percentage': '0',
                        'hourly_commitment': '0',
                        'total_recommendations': '0'
                    },
                    'details': []
                })
                
        except Exception as e:
            error_msg = f"Error analyzing {sp_type}: {str(e)}"
            print(error_msg)
            results['errors'].append({
                'savings_plan_type': sp_type,
                'error': str(e),
                'timestamp': datetime.datetime.now().isoformat()
            })
            
            # Add error placeholder in recommendations
            results['recommendations'].append({
                'savings_plan_type': sp_type,
                'error': str(e),
                'summary': {
                    'estimated_monthly_savings': '0',
                    'estimated_roi': '0',
                    'estimated_savings_percentage': '0',
                    'hourly_commitment': '0',
                    'total_recommendations': '0'
                }
            })
    
    # Calculate total potential savings across all Savings Plans types
    total_monthly_savings = 0
    successful_analyses = 0
    
    for rec in results['recommendations']:
        if 'error' not in rec:
            try:
                savings = float(rec['summary']['estimated_monthly_savings'])
                total_monthly_savings += savings
                if savings > 0:
                    successful_analyses += 1
            except (ValueError, KeyError, TypeError):
                pass
    
    # Add totals and analysis summary
    results['analysis_summary'] = {
        'total_monthly_savings': round(total_monthly_savings, 2),
        'annual_savings_potential': round(total_monthly_savings * 12, 2),
        'successful_analyses': successful_analyses,
        'total_analyses': len(savings_plans_types),
        'analysis_success_rate': round((successful_analyses / len(savings_plans_types)) * 100, 2)
    }
    
    # Generate insights and recommendations
    insights = generate_insights(results)
    results['insights'] = insights
    
    # Save results to S3
    if bucket_name:
        try:
            timestamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
            key = f"savings-plans-recommendations/{timestamp}.json"
            
            # Prepare S3 object with metadata
            s3_object = {
                'analysis_metadata': {
                    'generated_at': datetime.datetime.now().isoformat(),
                    'parameters': results['parameters'],
                    'total_savings': results['analysis_summary']['total_monthly_savings'],
                    'version': '1.0'
                },
                'results': results
            }
            
            s3_client.put_object(
                Bucket=bucket_name,
                Key=key,
                Body=json.dumps(s3_object, indent=2, default=str),
                ContentType='application/json',
                Metadata={
                    'analysis-date': timestamp,
                    'total-monthly-savings': str(results['analysis_summary']['total_monthly_savings']),
                    'successful-analyses': str(successful_analyses)
                }
            )
            
            results['report_location'] = f"s3://{bucket_name}/{key}"
            print(f"Results saved to S3: {results['report_location']}")
            
        except Exception as e:
            error_msg = f"Error saving results to S3: {str(e)}"
            print(error_msg)
            results['errors'].append({
                'component': 'S3 Save',
                'error': str(e),
                'timestamp': datetime.datetime.now().isoformat()
            })
    
    # Log final results
    print(f"Analysis complete. Total monthly savings potential: ${results['analysis_summary']['total_monthly_savings']}")
    print(f"Annual savings potential: ${results['analysis_summary']['annual_savings_potential']}")
    print(f"Successful analyses: {successful_analyses}/{len(savings_plans_types)}")
    
    return {
        'statusCode': 200,
        'body': json.dumps(results, indent=2, default=str),
        'headers': {
            'Content-Type': 'application/json'
        }
    }

def generate_insights(results):
    """
    Generate insights and recommendations based on analysis results.
    
    Args:
        results: Analysis results dictionary
        
    Returns:
        dict: Insights and recommendations
    """
    insights = {
        'recommendations': [],
        'warnings': [],
        'opportunities': []
    }
    
    total_savings = results['analysis_summary']['total_monthly_savings']
    
    # Generate recommendations based on savings potential
    if total_savings > 1000:
        insights['recommendations'].append({
            'type': 'high_savings',
            'message': f"High savings potential detected (${total_savings}/month). Consider implementing Savings Plans immediately.",
            'priority': 'high'
        })
    elif total_savings > 100:
        insights['recommendations'].append({
            'type': 'moderate_savings',
            'message': f"Moderate savings potential (${total_savings}/month). Review recommendations for cost optimization.",
            'priority': 'medium'
        })
    elif total_savings > 0:
        insights['recommendations'].append({
            'type': 'low_savings',
            'message': f"Low savings potential (${total_savings}/month). Monitor usage patterns for future opportunities.",
            'priority': 'low'
        })
    else:
        insights['recommendations'].append({
            'type': 'no_savings',
            'message': "No significant savings opportunities detected. Current usage may already be optimized.",
            'priority': 'info'
        })
    
    # Analyze each Savings Plans type
    for rec in results['recommendations']:
        if 'error' not in rec:
            sp_type = rec['savings_plan_type']
            monthly_savings = float(rec['summary']['estimated_monthly_savings'])
            roi = float(rec['summary']['estimated_roi'])
            
            if monthly_savings > 0:
                insights['opportunities'].append({
                    'savings_plan_type': sp_type,
                    'monthly_savings': monthly_savings,
                    'roi_percentage': roi,
                    'recommendation': f"Consider {sp_type.replace('_', ' ').title()} with ${monthly_savings}/month savings potential"
                })
    
    # Add warnings for analysis issues
    if results['errors']:
        insights['warnings'].append({
            'type': 'analysis_errors',
            'message': f"{len(results['errors'])} analysis errors occurred. Some recommendations may be incomplete.",
            'details': results['errors']
        })
    
    return insights