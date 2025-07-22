#!/usr/bin/env python3
"""
CDK Python application for Serverless Analytics with Athena Federated Query

This application creates the infrastructure needed for cross-platform analytics
using Amazon Athena with federated query capabilities across RDS MySQL and DynamoDB.
"""

import os
from aws_cdk import (
    App,
    Environment,
    Stack,
    StackProps,
    Duration,
    CfnOutput,
    RemovalPolicy,
    aws_s3 as s3,
    aws_rds as rds,
    aws_dynamodb as dynamodb,
    aws_ec2 as ec2,
    aws_athena as athena,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_secretsmanager as secretsmanager,
    aws_serverlessrepo as serverlessrepo,
    aws_cloudformation as cloudformation,
    custom_resources as cr,
)
from constructs import Construct
from typing import Dict, List, Optional


class ServerlessAnalyticsAthenaFederatedQueryStack(Stack):
    """
    CDK Stack for Serverless Analytics with Athena Federated Query
    
    This stack creates:
    - S3 buckets for spill data and query results
    - VPC and security groups for database connectivity
    - RDS MySQL instance with sample data
    - DynamoDB table with sample data
    - Lambda-based data connectors for MySQL and DynamoDB
    - Athena workgroup and data catalogs
    - Federated views for cross-source analytics
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        db_instance_class: str = "db.t3.micro",
        db_allocated_storage: int = 20,
        lambda_memory_size: int = 3008,
        lambda_timeout: int = 900,
        **kwargs
    ) -> None:
        """
        Initialize the Serverless Analytics Athena Federated Query stack
        
        Args:
            scope: The construct scope
            construct_id: The construct ID
            db_instance_class: RDS instance class for MySQL database
            db_allocated_storage: Storage size in GB for RDS instance
            lambda_memory_size: Memory allocation for Lambda connectors
            lambda_timeout: Timeout in seconds for Lambda connectors
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        # Create S3 buckets for spill data and query results
        self._create_s3_buckets()
        
        # Create VPC and networking components
        self._create_vpc_and_networking()
        
        # Create RDS MySQL instance
        self._create_rds_mysql_instance(db_instance_class, db_allocated_storage)
        
        # Create DynamoDB table
        self._create_dynamodb_table()
        
        # Deploy Lambda data connectors
        self._deploy_lambda_connectors(lambda_memory_size, lambda_timeout)
        
        # Create Athena workgroup and data catalogs
        self._create_athena_resources()
        
        # Create federated views
        self._create_federated_views()
        
        # Create outputs
        self._create_outputs()

    def _create_s3_buckets(self) -> None:
        """Create S3 buckets for spill data and query results"""
        # S3 bucket for Lambda spill data
        self.spill_bucket = s3.Bucket(
            self,
            "SpillBucket",
            bucket_name=f"athena-federated-spill-{self.account}-{self.region}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            versioning=True,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteSpillDataAfter7Days",
                    enabled=True,
                    expiration=Duration.days(7),
                    abort_incomplete_multipart_upload_after=Duration.days(1),
                )
            ],
        )

        # S3 bucket for Athena query results
        self.results_bucket = s3.Bucket(
            self,
            "ResultsBucket",
            bucket_name=f"athena-federated-results-{self.account}-{self.region}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            versioning=True,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteResultsAfter30Days",
                    enabled=True,
                    expiration=Duration.days(30),
                    abort_incomplete_multipart_upload_after=Duration.days(1),
                )
            ],
        )

    def _create_vpc_and_networking(self) -> None:
        """Create VPC and networking components for database connectivity"""
        # Create VPC
        self.vpc = ec2.Vpc(
            self,
            "AtheneFederatedVPC",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=2,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="Private",
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    cidr_mask=24,
                ),
                ec2.SubnetConfiguration(
                    name="Public",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24,
                ),
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True,
        )

        # Create security group for database access
        self.database_security_group = ec2.SecurityGroup(
            self,
            "DatabaseSecurityGroup",
            vpc=self.vpc,
            description="Security group for Athena federated query database access",
            allow_all_outbound=True,
        )

        # Allow MySQL access within the security group
        self.database_security_group.add_ingress_rule(
            peer=self.database_security_group,
            connection=ec2.Port.tcp(3306),
            description="Allow MySQL access from Lambda connectors",
        )

        # Create security group for Lambda functions
        self.lambda_security_group = ec2.SecurityGroup(
            self,
            "LambdaSecurityGroup",
            vpc=self.vpc,
            description="Security group for Lambda connector functions",
            allow_all_outbound=True,
        )

    def _create_rds_mysql_instance(self, instance_class: str, allocated_storage: int) -> None:
        """Create RDS MySQL instance with sample data"""
        # Create database credentials in Secrets Manager
        self.db_credentials = secretsmanager.Secret(
            self,
            "DatabaseCredentials",
            description="Credentials for Athena federated query MySQL database",
            generate_secret_string=secretsmanager.SecretStringGenerator(
                secret_string_template='{"username": "admin"}',
                generate_string_key="password",
                exclude_characters=" %+~`#$&*()|[]{}:;<>?!'/\"\\",
                password_length=32,
            ),
        )

        # Create DB subnet group
        self.db_subnet_group = rds.SubnetGroup(
            self,
            "DatabaseSubnetGroup",
            description="Subnet group for Athena federated query database",
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
            ),
        )

        # Create RDS MySQL instance
        self.mysql_instance = rds.DatabaseInstance(
            self,
            "MySQLInstance",
            engine=rds.DatabaseInstanceEngine.mysql(
                version=rds.MysqlEngineVersion.VER_8_0
            ),
            instance_type=ec2.InstanceType(instance_class),
            allocated_storage=allocated_storage,
            storage_type=rds.StorageType.GP2,
            database_name="analytics_db",
            credentials=rds.Credentials.from_secret(self.db_credentials),
            vpc=self.vpc,
            security_groups=[self.database_security_group],
            subnet_group=self.db_subnet_group,
            multi_az=False,
            publicly_accessible=False,
            backup_retention=Duration.days(7),
            deletion_protection=False,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Create sample data using custom resource
        self._create_sample_mysql_data()

    def _create_sample_mysql_data(self) -> None:
        """Create sample data in MySQL database using custom resource"""
        # Create Lambda function to initialize sample data
        init_data_function = lambda_.Function(
            self,
            "InitializeSampleData",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.handler",
            timeout=Duration.minutes(5),
            memory_size=512,
            vpc=self.vpc,
            security_groups=[self.lambda_security_group],
            environment={
                "DB_SECRET_ARN": self.db_credentials.secret_arn,
                "DB_ENDPOINT": self.mysql_instance.instance_endpoint.hostname,
                "DB_NAME": "analytics_db",
            },
            code=lambda_.Code.from_inline("""
import json
import boto3
import pymysql
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    try:
        # Get database credentials from Secrets Manager
        secrets_client = boto3.client('secretsmanager')
        secret_response = secrets_client.get_secret_value(
            SecretId=os.environ['DB_SECRET_ARN']
        )
        secret = json.loads(secret_response['SecretString'])
        
        # Connect to MySQL database
        connection = pymysql.connect(
            host=os.environ['DB_ENDPOINT'],
            user=secret['username'],
            password=secret['password'],
            database=os.environ['DB_NAME'],
            port=3306
        )
        
        with connection.cursor() as cursor:
            # Create sample orders table
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS sample_orders (
                    order_id INT PRIMARY KEY,
                    customer_id INT,
                    product_name VARCHAR(255),
                    quantity INT,
                    price DECIMAL(10,2),
                    order_date DATE
                )
            ''')
            
            # Insert sample data
            sample_data = [
                (1, 101, "Laptop", 1, 999.99, "2024-01-15"),
                (2, 102, "Mouse", 2, 29.99, "2024-01-16"),
                (3, 103, "Keyboard", 1, 79.99, "2024-01-17"),
                (4, 101, "Monitor", 1, 299.99, "2024-01-18"),
                (5, 104, "Headphones", 3, 149.99, "2024-01-19"),
                (6, 105, "Tablet", 1, 449.99, "2024-01-20"),
                (7, 102, "Webcam", 1, 89.99, "2024-01-21"),
                (8, 106, "Speakers", 2, 129.99, "2024-01-22"),
                (9, 103, "Printer", 1, 199.99, "2024-01-23"),
                (10, 107, "Router", 1, 79.99, "2024-01-24")
            ]
            
            cursor.executemany('''
                INSERT IGNORE INTO sample_orders 
                (order_id, customer_id, product_name, quantity, price, order_date)
                VALUES (%s, %s, %s, %s, %s, %s)
            ''', sample_data)
            
            connection.commit()
            
        logger.info("Sample data initialized successfully")
        return {
            'statusCode': 200,
            'body': json.dumps('Sample data initialized successfully')
        }
        
    except Exception as e:
        logger.error(f"Error initializing sample data: {str(e)}")
        raise e
    finally:
        if 'connection' in locals():
            connection.close()
            """),
        )

        # Grant permissions to access secrets and VPC
        self.db_credentials.grant_read(init_data_function)
        
        # Create custom resource to initialize data
        self.sample_data_provider = cr.Provider(
            self,
            "SampleDataProvider",
            on_event_handler=init_data_function,
        )

        self.sample_data_custom_resource = cr.CustomResource(
            self,
            "SampleDataCustomResource",
            service_token=self.sample_data_provider.service_token,
            properties={
                "Trigger": self.mysql_instance.instance_endpoint.hostname,
            },
        )

        # Ensure the custom resource runs after the database is available
        self.sample_data_custom_resource.node.add_dependency(self.mysql_instance)

    def _create_dynamodb_table(self) -> None:
        """Create DynamoDB table with sample data"""
        # Create DynamoDB table
        self.dynamodb_table = dynamodb.Table(
            self,
            "OrdersTable",
            table_name=f"Orders-{self.account}-{self.region}",
            partition_key=dynamodb.Attribute(
                name="order_id",
                type=dynamodb.AttributeType.STRING,
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            encryption=dynamodb.TableEncryption.AWS_MANAGED,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
        )

        # Create Lambda function to populate sample data
        populate_dynamodb_function = lambda_.Function(
            self,
            "PopulateDynamoDBData",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.handler",
            timeout=Duration.minutes(2),
            memory_size=256,
            environment={
                "TABLE_NAME": self.dynamodb_table.table_name,
            },
            code=lambda_.Code.from_inline("""
import json
import boto3
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    try:
        dynamodb = boto3.resource('dynamodb')
        table = dynamodb.Table(os.environ['TABLE_NAME'])
        
        # Sample order tracking data
        sample_data = [
            {"order_id": "1001", "status": "shipped", "tracking_number": "TRK123456", "carrier": "FedEx"},
            {"order_id": "1002", "status": "processing", "tracking_number": "TRK789012", "carrier": "UPS"},
            {"order_id": "1003", "status": "delivered", "tracking_number": "TRK345678", "carrier": "USPS"},
            {"order_id": "1004", "status": "shipped", "tracking_number": "TRK901234", "carrier": "DHL"},
            {"order_id": "1005", "status": "processing", "tracking_number": "TRK567890", "carrier": "FedEx"},
            {"order_id": "1", "status": "delivered", "tracking_number": "TRK111111", "carrier": "UPS"},
            {"order_id": "2", "status": "shipped", "tracking_number": "TRK222222", "carrier": "FedEx"},
            {"order_id": "3", "status": "processing", "tracking_number": "TRK333333", "carrier": "USPS"},
            {"order_id": "4", "status": "delivered", "tracking_number": "TRK444444", "carrier": "DHL"},
            {"order_id": "5", "status": "shipped", "tracking_number": "TRK555555", "carrier": "UPS"}
        ]
        
        # Insert sample data
        for item in sample_data:
            table.put_item(Item=item)
            
        logger.info("DynamoDB sample data populated successfully")
        return {
            'statusCode': 200,
            'body': json.dumps('DynamoDB sample data populated successfully')
        }
        
    except Exception as e:
        logger.error(f"Error populating DynamoDB data: {str(e)}")
        raise e
            """),
        )

        # Grant permissions to write to DynamoDB table
        self.dynamodb_table.grant_write_data(populate_dynamodb_function)

        # Create custom resource to populate data
        self.dynamodb_data_provider = cr.Provider(
            self,
            "DynamoDBDataProvider",
            on_event_handler=populate_dynamodb_function,
        )

        self.dynamodb_data_custom_resource = cr.CustomResource(
            self,
            "DynamoDBDataCustomResource",
            service_token=self.dynamodb_data_provider.service_token,
            properties={
                "Trigger": self.dynamodb_table.table_name,
            },
        )

        # Ensure the custom resource runs after the table is created
        self.dynamodb_data_custom_resource.node.add_dependency(self.dynamodb_table)

    def _deploy_lambda_connectors(self, memory_size: int, timeout: int) -> None:
        """Deploy Lambda-based data connectors for MySQL and DynamoDB"""
        # Create IAM role for Lambda connectors
        self.connector_role = iam.Role(
            self,
            "ConnectorRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaVPCAccessExecutionRole"
                )
            ],
        )

        # Add permissions for connectors
        self.connector_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:DeleteObject",
                    "s3:ListBucket",
                ],
                resources=[
                    self.spill_bucket.bucket_arn,
                    f"{self.spill_bucket.bucket_arn}/*",
                ],
            )
        )

        # MySQL connector specific permissions
        self.connector_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "secretsmanager:GetSecretValue",
                    "secretsmanager:DescribeSecret",
                ],
                resources=[self.db_credentials.secret_arn],
            )
        )

        # DynamoDB connector specific permissions
        self.connector_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "dynamodb:DescribeTable",
                    "dynamodb:ListTables",
                    "dynamodb:Query",
                    "dynamodb:Scan",
                    "dynamodb:GetItem",
                    "dynamodb:BatchGetItem",
                ],
                resources=[self.dynamodb_table.table_arn],
            )
        )

        # Deploy MySQL connector using CloudFormation stack
        self.mysql_connector_stack = cloudformation.CfnStack(
            self,
            "MySQLConnectorStack",
            template_url="https://s3.amazonaws.com/athena-downloads/drivers/JDBC/SimbaAthenaJDBC-2.0.32.1000/AthenaMySQLConnector.yaml",
            parameters={
                "LambdaFunctionName": "athena-mysql-connector",
                "DefaultConnectionString": f"mysql://jdbc:mysql://{self.mysql_instance.instance_endpoint.hostname}:3306/analytics_db?user=admin&password=${{admin}}",
                "SpillBucket": self.spill_bucket.bucket_name,
                "LambdaMemory": str(memory_size),
                "LambdaTimeout": str(timeout),
                "SecurityGroupIds": self.lambda_security_group.security_group_id,
                "SubnetIds": ",".join([subnet.subnet_id for subnet in self.vpc.private_subnets]),
            },
            timeout_in_minutes=10,
        )

        # Deploy DynamoDB connector using CloudFormation stack
        self.dynamodb_connector_stack = cloudformation.CfnStack(
            self,
            "DynamoDBConnectorStack",
            template_url="https://s3.amazonaws.com/athena-downloads/drivers/JDBC/SimbaAthenaJDBC-2.0.32.1000/AthenaDynamoDBConnector.yaml",
            parameters={
                "LambdaFunctionName": "athena-dynamodb-connector",
                "SpillBucket": self.spill_bucket.bucket_name,
                "LambdaMemory": str(memory_size),
                "LambdaTimeout": str(timeout),
            },
            timeout_in_minutes=10,
        )

    def _create_athena_resources(self) -> None:
        """Create Athena workgroup and data catalogs"""
        # Create Athena workgroup
        self.athena_workgroup = athena.CfnWorkGroup(
            self,
            "FederatedAnalyticsWorkGroup",
            name="federated-analytics",
            description="Workgroup for federated query analytics",
            state="ENABLED",
            work_group_configuration=athena.CfnWorkGroup.WorkGroupConfigurationProperty(
                enforce_work_group_configuration=True,
                publish_cloud_watch_metrics=True,
                result_configuration=athena.CfnWorkGroup.ResultConfigurationProperty(
                    output_location=f"s3://{self.results_bucket.bucket_name}/",
                    encryption_configuration=athena.CfnWorkGroup.EncryptionConfigurationProperty(
                        encryption_option="SSE_S3"
                    ),
                ),
                bytes_scanned_cutoff_per_query=1000000000,  # 1GB limit
            ),
        )

        # Create MySQL data catalog
        self.mysql_data_catalog = athena.CfnDataCatalog(
            self,
            "MySQLDataCatalog",
            name="mysql_catalog",
            description="MySQL data source for federated queries",
            type="LAMBDA",
            parameters={
                "function": f"arn:aws:lambda:{self.region}:{self.account}:function:athena-mysql-connector",
            },
        )

        # Create DynamoDB data catalog
        self.dynamodb_data_catalog = athena.CfnDataCatalog(
            self,
            "DynamoDBDataCatalog",
            name="dynamodb_catalog",
            description="DynamoDB data source for federated queries",
            type="LAMBDA",
            parameters={
                "function": f"arn:aws:lambda:{self.region}:{self.account}:function:athena-dynamodb-connector",
            },
        )

        # Ensure connectors are deployed before creating catalogs
        self.mysql_data_catalog.node.add_dependency(self.mysql_connector_stack)
        self.dynamodb_data_catalog.node.add_dependency(self.dynamodb_connector_stack)

    def _create_federated_views(self) -> None:
        """Create federated views for cross-source analytics"""
        # Create Lambda function to create federated views
        create_views_function = lambda_.Function(
            self,
            "CreateFederatedViews",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.handler",
            timeout=Duration.minutes(5),
            memory_size=256,
            environment={
                "WORKGROUP": self.athena_workgroup.name,
                "RESULTS_BUCKET": self.results_bucket.bucket_name,
                "MYSQL_CATALOG": self.mysql_data_catalog.name,
                "DYNAMODB_CATALOG": self.dynamodb_data_catalog.name,
                "DYNAMODB_TABLE": self.dynamodb_table.table_name,
            },
            code=lambda_.Code.from_inline("""
import json
import boto3
import logging
import os
import time

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    try:
        athena = boto3.client('athena')
        
        # Create federated view query
        view_query = f'''
        CREATE OR REPLACE VIEW default.order_analytics AS
        SELECT 
            mysql_orders.order_id,
            mysql_orders.customer_id,
            mysql_orders.product_name,
            mysql_orders.quantity,
            mysql_orders.price,
            mysql_orders.order_date,
            COALESCE(ddb_tracking.status, 'pending') as shipment_status,
            ddb_tracking.tracking_number,
            ddb_tracking.carrier,
            (mysql_orders.quantity * mysql_orders.price) as total_amount
        FROM {os.environ['MYSQL_CATALOG']}.analytics_db.sample_orders mysql_orders
        LEFT JOIN {os.environ['DYNAMODB_CATALOG']}.default.{os.environ['DYNAMODB_TABLE']} ddb_tracking
        ON CAST(mysql_orders.order_id AS VARCHAR) = ddb_tracking.order_id
        '''
        
        # Execute query
        response = athena.start_query_execution(
            QueryString=view_query,
            WorkGroup=os.environ['WORKGROUP'],
            ResultConfiguration={
                'OutputLocation': f"s3://{os.environ['RESULTS_BUCKET']}/views/"
            }
        )
        
        query_execution_id = response['QueryExecutionId']
        
        # Wait for query to complete
        while True:
            query_status = athena.get_query_execution(
                QueryExecutionId=query_execution_id
            )
            
            status = query_status['QueryExecution']['Status']['State']
            
            if status in ['SUCCEEDED', 'FAILED', 'CANCELLED']:
                break
                
            time.sleep(2)
        
        if status == 'SUCCEEDED':
            logger.info("Federated view created successfully")
            return {
                'statusCode': 200,
                'body': json.dumps('Federated view created successfully')
            }
        else:
            error_message = query_status['QueryExecution']['Status'].get('StateChangeReason', 'Unknown error')
            logger.error(f"Query failed: {error_message}")
            raise Exception(f"Query failed: {error_message}")
            
    except Exception as e:
        logger.error(f"Error creating federated views: {str(e)}")
        raise e
            """),
        )

        # Grant permissions to execute Athena queries
        create_views_function.add_to_role_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "athena:StartQueryExecution",
                    "athena:GetQueryExecution",
                    "athena:GetQueryResults",
                    "athena:StopQueryExecution",
                ],
                resources=[
                    f"arn:aws:athena:{self.region}:{self.account}:workgroup/{self.athena_workgroup.name}",
                ],
            )
        )

        # Grant permissions to write to results bucket
        self.results_bucket.grant_write(create_views_function)

        # Grant permissions to access Glue Data Catalog
        create_views_function.add_to_role_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "glue:CreateTable",
                    "glue:GetTable",
                    "glue:GetTables",
                    "glue:UpdateTable",
                    "glue:DeleteTable",
                    "glue:GetDatabase",
                    "glue:GetDatabases",
                    "glue:CreateDatabase",
                ],
                resources=["*"],
            )
        )

        # Create custom resource to create views
        self.views_provider = cr.Provider(
            self,
            "ViewsProvider",
            on_event_handler=create_views_function,
        )

        self.views_custom_resource = cr.CustomResource(
            self,
            "ViewsCustomResource",
            service_token=self.views_provider.service_token,
            properties={
                "Trigger": f"{self.mysql_data_catalog.name}-{self.dynamodb_data_catalog.name}",
            },
        )

        # Ensure views are created after catalogs and data
        self.views_custom_resource.node.add_dependency(self.mysql_data_catalog)
        self.views_custom_resource.node.add_dependency(self.dynamodb_data_catalog)
        self.views_custom_resource.node.add_dependency(self.sample_data_custom_resource)
        self.views_custom_resource.node.add_dependency(self.dynamodb_data_custom_resource)

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources"""
        CfnOutput(
            self,
            "SpillBucketName",
            value=self.spill_bucket.bucket_name,
            description="S3 bucket for Lambda spill data",
        )

        CfnOutput(
            self,
            "ResultsBucketName",
            value=self.results_bucket.bucket_name,
            description="S3 bucket for Athena query results",
        )

        CfnOutput(
            self,
            "MySQLEndpoint",
            value=self.mysql_instance.instance_endpoint.hostname,
            description="RDS MySQL instance endpoint",
        )

        CfnOutput(
            self,
            "DynamoDBTableName",
            value=self.dynamodb_table.table_name,
            description="DynamoDB table name for order tracking",
        )

        CfnOutput(
            self,
            "AthenaWorkGroupName",
            value=self.athena_workgroup.name,
            description="Athena workgroup for federated queries",
        )

        CfnOutput(
            self,
            "MySQLCatalogName",
            value=self.mysql_data_catalog.name,
            description="MySQL data catalog name",
        )

        CfnOutput(
            self,
            "DynamoDBCatalogName",
            value=self.dynamodb_data_catalog.name,
            description="DynamoDB data catalog name",
        )

        CfnOutput(
            self,
            "SampleFederatedQuery",
            value=f"SELECT * FROM {self.mysql_data_catalog.name}.analytics_db.sample_orders LIMIT 10",
            description="Sample federated query to test MySQL connectivity",
        )

        CfnOutput(
            self,
            "FederatedViewQuery",
            value="SELECT * FROM default.order_analytics ORDER BY order_date DESC",
            description="Query to access the federated view combining MySQL and DynamoDB data",
        )


def main() -> None:
    """Main function to create and deploy the CDK application"""
    app = App()

    # Get environment configuration
    env = Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT", os.environ.get("AWS_ACCOUNT_ID")),
        region=os.environ.get("CDK_DEFAULT_REGION", os.environ.get("AWS_REGION", "us-east-1")),
    )

    # Create the main stack
    ServerlessAnalyticsAthenaFederatedQueryStack(
        app,
        "ServerlessAnalyticsAthenaFederatedQueryStack",
        env=env,
        description="CDK stack for Serverless Analytics with Athena Federated Query across RDS MySQL and DynamoDB",
        # Customize these parameters as needed
        db_instance_class="db.t3.micro",
        db_allocated_storage=20,
        lambda_memory_size=3008,
        lambda_timeout=900,
    )

    # Synthesize the application
    app.synth()


if __name__ == "__main__":
    main()