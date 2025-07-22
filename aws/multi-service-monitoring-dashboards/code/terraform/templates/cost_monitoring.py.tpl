import json
import boto3
from datetime import datetime, timedelta

cloudwatch = boto3.client('cloudwatch')
ce = boto3.client('ce')

def lambda_handler(event, context):
    """
    Lambda function to monitor AWS costs and publish cost metrics to CloudWatch.
    This function retrieves cost data from AWS Cost Explorer and publishes trends.
    """
    try:
        # Get cost data for the last 7 days
        end_date = datetime.now().date()
        start_date = end_date - timedelta(days=7)
        
        print(f"Retrieving cost data from {start_date} to {end_date}")
        
        # Get cost and usage data
        response = ce.get_cost_and_usage(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity='DAILY',
            Metrics=['BlendedCost'],
            GroupBy=[
                {
                    'Type': 'DIMENSION',
                    'Key': 'SERVICE'
                }
            ]
        )
        
        # Process cost data
        daily_costs = []
        service_costs = {}
        
        for result in response['ResultsByTime']:
            date_str = result['TimePeriod']['Start']
            daily_cost = float(result['Total']['BlendedCost']['Amount'])
            daily_costs.append(daily_cost)
            
            print(f"Daily cost for {date_str}: ${daily_cost:.2f}")
            
            # Collect service-specific costs
            for group in result['Groups']:
                service_name = group['Keys'][0] if group['Keys'] else 'Unknown'
                service_cost = float(group['Metrics']['BlendedCost']['Amount'])
                
                if service_name not in service_costs:
                    service_costs[service_name] = []
                service_costs[service_name].append(service_cost)
        
        # Calculate cost metrics
        if daily_costs:
            avg_daily_cost = sum(daily_costs) / len(daily_costs)
            latest_cost = daily_costs[-1]
            
            # Calculate cost trend (percentage change from average)
            if avg_daily_cost > 0:
                cost_trend = ((latest_cost - avg_daily_cost) / avg_daily_cost) * 100
            else:
                cost_trend = 0
                
            # Calculate weekly total
            weekly_total = sum(daily_costs)
            
            # Find top spending services
            top_services = {}
            for service, costs in service_costs.items():
                total_service_cost = sum(costs)
                if total_service_cost > 0:
                    top_services[service] = total_service_cost
            
            # Sort services by cost
            sorted_services = sorted(top_services.items(), key=lambda x: x[1], reverse=True)
            
        else:
            avg_daily_cost = 0
            latest_cost = 0
            cost_trend = 0
            weekly_total = 0
            sorted_services = []
        
        # Publish cost metrics to CloudWatch
        metrics = [
            {
                'MetricName': 'DailyCost',
                'Value': latest_cost,
                'Unit': 'None',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': '${environment}'}
                ]
            },
            {
                'MetricName': 'CostTrend',
                'Value': cost_trend,
                'Unit': 'Percent',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': '${environment}'}
                ]
            },
            {
                'MetricName': 'WeeklyAverageCost',
                'Value': avg_daily_cost,
                'Unit': 'None',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': '${environment}'}
                ]
            },
            {
                'MetricName': 'WeeklyTotalCost',
                'Value': weekly_total,
                'Unit': 'None',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': '${environment}'}
                ]
            }
        ]
        
        # Add top service costs (up to 5 services)
        for service, cost in sorted_services[:5]:
            # Clean service name for metric dimensions
            clean_service_name = service.replace(' ', '_').replace('-', '_')
            metrics.append({
                'MetricName': 'ServiceCost',
                'Value': cost,
                'Unit': 'None',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': '${environment}'},
                    {'Name': 'Service', 'Value': clean_service_name}
                ]
            })
        
        # Submit metrics to CloudWatch
        if metrics:
            cloudwatch.put_metric_data(
                Namespace='Cost/Management',
                MetricData=metrics
            )
        
        print(f"Cost metrics published: {len(metrics)} metrics")
        print(f"Daily cost: ${latest_cost:.2f}")
        print(f"Cost trend: {cost_trend:.1f}%")
        print(f"Weekly average: ${avg_daily_cost:.2f}")
        print(f"Weekly total: ${weekly_total:.2f}")
        
        if sorted_services:
            print("Top spending services:")
            for service, cost in sorted_services[:5]:
                print(f"  {service}: ${cost:.2f}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'daily_cost': latest_cost,
                'cost_trend': cost_trend,
                'weekly_average': avg_daily_cost,
                'weekly_total': weekly_total,
                'top_services': dict(sorted_services[:5]),
                'metrics_published': len(metrics)
            })
        }
        
    except Exception as e:
        print(f"Error monitoring costs: {str(e)}")
        
        # Publish error metric
        try:
            cloudwatch.put_metric_data(
                Namespace='Cost/Management',
                MetricData=[
                    {
                        'MetricName': 'CostMonitoringErrors',
                        'Value': 1,
                        'Unit': 'Count',
                        'Dimensions': [
                            {'Name': 'Environment', 'Value': '${environment}'}
                        ]
                    }
                ]
            )
        except:
            pass  # Ignore errors when publishing error metrics
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Cost monitoring failed'
            })
        }

def get_cost_anomalies():
    """
    Get cost anomalies from AWS Cost Anomaly Detection.
    This function can be extended to integrate with Cost Anomaly Detection service.
    
    Returns:
        list: List of cost anomalies
    """
    try:
        # This would require AWS Cost Anomaly Detection to be set up
        # For now, return empty list
        return []
        
    except Exception as e:
        print(f"Error getting cost anomalies: {str(e)}")
        return []