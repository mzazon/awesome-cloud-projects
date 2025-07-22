#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as elasticache from 'aws-cdk-lib/aws-elasticache';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Stack for Database Query Caching with ElastiCache Redis
 * 
 * This stack creates a complete caching architecture including:
 * - VPC with public and private subnets
 * - ElastiCache Redis replication group with automatic failover
 * - RDS MySQL database for testing
 * - EC2 instance for cache testing and validation
 * - Security groups with least privilege access
 */
export class DatabaseQueryCachingStack extends cdk.Stack {
  public readonly vpc: ec2.Vpc;
  public readonly redisCluster: elasticache.CfnReplicationGroup;
  public readonly database: rds.DatabaseInstance;
  public readonly testInstance: ec2.Instance;
  public readonly redisEndpoint: string;
  public readonly databaseEndpoint: string;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Create VPC with public and private subnets for multi-AZ deployment
    this.vpc = new ec2.Vpc(this, 'CacheVpc', {
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
        },
      ],
      enableDnsHostnames: true,
      enableDnsSupport: true,
    });

    // Create security groups for cache and database access
    const cacheSecurityGroup = this.createCacheSecurityGroup();
    const databaseSecurityGroup = this.createDatabaseSecurityGroup();
    const ec2SecurityGroup = this.createEC2SecurityGroup();

    // Allow cache access from EC2 instances
    cacheSecurityGroup.addIngressRule(
      ec2SecurityGroup,
      ec2.Port.tcp(6379),
      'Allow Redis access from EC2 instances'
    );

    // Allow database access from EC2 instances
    databaseSecurityGroup.addIngressRule(
      ec2SecurityGroup,
      ec2.Port.tcp(3306),
      'Allow MySQL access from EC2 instances'
    );

    // Create ElastiCache subnet group for multi-AZ placement
    const cacheSubnetGroup = new elasticache.CfnSubnetGroup(this, 'CacheSubnetGroup', {
      description: 'Subnet group for ElastiCache Redis cluster',
      subnetIds: this.vpc.privateSubnets.map(subnet => subnet.subnetId),
      cacheSubnetGroupName: `cache-subnet-group-${this.stackName.toLowerCase()}`,
    });

    // Create custom parameter group for Redis optimization
    const parameterGroup = new elasticache.CfnParameterGroup(this, 'CacheParameterGroup', {
      cacheParameterGroupFamily: 'redis7.x',
      description: 'Custom parameters for database caching optimization',
      properties: {
        'maxmemory-policy': 'allkeys-lru', // LRU eviction for cache-aside pattern
        'timeout': '300',                   // Connection timeout
        'tcp-keepalive': '60',             // TCP keepalive
      },
    });

    // Create ElastiCache Redis replication group with automatic failover
    this.redisCluster = new elasticache.CfnReplicationGroup(this, 'RedisCluster', {
      replicationGroupDescription: 'Redis cluster for database query caching',
      engine: 'redis',
      cacheNodeType: 'cache.t3.micro',
      numCacheClusters: 2,
      automaticFailoverEnabled: true,
      multiAzEnabled: true,
      cacheParameterGroupName: parameterGroup.ref,
      cacheSubnetGroupName: cacheSubnetGroup.ref,
      securityGroupIds: [cacheSecurityGroup.securityGroupId],
      port: 6379,
      transitEncryptionEnabled: true,
      atRestEncryptionEnabled: true,
      // Backup configuration for data persistence
      snapshotRetentionLimit: 1,
      snapshotWindow: '03:00-04:00',
      // Maintenance configuration
      preferredMaintenanceWindow: 'sun:04:00-sun:05:00',
      // CloudWatch logging
      logDeliveryConfigurations: [
        {
          destinationType: 'cloudwatch-logs',
          destinationDetails: {
            logGroup: `/aws/elasticache/${this.stackName.toLowerCase()}/slow-log`,
          },
          logFormat: 'text',
          logType: 'slow-log',
        },
      ],
    });

    // Add dependency to ensure subnet group is created first
    this.redisCluster.addDependency(cacheSubnetGroup);
    this.redisCluster.addDependency(parameterGroup);

    // Create CloudWatch log group for ElastiCache logs
    new logs.LogGroup(this, 'CacheLogGroup', {
      logGroupName: `/aws/elasticache/${this.stackName.toLowerCase()}/slow-log`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create RDS subnet group for multi-AZ database deployment
    const dbSubnetGroup = new rds.SubnetGroup(this, 'DatabaseSubnetGroup', {
      vpc: this.vpc,
      description: 'Subnet group for RDS database',
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      },
    });

    // Create RDS MySQL database for cache testing
    this.database = new rds.DatabaseInstance(this, 'TestDatabase', {
      engine: rds.DatabaseInstanceEngine.mysql({
        version: rds.MysqlEngineVersion.VER_8_0,
      }),
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO),
      credentials: rds.Credentials.fromGeneratedSecret('admin', {
        secretName: `${this.stackName}/database-credentials`,
        excludeCharacters: ' %+~`#$&*()|[]{}:;<>?!\'/@"\\',
      }),
      vpc: this.vpc,
      subnetGroup: dbSubnetGroup,
      securityGroups: [databaseSecurityGroup],
      allocatedStorage: 20,
      storageType: rds.StorageType.GP2,
      backupRetention: cdk.Duration.days(0), // Disable backups for test instance
      deleteAutomatedBackups: true,
      deletionProtection: false,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      // Performance monitoring
      enablePerformanceInsights: true,
      performanceInsightRetention: rds.PerformanceInsightRetention.DEFAULT,
      // CloudWatch logging
      cloudwatchLogsExports: ['error', 'general', 'slow'],
      cloudwatchLogsRetention: logs.RetentionDays.ONE_WEEK,
    });

    // Create IAM role for EC2 instance with necessary permissions
    const ec2Role = new iam.Role(this, 'EC2Role', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      description: 'IAM role for EC2 instance to access ElastiCache and RDS',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
      ],
      inlinePolicies: {
        CacheAndDatabaseAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'elasticache:DescribeReplicationGroups',
                'elasticache:DescribeCacheClusters',
                'rds:DescribeDBInstances',
                'secretsmanager:GetSecretValue',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Create instance profile for EC2 role
    const instanceProfile = new iam.CfnInstanceProfile(this, 'EC2InstanceProfile', {
      roles: [ec2Role.roleName],
    });

    // Create user data script for EC2 instance setup
    const userData = ec2.UserData.forLinux();
    userData.addCommands(
      '#!/bin/bash',
      'yum update -y',
      'yum install -y redis mysql amazon-cloudwatch-agent',
      
      // Install Python dependencies for cache testing
      'amazon-linux-extras install -y python3.8',
      'pip3 install redis pymysql boto3',
      
      // Create cache testing script
      'cat > /home/ec2-user/cache_demo.py << "EOF"',
      this.getCacheDemoScript(),
      'EOF',
      'chown ec2-user:ec2-user /home/ec2-user/cache_demo.py',
      'chmod +x /home/ec2-user/cache_demo.py',
      
      // Create environment setup script
      'cat > /home/ec2-user/setup_env.sh << "EOF"',
      '#!/bin/bash',
      `export REDIS_HOST="${this.redisCluster.attrRedisEndpointAddress}"`,
      `export MYSQL_HOST="${this.database.instanceEndpoint.hostname}"`,
      'export MYSQL_USER="admin"',
      'export MYSQL_DB="testdb"',
      '# Get database password from Secrets Manager',
      `SECRET_ARN="${this.database.secret?.secretArn}"`,
      'export MYSQL_PASSWORD=$(aws secretsmanager get-secret-value --secret-id $SECRET_ARN --query SecretString --output text | jq -r .password)',
      'echo "Environment variables configured successfully"',
      'echo "Redis Host: $REDIS_HOST"',
      'echo "MySQL Host: $MYSQL_HOST"',
      'EOF',
      'chown ec2-user:ec2-user /home/ec2-user/setup_env.sh',
      'chmod +x /home/ec2-user/setup_env.sh',
      
      // Install CloudWatch agent
      '/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s',
    );

    // Create EC2 instance for cache testing
    this.testInstance = new ec2.Instance(this, 'CacheTestInstance', {
      vpc: this.vpc,
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO),
      machineImage: ec2.MachineImage.latestAmazonLinux({
        generation: ec2.AmazonLinuxGeneration.AMAZON_LINUX_2,
      }),
      securityGroup: ec2SecurityGroup,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PUBLIC, // Public subnet for easier access
      },
      userData: userData,
      role: ec2Role,
      keyName: undefined, // Use SSM Session Manager instead of SSH keys
    });

    // Store endpoints for easy access
    this.redisEndpoint = this.redisCluster.attrRedisEndpointAddress;
    this.databaseEndpoint = this.database.instanceEndpoint.hostname;

    // Create outputs for important resource information
    this.createOutputs();

    // Add tags to all resources
    this.addResourceTags();
  }

  /**
   * Create security group for ElastiCache Redis cluster
   */
  private createCacheSecurityGroup(): ec2.SecurityGroup {
    return new ec2.SecurityGroup(this, 'CacheSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for ElastiCache Redis cluster',
      allowAllOutbound: false, // Explicitly control outbound traffic
    });
  }

  /**
   * Create security group for RDS database
   */
  private createDatabaseSecurityGroup(): ec2.SecurityGroup {
    return new ec2.SecurityGroup(this, 'DatabaseSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for RDS MySQL database',
      allowAllOutbound: false, // Explicitly control outbound traffic
    });
  }

  /**
   * Create security group for EC2 instances
   */
  private createEC2SecurityGroup(): ec2.SecurityGroup {
    const securityGroup = new ec2.SecurityGroup(this, 'EC2SecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for EC2 test instances',
      allowAllOutbound: true, // Allow outbound for software installation and AWS API calls
    });

    // Allow HTTPS for AWS API calls and software downloads
    securityGroup.addEgressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(443),
      'Allow HTTPS outbound for AWS APIs and downloads'
    );

    // Allow HTTP for software downloads
    securityGroup.addEgressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(80),
      'Allow HTTP outbound for software downloads'
    );

    return securityGroup;
  }

  /**
   * Get the cache demonstration script content
   */
  private getCacheDemoScript(): string {
    return `import redis
import pymysql
import json
import time
import sys
import os
import boto3

# Configuration from environment variables
REDIS_HOST = os.environ.get('REDIS_HOST', 'localhost')
MYSQL_HOST = os.environ.get('MYSQL_HOST', 'localhost')
MYSQL_USER = os.environ.get('MYSQL_USER', 'admin')
MYSQL_PASSWORD = os.environ.get('MYSQL_PASSWORD')
MYSQL_DB = os.environ.get('MYSQL_DB', 'testdb')

def get_redis_client():
    """Create Redis client with SSL support"""
    return redis.Redis(
        host=REDIS_HOST,
        port=6379,
        decode_responses=True,
        ssl=True,
        ssl_cert_reqs=None
    )

def get_mysql_connection():
    """Create MySQL connection"""
    return pymysql.connect(
        host=MYSQL_HOST,
        user=MYSQL_USER,
        password=MYSQL_PASSWORD,
        database=MYSQL_DB,
        autocommit=True
    )

def cache_aside_get(redis_client, key, db_query_func, ttl=300):
    """Implement cache-aside pattern"""
    try:
        # Try to get from cache first
        cached_data = redis_client.get(key)
        if cached_data:
            print(f"✅ Cache HIT for key: {key}")
            return json.loads(cached_data)
        
        # Cache miss - get from database
        print(f"❌ Cache MISS for key: {key}")
        data = db_query_func()
        
        # Store in cache with TTL
        if data:
            redis_client.setex(key, ttl, json.dumps(data))
            print(f"📝 Data cached with {ttl}s TTL")
        
        return data
    except Exception as e:
        print(f"Error in cache_aside_get: {e}")
        return db_query_func()  # Fallback to database

def demo_cache_performance():
    """Demonstrate cache performance improvement"""
    try:
        redis_client = get_redis_client()
        
        # Test Redis connectivity
        redis_client.ping()
        print("✅ Redis connection successful")
        
        # Simulate database query function
        def simulate_db_query():
            time.sleep(0.1)  # Simulate database latency
            return {
                "id": 1,
                "name": "Sample Product",
                "price": 29.99,
                "description": "A sample product for cache testing"
            }
        
        cache_key = "product:1"
        
        # First call - cache miss
        print("\\n--- First call (Cache Miss) ---")
        start_time = time.time()
        result1 = cache_aside_get(redis_client, cache_key, simulate_db_query)
        db_time = time.time() - start_time
        
        # Second call - cache hit
        print("\\n--- Second call (Cache Hit) ---")
        start_time = time.time()
        result2 = cache_aside_get(redis_client, cache_key, simulate_db_query)
        cache_time = time.time() - start_time
        
        # Performance comparison
        print(f"\\n🚀 Performance Comparison:")
        print(f"Database query time: {db_time:.4f} seconds")
        print(f"Cache query time: {cache_time:.4f} seconds")
        improvement = db_time / cache_time if cache_time > 0 else 1
        print(f"Speed improvement: {improvement:.1f}x faster")
        
        # Cache statistics
        print(f"\\n📊 Cache Statistics:")
        info = redis_client.info('stats')
        print(f"Cache hits: {info.get('keyspace_hits', 0)}")
        print(f"Cache misses: {info.get('keyspace_misses', 0)}")
        
        return True
        
    except Exception as e:
        print(f"❌ Error in demo: {e}")
        return False

if __name__ == "__main__":
    print("🧪 Starting cache performance demonstration...")
    success = demo_cache_performance()
    sys.exit(0 if success else 1)`;
  }

  /**
   * Create CloudFormation outputs
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'VpcId', {
      value: this.vpc.vpcId,
      description: 'VPC ID for the caching infrastructure',
      exportName: `${this.stackName}-VpcId`,
    });

    new cdk.CfnOutput(this, 'RedisEndpoint', {
      value: this.redisCluster.attrRedisEndpointAddress,
      description: 'ElastiCache Redis cluster endpoint',
      exportName: `${this.stackName}-RedisEndpoint`,
    });

    new cdk.CfnOutput(this, 'RedisPort', {
      value: this.redisCluster.attrRedisEndpointPort.toString(),
      description: 'ElastiCache Redis cluster port',
      exportName: `${this.stackName}-RedisPort`,
    });

    new cdk.CfnOutput(this, 'DatabaseEndpoint', {
      value: this.database.instanceEndpoint.hostname,
      description: 'RDS MySQL database endpoint',
      exportName: `${this.stackName}-DatabaseEndpoint`,
    });

    new cdk.CfnOutput(this, 'DatabasePort', {
      value: this.database.instanceEndpoint.port.toString(),
      description: 'RDS MySQL database port',
      exportName: `${this.stackName}-DatabasePort`,
    });

    new cdk.CfnOutput(this, 'DatabaseSecretArn', {
      value: this.database.secret?.secretArn || 'N/A',
      description: 'ARN of the secret containing database credentials',
      exportName: `${this.stackName}-DatabaseSecretArn`,
    });

    new cdk.CfnOutput(this, 'TestInstanceId', {
      value: this.testInstance.instanceId,
      description: 'EC2 instance ID for cache testing',
      exportName: `${this.stackName}-TestInstanceId`,
    });

    new cdk.CfnOutput(this, 'ConnectionInstructions', {
      value: `aws ssm start-session --target ${this.testInstance.instanceId}`,
      description: 'Command to connect to test instance via SSM Session Manager',
    });
  }

  /**
   * Add consistent tags to all resources
   */
  private addResourceTags(): void {
    const tags = {
      Project: 'DatabaseQueryCaching',
      Environment: 'Development',
      Purpose: 'Performance Testing',
      ManagedBy: 'AWS CDK',
    };

    Object.entries(tags).forEach(([key, value]) => {
      cdk.Tags.of(this).add(key, value);
    });
  }
}

// CDK App
const app = new cdk.App();

// Create stack with recommended naming convention
new DatabaseQueryCachingStack(app, 'DatabaseQueryCachingStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'Database Query Caching with ElastiCache Redis - CDK TypeScript Implementation',
  tags: {
    Project: 'AWS-Recipes',
    Recipe: 'database-query-caching-elasticache',
    IaCTool: 'CDK-TypeScript',
  },
});

// Synthesize the app
app.synth();