#!/usr/bin/env python3
"""
Advanced Blue-Green Deployments with ECS, Lambda, and CodeDeploy

This CDK application creates a sophisticated blue-green deployment infrastructure
that supports both containerized (ECS) and serverless (Lambda) workloads with
automated rollback capabilities, comprehensive monitoring, and deployment hooks.

The infrastructure includes:
- VPC with public and private subnets
- Application Load Balancer with blue/green target groups
- ECS Fargate cluster and service
- Lambda functions with versioning and aliases
- CodeDeploy applications for both ECS and Lambda
- CloudWatch monitoring and alarms
- SNS notifications
- IAM roles with least privilege access
- ECR repository for container images
- Deployment automation hooks
"""

import os
from aws_cdk import (
    App,
    Stack,
    Environment,
    Tags,
    CfnOutput,
    Duration,
    RemovalPolicy,
    aws_ec2 as ec2,
    aws_ecs as ecs,
    aws_elasticloadbalancingv2 as elbv2,
    aws_lambda as lambda_,
    aws_codedeploy as codedeploy,
    aws_iam as iam,
    aws_ecr as ecr,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
    aws_sns as sns,
    aws_applicationautoscaling as appscaling,
)
from constructs import Construct


class AdvancedBlueGreenDeploymentStack(Stack):
    """
    Advanced Blue-Green Deployment Stack
    
    Creates a comprehensive blue-green deployment infrastructure supporting
    both ECS and Lambda with automated rollback and monitoring capabilities.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack parameters
        self.project_name = self.node.try_get_context("project_name") or "advanced-deployment"
        self.environment_name = self.node.try_get_context("environment") or "production"
        
        # Create core infrastructure
        self._create_vpc_infrastructure()
        self._create_security_groups()
        self._create_iam_roles()
        self._create_ecr_repository()
        self._create_application_load_balancer()
        self._create_ecs_infrastructure()
        self._create_lambda_infrastructure()
        self._create_codedeploy_applications()
        self._create_monitoring_and_alarms()
        self._create_deployment_hooks()
        
        # Add stack-level tags
        Tags.of(self).add("Project", self.project_name)
        Tags.of(self).add("Environment", self.environment_name)
        Tags.of(self).add("DeploymentPattern", "BlueGreen")

    def _create_vpc_infrastructure(self) -> None:
        """Create VPC with public and private subnets for multi-AZ deployment."""
        self.vpc = ec2.Vpc(
            self, "VPC",
            vpc_name=f"{self.project_name}-vpc",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=2,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="PublicSubnet",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24,
                ),
                ec2.SubnetConfiguration(
                    name="PrivateSubnet",
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    cidr_mask=24,
                ),
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True,
        )

        # VPC Flow Logs for security monitoring
        vpc_flow_logs_role = iam.Role(
            self, "VPCFlowLogsRole",
            assumed_by=iam.ServicePrincipal("vpc-flow-logs.amazonaws.com"),
            inline_policies={
                "FlowLogsPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "logs:CreateLogGroup",
                                "logs:CreateLogStream",
                                "logs:PutLogEvents",
                                "logs:DescribeLogGroups",
                                "logs:DescribeLogStreams",
                            ],
                            resources=["*"],
                        )
                    ]
                )
            },
        )

        vpc_flow_logs = ec2.FlowLog(
            self, "VPCFlowLogs",
            resource_type=ec2.FlowLogResourceType.from_vpc(self.vpc),
            destination=ec2.FlowLogDestination.to_cloud_watch_logs(
                logs.LogGroup(
                    self, "VPCFlowLogsGroup",
                    log_group_name=f"/aws/vpc/flowlogs/{self.project_name}",
                    retention=logs.RetentionDays.ONE_WEEK,
                    removal_policy=RemovalPolicy.DESTROY,
                ),
                vpc_flow_logs_role,
            ),
        )

    def _create_security_groups(self) -> None:
        """Create security groups with least privilege access."""
        # ALB Security Group
        self.alb_security_group = ec2.SecurityGroup(
            self, "ALBSecurityGroup",
            vpc=self.vpc,
            description="Security group for Application Load Balancer",
            security_group_name=f"{self.project_name}-alb-sg",
        )
        
        self.alb_security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(80),
            description="Allow HTTP traffic",
        )
        
        self.alb_security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(443),
            description="Allow HTTPS traffic",
        )

        # ECS Security Group
        self.ecs_security_group = ec2.SecurityGroup(
            self, "ECSSecurityGroup",
            vpc=self.vpc,
            description="Security group for ECS tasks",
            security_group_name=f"{self.project_name}-ecs-sg",
        )
        
        self.ecs_security_group.add_ingress_rule(
            peer=ec2.Peer.security_group_id(self.alb_security_group.security_group_id),
            connection=ec2.Port.tcp(8080),
            description="Allow traffic from ALB to ECS tasks",
        )

        # Lambda Security Group
        self.lambda_security_group = ec2.SecurityGroup(
            self, "LambdaSecurityGroup",
            vpc=self.vpc,
            description="Security group for Lambda functions",
            security_group_name=f"{self.project_name}-lambda-sg",
        )

    def _create_iam_roles(self) -> None:
        """Create IAM roles with least privilege permissions."""
        # ECS Task Execution Role
        self.ecs_execution_role = iam.Role(
            self, "ECSExecutionRole",
            role_name=f"{self.project_name}-ecs-execution-role",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonECSTaskExecutionRolePolicy"
                ),
            ],
        )

        # ECS Task Role
        self.ecs_task_role = iam.Role(
            self, "ECSTaskRole",
            role_name=f"{self.project_name}-ecs-task-role",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
            inline_policies={
                "CloudWatchMetrics": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "cloudwatch:PutMetricData",
                                "logs:CreateLogStream",
                                "logs:PutLogEvents",
                            ],
                            resources=["*"],
                        )
                    ]
                )
            },
        )

        # Lambda Execution Role
        self.lambda_execution_role = iam.Role(
            self, "LambdaExecutionRole",
            role_name=f"{self.project_name}-lambda-execution-role",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaVPCAccessExecutionRole"
                ),
            ],
        )

        # CodeDeploy Service Role
        self.codedeploy_role = iam.Role(
            self, "CodeDeployRole",
            role_name=f"{self.project_name}-codedeploy-role",
            assumed_by=iam.ServicePrincipal("codedeploy.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSCodeDeployRoleForECS"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSCodeDeployRoleForLambda"
                ),
            ],
        )

        # Deployment Hooks Lambda Role
        self.hooks_lambda_role = iam.Role(
            self, "HooksLambdaRole",
            role_name=f"{self.project_name}-hooks-lambda-role",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
            ],
            inline_policies={
                "CodeDeployHooks": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "codedeploy:PutLifecycleEventHookExecutionStatus",
                                "lambda:InvokeFunction",
                                "cloudwatch:PutMetricData",
                                "ecs:DescribeServices",
                                "ecs:DescribeTasks",
                            ],
                            resources=["*"],
                        )
                    ]
                )
            },
        )

    def _create_ecr_repository(self) -> None:
        """Create ECR repository for container images."""
        self.ecr_repository = ecr.Repository(
            self, "ECRRepository",
            repository_name=f"{self.project_name}-web-app",
            image_scan_on_push=True,
            lifecycle_rules=[
                ecr.LifecycleRule(
                    description="Keep last 10 images",
                    max_image_count=10,
                    rule_priority=1,
                ),
            ],
            removal_policy=RemovalPolicy.DESTROY,
        )

    def _create_application_load_balancer(self) -> None:
        """Create Application Load Balancer with blue/green target groups."""
        # Application Load Balancer
        self.alb = elbv2.ApplicationLoadBalancer(
            self, "ApplicationLoadBalancer",
            load_balancer_name=f"{self.project_name}-alb",
            vpc=self.vpc,
            internet_facing=True,
            security_group=self.alb_security_group,
        )

        # Blue Target Group
        self.target_group_blue = elbv2.ApplicationTargetGroup(
            self, "TargetGroupBlue",
            target_group_name=f"{self.project_name}-blue-tg",
            port=8080,
            protocol=elbv2.ApplicationProtocol.HTTP,
            vpc=self.vpc,
            target_type=elbv2.TargetType.IP,
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

        # Green Target Group
        self.target_group_green = elbv2.ApplicationTargetGroup(
            self, "TargetGroupGreen",
            target_group_name=f"{self.project_name}-green-tg",
            port=8080,
            protocol=elbv2.ApplicationProtocol.HTTP,
            vpc=self.vpc,
            target_type=elbv2.TargetType.IP,
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

        # ALB Listener
        self.alb_listener = self.alb.add_listener(
            "ALBListener",
            port=80,
            protocol=elbv2.ApplicationProtocol.HTTP,
            default_action=elbv2.ListenerAction.forward(
                target_groups=[self.target_group_blue]
            ),
        )

    def _create_ecs_infrastructure(self) -> None:
        """Create ECS cluster and service for blue-green deployments."""
        # ECS Cluster
        self.ecs_cluster = ecs.Cluster(
            self, "ECSCluster",
            cluster_name=f"{self.project_name}-cluster",
            vpc=self.vpc,
            container_insights=True,
        )

        # CloudWatch Log Group for ECS
        self.ecs_log_group = logs.LogGroup(
            self, "ECSLogGroup",
            log_group_name=f"/ecs/{self.project_name}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # ECS Task Definition
        self.ecs_task_definition = ecs.FargateTaskDefinition(
            self, "ECSTaskDefinition",
            family=f"{self.project_name}-web-app",
            cpu=256,
            memory_limit_mib=512,
            execution_role=self.ecs_execution_role,
            task_role=self.ecs_task_role,
        )

        # Container Definition
        self.container = self.ecs_task_definition.add_container(
            "WebAppContainer",
            container_name="web-app",
            image=ecs.ContainerImage.from_ecr_repository(
                repository=self.ecr_repository,
                tag="1.0.0"
            ),
            port_mappings=[
                ecs.PortMapping(
                    container_port=8080,
                    protocol=ecs.Protocol.TCP,
                )
            ],
            environment={
                "APP_VERSION": "1.0.0",
                "ENVIRONMENT": "blue",
                "PORT": "8080",
            },
            logging=ecs.LogDrivers.aws_logs(
                stream_prefix="ecs",
                log_group=self.ecs_log_group,
            ),
            health_check=ecs.HealthCheck(
                command=[
                    "CMD-SHELL",
                    "curl -f http://localhost:8080/health || exit 1"
                ],
                interval=Duration.seconds(30),
                timeout=Duration.seconds(5),
                retries=3,
                start_period=Duration.seconds(60),
            ),
        )

        # ECS Service
        self.ecs_service = ecs.FargateService(
            self, "ECSService",
            service_name=f"{self.project_name}-service",
            cluster=self.ecs_cluster,
            task_definition=self.ecs_task_definition,
            desired_count=2,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
            ),
            security_groups=[self.ecs_security_group],
            enable_execute_command=True,
            deployment_configuration=ecs.DeploymentConfiguration(
                maximum_percent=200,
                minimum_healthy_percent=50,
            ),
        )

        # Attach service to blue target group
        self.ecs_service.attach_to_application_target_group(self.target_group_blue)

        # Auto Scaling for ECS Service
        scalable_target = self.ecs_service.auto_scale_task_count(
            min_capacity=1,
            max_capacity=10,
        )

        scalable_target.scale_on_cpu_utilization(
            "CPUScaling",
            target_utilization_percent=70,
            scale_in_cooldown=Duration.minutes(5),
            scale_out_cooldown=Duration.minutes(2),
        )

        scalable_target.scale_on_memory_utilization(
            "MemoryScaling",
            target_utilization_percent=80,
            scale_in_cooldown=Duration.minutes(5),
            scale_out_cooldown=Duration.minutes(2),
        )

    def _create_lambda_infrastructure(self) -> None:
        """Create Lambda function with versioning and aliases."""
        # Lambda function code (inline for demo purposes)
        lambda_code = '''
import json
import os
import random
from datetime import datetime

def lambda_handler(event, context):
    version = os.environ.get('VERSION', '1.0.0')
    environment = os.environ.get('ENVIRONMENT', 'blue')
    
    http_method = event.get('httpMethod', 'GET')
    path = event.get('path', '/')
    
    if path == '/health':
        return health_check(version, environment)
    elif path == '/api/lambda-data':
        return get_lambda_data(version, environment)
    elif path == '/':
        return home_response(version, environment)
    else:
        return {
            'statusCode': 404,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'Not found'})
        }

def health_check(version, environment):
    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps({
            'status': 'healthy',
            'version': version,
            'environment': environment,
            'timestamp': datetime.utcnow().isoformat(),
            'requestId': context.aws_request_id if 'context' in globals() else 'unknown'
        })
    }

def get_lambda_data(version, environment):
    data = {
        'version': version,
        'environment': environment,
        'lambda_data': [
            {'id': i, 'type': 'lambda', 'value': random.random()}
            for i in range(1, 4)
        ],
        'timestamp': datetime.utcnow().isoformat(),
        'execution_time_ms': random.randint(50, 200)
    }
    
    if version == '2.0.0':
        data['new_feature'] = 'Enhanced Lambda processing'
        data['lambda_data'].append({
            'id': 4, 'type': 'lambda-enhanced', 'value': random.random()
        })
    
    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps(data)
    }

def home_response(version, environment):
    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps({
            'message': 'Lambda Blue-Green Deployment Demo',
            'version': version,
            'environment': environment,
            'timestamp': datetime.utcnow().isoformat()
        })
    }
        '''

        # Lambda Function
        self.lambda_function = lambda_.Function(
            self, "LambdaFunction",
            function_name=f"{self.project_name}-api-function",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(lambda_code),
            timeout=Duration.seconds(30),
            memory_size=256,
            environment={
                "VERSION": "1.0.0",
                "ENVIRONMENT": "blue",
            },
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
            ),
            security_groups=[self.lambda_security_group],
            role=self.lambda_execution_role,
            tracing=lambda_.Tracing.ACTIVE,
        )

        # Lambda Alias for production traffic
        self.lambda_alias = lambda_.Alias(
            self, "LambdaAlias",
            alias_name="PROD",
            version=self.lambda_function.current_version,
            description="Production alias for blue-green deployments",
        )

    def _create_codedeploy_applications(self) -> None:
        """Create CodeDeploy applications for ECS and Lambda."""
        # CodeDeploy Application for ECS
        self.codedeploy_ecs_app = codedeploy.EcsApplication(
            self, "CodeDeployECSApp",
            application_name=f"{self.project_name}-ecs-app",
        )

        # CodeDeploy Deployment Group for ECS
        self.codedeploy_ecs_deployment_group = codedeploy.EcsDeploymentGroup(
            self, "CodeDeployECSDeploymentGroup",
            application=self.codedeploy_ecs_app,
            deployment_group_name=f"{self.project_name}-ecs-dg",
            service=self.ecs_service,
            blue_green_deployment_config=codedeploy.EcsBlueGreenDeploymentConfig(
                listener=self.alb_listener,
                blue_target_group=self.target_group_blue,
                green_target_group=self.target_group_green,
                deployment_approval_wait_time=Duration.minutes(0),
                termination_wait_time=Duration.minutes(5),
            ),
            deployment_config=codedeploy.EcsDeploymentConfig.LINEAR_10_PERCENT_EVERY_1_MINUTES,
            service_role=self.codedeploy_role,
            auto_rollback=codedeploy.AutoRollbackConfig(
                failed_deployment=True,
                stopped_deployment=True,
                deployment_in_alarm=True,
            ),
        )

        # CodeDeploy Application for Lambda
        self.codedeploy_lambda_app = codedeploy.LambdaApplication(
            self, "CodeDeployLambdaApp",
            application_name=f"{self.project_name}-lambda-app",
        )

        # CodeDeploy Deployment Group for Lambda
        self.codedeploy_lambda_deployment_group = codedeploy.LambdaDeploymentGroup(
            self, "CodeDeployLambdaDeploymentGroup",
            application=self.codedeploy_lambda_app,
            deployment_group_name=f"{self.project_name}-lambda-dg",
            alias=self.lambda_alias,
            deployment_config=codedeploy.LambdaDeploymentConfig.LINEAR_10_PERCENT_EVERY_1_MINUTE,
            service_role=self.codedeploy_role,
            auto_rollback=codedeploy.AutoRollbackConfig(
                failed_deployment=True,
                stopped_deployment=True,
                deployment_in_alarm=True,
            ),
        )

    def _create_monitoring_and_alarms(self) -> None:
        """Create comprehensive monitoring and alarm system."""
        # SNS Topic for notifications
        self.sns_topic = sns.Topic(
            self, "DeploymentNotifications",
            topic_name=f"{self.project_name}-notifications",
            display_name="Blue-Green Deployment Notifications",
        )

        # CloudWatch Alarms for ECS Service
        self.ecs_high_error_alarm = cloudwatch.Alarm(
            self, "ECSHighErrorRate",
            alarm_name=f"{self.project_name}-ecs-high-error-rate",
            alarm_description="High error rate in ECS service",
            metric=cloudwatch.Metric(
                namespace="AWS/ApplicationELB",
                metric_name="HTTPCode_Target_5XX_Count",
                dimensions_map={
                    "LoadBalancer": self.alb.load_balancer_full_name,
                    "TargetGroup": self.target_group_green.target_group_full_name,
                },
                statistic="Sum",
                period=Duration.minutes(1),
            ),
            threshold=10,
            evaluation_periods=3,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        )

        self.ecs_high_latency_alarm = cloudwatch.Alarm(
            self, "ECSHighLatency",
            alarm_name=f"{self.project_name}-ecs-high-latency",
            alarm_description="High response time in ECS service",
            metric=cloudwatch.Metric(
                namespace="AWS/ApplicationELB",
                metric_name="TargetResponseTime",
                dimensions_map={
                    "LoadBalancer": self.alb.load_balancer_full_name,
                    "TargetGroup": self.target_group_green.target_group_full_name,
                },
                statistic="Average",
                period=Duration.minutes(1),
            ),
            threshold=2.0,
            evaluation_periods=5,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        )

        # CloudWatch Alarms for Lambda Function
        self.lambda_error_alarm = cloudwatch.Alarm(
            self, "LambdaHighErrorRate",
            alarm_name=f"{self.project_name}-lambda-high-error-rate",
            alarm_description="High error rate in Lambda function",
            metric=self.lambda_function.metric_errors(
                period=Duration.minutes(1),
                statistic="Sum",
            ),
            threshold=5,
            evaluation_periods=3,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        )

        self.lambda_duration_alarm = cloudwatch.Alarm(
            self, "LambdaHighDuration",
            alarm_name=f"{self.project_name}-lambda-high-duration",
            alarm_description="High duration in Lambda function",
            metric=self.lambda_function.metric_duration(
                period=Duration.minutes(1),
                statistic="Average",
            ),
            threshold=5000,
            evaluation_periods=5,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        )

        # Add alarms to SNS topic
        self.ecs_high_error_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.sns_topic)
        )
        self.ecs_high_latency_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.sns_topic)
        )
        self.lambda_error_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.sns_topic)
        )
        self.lambda_duration_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.sns_topic)
        )

        # Add alarms to CodeDeploy deployment groups for auto-rollback
        self.codedeploy_ecs_deployment_group.add_alarm(self.ecs_high_error_alarm)
        self.codedeploy_ecs_deployment_group.add_alarm(self.ecs_high_latency_alarm)
        self.codedeploy_lambda_deployment_group.add_alarm(self.lambda_error_alarm)
        self.codedeploy_lambda_deployment_group.add_alarm(self.lambda_duration_alarm)

    def _create_deployment_hooks(self) -> None:
        """Create pre and post deployment validation hooks."""
        # Pre-deployment validation hook
        pre_deployment_code = '''
import json
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

codedeploy = boto3.client('codedeploy')

def lambda_handler(event, context):
    try:
        deployment_id = event['DeploymentId']
        lifecycle_event_hook_execution_id = event['LifecycleEventHookExecutionId']
        
        logger.info(f"Running pre-deployment validation for deployment: {deployment_id}")
        
        # Simulate validation checks
        validation_result = validate_deployment_readiness(event)
        
        status = 'Succeeded' if validation_result['success'] else 'Failed'
        
        codedeploy.put_lifecycle_event_hook_execution_status(
            deploymentId=deployment_id,
            lifecycleEventHookExecutionId=lifecycle_event_hook_execution_id,
            status=status
        )
        
        return {'statusCode': 200}
    except Exception as e:
        logger.error(f"Error in pre-deployment hook: {str(e)}")
        return {'statusCode': 500}

def validate_deployment_readiness(event):
    # Implement your validation logic here
    return {'success': True, 'reason': 'All checks passed'}
        '''

        self.pre_deployment_hook = lambda_.Function(
            self, "PreDeploymentHook",
            function_name=f"{self.project_name}-pre-deployment-hook",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(pre_deployment_code),
            timeout=Duration.minutes(5),
            memory_size=256,
            role=self.hooks_lambda_role,
        )

        # Post-deployment validation hook
        post_deployment_code = '''
import json
import boto3
import logging
import time

logger = logging.getLogger()
logger.setLevel(logging.INFO)

codedeploy = boto3.client('codedeploy')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    try:
        deployment_id = event['DeploymentId']
        lifecycle_event_hook_execution_id = event['LifecycleEventHookExecutionId']
        
        logger.info(f"Running post-deployment validation for deployment: {deployment_id}")
        
        # Simulate validation checks
        validation_result = validate_deployment_success(event)
        
        status = 'Succeeded' if validation_result['success'] else 'Failed'
        
        codedeploy.put_lifecycle_event_hook_execution_status(
            deploymentId=deployment_id,
            lifecycleEventHookExecutionId=lifecycle_event_hook_execution_id,
            status=status
        )
        
        # Record metrics
        cloudwatch.put_metric_data(
            Namespace='Deployment/Validation',
            MetricData=[
                {
                    'MetricName': 'PostDeploymentValidation',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {'Name': 'Status', 'Value': 'Success' if validation_result['success'] else 'Failure'}
                    ]
                }
            ]
        )
        
        return {'statusCode': 200}
    except Exception as e:
        logger.error(f"Error in post-deployment hook: {str(e)}")
        return {'statusCode': 500}

def validate_deployment_success(event):
    # Implement your validation logic here
    return {'success': True, 'reason': 'All tests passed'}
        '''

        self.post_deployment_hook = lambda_.Function(
            self, "PostDeploymentHook",
            function_name=f"{self.project_name}-post-deployment-hook",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(post_deployment_code),
            timeout=Duration.minutes(5),
            memory_size=256,
            role=self.hooks_lambda_role,
        )

        # Grant permissions for hooks to interact with CodeDeploy
        self.pre_deployment_hook.add_to_role_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["codedeploy:PutLifecycleEventHookExecutionStatus"],
                resources=["*"],
            )
        )

        self.post_deployment_hook.add_to_role_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "codedeploy:PutLifecycleEventHookExecutionStatus",
                    "cloudwatch:PutMetricData",
                ],
                resources=["*"],
            )
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        # VPC and Networking
        CfnOutput(
            self, "VPCId",
            value=self.vpc.vpc_id,
            description="VPC ID for the blue-green deployment infrastructure",
            export_name=f"{self.project_name}-vpc-id",
        )

        # Load Balancer
        CfnOutput(
            self, "ALBDNSName",
            value=self.alb.load_balancer_dns_name,
            description="DNS name of the Application Load Balancer",
            export_name=f"{self.project_name}-alb-dns",
        )

        # ECR Repository
        CfnOutput(
            self, "ECRRepositoryURI",
            value=self.ecr_repository.repository_uri,
            description="ECR repository URI for container images",
            export_name=f"{self.project_name}-ecr-uri",
        )

        # ECS Resources
        CfnOutput(
            self, "ECSClusterName",
            value=self.ecs_cluster.cluster_name,
            description="Name of the ECS cluster",
            export_name=f"{self.project_name}-ecs-cluster",
        )

        CfnOutput(
            self, "ECSServiceName",
            value=self.ecs_service.service_name,
            description="Name of the ECS service",
            export_name=f"{self.project_name}-ecs-service",
        )

        # Lambda Resources
        CfnOutput(
            self, "LambdaFunctionName",
            value=self.lambda_function.function_name,
            description="Name of the Lambda function",
            export_name=f"{self.project_name}-lambda-function",
        )

        CfnOutput(
            self, "LambdaAliasArn",
            value=self.lambda_alias.alias_arn,
            description="ARN of the Lambda production alias",
            export_name=f"{self.project_name}-lambda-alias-arn",
        )

        # CodeDeploy Applications
        CfnOutput(
            self, "CodeDeployECSAppName",
            value=self.codedeploy_ecs_app.application_name,
            description="Name of the CodeDeploy ECS application",
            export_name=f"{self.project_name}-codedeploy-ecs-app",
        )

        CfnOutput(
            self, "CodeDeployLambdaAppName",
            value=self.codedeploy_lambda_app.application_name,
            description="Name of the CodeDeploy Lambda application",
            export_name=f"{self.project_name}-codedeploy-lambda-app",
        )

        # Monitoring
        CfnOutput(
            self, "SNSTopicArn",
            value=self.sns_topic.topic_arn,
            description="ARN of the SNS topic for deployment notifications",
            export_name=f"{self.project_name}-sns-topic-arn",
        )


def main():
    """Main application entry point."""
    app = App()
    
    # Get environment configuration
    env = Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
        region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
    )
    
    # Create the stack
    stack = AdvancedBlueGreenDeploymentStack(
        app,
        "AdvancedBlueGreenDeploymentStack",
        env=env,
        description="Advanced Blue-Green Deployments with ECS, Lambda, and CodeDeploy",
    )
    
    # Create outputs
    stack._create_outputs()
    
    # Synthesize the app
    app.synth()


if __name__ == "__main__":
    main()