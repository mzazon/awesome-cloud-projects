#!/usr/bin/env python3
"""
AWS CDK Python Application for Service Performance Cost Analytics with VPC Lattice and CloudWatch Insights

This CDK application deploys the complete infrastructure for correlating VPC Lattice service mesh 
performance metrics with AWS costs using CloudWatch Insights queries and Cost Explorer API integration.

The solution creates:
- VPC Lattice Service Network with monitoring
- Lambda functions for performance analysis and cost correlation
- CloudWatch Log Groups and access logging
- EventBridge scheduling for automated analysis
- IAM roles with appropriate permissions
- CloudWatch Dashboard for visualization
"""

import aws_cdk as cdk
from aws_cdk import (
    Duration,
    RemovalPolicy,
    Stack,
    StackProps,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_logs as logs,
    aws_events as events,
    aws_events_targets as targets,
    aws_cloudwatch as cloudwatch,
    aws_vpclattice as vpclattice,
    aws_ce as ce,
)
from constructs import Construct
import os


class ServicePerformanceCostAnalyticsStack(Stack):
    """
    CDK Stack for Service Performance Cost Analytics with VPC Lattice and CloudWatch Insights
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names to avoid conflicts
        unique_suffix = self.node.try_get_context("unique_suffix") or "demo"
        
        # Stack parameters
        service_network_name = f"analytics-mesh-{unique_suffix}"
        log_group_name = "/aws/vpclattice/performance-analytics"
        
        # Create CloudWatch Log Group for VPC Lattice logs
        log_group = logs.LogGroup(
            self,
            "VpcLatticeLogGroup",
            log_group_name=log_group_name,
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )

        # Create IAM role for Lambda functions with comprehensive permissions
        lambda_role = iam.Role(
            self,
            "LambdaAnalyticsRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole"),
                iam.ManagedPolicy.from_aws_managed_policy_name("CloudWatchLogsFullAccess")
            ],
            inline_policies={
                "CostExplorerAnalyticsPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "ce:GetCostAndUsage",
                                "ce:GetDimensionValues",
                                "ce:GetMetricsAndUsage",
                                "ce:ListCostCategoryDefinitions",
                                "ce:GetUsageReport",
                                "ce:GetAnomalyDetectors",
                                "ce:GetAnomalySubscriptions"
                            ],
                            resources=["*"]
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "cloudwatch:PutMetricData",
                                "logs:StartQuery",
                                "logs:GetQueryResults",
                                "vpc-lattice:GetService",
                                "vpc-lattice:GetServiceNetwork",
                                "vpc-lattice:ListServices",
                                "vpc-lattice:ListServiceNetworks",
                                "lambda:InvokeFunction"
                            ],
                            resources=["*"]
                        )
                    ]
                )
            }
        )

        # Create VPC Lattice Service Network
        service_network = vpclattice.CfnServiceNetwork(
            self,
            "AnalyticsServiceNetwork",
            name=service_network_name,
            auth_type="AWS_IAM",
            tags=[
                cdk.CfnTag(key="Purpose", value="PerformanceCostAnalytics"),
                cdk.CfnTag(key="Environment", value="Demo")
            ]
        )

        # Configure access logging for VPC Lattice
        access_log_subscription = vpclattice.CfnAccessLogSubscription(
            self,
            "ServiceNetworkAccessLog",
            resource_identifier=service_network.attr_arn,
            destination_arn=log_group.log_group_arn
        )

        # Create Performance Analyzer Lambda Function
        performance_analyzer = lambda_.Function(
            self,
            "PerformanceAnalyzer",
            function_name=f"performance-analyzer-{unique_suffix}",
            runtime=lambda_.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline("""
import json
import boto3
import time
from datetime import datetime, timedelta

