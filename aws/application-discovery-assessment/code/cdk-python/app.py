#!/usr/bin/env python3
"""
AWS Application Discovery Service CDK Python Application

This CDK application deploys the infrastructure for AWS Application Discovery Service
including IAM roles, S3 buckets, Lambda functions, and supporting services for
automated discovery and assessment workflows.
"""

import os
from typing import Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    StackProps,
    aws_iam as iam,
    aws_s3 as s3,
    aws_lambda as lambda_,
    aws_events as events,
    aws_events_targets as targets,
    aws_glue as glue,
    aws_athena as athena,
    RemovalPolicy,
    Duration,
)
from constructs import Construct


class ApplicationDiscoveryStack(Stack):
    """
    Stack for AWS Application Discovery Service infrastructure
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        migration_hub_home_region: str = "us-west-2",
        **kwargs: StackProps,
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.try_get_context("unique_suffix") or "discovery"
        account_id = self.account
        region = self.region

        # Create S3 bucket for discovery data export
        self.discovery_bucket = s3.Bucket(
            self,
            "DiscoveryDataBucket",
            bucket_name=f"discovery-data-{account_id}-{unique_suffix}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            versioned=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="discovery-data-lifecycle",
                    enabled=True,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30),
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90),
                        ),
                    ],
                )
            ],
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Create IAM role for Application Discovery Service
        self.discovery_service_role = iam.Role(
            self,
            "ApplicationDiscoveryServiceRole",
            role_name="ApplicationDiscoveryServiceRole",
            assumed_by=iam.ServicePrincipal("discovery.amazonaws.com"),
            description="Role for AWS Application Discovery Service continuous export",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/ApplicationDiscoveryServiceContinuousExportServiceRolePolicy"
                )
            ],
        )

        # Grant the service role permissions to write to S3 bucket
        self.discovery_bucket.grant_write(self.discovery_service_role)

        # Create Lambda function for automated discovery reporting
        self.discovery_automation_function = lambda_.Function(
            self,
            "DiscoveryAutomationFunction",
            function_name=f"discovery-automation-{unique_suffix}",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_lambda_code()),
            timeout=Duration.minutes(5),
            environment={
                "DISCOVERY_BUCKET": self.discovery_bucket.bucket_name,
                "AWS_REGION": region,
            },
            description="Automated discovery data export and reporting",
        )

        # Grant Lambda permissions to start discovery exports
        self.discovery_automation_function.add_to_role_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "discovery:StartExportTask",
                    "discovery:DescribeExportTasks",
                    "discovery:StartContinuousExport",
                    "discovery:DescribeContinuousExports",
                    "discovery:GetDiscoverySummary",
                ],
                resources=["*"],
            )
        )

        # Grant Lambda permissions to write to S3 bucket
        self.discovery_bucket.grant_write(self.discovery_automation_function)

        # Create EventBridge rule for scheduled discovery reports
        self.discovery_schedule_rule = events.Rule(
            self,
            "DiscoveryReportSchedule",
            rule_name="DiscoveryReportSchedule",
            description="Weekly discovery data export schedule",
            schedule=events.Schedule.rate(Duration.days(7)),
            enabled=True,
        )

        # Add Lambda function as target for EventBridge rule
        self.discovery_schedule_rule.add_target(
            targets.LambdaFunction(self.discovery_automation_function)
        )

        # Create Glue database for discovery data analysis
        self.discovery_database = glue.CfnDatabase(
            self,
            "DiscoveryAnalysisDatabase",
            catalog_id=account_id,
            database_input=glue.CfnDatabase.DatabaseInputProperty(
                name="discovery_analysis",
                description="Database for AWS Application Discovery Service data analysis",
            ),
        )

        # Create Glue table for server configurations
        self.servers_table = glue.CfnTable(
            self,
            "ServersTable",
            catalog_id=account_id,
            database_name=self.discovery_database.ref,
            table_input=glue.CfnTable.TableInputProperty(
                name="servers",
                description="Table for server configuration data from Application Discovery Service",
                storage_descriptor=glue.CfnTable.StorageDescriptorProperty(
                    columns=[
                        glue.CfnTable.ColumnProperty(
                            name="server_configuration_id",
                            type="string",
                            comment="Unique identifier for server configuration",
                        ),
                        glue.CfnTable.ColumnProperty(
                            name="server_hostname",
                            type="string",
                            comment="Server hostname",
                        ),
                        glue.CfnTable.ColumnProperty(
                            name="server_os_name",
                            type="string",
                            comment="Operating system name",
                        ),
                        glue.CfnTable.ColumnProperty(
                            name="server_cpu_type",
                            type="string",
                            comment="CPU type and architecture",
                        ),
                        glue.CfnTable.ColumnProperty(
                            name="server_total_ram_kb",
                            type="bigint",
                            comment="Total RAM in kilobytes",
                        ),
                        glue.CfnTable.ColumnProperty(
                            name="server_performance_avg_cpu_usage_pct",
                            type="double",
                            comment="Average CPU usage percentage",
                        ),
                        glue.CfnTable.ColumnProperty(
                            name="server_performance_max_cpu_usage_pct",
                            type="double",
                            comment="Maximum CPU usage percentage",
                        ),
                        glue.CfnTable.ColumnProperty(
                            name="server_performance_avg_free_ram_kb",
                            type="double",
                            comment="Average free RAM in kilobytes",
                        ),
                        glue.CfnTable.ColumnProperty(
                            name="server_type",
                            type="string",
                            comment="Server type (physical/virtual)",
                        ),
                        glue.CfnTable.ColumnProperty(
                            name="server_hypervisor",
                            type="string",
                            comment="Hypervisor type if virtual",
                        ),
                    ],
                    location=f"s3://{self.discovery_bucket.bucket_name}/continuous-export/servers/",
                    input_format="org.apache.hadoop.mapred.TextInputFormat",
                    output_format="org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat",
                    serde_info=glue.CfnTable.SerdeInfoProperty(
                        serialization_library="org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe",
                        parameters={"field.delim": ",", "skip.header.line.count": "1"},
                    ),
                ),
                table_type="EXTERNAL_TABLE",
            ),
        )

        # Create S3 bucket for Athena query results
        self.athena_results_bucket = s3.Bucket(
            self,
            "AthenaResultsBucket",
            bucket_name=f"discovery-athena-results-{account_id}-{unique_suffix}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="athena-results-cleanup",
                    enabled=True,
                    expiration=Duration.days(30),
                )
            ],
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Create Athena workgroup for discovery analysis
        self.athena_workgroup = athena.CfnWorkGroup(
            self,
            "DiscoveryAnalysisWorkGroup",
            name="discovery-analysis",
            description="Workgroup for AWS Application Discovery Service data analysis",
            work_group_configuration=athena.CfnWorkGroup.WorkGroupConfigurationProperty(
                enforce_work_group_configuration=True,
                publish_cloud_watch_metrics=True,
                result_configuration=athena.CfnWorkGroup.ResultConfigurationProperty(
                    output_location=f"s3://{self.athena_results_bucket.bucket_name}/",
                    encryption_configuration=athena.CfnWorkGroup.EncryptionConfigurationProperty(
                        encryption_option="SSE_S3"
                    ),
                ),
            ),
        )

        # Output important resource information
        cdk.CfnOutput(
            self,
            "DiscoveryBucketName",
            value=self.discovery_bucket.bucket_name,
            description="S3 bucket for discovery data export",
        )

        cdk.CfnOutput(
            self,
            "DiscoveryServiceRoleArn",
            value=self.discovery_service_role.role_arn,
            description="IAM role for Application Discovery Service",
        )

        cdk.CfnOutput(
            self,
            "DiscoveryAutomationFunctionName",
            value=self.discovery_automation_function.function_name,
            description="Lambda function for automated discovery reporting",
        )

        cdk.CfnOutput(
            self,
            "GlueDatabaseName",
            value=self.discovery_database.ref,
            description="Glue database for discovery data analysis",
        )

        cdk.CfnOutput(
            self,
            "AthenaWorkGroupName",
            value=self.athena_workgroup.name,
            description="Athena workgroup for discovery analysis",
        )

        cdk.CfnOutput(
            self,
            "MigrationHubHomeRegion",
            value=migration_hub_home_region,
            description="Migration Hub home region for centralized tracking",
        )

    def _get_lambda_code(self) -> str:
        """
        Returns the Lambda function code for automated discovery reporting
        """
        return """
