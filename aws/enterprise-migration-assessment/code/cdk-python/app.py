#!/usr/bin/env python3
"""
AWS CDK Application for Enterprise Migration Assessment
with AWS Application Discovery Service

This CDK application deploys infrastructure for comprehensive
enterprise migration assessment using AWS Application Discovery Service,
Migration Hub, and supporting services.
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_s3 as s3,
    aws_iam as iam,
    aws_logs as logs,
    aws_events as events,
    aws_events_targets as targets,
    aws_lambda as lambda_,
    aws_ssm as ssm,
    RemovalPolicy,
    Duration,
    CfnOutput,
    Tags
)
from constructs import Construct
from typing import Dict, Any
import os
import json


class MigrationDiscoveryStack(Stack):
    """
    CDK Stack for Enterprise Migration Assessment Infrastructure
    
    This stack creates:
    - S3 bucket for discovery data storage
    - IAM roles for Application Discovery Service
    - CloudWatch logs for monitoring
    - EventBridge rules for automated exports
    - Lambda function for data processing
    - SSM parameters for configuration
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        account_id = self.account
        region = self.region
        unique_suffix = f"{account_id[:8]}-{region}"

        # Create S3 bucket for discovery data export
        self.discovery_bucket = self._create_discovery_bucket(unique_suffix)
        
        # Create IAM roles for discovery services
        self.discovery_role = self._create_discovery_service_role()
        
        # Create CloudWatch log group for discovery monitoring
        self.log_group = self._create_log_group(unique_suffix)
        
        # Create Lambda function for data processing
        self.data_processor = self._create_data_processor_function(unique_suffix)
        
        # Create EventBridge rule for automated exports
        self.export_rule = self._create_automated_export_rule()
        
        # Create SSM parameters for configuration
        self._create_configuration_parameters(unique_suffix)
        
        # Add tags to all resources
        self._add_tags()

    def _create_discovery_bucket(self, unique_suffix: str) -> s3.Bucket:
        """
        Create S3 bucket for storing discovery data exports
        
        Args:
            unique_suffix: Unique identifier for bucket naming
            
        Returns:
            S3 Bucket construct
        """
        bucket_name = f"migration-discovery-{unique_suffix}"
        
        bucket = s3.Bucket(
            self, "DiscoveryDataBucket",
            bucket_name=bucket_name,
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DiscoveryDataLifecycle",
                    enabled=True,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90)
                        )
                    ],
                    noncurrent_version_transitions=[
                        s3.NoncurrentVersionTransition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(30)
                        )
                    ]
                )
            ],
            removal_policy=RemovalPolicy.RETAIN
        )
        
        # Add bucket policy for Application Discovery Service
        bucket.add_to_resource_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("discovery.amazonaws.com")],
                actions=[
                    "s3:GetBucketLocation",
                    "s3:ListBucket",
                    "s3:PutObject",
                    "s3:GetObject",
                    "s3:DeleteObject"
                ],
                resources=[
                    bucket.bucket_arn,
                    f"{bucket.bucket_arn}/*"
                ]
            )
        )
        
        CfnOutput(
            self, "DiscoveryBucketName",
            value=bucket.bucket_name,
            description="S3 bucket for discovery data exports"
        )
        
        return bucket

    def _create_discovery_service_role(self) -> iam.Role:
        """
        Create IAM role for Application Discovery Service
        
        Returns:
            IAM Role for discovery service
        """
        role = iam.Role(
            self, "DiscoveryServiceRole",
            assumed_by=iam.ServicePrincipal("discovery.amazonaws.com"),
            description="Role for AWS Application Discovery Service",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AWSApplicationDiscoveryServiceFirehose"
                )
            ]
        )
        
        # Add inline policy for S3 access
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetBucketLocation",
                    "s3:ListBucket",
                    "s3:PutObject",
                    "s3:GetObject"
                ],
                resources=[
                    self.discovery_bucket.bucket_arn,
                    f"{self.discovery_bucket.bucket_arn}/*"
                ]
            )
        )
        
        # Add policy for Migration Hub integration
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "mgh:CreateProgressUpdateStream",
                    "mgh:DescribeApplicationState",
                    "mgh:DescribeMigrationTask",
                    "mgh:ListCreatedArtifacts",
                    "mgh:ListDiscoveredResources",
                    "mgh:ListMigrationTasks",
                    "mgh:ListProgressUpdateStreams",
                    "mgh:NotifyApplicationState",
                    "mgh:NotifyMigrationTaskState",
                    "mgh:PutResourceAttributes"
                ],
                resources=["*"]
            )
        )
        
        CfnOutput(
            self, "DiscoveryServiceRoleArn",
            value=role.role_arn,
            description="IAM role ARN for Application Discovery Service"
        )
        
        return role

    def _create_log_group(self, unique_suffix: str) -> logs.LogGroup:
        """
        Create CloudWatch log group for discovery monitoring
        
        Args:
            unique_suffix: Unique identifier for log group naming
            
        Returns:
            CloudWatch LogGroup construct
        """
        log_group = logs.LogGroup(
            self, "DiscoveryLogGroup",
            log_group_name=f"/aws/discovery/enterprise-migration-{unique_suffix}",
            retention=logs.RetentionDays.SIX_MONTHS,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        CfnOutput(
            self, "DiscoveryLogGroupName",
            value=log_group.log_group_name,
            description="CloudWatch log group for discovery monitoring"
        )
        
        return log_group

    def _create_data_processor_function(self, unique_suffix: str) -> lambda_.Function:
        """
        Create Lambda function for processing discovery data
        
        Args:
            unique_suffix: Unique identifier for function naming
            
        Returns:
            Lambda Function construct
        """
        # Create Lambda execution role
        lambda_role = iam.Role(
            self, "DataProcessorRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )
        
        # Add permissions for S3 and Discovery Service
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:ListBucket"
                ],
                resources=[
                    self.discovery_bucket.bucket_arn,
                    f"{self.discovery_bucket.bucket_arn}/*"
                ]
            )
        )
        
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "discovery:DescribeConfigurations",
                    "discovery:ListConfigurations",
                    "discovery:DescribeExportTasks",
                    "discovery:StartExportTask"
                ],
                resources=["*"]
            )
        )
        
        # Lambda function code
        lambda_code = '''
import json
import boto3
import csv
import io
from datetime import datetime
from typing import Dict, List, Any

def lambda_handler(event, context):
    """
    Process discovery data exports and generate migration assessments
    """
    s3 = boto3.client('s3')
    discovery = boto3.client('discovery')
    
    try:
        # Get bucket and key from S3 event
        bucket = event['Records'][0]['s3']['bucket']['name']
        key = event['Records'][0]['s3']['object']['key']
        
        # Process discovery data file
        response = s3.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8')
        
        # Parse CSV data
        csv_reader = csv.DictReader(io.StringIO(content))
        servers = list(csv_reader)
        
        # Generate migration assessment
        assessment = generate_migration_assessment(servers)
        
        # Save assessment results
        assessment_key = f"assessments/migration-assessment-{datetime.now().strftime('%Y%m%d-%H%M%S')}.json"
        s3.put_object(
            Bucket=bucket,
            Key=assessment_key,
            Body=json.dumps(assessment, indent=2),
            ContentType='application/json'
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Assessment completed successfully',
                'assessment_file': assessment_key
            })
        }
        
    except Exception as e:
        print(f"Error processing discovery data: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def generate_migration_assessment(servers: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Generate migration readiness assessment from discovery data
    """
    assessment = {
        'timestamp': datetime.now().isoformat(),
        'total_servers': len(servers),
        'server_categories': {
            'windows': 0,
            'linux': 0,
            'other': 0
        },
        'migration_complexity': {
            'low': 0,
            'medium': 0,
            'high': 0
        },
        'recommendations': []
    }
    
    for server in servers:
        # Categorize by OS
        os_name = server.get('osName', '').lower()
        if 'windows' in os_name:
            assessment['server_categories']['windows'] += 1
        elif any(linux_dist in os_name for linux_dist in ['linux', 'ubuntu', 'rhel', 'centos']):
            assessment['server_categories']['linux'] += 1
        else:
            assessment['server_categories']['other'] += 1
        
        # Assess migration complexity based on factors
        complexity = assess_server_complexity(server)
        assessment['migration_complexity'][complexity] += 1
    
    # Generate recommendations
    assessment['recommendations'] = generate_recommendations(assessment)
    
    return assessment

def assess_server_complexity(server: Dict[str, Any]) -> str:
    """
    Assess migration complexity for a single server
    """
    # Simplified complexity assessment logic
    cpu_count = int(server.get('processorCount', 0))
    memory_mb = int(server.get('totalRamInMB', 0))
    
    if cpu_count <= 2 and memory_mb <= 4096:
        return 'low'
    elif cpu_count <= 8 and memory_mb <= 16384:
        return 'medium'
    else:
        return 'high'

def generate_recommendations(assessment: Dict[str, Any]) -> List[str]:
    """
    Generate migration recommendations based on assessment
    """
    recommendations = []
    
    total_servers = assessment['total_servers']
    
    if total_servers > 100:
        recommendations.append("Consider phased migration approach with multiple waves")
    
    if assessment['migration_complexity']['high'] > total_servers * 0.3:
        recommendations.append("High complexity servers detected - plan for extended migration timelines")
    
    if assessment['server_categories']['windows'] > assessment['server_categories']['linux']:
        recommendations.append("Windows-heavy environment - consider Windows Server on AWS optimization")
    
    return recommendations
'''
        
        function = lambda_.Function(
            self, "DiscoveryDataProcessor",
            function_name=f"discovery-data-processor-{unique_suffix}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(lambda_code),
            role=lambda_role,
            timeout=Duration.minutes(5),
            memory_size=512,
            environment={
                "DISCOVERY_BUCKET": self.discovery_bucket.bucket_name,
                "LOG_GROUP": self.log_group.log_group_name
            }
        )
        
        # Add S3 event trigger
        self.discovery_bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            targets.LambdaDestination(function),
            s3.NotificationKeyFilter(prefix="exports/")
        )
        
        CfnOutput(
            self, "DataProcessorFunctionName",
            value=function.function_name,
            description="Lambda function for processing discovery data"
        )
        
        return function

    def _create_automated_export_rule(self) -> events.Rule:
        """
        Create EventBridge rule for automated weekly discovery exports
        
        Returns:
            EventBridge Rule construct
        """
        # Create Lambda function for triggering exports
        export_lambda_role = iam.Role(
            self, "ExportLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )
        
        export_lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "discovery:StartExportTask",
                    "discovery:DescribeExportTasks"
                ],
                resources=["*"]
            )
        )
        
        export_function_code = '''
import json
import boto3
from datetime import datetime

def lambda_handler(event, context):
    """
    Trigger automated discovery data export
    """
    discovery = boto3.client('discovery')
    
    try:
        # Start export task
        response = discovery.start_export_task(
            exportDataFormat='CSV',
            filters=[
                {
                    'name': 'AgentId',
                    'values': ['*'],
                    'condition': 'EQUALS'
                }
            ],
            s3Bucket=os.environ['DISCOVERY_BUCKET'],
            s3Prefix=f"exports/automated-{datetime.now().strftime('%Y%m%d')}"
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Export task started successfully',
                'exportId': response['exportId']
            })
        }
        
    except Exception as e:
        print(f"Error starting export task: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
'''
        
        export_function = lambda_.Function(
            self, "AutomatedExportFunction",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(export_function_code),
            role=export_lambda_role,
            timeout=Duration.minutes(2),
            environment={
                "DISCOVERY_BUCKET": self.discovery_bucket.bucket_name
            }
        )
        
        # Create EventBridge rule for weekly execution
        rule = events.Rule(
            self, "WeeklyDiscoveryExport",
            schedule=events.Schedule.rate(Duration.days(7)),
            description="Automated weekly discovery data export",
            enabled=True
        )
        
        rule.add_target(targets.LambdaFunction(export_function))
        
        CfnOutput(
            self, "AutomatedExportRuleName",
            value=rule.rule_name,
            description="EventBridge rule for automated exports"
        )
        
        return rule

    def _create_configuration_parameters(self, unique_suffix: str) -> None:
        """
        Create SSM parameters for configuration management
        
        Args:
            unique_suffix: Unique identifier for parameter naming
        """
        # Migration project configuration
        ssm.StringParameter(
            self, "MigrationProjectName",
            parameter_name=f"/migration/discovery/{unique_suffix}/project-name",
            string_value=f"enterprise-migration-{unique_suffix}",
            description="Migration project name for tracking"
        )
        
        # Discovery configuration
        discovery_config = {
            "region": self.region,
            "enableSSL": True,
            "collectionConfiguration": {
                "collectProcesses": True,
                "collectNetworkConnections": True,
                "collectPerformanceData": True
            }
        }
        
        ssm.StringParameter(
            self, "DiscoveryConfiguration",
            parameter_name=f"/migration/discovery/{unique_suffix}/agent-config",
            string_value=json.dumps(discovery_config),
            description="Discovery agent configuration"
        )
        
        # Migration wave configuration
        migration_waves = {
            "waves": [
                {
                    "waveNumber": 1,
                    "name": "Pilot Wave - Low Risk Applications",
                    "description": "Standalone applications with minimal dependencies",
                    "targetMigrationDate": "2024-Q2"
                },
                {
                    "waveNumber": 2,
                    "name": "Business Applications Wave",
                    "description": "Core business applications with managed dependencies",
                    "targetMigrationDate": "2024-Q3"
                },
                {
                    "waveNumber": 3,
                    "name": "Legacy Systems Wave",
                    "description": "Complex legacy systems requiring refactoring",
                    "targetMigrationDate": "2024-Q4"
                }
            ]
        }
        
        ssm.StringParameter(
            self, "MigrationWaves",
            parameter_name=f"/migration/discovery/{unique_suffix}/wave-config",
            string_value=json.dumps(migration_waves),
            description="Migration wave planning configuration"
        )

    def _add_tags(self) -> None:
        """Add tags to all resources in the stack"""
        Tags.of(self).add("Project", "EnterpriseMigrationAssessment")
        Tags.of(self).add("Environment", "Discovery")
        Tags.of(self).add("ManagedBy", "CDK")
        Tags.of(self).add("Purpose", "MigrationAssessment")


class MigrationDiscoveryApp(cdk.App):
    """CDK Application for Migration Discovery Infrastructure"""
    
    def __init__(self):
        super().__init__()
        
        # Get environment configuration
        env = cdk.Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
        )
        
        # Create the main stack
        MigrationDiscoveryStack(
            self, "MigrationDiscoveryStack",
            env=env,
            description="Infrastructure for Enterprise Migration Assessment with AWS Application Discovery Service"
        )


def main():
    """Main application entry point"""
    app = MigrationDiscoveryApp()
    app.synth()


if __name__ == "__main__":
    main()