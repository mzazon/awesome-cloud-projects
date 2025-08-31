import json
import boto3
import datetime
from decimal import Decimal
import os

def lambda_handler(event, context):
    """
    VPC Lattice Cost Analytics Lambda Function
    
    This function combines VPC Lattice CloudWatch metrics with Cost Explorer data
    to generate comprehensive cost analytics for service mesh infrastructure.
    """
    
    # Initialize AWS service clients
    ce_client = boto3.client('ce')
    cw_client = boto3.client('cloudwatch')
    s3_client = boto3.client('s3')
    lattice_client = boto3.client('vpc-lattice')
    
    # Get S3 bucket name from environment variable
    bucket_name = os.environ.get('BUCKET_NAME', '${bucket_name}')
    
    # Calculate date range for cost analysis (last 7 days)
    end_date = datetime.datetime.now().date()
    start_date = end_date - datetime.timedelta(days=7)
    
    try:
        print(f"Starting cost analytics for period: {start_date} to {end_date}")
        
        # Get VPC Lattice service networks
        service_networks = lattice_client.list_service_networks()
        print(f"Found {len(service_networks.get('items', []))} VPC Lattice service networks")
        
        cost_data = {}
        
        # Query Cost Explorer for VPC Lattice related costs
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
            ],
            Filter={
                'Or': [
                    {
                        'Dimensions': {
                            'Key': 'SERVICE',
                            'Values': ['Amazon Virtual Private Cloud']
                        }
                    },
                    {
                        'Dimensions': {
                            'Key': 'SERVICE',
                            'Values': ['VPC Lattice', 'Amazon VPC Lattice']
                        }
                    }
                ]
            }
        )
        
        # Process cost data from Cost Explorer
        for result in response['ResultsByTime']:
            date = result['TimePeriod']['Start']
            for group in result['Groups']:
                service = group['Keys'][0]
                region = group['Keys'][1]
                amount = float(group['Metrics']['BlendedCost']['Amount'])
                
                cost_data[f"{date}_{service}_{region}"] = {
                    'date': date,
                    'service': service,
                    'region': region,
                    'cost': amount,
                    'currency': group['Metrics']['BlendedCost']['Unit']
                }
        
        print(f"Processed {len(cost_data)} cost data points")
        
        # Get VPC Lattice CloudWatch metrics
        metrics_data = {}
        for network in service_networks.get('items', []):
            network_id = network['id']
            network_name = network.get('name', network_id)
            
            try:
                # Get request count metrics for service network
                metric_response = cw_client.get_metric_statistics(
                    Namespace='AWS/VpcLattice',
                    MetricName='TotalRequestCount',
                    Dimensions=[
                        {'Name': 'ServiceNetwork', 'Value': network_id}
                    ],
                    StartTime=datetime.datetime.combine(start_date, datetime.time.min),
                    EndTime=datetime.datetime.combine(end_date, datetime.time.min),
                    Period=86400,  # Daily
                    Statistics=['Sum']
                )
                
                total_requests = sum([point['Sum'] for point in metric_response['Datapoints']])
                
                metrics_data[network_id] = {
                    'network_name': network_name,
                    'request_count': total_requests
                }
                
                print(f"Processed metrics for network {network_name}: {total_requests} requests")
                
            except Exception as e:
                print(f"Warning: Could not retrieve metrics for network {network_id}: {str(e)}")
                metrics_data[network_id] = {
                    'network_name': network_name,
                    'request_count': 0
                }
        
        # Combine cost and metrics data into analytics report
        analytics_report = {
            'report_date': end_date.isoformat(),
            'time_period': {
                'start': start_date.isoformat(),
                'end': end_date.isoformat()
            },
            'cost_data': cost_data,
            'metrics_data': metrics_data,
            'summary': {
                'total_cost': sum([item['cost'] for item in cost_data.values()]),
                'total_requests': sum([item['request_count'] for item in metrics_data.values()]),
                'cost_per_request': 0
            }
        }
        
        # Calculate cost per request if requests exist
        if analytics_report['summary']['total_requests'] > 0:
            analytics_report['summary']['cost_per_request'] = (
                analytics_report['summary']['total_cost'] / 
                analytics_report['summary']['total_requests']
            )
        
        # Store analytics report in S3
        report_key = f"cost-reports/{end_date.isoformat()}_lattice_analytics.json"
        s3_client.put_object(
            Bucket=bucket_name,
            Key=report_key,
            Body=json.dumps(analytics_report, indent=2),
            ContentType='application/json'
        )
        
        print(f"Stored analytics report in S3: {report_key}")
        
        # Create CloudWatch custom metrics for dashboard visualization
        metric_data = [
            {
                'MetricName': 'TotalCost',
                'Value': analytics_report['summary']['total_cost'],
                'Unit': 'None',
                'Timestamp': datetime.datetime.now()
            },
            {
                'MetricName': 'TotalRequests',
                'Value': analytics_report['summary']['total_requests'],
                'Unit': 'Count',
                'Timestamp': datetime.datetime.now()
            },
            {
                'MetricName': 'CostPerRequest',
                'Value': analytics_report['summary']['cost_per_request'],
                'Unit': 'None',
                'Timestamp': datetime.datetime.now()
            }
        ]
        
        # Publish custom metrics to CloudWatch
        cw_client.put_metric_data(
            Namespace='VPCLattice/CostAnalytics',
            MetricData=metric_data
        )
        
        print("Published custom metrics to CloudWatch")
        
        # Return success response
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Cost analytics completed successfully',
                'report_location': f's3://{bucket_name}/{report_key}',
                'summary': analytics_report['summary'],
                'timestamp': datetime.datetime.now().isoformat()
            })
        }
        
    except Exception as e:
        error_message = f"Error processing cost analytics: {str(e)}"
        print(error_message)
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_message,
                'timestamp': datetime.datetime.now().isoformat()
            })
        }