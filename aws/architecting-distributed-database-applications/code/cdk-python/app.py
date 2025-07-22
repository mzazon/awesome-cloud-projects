#!/usr/bin/env python3
"""
CDK Python application for Architecting Distributed Database Applications with Aurora DSQL.

This application creates a distributed database architecture using Aurora DSQL's active-active
multi-region capabilities, combined with Lambda functions for serverless compute and EventBridge
for event-driven coordination.
"""

import os
from typing import Dict, Any, Optional

import aws_cdk as cdk
from aws_cdk import (
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_events as events,
    aws_events_targets as targets,
    CfnOutput,
    Stack,
    StackProps,
    Duration,
    Tags,
)
from constructs import Construct

# Since Aurora DSQL is a preview service, we'll use CfnResource for custom resource creation
# This can be updated to use native CDK constructs when they become available
from aws_cdk import aws_lambda as lambda_func
from aws_cdk.aws_lambda import Code, Runtime
import json


class AuroraDSQLStack(Stack):
    """
    CDK Stack for Aurora DSQL multi-region distributed application.
    
    This stack creates:
    - Aurora DSQL clusters in primary and secondary regions
    - Multi-region cluster links for active-active replication
    - Lambda functions for database operations
    - EventBridge custom event buses for cross-region coordination
    - IAM roles and policies with least privilege access
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        primary_region: str = "us-east-1",
        secondary_region: str = "us-west-2",
        witness_region: str = "eu-west-1",
        environment_name: str = "production",
        **kwargs: Any
    ) -> None:
        """
        Initialize the Aurora DSQL stack.

        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            primary_region: Primary AWS region for Aurora DSQL cluster
            secondary_region: Secondary AWS region for Aurora DSQL cluster
            witness_region: Witness region for transaction logs and consensus
            environment_name: Environment name for resource tagging
            **kwargs: Additional keyword arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        self.primary_region = primary_region
        self.secondary_region = secondary_region
        self.witness_region = witness_region
        self.environment_name = environment_name

        # Generate unique suffix for resource names
        unique_suffix = self.node.try_get_context("unique_suffix") or "cdkstack"

        # Create Aurora DSQL clusters
        self.primary_cluster = self._create_dsql_cluster(
            "PrimaryCluster",
            f"app-cluster-primary-{unique_suffix}",
            self.primary_region,
        )

        self.secondary_cluster = self._create_dsql_cluster(
            "SecondaryCluster", 
            f"app-cluster-secondary-{unique_suffix}",
            self.secondary_region,
        )

        # Create multi-region cluster link
        self.cluster_link = self._create_multi_region_link()

        # Create IAM role for Lambda functions
        self.lambda_role = self._create_lambda_execution_role()

        # Create Lambda functions for both regions
        self.primary_lambda = self._create_lambda_function(
            "PrimaryLambda",
            f"dsql-processor-primary-{unique_suffix}",
            self.primary_cluster,
        )

        self.secondary_lambda = self._create_lambda_function(
            "SecondaryLambda",
            f"dsql-processor-secondary-{unique_suffix}", 
            self.secondary_cluster,
        )

        # Create EventBridge custom buses
        self.primary_event_bus = self._create_event_bus(
            "PrimaryEventBus",
            f"dsql-events-{unique_suffix}",
        )

        self.secondary_event_bus = self._create_event_bus(
            "SecondaryEventBus",
            f"dsql-events-{unique_suffix}",
        )

        # Create EventBridge rules and targets
        self._create_event_rules()

        # Create database schema initialization
        self._create_schema_initialization()

        # Add tags to all resources
        self._add_resource_tags()

        # Create outputs
        self._create_outputs()

    def _create_dsql_cluster(
        self, construct_id: str, cluster_name: str, region: str
    ) -> cdk.CfnResource:
        """
        Create an Aurora DSQL cluster.

        Since Aurora DSQL is a preview service, we use CfnResource to create the cluster
        with a custom resource provider.

        Args:
            construct_id: Construct identifier
            cluster_name: Name of the DSQL cluster
            region: AWS region for the cluster

        Returns:
            CfnResource representing the Aurora DSQL cluster
        """
        # Create a custom resource provider for Aurora DSQL cluster creation
        cluster_provider = lambda_func.Function(
            self,
            f"{construct_id}Provider",
            runtime=Runtime.PYTHON_3_9,
            handler="index.handler",
            code=Code.from_inline("""
import json
import boto3
import cfnresponse
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    logger.info(f'Event: {json.dumps(event)}')
    
    try:
        dsql_client = boto3.client('dsql', region_name=event['ResourceProperties']['Region'])
        cluster_name = event['ResourceProperties']['ClusterName']
        witness_region = event['ResourceProperties']['WitnessRegion']
        
        if event['RequestType'] == 'Create':
            # Create Aurora DSQL cluster
            response = dsql_client.create_cluster(
                ClusterName=cluster_name,
                WitnessRegion=witness_region,
                EngineVersion='postgres',
                Tags=[
                    {'Key': 'Environment', 'Value': 'Production'},
                    {'Key': 'Application', 'Value': 'DistributedApp'}
                ]
            )
            cluster_id = response['Cluster']['ClusterIdentifier']
            
            # Wait for cluster to be available
            waiter = dsql_client.get_waiter('cluster_available')
            waiter.wait(ClusterIdentifier=cluster_id)
            
            cfnresponse.send(event, context, cfnresponse.SUCCESS, {
                'ClusterIdentifier': cluster_id,
                'ClusterEndpoint': response['Cluster']['Endpoint']
            }, cluster_id)
            
        elif event['RequestType'] == 'Delete':
            cluster_id = event['PhysicalResourceId']
            try:
                dsql_client.delete_cluster(ClusterIdentifier=cluster_id)
                # Wait for deletion
                waiter = dsql_client.get_waiter('cluster_deleted')
                waiter.wait(ClusterIdentifier=cluster_id)
            except Exception as e:
                logger.warning(f'Error deleting cluster: {e}')
                
            cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
            
        else:  # Update
            cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
            
    except Exception as e:
        logger.error(f'Error: {e}')
        cfnresponse.send(event, context, cfnresponse.FAILED, {})
"""),
            timeout=Duration.minutes(15),
        )

        # Grant permissions to the provider function
        cluster_provider.add_to_role_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "dsql:CreateCluster",
                    "dsql:DeleteCluster", 
                    "dsql:DescribeCluster",
                    "dsql:DescribeClusters",
                    "dsql:TagResource",
                ],
                resources=["*"],
            )
        )

        # Create the custom resource
        cluster = cdk.CustomResource(
            self,
            construct_id,
            service_token=cluster_provider.function_arn,
            properties={
                "ClusterName": cluster_name,
                "Region": region,
                "WitnessRegion": self.witness_region,
            },
        )

        return cluster

    def _create_multi_region_link(self) -> cdk.CfnResource:
        """
        Create multi-region cluster link for active-active replication.

        Returns:
            CfnResource representing the multi-region cluster link
        """
        # Create custom resource provider for multi-region cluster linking
        link_provider = lambda_func.Function(
            self,
            "MultiRegionLinkProvider",
            runtime=Runtime.PYTHON_3_9,
            handler="index.handler",
            code=Code.from_inline("""
import json
import boto3
import cfnresponse
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    logger.info(f'Event: {json.dumps(event)}')
    
    try:
        dsql_client = boto3.client('dsql', region_name=event['ResourceProperties']['PrimaryRegion'])
        primary_cluster_id = event['ResourceProperties']['PrimaryClusterId']
        secondary_cluster_id = event['ResourceProperties']['SecondaryClusterId']
        secondary_region = event['ResourceProperties']['SecondaryRegion']
        witness_region = event['ResourceProperties']['WitnessRegion']
        
        if event['RequestType'] == 'Create':
            # Create multi-region clusters link
            response = dsql_client.create_multi_region_clusters(
                PrimaryClusterIdentifier=primary_cluster_id,
                SecondaryClusterIdentifier=secondary_cluster_id,
                SecondaryClusterRegion=secondary_region,
                WitnessRegion=witness_region
            )
            
            # Wait for multi-region setup to complete
            waiter = dsql_client.get_waiter('multi_region_clusters_available')
            waiter.wait(PrimaryClusterIdentifier=primary_cluster_id)
            
            cfnresponse.send(event, context, cfnresponse.SUCCESS, {
                'LinkId': f"{primary_cluster_id}-{secondary_cluster_id}"
            }, f"{primary_cluster_id}-{secondary_cluster_id}")
            
        elif event['RequestType'] == 'Delete':
            try:
                dsql_client.delete_multi_region_clusters(
                    PrimaryClusterIdentifier=primary_cluster_id
                )
                # Wait for deletion
                waiter = dsql_client.get_waiter('multi_region_clusters_deleted')
                waiter.wait(PrimaryClusterIdentifier=primary_cluster_id)
            except Exception as e:
                logger.warning(f'Error deleting multi-region link: {e}')
                
            cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
            
        else:  # Update
            cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
            
    except Exception as e:
        logger.error(f'Error: {e}')
        cfnresponse.send(event, context, cfnresponse.FAILED, {})
"""),
            timeout=Duration.minutes(15),
        )

        # Grant permissions to the link provider function
        link_provider.add_to_role_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "dsql:CreateMultiRegionClusters",
                    "dsql:DeleteMultiRegionClusters",
                    "dsql:DescribeMultiRegionClusters",
                ],
                resources=["*"],
            )
        )

        # Create the multi-region link
        cluster_link = cdk.CustomResource(
            self,
            "ClusterLink",
            service_token=link_provider.function_arn,
            properties={
                "PrimaryClusterId": self.primary_cluster.get_att("ClusterIdentifier").to_string(),
                "SecondaryClusterId": self.secondary_cluster.get_att("ClusterIdentifier").to_string(),
                "PrimaryRegion": self.primary_region,
                "SecondaryRegion": self.secondary_region,
                "WitnessRegion": self.witness_region,
            },
        )

        # Ensure clusters are created before linking
        cluster_link.node.add_dependency(self.primary_cluster)
        cluster_link.node.add_dependency(self.secondary_cluster)

        return cluster_link

    def _create_lambda_execution_role(self) -> iam.Role:
        """
        Create IAM role for Lambda functions with Aurora DSQL and EventBridge permissions.

        Returns:
            IAM Role with appropriate permissions
        """
        role = iam.Role(
            self,
            "DSQLLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )

        # Add Aurora DSQL and EventBridge permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "dsql:Connect",
                    "dsql:DbConnect", 
                    "dsql:ExecuteStatement",
                    "events:PutEvents",
                ],
                resources=["*"],
            )
        )

        return role

    def _create_lambda_function(
        self, construct_id: str, function_name: str, dsql_cluster: cdk.CfnResource
    ) -> lambda_func.Function:
        """
        Create Lambda function for database operations.

        Args:
            construct_id: Construct identifier
            function_name: Name of the Lambda function
            dsql_cluster: Aurora DSQL cluster resource

        Returns:
            Lambda Function construct
        """
        # Lambda function code for Aurora DSQL operations
        lambda_code = """
import json
import boto3
import os
from datetime import datetime
import uuid
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Lambda handler for Aurora DSQL database operations and EventBridge integration.
    
    Supports read and write operations with automatic event publishing.
    """
    # Initialize clients
    dsql_client = boto3.client('dsql')
    eventbridge = boto3.client('events')
    
    # Aurora DSQL connection parameters
    cluster_identifier = os.environ.get('DSQL_CLUSTER_ID')
    event_bus_name = os.environ.get('EVENT_BUS_NAME', 'default')
    
    logger.info(f'Processing event: {json.dumps(event)}')
    
    try:
        # Process the incoming event
        operation = event.get('operation', 'read')
        
        if operation == 'write':
            # Perform write operation using Aurora DSQL Data API
            transaction_id = event.get('transaction_id', str(uuid.uuid4()))
            amount = event.get('amount', 0)
            
            logger.info(f'Writing transaction {transaction_id} with amount {amount}')
            
            response = dsql_client.execute_statement(
                ClusterIdentifier=cluster_identifier,
                Sql='''
                    INSERT INTO transactions (id, amount, timestamp, region, status)
                    VALUES (?, ?, ?, ?, ?)
                ''',
                Parameters=[
                    {'StringValue': transaction_id},
                    {'DoubleValue': float(amount)},
                    {'StringValue': datetime.now().isoformat()},
                    {'StringValue': context.invoked_function_arn.split(':')[3]},
                    {'StringValue': 'completed'}
                ]
            )
            
            # Publish event to EventBridge
            eventbridge.put_events(
                Entries=[
                    {
                        'Source': 'dsql.application',
                        'DetailType': 'Transaction Created',
                        'Detail': json.dumps({
                            'transaction_id': transaction_id,
                            'amount': amount,
                            'region': context.invoked_function_arn.split(':')[3],
                            'timestamp': datetime.now().isoformat()
                        }),
                        'EventBusName': event_bus_name
                    }
                ]
            )
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Transaction created successfully',
                    'transaction_id': transaction_id,
                    'region': context.invoked_function_arn.split(':')[3]
                })
            }
            
        elif operation == 'read':
            # Perform read operation
            logger.info('Reading transaction count')
            
            response = dsql_client.execute_statement(
                ClusterIdentifier=cluster_identifier,
                Sql='SELECT COUNT(*) as count FROM transactions'
            )
            
            # Extract count from response
            count = 0
            if response.get('Records') and len(response['Records']) > 0:
                if response['Records'][0].get('Values') and len(response['Records'][0]['Values']) > 0:
                    count_value = response['Records'][0]['Values'][0]
                    count = count_value.get('LongValue', 0)
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'transaction_count': count,
                    'region': context.invoked_function_arn.split(':')[3],
                    'timestamp': datetime.now().isoformat()
                })
            }
            
        elif operation == 'init_schema':
            # Initialize database schema
            logger.info('Initializing database schema')
            
            # Create transactions table
            dsql_client.execute_statement(
                ClusterIdentifier=cluster_identifier,
                Sql='''
                    CREATE TABLE IF NOT EXISTS transactions (
                        id VARCHAR(255) PRIMARY KEY,
                        amount DECIMAL(10,2) NOT NULL,
                        timestamp TIMESTAMP NOT NULL,
                        region VARCHAR(50) NOT NULL,
                        status VARCHAR(50) DEFAULT 'pending'
                    )
                '''
            )
            
            # Create indexes
            dsql_client.execute_statement(
                ClusterIdentifier=cluster_identifier,
                Sql='CREATE INDEX IF NOT EXISTS idx_transactions_timestamp ON transactions(timestamp)'
            )
            
            dsql_client.execute_statement(
                ClusterIdentifier=cluster_identifier,
                Sql='CREATE INDEX IF NOT EXISTS idx_transactions_region ON transactions(region)'
            )
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Database schema initialized successfully',
                    'region': context.invoked_function_arn.split(':')[3]
                })
            }
        
        return {
            'statusCode': 400,
            'body': json.dumps({
                'error': 'Invalid operation',
                'supported_operations': ['read', 'write', 'init_schema']
            })
        }
        
    except Exception as e:
        logger.error(f'Error processing request: {str(e)}')
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f'Internal server error: {str(e)}',
                'region': context.invoked_function_arn.split(':')[3]
            })
        }
