#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as quicksight from 'aws-cdk-lib/aws-quicksight';
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';
import { Construct } from 'constructs';

/**
 * Interface for stack properties with customizable parameters
 */
interface QuickSightBIDashboardStackProps extends cdk.StackProps {
  /** Prefix for resource names to ensure uniqueness */
  readonly resourcePrefix?: string;
  /** QuickSight user namespace (default: 'default') */
  readonly quickSightNamespace?: string;
  /** RDS database instance class */
  readonly databaseInstanceClass?: ec2.InstanceClass;
  /** RDS database instance size */
  readonly databaseInstanceSize?: ec2.InstanceSize;
  /** Enable RDS for additional data source demonstration */
  readonly enableRdsDataSource?: boolean;
}

/**
 * AWS CDK Stack for QuickSight Business Intelligence Dashboards
 * 
 * This stack creates a complete business intelligence solution using Amazon QuickSight
 * with S3 and optional RDS data sources. It demonstrates how to:
 * - Set up secure IAM roles for QuickSight data access
 * - Create S3 buckets with sample CSV data for analytics
 * - Configure QuickSight data sources, datasets, analyses, and dashboards
 * - Implement proper security and access controls
 * - Provide optional RDS PostgreSQL database for additional data sources
 */
export class QuickSightBIDashboardStack extends cdk.Stack {
  public readonly dataBucket: s3.Bucket;
  public readonly quickSightServiceRole: iam.Role;
  public readonly rdsInstance?: rds.DatabaseInstance;
  public readonly vpc?: ec2.Vpc;

  constructor(scope: Construct, id: string, props: QuickSightBIDashboardStackProps = {}) {
    super(scope, id, props);

    // Extract configuration parameters with defaults
    const resourcePrefix = props.resourcePrefix || 'quicksight-bi';
    const quickSightNamespace = props.quickSightNamespace || 'default';
    const enableRds = props.enableRdsDataSource ?? false;
    const databaseInstanceClass = props.databaseInstanceClass || ec2.InstanceClass.T3;
    const databaseInstanceSize = props.databaseInstanceSize || ec2.InstanceSize.MICRO;

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.substring(0, 8);

    // Create S3 bucket for data storage with proper configuration
    this.dataBucket = new s3.Bucket(this, 'QuickSightDataBucket', {
      bucketName: `${resourcePrefix}-data-${uniqueSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes only
      autoDeleteObjects: true, // For demo purposes only
      lifecycleRules: [
        {
          id: 'delete-incomplete-multipart-uploads',
          abortIncompleteMultipartUploadAfter: cdk.Duration.days(7),
        },
        {
          id: 'transition-to-ia',
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
          ],
        },
      ],
    });

    // Create IAM role for QuickSight to access AWS services
    this.quickSightServiceRole = new iam.Role(this, 'QuickSightServiceRole', {
      roleName: `${resourcePrefix}-service-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('quicksight.amazonaws.com'),
      description: 'IAM role for QuickSight to access data sources including S3 and RDS',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonS3ReadOnlyAccess'),
      ],
    });

    // Add specific permissions for the data bucket
    this.dataBucket.grantRead(this.quickSightServiceRole);

    // Create sample sales data for demonstration
    const sampleData = `date,region,product,sales_amount,quantity
2024-01-01,North,Widget A,1200,10
2024-01-01,South,Widget B,800,8
2024-01-02,North,Widget A,1400,12
2024-01-02,South,Widget B,900,9
2024-01-03,East,Widget C,1100,11
2024-01-03,West,Widget A,1300,13
2024-01-04,North,Widget B,1600,16
2024-01-04,South,Widget C,1000,10
2024-01-05,East,Widget A,1500,15
2024-01-05,West,Widget B,1100,11
2024-01-06,North,Widget C,1800,18
2024-01-06,South,Widget A,950,9
2024-01-07,East,Widget B,1250,12
2024-01-07,West,Widget C,1450,14
2024-01-08,North,Widget A,1350,13
2024-01-08,South,Widget B,1150,11
2024-01-09,East,Widget A,1650,16
2024-01-09,West,Widget B,1050,10
2024-01-10,North,Widget C,1750,17
2024-01-10,South,Widget A,1000,10`;