def lambda_handler(event, context):
    logs_client = boto3.client('logs')
    cloudwatch = boto3.client('cloudwatch')
    
    try:
        # Calculate time range for analysis (last 24 hours)
        end_time = datetime.now()
        start_time = end_time - timedelta(hours=24)
        
        # CloudWatch Insights query for VPC Lattice performance
        query = '''
        fields @timestamp, sourceVpc, targetService, responseTime, requestSize, responseSize
        | filter @message like /requestId/
        | stats avg(responseTime) as avgResponseTime, 
                sum(requestSize) as totalRequests,
                sum(responseSize) as totalBytes,
                count() as requestCount by targetService
        | sort avgResponseTime desc
        '''
        
        # Start CloudWatch Insights query
        query_response = logs_client.start_query(
            logGroupName=event.get('log_group', '/aws/vpclattice/performance-analytics'),
            startTime=int(start_time.timestamp()),
            endTime=int(end_time.timestamp()),
            queryString=query
        )
        
        query_id = query_response['queryId']
        
        # Wait for query completion
        for attempt in range(30):  # Wait up to 30 seconds
            query_status = logs_client.get_query_results(queryId=query_id)
            if query_status['status'] == 'Complete':
                break
            elif query_status['status'] == 'Failed':
                raise Exception(f"Query failed: {query_status.get('statistics', {})}")
            time.sleep(1)
        else:
            raise Exception("Query timeout after 30 seconds")
        
        # Process results and publish custom metrics
        performance_data = []
        for result in query_status.get('results', []):
            service_metrics = {}
            for field in result:
                service_metrics[field['field']] = field['value']
            
            if service_metrics:
                performance_data.append(service_metrics)
                
                # Publish custom CloudWatch metrics
                if 'targetService' in service_metrics and 'avgResponseTime' in service_metrics:
                    try:
                        cloudwatch.put_metric_data(
                            Namespace='VPCLattice/Performance',
                            MetricData=[
                                {
                                    'MetricName': 'AverageResponseTime',
                                    'Dimensions': [
                                        {
                                            'Name': 'ServiceName',
                                            'Value': service_metrics['targetService']
                                        }
                                    ],
                                    'Value': float(service_metrics['avgResponseTime']),
                                    'Unit': 'Milliseconds',
                                    'Timestamp': datetime.now()
                                }
                            ]
                        )
                    except Exception as metric_error:
                        print(f"Error publishing metrics: {metric_error}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Performance analysis completed',
                'services_analyzed': len(performance_data),
                'performance_data': performance_data,
                'query_id': query_id
            })
        }
        
    except Exception as e:
        print(f"Error in performance analysis: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Performance analysis failed'
            })
        }
            """),
            role=lambda_role,
            timeout=Duration.seconds(90),
            memory_size=256,
            environment={
                "LOG_GROUP_NAME": log_group_name
            },
            description="Analyzes VPC Lattice performance metrics using CloudWatch Insights"
        )

        # Create Cost Correlator Lambda Function
        cost_correlator = lambda_.Function(
            self,
            "CostCorrelator",
            function_name=f"cost-correlator-{unique_suffix}",
            runtime=lambda_.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline("""
import json
import boto3
from datetime import datetime, timedelta

def lambda_handler(event, context):
    ce_client = boto3.client('ce')
    
    try:
        # Calculate date range for cost analysis
        end_date = datetime.now()
        start_date = end_date - timedelta(days=7)
        
        # Get cost and usage data for VPC Lattice and related services
        cost_response = ce_client.get_cost_and_usage(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity='DAILY',
            Metrics=['BlendedCost', 'UsageQuantity'],
            GroupBy=[
                {
                    'Type': 'DIMENSION',
                    'Key': 'SERVICE'
                }
            ],
            Filter={
                'Dimensions': {
                    'Key': 'SERVICE',
                    'Values': ['Amazon Virtual Private Cloud', 'Amazon Elastic Compute Cloud - Compute', 'AWS Lambda'],
                    'MatchOptions': ['EQUALS']
                }
            }
        )
        
        # Process cost data
        cost_analysis = {}
        total_cost = 0.0
        
        for result_by_time in cost_response['ResultsByTime']:
            date = result_by_time['TimePeriod']['Start']
            cost_analysis[date] = {}
            
            for group in result_by_time['Groups']:
                service = group['Keys'][0]
                cost = float(group['Metrics']['BlendedCost']['Amount'])
                usage = float(group['Metrics']['UsageQuantity']['Amount'])
                
                cost_analysis[date][service] = {
                    'cost': cost,
                    'usage': usage,
                    'cost_per_unit': cost / usage if usage > 0 else 0
                }
                total_cost += cost
        
        # Correlate with performance data from event
        performance_data = event.get('performance_data', [])
        
        correlations = []
        for service_perf in performance_data:
            service_name = service_perf.get('targetService', 'unknown')
            avg_response_time = float(service_perf.get('avgResponseTime', 0)) if service_perf.get('avgResponseTime') else 0
            request_count = int(service_perf.get('requestCount', 0)) if service_perf.get('requestCount') else 0
            
            # Calculate cost efficiency metric
            vpc_cost = sum(
                day_data.get('Amazon Virtual Private Cloud', {}).get('cost', 0) 
                for day_data in cost_analysis.values()
            )
            
            if request_count > 0 and avg_response_time > 0:
                cost_per_request = vpc_cost / request_count if request_count > 0 else 0
                # Efficiency score: higher is better (inverse relationship with cost and response time)
                efficiency_score = 1000 / (avg_response_time * (cost_per_request + 0.001)) if (avg_response_time > 0 and cost_per_request >= 0) else 0
            else:
                cost_per_request = 0
                efficiency_score = 0
            
            correlations.append({
                'service': service_name,
                'avg_response_time': avg_response_time,
                'request_count': request_count,
                'estimated_cost': vpc_cost,
                'cost_per_request': cost_per_request,
                'efficiency_score': efficiency_score
            })
        
        # Sort by efficiency score to identify optimization opportunities
        correlations.sort(key=lambda x: x['efficiency_score'], reverse=True)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'cost_analysis': cost_analysis,
                'total_cost_analyzed': total_cost,
                'service_correlations': correlations,
                'optimization_candidates': [
                    corr for corr in correlations 
                    if corr['efficiency_score'] < 50  # Low efficiency threshold
                ]
            })
        }
        
    except Exception as e:
        print(f"Error in cost correlation: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Cost correlation analysis failed'
            })
        }
            """),
            role=lambda_role,
            timeout=Duration.seconds(120),
            memory_size=512,
            description="Correlates VPC Lattice performance with AWS costs"
        )

        # Create Report Generator Lambda Function
        report_generator = lambda_.Function(
            self,
            "ReportGenerator",
            function_name=f"report-generator-{unique_suffix}",
            runtime=lambda_.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(f"""
