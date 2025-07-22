#!/usr/bin/env python3
"""
CDK Python application for Implementing Enterprise Search with OpenSearch Service.

This application creates a comprehensive search infrastructure including:
- Multi-AZ OpenSearch Service domain with dedicated master nodes
- Lambda function for automated data indexing
- S3 bucket for data storage
- CloudWatch monitoring and alerting
- IAM roles and security configurations
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_opensearch as opensearch,
    aws_lambda as lambda_,
    aws_s3 as s3,
    aws_iam as iam,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
    aws_cloudwatch_actions as cw_actions,
    aws_sns as sns,
    RemovalPolicy,
    Duration,
    CfnOutput,
)
from constructs import Construct
import json


class OpenSearchSearchSolutionStack(Stack):
    """
    CDK Stack for OpenSearch Service-based search solutions.
    
    Creates a production-ready search infrastructure with enterprise-grade
    features including multi-AZ deployment, dedicated masters, ML capabilities,
    and comprehensive monitoring.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create S3 bucket for data storage
        self.data_bucket = self._create_data_bucket()
        
        # Create CloudWatch log groups for OpenSearch
        self.log_groups = self._create_log_groups()
        
        # Create IAM roles
        self.opensearch_role = self._create_opensearch_service_role()
        self.lambda_role = self._create_lambda_execution_role()
        
        # Create OpenSearch Service domain
        self.opensearch_domain = self._create_opensearch_domain()
        
        # Create Lambda function for data indexing
        self.indexer_function = self._create_indexer_lambda()
        
        # Create CloudWatch monitoring and alerts
        self._create_monitoring_and_alerts()
        
        # Create outputs
        self._create_outputs()

    def _create_data_bucket(self) -> s3.Bucket:
        """Create S3 bucket for storing data to be indexed."""
        bucket = s3.Bucket(
            self,
            "DataBucket",
            bucket_name=f"opensearch-data-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )
        
        # Add CORS configuration for web applications
        bucket.add_cors_rule(
            allowed_methods=[s3.HttpMethods.GET, s3.HttpMethods.PUT, s3.HttpMethods.POST],
            allowed_origins=["*"],
            allowed_headers=["*"],
            max_age=3600,
        )
        
        return bucket

    def _create_log_groups(self) -> dict:
        """Create CloudWatch log groups for OpenSearch Service."""
        log_groups = {}
        
        # Index slow logs
        log_groups["index_slow"] = logs.LogGroup(
            self,
            "IndexSlowLogs",
            log_group_name=f"/aws/opensearch/domains/search-demo/index-slow-logs",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        # Search slow logs
        log_groups["search_slow"] = logs.LogGroup(
            self,
            "SearchSlowLogs",
            log_group_name=f"/aws/opensearch/domains/search-demo/search-slow-logs",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        # Application logs
        log_groups["application"] = logs.LogGroup(
            self,
            "ApplicationLogs",
            log_group_name=f"/aws/opensearch/domains/search-demo/application-logs",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        return log_groups

    def _create_opensearch_service_role(self) -> iam.Role:
        """Create IAM role for OpenSearch Service."""
        role = iam.Role(
            self,
            "OpenSearchServiceRole",
            assumed_by=iam.ServicePrincipal("opensearch.amazonaws.com"),
            description="IAM role for OpenSearch Service domain",
        )
        
        # Add CloudWatch Logs permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:PutLogEvents",
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:DescribeLogGroups",
                    "logs:DescribeLogStreams",
                ],
                resources=[
                    f"arn:aws:logs:{self.region}:{self.account}:log-group:/aws/opensearch/*"
                ],
            )
        )
        
        return role

    def _create_lambda_execution_role(self) -> iam.Role:
        """Create IAM role for Lambda function execution."""
        role = iam.Role(
            self,
            "LambdaExecutionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="IAM role for OpenSearch indexer Lambda function",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )
        
        # Add S3 read permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["s3:GetObject", "s3:ListBucket"],
                resources=[
                    self.data_bucket.bucket_arn,
                    f"{self.data_bucket.bucket_arn}/*",
                ],
            )
        )
        
        return role

    def _create_opensearch_domain(self) -> opensearch.Domain:
        """Create OpenSearch Service domain with production-ready configuration."""
        
        # Create access policy for the domain
        access_policy = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {"AWS": f"arn:aws:iam::{self.account}:root"},
                    "Action": "es:*",
                    "Resource": f"arn:aws:es:{self.region}:{self.account}:domain/search-demo/*",
                }
            ],
        }
        
        domain = opensearch.Domain(
            self,
            "SearchDemoDomain",
            domain_name="search-demo",
            version=opensearch.EngineVersion.OPENSEARCH_2_11,
            
            # Cluster configuration with dedicated masters
            capacity=opensearch.CapacityConfig(
                data_nodes=3,
                data_node_instance_type="m6g.large.search",
                master_nodes=3,
                master_node_instance_type="m6g.medium.search",
                multi_az_with_standby_enabled=False,
            ),
            
            # EBS configuration for high performance
            ebs=opensearch.EbsOptions(
                enabled=True,
                volume_type=cdk.aws_ec2.EbsDeviceVolumeType.GP3,
                volume_size=100,
                iops=3000,
                throughput=125,
            ),
            
            # Security configuration
            node_to_node_encryption=True,
            encryption_at_rest=opensearch.EncryptionAtRestOptions(enabled=True),
            enforce_https=True,
            tls_security_policy=opensearch.TLSSecurityPolicy.TLS_1_2,
            
            # Fine-grained access control
            fine_grained_access_control=opensearch.AdvancedSecurityOptions(
                master_user_name="admin",
                master_user_password=cdk.SecretValue.unsafe_plain_text("TempPassword123!"),
            ),
            
            # Logging configuration
            logging=opensearch.LoggingOptions(
                slow_search_log_enabled=True,
                slow_search_log_group=self.log_groups["search_slow"],
                slow_index_log_enabled=True,
                slow_index_log_group=self.log_groups["index_slow"],
                app_log_enabled=True,
                app_log_group=self.log_groups["application"],
            ),
            
            # Access policies
            access_policies=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    principals=[iam.AnyPrincipal()],
                    actions=["es:*"],
                    resources=[f"arn:aws:es:{self.region}:{self.account}:domain/search-demo/*"],
                )
            ],
            
            # Automated snapshots
            automated_snapshot_start_hour=2,
            
            # Zone awareness for high availability
            zone_awareness=opensearch.ZoneAwarenessConfig(
                enabled=True,
                availability_zone_count=3,
            ),
            
            # Removal policy for demo purposes
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        return domain

    def _create_indexer_lambda(self) -> lambda_.Function:
        """Create Lambda function for automated data indexing."""
        
        # Lambda function code
        lambda_code = """
import json
import boto3
import requests
from requests.auth import HTTPBasicAuth
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    '''
    Lambda function to index data from S3 into OpenSearch Service.
    Processes S3 events and indexes JSON documents.
    '''
    try:
        # Get OpenSearch endpoint from environment
        os_endpoint = os.environ['OPENSEARCH_ENDPOINT']
        
        # Process S3 event records
        if 'Records' in event:
            s3_client = boto3.client('s3')
            
            for record in event['Records']:
                bucket = record['s3']['bucket']['name']
                key = record['s3']['object']['key']
                
                logger.info(f"Processing file: s3://{bucket}/{key}")
                
                # Download file from S3
                try:
                    response = s3_client.get_object(Bucket=bucket, Key=key)
                    content = response['Body'].read().decode('utf-8')
                    
                    # Parse JSON data
                    if key.endswith('.json'):
                        products = json.loads(content)
                        
                        # Ensure products is a list
                        if not isinstance(products, list):
                            products = [products]
                        
                        # Index each product
                        for product in products:
                            if 'id' in product:
                                doc_id = product['id']
                                index_url = f"https://{os_endpoint}/products/_doc/{doc_id}"
                                
                                # Index document (using HTTP basic auth)
                                response = requests.put(
                                    index_url,
                                    headers={'Content-Type': 'application/json'},
                                    auth=HTTPBasicAuth('admin', 'TempPassword123!'),
                                    data=json.dumps(product),
                                    timeout=30
                                )
                                
                                if response.status_code in [200, 201]:
                                    logger.info(f"Successfully indexed product {doc_id}")
                                else:
                                    logger.error(f"Failed to index product {doc_id}: {response.status_code} - {response.text}")
                        
                        # Refresh index to make documents searchable
                        refresh_url = f"https://{os_endpoint}/products/_refresh"
                        requests.post(
                            refresh_url,
                            auth=HTTPBasicAuth('admin', 'TempPassword123!'),
                            timeout=30
                        )
                        
                    else:
                        logger.warning(f"Skipping non-JSON file: {key}")
                        
                except Exception as e:
                    logger.error(f"Error processing file {key}: {str(e)}")
                    continue
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Data indexing completed successfully',
                'processed_records': len(event.get('Records', []))
            })
        }
        
    except Exception as e:
        logger.error(f"Lambda execution error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Data indexing failed'
            })
        }
"""
        
        function = lambda_.Function(
            self,
            "OpenSearchIndexer",
            function_name="opensearch-indexer",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(lambda_code),
            role=self.lambda_role,
            timeout=Duration.minutes(5),
            memory_size=256,
            environment={
                "OPENSEARCH_ENDPOINT": self.opensearch_domain.domain_endpoint,
            },
            description="Lambda function for indexing data into OpenSearch Service",
        )
        
        # Add permissions for OpenSearch access
        function.add_to_role_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "es:ESHttpPost",
                    "es:ESHttpPut",
                    "es:ESHttpGet",
                    "es:ESHttpDelete",
                ],
                resources=[self.opensearch_domain.domain_arn + "/*"],
            )
        )
        
        return function

    def _create_monitoring_and_alerts(self) -> None:
        """Create CloudWatch monitoring dashboard and alerts."""
        
        # Create SNS topic for alerts
        alert_topic = sns.Topic(
            self,
            "OpenSearchAlerts",
            topic_name="opensearch-alerts",
            display_name="OpenSearch Service Alerts",
        )
        
        # Create CloudWatch dashboard
        dashboard = cloudwatch.Dashboard(
            self,
            "OpenSearchDashboard",
            dashboard_name="OpenSearch-SearchDemo-Dashboard",
        )
        
        # Add performance metrics widget
        performance_widget = cloudwatch.GraphWidget(
            title="OpenSearch Performance Metrics",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/ES",
                    metric_name="SearchLatency",
                    dimensions_map={
                        "DomainName": self.opensearch_domain.domain_name,
                        "ClientId": self.account,
                    },
                    statistic="Average",
                ),
                cloudwatch.Metric(
                    namespace="AWS/ES",
                    metric_name="IndexingLatency",
                    dimensions_map={
                        "DomainName": self.opensearch_domain.domain_name,
                        "ClientId": self.account,
                    },
                    statistic="Average",
                ),
            ],
            right=[
                cloudwatch.Metric(
                    namespace="AWS/ES",
                    metric_name="SearchRate",
                    dimensions_map={
                        "DomainName": self.opensearch_domain.domain_name,
                        "ClientId": self.account,
                    },
                    statistic="Average",
                ),
                cloudwatch.Metric(
                    namespace="AWS/ES",
                    metric_name="IndexingRate",
                    dimensions_map={
                        "DomainName": self.opensearch_domain.domain_name,
                        "ClientId": self.account,
                    },
                    statistic="Average",
                ),
            ],
        )
        
        # Add cluster health widget
        health_widget = cloudwatch.GraphWidget(
            title="OpenSearch Cluster Health",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/ES",
                    metric_name="ClusterStatus.yellow",
                    dimensions_map={
                        "DomainName": self.opensearch_domain.domain_name,
                        "ClientId": self.account,
                    },
                    statistic="Maximum",
                ),
                cloudwatch.Metric(
                    namespace="AWS/ES",
                    metric_name="ClusterStatus.red",
                    dimensions_map={
                        "DomainName": self.opensearch_domain.domain_name,
                        "ClientId": self.account,
                    },
                    statistic="Maximum",
                ),
            ],
            right=[
                cloudwatch.Metric(
                    namespace="AWS/ES",
                    metric_name="StorageUtilization",
                    dimensions_map={
                        "DomainName": self.opensearch_domain.domain_name,
                        "ClientId": self.account,
                    },
                    statistic="Maximum",
                ),
                cloudwatch.Metric(
                    namespace="AWS/ES",
                    metric_name="CPUUtilization",
                    dimensions_map={
                        "DomainName": self.opensearch_domain.domain_name,
                        "ClientId": self.account,
                    },
                    statistic="Average",
                ),
            ],
        )
        
        dashboard.add_widgets(performance_widget, health_widget)
        
        # Create high search latency alarm
        search_latency_alarm = cloudwatch.Alarm(
            self,
            "HighSearchLatencyAlarm",
            alarm_name=f"OpenSearch-High-Search-Latency-{self.opensearch_domain.domain_name}",
            alarm_description="Alert when search latency exceeds 1000ms",
            metric=cloudwatch.Metric(
                namespace="AWS/ES",
                metric_name="SearchLatency",
                dimensions_map={
                    "DomainName": self.opensearch_domain.domain_name,
                    "ClientId": self.account,
                },
                statistic="Average",
            ),
            threshold=1000,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        )
        
        # Add SNS action to alarm
        search_latency_alarm.add_alarm_action(
            cw_actions.SnsAction(alert_topic)
        )
        
        # Create cluster status alarm
        cluster_status_alarm = cloudwatch.Alarm(
            self,
            "ClusterStatusAlarm",
            alarm_name=f"OpenSearch-Cluster-Status-{self.opensearch_domain.domain_name}",
            alarm_description="Alert when cluster status is red",
            metric=cloudwatch.Metric(
                namespace="AWS/ES",
                metric_name="ClusterStatus.red",
                dimensions_map={
                    "DomainName": self.opensearch_domain.domain_name,
                    "ClientId": self.account,
                },
                statistic="Maximum",
            ),
            threshold=0,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        )
        
        cluster_status_alarm.add_alarm_action(
            cw_actions.SnsAction(alert_topic)
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        
        CfnOutput(
            self,
            "OpenSearchDomainEndpoint",
            description="OpenSearch Service domain endpoint",
            value=f"https://{self.opensearch_domain.domain_endpoint}",
            export_name="OpenSearchDomainEndpoint",
        )
        
        CfnOutput(
            self,
            "OpenSearchDashboardsURL",
            description="OpenSearch Dashboards URL",
            value=f"https://{self.opensearch_domain.domain_endpoint}/_dashboards/",
            export_name="OpenSearchDashboardsURL",
        )
        
        CfnOutput(
            self,
            "DataBucketName",
            description="S3 bucket name for data storage",
            value=self.data_bucket.bucket_name,
            export_name="DataBucketName",
        )
        
        CfnOutput(
            self,
            "IndexerFunctionName",
            description="Lambda function name for data indexing",
            value=self.indexer_function.function_name,
            export_name="IndexerFunctionName",
        )
        
        CfnOutput(
            self,
            "IndexerFunctionArn",
            description="Lambda function ARN for data indexing",
            value=self.indexer_function.function_arn,
            export_name="IndexerFunctionArn",
        )


# CDK App
app = cdk.App()

# Create the main stack
OpenSearchSearchSolutionStack(
    app,
    "OpenSearchSearchSolutionStack",
    description="CDK stack for Implementing Enterprise Search with OpenSearch Service",
    env=cdk.Environment(
        account=app.node.try_get_context("account"),
        region=app.node.try_get_context("region"),
    ),
)

app.synth()