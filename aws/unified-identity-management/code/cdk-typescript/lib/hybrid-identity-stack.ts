import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ds from 'aws-cdk-lib/aws-directoryservice';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';

/**
 * Interface for configurable stack properties
 */
export interface HybridIdentityStackProps extends cdk.StackProps {
  readonly vpcCidr?: string;
  readonly directoryName?: string;
  readonly directoryPassword?: string;
  readonly rdsInstanceClass?: string;
  readonly enableWorkSpaces?: boolean;
  readonly enableTrust?: boolean;
  readonly onPremisesDomain?: string;
}

/**
 * CDK Stack for Hybrid Identity Management with AWS Directory Service
 * 
 * This stack creates:
 * - VPC with proper subnet configuration for Directory Service
 * - AWS Managed Microsoft AD (Directory Service)
 * - Security groups for secure communication
 * - RDS SQL Server instance with Windows Authentication
 * - IAM roles for service integration
 * - CloudWatch logging for monitoring
 * - Secrets Manager for secure credential storage
 */
export class HybridIdentityStack extends cdk.Stack {
  public readonly vpc: ec2.Vpc;
  public readonly directory: ds.CfnMicrosoftAD;
  public readonly rdsInstance: rds.DatabaseInstance;
  public readonly directoryServiceRole: iam.Role;

  constructor(scope: Construct, id: string, props?: HybridIdentityStackProps) {
    super(scope, id, props);

    // Configuration with sensible defaults
    const vpcCidr = props?.vpcCidr || '10.0.0.0/16';
    const directoryName = props?.directoryName || `hybrid-ad-${this.generateRandomSuffix()}`;
    const enableWorkSpaces = props?.enableWorkSpaces ?? true;
    const rdsInstanceClass = props?.rdsInstanceClass || 'db.t3.medium';

    // Create VPC with proper configuration for Directory Service
    this.vpc = this.createVpc(vpcCidr);

    // Create secrets for directory and database passwords
    const directorySecret = this.createDirectorySecret();
    const rdsSecret = this.createRdsSecret();

    // Create security groups
    const securityGroups = this.createSecurityGroups();

    // Create AWS Managed Microsoft AD
    this.directory = this.createManagedDirectory(
      directoryName,
      directorySecret,
      securityGroups.directorySecurityGroup
    );

    // Create IAM role for RDS Directory Service integration
    this.directoryServiceRole = this.createDirectoryServiceRole();

    // Create RDS SQL Server instance with Windows Authentication
    this.rdsInstance = this.createRdsInstance(
      rdsSecret,
      securityGroups.rdsSecurityGroup,
      rdsInstanceClass
    );

    // Create CloudWatch log groups for monitoring
    this.createCloudWatchLogGroups();

    // Create EC2 instance for domain administration (optional)
    this.createDomainAdminInstance(securityGroups.adminSecurityGroup);

    // Output important values
    this.createOutputs();
  }

  /**
   * Create VPC with subnets in multiple AZs for Directory Service
   */
  private createVpc(cidr: string): ec2.Vpc {
    const vpc = new ec2.Vpc(this, 'HybridIdentityVpc', {
      ipAddresses: ec2.IpAddresses.cidr(cidr),
      maxAzs: 2,
      natGateways: 1, // Cost optimization - use 1 NAT Gateway
      subnetConfiguration: [
        {
          name: 'Public',
          subnetType: ec2.SubnetType.PUBLIC,
          cidrMask: 24,
        },
        {
          name: 'Private',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
          cidrMask: 24,
        },
        {
          name: 'Directory',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
          cidrMask: 26, // Smaller subnets for directory services
        },
      ],
      enableDnsHostnames: true,
      enableDnsSupport: true,
    });

    // Tag the VPC and subnets
    cdk.Tags.of(vpc).add('Name', 'HybridIdentityVpc');
    cdk.Tags.of(vpc).add('Purpose', 'HybridIdentityManagement');

    return vpc;
  }