"""

        function = lambda_func.Function(
            self,
            construct_id,
            function_name=function_name,
            runtime=Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=Code.from_inline(lambda_code),
            role=self.lambda_role,
            timeout=Duration.seconds(30),
            environment={
                "DSQL_CLUSTER_ID": dsql_cluster.get_att("ClusterIdentifier").to_string(),
            },
        )

        return function

    def _create_event_bus(self, construct_id: str, bus_name: str) -> events.EventBus:
        """
        Create EventBridge custom event bus.

        Args:
            construct_id: Construct identifier
            bus_name: Name of the EventBridge bus

        Returns:
            EventBridge EventBus construct
        """
        event_bus = events.EventBus(
            self,
            construct_id,
            event_bus_name=bus_name,
        )

        return event_bus

    def _create_event_rules(self) -> None:
        """Create EventBridge rules for cross-region event replication."""
        # Update Lambda environment to include event bus names
        self.primary_lambda.add_environment(
            "EVENT_BUS_NAME", self.primary_event_bus.event_bus_name
        )
        self.secondary_lambda.add_environment(
            "EVENT_BUS_NAME", self.secondary_event_bus.event_bus_name
        )

        # Create rule for transaction events in primary region
        primary_rule = events.Rule(
            self,
            "PrimaryTransactionRule",
            event_bus=self.primary_event_bus,
            event_pattern=events.EventPattern(
                source=["dsql.application"],
                detail_type=["Transaction Created"],
            ),
        )

        # Create rule for transaction events in secondary region  
        secondary_rule = events.Rule(
            self,
            "SecondaryTransactionRule",
            event_bus=self.secondary_event_bus,
            event_pattern=events.EventPattern(
                source=["dsql.application"],
                detail_type=["Transaction Created"],
            ),
        )

        # Add Lambda targets to rules (for demonstration - in practice you might
        # route to different functions or external systems)
        primary_rule.add_target(targets.LambdaFunction(self.secondary_lambda))
        secondary_rule.add_target(targets.LambdaFunction(self.primary_lambda))

    def _create_schema_initialization(self) -> None:
        """Create Lambda function to initialize database schema."""
        # Create a custom resource to initialize the database schema
        schema_init_provider = lambda_func.Function(
            self,
            "SchemaInitProvider",
            runtime=Runtime.PYTHON_3_9,
            handler="index.handler",
            code=Code.from_inline("""
