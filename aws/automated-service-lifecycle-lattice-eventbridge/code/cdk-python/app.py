#!/usr/bin/env python3
"""
AWS CDK Application for Automated Service Lifecycle with VPC Lattice and EventBridge

This CDK application deploys an automated service lifecycle management system that uses:
- VPC Lattice for service networking and discovery
- EventBridge for event-driven automation
- Lambda functions for health monitoring and auto-scaling
- CloudWatch for metrics and logging
- IAM roles and policies for secure access

The solution provides:
- Automated service health monitoring
- Event-driven scaling decisions
- Centralized monitoring dashboard
- Comprehensive logging and observability
"""

import os
from typing import Dict, Any, Optional

import aws_cdk as cdk
from aws_cdk import (
    App,
    CfnOutput,
    Duration,
    RemovalPolicy,
    Stack,
    StackProps
)
from aws_cdk import aws_iam as iam
from aws_cdk import aws_lambda as _lambda
from aws_cdk import aws_events as events
from aws_cdk import aws_events_targets as targets
from aws_cdk import aws_logs as logs
from aws_cdk import aws_cloudwatch as cloudwatch
from aws_cdk import aws_vpclattice as vpclattice

from constructs import Construct


class ServiceLifecycleStack(Stack):
    """
    CDK Stack for Automated Service Lifecycle Management
    
    This stack creates infrastructure for automated lifecycle management of microservices
    using VPC Lattice for networking, EventBridge for event routing, and Lambda for
    orchestration and automation.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Configuration parameters
        self.service_network_name = self.get_parameter("ServiceNetworkName", "microservices-network")
        self.event_bus_name = self.get_parameter("EventBusName", "service-lifecycle-bus")
        
        # Create CloudWatch Log Group for VPC Lattice access logs
        self.access_log_group = self._create_access_log_group()
        
        # Create VPC Lattice Service Network
        self.service_network = self._create_service_network()
        
        # Create custom EventBridge bus
        self.event_bus = self._create_event_bus()
        
        # Create IAM role for Lambda functions
        self.lambda_role = self._create_lambda_role()
        
        # Create Lambda functions
        self.health_monitor_function = self._create_health_monitor_function()
        self.auto_scaler_function = self._create_auto_scaler_function()
        
        # Create EventBridge rules
        self._create_eventbridge_rules()
        
        # Create scheduled health checks
        self._create_scheduled_health_checks()
        
        # Create CloudWatch Dashboard
        self._create_monitoring_dashboard()
        
        # Create outputs
        self._create_outputs()

    def get_parameter(self, name: str, default: str) -> str:
        """Get parameter from context or use default value"""
        return self.node.try_get_context(name) or default

    def _create_access_log_group(self) -> logs.LogGroup:
        """Create CloudWatch Log Group for VPC Lattice access logs"""
        log_group = logs.LogGroup(
            self, "ServiceLifecycleLogGroup",
            log_group_name=f"/aws/vpclattice/service-lifecycle",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        return log_group

    def _create_service_network(self) -> vpclattice.CfnServiceNetwork:
        """Create VPC Lattice Service Network with access logging"""
        # Create the service network
        service_network = vpclattice.CfnServiceNetwork(
            self, "ServiceNetwork",
            name=self.service_network_name,
            auth_type="AWS_IAM"
        )
        
        # Create access log subscription
        vpclattice.CfnAccessLogSubscription(
            self, "ServiceNetworkAccessLogs",
            destination_arn=self.access_log_group.log_group_arn,
            resource_identifier=service_network.attr_id
        )
        
        return service_network

    def _create_event_bus(self) -> events.EventBus:
        """Create custom EventBridge bus for service lifecycle events"""
        event_bus = events.EventBus(
            self, "ServiceLifecycleEventBus",
            event_bus_name=self.event_bus_name
        )
        
        return event_bus

    def _create_lambda_role(self) -> iam.Role:
        """Create IAM role for Lambda functions with necessary permissions"""
        lambda_role = iam.Role(
            self, "ServiceLifecycleLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="IAM role for service lifecycle management Lambda functions",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole"),
            ]
        )
        
        # Add custom policies for VPC Lattice, EventBridge, and CloudWatch
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "vpc-lattice:*",
                    "events:PutEvents",
                    "cloudwatch:GetMetricStatistics",
                    "cloudwatch:PutMetricData",
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                    "ecs:DescribeServices",
                    "ecs:UpdateService",
                    "autoscaling:DescribeAutoScalingGroups",
                    "autoscaling:SetDesiredCapacity"
                ],
                resources=["*"]
            )
        )
        
        return lambda_role

    def _create_health_monitor_function(self) -> _lambda.Function:
        """Create Lambda function for monitoring service health"""
        
        # Lambda function code for health monitoring
        health_monitor_code = '''
import json
import boto3
import os
from datetime import datetime, timedelta
from typing import Dict, Any, List

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda function to monitor VPC Lattice service health and publish events
    
    This function:
    1. Lists all services in the VPC Lattice service network
    2. Retrieves CloudWatch metrics for each service
    3. Evaluates service health based on request count
    4. Publishes health events to EventBridge for automation
    """
    lattice = boto3.client('vpc-lattice')
    cloudwatch = boto3.client('cloudwatch')
    eventbridge = boto3.client('events')
    
    service_network_id = os.environ['SERVICE_NETWORK_ID']
    event_bus_name = os.environ['EVENT_BUS_NAME']
    
    try:
        # Get service network services
        services_response = lattice.list_services(
            serviceNetworkIdentifier=service_network_id
        )
        
        processed_services = 0
        
        for service in services_response.get('items', []):
            service_id = service['id']
            service_name = service['name']
            
            # Get CloudWatch metrics for service health
            end_time = datetime.utcnow()
            start_time = end_time - timedelta(minutes=5)
            
            try:
                metrics_response = cloudwatch.get_metric_statistics(
                    Namespace='AWS/VpcLattice',
                    MetricName='RequestCount',
                    Dimensions=[
                        {'Name': 'ServiceId', 'Value': service_id}
                    ],
                    StartTime=start_time,
                    EndTime=end_time,
                    Period=300,
                    Statistics=['Sum']
                )
                
                # Calculate request count and determine health status
                request_count = sum([point['Sum'] for point in metrics_response['Datapoints']])
                health_status = 'healthy' if request_count > 0 else 'unhealthy'
                
                # Publish service health event to EventBridge
                event_detail = {
                    'serviceId': service_id,
                    'serviceName': service_name,
                    'healthStatus': health_status,
                    'requestCount': request_count,
                    'timestamp': datetime.utcnow().isoformat(),
                    'evaluationPeriod': 5
                }
                
                eventbridge.put_events(
                    Entries=[
                        {
                            'Source': 'vpc-lattice.health-monitor',
                            'DetailType': 'Service Health Check',
                            'Detail': json.dumps(event_detail),
                            'EventBusName': event_bus_name
                        }
                    ]
                )
                
                processed_services += 1
                print(f"Processed service {service_name}: {health_status} (requests: {request_count})")
                
            except Exception as e:
                print(f"Error processing service {service_name}: {str(e)}")
                continue
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Health check completed',
                'processedServices': processed_services
            })
        }
        
    except Exception as e:
        print(f"Error in health monitoring: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Health check failed'
            })
        }
        '''
        
        health_monitor_function = _lambda.Function(
            self, "ServiceHealthMonitorFunction",
            runtime=_lambda.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(health_monitor_code),
            role=self.lambda_role,
            timeout=Duration.minutes(1),
            memory_size=256,
            environment={
                "SERVICE_NETWORK_ID": self.service_network.attr_id,
                "EVENT_BUS_NAME": self.event_bus.event_bus_name
            },
            description="Monitors VPC Lattice service health and publishes lifecycle events"
        )
        
        return health_monitor_function

    def _create_auto_scaler_function(self) -> _lambda.Function:
        """Create Lambda function for auto-scaling based on health events"""
        
        # Lambda function code for auto-scaling
        auto_scaler_code = '''