import json
import boto3
from datetime import datetime

def lambda_handler(event, context):
    lambda_client = boto3.client('lambda')
    
    try:
        suffix = event.get('suffix', '{unique_suffix}')
        log_group = event.get('log_group', '{log_group_name}')
        
        # Invoke performance analyzer
        perf_response = lambda_client.invoke(
            FunctionName=f"performance-analyzer-{{suffix}}",
            InvocationType='RequestResponse',
            Payload=json.dumps({{
                'log_group': log_group
            }})
        )
        
        perf_data = json.loads(perf_response['Payload'].read())
        
        # Check for errors in performance analysis
        if perf_data.get('statusCode') != 200:
            raise Exception(f"Performance analysis failed: {{perf_data.get('body', 'Unknown error')}}")
        
        perf_body = json.loads(perf_data.get('body', '{{}}'))
        
        # Invoke cost correlator with performance data
        cost_response = lambda_client.invoke(
            FunctionName=f"cost-correlator-{{suffix}}",
            InvocationType='RequestResponse',
            Payload=json.dumps({{
                'performance_data': perf_body.get('performance_data', [])
            }})
        )
        
        cost_data = json.loads(cost_response['Payload'].read())
        
        # Check for errors in cost analysis
        if cost_data.get('statusCode') != 200:
            raise Exception(f"Cost analysis failed: {{cost_data.get('body', 'Unknown error')}}")
        
        cost_body = json.loads(cost_data.get('body', '{{}}'))
        
        # Generate comprehensive report
        optimization_candidates = cost_body.get('optimization_candidates', [])
        
        report = {{
            'timestamp': datetime.now().isoformat(),
            'summary': {{
                'services_analyzed': perf_body.get('services_analyzed', 0),
                'optimization_opportunities': len(optimization_candidates),
                'total_cost_analyzed': cost_body.get('total_cost_analyzed', 0),
                'analysis_period': '24 hours (performance) / 7 days (cost)'
            }},
            'performance_insights': perf_body.get('performance_data', []),
            'cost_correlations': cost_body.get('service_correlations', []),
            'optimization_recommendations': optimization_candidates
        }}
        
        # Generate actionable recommendations
        recommendations = []
        for candidate in optimization_candidates:
            service_name = candidate.get('service', 'unknown')
            avg_response_time = candidate.get('avg_response_time', 0)
            cost_per_request = candidate.get('cost_per_request', 0)
            
            if avg_response_time > 500:  # High response time threshold
                recommendations.append(f"Service {{service_name}}: Consider optimizing for performance (avg response time: {{avg_response_time:.2f}}ms)")
            
            if cost_per_request > 0.01:  # High cost per request threshold
                recommendations.append(f"Service {{service_name}}: Review resource allocation (cost per request: ${{cost_per_request:.4f}})")
            
            if candidate.get('efficiency_score', 0) < 10:  # Very low efficiency
                recommendations.append(f"Service {{service_name}}: Critical efficiency review needed (efficiency score: {{candidate.get('efficiency_score', 0):.2f}})")
        
        if not recommendations:
            recommendations.append("No critical optimization opportunities identified. Continue monitoring for trends.")
        
        report['actionable_recommendations'] = recommendations
        
        return {{
            'statusCode': 200,
            'body': json.dumps(report, default=str, indent=2)
        }}
        
    except Exception as e:
        print(f"Error in report generation: {{str(e)}}")
        return {{
            'statusCode': 500,
            'body': json.dumps({{
                'error': str(e),
                'message': 'Report generation failed',
                'timestamp': datetime.now().isoformat()
            }})
        }}
            """),
            role=lambda_role,
            timeout=Duration.seconds(180),
            memory_size=256,
            description="Orchestrates performance and cost analysis reporting"
        )

        # Create EventBridge rule for scheduled analytics
        analytics_rule = events.Rule(
            self,
            "AnalyticsScheduler",
            rule_name=f"analytics-scheduler-{unique_suffix}",
            schedule=events.Schedule.rate(Duration.hours(6)),
            description="Trigger VPC Lattice performance cost analytics every 6 hours",
            enabled=True
        )

        # Add Lambda target to EventBridge rule
        analytics_rule.add_target(
            targets.LambdaFunction(
                report_generator,
                event=events.RuleTargetInput.from_object({
                    "suffix": unique_suffix,
                    "log_group": log_group_name
                })
            )
        )

        # Create sample VPC Lattice service for testing
        sample_service = vpclattice.CfnService(
            self,
            "SampleAnalyticsService",
            name=f"sample-analytics-service-{unique_suffix}",
            tags=[
                cdk.CfnTag(key="Purpose", value="AnalyticsDemo"),
                cdk.CfnTag(key="CostCenter", value="Analytics")
            ]
        )

        # Associate sample service with service network
        service_association = vpclattice.CfnServiceNetworkServiceAssociation(
            self,
            "SampleServiceAssociation",
            service_network_identifier=service_network.attr_id,
            service_identifier=sample_service.attr_id,
            tags=[
                cdk.CfnTag(key="Purpose", value="AnalyticsDemo")
            ]
        )

        # Create CloudWatch Dashboard for performance cost analytics
        dashboard = cloudwatch.Dashboard(
            self,
            "PerformanceCostAnalyticsDashboard",
            dashboard_name=f"VPC-Lattice-Performance-Cost-Analytics-{unique_suffix}",
            widgets=[
                [
                    cloudwatch.GraphWidget(
                        title="VPC Lattice Performance Metrics",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/VPCLattice",
                                metric_name="NewConnectionCount",
                                dimensions_map={
                                    "ServiceNetwork": service_network_name
                                },
                                statistic="Average"
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/VPCLattice",
                                metric_name="ActiveConnectionCount",
                                dimensions_map={
                                    "ServiceNetwork": service_network_name
                                },
                                statistic="Average"
                            )
                        ],
                        right=[
                            cloudwatch.Metric(
                                namespace="VPCLattice/Performance",
                                metric_name="AverageResponseTime",
                                dimensions_map={
                                    "ServiceName": f"sample-analytics-service-{unique_suffix}"
                                },
                                statistic="Average"
                            )
                        ],
                        width=12,
                        height=6,
                        period=Duration.minutes(5)
                    )
                ],
                [
                    cloudwatch.LogQueryWidget(
                        title="Service Response Time Analysis",
                        log_groups=[log_group],
                        query_lines=[
                            "fields @timestamp, targetService, responseTime, requestSize",
                            "| filter @message like /requestId/",
                            "| stats avg(responseTime) as avgResponseTime by targetService",
                            "| sort avgResponseTime desc"
                        ],
                        width=24,
                        height=6
                    )
                ]
            ]
        )

        # Stack Outputs
        cdk.CfnOutput(
            self,
            "ServiceNetworkId",
            value=service_network.attr_id,
            description="VPC Lattice Service Network ID"
        )

        cdk.CfnOutput(
            self,
            "ServiceNetworkArn",
            value=service_network.attr_arn,
            description="VPC Lattice Service Network ARN"
        )

        cdk.CfnOutput(
            self,
            "PerformanceAnalyzerFunction",
            value=performance_analyzer.function_name,
            description="Performance Analyzer Lambda Function Name"
        )

        cdk.CfnOutput(
            self,
            "CostCorrelatorFunction",
            value=cost_correlator.function_name,
            description="Cost Correlator Lambda Function Name"
        )

        cdk.CfnOutput(
            self,
            "ReportGeneratorFunction",
            value=report_generator.function_name,
            description="Report Generator Lambda Function Name"
        )

        cdk.CfnOutput(
            self,
            "CloudWatchDashboard",
            value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={dashboard.dashboard_name}",
            description="CloudWatch Dashboard URL"
        )

        cdk.CfnOutput(
            self,
            "LogGroupName",
            value=log_group.log_group_name,
            description="CloudWatch Log Group for VPC Lattice logs"
        )


app = cdk.App()

# Get unique suffix from context or use default
unique_suffix = app.node.try_get_context("unique_suffix") or "demo"

ServicePerformanceCostAnalyticsStack(
    app, 
    "ServicePerformanceCostAnalyticsStack",
    description="Service Performance Cost Analytics with VPC Lattice and CloudWatch Insights",
    env=cdk.Environment(
        account=os.environ.get('CDK_DEFAULT_ACCOUNT'),
        region=os.environ.get('CDK_DEFAULT_REGION', 'us-east-1')
    )
)

app.synth()