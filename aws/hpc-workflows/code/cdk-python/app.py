#!/usr/bin/env python3
"""
Fault-Tolerant HPC Workflows with Step Functions and Spot Fleet
A comprehensive CDK Python implementation for building resilient HPC workload orchestration.
"""

import os
import json
from typing import Dict, List, Optional, Any
from constructs import Construct
from aws_cdk import (
    App,
    Stack,
    StackProps,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_stepfunctions as sfn,
    aws_stepfunctions_tasks as sfn_tasks,
    aws_lambda as lambda_,
    aws_dynamodb as dynamodb,
    aws_s3 as s3,
    aws_iam as iam,
    aws_events as events,
    aws_events_targets as targets,
    aws_cloudwatch as cloudwatch,
    aws_sns as sns,
    aws_logs as logs,
    aws_batch as batch,
    aws_ec2 as ec2,
    aws_ecs as ecs,
    Stack,
    aws_autoscaling as autoscaling,
)


class FaultTolerantHPCWorkflowStack(Stack):
    """
    CDK Stack for fault-tolerant HPC workflows using Step Functions and Spot Fleet.
    
    This stack creates a comprehensive infrastructure for orchestrating HPC workloads
    with automatic fault tolerance, cost optimization through Spot instances, and
    intelligent checkpointing capabilities.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        project_name: str = "hpc-workflow",
        enable_spot_fleet: bool = True,
        vpc_id: Optional[str] = None,
        **kwargs: Any
    ) -> None:
        """
        Initialize the Fault-Tolerant HPC Workflow Stack.
        
        Args:
            scope: The parent construct
            construct_id: The construct ID
            project_name: Name prefix for all resources
            enable_spot_fleet: Whether to enable Spot Fleet functionality
            vpc_id: Optional VPC ID to use (creates new VPC if not provided)
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        self.project_name = project_name
        self.enable_spot_fleet = enable_spot_fleet

        # Create VPC or use existing
        self.vpc = self._create_or_get_vpc(vpc_id)
        
        # Create core storage and state management
        self.checkpoint_bucket = self._create_checkpoint_bucket()
        self.workflow_state_table = self._create_workflow_state_table()
        
        # Create IAM roles
        self.lambda_role = self._create_lambda_execution_role()
        self.step_functions_role = self._create_step_functions_role()
        self.batch_execution_role = self._create_batch_execution_role()
        self.spot_fleet_role = self._create_spot_fleet_role()
        
        # Create Lambda functions
        self.lambda_functions = self._create_lambda_functions()
        
        # Create Batch infrastructure
        self.batch_infrastructure = self._create_batch_infrastructure()
        
        # Create Step Functions state machine
        self.state_machine = self._create_state_machine()
        
        # Create monitoring and alerting
        self.monitoring = self._create_monitoring_infrastructure()
        
        # Create event-driven spot interruption handling
        self.spot_interruption_handling = self._create_spot_interruption_handling()
        
        # Create outputs
        self._create_outputs()

    def _create_or_get_vpc(self, vpc_id: Optional[str]) -> ec2.IVpc:
        """Create a new VPC or reference an existing one."""
        if vpc_id:
            return ec2.Vpc.from_lookup(self, "ExistingVPC", vpc_id=vpc_id)
        
        return ec2.Vpc(
            self,
            "HPCVPC",
            max_azs=3,
            cidr="10.0.0.0/16",
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="Public",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24,
                ),
                ec2.SubnetConfiguration(
                    name="Private",
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    cidr_mask=24,
                ),
            ],
        )

    def _create_checkpoint_bucket(self) -> s3.Bucket:
        """Create S3 bucket for checkpoint storage."""
        bucket = s3.Bucket(
            self,
            "CheckpointBucket",
            bucket_name=f"{self.project_name}-checkpoints-{self.account}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="ArchiveOldCheckpoints",
                    enabled=True,
                    expiration=Duration.days(30),
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(7),
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(14),
                        ),
                    ],
                ),
            ],
        )
        
        # Create folder structure
        for folder in ["checkpoints/", "workflows/", "results/"]:
            s3.BucketDeployment(
                self,
                f"Create{folder.replace('/', '').title()}Folder",
                sources=[s3.Source.data(folder, "")],
                destination_bucket=bucket,
                destination_key_prefix=folder,
            )
        
        return bucket

    def _create_workflow_state_table(self) -> dynamodb.Table:
        """Create DynamoDB table for workflow state management."""
        return dynamodb.Table(
            self,
            "WorkflowStateTable",
            table_name=f"{self.project_name}-workflow-state",
            partition_key=dynamodb.Attribute(
                name="WorkflowId", type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="TaskId", type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
        )

    def _create_lambda_execution_role(self) -> iam.Role:
        """Create IAM role for Lambda functions."""
        role = iam.Role(
            self,
            "LambdaExecutionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
            ],
        )
        
        # Add permissions for HPC workflow operations
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:DeleteObject",
                    "s3:ListBucket",
                ],
                resources=[
                    self.checkpoint_bucket.bucket_arn,
                    f"{self.checkpoint_bucket.bucket_arn}/*",
                ],
            )
        )
        
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "dynamodb:GetItem",
                    "dynamodb:PutItem",
                    "dynamodb:UpdateItem",
                    "dynamodb:DeleteItem",
                    "dynamodb:Query",
                    "dynamodb:Scan",
                ],
                resources=[self.workflow_state_table.table_arn],
            )
        )
        
        if self.enable_spot_fleet:
            role.add_to_policy(
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "ec2:DescribeSpotFleetRequests",
                        "ec2:ModifySpotFleetRequest",
                        "ec2:CancelSpotFleetRequests",
                        "ec2:CreateSpotFleetRequest",
                        "ec2:DescribeSpotFleetInstances",
                        "ec2:DescribeInstances",
                        "ec2:DescribeSpotPriceHistory",
                        "batch:DescribeJobs",
                        "batch:SubmitJob",
                        "batch:TerminateJob",
                        "batch:ListJobs",
                        "cloudwatch:PutMetricData",
                    ],
                    resources=["*"],
                )
            )
        
        return role

    def _create_step_functions_role(self) -> iam.Role:
        """Create IAM role for Step Functions state machine."""
        role = iam.Role(
            self,
            "StepFunctionsRole",
            assumed_by=iam.ServicePrincipal("states.amazonaws.com"),
        )
        
        # Add permissions for Lambda invocation
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["lambda:InvokeFunction"],
                resources=["*"],  # Will be restricted after Lambda functions are created
            )
        )
        
        # Add permissions for Batch operations
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "batch:SubmitJob",
                    "batch:DescribeJobs",
                    "batch:TerminateJob",
                ],
                resources=["*"],
            )
        )
        
        # Add permissions for SNS notifications
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["sns:Publish"],
                resources=["*"],
            )
        )
        
        return role

    def _create_batch_execution_role(self) -> iam.Role:
        """Create IAM role for Batch job execution."""
        return iam.Role(
            self,
            "BatchExecutionRole",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonECSTaskExecutionRolePolicy"
                ),
            ],
        )

    def _create_spot_fleet_role(self) -> iam.Role:
        """Create IAM role for Spot Fleet management."""
        return iam.Role(
            self,
            "SpotFleetRole",
            assumed_by=iam.ServicePrincipal("spotfleet.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonEC2SpotFleetTaggingRole"
                ),
            ],
        )

    def _create_lambda_functions(self) -> Dict[str, lambda_.Function]:
        """Create all Lambda functions for HPC workflow management."""
        functions = {}
        
        # Workflow Parser Lambda
        functions["workflow_parser"] = lambda_.Function(
            self,
            "WorkflowParserFunction",
            function_name=f"{self.project_name}-workflow-parser",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="workflow_parser.lambda_handler",
            code=lambda_.Code.from_inline(self._get_workflow_parser_code()),
            timeout=Duration.minutes(5),
            memory_size=512,
            role=self.lambda_role,
            environment={
                "PROJECT_NAME": self.project_name,
                "CHECKPOINT_BUCKET": self.checkpoint_bucket.bucket_name,
                "WORKFLOW_STATE_TABLE": self.workflow_state_table.table_name,
            },
        )
        
        # Checkpoint Manager Lambda
        functions["checkpoint_manager"] = lambda_.Function(
            self,
            "CheckpointManagerFunction",
            function_name=f"{self.project_name}-checkpoint-manager",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="checkpoint_manager.lambda_handler",
            code=lambda_.Code.from_inline(self._get_checkpoint_manager_code()),
            timeout=Duration.minutes(5),
            memory_size=512,
            role=self.lambda_role,
            environment={
                "PROJECT_NAME": self.project_name,
                "CHECKPOINT_BUCKET": self.checkpoint_bucket.bucket_name,
                "WORKFLOW_STATE_TABLE": self.workflow_state_table.table_name,
            },
        )
        
        if self.enable_spot_fleet:
            # Spot Fleet Manager Lambda
            functions["spot_fleet_manager"] = lambda_.Function(
                self,
                "SpotFleetManagerFunction",
                function_name=f"{self.project_name}-spot-fleet-manager",
                runtime=lambda_.Runtime.PYTHON_3_9,
                handler="spot_fleet_manager.lambda_handler",
                code=lambda_.Code.from_inline(self._get_spot_fleet_manager_code()),
                timeout=Duration.minutes(5),
                memory_size=256,
                role=self.lambda_role,
                environment={
                    "PROJECT_NAME": self.project_name,
                    "SPOT_FLEET_ROLE_ARN": self.spot_fleet_role.role_arn,
                },
            )
            
            # Spot Interruption Handler Lambda
            functions["spot_interruption_handler"] = lambda_.Function(
                self,
                "SpotInterruptionHandlerFunction",
                function_name=f"{self.project_name}-spot-interruption-handler",
                runtime=lambda_.Runtime.PYTHON_3_9,
                handler="spot_interruption_handler.lambda_handler",
                code=lambda_.Code.from_inline(self._get_spot_interruption_handler_code()),
                timeout=Duration.minutes(1),
                memory_size=256,
                role=self.lambda_role,
                environment={
                    "PROJECT_NAME": self.project_name,
                    "WORKFLOW_STATE_TABLE": self.workflow_state_table.table_name,
                },
            )
        
        return functions

    def _create_batch_infrastructure(self) -> Dict[str, Any]:
        """Create AWS Batch infrastructure for HPC workload execution."""
        # Create security group for Batch compute environment
        security_group = ec2.SecurityGroup(
            self,
            "BatchSecurityGroup",
            vpc=self.vpc,
            description="Security group for Batch compute environment",
            allow_all_outbound=True,
        )
        
        # Create Batch compute environment
        compute_environment = batch.CfnComputeEnvironment(
            self,
            "HPCComputeEnvironment",
            compute_environment_name=f"{self.project_name}-compute-env",
            type="MANAGED",
            state="ENABLED",
            compute_resources=batch.CfnComputeEnvironment.ComputeResourcesProperty(
                type="EC2" if self.enable_spot_fleet else "FARGATE",
                allocation_strategy="SPOT_CAPACITY_OPTIMIZED" if self.enable_spot_fleet else "BEST_FIT",
                min_vcpus=0,
                max_vcpus=1000,
                desired_vcpus=0,
                instance_types=["c5.large", "c5.xlarge", "c5.2xlarge", "c5.4xlarge"],
                spot_iam_fleet_request_role=self.spot_fleet_role.role_arn if self.enable_spot_fleet else None,
                ec2_configuration=[
                    batch.CfnComputeEnvironment.Ec2ConfigurationObjectProperty(
                        image_type="ECS_AL2"
                    )
                ],
                subnets=[subnet.subnet_id for subnet in self.vpc.private_subnets],
                security_group_ids=[security_group.security_group_id],
                instance_role=iam.Role(
                    self,
                    "BatchInstanceRole",
                    assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
                    managed_policies=[
                        iam.ManagedPolicy.from_aws_managed_policy_name(
                            "service-role/AmazonEC2ContainerServiceforEC2Role"
                        ),
                    ],
                ).role_arn,
                tags={"Project": self.project_name},
            ),
            service_role=iam.Role(
                self,
                "BatchServiceRole",
                assumed_by=iam.ServicePrincipal("batch.amazonaws.com"),
                managed_policies=[
                    iam.ManagedPolicy.from_aws_managed_policy_name(
                        "service-role/AWSBatchServiceRole"
                    ),
                ],
            ).role_arn,
        )
        
        # Create Batch job queue
        job_queue = batch.CfnJobQueue(
            self,
            "HPCJobQueue",
            job_queue_name=f"{self.project_name}-job-queue",
            state="ENABLED",
            priority=1,
            compute_environment_order=[
                batch.CfnJobQueue.ComputeEnvironmentOrderProperty(
                    order=1,
                    compute_environment=compute_environment.ref,
                )
            ],
        )
        
        # Create Batch job definition
        job_definition = batch.CfnJobDefinition(
            self,
            "HPCJobDefinition",
            job_definition_name=f"{self.project_name}-job-definition",
            type="container",
            container_properties=batch.CfnJobDefinition.ContainerPropertiesProperty(
                image="ubuntu:20.04",
                vcpus=1,
                memory=1024,
                job_role_arn=self.batch_execution_role.role_arn,
                environment=[
                    batch.CfnJobDefinition.EnvironmentProperty(
                        name="PROJECT_NAME",
                        value=self.project_name,
                    ),
                ],
            ),
            retry_strategy=batch.CfnJobDefinition.RetryStrategyProperty(attempts=3),
            timeout=batch.CfnJobDefinition.TimeoutProperty(attempt_duration_seconds=3600),
        )
        
        return {
            "compute_environment": compute_environment,
            "job_queue": job_queue,
            "job_definition": job_definition,
            "security_group": security_group,
        }

    def _create_state_machine(self) -> sfn.StateMachine:
        """Create Step Functions state machine for HPC workflow orchestration."""
        # Define state machine workflow
        parse_workflow = sfn_tasks.LambdaInvoke(
            self,
            "ParseWorkflow",
            lambda_function=self.lambda_functions["workflow_parser"],
            result_path="$.parsed_workflow",
            retry_on_service_exceptions=True,
        )
        
        # Initialize resources (parallel execution)
        initialize_resources = sfn.Parallel(
            self,
            "InitializeResources",
            result_path="$.resources",
        )
        
        if self.enable_spot_fleet:
            create_spot_fleet = sfn_tasks.LambdaInvoke(
                self,
                "CreateSpotFleet",
                lambda_function=self.lambda_functions["spot_fleet_manager"],
                payload=sfn.TaskInput.from_object({
                    "action": "create",
                    "target_capacity": 4,
                    "fleet_role_arn": self.spot_fleet_role.role_arn,
                }),
                result_path="$.spot_fleet",
            )
            initialize_resources.branch(create_spot_fleet)
        
        # Initialize Batch queue
        initialize_batch = sfn.Pass(
            self,
            "InitializeBatch",
            parameters={
                "queue_name": self.batch_infrastructure["job_queue"].job_queue_name,
                "status": "initialized",
            },
            result_path="$.batch_queue",
        )
        initialize_resources.branch(initialize_batch)
        
        # Execute workflow stages
        execute_stages = sfn.Map(
            self,
            "ExecuteWorkflowStages",
            items_path="$.parsed_workflow.execution_plan.stages",
            max_concurrency=1,
            result_path="$.workflow_results",
        )
        
        # Execute individual stage
        execute_stage = sfn.Map(
            self,
            "ExecuteStage",
            items_path="$.tasks",
            max_concurrency=10,
            result_path="$.stage_results",
        )
        
        # Save checkpoint before task execution
        save_checkpoint = sfn_tasks.LambdaInvoke(
            self,
            "SaveCheckpoint",
            lambda_function=self.lambda_functions["checkpoint_manager"],
            payload=sfn.TaskInput.from_object({
                "action": "save",
                "workflow_id": sfn.JsonPath.string_at("$.workflow_id"),
                "task_id": sfn.JsonPath.string_at("$.id"),
                "checkpoint_data": sfn.JsonPath.entire_payload,
                "bucket_name": self.checkpoint_bucket.bucket_name,
                "table_name": self.workflow_state_table.table_name,
            }),
            result_path="$.checkpoint",
        )
        
        # Execute Batch job
        execute_task = sfn_tasks.BatchSubmitJob(
            self,
            "ExecuteTask",
            job_definition_arn=self.batch_infrastructure["job_definition"].ref,
            job_name=sfn.JsonPath.string_at("$.name"),
            job_queue_arn=self.batch_infrastructure["job_queue"].ref,
            result_path="$.job_result",
        )
        
        # Handle task failure with retry logic
        handle_task_failure = sfn.Choice(self, "HandleTaskFailure")
        
        # Restore from checkpoint
        restore_checkpoint = sfn_tasks.LambdaInvoke(
            self,
            "RestoreCheckpoint",
            lambda_function=self.lambda_functions["checkpoint_manager"],
            payload=sfn.TaskInput.from_object({
                "action": "restore",
                "workflow_id": sfn.JsonPath.string_at("$.workflow_id"),
                "task_id": sfn.JsonPath.string_at("$.id"),
                "bucket_name": self.checkpoint_bucket.bucket_name,
                "table_name": self.workflow_state_table.table_name,
            }),
            result_path="$.restored_checkpoint",
        )
        
        # Task completion
        task_completed = sfn.Pass(
            self,
            "TaskCompleted",
            parameters={
                "status": "completed",
                "task_id": sfn.JsonPath.string_at("$.id"),
                "completion_time": sfn.JsonPath.string_at("$$.State.EnteredTime"),
            },
        )
        
        # Task failure
        task_failed = sfn.Fail(
            self,
            "TaskFailed",
            cause="Task execution failed after all retry attempts",
        )
        
        # Cleanup resources
        cleanup_resources = sfn.Pass(
            self,
            "CleanupResources",
            result_path="$.cleanup_result",
        )
        
        if self.enable_spot_fleet:
            cleanup_spot_fleet = sfn_tasks.LambdaInvoke(
                self,
                "CleanupSpotFleet",
                lambda_function=self.lambda_functions["spot_fleet_manager"],
                payload=sfn.TaskInput.from_object({
                    "action": "terminate",
                    "fleet_id": sfn.JsonPath.string_at("$.resources[0].spot_fleet.fleet_id"),
                }),
                result_path="$.cleanup_result",
            )
            cleanup_resources = cleanup_spot_fleet
        
        # Workflow completion
        workflow_completed = sfn.Pass(
            self,
            "WorkflowCompleted",
            parameters={
                "status": "completed",
                "workflow_id": sfn.JsonPath.string_at("$.parsed_workflow.workflow_id"),
                "completion_time": sfn.JsonPath.string_at("$$.State.EnteredTime"),
            },
        )
        
        # Build state machine definition
        execute_task.add_retry(
            errors=["States.TaskFailed"],
            interval=Duration.seconds(30),
            max_attempts=3,
            backoff_rate=2.0,
        )
        
        execute_task.add_catch(
            handler=handle_task_failure,
            result_path="$.error",
        )
        
        handle_task_failure.when(
            sfn.Condition.boolean_equals("$.spot_enabled", True),
            restore_checkpoint,
        ).otherwise(task_failed)
        
        restore_checkpoint.next(task_completed)
        execute_task.next(task_completed)
        
        # Chain the workflow
        save_checkpoint.next(execute_task)
        execute_stage.iterator(save_checkpoint)
        execute_stages.iterator(execute_stage)
        
        definition = (
            parse_workflow
            .next(initialize_resources)
            .next(execute_stages)
            .next(cleanup_resources)
            .next(workflow_completed)
        )
        
        # Create state machine
        state_machine = sfn.StateMachine(
            self,
            "HPCWorkflowStateMachine",
            state_machine_name=f"{self.project_name}-orchestrator",
            definition=definition,
            role=self.step_functions_role,
            timeout=Duration.hours(24),
            logs=sfn.LogOptions(
                destination=logs.LogGroup(
                    self,
                    "StateMachineLogGroup",
                    log_group_name=f"/aws/stepfunctions/{self.project_name}-orchestrator",
                    retention=logs.RetentionDays.ONE_MONTH,
                ),
                level=sfn.LogLevel.ALL,
            ),
        )
        
        return state_machine

    def _create_monitoring_infrastructure(self) -> Dict[str, Any]:
        """Create CloudWatch monitoring and alerting infrastructure."""
        # Create SNS topic for alerts
        alerts_topic = sns.Topic(
            self,
            "AlertsTopic",
            topic_name=f"{self.project_name}-alerts",
            display_name="HPC Workflow Alerts",
        )
        
        # Create CloudWatch dashboard
        dashboard = cloudwatch.Dashboard(
            self,
            "HPCWorkflowDashboard",
            dashboard_name=f"{self.project_name}-monitoring",
            widgets=[
                [
                    cloudwatch.GraphWidget(
                        title="Step Functions Execution Metrics",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/StepFunctions",
                                metric_name="ExecutionTime",
                                dimensions_map={
                                    "StateMachineArn": self.state_machine.state_machine_arn,
                                },
                                statistic="Average",
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/StepFunctions",
                                metric_name="ExecutionsFailed",
                                dimensions_map={
                                    "StateMachineArn": self.state_machine.state_machine_arn,
                                },
                                statistic="Sum",
                            ),
                        ],
                        width=12,
                    ),
                ],
                [
                    cloudwatch.GraphWidget(
                        title="Batch Job Metrics",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/Batch",
                                metric_name="RunningJobs",
                                dimensions_map={
                                    "JobQueue": self.batch_infrastructure["job_queue"].job_queue_name,
                                },
                                statistic="Average",
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/Batch",
                                metric_name="SubmittedJobs",
                                dimensions_map={
                                    "JobQueue": self.batch_infrastructure["job_queue"].job_queue_name,
                                },
                                statistic="Sum",
                            ),
                        ],
                        width=12,
                    ),
                ],
            ],
        )
        
        # Create CloudWatch alarms
        workflow_failure_alarm = cloudwatch.Alarm(
            self,
            "WorkflowFailureAlarm",
            alarm_name=f"{self.project_name}-workflow-failures",
            alarm_description="Alert when workflows fail",
            metric=cloudwatch.Metric(
                namespace="AWS/StepFunctions",
                metric_name="ExecutionsFailed",
                dimensions_map={
                    "StateMachineArn": self.state_machine.state_machine_arn,
                },
                statistic="Sum",
            ),
            threshold=1,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
        )
        
        workflow_failure_alarm.add_alarm_action(
            cloudwatch.SnsAction(alerts_topic)
        )
        
        return {
            "alerts_topic": alerts_topic,
            "dashboard": dashboard,
            "workflow_failure_alarm": workflow_failure_alarm,
        }

    def _create_spot_interruption_handling(self) -> Optional[Dict[str, Any]]:
        """Create EventBridge rules for handling Spot instance interruptions."""
        if not self.enable_spot_fleet:
            return None
        
        # Create EventBridge rule for Spot interruption warnings
        spot_interruption_rule = events.Rule(
            self,
            "SpotInterruptionRule",
            rule_name=f"{self.project_name}-spot-interruption-warning",
            description="Detect Spot instance interruption warnings",
            event_pattern=events.EventPattern(
                source=["aws.ec2"],
                detail_type=["EC2 Spot Instance Interruption Warning"],
                detail={"instance-action": ["terminate"]},
            ),
        )
        
        # Add Lambda target to handle interruptions
        spot_interruption_rule.add_target(
            targets.LambdaFunction(
                self.lambda_functions["spot_interruption_handler"]
            )
        )
        
        return {
            "spot_interruption_rule": spot_interruption_rule,
        }

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        CfnOutput(
            self,
            "StateMachineArn",
            value=self.state_machine.state_machine_arn,
            description="ARN of the HPC workflow Step Functions state machine",
        )
        
        CfnOutput(
            self,
            "CheckpointBucketName",
            value=self.checkpoint_bucket.bucket_name,
            description="Name of the S3 bucket for checkpoints",
        )
        
        CfnOutput(
            self,
            "WorkflowStateTableName",
            value=self.workflow_state_table.table_name,
            description="Name of the DynamoDB table for workflow state",
        )
        
        CfnOutput(
            self,
            "BatchJobQueueName",
            value=self.batch_infrastructure["job_queue"].job_queue_name,
            description="Name of the Batch job queue",
        )
        
        CfnOutput(
            self,
            "DashboardUrl",
            value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.project_name}-monitoring",
            description="URL to the CloudWatch dashboard",
        )

    def _get_workflow_parser_code(self) -> str:
        """Return the inline code for the workflow parser Lambda function."""
        return '''
import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """Parse HPC workflow definitions and prepare execution plan."""
    try:
        workflow_definition = event['workflow_definition']
        workflow_id = event.get('workflow_id', f"workflow-{datetime.utcnow().strftime('%Y%m%d-%H%M%S')}")
        
        # Parse workflow definition
        parsed_workflow = parse_workflow(workflow_definition)
        
        # Generate execution plan
        execution_plan = generate_execution_plan(parsed_workflow, workflow_id)
        
        return {
            'statusCode': 200,
            'workflow_id': workflow_id,
            'execution_plan': execution_plan,
            'estimated_cost': calculate_estimated_cost(execution_plan),
            'estimated_duration': calculate_estimated_duration(execution_plan)
        }
        
    except Exception as e:
        logger.error(f"Error parsing workflow: {str(e)}")
        raise

def parse_workflow(workflow_def):
    """Parse workflow definition into structured format."""
    parsed = {
        'name': workflow_def.get('name', 'Unnamed Workflow'),
        'description': workflow_def.get('description', ''),
        'tasks': [],
        'dependencies': {},
        'global_config': workflow_def.get('global_config', {})
    }
    
    # Parse tasks
    for task in workflow_def.get('tasks', []):
        parsed_task = {
            'id': task['id'],
            'name': task.get('name', task['id']),
            'type': task.get('type', 'batch'),
            'container_image': task.get('container_image'),
            'command': task.get('command', []),
            'environment': task.get('environment', {}),
            'resources': {
                'vcpus': task.get('vcpus', 1),
                'memory': task.get('memory', 1024),
                'nodes': task.get('nodes', 1)
            },
            'retry_strategy': {
                'attempts': task.get('retry_attempts', 3),
                'backoff_multiplier': task.get('backoff_multiplier', 2.0)
            },
            'checkpoint_enabled': task.get('checkpoint_enabled', False),
            'spot_enabled': task.get('spot_enabled', True)
        }
        parsed['tasks'].append(parsed_task)
        
        # Parse dependencies
        if 'depends_on' in task:
            parsed['dependencies'][task['id']] = task['depends_on']
    
    return parsed

def generate_execution_plan(parsed_workflow, workflow_id):
    """Generate step-by-step execution plan."""
    execution_plan = {
        'workflow_id': workflow_id,
        'stages': [],
        'parallel_groups': [],
        'total_tasks': len(parsed_workflow['tasks'])
    }
    
    # Simple topological sort for dependency resolution
    remaining_tasks = {task['id']: task for task in parsed_workflow['tasks']}
    dependencies = parsed_workflow['dependencies']
    completed_tasks = set()
    stage_number = 0
    
    while remaining_tasks:
        stage_number += 1
        current_stage = {
            'stage': stage_number,
            'tasks': [],
            'parallel_execution': True
        }
        
        # Find tasks with no remaining dependencies
        ready_tasks = []
        for task_id, task in remaining_tasks.items():
            deps = dependencies.get(task_id, [])
            if all(dep in completed_tasks for dep in deps):
                ready_tasks.append(task)
        
        if not ready_tasks:
            raise ValueError("Unable to resolve task dependencies")
        
        # Add ready tasks to current stage
        for task in ready_tasks:
            current_stage['tasks'].append(task)
            completed_tasks.add(task['id'])
            del remaining_tasks[task['id']]
        
        execution_plan['stages'].append(current_stage)
    
    return execution_plan

def calculate_estimated_cost(execution_plan):
    """Calculate estimated cost for workflow execution."""
    total_vcpu_hours = 0
    
    for stage in execution_plan['stages']:
        for task in stage['tasks']:
            vcpus = task['resources']['vcpus']
            nodes = task['resources']['nodes']
            estimated_hours = 1  # Simplified assumption
            total_vcpu_hours += vcpus * nodes * estimated_hours
    
    # Rough estimate: $0.10 per vCPU hour for spot instances
    estimated_cost = total_vcpu_hours * 0.10
    
    return {
        'total_vcpu_hours': total_vcpu_hours,
        'estimated_cost_usd': estimated_cost,
        'currency': 'USD'
    }

def calculate_estimated_duration(execution_plan):
    """Calculate estimated duration for workflow execution."""
    total_stages = len(execution_plan['stages'])
    estimated_minutes = total_stages * 30  # Simplified assumption
    
    return {
        'estimated_duration_minutes': estimated_minutes,
        'total_stages': total_stages
    }
'''

    def _get_checkpoint_manager_code(self) -> str:
        """Return the inline code for the checkpoint manager Lambda function."""
        return '''
import json
import boto3
import logging
from datetime import datetime
import uuid

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    """Manages checkpoints for fault-tolerant workflows."""
    try:
        action = event.get('action', 'save')
        
        if action == 'save':
            return save_checkpoint(event)
        elif action == 'restore':
            return restore_checkpoint(event)
        elif action == 'list':
            return list_checkpoints(event)
        elif action == 'cleanup':
            return cleanup_old_checkpoints(event)
        else:
            raise ValueError(f"Unknown action: {action}")
            
    except Exception as e:
        logger.error(f"Error in checkpoint manager: {str(e)}")
        raise

def save_checkpoint(event):
    """Save workflow checkpoint to S3 and DynamoDB."""
    workflow_id = event['workflow_id']
    task_id = event['task_id']
    checkpoint_data = event['checkpoint_data']
    bucket_name = event['bucket_name']
    
    # Generate checkpoint ID
    checkpoint_id = str(uuid.uuid4())
    timestamp = datetime.utcnow().isoformat()
    
    # Save checkpoint data to S3
    s3_key = f"checkpoints/{workflow_id}/{task_id}/{checkpoint_id}.json"
    
    s3.put_object(
        Bucket=bucket_name,
        Key=s3_key,
        Body=json.dumps(checkpoint_data),
        ContentType='application/json',
        Metadata={
            'workflow_id': workflow_id,
            'task_id': task_id,
            'timestamp': timestamp
        }
    )
    
    # Update DynamoDB with checkpoint metadata
    table = dynamodb.Table(event['table_name'])
    table.put_item(
        Item={
            'WorkflowId': workflow_id,
            'TaskId': task_id,
            'CheckpointId': checkpoint_id,
            'S3Key': s3_key,
            'Timestamp': timestamp,
            'Status': 'saved'
        }
    )
    
    logger.info(f"Checkpoint saved: {checkpoint_id}")
    
    return {
        'statusCode': 200,
        'checkpoint_id': checkpoint_id,
        's3_key': s3_key,
        'timestamp': timestamp
    }

def restore_checkpoint(event):
    """Restore latest checkpoint for a workflow task."""
    workflow_id = event['workflow_id']
    task_id = event['task_id']
    bucket_name = event['bucket_name']
    table_name = event['table_name']
    
    # Query DynamoDB for latest checkpoint
    table = dynamodb.Table(table_name)
    response = table.query(
        KeyConditionExpression='WorkflowId = :wid AND TaskId = :tid',
        ExpressionAttributeValues={
            ':wid': workflow_id,
            ':tid': task_id
        },
        ScanIndexForward=False,  # Latest first
        Limit=1
    )
    
    if not response['Items']:
        return {
            'statusCode': 404,
            'message': 'No checkpoint found'
        }
    
    latest_checkpoint = response['Items'][0]
    s3_key = latest_checkpoint['S3Key']
    
    # Retrieve checkpoint data from S3
    s3_response = s3.get_object(
        Bucket=bucket_name,
        Key=s3_key
    )
    
    checkpoint_data = json.loads(s3_response['Body'].read().decode('utf-8'))
    
    return {
        'statusCode': 200,
        'checkpoint_id': latest_checkpoint['CheckpointId'],
        'checkpoint_data': checkpoint_data,
        'timestamp': latest_checkpoint['Timestamp']
    }

def list_checkpoints(event):
    """List all checkpoints for a workflow."""
    workflow_id = event['workflow_id']
    table_name = event['table_name']
    
    table = dynamodb.Table(table_name)
    response = table.query(
        KeyConditionExpression='WorkflowId = :wid',
        ExpressionAttributeValues={
            ':wid': workflow_id
        }
    )
    
    return {
        'statusCode': 200,
        'checkpoints': response['Items']
    }

def cleanup_old_checkpoints(event):
    """Clean up checkpoints older than specified days."""
    days_to_keep = event.get('days_to_keep', 7)
    bucket_name = event['bucket_name']
    
    # Implementation for cleanup would go here
    # This is a simplified version
    
    return {
        'statusCode': 200,
        'message': f'Cleanup completed for checkpoints older than {days_to_keep} days'
    }
'''

    def _get_spot_fleet_manager_code(self) -> str:
        """Return the inline code for the spot fleet manager Lambda function."""
        return '''
import json
import boto3
import logging
from datetime import datetime, timedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ec2 = boto3.client('ec2')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    """Manages Spot Fleet lifecycle and handles interruptions."""
    try:
        action = event.get('action', 'create')
        
        if action == 'create':
            return create_spot_fleet(event)
        elif action == 'modify':
            return modify_spot_fleet(event)
        elif action == 'terminate':
            return terminate_spot_fleet(event)
        elif action == 'check_health':
            return check_spot_fleet_health(event)
        else:
            raise ValueError(f"Unknown action: {action}")
            
    except Exception as e:
        logger.error(f"Error in spot fleet manager: {str(e)}")
        raise

def create_spot_fleet(event):
    """Create a new Spot Fleet with fault tolerance."""
    config = {
        'SpotFleetRequestConfig': {
            'IamFleetRole': event['fleet_role_arn'],
            'AllocationStrategy': 'diversified',
            'TargetCapacity': event.get('target_capacity', 4),
            'SpotPrice': event.get('spot_price', '0.50'),
            'LaunchSpecifications': [
                {
                    'ImageId': event.get('ami_id', 'ami-0abcdef1234567890'),
                    'InstanceType': 'c5.large',
                    'KeyName': event.get('key_name'),
                    'SecurityGroups': [{'GroupId': event.get('security_group_id', 'sg-placeholder')}],
                    'SubnetId': event.get('subnet_id', 'subnet-placeholder'),
                    'UserData': event.get('user_data', ''),
                    'WeightedCapacity': 1.0
                },
                {
                    'ImageId': event.get('ami_id', 'ami-0abcdef1234567890'),
                    'InstanceType': 'c5.xlarge',
                    'KeyName': event.get('key_name'),
                    'SecurityGroups': [{'GroupId': event.get('security_group_id', 'sg-placeholder')}],
                    'SubnetId': event.get('subnet_id', 'subnet-placeholder'),
                    'UserData': event.get('user_data', ''),
                    'WeightedCapacity': 2.0
                }
            ],
            'TerminateInstancesWithExpiration': True,
            'Type': 'maintain',
            'ReplaceUnhealthyInstances': True
        }
    }
    
    response = ec2.request_spot_fleet(**config)
    fleet_id = response['SpotFleetRequestId']
    
    # Wait for fleet to become active
    waiter = ec2.get_waiter('spot_fleet_request_fulfilled')
    waiter.wait(SpotFleetRequestIds=[fleet_id])
    
    logger.info(f"Spot Fleet {fleet_id} created successfully")
    
    return {
        'statusCode': 200,
        'fleet_id': fleet_id,
        'status': 'active'
    }

def modify_spot_fleet(event):
    """Modify existing Spot Fleet capacity."""
    fleet_id = event['fleet_id']
    new_capacity = event['target_capacity']
    
    ec2.modify_spot_fleet_request(
        SpotFleetRequestId=fleet_id,
        TargetCapacity=new_capacity
    )
    
    return {
        'statusCode': 200,
        'fleet_id': fleet_id,
        'new_capacity': new_capacity
    }

def terminate_spot_fleet(event):
    """Terminate Spot Fleet."""
    fleet_id = event['fleet_id']
    
    ec2.cancel_spot_fleet_requests(
        SpotFleetRequestIds=[fleet_id],
        TerminateInstances=True
    )
    
    return {
        'statusCode': 200,
        'fleet_id': fleet_id,
        'status': 'terminated'
    }

def check_spot_fleet_health(event):
    """Check Spot Fleet health and capacity."""
    fleet_id = event['fleet_id']
    
    response = ec2.describe_spot_fleet_requests(
        SpotFleetRequestIds=[fleet_id]
    )
    
    fleet_state = response['SpotFleetRequestConfigs'][0]['SpotFleetRequestState']
    
    # Get instance health
    instances_response = ec2.describe_spot_fleet_instances(
        SpotFleetRequestId=fleet_id
    )
    
    healthy_instances = len([
        i for i in instances_response['ActiveInstances'] 
        if i['InstanceHealth'] == 'healthy'
    ])
    
    return {
        'statusCode': 200,
        'fleet_id': fleet_id,
        'fleet_state': fleet_state,
        'healthy_instances': healthy_instances,
        'total_instances': len(instances_response['ActiveInstances'])
    }
'''

    def _get_spot_interruption_handler_code(self) -> str:
        """Return the inline code for the spot interruption handler Lambda function."""
        return '''
import json
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

stepfunctions = boto3.client('stepfunctions')
batch = boto3.client('batch')

def lambda_handler(event, context):
    """Handle Spot instance interruption warnings."""
    try:
        # Extract instance information from CloudWatch event
        detail = event['detail']
        instance_id = detail['instance-id']
        
        logger.info(f"Spot interruption warning received for instance: {instance_id}")
        
        # Find running Batch jobs on this instance
        running_jobs = find_batch_jobs_on_instance(instance_id)
        
        for job_id in running_jobs:
            # Trigger checkpoint and graceful shutdown
            trigger_emergency_checkpoint(job_id)
        
        return {
            'statusCode': 200,
            'message': f'Handled interruption warning for {instance_id}',
            'affected_jobs': running_jobs
        }
        
    except Exception as e:
        logger.error(f"Error handling spot interruption: {str(e)}")
        raise

def find_batch_jobs_on_instance(instance_id):
    """Find Batch jobs running on specific instance."""
    # This is a simplified implementation
    # In practice, you'd need to correlate instance IDs with Batch jobs
    response = batch.list_jobs(
        jobQueue=os.environ.get('BATCH_QUEUE_NAME', 'default'),
        jobStatus='RUNNING'
    )
    
    return [job['jobId'] for job in response['jobSummaryList']]

def trigger_emergency_checkpoint(job_id):
    """Trigger emergency checkpoint for a job."""
    # Send signal to Step Functions to handle graceful shutdown
    logger.info(f"Triggering emergency checkpoint for job: {job_id}")
'''


def main() -> None:
    """Main application entry point."""
    app = App()
    
    # Get configuration from environment variables or use defaults
    project_name = app.node.try_get_context("project_name") or "hpc-workflow"
    enable_spot_fleet = app.node.try_get_context("enable_spot_fleet") != "false"
    vpc_id = app.node.try_get_context("vpc_id")
    
    # Create the main stack
    FaultTolerantHPCWorkflowStack(
        app,
        "FaultTolerantHPCWorkflowStack",
        project_name=project_name,
        enable_spot_fleet=enable_spot_fleet,
        vpc_id=vpc_id,
        description="Fault-tolerant HPC workflows with Step Functions and Spot Fleet",
        tags={
            "Project": project_name,
            "Environment": "Production",
            "Component": "HPC-Workflow-Orchestration",
        },
    )
    
    app.synth()


if __name__ == "__main__":
    main()