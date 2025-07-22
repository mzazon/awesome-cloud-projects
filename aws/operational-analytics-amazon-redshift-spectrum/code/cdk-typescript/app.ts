#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { 
  Stack, 
  StackProps, 
  RemovalPolicy, 
  CfnOutput, 
  Duration 
} from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as redshift from 'aws-cdk-lib/aws-redshift';
import * as glue from 'aws-cdk-lib/aws-glue';
import * as ec2 from 'aws-cdk-lib/aws-ec2';

/**
 * Properties for the Operational Analytics Stack
 */
interface OperationalAnalyticsStackProps extends StackProps {
  /**
   * Prefix for resource names to ensure uniqueness
   */
  readonly resourcePrefix?: string;
  
  /**
   * Master username for Redshift cluster
   * @default 'admin'
   */
  readonly masterUsername?: string;
  
  /**
   * Redshift cluster node type
   * @default 'dc2.large'
   */
  readonly nodeType?: string;
  
  /**
   * Whether the Redshift cluster should be publicly accessible
   * @default true
   */
  readonly publiclyAccessible?: boolean;
  
  /**
   * Database name for the Redshift cluster
   * @default 'analytics'
   */
  readonly databaseName?: string;
}

/**
 * AWS CDK Stack for Operational Analytics with Amazon Redshift Spectrum
 * 
 * This stack creates:
 * - S3 data lake bucket with sample operational data
 * - IAM roles for Redshift Spectrum and Glue operations
 * - AWS Glue Data Catalog database and crawlers
 * - Amazon Redshift cluster with Spectrum capabilities
 * - VPC and security groups for secure access
 */
export class OperationalAnalyticsStack extends Stack {
  
  // Core infrastructure components
  public readonly dataLakeBucket: s3.Bucket;
  public readonly redshiftCluster: redshift.Cluster;
  public readonly glueDatabase: glue.CfnDatabase;
  public readonly spectrumRole: iam.Role;
  public readonly glueRole: iam.Role;
  public readonly vpc: ec2.Vpc;
  
  constructor(scope: Construct, id: string, props: OperationalAnalyticsStackProps = {}) {
    super(scope, id, props);
    
    // Generate unique resource suffix for naming
    const resourceSuffix = props.resourcePrefix || this.generateUniqueId();
    
    // Default configuration values
    const masterUsername = props.masterUsername || 'admin';
    const nodeType = props.nodeType || 'dc2.large';
    const publiclyAccessible = props.publiclyAccessible ?? true;
    const databaseName = props.databaseName || 'analytics';
    
    // Create VPC for Redshift cluster with proper networking
    this.vpc = this.createVpc();
    
    // Create S3 data lake infrastructure
    this.dataLakeBucket = this.createDataLakeBucket(resourceSuffix);
    
    // Create IAM roles for service integration
    this.spectrumRole = this.createRedshiftSpectrumRole(resourceSuffix);
    this.glueRole = this.createGlueServiceRole(resourceSuffix);
    
    // Set up AWS Glue Data Catalog
    this.glueDatabase = this.createGlueDatabase(resourceSuffix);
    this.createGlueCrawlers(resourceSuffix);
    
    // Create Redshift cluster with Spectrum capabilities
    this.redshiftCluster = this.createRedshiftCluster({
      resourceSuffix,
      masterUsername,
      nodeType,
      publiclyAccessible,
      databaseName
    });
    
    // Deploy sample operational data to S3
    this.deploySampleData();
    
    // Generate stack outputs for easy access
    this.createOutputs();
  }
  