  /**
   * Create secrets for directory and RDS passwords
   */
  private createDirectorySecret(): secretsmanager.Secret {
    return new secretsmanager.Secret(this, 'DirectoryPassword', {
      description: 'Password for AWS Managed Microsoft AD',
      generateSecretString: {
        secretStringTemplate: JSON.stringify({ username: 'Admin' }),
        generateStringKey: 'password',
        excludeCharacters: ' %+~`#$&*()|[]{}:;<>?!\'/@"\\',
        includeSpace: false,
        passwordLength: 32,
        requireEachIncludedType: true,
      },
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
    });
  }

  private createRdsSecret(): secretsmanager.Secret {
    return new secretsmanager.Secret(this, 'RdsPassword', {
      description: 'Password for RDS SQL Server master user',
      generateSecretString: {
        secretStringTemplate: JSON.stringify({ username: 'admin' }),
        generateStringKey: 'password',
        excludeCharacters: ' %+~`#$&*()|[]{}:;<>?!\'/@"\\',
        includeSpace: false,
        passwordLength: 32,
        requireEachIncludedType: true,
      },
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
    });
  }

  /**
   * Create security groups for various components
   */
  private createSecurityGroups() {
    // Security group for Directory Service
    const directorySecurityGroup = new ec2.SecurityGroup(this, 'DirectorySecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for AWS Managed Microsoft AD',
      allowAllOutbound: true,
    });

