#!/usr/bin/env node

/**
 * Blockchain-Based Voting System CDK Application
 * 
 * This CDK application deploys a secure, transparent blockchain voting system
 * using Amazon Managed Blockchain, Lambda functions, DynamoDB, and other AWS services.
 * 
 * Key Features:
 * - Immutable vote recording on Ethereum blockchain
 * - Encrypted voter authentication with KMS
 * - Real-time vote monitoring with EventBridge
 * - Comprehensive audit trails and compliance
 * - Serverless architecture for scalability
 * 
 * @author CDK Application Generator
 * @version 1.0.0
 */

import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import { BlockchainVotingSystemStack } from './lib/blockchain-voting-system-stack';

/**
 * Main CDK Application class for the Blockchain Voting System
 */
class BlockchainVotingApp extends cdk.App {
  constructor() {
    super();

    // Get environment configuration
    const account = process.env.CDK_DEFAULT_ACCOUNT;
    const region = process.env.CDK_DEFAULT_REGION || 'us-east-1';
    const environment = process.env.ENVIRONMENT || 'dev';
    const adminEmail = process.env.ADMIN_EMAIL || 'admin@example.com';

    // Validate required environment variables
    this.validateEnvironment(account, region, environment, adminEmail);

    // Create the main voting system stack
    const votingSystemStack = new BlockchainVotingSystemStack(this, 'BlockchainVotingSystem', {
      env: {
        account,
        region,
      },
      environment,
      adminEmail,
      description: `Blockchain-based voting system infrastructure for ${environment} environment`,
      tags: {
        Project: 'BlockchainVotingSystem',
        Environment: environment,
        Repository: 'aws-recipes-blockchain-voting',
        ManagedBy: 'CDK',
        CostCenter: 'VotingSystem',
      },
    });

    // Add additional tags for cost allocation and governance
    cdk.Tags.of(votingSystemStack).add('Application', 'VotingSystem');
    cdk.Tags.of(votingSystemStack).add('Owner', 'ElectionCommission');
    cdk.Tags.of(votingSystemStack).add('SecurityLevel', 'High');
    cdk.Tags.of(votingSystemStack).add('ComplianceRequired', 'true');
  }

  /**
   * Validates required environment variables and configuration
   */
  private validateEnvironment(account: string | undefined, region: string, environment: string, adminEmail: string): void {
    if (!account) {
      throw new Error('CDK_DEFAULT_ACCOUNT must be set');
    }

    if (!region) {
      throw new Error('CDK_DEFAULT_REGION must be set');
    }

    if (!['dev', 'staging', 'prod'].includes(environment)) {
      throw new Error('ENVIRONMENT must be one of: dev, staging, prod');
    }

    // Basic email validation
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(adminEmail)) {
      throw new Error('ADMIN_EMAIL must be a valid email address');
    }

    // Validate account format
    if (!/^\d{12}$/.test(account)) {
      throw new Error('AWS account ID must be 12 digits');
    }
  }
}

// Create and synthesize the CDK application
const app = new BlockchainVotingApp();
app.synth();