  /**
   * Creates a VPC with public and private subnets for Redshift deployment
   */
  private createVpc(): ec2.Vpc {
    return new ec2.Vpc(this, 'SpectrumVpc', {
      maxAzs: 2,
      natGateways: 1,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'Public',
          subnetType: ec2.SubnetType.PUBLIC,
        },
        {
          cidrMask: 24,
          name: 'Private',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
        }
      ],
      enableDnsHostnames: true,
      enableDnsSupport: true,
    });
  }
  
  /**
   * Creates S3 bucket for data lake storage with proper configuration
   */
  private createDataLakeBucket(resourceSuffix: string): s3.Bucket {
    const bucket = new s3.Bucket(this, 'DataLakeBucket', {
      bucketName: `spectrum-data-lake-${resourceSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [
        {
          // Transition to IA after 30 days for cost optimization
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: Duration.days(30),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: Duration.days(90),
            }
          ],
        }
      ],
    });
    
    // Add bucket notification configuration for future streaming integrations
    bucket.addToResourcePolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      principals: [new iam.ServicePrincipal('glue.amazonaws.com')],
      actions: ['s3:GetObject', 's3:ListBucket'],
      resources: [bucket.bucketArn, `${bucket.bucketArn}/*`],
    }));
    
    return bucket;
  }
  
  /**
   * Creates IAM role for Redshift Spectrum with necessary permissions
   */
  private createRedshiftSpectrumRole(resourceSuffix: string): iam.Role {
    const role = new iam.Role(this, 'RedshiftSpectrumRole', {
      roleName: `RedshiftSpectrumRole-${resourceSuffix}`,
      assumedBy: new iam.ServicePrincipal('redshift.amazonaws.com'),
      description: 'IAM role for Redshift Spectrum to access S3 and Glue catalog',
    });
    
    // Add managed policy for Redshift service
    role.addManagedPolicy(
      iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonRedshiftServiceLinkedRolePolicy')
    );
    
    // Custom policy for S3 and Glue access
    const spectrumPolicy = new iam.PolicyDocument({
      statements: [
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            's3:GetObject',
            's3:ListBucket',
            's3:GetBucketLocation'
          ],
          resources: [
            this.dataLakeBucket.bucketArn,
            `${this.dataLakeBucket.bucketArn}/*`
          ],
        }),
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'glue:GetDatabase',
            'glue:GetDatabases',
            'glue:GetTable',
            'glue:GetTables',
            'glue:GetPartition',
            'glue:GetPartitions',
            'glue:BatchCreatePartition',
            'glue:BatchUpdatePartition',
            'glue:BatchDeletePartition'
          ],
          resources: ['*'],
        }),
      ],
    });
    
    role.attachInlinePolicy(new iam.Policy(this, 'SpectrumInlinePolicy', {
      document: spectrumPolicy,
    }));
    
    return role;
  }
  
  /**
   * Creates IAM role for AWS Glue service operations
   */
  private createGlueServiceRole(resourceSuffix: string): iam.Role {
    const role = new iam.Role(this, 'GlueServiceRole', {
      roleName: `GlueSpectrumRole-${resourceSuffix}`,
      assumedBy: new iam.ServicePrincipal('glue.amazonaws.com'),
      description: 'IAM role for AWS Glue to crawl S3 data and populate catalog',
    });
    
    // Add AWS managed policy for Glue service
    role.addManagedPolicy(
      iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSGlueServiceRole')
    );
    
    // Grant access to the data lake bucket
    this.dataLakeBucket.grantRead(role);
    
    return role;
  }
  
  /**
   * Creates AWS Glue database for metadata catalog
   */
  private createGlueDatabase(resourceSuffix: string): glue.CfnDatabase {
    return new glue.CfnDatabase(this, 'GlueDatabase', {
      catalogId: this.account,
      databaseInput: {
        name: `spectrum_db_${resourceSuffix}`,
        description: 'Database for Redshift Spectrum operational analytics',
      },
    });
  }
  
  /**
   * Creates Glue crawlers for automated schema discovery
   */
  private createGlueCrawlers(resourceSuffix: string): void {
    // Sales data crawler
    new glue.CfnCrawler(this, 'SalesCrawler', {
      name: `sales-crawler-${resourceSuffix}`,
      role: this.glueRole.roleArn,
      databaseName: this.glueDatabase.ref,
      targets: {
        s3Targets: [
          {
            path: `s3://${this.dataLakeBucket.bucketName}/operational-data/sales/`,
          },
        ],
      },
      description: 'Crawler for sales transaction data',
      schemaChangePolicy: {
        updateBehavior: 'UPDATE_IN_DATABASE',
        deleteBehavior: 'LOG',
      },
    });
    
    // Customer data crawler
    new glue.CfnCrawler(this, 'CustomersCrawler', {
      name: `customers-crawler-${resourceSuffix}`,
      role: this.glueRole.roleArn,
      databaseName: this.glueDatabase.ref,
      targets: {
        s3Targets: [
          {
            path: `s3://${this.dataLakeBucket.bucketName}/operational-data/customers/`,
          },
        ],
      },
      description: 'Crawler for customer profile data',
      schemaChangePolicy: {
        updateBehavior: 'UPDATE_IN_DATABASE',
        deleteBehavior: 'LOG',
      },
    });
    
    // Products data crawler
    new glue.CfnCrawler(this, 'ProductsCrawler', {
      name: `products-crawler-${resourceSuffix}`,
      role: this.glueRole.roleArn,
      databaseName: this.glueDatabase.ref,
      targets: {
        s3Targets: [
          {
            path: `s3://${this.dataLakeBucket.bucketName}/operational-data/products/`,
          },
        ],
      },
      description: 'Crawler for product catalog data',
      schemaChangePolicy: {
        updateBehavior: 'UPDATE_IN_DATABASE',
        deleteBehavior: 'LOG',
      },
    });
  }
  
  /**
   * Creates Redshift cluster with Spectrum configuration
   */
  private createRedshiftCluster(config: {
    resourceSuffix: string;
    masterUsername: string;
    nodeType: string;
    publiclyAccessible: boolean;
    databaseName: string;
  }): redshift.Cluster {
    
    // Create subnet group for Redshift cluster
    const subnetGroup = new redshift.CfnClusterSubnetGroup(this, 'RedshiftSubnetGroup', {
      description: 'Subnet group for Redshift Spectrum cluster',
      subnetIds: this.vpc.privateSubnets.map(subnet => subnet.subnetId),
    });
    
    // Create security group for Redshift cluster
    const securityGroup = new ec2.SecurityGroup(this, 'RedshiftSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for Redshift Spectrum cluster',
      allowAllOutbound: true,
    });
    
    // Allow connections on Redshift port from VPC
    securityGroup.addIngressRule(
      ec2.Peer.ipv4(this.vpc.vpcCidrBlock),
      ec2.Port.tcp(5439),
      'Allow Redshift connections from VPC'
    );
    
    // If publicly accessible, allow connections from anywhere (for demo purposes)
    if (config.publiclyAccessible) {
      securityGroup.addIngressRule(
        ec2.Peer.anyIpv4(),
        ec2.Port.tcp(5439),
        'Allow Redshift connections from internet (demo only)'
      );
    }
    
    // Create Redshift cluster
    const cluster = new redshift.Cluster(this, 'RedshiftCluster', {
      clusterName: `spectrum-cluster-${config.resourceSuffix}`,
      masterUser: {
        masterUsername: config.masterUsername,
        masterPassword: cdk.SecretValue.unsafePlainText('TempPassword123!'),
      },
      vpc: this.vpc,
      vpcSubnets: {
        subnetType: config.publiclyAccessible 
          ? ec2.SubnetType.PUBLIC 
          : ec2.SubnetType.PRIVATE_WITH_EGRESS,
      },
      securityGroups: [securityGroup],
      clusterType: redshift.ClusterType.SINGLE_NODE,
      nodeType: redshift.NodeType.of(config.nodeType),
      defaultDatabaseName: config.databaseName,
      publiclyAccessible: config.publiclyAccessible,
      roles: [this.spectrumRole],
      removalPolicy: RemovalPolicy.DESTROY,
    });
    
    // Apply parameter group optimizations for Spectrum
    const parameterGroup = new redshift.CfnClusterParameterGroup(this, 'SpectrumParameterGroup', {
      description: 'Parameter group optimized for Redshift Spectrum',
      parameterGroupFamily: 'redshift-1.0',
      parameters: [
        {
          parameterName: 'enable_user_activity_logging',
          parameterValue: 'true',
        },
        {
          parameterName: 'auto_analyze',
          parameterValue: 'true',
        },
        {
          parameterName: 'search_path',
          parameterValue: '$user,public,spectrum_schema',
        }
      ],
    });
    
    // Associate parameter group with cluster
    const cfnCluster = cluster.node.defaultChild as redshift.CfnCluster;
    cfnCluster.clusterParameterGroupName = parameterGroup.ref;
    
    return cluster;
  }
  
  /**
   * Deploys sample operational data to S3 for testing
   */
  private deploySampleData(): void {
    // Create sample sales data
    const salesData = `transaction_id,customer_id,product_id,quantity,unit_price,transaction_date,store_id,region,payment_method
TXN001,CUST001,PROD001,2,29.99,2024-01-15,STORE001,North,credit_card
TXN002,CUST002,PROD002,1,199.99,2024-01-15,STORE002,South,debit_card
TXN003,CUST003,PROD003,3,15.50,2024-01-16,STORE001,North,cash
TXN004,CUST001,PROD004,1,89.99,2024-01-16,STORE003,East,credit_card
TXN005,CUST004,PROD001,2,29.99,2024-01-17,STORE002,South,credit_card
TXN006,CUST005,PROD005,1,45.00,2024-01-17,STORE001,North,credit_card
TXN007,CUST002,PROD003,2,15.50,2024-01-18,STORE002,South,debit_card
TXN008,CUST003,PROD002,1,199.99,2024-01-18,STORE003,East,cash
TXN009,CUST004,PROD004,1,89.99,2024-01-19,STORE001,North,credit_card
TXN010,CUST001,PROD005,2,45.00,2024-01-19,STORE002,South,credit_card`;
    
    // Create sample customer data
    const customerData = `customer_id,first_name,last_name,email,phone,registration_date,tier,city,state
CUST001,John,Doe,john.doe@email.com,555-0101,2023-01-15,premium,New York,NY
CUST002,Jane,Smith,jane.smith@email.com,555-0102,2023-02-20,standard,Los Angeles,CA
CUST003,Bob,Johnson,bob.johnson@email.com,555-0103,2023-03-10,standard,Chicago,IL
CUST004,Alice,Brown,alice.brown@email.com,555-0104,2023-04-05,premium,Miami,FL
CUST005,Charlie,Wilson,charlie.wilson@email.com,555-0105,2023-05-12,standard,Seattle,WA
CUST006,Diana,Miller,diana.miller@email.com,555-0106,2023-06-08,premium,Boston,MA
CUST007,Eve,Davis,eve.davis@email.com,555-0107,2023-07-14,standard,Portland,OR
CUST008,Frank,Garcia,frank.garcia@email.com,555-0108,2023-08-22,standard,Austin,TX`;
    
    // Create sample product data
    const productData = `product_id,product_name,category,brand,cost,retail_price,supplier_id
PROD001,Wireless Headphones,Electronics,TechBrand,20.00,29.99,SUP001
PROD002,Smart Watch,Electronics,TechBrand,120.00,199.99,SUP001
PROD003,Coffee Mug,Home,HomeBrand,8.00,15.50,SUP002
PROD004,Bluetooth Speaker,Electronics,AudioMax,50.00,89.99,SUP003
PROD005,Desk Lamp,Home,HomeBrand,25.00,45.00,SUP002
PROD006,Wireless Mouse,Electronics,TechBrand,15.00,25.99,SUP001
PROD007,Water Bottle,Home,HomeBrand,5.00,12.99,SUP002
PROD008,Phone Charger,Electronics,PowerMax,8.00,19.99,SUP004`;
    
    // Deploy sample data using CDK S3 deployment
    new s3deploy.BucketDeployment(this, 'SampleDataDeployment', {
      sources: [
        s3deploy.Source.data('operational-data/sales/year=2024/month=01/sales_transactions.csv', salesData),
        s3deploy.Source.data('operational-data/customers/customers.csv', customerData),
        s3deploy.Source.data('operational-data/products/products.csv', productData),
      ],
      destinationBucket: this.dataLakeBucket,
    });
  }
  
  /**
   * Creates CloudFormation outputs for easy access to resources
   */
  private createOutputs(): void {
    new CfnOutput(this, 'DataLakeBucketName', {
      value: this.dataLakeBucket.bucketName,
      description: 'Name of the S3 data lake bucket',
      exportName: `${this.stackName}-DataLakeBucket`,
    });
    
    new CfnOutput(this, 'RedshiftClusterEndpoint', {
      value: this.redshiftCluster.clusterEndpoint.hostname,
      description: 'Redshift cluster endpoint hostname',
      exportName: `${this.stackName}-RedshiftEndpoint`,
    });
    
    new CfnOutput(this, 'RedshiftClusterPort', {
      value: this.redshiftCluster.clusterEndpoint.port.toString(),
      description: 'Redshift cluster port number',
      exportName: `${this.stackName}-RedshiftPort`,
    });
    
    new CfnOutput(this, 'GlueDatabaseName', {
      value: this.glueDatabase.ref,
      description: 'Name of the Glue database for Spectrum',
      exportName: `${this.stackName}-GlueDatabase`,
    });
    
    new CfnOutput(this, 'SpectrumRoleArn', {
      value: this.spectrumRole.roleArn,
      description: 'ARN of the Redshift Spectrum IAM role',
      exportName: `${this.stackName}-SpectrumRole`,
    });
    
    new CfnOutput(this, 'RedshiftConnectionCommand', {
      value: `psql -h ${this.redshiftCluster.clusterEndpoint.hostname} -p ${this.redshiftCluster.clusterEndpoint.port} -U admin -d analytics`,
      description: 'Command to connect to Redshift cluster',
    });
    
    new CfnOutput(this, 'SpectrumSetupInstructions', {
      value: 'After deployment, run Glue crawlers and configure external schema in Redshift',
      description: 'Next steps for setting up Spectrum queries',
    });
  }
  
  /**
   * Generates a unique identifier for resource naming
   */
  private generateUniqueId(): string {
    return Math.random().toString(36).substring(2, 8);
  }
}