    // Deploy sample data to S3 bucket
    new s3deploy.BucketDeployment(this, 'SampleDataDeployment', {
      sources: [
        s3deploy.Source.data('data/sales_data.csv', sampleData),
        s3deploy.Source.data('data/product_catalog.csv', this.createProductCatalogData()),
        s3deploy.Source.data('data/customer_demographics.csv', this.createCustomerDemographicsData()),
      ],
      destinationBucket: this.dataBucket,
      retainOnDelete: false,
    });

    // Optional: Create RDS PostgreSQL instance for additional data source demonstration
    if (enableRds) {
      // Create VPC for RDS instance
      this.vpc = new ec2.Vpc(this, 'QuickSightVpc', {
        vpcName: `${resourcePrefix}-vpc-${uniqueSuffix}`,
        maxAzs: 2,
        enableDnsHostnames: true,
        enableDnsSupport: true,
        subnetConfiguration: [
          {
            cidrMask: 24,
            name: 'public-subnet',
            subnetType: ec2.SubnetType.PUBLIC,
          },
          {
            cidrMask: 24,
            name: 'private-subnet',
            subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
          },
          {
            cidrMask: 28,
            name: 'isolated-subnet',
            subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
          },
        ],
      });

      // Create subnet group for RDS
      const subnetGroup = new rds.SubnetGroup(this, 'DatabaseSubnetGroup', {
        vpc: this.vpc,
        description: 'Subnet group for QuickSight RDS database',
        vpcSubnets: {
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
      });

      // Create security group for RDS
      const databaseSecurityGroup = new ec2.SecurityGroup(this, 'DatabaseSecurityGroup', {
        vpc: this.vpc,
        description: 'Security group for QuickSight RDS database',
        allowAllOutbound: false,
      });

      // Allow QuickSight to connect to PostgreSQL port
      databaseSecurityGroup.addIngressRule(
        ec2.Peer.ipv4(this.vpc.vpcCidrBlock),
        ec2.Port.tcp(5432),
        'Allow PostgreSQL access from VPC'
      );

      // Create RDS PostgreSQL instance
      this.rdsInstance = new rds.DatabaseInstance(this, 'QuickSightDatabase', {
        engine: rds.DatabaseInstanceEngine.postgres({
          version: rds.PostgresEngineVersion.VER_15_4,
        }),
        instanceType: ec2.InstanceType.of(databaseInstanceClass, databaseInstanceSize),
        vpc: this.vpc,
        subnetGroup: subnetGroup,
        securityGroups: [databaseSecurityGroup],
        databaseName: 'quicksightdb',
        credentials: rds.Credentials.fromGeneratedSecret('quicksight_admin', {
          secretName: `${resourcePrefix}-db-credentials-${uniqueSuffix}`,
        }),
        allocatedStorage: 20,
        maxAllocatedStorage: 100,
        storageEncrypted: true,
        backupRetention: cdk.Duration.days(7),
        deletionProtection: false, // For demo purposes
        removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
      });

      // Grant QuickSight role permissions to access RDS
      this.quickSightServiceRole.addToPolicy(
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'rds:DescribeDBInstances',
            'rds:DescribeDBClusters',
            'rds:DescribeDBSubnetGroups',
            'rds:DescribeDBSecurityGroups',
          ],
          resources: [this.rdsInstance.instanceArn],
        })
      );
    }

    // Create QuickSight Data Source for S3
    const s3DataSource = new quicksight.CfnDataSource(this, 'S3DataSource', {
      dataSourceId: `s3-sales-data-${uniqueSuffix}`,
      awsAccountId: this.account,
      name: 'Sales Data S3 Source',
      type: 'S3',
      dataSourceParameters: {
        s3Parameters: {
          manifestFileLocation: {
            bucket: this.dataBucket.bucketName,
            key: 'data/sales_data.csv',
          },
        },
      },
      permissions: [
        {
          principal: this.quickSightServiceRole.roleArn,
          actions: [
            'quicksight:DescribeDataSource',
            'quicksight:DescribeDataSourcePermissions',
            'quicksight:PassDataSource',
            'quicksight:UpdateDataSource',
            'quicksight:DeleteDataSource',
          ],
        },
      ],
    });

    // Create QuickSight Dataset from S3 Data Source
    const salesDataSet = new quicksight.CfnDataSet(this, 'SalesDataSet', {
      dataSetId: `sales-dataset-${uniqueSuffix}`,
      awsAccountId: this.account,
      name: 'Sales Dataset',
      importMode: 'SPICE', // Use SPICE for better performance
      physicalTableMap: {
        SalesTable: {
          s3Source: {
            dataSourceArn: s3DataSource.attrArn,
            uploadSettings: {
              format: 'CSV',
              startFromRow: 1,
              containsHeader: true,
              delimiter: ',',
            },
            inputColumns: [
              { name: 'date', type: 'DATETIME' },
              { name: 'region', type: 'STRING' },
              { name: 'product', type: 'STRING' },
              { name: 'sales_amount', type: 'DECIMAL' },
              { name: 'quantity', type: 'INTEGER' },
            ],
          },
        },
      },
      permissions: [
        {
          principal: this.quickSightServiceRole.roleArn,
          actions: [
            'quicksight:DescribeDataSet',
            'quicksight:DescribeDataSetPermissions',
            'quicksight:PassDataSet',
            'quicksight:DescribeIngestion',
            'quicksight:ListIngestions',
            'quicksight:UpdateDataSet',
            'quicksight:DeleteDataSet',
            'quicksight:CreateIngestion',
            'quicksight:CancelIngestion',
          ],
        },
      ],
    });

    // Create QuickSight Analysis with visualizations
    const salesAnalysis = new quicksight.CfnAnalysis(this, 'SalesAnalysis', {
      analysisId: `sales-analysis-${uniqueSuffix}`,
      awsAccountId: this.account,
      name: 'Sales Analysis',
      definition: {
        dataSetIdentifierDeclarations: [
          {
            dataSetArn: salesDataSet.attrArn,
            identifier: 'SalesDataSet',
          },
        ],
        sheets: [
          {
            sheetId: 'sales-overview-sheet',
            name: 'Sales Overview',
            visuals: [
              {
                barChartVisual: {
                  visualId: 'sales-by-region-chart',
                  title: {
                    visibility: 'VISIBLE',
                    formatText: {
                      plainText: 'Sales by Region',
                    },
                  },
                  fieldWells: {
                    barChartAggregatedFieldWells: {
                      category: [
                        {
                          categoricalDimensionField: {
                            fieldId: 'region-field',
                            column: {
                              dataSetIdentifier: 'SalesDataSet',
                              columnName: 'region',
                            },
                          },
                        },
                      ],
                      values: [
                        {
                          numericalMeasureField: {
                            fieldId: 'sales-amount-field',
                            column: {
                              dataSetIdentifier: 'SalesDataSet',
                              columnName: 'sales_amount',
                            },
                            aggregationFunction: {
                              simpleNumericalAggregation: 'SUM',
                            },
                          },
                        },
                      ],
                    },
                  },
                },
              },
              {
                lineChartVisual: {
                  visualId: 'sales-trend-chart',
                  title: {
                    visibility: 'VISIBLE',
                    formatText: {
                      plainText: 'Sales Trend Over Time',
                    },
                  },
                  fieldWells: {
                    lineChartAggregatedFieldWells: {
                      category: [
                        {
                          dateTimeDimensionField: {
                            fieldId: 'date-field',
                            column: {
                              dataSetIdentifier: 'SalesDataSet',
                              columnName: 'date',
                            },
                            dateGranularity: 'DAY',
                          },
                        },
                      ],
                      values: [
                        {
                          numericalMeasureField: {
                            fieldId: 'sales-amount-trend',
                            column: {
                              dataSetIdentifier: 'SalesDataSet',
                              columnName: 'sales_amount',
                            },
                            aggregationFunction: {
                              simpleNumericalAggregation: 'SUM',
                            },
                          },
                        },
                      ],
                    },
                  },
                },
              },
              {
                pieChartVisual: {
                  visualId: 'product-distribution-chart',
                  title: {
                    visibility: 'VISIBLE',
                    formatText: {
                      plainText: 'Sales Distribution by Product',
                    },
                  },
                  fieldWells: {
                    pieChartAggregatedFieldWells: {
                      category: [
                        {
                          categoricalDimensionField: {
                            fieldId: 'product-field',
                            column: {
                              dataSetIdentifier: 'SalesDataSet',
                              columnName: 'product',
                            },
                          },
                        },
                      ],
                      values: [
                        {
                          numericalMeasureField: {
                            fieldId: 'sales-amount-pie',
                            column: {
                              dataSetIdentifier: 'SalesDataSet',
                              columnName: 'sales_amount',
                            },
                            aggregationFunction: {
                              simpleNumericalAggregation: 'SUM',
                            },
                          },
                        },
                      ],
                    },
                  },
                },
              },
            ],
          },
        ],
      },
      permissions: [
        {
          principal: this.quickSightServiceRole.roleArn,
          actions: [
            'quicksight:RestoreAnalysis',
            'quicksight:UpdateAnalysisPermissions',
            'quicksight:DeleteAnalysis',
            'quicksight:QueryAnalysis',
            'quicksight:DescribeAnalysisPermissions',
            'quicksight:DescribeAnalysis',
            'quicksight:UpdateAnalysis',
          ],
        },
      ],
    });

    // Create QuickSight Dashboard from Analysis
    const salesDashboard = new quicksight.CfnDashboard(this, 'SalesDashboard', {
      dashboardId: `sales-dashboard-${uniqueSuffix}`,
      awsAccountId: this.account,
      name: 'Sales Dashboard',
      sourceEntity: {
        sourceTemplate: {
          dataSetReferences: [
            {
              dataSetArn: salesDataSet.attrArn,
              dataSetPlaceholder: 'SalesDataSet',
            },
          ],
          arn: salesAnalysis.attrArn,
        },
      },
      permissions: [
        {
          principal: this.quickSightServiceRole.roleArn,
          actions: [
            'quicksight:DescribeDashboard',
            'quicksight:ListDashboardVersions',
            'quicksight:UpdateDashboardPermissions',
            'quicksight:QueryDashboard',
            'quicksight:UpdateDashboard',
            'quicksight:DeleteDashboard',
            'quicksight:DescribeDashboardPermissions',
            'quicksight:UpdateDashboardPublishedVersion',
          ],
        },
      ],
    });

    // Add dependencies to ensure proper creation order
    salesDataSet.addDependency(s3DataSource);
    salesAnalysis.addDependency(salesDataSet);
    salesDashboard.addDependency(salesAnalysis);

    // CloudFormation Outputs for important resources
    new cdk.CfnOutput(this, 'DataBucketName', {
      value: this.dataBucket.bucketName,
      description: 'Name of the S3 bucket containing sample data',
      exportName: `${this.stackName}-DataBucketName`,
    });

    new cdk.CfnOutput(this, 'QuickSightServiceRoleArn', {
      value: this.quickSightServiceRole.roleArn,
      description: 'ARN of the IAM role for QuickSight service access',
      exportName: `${this.stackName}-QuickSightServiceRoleArn`,
    });

    new cdk.CfnOutput(this, 'DataSourceId', {
      value: s3DataSource.dataSourceId!,
      description: 'QuickSight Data Source ID for S3',
      exportName: `${this.stackName}-DataSourceId`,
    });

    new cdk.CfnOutput(this, 'DataSetId', {
      value: salesDataSet.dataSetId!,
      description: 'QuickSight Dataset ID',
      exportName: `${this.stackName}-DataSetId`,
    });

    new cdk.CfnOutput(this, 'AnalysisId', {
      value: salesAnalysis.analysisId!,
      description: 'QuickSight Analysis ID',
      exportName: `${this.stackName}-AnalysisId`,
    });

    new cdk.CfnOutput(this, 'DashboardId', {
      value: salesDashboard.dashboardId!,
      description: 'QuickSight Dashboard ID',
      exportName: `${this.stackName}-DashboardId`,
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://quicksight.aws.amazon.com/sn/dashboards/${salesDashboard.dashboardId}`,
      description: 'URL to access the QuickSight Dashboard',
      exportName: `${this.stackName}-DashboardUrl`,
    });

    if (this.rdsInstance) {
      new cdk.CfnOutput(this, 'RdsEndpoint', {
        value: this.rdsInstance.instanceEndpoint.hostname,
        description: 'RDS PostgreSQL instance endpoint',
        exportName: `${this.stackName}-RdsEndpoint`,
      });

      new cdk.CfnOutput(this, 'RdsSecretArn', {
        value: this.rdsInstance.secret?.secretArn || 'N/A',
        description: 'ARN of the secret containing RDS credentials',
        exportName: `${this.stackName}-RdsSecretArn`,
      });
    }

    // Add tags to all resources for cost tracking and management
    cdk.Tags.of(this).add('Project', 'QuickSight-BI-Dashboard');
    cdk.Tags.of(this).add('Environment', 'Demo');
    cdk.Tags.of(this).add('Cost-Center', 'Analytics');
  }

  /**
   * Creates sample product catalog data for additional analytics
   */
  private createProductCatalogData(): string {
    return `product_id,product_name,category,price,cost,margin
WA001,Widget A,Electronics,120,80,40
WB002,Widget B,Home & Garden,100,65,35
WC003,Widget C,Sports & Outdoors,110,70,40
WD004,Widget D,Electronics,130,85,45
WE005,Widget E,Health & Beauty,95,60,35`;
  }

  /**
   * Creates sample customer demographics data for enhanced analytics
   */
  private createCustomerDemographicsData(): string {
    return `customer_id,region,age_group,income_bracket,customer_segment
CUST001,North,25-34,50k-75k,Premium
CUST002,South,35-44,75k-100k,Standard
CUST003,East,45-54,100k+,Premium
CUST004,West,25-34,25k-50k,Basic
CUST005,North,55+,75k-100k,Standard
CUST006,South,35-44,50k-75k,Standard
CUST007,East,25-34,100k+,Premium
CUST008,West,45-54,25k-50k,Basic`;
  }
}

// CDK App instantiation and stack deployment
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const resourcePrefix = app.node.tryGetContext('resourcePrefix') || process.env.RESOURCE_PREFIX || 'quicksight-bi';
const quickSightNamespace = app.node.tryGetContext('quickSightNamespace') || process.env.QUICKSIGHT_NAMESPACE || 'default';
const enableRds = app.node.tryGetContext('enableRds') === 'true' || process.env.ENABLE_RDS === 'true';

// Deploy the QuickSight BI Dashboard stack
new QuickSightBIDashboardStack(app, 'QuickSightBIDashboardStack', {
  resourcePrefix,
  quickSightNamespace,
  enableRdsDataSource: enableRds,
  databaseInstanceClass: ec2.InstanceClass.T3,
  databaseInstanceSize: ec2.InstanceSize.MICRO,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'CDK Stack for Business Intelligence Dashboards with QuickSight, S3, and optional RDS data sources',
  tags: {
    Project: 'QuickSight-BI-Dashboard',
    Environment: 'Demo',
    CdkVersion: cdk.VERSION,
  },
});

// Synthesize the CloudFormation template
app.synth();