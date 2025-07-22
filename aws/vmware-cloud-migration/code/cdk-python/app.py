#!/usr/bin/env python3
"""
VMware Cloud Migration with VMware Cloud on AWS CDK Application

This CDK application deploys the infrastructure needed for VMware Cloud migration
including VPC connectivity, monitoring, backup, and supporting AWS services.
"""

import aws_cdk as cdk
from constructs import Construct
from aws_cdk import (
    Stack,
    aws_ec2 as ec2,
    aws_iam as iam,
    aws_s3 as s3,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
    aws_budgets as budgets,
    aws_sns as sns,
    aws_sns_subscriptions as subscriptions,
    aws_events as events,
    aws_events_targets as targets,
    aws_dynamodb as dynamodb,
    aws_lambda as lambda_,
    aws_ce as ce,
    aws_directconnect as dx,
    aws_mgn as mgn,
    RemovalPolicy,
    Duration,
    CfnOutput,
    Tags
)
import json
from typing import Dict, List, Optional


class VMwareCloudMigrationStack(Stack):
    """
    Main stack for VMware Cloud Migration infrastructure.
    
    This stack creates all the necessary AWS resources to support VMware Cloud
    migration including networking, monitoring, backup, and governance.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create VPC for VMware Cloud connectivity
        self.vpc = self._create_vpc()
        
        # Create security groups for HCX
        self.hcx_security_group = self._create_hcx_security_group()
        
        # Create IAM role for VMware Cloud on AWS
        self.vmware_service_role = self._create_vmware_service_role()
        
        # Create S3 bucket for backups
        self.backup_bucket = self._create_backup_bucket()
        
        # Create monitoring and logging
        self.log_group = self._create_log_group()
        self.cloudwatch_dashboard = self._create_cloudwatch_dashboard()
        
        # Create SNS topic for alerts
        self.sns_topic = self._create_sns_topic()
        
        # Create CloudWatch alarms
        self._create_cloudwatch_alarms()
        
        # Create DynamoDB table for migration tracking
        self.migration_table = self._create_migration_table()
        
        # Create Lambda function for migration orchestration
        self.migration_orchestrator = self._create_migration_orchestrator()
        
        # Create EventBridge rules
        self._create_event_rules()
        
        # Create Direct Connect Gateway (optional)
        self.dx_gateway = self._create_dx_gateway()
        
        # Create cost management resources
        self._create_cost_management()
        
        # Create MGN resources
        self._create_mgn_resources()
        
        # Add tags to all resources
        self._add_common_tags()
        
        # Create outputs
        self._create_outputs()

    def _create_vpc(self) -> ec2.Vpc:
        """Create VPC for VMware Cloud connectivity."""
        vpc = ec2.Vpc(
            self, "VMwareCloudVPC",
            vpc_name="vmware-migration-vpc",
            ip_addresses=ec2.IpAddresses.cidr("10.1.0.0/16"),
            max_azs=2,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="VMwareCloudSubnet",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24
                )
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True
        )
        
        # Add VPC endpoint for S3 (cost optimization)
        vpc.add_gateway_endpoint(
            "S3Endpoint",
            service=ec2.GatewayVpcEndpointAwsService.S3,
            subnets=[ec2.SubnetSelection(subnet_type=ec2.SubnetType.PUBLIC)]
        )
        
        return vpc

    def _create_hcx_security_group(self) -> ec2.SecurityGroup:
        """Create security group for HCX traffic."""
        sg = ec2.SecurityGroup(
            self, "HCXSecurityGroup",
            vpc=self.vpc,
            description="Security group for VMware HCX traffic",
            security_group_name="vmware-hcx-sg"
        )
        
        # HCX management traffic
        sg.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(443),
            description="HCX HTTPS management"
        )
        
        sg.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(9443),
            description="HCX vSphere Web Client"
        )
        
        sg.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(8043),
            description="HCX Manager Admin UI"
        )
        
        # HCX mobility traffic
        sg.add_ingress_rule(
            peer=ec2.Peer.ipv4("192.168.0.0/16"),
            connection=ec2.Port.tcp(902),
            description="HCX mobility agent"
        )
        
        # HCX bulk migration ports
        sg.add_ingress_rule(
            peer=ec2.Peer.ipv4("192.168.0.0/16"),
            connection=ec2.Port.tcp_range(31031, 31100),
            description="HCX bulk migration"
        )
        
        return sg

    def _create_vmware_service_role(self) -> iam.Role:
        """Create IAM role for VMware Cloud on AWS service."""
        role = iam.Role(
            self, "VMwareCloudServiceRole",
            role_name="VMwareCloudOnAWS-ServiceRole",
            assumed_by=iam.AccountPrincipal("063048924651"),  # VMware Cloud on AWS account
            external_ids=[self.account],
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "VMwareCloudOnAWSServiceRolePolicy"
                )
            ]
        )
        
        return role

    def _create_backup_bucket(self) -> s3.Bucket:
        """Create S3 bucket for VMware backups with lifecycle policies."""
        bucket = s3.Bucket(
            self, "VMwareBackupBucket",
            bucket_name=f"vmware-backup-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="VMwareBackupLifecycle",
                    enabled=True,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.STANDARD_IA,
                            transition_after=Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90)
                        )
                    ]
                )
            ]
        )
        
        # Add notification configuration for backup events
        bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            s3.NotificationKeyFilter(prefix="migration-plan/")
        )
        
        return bucket

    def _create_log_group(self) -> logs.LogGroup:
        """Create CloudWatch log group for VMware operations."""
        log_group = logs.LogGroup(
            self, "VMwareLogGroup",
            log_group_name="/aws/vmware/migration",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        return log_group

    def _create_cloudwatch_dashboard(self) -> cloudwatch.Dashboard:
        """Create CloudWatch dashboard for VMware migration monitoring."""
        dashboard = cloudwatch.Dashboard(
            self, "VMwareMigrationDashboard",
            dashboard_name="VMware-Migration-Dashboard"
        )
        
        # Add SDDC health metrics
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="VMware SDDC Health",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/VMwareCloudOnAWS",
                        metric_name="HostHealth",
                        statistic="Average"
                    )
                ],
                width=12,
                height=6
            )
        )
        
        # Add migration progress metrics
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Migration Progress",
                left=[
                    cloudwatch.Metric(
                        namespace="VMware/Migration",
                        metric_name="MigrationProgress",
                        statistic="Average"
                    ),
                    cloudwatch.Metric(
                        namespace="VMware/Migration",
                        metric_name="CurrentWave",
                        statistic="Average"
                    )
                ],
                width=12,
                height=6
            )
        )
        
        return dashboard

    def _create_sns_topic(self) -> sns.Topic:
        """Create SNS topic for VMware migration alerts."""
        topic = sns.Topic(
            self, "VMwareMigrationAlerts",
            topic_name="VMware-Migration-Alerts",
            display_name="VMware Migration Alerts"
        )
        
        # Add email subscription (replace with actual email)
        topic.add_subscription(
            subscriptions.EmailSubscription("admin@company.com")
        )
        
        return topic

    def _create_cloudwatch_alarms(self) -> None:
        """Create CloudWatch alarms for SDDC monitoring."""
        # SDDC Host Health alarm
        cloudwatch.Alarm(
            self, "VMwareSDDCHostHealth",
            alarm_name="VMware-SDDC-HostHealth",
            alarm_description="Monitor VMware SDDC host health",
            metric=cloudwatch.Metric(
                namespace="AWS/VMwareCloudOnAWS",
                metric_name="HostHealth",
                statistic="Average"
            ),
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            evaluation_periods=2,
            datapoints_to_alarm=2
        ).add_alarm_action(
            cloudwatch.SnsAction(self.sns_topic)
        )
        
        # Migration progress alarm
        cloudwatch.Alarm(
            self, "MigrationProgressAlarm",
            alarm_name="Migration-Progress-Stalled",
            alarm_description="Alert when migration progress stalls",
            metric=cloudwatch.Metric(
                namespace="VMware/Migration",
                metric_name="MigrationProgress",
                statistic="Average"
            ),
            threshold=5,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            evaluation_periods=3,
            datapoints_to_alarm=3,
            treat_missing_data=cloudwatch.TreatMissingData.BREACHING
        ).add_alarm_action(
            cloudwatch.SnsAction(self.sns_topic)
        )

    def _create_migration_table(self) -> dynamodb.Table:
        """Create DynamoDB table for migration tracking."""
        table = dynamodb.Table(
            self, "VMwareMigrationTracking",
            table_name="VMwareMigrationTracking",
            partition_key=dynamodb.Attribute(
                name="VMName",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="MigrationWave",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True
        )
        
        return table

    def _create_migration_orchestrator(self) -> lambda_.Function:
        """Create Lambda function for migration orchestration."""
        # Create Lambda execution role
        lambda_role = iam.Role(
            self, "MigrationOrchestratorRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )
        
        # Add permissions for CloudWatch metrics and DynamoDB
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "cloudwatch:PutMetricData",
                    "dynamodb:PutItem",
                    "dynamodb:GetItem",
                    "dynamodb:UpdateItem",
                    "dynamodb:Scan",
                    "s3:GetObject",
                    "s3:PutObject",
                    "sns:Publish"
                ],
                resources=["*"]
            )
        )
        
        # Create Lambda function
        function = lambda_.Function(
            self, "MigrationOrchestrator",
            function_name="VMware-Migration-Orchestrator",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_lambda_code()),
            timeout=Duration.minutes(5),
            role=lambda_role,
            environment={
                "BACKUP_BUCKET": self.backup_bucket.bucket_name,
                "SNS_TOPIC_ARN": self.sns_topic.topic_arn,
                "MIGRATION_TABLE": self.migration_table.table_name
            }
        )
        
        return function

    def _get_lambda_code(self) -> str:
        """Get the Lambda function code for migration orchestration."""
        return '''
import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Lambda function to orchestrate VMware migration waves.
    """
    cloudwatch = boto3.client('cloudwatch')
    dynamodb = boto3.resource('dynamodb')
    sns = boto3.client('sns')
    
    # Get environment variables
    backup_bucket = os.environ['BACKUP_BUCKET']
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    table_name = os.environ['MIGRATION_TABLE']
    
    table = dynamodb.Table(table_name)
    
    try:
        # Parse input event
        wave_number = event.get('wave_number', 1)
        action = event.get('action', 'start')
        
        if action == 'start':
            # Start migration wave
            cloudwatch.put_metric_data(
                Namespace='VMware/Migration',
                MetricData=[
                    {
                        'MetricName': 'CurrentWave',
                        'Value': wave_number,
                        'Unit': 'Count'
                    }
                ]
            )
            
            # Update migration table
            table.put_item(
                Item={
                    'VMName': f'wave-{wave_number}',
                    'MigrationWave': str(wave_number),
                    'Status': 'IN_PROGRESS',
                    'StartTime': datetime.now().isoformat(),
                    'Progress': 0
                }
            )
            
            # Send notification
            sns.publish(
                TopicArn=sns_topic_arn,
                Message=f'Migration wave {wave_number} started',
                Subject='VMware Migration Wave Started'
            )
            
        elif action == 'progress':
            # Update migration progress
            progress = event.get('progress', 0)
            
            cloudwatch.put_metric_data(
                Namespace='VMware/Migration',
                MetricData=[
                    {
                        'MetricName': 'WaveProgress',
                        'Value': progress,
                        'Unit': 'Percent'
                    }
                ]
            )
            
            # Update DynamoDB record
            table.update_item(
                Key={
                    'VMName': f'wave-{wave_number}',
                    'MigrationWave': str(wave_number)
                },
                UpdateExpression='SET Progress = :progress',
                ExpressionAttributeValues={
                    ':progress': progress
                }
            )
            
        return {
            'statusCode': 200,
            'body': json.dumps(f'Migration wave {wave_number} {action} completed')
        }
        
    except Exception as e:
        print(f'Error: {str(e)}')
        
        # Send error notification
        sns.publish(
            TopicArn=sns_topic_arn,
            Message=f'Migration orchestration error: {str(e)}',
            Subject='VMware Migration Error'
        )
        
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }
'''

    def _create_event_rules(self) -> None:
        """Create EventBridge rules for SDDC events."""
        # Rule for SDDC state changes
        rule = events.Rule(
            self, "VMwareSDDCStateChangeRule",
            rule_name="VMware-SDDC-StateChange",
            event_pattern=events.EventPattern(
                source=["aws.vmware"],
                detail_type=["VMware Cloud on AWS SDDC State Change"]
            )
        )
        
        # Add SNS target
        rule.add_target(targets.SnsTopic(self.sns_topic))

    def _create_dx_gateway(self) -> Optional[dx.CfnDirectConnectGateway]:
        """Create Direct Connect Gateway for hybrid connectivity."""
        dx_gateway = dx.CfnDirectConnectGateway(
            self, "VMwareDirectConnectGateway",
            name="vmware-migration-dx-gateway",
            amazon_side_asn=64512
        )
        
        return dx_gateway

    def _create_cost_management(self) -> None:
        """Create cost management resources."""
        # Create budget for VMware Cloud on AWS
        budgets.CfnBudget(
            self, "VMwareCloudBudget",
            budget=budgets.CfnBudget.BudgetDataProperty(
                budget_name="VMware-Cloud-Budget",
                budget_limit=budgets.CfnBudget.SpendProperty(
                    amount=15000,
                    unit="USD"
                ),
                time_unit="MONTHLY",
                budget_type="COST",
                cost_filters=budgets.CfnBudget.CostFiltersProperty(
                    service=["VMware Cloud on AWS"]
                )
            ),
            notifications_with_subscribers=[
                budgets.CfnBudget.NotificationWithSubscribersProperty(
                    notification=budgets.CfnBudget.NotificationProperty(
                        notification_type="ACTUAL",
                        comparison_operator="GREATER_THAN",
                        threshold=80,
                        threshold_type="PERCENTAGE"
                    ),
                    subscribers=[
                        budgets.CfnBudget.SubscriberProperty(
                            subscription_type="EMAIL",
                            address="admin@company.com"
                        )
                    ]
                )
            ]
        )
        
        # Create cost anomaly detector
        ce.CfnAnomalyDetector(
            self, "VMwareCostAnomalyDetector",
            detector_name="VMware-Cost-Anomaly-Detector",
            monitor_type="DIMENSIONAL",
            dimension_key="SERVICE",
            monitor_specification=ce.CfnAnomalyDetector.MonitorSpecificationProperty(
                dimension_key="SERVICE",
                match_options=["EQUALS"],
                values=["VMware Cloud on AWS"]
            )
        )

    def _create_mgn_resources(self) -> None:
        """Create Application Migration Service resources."""
        # Create replication configuration template
        mgn.CfnReplicationConfigurationTemplate(
            self, "MGNReplicationTemplate",
            associate_default_security_group=True,
            bandwidth_throttling=100,
            create_public_ip=True,
            data_plane_routing="PRIVATE_IP",
            default_large_staging_disk_type="GP3",
            ebs_encryption="DEFAULT",
            replication_server_instance_type="m5.large",
            staging_area_subnet_id=self.vpc.public_subnets[0].subnet_id,
            staging_area_tags={
                "Environment": "Migration",
                "Project": "VMware"
            },
            use_dedicated_replication_server=False
        )

    def _add_common_tags(self) -> None:
        """Add common tags to all resources."""
        Tags.of(self).add("Project", "VMware-Migration")
        Tags.of(self).add("Environment", "Production")
        Tags.of(self).add("Owner", "CloudOps")
        Tags.of(self).add("CostCenter", "Migration")

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs."""
        CfnOutput(
            self, "VPCId",
            value=self.vpc.vpc_id,
            description="VPC ID for VMware Cloud connectivity"
        )
        
        CfnOutput(
            self, "SubnetId",
            value=self.vpc.public_subnets[0].subnet_id,
            description="Subnet ID for VMware Cloud connectivity"
        )
        
        CfnOutput(
            self, "HCXSecurityGroupId",
            value=self.hcx_security_group.security_group_id,
            description="Security Group ID for HCX traffic"
        )
        
        CfnOutput(
            self, "BackupBucketName",
            value=self.backup_bucket.bucket_name,
            description="S3 bucket for VMware backups"
        )
        
        CfnOutput(
            self, "VMwareServiceRoleArn",
            value=self.vmware_service_role.role_arn,
            description="IAM role ARN for VMware Cloud on AWS"
        )
        
        CfnOutput(
            self, "SNSTopicArn",
            value=self.sns_topic.topic_arn,
            description="SNS topic ARN for migration alerts"
        )
        
        CfnOutput(
            self, "MigrationTableName",
            value=self.migration_table.table_name,
            description="DynamoDB table for migration tracking"
        )
        
        CfnOutput(
            self, "DirectConnectGatewayId",
            value=self.dx_gateway.attr_direct_connect_gateway_id,
            description="Direct Connect Gateway ID for hybrid connectivity"
        )


class VMwareCloudMigrationApp(cdk.App):
    """Main CDK application for VMware Cloud Migration."""
    
    def __init__(self):
        super().__init__()
        
        # Create the main stack
        VMwareCloudMigrationStack(
            self, "VMwareCloudMigrationStack",
            description="Infrastructure for VMware Cloud Migration with VMware Cloud on AWS",
            env=cdk.Environment(
                account=self.node.try_get_context("account"),
                region=self.node.try_get_context("region")
            )
        )


if __name__ == "__main__":
    app = VMwareCloudMigrationApp()
    app.synth()