import json
import boto3
import cfnresponse
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    logger.info(f'Schema init event: {json.dumps(event)}')
    
    try:
        lambda_client = boto3.client('lambda')
        function_name = event['ResourceProperties']['FunctionName']
        
        if event['RequestType'] == 'Create' or event['RequestType'] == 'Update':
            # Invoke the Lambda function to initialize schema
            response = lambda_client.invoke(
                FunctionName=function_name,
                Payload=json.dumps({'operation': 'init_schema'})
            )
            
            payload = json.loads(response['Payload'].read())
            logger.info(f'Schema init response: {payload}')
            
            cfnresponse.send(event, context, cfnresponse.SUCCESS, {
                'Message': 'Schema initialized successfully'
            })
            
        else:  # Delete
            cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
            
    except Exception as e:
        logger.error(f'Error initializing schema: {e}')
        cfnresponse.send(event, context, cfnresponse.FAILED, {})
"""),
            timeout=Duration.minutes(5),
            role=self.lambda_role,
        )

        # Grant permission to invoke the primary Lambda function
        schema_init_provider.add_to_role_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["lambda:InvokeFunction"],
                resources=[self.primary_lambda.function_arn],
            )
        )

        # Create custom resource to initialize schema
        schema_init = cdk.CustomResource(
            self,
            "SchemaInitialization",
            service_token=schema_init_provider.function_arn,
            properties={
                "FunctionName": self.primary_lambda.function_name,
            },
        )

        # Ensure schema initialization happens after cluster link is created
        schema_init.node.add_dependency(self.cluster_link)

    def _add_resource_tags(self) -> None:
        """Add tags to all resources in the stack."""
        Tags.of(self).add("Environment", self.environment_name)
        Tags.of(self).add("Application", "AuroraDSQLMultiRegion")
        Tags.of(self).add("CreatedBy", "CDK")
        Tags.of(self).add("Purpose", "DistributedDatabase")

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource identifiers."""
        CfnOutput(
            self,
            "PrimaryClusterIdentifier",
            description="Primary Aurora DSQL cluster identifier",
            value=self.primary_cluster.get_att("ClusterIdentifier").to_string(),
        )

        CfnOutput(
            self,
            "SecondaryClusterIdentifier", 
            description="Secondary Aurora DSQL cluster identifier",
            value=self.secondary_cluster.get_att("ClusterIdentifier").to_string(),
        )

        CfnOutput(
            self,
            "PrimaryLambdaFunctionName",
            description="Primary region Lambda function name",
            value=self.primary_lambda.function_name,
        )

        CfnOutput(
            self,
            "SecondaryLambdaFunctionName",
            description="Secondary region Lambda function name", 
            value=self.secondary_lambda.function_name,
        )

        CfnOutput(
            self,
            "PrimaryEventBusName",
            description="Primary region EventBridge bus name",
            value=self.primary_event_bus.event_bus_name,
        )

        CfnOutput(
            self,
            "SecondaryEventBusName",
            description="Secondary region EventBridge bus name",
            value=self.secondary_event_bus.event_bus_name,
        )