import json
import boto3
import os
from datetime import datetime
from typing import Dict, Any

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    \"\"\"
    Lambda function to automate discovery data export and reporting
    \"\"\"
    try:
        # Initialize AWS clients
        discovery_client = boto3.client('discovery')
        s3_client = boto3.client('s3')
        
        # Get environment variables
        bucket_name = os.environ['DISCOVERY_BUCKET']
        region = os.environ['AWS_REGION']
        
        # Start discovery data export
        export_response = discovery_client.start_export_task(
            exportDataFormat='CSV',
            s3Bucket=bucket_name,
            s3BucketRegion=region
        )
        
        export_id = export_response['exportId']
        
        # Get discovery summary
        summary_response = discovery_client.get_discovery_summary()
        
        # Create report metadata
        report_metadata = {
            'timestamp': datetime.utcnow().isoformat(),
            'export_id': export_id,
            'servers_count': summary_response.get('servers', 0),
            'applications_count': summary_response.get('applications', 0),
            'server_mapping_count': summary_response.get('serverMappings', 0),
            'connector_ids': summary_response.get('connectorIds', []),
            'agent_ids': summary_response.get('agentIds', [])
        }
        
        # Save report metadata to S3
        metadata_key = f"reports/{datetime.utcnow().strftime('%Y/%m/%d')}/report-metadata.json"
        s3_client.put_object(
            Bucket=bucket_name,
            Key=metadata_key,
            Body=json.dumps(report_metadata, indent=2),
            ContentType='application/json'
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Discovery export started successfully',
                'export_id': export_id,
                'metadata_location': f"s3://{bucket_name}/{metadata_key}"
            })
        }
        
    except Exception as e:
        print(f"Error in discovery automation: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Discovery automation failed'
            })
        }
"""


def main() -> None:
    """
    Main function to create and deploy the CDK application
    """
    app = cdk.App()
    
    # Get configuration from CDK context
    migration_hub_home_region = app.node.try_get_context("migration_hub_home_region") or "us-west-2"
    
    # Create the Application Discovery stack
    ApplicationDiscoveryStack(
        app,
        "ApplicationDiscoveryStack",
        migration_hub_home_region=migration_hub_home_region,
        description="AWS Application Discovery Service infrastructure for migration assessment",
        tags={
            "Project": "ApplicationDiscovery",
            "Environment": "Production",
            "ManagedBy": "CDK",
        },
    )
    
    app.synth()


if __name__ == "__main__":
    main()