/**
 * CDK Application entry point
 */
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT || process.env.AWS_ACCOUNT_ID,
  region: process.env.CDK_DEFAULT_REGION || process.env.AWS_REGION || 'us-east-1',
};

// Create the operational analytics stack
new OperationalAnalyticsStack(app, 'OperationalAnalyticsStack', {
  env,
  description: 'Operational Analytics with Amazon Redshift Spectrum - CDK Stack',
  
  // Stack configuration options
  resourcePrefix: app.node.tryGetContext('resourcePrefix'),
  masterUsername: app.node.tryGetContext('masterUsername') || 'admin',
  nodeType: app.node.tryGetContext('nodeType') || 'dc2.large',
  publiclyAccessible: app.node.tryGetContext('publiclyAccessible') ?? true,
  databaseName: app.node.tryGetContext('databaseName') || 'analytics',
  
  // Add stack tags for resource management
  tags: {
    'Project': 'OperationalAnalytics',
    'Environment': app.node.tryGetContext('environment') || 'development',
    'ManagedBy': 'AWS-CDK',
    'Recipe': 'operational-analytics-amazon-redshift-spectrum',
  },
});

// Add global tags to all resources
cdk.Tags.of(app).add('Project', 'AWS-Recipes');
cdk.Tags.of(app).add('Recipe', 'operational-analytics-amazon-redshift-spectrum');