class AuroraDSQLMultiRegionApp(cdk.App):
    """
    CDK Application for Aurora DSQL multi-region distributed architecture.
    
    This application orchestrates the deployment of a complete multi-region
    distributed system using Aurora DSQL, Lambda, and EventBridge.
    """

    def __init__(self) -> None:
        super().__init__()

        # Get configuration from context or environment variables
        primary_region = self.node.try_get_context("primary_region") or os.environ.get(
            "PRIMARY_REGION", "us-east-1"
        )
        secondary_region = self.node.try_get_context("secondary_region") or os.environ.get(
            "SECONDARY_REGION", "us-west-2"
        )
        witness_region = self.node.try_get_context("witness_region") or os.environ.get(
            "WITNESS_REGION", "eu-west-1"
        )
        environment_name = self.node.try_get_context("environment") or os.environ.get(
            "ENVIRONMENT", "production"
        )

        # Create the main stack
        AuroraDSQLStack(
            self,
            "AuroraDSQLMultiRegionStack",
            primary_region=primary_region,
            secondary_region=secondary_region,
            witness_region=witness_region,
            environment_name=environment_name,
            description="Multi-region distributed application with Aurora DSQL, Lambda, and EventBridge",
        )


# Create and run the CDK application
if __name__ == "__main__":
    app = AuroraDSQLMultiRegionApp()
    app.synth()