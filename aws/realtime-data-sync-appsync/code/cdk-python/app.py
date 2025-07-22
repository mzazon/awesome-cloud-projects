#!/usr/bin/env python3
"""
AWS CDK Python Application for Real-Time Data Synchronization
with AWS AppSync and DynamoDB Streams

This application creates a complete serverless real-time data synchronization
solution using AWS AppSync GraphQL API with DynamoDB Streams for automatic
change notification across all connected clients.
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_dynamodb as dynamodb,
    aws_lambda as lambda_,
    aws_lambda_event_sources as lambda_event_sources,
    aws_iam as iam,
    aws_appsync as appsync,
    aws_logs as logs,
    CfnOutput,
    Tags
)
from constructs import Construct


class RealTimeDataSyncStack(Stack):
    """
    CDK Stack for Real-Time Data Synchronization with AppSync and DynamoDB Streams
    
    This stack creates:
    - DynamoDB table with streams enabled
    - Lambda function for stream processing
    - AppSync GraphQL API with real-time subscriptions
    - IAM roles and policies with least privilege access
    - CloudWatch logging and monitoring
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack parameters
        self.table_name = f"RealTimeData-{self.node.addr}"
        self.api_name = f"RealTimeSyncAPI-{self.node.addr}"
        
        # Create DynamoDB table with streams
        self.dynamodb_table = self._create_dynamodb_table()
        
        # Create Lambda function for stream processing
        self.stream_processor = self._create_stream_processor()
        
        # Create AppSync GraphQL API
        self.appsync_api = self._create_appsync_api()
        
        # Create data sources and resolvers
        self.dynamodb_data_source = self._create_dynamodb_data_source()
        self._create_graphql_resolvers()
        
        # Add resource tags
        self._add_resource_tags()
        
        # Create outputs
        self._create_outputs()

    def _create_dynamodb_table(self) -> dynamodb.Table:
        """
        Create DynamoDB table with streams enabled for real-time change capture
        
        Returns:
            dynamodb.Table: DynamoDB table with streams configuration
        """
        table = dynamodb.Table(
            self, "RealTimeDataTable",
            table_name=self.table_name,
            partition_key=dynamodb.Attribute(
                name="id",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
            deletion_protection=False
        )
        
        # Add tags for resource management
        Tags.of(table).add("Component", "DataStorage")
        Tags.of(table).add("Service", "DynamoDB")
        
        return table

    def _create_stream_processor(self) -> lambda_.Function:
        """
        Create Lambda function to process DynamoDB stream events
        
        Returns:
            lambda_.Function: Lambda function for stream processing
        """
        # Create Lambda execution role
        lambda_role = iam.Role(
            self, "StreamProcessorRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaDynamoDBExecutionRole"
                )
            ]
        )
        
        # Create Lambda function
        function = lambda_.Function(
            self, "StreamProcessor",
            function_name=f"AppSyncNotifier-{self.node.addr}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_lambda_code()),
            role=lambda_role,
            timeout=Duration.minutes(1),
            memory_size=256,
            environment={
                "TABLE_NAME": self.dynamodb_table.table_name,
                "APPSYNC_API_URL": "",  # Will be updated after AppSync creation
                "LOG_LEVEL": "INFO"
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
            dead_letter_queue_enabled=True,
            reserved_concurrent_executions=10
        )
        
        # Add DynamoDB stream as event source
        function.add_event_source(
            lambda_event_sources.DynamoEventSource(
                self.dynamodb_table,
                starting_position=lambda_.StartingPosition.LATEST,
                batch_size=10,
                max_batching_window=Duration.seconds(5),
                retry_attempts=3,
                parallelization_factor=1
            )
        )
        
        # Add tags
        Tags.of(function).add("Component", "StreamProcessor")
        Tags.of(function).add("Service", "Lambda")
        
        return function

    def _get_lambda_code(self) -> str:
        """
        Get the Lambda function code for processing DynamoDB stream events
        
        Returns:
            str: Lambda function code
        """
        return '''
import json
import boto3
import logging
import os
from datetime import datetime
from typing import Dict, Any, List

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.getenv('LOG_LEVEL', 'INFO'))

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process DynamoDB stream events and trigger AppSync mutations
    for real-time data synchronization
    
    Args:
        event: DynamoDB stream event
        context: Lambda context
        
    Returns:
        Dict with processing results
    """
    
    logger.info(f"Processing {len(event['Records'])} stream records")
    
    processed_records = 0
    
    for record in event['Records']:
        try:
            event_name = record['eventName']
            
            if event_name in ['INSERT', 'MODIFY', 'REMOVE']:
                # Extract item data from stream record
                item_data = {}
                if 'NewImage' in record['dynamodb']:
                    item_data = record['dynamodb']['NewImage']
                    
                item_id = item_data.get('id', {}).get('S', 'unknown')
                
                logger.info(f"Processing {event_name} for item {item_id}")
                
                # Create change event for AppSync notification
                change_event = {
                    'eventType': event_name,
                    'itemId': item_id,
                    'timestamp': datetime.utcnow().isoformat(),
                    'newImage': item_data if 'NewImage' in record['dynamodb'] else None,
                    'oldImage': record['dynamodb'].get('OldImage')
                }
                
                # In production, this would trigger AppSync mutations
                # For demonstration, we log the change event
                logger.info(f"Change event: {json.dumps(change_event, default=str)}")
                
                # TODO: Implement AppSync mutation trigger here
                # This would involve calling AppSync API to trigger subscriptions
                
                processed_records += 1
                
        except Exception as e:
            logger.error(f"Error processing record: {str(e)}")
            # In production, you might want to send to DLQ or retry
            
    logger.info(f"Successfully processed {processed_records} records")
    
    return {
        'statusCode': 200,
        'processedRecords': processed_records,
        'totalRecords': len(event['Records'])
    }
'''

    def _create_appsync_api(self) -> appsync.GraphqlApi:
        """
        Create AppSync GraphQL API with real-time subscription capabilities
        
        Returns:
            appsync.GraphqlApi: AppSync API instance
        """
        # Create AppSync API
        api = appsync.GraphqlApi(
            self, "RealTimeSyncAPI",
            name=self.api_name,
            schema=appsync.SchemaFile.from_asset("schema.graphql"),
            authorization_config=appsync.AuthorizationConfig(
                default_authorization=appsync.AuthorizationMode(
                    authorization_type=appsync.AuthorizationType.API_KEY,
                    api_key_config=appsync.ApiKeyConfig(
                        description="Development API key for real-time sync",
                        expires=cdk.Expiration.after(Duration.days(30))
                    )
                )
            ),
            log_config=appsync.LogConfig(
                retention=logs.RetentionDays.ONE_WEEK
            ),
            xray_enabled=True
        )
        
        # Add tags
        Tags.of(api).add("Component", "GraphQLAPI")
        Tags.of(api).add("Service", "AppSync")
        
        return api

    def _create_dynamodb_data_source(self) -> appsync.DynamoDbDataSource:
        """
        Create DynamoDB data source for AppSync
        
        Returns:
            appsync.DynamoDbDataSource: DynamoDB data source
        """
        # Create service role for AppSync DynamoDB access
        service_role = iam.Role(
            self, "AppSyncDynamoDBRole",
            assumed_by=iam.ServicePrincipal("appsync.amazonaws.com"),
            inline_policies={
                "DynamoDBAccess": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "dynamodb:GetItem",
                                "dynamodb:PutItem",
                                "dynamodb:UpdateItem",
                                "dynamodb:DeleteItem",
                                "dynamodb:Query",
                                "dynamodb:Scan"
                            ],
                            resources=[self.dynamodb_table.table_arn]
                        )
                    ]
                )
            }
        )
        
        # Create DynamoDB data source
        data_source = self.appsync_api.add_dynamo_db_data_source(
            "DynamoDBDataSource",
            table=self.dynamodb_table,
            service_role=service_role
        )
        
        return data_source

    def _create_graphql_resolvers(self) -> None:
        """Create GraphQL resolvers for CRUD operations"""
        
        # Create mutation resolver for createDataItem
        self.dynamodb_data_source.create_resolver(
            "CreateDataItemResolver",
            type_name="Mutation",
            field_name="createDataItem",
            request_mapping_template=appsync.MappingTemplate.from_string('''
{
    "version": "2017-02-28",
    "operation": "PutItem",
    "key": {
        "id": $util.dynamodb.toDynamoDBJson($util.autoId())
    },
    "attributeValues": {
        "title": $util.dynamodb.toDynamoDBJson($ctx.args.input.title),
        "content": $util.dynamodb.toDynamoDBJson($ctx.args.input.content),
        "timestamp": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601()),
        "version": $util.dynamodb.toDynamoDBJson(1)
    }
}
            '''),
            response_mapping_template=appsync.MappingTemplate.from_string('''
$util.toJson($ctx.result)
            ''')
        )
        
        # Create query resolver for getDataItem
        self.dynamodb_data_source.create_resolver(
            "GetDataItemResolver",
            type_name="Query",
            field_name="getDataItem",
            request_mapping_template=appsync.MappingTemplate.from_string('''
{
    "version": "2017-02-28",
    "operation": "GetItem",
    "key": {
        "id": $util.dynamodb.toDynamoDBJson($ctx.args.id)
    }
}
            '''),
            response_mapping_template=appsync.MappingTemplate.from_string('''
$util.toJson($ctx.result)
            ''')
        )
        
        # Create query resolver for listDataItems
        self.dynamodb_data_source.create_resolver(
            "ListDataItemsResolver",
            type_name="Query",
            field_name="listDataItems",
            request_mapping_template=appsync.MappingTemplate.from_string('''
{
    "version": "2017-02-28",
    "operation": "Scan",
    "limit": $util.defaultIfNull($ctx.args.limit, 20)
}
            '''),
            response_mapping_template=appsync.MappingTemplate.from_string('''
$util.toJson($ctx.result.items)
            ''')
        )
        
        # Create mutation resolver for updateDataItem
        self.dynamodb_data_source.create_resolver(
            "UpdateDataItemResolver",
            type_name="Mutation",
            field_name="updateDataItem",
            request_mapping_template=appsync.MappingTemplate.from_string('''
{
    "version": "2017-02-28",
    "operation": "UpdateItem",
    "key": {
        "id": $util.dynamodb.toDynamoDBJson($ctx.args.input.id)
    },
    "update": {
        "expression": "SET #title = :title, #content = :content, #timestamp = :timestamp, #version = #version + :inc",
        "expressionNames": {
            "#title": "title",
            "#content": "content",
            "#timestamp": "timestamp",
            "#version": "version"
        },
        "expressionValues": {
            ":title": $util.dynamodb.toDynamoDBJson($ctx.args.input.title),
            ":content": $util.dynamodb.toDynamoDBJson($ctx.args.input.content),
            ":timestamp": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601()),
            ":inc": $util.dynamodb.toDynamoDBJson(1)
        }
    }
}
            '''),
            response_mapping_template=appsync.MappingTemplate.from_string('''
$util.toJson($ctx.result)
            ''')
        )
        
        # Create mutation resolver for deleteDataItem
        self.dynamodb_data_source.create_resolver(
            "DeleteDataItemResolver",
            type_name="Mutation",
            field_name="deleteDataItem",
            request_mapping_template=appsync.MappingTemplate.from_string('''
{
    "version": "2017-02-28",
    "operation": "DeleteItem",
    "key": {
        "id": $util.dynamodb.toDynamoDBJson($ctx.args.id)
    }
}
            '''),
            response_mapping_template=appsync.MappingTemplate.from_string('''
$util.toJson($ctx.result)
            ''')
        )

    def _add_resource_tags(self) -> None:
        """Add common tags to all resources in the stack"""
        Tags.of(self).add("Project", "AppSyncRealTimeSync")
        Tags.of(self).add("Environment", "Development")
        Tags.of(self).add("CreatedBy", "CDK")
        Tags.of(self).add("Recipe", "building-real-time-data-synchronization")

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources"""
        
        CfnOutput(
            self, "DynamoDBTableName",
            value=self.dynamodb_table.table_name,
            description="Name of the DynamoDB table"
        )
        
        CfnOutput(
            self, "DynamoDBTableArn",
            value=self.dynamodb_table.table_arn,
            description="ARN of the DynamoDB table"
        )
        
        CfnOutput(
            self, "AppSyncAPIId",
            value=self.appsync_api.api_id,
            description="AppSync GraphQL API ID"
        )
        
        CfnOutput(
            self, "AppSyncAPIURL",
            value=self.appsync_api.graphql_url,
            description="AppSync GraphQL API URL"
        )
        
        CfnOutput(
            self, "AppSyncAPIKey",
            value=self.appsync_api.api_key,
            description="AppSync API Key for authentication"
        )
        
        CfnOutput(
            self, "LambdaFunctionName",
            value=self.stream_processor.function_name,
            description="Name of the Lambda function processing DynamoDB streams"
        )
        
        CfnOutput(
            self, "LambdaFunctionArn",
            value=self.stream_processor.function_arn,
            description="ARN of the Lambda function processing DynamoDB streams"
        )


class RealTimeDataSyncApp(cdk.App):
    """CDK Application for Real-Time Data Synchronization"""

    def __init__(self):
        super().__init__()
        
        # Create the main stack
        RealTimeDataSyncStack(
            self, "RealTimeDataSyncStack",
            description="Real-Time Data Synchronization with AWS AppSync and DynamoDB Streams",
            env=cdk.Environment(
                account=os.getenv('CDK_DEFAULT_ACCOUNT'),
                region=os.getenv('CDK_DEFAULT_REGION')
            )
        )


# Create the GraphQL schema file
def create_schema_file():
    """Create the GraphQL schema file required by AppSync"""
    schema_content = '''
type DataItem {
    id: ID!
    title: String!
    content: String!
    timestamp: String!
    version: Int!
}

type Query {
    getDataItem(id: ID!): DataItem
    listDataItems(limit: Int): [DataItem]
}

type Mutation {
    createDataItem(input: CreateDataItemInput!): DataItem
    updateDataItem(input: UpdateDataItemInput!): DataItem
    deleteDataItem(id: ID!): DataItem
}

type Subscription {
    onDataItemCreated: DataItem
        @aws_subscribe(mutations: ["createDataItem"])
    onDataItemUpdated: DataItem
        @aws_subscribe(mutations: ["updateDataItem"])
    onDataItemDeleted: DataItem
        @aws_subscribe(mutations: ["deleteDataItem"])
}

input CreateDataItemInput {
    title: String!
    content: String!
}

input UpdateDataItemInput {
    id: ID!
    title: String
    content: String
}
'''
    
    with open('schema.graphql', 'w') as f:
        f.write(schema_content)


# Application entry point
if __name__ == "__main__":
    # Create schema file
    create_schema_file()
    
    # Create and run the CDK app
    app = RealTimeDataSyncApp()
    app.synth()