import json
import boto3
import os
from typing import Dict, Any

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda function to handle auto-scaling based on service health events
    
    This function:
    1. Processes EventBridge events containing service health information
    2. Evaluates scaling requirements based on health status and metrics
    3. Triggers appropriate scaling actions for target groups
    4. Logs scaling decisions for monitoring and debugging
    """
    lattice = boto3.client('vpc-lattice')
    
    try:
        # Parse EventBridge event
        detail = event.get('detail', {})
        if isinstance(detail, str):
            detail = json.loads(detail)
            
        service_id = detail.get('serviceId')
        service_name = detail.get('serviceName')
        health_status = detail.get('healthStatus')
        request_count = detail.get('requestCount', 0)
        
        if not all([service_id, service_name, health_status]):
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Missing required event details'})
            }
        
        print(f"Processing scaling event for service: {service_name}")
        print(f"Health status: {health_status}, Request count: {request_count}")
        
        # Get target groups for the service
        try:
            target_groups_response = lattice.list_target_groups(
                serviceIdentifier=service_id
            )
        except Exception as e:
            print(f"Error listing target groups for service {service_id}: {str(e)}")
            target_groups_response = {'items': []}
        
        scaling_actions = []
        
        for tg in target_groups_response.get('items', []):
            tg_id = tg['id']
            tg_name = tg.get('name', tg_id)
            
            try:
                # Get current target count
                targets_response = lattice.list_targets(
                    targetGroupIdentifier=tg_id
                )
                current_count = len(targets_response.get('items', []))
                
                # Determine scaling action based on health and current capacity
                scaling_decision = None
                
                if health_status == 'unhealthy' and current_count < 5:
                    scaling_decision = {
                        'action': 'scale_up',
                        'reason': 'Service unhealthy and below max capacity',
                        'currentCount': current_count,
                        'recommendedCount': min(current_count + 1, 5)
                    }
                    print(f"Recommending scale-up for target group: {tg_name}")
                    
                elif health_status == 'healthy' and request_count < 10 and current_count > 1:
                    scaling_decision = {
                        'action': 'scale_down',
                        'reason': 'Service healthy with low traffic',
                        'currentCount': current_count,
                        'recommendedCount': max(current_count - 1, 1)
                    }
                    print(f"Recommending scale-down for target group: {tg_name}")
                    
                else:
                    scaling_decision = {
                        'action': 'no_change',
                        'reason': 'No scaling required',
                        'currentCount': current_count
                    }
                    print(f"No scaling action needed for target group: {tg_name}")
                
                scaling_actions.append({
                    'targetGroupId': tg_id,
                    'targetGroupName': tg_name,
                    **scaling_decision
                })
                
            except Exception as e:
                print(f"Error processing target group {tg_id}: {str(e)}")
                scaling_actions.append({
                    'targetGroupId': tg_id,
                    'error': str(e)
                })
        
        # In a production environment, you would implement actual scaling logic here
        # For example, updating ECS services or Auto Scaling Groups
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Scaling evaluation completed',
                'serviceName': service_name,
                'healthStatus': health_status,
                'scalingActions': scaling_actions
            })
        }
        
    except Exception as e:
        print(f"Error in auto-scaling: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Auto-scaling evaluation failed'
            })
        }
        '''
        
        auto_scaler_function = _lambda.Function(
            self, "ServiceAutoScalerFunction",
            runtime=_lambda.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(auto_scaler_code),
            role=self.lambda_role,
            timeout=Duration.minutes(1),
            memory_size=256,
            description="Handles auto-scaling decisions based on service health events"
        )
        
        return auto_scaler_function

    def _create_eventbridge_rules(self) -> None:
        """Create EventBridge rules for routing health events to scaling function"""
        
        # Rule for service health monitoring events
        health_monitoring_rule = events.Rule(
            self, "HealthMonitoringRule",
            event_bus=self.event_bus,
            event_pattern=events.EventPattern(
                source=["vpc-lattice.health-monitor"],
                detail_type=["Service Health Check"],
                detail={
                    "healthStatus": ["unhealthy", "healthy"]
                }
            ),
            description="Routes service health events to auto-scaling function"
        )
        
        # Add Lambda target to the rule
        health_monitoring_rule.add_target(
            targets.LambdaFunction(self.auto_scaler_function)
        )

    def _create_scheduled_health_checks(self) -> None:
        """Create scheduled EventBridge rule for regular health checks"""
        
        # Create CloudWatch Events rule for scheduled health checks
        scheduled_rule = events.Rule(
            self, "ScheduledHealthCheckRule",
            schedule=events.Schedule.rate(Duration.minutes(5)),
            description="Triggers health monitoring function every 5 minutes"
        )
        
        # Add Lambda target for scheduled health checks
        scheduled_rule.add_target(
            targets.LambdaFunction(self.health_monitor_function)
        )

    def _create_monitoring_dashboard(self) -> cloudwatch.Dashboard:
        """Create CloudWatch dashboard for service lifecycle monitoring"""
        
        dashboard = cloudwatch.Dashboard(
            self, "ServiceLifecycleDashboard",
            dashboard_name="ServiceLifecycleMonitoring"
        )
        
        # VPC Lattice service metrics widget
        vpc_lattice_metrics = cloudwatch.GraphWidget(
            title="VPC Lattice Service Metrics",
            width=12,
            height=6,
            left=[
                cloudwatch.Metric(
                    namespace="AWS/VpcLattice",
                    metric_name="RequestCount",
                    statistic="Sum",
                    period=Duration.minutes(5)
                ),
                cloudwatch.Metric(
                    namespace="AWS/VpcLattice",
                    metric_name="ResponseTime",
                    statistic="Average",
                    period=Duration.minutes(5)
                ),
                cloudwatch.Metric(
                    namespace="AWS/VpcLattice",
                    metric_name="TargetResponseTime",
                    statistic="Average",
                    period=Duration.minutes(5)
                )
            ]
        )
        
        # Lambda function metrics widget
        lambda_metrics = cloudwatch.GraphWidget(
            title="Lambda Function Metrics",
            width=12,
            height=6,
            left=[
                self.health_monitor_function.metric_invocations(
                    statistic="Sum",
                    period=Duration.minutes(5)
                ),
                self.health_monitor_function.metric_errors(
                    statistic="Sum",
                    period=Duration.minutes(5)
                ),
                self.auto_scaler_function.metric_invocations(
                    statistic="Sum",
                    period=Duration.minutes(5)
                ),
                self.auto_scaler_function.metric_errors(
                    statistic="Sum",
                    period=Duration.minutes(5)
                )
            ]
        )
        
        # Health monitor logs widget
        health_monitor_logs = cloudwatch.LogQueryWidget(
            title="Health Monitor Logs",
            width=12,
            height=6,
            log_groups=[self.health_monitor_function.log_group],
            query_lines=[
                "fields @timestamp, @message",
                "sort @timestamp desc",
                "limit 20"
            ]
        )
        
        # Add widgets to dashboard
        dashboard.add_widgets(vpc_lattice_metrics)
        dashboard.add_widgets(lambda_metrics)
        dashboard.add_widgets(health_monitor_logs)
        
        return dashboard

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources"""
        
        CfnOutput(
            self, "ServiceNetworkId",
            value=self.service_network.attr_id,
            description="VPC Lattice Service Network ID",
            export_name=f"{self.stack_name}-ServiceNetworkId"
        )
        
        CfnOutput(
            self, "ServiceNetworkArn",
            value=self.service_network.attr_arn,
            description="VPC Lattice Service Network ARN",
            export_name=f"{self.stack_name}-ServiceNetworkArn"
        )
        
        CfnOutput(
            self, "EventBusName",
            value=self.event_bus.event_bus_name,
            description="EventBridge Custom Bus Name",
            export_name=f"{self.stack_name}-EventBusName"
        )
        
        CfnOutput(
            self, "EventBusArn",
            value=self.event_bus.event_bus_arn,
            description="EventBridge Custom Bus ARN",
            export_name=f"{self.stack_name}-EventBusArn"
        )
        
        CfnOutput(
            self, "HealthMonitorFunctionName",
            value=self.health_monitor_function.function_name,
            description="Health Monitor Lambda Function Name",
            export_name=f"{self.stack_name}-HealthMonitorFunctionName"
        )
        
        CfnOutput(
            self, "AutoScalerFunctionName",
            value=self.auto_scaler_function.function_name,
            description="Auto Scaler Lambda Function Name",
            export_name=f"{self.stack_name}-AutoScalerFunctionName"
        )
        
        CfnOutput(
            self, "AccessLogGroupName",
            value=self.access_log_group.log_group_name,
            description="CloudWatch Log Group for VPC Lattice Access Logs",
            export_name=f"{self.stack_name}-AccessLogGroupName"
        )


def main() -> None:
    """Main application entry point"""
    app = App()
    
    # Create the service lifecycle stack
    ServiceLifecycleStack(
        app,
        "ServiceLifecycleStack",
        description="Automated Service Lifecycle Management with VPC Lattice and EventBridge",
        env=cdk.Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION")
        )
    )
    
    app.synth()


if __name__ == "__main__":
    main()