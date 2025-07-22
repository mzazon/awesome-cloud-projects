#!/usr/bin/env python3
"""
CDK Python Application for Container Health Checks and Self-Healing Applications

This application deploys a comprehensive health check and self-healing solution using:
- ECS Fargate service with health checks
- Application Load Balancer with target group health checks
- CloudWatch alarms for monitoring
- Lambda function for advanced self-healing actions
- Auto-scaling policies for dynamic capacity management

Author: AWS CDK Recipe Generator
Version: 1.0
"""

import os
import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    CfnOutput,
    aws_ec2 as ec2,
    aws_ecs as ecs,
    aws_elasticloadbalancingv2 as elbv2,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_sns as sns,
    aws_applicationautoscaling as autoscaling,
    aws_secretsmanager as secretsmanager,
)
from constructs import Construct


class ContainerHealthCheckStack(Stack):
    """
    Main stack for deploying container health checks and self-healing applications.
    
    This stack creates a complete solution with:
    - VPC with public subnets across multiple AZs
    - ECS Fargate cluster with health check configuration
    - Application Load Balancer with target group health checks
    - CloudWatch monitoring and alarms
    - Lambda-based self-healing automation
    - Auto-scaling policies for dynamic capacity management
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)
        
        # Generate random suffix for unique resource names
        self.random_suffix = self._generate_random_suffix()
        
        # Create VPC and networking components
        self.vpc = self._create_vpc()
        
        # Create security groups
        self.alb_security_group = self._create_alb_security_group()
        self.ecs_security_group = self._create_ecs_security_group()
        
        # Create ECS cluster and related resources
        self.ecs_cluster = self._create_ecs_cluster()
        self.task_definition = self._create_task_definition()
        
        # Create Application Load Balancer and target group
        self.alb, self.target_group = self._create_load_balancer()
        
        # Create ECS service with health check configuration
        self.ecs_service = self._create_ecs_service()
        
        # Create CloudWatch alarms for monitoring
        self._create_cloudwatch_alarms()
        
        # Create Lambda function for self-healing
        self.lambda_function = self._create_self_healing_lambda()
        
        # Create auto-scaling policies
        self._create_auto_scaling()
        
        # Create outputs
        self._create_outputs()

    def _generate_random_suffix(self) -> str:
        """Generate a random suffix for unique resource names."""
        import random
        import string
        return ''.join(random.choices(string.ascii_lowercase + string.digits, k=6))

    def _create_vpc(self) -> ec2.Vpc:
        """Create VPC with public subnets across multiple availability zones."""
        vpc = ec2.Vpc(
            self, "HealthCheckVPC",
            vpc_name=f"health-check-vpc-{self.random_suffix}",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=2,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="PublicSubnet",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24,
                )
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True,
        )
        
        # Add tags for better resource management
        cdk.Tags.of(vpc).add("Name", f"health-check-vpc-{self.random_suffix}")
        cdk.Tags.of(vpc).add("Purpose", "Container Health Check Demo")
        
        return vpc

    def _create_alb_security_group(self) -> ec2.SecurityGroup:
        """Create security group for Application Load Balancer."""
        security_group = ec2.SecurityGroup(
            self, "ALBSecurityGroup",
            vpc=self.vpc,
            description="Security group for Application Load Balancer",
            security_group_name=f"health-check-alb-sg-{self.random_suffix}",
            allow_all_outbound=True,
        )
        
        # Allow HTTP traffic from internet
        security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(80),
            description="Allow HTTP traffic from internet",
        )
        
        # Allow HTTPS traffic from internet
        security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(443),
            description="Allow HTTPS traffic from internet",
        )
        
        return security_group

    def _create_ecs_security_group(self) -> ec2.SecurityGroup:
        """Create security group for ECS tasks."""
        security_group = ec2.SecurityGroup(
            self, "ECSSecurityGroup",
            vpc=self.vpc,
            description="Security group for ECS tasks",
            security_group_name=f"health-check-ecs-sg-{self.random_suffix}",
            allow_all_outbound=True,
        )
        
        # Allow HTTP traffic from ALB security group
        security_group.add_ingress_rule(
            peer=ec2.Peer.security_group_id(self.alb_security_group.security_group_id),
            connection=ec2.Port.tcp(80),
            description="Allow HTTP traffic from ALB",
        )
        
        return security_group

    def _create_ecs_cluster(self) -> ecs.Cluster:
        """Create ECS cluster with Fargate capacity."""
        cluster = ecs.Cluster(
            self, "HealthCheckCluster",
            cluster_name=f"health-check-cluster-{self.random_suffix}",
            vpc=self.vpc,
            enable_fargate_capacity_providers=True,
            container_insights=True,
        )
        
        # Add tags for better resource management
        cdk.Tags.of(cluster).add("Name", f"health-check-cluster-{self.random_suffix}")
        cdk.Tags.of(cluster).add("Purpose", "Container Health Check Demo")
        
        return cluster

    def _create_task_definition(self) -> ecs.FargateTaskDefinition:
        """Create ECS task definition with health check configuration."""
        # Create task execution role
        task_execution_role = iam.Role(
            self, "TaskExecutionRole",
            role_name=f"ecsTaskExecutionRole-{self.random_suffix}",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonECSTaskExecutionRolePolicy"
                ),
            ],
        )
        
        # Create task definition
        task_definition = ecs.FargateTaskDefinition(
            self, "TaskDefinition",
            family="health-check-app",
            cpu=256,
            memory_limit_mib=512,
            execution_role=task_execution_role,
        )
        
        # Create log group for container logs
        log_group = logs.LogGroup(
            self, "TaskLogGroup",
            log_group_name=f"/ecs/health-check-app-{self.random_suffix}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=cdk.RemovalPolicy.DESTROY,
        )
        
        # Add container with health check configuration
        container = task_definition.add_container(
            "health-check-container",
            image=ecs.ContainerImage.from_registry("nginx:latest"),
            port_mappings=[
                ecs.PortMapping(
                    container_port=80,
                    protocol=ecs.Protocol.TCP,
                ),
            ],
            logging=ecs.LogDrivers.aws_logs(
                log_group=log_group,
                stream_prefix="ecs",
            ),
            environment={
                "NGINX_PORT": "80",
            },
            # Configure container health check
            health_check=ecs.HealthCheck(
                command=[
                    "CMD-SHELL",
                    "curl -f http://localhost/health || exit 1",
                ],
                interval=Duration.seconds(30),
                timeout=Duration.seconds(5),
                retries=3,
                start_period=Duration.seconds(60),
            ),
        )
        
        # Override default command to configure nginx with health endpoint
        container.add_property_override(
            "command",
            [
                "sh",
                "-c",
                "echo 'server { listen 80; location / { return 200 \"Healthy\"; } location /health { return 200 \"OK\"; } }' > /etc/nginx/conf.d/default.conf && nginx -g 'daemon off;'"
            ],
        )
        
        return task_definition

    def _create_load_balancer(self) -> tuple[elbv2.ApplicationLoadBalancer, elbv2.ApplicationTargetGroup]:
        """Create Application Load Balancer with target group health checks."""
        # Create Application Load Balancer
        alb = elbv2.ApplicationLoadBalancer(
            self, "ApplicationLoadBalancer",
            load_balancer_name=f"health-check-alb-{self.random_suffix}",
            vpc=self.vpc,
            internet_facing=True,
            security_group=self.alb_security_group,
        )
        
        # Create target group with health check configuration
        target_group = elbv2.ApplicationTargetGroup(
            self, "TargetGroup",
            target_group_name=f"health-check-tg-{self.random_suffix}",
            port=80,
            protocol=elbv2.ApplicationProtocol.HTTP,
            target_type=elbv2.TargetType.IP,
            vpc=self.vpc,
            # Configure health check settings
            health_check=elbv2.HealthCheck(
                enabled=True,
                healthy_http_codes="200",
                healthy_threshold_count=2,
                interval=Duration.seconds(30),
                path="/health",
                port="traffic-port",
                protocol=elbv2.Protocol.HTTP,
                timeout=Duration.seconds(5),
                unhealthy_threshold_count=3,
            ),
        )
        
        # Create ALB listener
        alb.add_listener(
            "ALBListener",
            port=80,
            protocol=elbv2.ApplicationProtocol.HTTP,
            default_action=elbv2.ListenerAction.forward([target_group]),
        )
        
        return alb, target_group

    def _create_ecs_service(self) -> ecs.FargateService:
        """Create ECS service with load balancer integration."""
        service = ecs.FargateService(
            self, "ECSService",
            service_name=f"health-check-service-{self.random_suffix}",
            cluster=self.ecs_cluster,
            task_definition=self.task_definition,
            desired_count=2,
            assign_public_ip=True,
            security_groups=[self.ecs_security_group],
            health_check_grace_period=Duration.seconds(300),
            # Enable service discovery for better observability
            cloud_map_options=ecs.CloudMapOptions(
                cloud_map_namespace=ecs.CloudMapNamespace.from_namespace_attributes(
                    self, "Namespace",
                    namespace_id="",
                    namespace_arn="",
                    namespace_name="local",
                ),
            ) if False else None,  # Disabled for simplicity
        )
        
        # Attach service to target group
        service.attach_to_application_target_group(self.target_group)
        
        return service

    def _create_cloudwatch_alarms(self) -> None:
        """Create CloudWatch alarms for health monitoring."""
        # Alarm for unhealthy targets
        cloudwatch.Alarm(
            self, "UnhealthyTargetsAlarm",
            alarm_name=f"UnhealthyTargets-{self.random_suffix}",
            alarm_description="Alert when targets are unhealthy",
            metric=cloudwatch.Metric(
                namespace="AWS/ApplicationELB",
                metric_name="UnHealthyHostCount",
                dimensions_map={
                    "TargetGroup": self.target_group.target_group_full_name,
                    "LoadBalancer": self.alb.load_balancer_full_name,
                },
                statistic="Average",
                period=Duration.seconds(60),
            ),
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )
        
        # Alarm for high response time
        cloudwatch.Alarm(
            self, "HighResponseTimeAlarm",
            alarm_name=f"HighResponseTime-{self.random_suffix}",
            alarm_description="Alert when response time is high",
            metric=cloudwatch.Metric(
                namespace="AWS/ApplicationELB",
                metric_name="TargetResponseTime",
                dimensions_map={
                    "TargetGroup": self.target_group.target_group_full_name,
                    "LoadBalancer": self.alb.load_balancer_full_name,
                },
                statistic="Average",
                period=Duration.seconds(300),
            ),
            threshold=1.0,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )
        
        # Alarm for ECS service running tasks
        cloudwatch.Alarm(
            self, "ECSServiceRunningTasksAlarm",
            alarm_name=f"ECSServiceRunningTasks-{self.random_suffix}",
            alarm_description="Alert when ECS service running tasks are low",
            metric=cloudwatch.Metric(
                namespace="AWS/ECS",
                metric_name="RunningTaskCount",
                dimensions_map={
                    "ServiceName": self.ecs_service.service_name,
                    "ClusterName": self.ecs_cluster.cluster_name,
                },
                statistic="Average",
                period=Duration.seconds(300),
            ),
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.BREACHING,
        )

    def _create_self_healing_lambda(self) -> lambda_.Function:
        """Create Lambda function for advanced self-healing capabilities."""
        # Create Lambda execution role
        lambda_role = iam.Role(
            self, "LambdaExecutionRole",
            role_name=f"health-check-lambda-role-{self.random_suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
            ],
        )
        
        # Add ECS permissions to Lambda role
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "ecs:UpdateService",
                    "ecs:DescribeServices",
                    "ecs:ListTasks",
                    "ecs:StopTask",
                    "ecs:DescribeTasks",
                ],
                resources=["*"],
            )
        )
        
        # Add CloudWatch permissions to Lambda role
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "cloudwatch:GetMetricStatistics",
                    "cloudwatch:PutMetricData",
                ],
                resources=["*"],
            )
        )
        
        # Create Lambda function
        lambda_function = lambda_.Function(
            self, "SelfHealingLambda",
            function_name=f"self-healing-function-{self.random_suffix}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            role=lambda_role,
            timeout=Duration.seconds(60),
            environment={
                "CLUSTER_NAME": self.ecs_cluster.cluster_name,
                "SERVICE_NAME": self.ecs_service.service_name,
            },
            code=lambda_.Code.from_inline('''
import json
import boto3
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ecs = boto3.client('ecs')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    try:
        # Parse CloudWatch alarm from SNS message
        if 'Records' in event:
            message = json.loads(event['Records'][0]['Sns']['Message'])
            alarm_name = message['AlarmName']
        else:
            # Direct invocation for testing
            alarm_name = event.get('AlarmName', 'test-alarm')
        
        logger.info(f"Processing alarm: {alarm_name}")
        
        cluster_name = os.environ.get('CLUSTER_NAME')
        service_name = os.environ.get('SERVICE_NAME')
        
        if 'ECSServiceRunningTasks' in alarm_name:
            # Handle ECS service health issues
            logger.info(f"Handling ECS service health issue for {service_name}")
            
            # Force new deployment to restart unhealthy tasks
            response = ecs.update_service(
                cluster=cluster_name,
                service=service_name,
                forceNewDeployment=True
            )
            
            logger.info(f"Forced new deployment for service {service_name}")
            
        elif 'UnhealthyTargets' in alarm_name:
            # Handle load balancer health issues
            logger.info("Unhealthy targets detected, ECS will handle automatically")
            
        elif 'HighResponseTime' in alarm_name:
            # Handle high response time issues
            logger.info("High response time detected, consider scaling up")
            
        # Put custom metric for self-healing actions
        cloudwatch.put_metric_data(
            Namespace='SelfHealing',
            MetricData=[
                {
                    'MetricName': 'HealingActionsTriggered',
                    'Value': 1,
                    'Unit': 'Count'
                },
            ]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps('Self-healing action completed successfully')
        }
        
    except Exception as e:
        logger.error(f"Error in self-healing: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }
            '''),
        )
        
        return lambda_function

    def _create_auto_scaling(self) -> None:
        """Create auto-scaling policies for ECS service."""
        # Create scalable target
        scalable_target = autoscaling.ScalableTarget(
            self, "ScalableTarget",
            service_namespace=autoscaling.ServiceNamespace.ECS,
            resource_id=f"service/{self.ecs_cluster.cluster_name}/{self.ecs_service.service_name}",
            scalable_dimension="ecs:service:DesiredCount",
            min_capacity=1,
            max_capacity=10,
        )
        
        # Create target tracking scaling policy based on CPU utilization
        scalable_target.scale_on_cpu_utilization(
            "CPUScaling",
            target_utilization_percent=70,
            scale_in_cooldown=Duration.seconds(300),
            scale_out_cooldown=Duration.seconds(300),
        )
        
        # Create target tracking scaling policy based on memory utilization
        scalable_target.scale_on_memory_utilization(
            "MemoryScaling",
            target_utilization_percent=80,
            scale_in_cooldown=Duration.seconds(300),
            scale_out_cooldown=Duration.seconds(300),
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        CfnOutput(
            self, "VPCId",
            value=self.vpc.vpc_id,
            description="VPC ID for the health check infrastructure",
        )
        
        CfnOutput(
            self, "ECSClusterName",
            value=self.ecs_cluster.cluster_name,
            description="ECS Cluster name",
        )
        
        CfnOutput(
            self, "ECSServiceName",
            value=self.ecs_service.service_name,
            description="ECS Service name",
        )
        
        CfnOutput(
            self, "ApplicationLoadBalancerDNS",
            value=self.alb.load_balancer_dns_name,
            description="Application Load Balancer DNS name",
        )
        
        CfnOutput(
            self, "TargetGroupArn",
            value=self.target_group.target_group_arn,
            description="Target Group ARN",
        )
        
        CfnOutput(
            self, "LambdaFunctionArn",
            value=self.lambda_function.function_arn,
            description="Self-healing Lambda function ARN",
        )
        
        CfnOutput(
            self, "HealthCheckEndpoint",
            value=f"http://{self.alb.load_balancer_dns_name}/health",
            description="Health check endpoint URL",
        )
        
        CfnOutput(
            self, "ApplicationEndpoint",
            value=f"http://{self.alb.load_balancer_dns_name}/",
            description="Application endpoint URL",
        )


def main() -> None:
    """Main function to create and deploy the CDK application."""
    app = cdk.App()
    
    # Get environment configuration
    env = cdk.Environment(
        account=os.getenv('CDK_DEFAULT_ACCOUNT'),
        region=os.getenv('CDK_DEFAULT_REGION', 'us-east-1')
    )
    
    # Create the main stack
    ContainerHealthCheckStack(
        app, "ContainerHealthCheckStack",
        env=env,
        description="Container Health Checks and Self-Healing Applications Infrastructure",
    )
    
    app.synth()


if __name__ == "__main__":
    main()