    // Security group for WorkSpaces
    const workspacesSecurityGroup = new ec2.SecurityGroup(this, 'WorkSpacesSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for Amazon WorkSpaces',
      allowAllOutbound: true,
    });

    // Security group for RDS
    const rdsSecurityGroup = new ec2.SecurityGroup(this, 'RdsSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for RDS SQL Server',
      allowAllOutbound: false,
    });

    // Security group for domain admin instance
    const adminSecurityGroup = new ec2.SecurityGroup(this, 'AdminSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for domain administration instance',
      allowAllOutbound: true,
    });

    // Configure security group rules for Directory Service
    directorySecurityGroup.addIngressRule(
      workspacesSecurityGroup,
      ec2.Port.tcp(445),
      'Allow SMB from WorkSpaces'
    );

    directorySecurityGroup.addIngressRule(
      adminSecurityGroup,
      ec2.Port.tcp(389),
      'Allow LDAP from admin instance'
    );

    directorySecurityGroup.addIngressRule(
      adminSecurityGroup,
      ec2.Port.tcp(636),
      'Allow LDAPS from admin instance'
    );

    directorySecurityGroup.addIngressRule(
      adminSecurityGroup,
      ec2.Port.tcp(88),
      'Allow Kerberos from admin instance'
    );

    // Configure RDS security group
    rdsSecurityGroup.addIngressRule(
      workspacesSecurityGroup,
      ec2.Port.tcp(1433),
      'Allow SQL Server from WorkSpaces'
    );

    rdsSecurityGroup.addIngressRule(
      adminSecurityGroup,
      ec2.Port.tcp(1433),
      'Allow SQL Server from admin instance'
    );

    // Allow RDP access to admin instance (restrict to your IP in production)
    adminSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(3389),
      'Allow RDP access (restrict in production)'
    );

    return {
      directorySecurityGroup,
      workspacesSecurityGroup,
      rdsSecurityGroup,
      adminSecurityGroup,
    };
  }

  /**
   * Create AWS Managed Microsoft AD
   */
  private createManagedDirectory(
    directoryName: string,
    secret: secretsmanager.Secret,
    securityGroup: ec2.SecurityGroup
  ): ds.CfnMicrosoftAD {
    // Get private isolated subnets for directory
    const directorySubnets = this.vpc.selectSubnets({
      subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
    });

    const directory = new ds.CfnMicrosoftAD(this, 'ManagedDirectory', {
      name: `${directoryName}.corp.local`,
      password: secret.secretValueFromJson('password').unsafeUnwrap(),
      vpcSettings: {
        vpcId: this.vpc.vpcId,
        subnetIds: directorySubnets.subnetIds,
      },
      edition: 'Standard', // Options: Standard, Enterprise
      shortName: directoryName.toUpperCase(),
      enableSso: false, // Can be enabled later if needed
      createAlias: true,
    });

    // Add tags
    cdk.Tags.of(directory).add('Name', directoryName);
    cdk.Tags.of(directory).add('Type', 'ManagedMicrosoftAD');

    // Create custom resource to enable client authentication after directory creation
    this.enableDirectoryFeatures(directory);

    return directory;
  }

  /**
   * Enable additional directory features using custom resources
   */
  private enableDirectoryFeatures(directory: ds.CfnMicrosoftAD): void {
    // Create custom resource to enable LDAPS and client authentication
    // This would typically be implemented with a Lambda function
    // For this example, we'll document the manual steps needed
    
    new cdk.CfnOutput(this, 'DirectorySetupInstructions', {
      value: `After deployment, enable LDAPS and client authentication for directory ${directory.ref}`,
      description: 'Manual setup instructions for directory features',
    });
  }

  /**
   * Create IAM role for RDS Directory Service integration
   */
  private createDirectoryServiceRole(): iam.Role {
    const role = new iam.Role(this, 'RdsDirectoryServiceRole', {
      assumedBy: new iam.ServicePrincipal('rds.amazonaws.com'),
      description: 'IAM role for RDS Directory Service integration',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonRDSDirectoryServiceAccess'),
      ],
    });

    return role;
  }

  /**
   * Create RDS SQL Server instance with Windows Authentication
   */
  private createRdsInstance(
    secret: secretsmanager.Secret,
    securityGroup: ec2.SecurityGroup,
    instanceClass: string
  ): rds.DatabaseInstance {
    // Create DB subnet group
    const subnetGroup = new rds.SubnetGroup(this, 'RdsSubnetGroup', {
      vpc: this.vpc,
      description: 'Subnet group for RDS SQL Server',
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      },
    });

    // Create parameter group for SQL Server
    const parameterGroup = new rds.ParameterGroup(this, 'SqlServerParameterGroup', {
      engine: rds.DatabaseInstanceEngine.sqlServerSe({
        version: rds.SqlServerEngineVersion.VER_15_00_4073_23_V1,
      }),
      description: 'Parameter group for SQL Server with Windows Authentication',
    });

    const instance = new rds.DatabaseInstance(this, 'SqlServerInstance', {
      engine: rds.DatabaseInstanceEngine.sqlServerSe({
        version: rds.SqlServerEngineVersion.VER_15_00_4073_23_V1,
      }),
      instanceType: ec2.InstanceType.of(
        ec2.InstanceClass.T3,
        instanceClass.includes('medium') ? ec2.InstanceSize.MEDIUM : ec2.InstanceSize.LARGE
      ),
      credentials: rds.Credentials.fromSecret(secret),
      allocatedStorage: 200,
      storageType: rds.StorageType.GP2,
      vpc: this.vpc,
      subnetGroup: subnetGroup,
      securityGroups: [securityGroup],
      parameterGroup: parameterGroup,
      backupRetention: cdk.Duration.days(7),
      deletionProtection: false, // Set to true for production
      multiAz: false, // Set to true for production
      domainRole: this.directoryServiceRole,
      domain: this.directory.ref,
      licenseModel: rds.LicenseModel.LICENSE_INCLUDED,
      timezone: 'GMT Standard Time',
      enablePerformanceInsights: true,
      performanceInsightRetention: rds.PerformanceInsightRetention.DEFAULT,
      cloudwatchLogsExports: ['error', 'agent'],
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
    });

    return instance;
  }

  /**
   * Create CloudWatch log groups for monitoring
   */
  private createCloudWatchLogGroups(): void {
    new logs.LogGroup(this, 'DirectoryServiceLogGroup', {
      logGroupName: '/aws/directoryservice/managedmicrosoftad',
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    new logs.LogGroup(this, 'WorkSpacesLogGroup', {
      logGroupName: '/aws/workspaces',
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });
  }

  /**
   * Create EC2 instance for domain administration
   */
  private createDomainAdminInstance(securityGroup: ec2.SecurityGroup): ec2.Instance {
    // Use Windows Server 2019 AMI
    const windowsAmi = ec2.MachineImage.latestWindows(ec2.WindowsVersion.WINDOWS_SERVER_2019_ENGLISH_FULL_BASE);

    // Create key pair for RDP access
    const keyPair = new ec2.CfnKeyPair(this, 'DomainAdminKeyPair', {
      keyName: `domain-admin-key-${this.generateRandomSuffix()}`,
      keyType: 'rsa',
    });

    const instance = new ec2.Instance(this, 'DomainAdminInstance', {
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MEDIUM),
      machineImage: windowsAmi,
      vpc: this.vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PUBLIC,
      },
      securityGroup: securityGroup,
      keyName: keyPair.keyName,
      role: this.createEc2InstanceRole(),
      userData: this.createUserData(),
    });

    // Output the instance ID for RDP connection
    new cdk.CfnOutput(this, 'DomainAdminInstanceId', {
      value: instance.instanceId,
      description: 'Instance ID for domain administration (use for RDP connection)',
    });

    return instance;
  }

  /**
   * Create IAM role for EC2 instance
   */
  private createEc2InstanceRole(): iam.Role {
    const role = new iam.Role(this, 'Ec2InstanceRole', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      description: 'IAM role for domain admin EC2 instance',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchAgentServerPolicy'),
      ],
    });

    // Add permissions to access directory service
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'ds:DescribeDirectories',
        'ds:DescribeTrusts',
      ],
      resources: ['*'],
    }));

    return role;
  }

  /**
   * Create user data script for EC2 instance
   */
  private createUserData(): ec2.UserData {
    const userData = ec2.UserData.forWindows();

    userData.addCommands(
      '# Install required Windows features',
      'Install-WindowsFeature -Name RSAT-AD-Tools -IncludeAllSubFeature',
      'Install-WindowsFeature -Name RSAT-DNS-Server',
      '',
      '# Configure PowerShell execution policy',
      'Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force',
      '',
      '# Create setup completion marker',
      'New-Item -Path "C:\\domain-admin-setup-complete.txt" -ItemType File -Value "Setup completed on $(Get-Date)"',
      '',
      '# Log setup completion',
      'Write-EventLog -LogName Application -Source "Application" -EventId 1000 -Message "Domain admin instance setup completed"'
    );

    return userData;
  }

  /**
   * Create stack outputs
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'VpcId', {
      value: this.vpc.vpcId,
      description: 'VPC ID for the hybrid identity infrastructure',
      exportName: `${this.stackName}-VpcId`,
    });

    new cdk.CfnOutput(this, 'DirectoryId', {
      value: this.directory.ref,
      description: 'Directory ID for AWS Managed Microsoft AD',
      exportName: `${this.stackName}-DirectoryId`,
    });

    new cdk.CfnOutput(this, 'DirectoryName', {
      value: this.directory.name,
      description: 'Directory name (FQDN) for AWS Managed Microsoft AD',
      exportName: `${this.stackName}-DirectoryName`,
    });

    new cdk.CfnOutput(this, 'RdsEndpoint', {
      value: this.rdsInstance.instanceEndpoint.hostname,
      description: 'RDS SQL Server endpoint for Windows Authentication',
      exportName: `${this.stackName}-RdsEndpoint`,
    });

    new cdk.CfnOutput(this, 'DirectoryDnsIpAddresses', {
      value: cdk.Fn.join(',', this.directory.attrDnsIpAddresses),
      description: 'DNS IP addresses for the directory (configure these in your VPC DHCP options)',
    });

    // WorkSpaces setup instructions
    new cdk.CfnOutput(this, 'WorkSpacesSetupInstructions', {
      value: `To enable WorkSpaces: 1) Register directory ${this.directory.ref} with WorkSpaces service, 2) Create users in the directory, 3) Launch WorkSpaces for users`,
      description: 'Instructions for setting up WorkSpaces with this directory',
    });

    // Cost estimation
    new cdk.CfnOutput(this, 'EstimatedMonthlyCost', {
      value: 'AWS Managed AD: ~$292/month, RDS t3.medium: ~$75/month, EC2 t3.medium: ~$30/month (costs vary by region and usage)',
      description: 'Estimated monthly cost for this infrastructure',
    });
  }

  /**
   * Generate a random suffix for resource names
   */
  private generateRandomSuffix(): string {
    return Math.random().toString(36).substring(2, 8);
  }
}