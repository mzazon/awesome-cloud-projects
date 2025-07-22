#!/usr/bin/env python3
"""
CDK Application for Operational Analytics with Amazon Redshift Spectrum

This application creates a complete data analytics infrastructure using:
- Amazon Redshift cluster with Spectrum capabilities
- S3 data lake with sample operational data
- AWS Glue Data Catalog for schema management
- IAM roles and policies for secure access
"""

import os
from aws_cdk import (
    App,
    Stack,
    Environment,
    CfnOutput,
    Duration,
    RemovalPolicy,
    aws_redshift as redshift,
    aws_s3 as s3,
    aws_s3_deployment as s3_deployment,
    aws_glue as glue,
    aws_iam as iam,
    aws_ec2 as ec2,
)
from constructs import Construct
from typing import Dict, Any


class OperationalAnalyticsStack(Stack):
    """
    CDK Stack for operational analytics with Redshift Spectrum.
    
    This stack creates:
    - S3 data lake with partitioned structure
    - Redshift cluster configured for Spectrum
    - Glue Data Catalog and crawlers
    - IAM roles with least privilege access
    - Sample operational data for testing
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        **kwargs: Any
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create unique suffix for resource naming
        unique_suffix = self.node.try_get_context("unique_suffix") or "demo"
        
        # Define resource names with unique suffix
        self.data_lake_bucket_name = f"spectrum-data-lake-{unique_suffix}"
        self.redshift_cluster_name = f"spectrum-cluster-{unique_suffix}"
        self.glue_database_name = f"spectrum_db_{unique_suffix.replace('-', '_')}"
        
        # Create VPC for Redshift cluster
        self.vpc = self._create_vpc()
        
        # Create S3 data lake
        self.data_lake_bucket = self._create_data_lake()
        
        # Create IAM role for Redshift Spectrum
        self.redshift_spectrum_role = self._create_redshift_spectrum_role()
        
        # Create Glue database and role
        self.glue_role = self._create_glue_role()
        self.glue_database = self._create_glue_database()
        
        # Create Redshift cluster
        self.redshift_cluster = self._create_redshift_cluster()
        
        # Create Glue crawlers
        self._create_glue_crawlers()
        
        # Deploy sample data
        self._deploy_sample_data()
        
        # Create outputs
        self._create_outputs()

    def _create_vpc(self) -> ec2.Vpc:
        """
        Create VPC for Redshift cluster with proper security configuration.
        
        Returns:
            ec2.Vpc: The created VPC with public and private subnets
        """
        vpc = ec2.Vpc(
            self,
            "SpectrumVPC",
            max_azs=2,
            nat_gateways=1,
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
        
        return vpc

    def _create_data_lake(self) -> s3.Bucket:
        """
        Create S3 bucket for data lake with proper configuration.
        
        Returns:
            s3.Bucket: The created S3 bucket with versioning and encryption
        """
        bucket = s3.Bucket(
            self,
            "DataLakeBucket",
            bucket_name=self.data_lake_bucket_name,
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )
        
        return bucket

    def _create_redshift_spectrum_role(self) -> iam.Role:
        """
        Create IAM role for Redshift Spectrum with necessary permissions.
        
        Returns:
            iam.Role: IAM role that Redshift can assume to access S3 and Glue
        """
        role = iam.Role(
            self,
            "RedshiftSpectrumRole",
            assumed_by=iam.ServicePrincipal("redshift.amazonaws.com"),
            description="IAM role for Redshift Spectrum to access S3 and Glue",
        )
        
        # Add permissions for S3 data lake access
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:ListBucket",
                    "s3:GetBucketLocation",
                ],
                resources=[
                    self.data_lake_bucket.bucket_arn,
                    f"{self.data_lake_bucket.bucket_arn}/*",
                ],
            )
        )
        
        # Add permissions for Glue Data Catalog access
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "glue:GetDatabase",
                    "glue:GetDatabases",
                    "glue:GetTable",
                    "glue:GetTables",
                    "glue:GetPartition",
                    "glue:GetPartitions",
                ],
                resources=["*"],
            )
        )
        
        return role

    def _create_glue_role(self) -> iam.Role:
        """
        Create IAM role for Glue crawlers with necessary permissions.
        
        Returns:
            iam.Role: IAM role that Glue crawlers can assume
        """
        role = iam.Role(
            self,
            "GlueSpectrumRole",
            assumed_by=iam.ServicePrincipal("glue.amazonaws.com"),
            description="IAM role for Glue crawlers to discover S3 data schemas",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSGlueServiceRole"
                )
            ],
        )
        
        # Add permissions for S3 data lake access
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:ListBucket",
                    "s3:GetBucketLocation",
                ],
                resources=[
                    self.data_lake_bucket.bucket_arn,
                    f"{self.data_lake_bucket.bucket_arn}/*",
                ],
            )
        )
        
        return role

    def _create_glue_database(self) -> glue.CfnDatabase:
        """
        Create Glue database for Spectrum table metadata.
        
        Returns:
            glue.CfnDatabase: The created Glue database
        """
        database = glue.CfnDatabase(
            self,
            "SpectrumGlueDatabase",
            catalog_id=self.account,
            database_input=glue.CfnDatabase.DatabaseInputProperty(
                name=self.glue_database_name,
                description="Database for Redshift Spectrum operational analytics",
            ),
        )
        
        return database

    def _create_redshift_cluster(self) -> redshift.Cluster:
        """
        Create Redshift cluster with Spectrum capabilities.
        
        Returns:
            redshift.Cluster: The created Redshift cluster
        """
        # Create security group for Redshift
        security_group = ec2.SecurityGroup(
            self,
            "RedshiftSecurityGroup",
            vpc=self.vpc,
            description="Security group for Redshift cluster",
            allow_all_outbound=True,
        )
        
        # Allow inbound connections on Redshift port
        security_group.add_ingress_rule(
            peer=ec2.Peer.ipv4(self.vpc.vpc_cidr_block),
            connection=ec2.Port.tcp(5439),
            description="Allow Redshift connections from VPC",
        )
        
        # Create subnet group for Redshift
        subnet_group = redshift.ClusterSubnetGroup(
            self,
            "RedshiftSubnetGroup",
            description="Subnet group for Redshift cluster",
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
            ),
        )
        
        # Create Redshift cluster
        cluster = redshift.Cluster(
            self,
            "RedshiftCluster",
            cluster_name=self.redshift_cluster_name,
            master_user=redshift.Login(
                master_username="admin",
                # In production, use AWS Secrets Manager for password
                master_password="TempPassword123!",
            ),
            vpc=self.vpc,
            security_groups=[security_group],
            subnet_group=subnet_group,
            cluster_type=redshift.ClusterType.SINGLE_NODE,
            node_type=redshift.NodeType.DC2_LARGE,
            default_database_name="analytics",
            publicly_accessible=False,
            roles=[self.redshift_spectrum_role],
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        return cluster

    def _create_glue_crawlers(self) -> None:
        """Create Glue crawlers for automatic schema discovery."""
        
        # Crawler for sales data
        sales_crawler = glue.CfnCrawler(
            self,
            "SalesCrawler",
            name=f"sales-crawler-{self.node.addr[-8:]}",
            role=self.glue_role.role_arn,
            database_name=self.glue_database_name,
            targets=glue.CfnCrawler.TargetsProperty(
                s3_targets=[
                    glue.CfnCrawler.S3TargetProperty(
                        path=f"s3://{self.data_lake_bucket_name}/operational-data/sales/"
                    )
                ]
            ),
            description="Crawler for sales transaction data",
        )
        
        # Crawler depends on Glue database
        sales_crawler.add_dependency(self.glue_database)
        
        # Crawler for customer data
        customers_crawler = glue.CfnCrawler(
            self,
            "CustomersCrawler",
            name=f"customers-crawler-{self.node.addr[-8:]}",
            role=self.glue_role.role_arn,
            database_name=self.glue_database_name,
            targets=glue.CfnCrawler.TargetsProperty(
                s3_targets=[
                    glue.CfnCrawler.S3TargetProperty(
                        path=f"s3://{self.data_lake_bucket_name}/operational-data/customers/"
                    )
                ]
            ),
            description="Crawler for customer profile data",
        )
        
        # Crawler depends on Glue database
        customers_crawler.add_dependency(self.glue_database)
        
        # Crawler for product data
        products_crawler = glue.CfnCrawler(
            self,
            "ProductsCrawler",
            name=f"products-crawler-{self.node.addr[-8:]}",
            role=self.glue_role.role_arn,
            database_name=self.glue_database_name,
            targets=glue.CfnCrawler.TargetsProperty(
                s3_targets=[
                    glue.CfnCrawler.S3TargetProperty(
                        path=f"s3://{self.data_lake_bucket_name}/operational-data/products/"
                    )
                ]
            ),
            description="Crawler for product catalog data",
        )
        
        # Crawler depends on Glue database
        products_crawler.add_dependency(self.glue_database)

    def _deploy_sample_data(self) -> None:
        """Deploy sample operational data to S3 data lake."""
        
        # Create local assets for sample data
        s3_deployment.BucketDeployment(
            self,
            "SampleDataDeployment",
            sources=[
                s3_deployment.Source.data(
                    "operational-data/sales/year=2024/month=01/sales_transactions.csv",
                    "transaction_id,customer_id,product_id,quantity,unit_price,transaction_date,store_id,region,payment_method\n"
                    "TXN001,CUST001,PROD001,2,29.99,2024-01-15,STORE001,North,credit_card\n"
                    "TXN002,CUST002,PROD002,1,199.99,2024-01-15,STORE002,South,debit_card\n"
                    "TXN003,CUST003,PROD003,3,15.50,2024-01-16,STORE001,North,cash\n"
                    "TXN004,CUST001,PROD004,1,89.99,2024-01-16,STORE003,East,credit_card\n"
                    "TXN005,CUST004,PROD001,2,29.99,2024-01-17,STORE002,South,credit_card"
                ),
                s3_deployment.Source.data(
                    "operational-data/customers/customers.csv",
                    "customer_id,first_name,last_name,email,phone,registration_date,tier,city,state\n"
                    "CUST001,John,Doe,john.doe@email.com,555-0101,2023-01-15,premium,New York,NY\n"
                    "CUST002,Jane,Smith,jane.smith@email.com,555-0102,2023-02-20,standard,Los Angeles,CA\n"
                    "CUST003,Bob,Johnson,bob.johnson@email.com,555-0103,2023-03-10,standard,Chicago,IL\n"
                    "CUST004,Alice,Brown,alice.brown@email.com,555-0104,2023-04-05,premium,Miami,FL\n"
                    "CUST005,Charlie,Wilson,charlie.wilson@email.com,555-0105,2023-05-12,standard,Seattle,WA"
                ),
                s3_deployment.Source.data(
                    "operational-data/products/products.csv",
                    "product_id,product_name,category,brand,cost,retail_price,supplier_id\n"
                    "PROD001,Wireless Headphones,Electronics,TechBrand,20.00,29.99,SUP001\n"
                    "PROD002,Smart Watch,Electronics,TechBrand,120.00,199.99,SUP001\n"
                    "PROD003,Coffee Mug,Home,HomeBrand,8.00,15.50,SUP002\n"
                    "PROD004,Bluetooth Speaker,Electronics,AudioMax,50.00,89.99,SUP003\n"
                    "PROD005,Desk Lamp,Home,HomeBrand,25.00,45.00,SUP002"
                ),
            ],
            destination_bucket=self.data_lake_bucket,
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        
        CfnOutput(
            self,
            "DataLakeBucketName",
            value=self.data_lake_bucket.bucket_name,
            description="S3 bucket name for the data lake",
        )
        
        CfnOutput(
            self,
            "RedshiftClusterEndpoint",
            value=self.redshift_cluster.cluster_endpoint.hostname,
            description="Redshift cluster endpoint for connections",
        )
        
        CfnOutput(
            self,
            "RedshiftClusterName",
            value=self.redshift_cluster_name,
            description="Redshift cluster identifier",
        )
        
        CfnOutput(
            self,
            "GlueDatabaseName",
            value=self.glue_database_name,
            description="Glue database name for Spectrum external schema",
        )
        
        CfnOutput(
            self,
            "RedshiftSpectrumRoleArn",
            value=self.redshift_spectrum_role.role_arn,
            description="IAM role ARN for Redshift Spectrum access",
        )
        
        CfnOutput(
            self,
            "ConnectionString",
            value=f"postgresql://admin:TempPassword123!@{self.redshift_cluster.cluster_endpoint.hostname}:5439/analytics",
            description="Connection string for Redshift cluster (change password in production)",
        )


app = App()

# Create the operational analytics stack
OperationalAnalyticsStack(
    app,
    "OperationalAnalyticsStack",
    env=Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
        region=os.environ.get("CDK_DEFAULT_REGION"),
    ),
    description="Operational analytics infrastructure with Amazon Redshift Spectrum",
)

app.synth()