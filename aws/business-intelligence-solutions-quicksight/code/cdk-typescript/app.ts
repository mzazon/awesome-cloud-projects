#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as quicksight from 'aws-cdk-lib/aws-quicksight';
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';
import { Construct } from 'constructs';

/**
 * Stack for deploying QuickSight Business Intelligence Solutions
 * 
 * This stack creates:
 * - S3 bucket with sample sales data
 * - RDS MySQL database instance
 * - QuickSight data sources, datasets, and dashboards
 * - IAM roles for secure access
 */
export class QuickSightBIStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);

    // Create VPC for RDS instance
    const vpc = new ec2.Vpc(this, 'QuickSightVPC', {
      maxAzs: 2,
      natGateways: 1,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'PublicSubnet',
          subnetType: ec2.SubnetType.PUBLIC,
        },
        {
          cidrMask: 24,
          name: 'PrivateSubnet',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
        },
        {
          cidrMask: 24,
          name: 'DatabaseSubnet',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
      ],
    });

    // Create S3 bucket for sample data
    const dataBucket = new s3.Bucket(this, 'QuickSightDataBucket', {
      bucketName: `quicksight-bi-data-${uniqueSuffix}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      versioned: false,
      publicReadAccess: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
    });

    // Create sample sales data file
    const sampleData = `date,region,product,sales_amount,quantity,customer_segment
2024-01-15,North America,Product A,1200.50,25,Enterprise
2024-01-15,Europe,Product B,850.75,15,SMB
2024-01-16,Asia Pacific,Product A,2100.25,42,Enterprise
2024-01-16,North America,Product C,675.00,18,Consumer
2024-01-17,Europe,Product A,1450.80,29,Enterprise
2024-01-17,Asia Pacific,Product B,920.45,21,SMB
2024-01-18,North America,Product B,1100.30,22,SMB
2024-01-18,Europe,Product C,780.90,16,Consumer
2024-01-19,Asia Pacific,Product C,1350.60,35,Enterprise
2024-01-19,North America,Product A,1680.75,33,Enterprise
2024-01-20,Europe,Product B,1325.40,27,Enterprise
2024-01-20,North America,Product C,890.25,19,Consumer
2024-01-21,Asia Pacific,Product A,1750.60,35,Enterprise
2024-01-21,Europe,Product C,945.80,20,Consumer
2024-01-22,North America,Product A,1580.90,32,Enterprise`;

    // Deploy sample data to S3
    new s3deploy.BucketDeployment(this, 'DeploySampleData', {
      sources: [
        s3deploy.Source.data('sales/sales_data.csv', sampleData),
        s3deploy.Source.data('sales/historical/sales_data.csv', sampleData),
      ],
      destinationBucket: dataBucket,
      retainOnDelete: false,
    });

    // Create security group for RDS
    const dbSecurityGroup = new ec2.SecurityGroup(this, 'DatabaseSecurityGroup', {
      vpc,
      description: 'Security group for QuickSight demo database',
      allowAllOutbound: false,
    });

    // Allow MySQL access from VPC
    dbSecurityGroup.addIngressRule(
      ec2.Peer.ipv4(vpc.vpcCidrBlock),
      ec2.Port.tcp(3306),
      'Allow MySQL access from VPC'
    );

    // Create DB subnet group
    const dbSubnetGroup = new rds.SubnetGroup(this, 'DatabaseSubnetGroup', {
      description: 'Subnet group for QuickSight demo database',
      vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
      },
    });

    // Create RDS MySQL instance
    const database = new rds.DatabaseInstance(this, 'QuickSightDatabase', {
      engine: rds.DatabaseInstanceEngine.mysql({
        version: rds.MysqlEngineVersion.VER_8_0,
      }),
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO),
      credentials: rds.Credentials.fromGeneratedSecret('admin', {
        secretName: `quicksight-db-credentials-${uniqueSuffix}`,
      }),
      vpc,
      subnetGroup: dbSubnetGroup,
      securityGroups: [dbSecurityGroup],
      allocatedStorage: 20,
      storageEncrypted: true,
      multiAz: false,
      deletionProtection: false,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      databaseName: 'quicksight_demo',
      backupRetention: cdk.Duration.days(0), // Disable backups for demo
    });

    // Create IAM role for QuickSight to access S3
    const quicksightRole = new iam.Role(this, 'QuickSightRole', {
      roleName: `QuickSight-S3-Role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('quicksight.amazonaws.com'),
      description: 'IAM role for QuickSight to access S3 data sources',
    });

    // Add S3 access policy to QuickSight role
    quicksightRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          's3:GetObject',
          's3:GetObjectVersion',
          's3:ListBucket',
        ],
        resources: [
          dataBucket.bucketArn,
          `${dataBucket.bucketArn}/*`,
        ],
      })
    );

    // Create S3 data source for QuickSight
    const s3DataSource = new quicksight.CfnDataSource(this, 'S3DataSource', {
      awsAccountId: this.account,
      dataSourceId: 'sales-data-s3',
      name: 'Sales Data S3',
      type: 'S3',
      dataSourceParameters: {
        s3Parameters: {
          manifestFileLocation: {
            bucket: dataBucket.bucketName,
            key: 'sales/sales_data.csv',
          },
        },
      },
      permissions: [
        {
          principal: `arn:aws:quicksight:${this.region}:${this.account}:user/default/${cdk.Aws.ACCOUNT_ID}`,
          actions: [
            'quicksight:DescribeDataSource',
            'quicksight:DescribeDataSourcePermissions',
            'quicksight:PassDataSource',
            'quicksight:UpdateDataSource',
            'quicksight:DeleteDataSource',
            'quicksight:UpdateDataSourcePermissions',
          ],
        },
      ],
    });

    // Create dataset from S3 data source
    const salesDataset = new quicksight.CfnDataSet(this, 'SalesDataset', {
      awsAccountId: this.account,
      dataSetId: 'sales-dataset',
      name: 'Sales Analytics Dataset',
      physicalTableMap: {
        'sales_table': {
          s3Source: {
            dataSourceArn: s3DataSource.attrArn,
            inputColumns: [
              { name: 'date', type: 'STRING' },
              { name: 'region', type: 'STRING' },
              { name: 'product', type: 'STRING' },
              { name: 'sales_amount', type: 'DECIMAL' },
              { name: 'quantity', type: 'INTEGER' },
              { name: 'customer_segment', type: 'STRING' },
            ],
          },
        },
      },
      logicalTableMap: {
        'sales_logical': {
          alias: 'Sales Data',
          source: {
            physicalTableId: 'sales_table',
          },
          dataTransforms: [
            {
              castColumnTypeOperation: {
                columnName: 'date',
                newColumnType: 'DATETIME',
                format: 'yyyy-MM-dd',
              },
            },
          ],
        },
      },
      importMode: 'SPICE',
      permissions: [
        {
          principal: `arn:aws:quicksight:${this.region}:${this.account}:user/default/${cdk.Aws.ACCOUNT_ID}`,
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
            'quicksight:UpdateDataSetPermissions',
          ],
        },
      ],
    });

    // Create QuickSight analysis
    const salesAnalysis = new quicksight.CfnAnalysis(this, 'SalesAnalysis', {
      awsAccountId: this.account,
      analysisId: 'sales-analysis',
      name: 'Sales Performance Analysis',
      definition: {
        dataSetIdentifierDeclarations: [
          {
            dataSetArn: salesDataset.attrArn,
            identifier: 'sales_data',
          },
        ],
        sheets: [
          {
            sheetId: 'sales_overview',
            name: 'Sales Overview',
            visuals: [
              {
                barChartVisual: {
                  visualId: 'sales_by_region',
                  title: {
                    text: 'Sales by Region',
                  },
                  chartConfiguration: {
                    fieldWells: {
                      barChartAggregatedFieldWells: {
                        category: [
                          {
                            categoricalDimensionField: {
                              fieldId: 'region',
                              column: {
                                dataSetIdentifier: 'sales_data',
                                columnName: 'region',
                              },
                            },
                          },
                        ],
                        values: [
                          {
                            numericalMeasureField: {
                              fieldId: 'sales_amount',
                              column: {
                                dataSetIdentifier: 'sales_data',
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
              },
              {
                pieChartVisual: {
                  visualId: 'sales_by_product',
                  title: {
                    text: 'Sales Distribution by Product',
                  },
                  chartConfiguration: {
                    fieldWells: {
                      pieChartAggregatedFieldWells: {
                        category: [
                          {
                            categoricalDimensionField: {
                              fieldId: 'product',
                              column: {
                                dataSetIdentifier: 'sales_data',
                                columnName: 'product',
                              },
                            },
                          },
                        ],
                        values: [
                          {
                            numericalMeasureField: {
                              fieldId: 'sales_amount_pie',
                              column: {
                                dataSetIdentifier: 'sales_data',
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
              },
            ],
          },
        ],
      },
      permissions: [
        {
          principal: `arn:aws:quicksight:${this.region}:${this.account}:user/default/${cdk.Aws.ACCOUNT_ID}`,
          actions: [
            'quicksight:RestoreAnalysis',
            'quicksight:UpdateAnalysisPermissions',
            'quicksight:DeleteAnalysis',
            'quicksight:DescribeAnalysisPermissions',
            'quicksight:QueryAnalysis',
            'quicksight:DescribeAnalysis',
            'quicksight:UpdateAnalysis',
          ],
        },
      ],
    });

    // Create QuickSight dashboard from analysis
    const salesDashboard = new quicksight.CfnDashboard(this, 'SalesDashboard', {
      awsAccountId: this.account,
      dashboardId: 'sales-dashboard',
      name: 'Sales Performance Dashboard',
      sourceEntity: {
        sourceTemplate: {
          dataSetReferences: [
            {
              dataSetArn: salesDataset.attrArn,
              dataSetPlaceholder: 'sales_data',
            },
          ],
          arn: salesAnalysis.attrArn,
        },
      },
      permissions: [
        {
          principal: `arn:aws:quicksight:${this.region}:${this.account}:user/default/${cdk.Aws.ACCOUNT_ID}`,
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
      dashboardPublishOptions: {
        adHocFilteringOption: {
          availabilityStatus: 'ENABLED',
        },
        exportToCsvOption: {
          availabilityStatus: 'ENABLED',
        },
        sheetControlsOption: {
          visibilityState: 'EXPANDED',
        },
      },
    });

    // Create scheduled refresh for dataset
    const refreshSchedule = new quicksight.CfnRefreshSchedule(this, 'DatasetRefreshSchedule', {
      awsAccountId: this.account,
      dataSetId: salesDataset.dataSetId!,
      schedule: {
        scheduleId: 'daily-refresh',
        refreshType: 'FULL_REFRESH',
        scheduleFrequency: {
          interval: 'DAILY',
          timeOfTheDay: '06:00',
        },
        startAfterDateTime: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
      },
    });

    // Output important information
    new cdk.CfnOutput(this, 'DataBucketName', {
      value: dataBucket.bucketName,
      description: 'S3 bucket containing sample sales data',
    });

    new cdk.CfnOutput(this, 'DatabaseEndpoint', {
      value: database.instanceEndpoint.hostname,
      description: 'RDS MySQL database endpoint',
    });

    new cdk.CfnOutput(this, 'DatabaseSecretArn', {
      value: database.secret?.secretArn || 'N/A',
      description: 'ARN of the secret containing database credentials',
    });

    new cdk.CfnOutput(this, 'QuickSightDataSourceArn', {
      value: s3DataSource.attrArn,
      description: 'ARN of the QuickSight S3 data source',
    });

    new cdk.CfnOutput(this, 'QuickSightDatasetArn', {
      value: salesDataset.attrArn,
      description: 'ARN of the QuickSight dataset',
    });

    new cdk.CfnOutput(this, 'QuickSightDashboardArn', {
      value: salesDashboard.attrArn,
      description: 'ARN of the QuickSight dashboard',
    });

    new cdk.CfnOutput(this, 'QuickSightDashboardUrl', {
      value: `https://${this.region}.quicksight.aws.amazon.com/sn/dashboards/${salesDashboard.dashboardId}`,
      description: 'URL to access the QuickSight dashboard',
    });

    new cdk.CfnOutput(this, 'IAMRoleArn', {
      value: quicksightRole.roleArn,
      description: 'ARN of the IAM role for QuickSight S3 access',
    });
  }
}

// Create CDK app
const app = new cdk.App();

// Deploy the stack
new QuickSightBIStack(app, 'QuickSightBIStack', {
  description: 'QuickSight Business Intelligence Solutions with S3, RDS, and interactive dashboards',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'QuickSight-BI-Solutions',
    Environment: 'Demo',
    Purpose: 'Business Intelligence Analytics',
  },
});

app.synth();