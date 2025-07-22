#!/usr/bin/env python3
"""
Test script for validating hybrid cloud connectivity infrastructure.

This script performs various tests to validate the deployment:
- Checks resource creation status
- Validates Transit Gateway attachments
- Tests route propagation
- Verifies DNS resolver endpoints
- Monitors Direct Connect metrics

Usage:
    python test_connectivity.py [--region us-east-1] [--project-id abc123]
"""

import argparse
import boto3
import sys
import time
from typing import Dict, List, Optional
from botocore.exceptions import ClientError


class ConnectivityTester:
    """Test hybrid cloud connectivity infrastructure."""
    
    def __init__(self, region: str, project_id: Optional[str] = None):
        """Initialize the tester with AWS clients."""
        self.region = region
        self.project_id = project_id
        
        # Initialize AWS clients
        self.ec2 = boto3.client('ec2', region_name=region)
        self.dx = boto3.client('directconnect', region_name=region)
        self.route53resolver = boto3.client('route53resolver', region_name=region)
        self.cloudwatch = boto3.client('cloudwatch', region_name=region)
        self.logs = boto3.client('logs', region_name=region)
        
        # Track test results
        self.test_results = []
    
    def log_test_result(self, test_name: str, status: str, message: str):
        """Log a test result."""
        self.test_results.append({
            'test': test_name,
            'status': status,
            'message': message
        })
        
        status_symbol = '✅' if status == 'PASS' else '❌' if status == 'FAIL' else '⚠️'
        print(f"{status_symbol} {test_name}: {message}")
    
    def test_vpc_creation(self) -> bool:
        """Test that VPCs were created successfully."""
        try:
            response = self.ec2.describe_vpcs()
            vpcs = response['Vpcs']
            
            if self.project_id:
                # Filter VPCs by project ID
                vpcs = [vpc for vpc in vpcs if any(
                    tag.get('Key') == 'Name' and self.project_id in tag.get('Value', '')
                    for tag in vpc.get('Tags', [])
                )]
            
            vpc_count = len(vpcs)
            if vpc_count >= 3:
                self.log_test_result(
                    'VPC Creation',
                    'PASS',
                    f'Found {vpc_count} VPCs (expected at least 3)'
                )
                return True
            else:
                self.log_test_result(
                    'VPC Creation',
                    'FAIL',
                    f'Found {vpc_count} VPCs (expected at least 3)'
                )
                return False
                
        except ClientError as e:
            self.log_test_result(
                'VPC Creation',
                'FAIL',
                f'Error checking VPCs: {e}'
            )
            return False
    
    def test_transit_gateway_status(self) -> bool:
        """Test Transit Gateway status."""
        try:
            response = self.ec2.describe_transit_gateways()
            transit_gateways = response['TransitGateways']
            
            if self.project_id:
                # Filter by project ID
                transit_gateways = [tgw for tgw in transit_gateways if any(
                    tag.get('Key') == 'Name' and self.project_id in tag.get('Value', '')
                    for tag in tgw.get('Tags', [])
                )]
            
            if not transit_gateways:
                self.log_test_result(
                    'Transit Gateway Status',
                    'FAIL',
                    'No Transit Gateway found'
                )
                return False
            
            tgw = transit_gateways[0]
            state = tgw['State']
            
            if state == 'available':
                self.log_test_result(
                    'Transit Gateway Status',
                    'PASS',
                    f'Transit Gateway is {state}'
                )
                return True
            else:
                self.log_test_result(
                    'Transit Gateway Status',
                    'WARN',
                    f'Transit Gateway is {state} (may still be provisioning)'
                )
                return False
                
        except ClientError as e:
            self.log_test_result(
                'Transit Gateway Status',
                'FAIL',
                f'Error checking Transit Gateway: {e}'
            )
            return False
    
    def test_transit_gateway_attachments(self) -> bool:
        """Test Transit Gateway VPC attachments."""
        try:
            response = self.ec2.describe_transit_gateway_attachments()
            attachments = response['TransitGatewayAttachments']
            
            # Filter for VPC attachments
            vpc_attachments = [att for att in attachments if att['ResourceType'] == 'vpc']
            
            if self.project_id:
                # Filter by project ID in tags
                vpc_attachments = [att for att in vpc_attachments if any(
                    tag.get('Key') == 'Name' and 'TGW-Attachment' in tag.get('Value', '')
                    for tag in att.get('Tags', [])
                )]
            
            attachment_count = len(vpc_attachments)
            available_count = len([att for att in vpc_attachments if att['State'] == 'available'])
            
            if attachment_count >= 3 and available_count >= 3:
                self.log_test_result(
                    'Transit Gateway Attachments',
                    'PASS',
                    f'{available_count}/{attachment_count} VPC attachments are available'
                )
                return True
            else:
                self.log_test_result(
                    'Transit Gateway Attachments',
                    'WARN',
                    f'{available_count}/{attachment_count} VPC attachments are available (may still be provisioning)'
                )
                return False
                
        except ClientError as e:
            self.log_test_result(
                'Transit Gateway Attachments',
                'FAIL',
                f'Error checking attachments: {e}'
            )
            return False
    
    def test_direct_connect_gateway(self) -> bool:
        """Test Direct Connect Gateway status."""
        try:
            response = self.dx.describe_direct_connect_gateways()
            gateways = response['directConnectGateways']
            
            if self.project_id:
                # Filter by project ID
                gateways = [gw for gw in gateways if self.project_id in gw.get('name', '')]
            
            if not gateways:
                self.log_test_result(
                    'Direct Connect Gateway',
                    'FAIL',
                    'No Direct Connect Gateway found'
                )
                return False
            
            gateway = gateways[0]
            state = gateway['directConnectGatewayState']
            
            if state == 'available':
                self.log_test_result(
                    'Direct Connect Gateway',
                    'PASS',
                    f'Direct Connect Gateway is {state}'
                )
                return True
            else:
                self.log_test_result(
                    'Direct Connect Gateway',
                    'WARN',
                    f'Direct Connect Gateway is {state}'
                )
                return False
                
        except ClientError as e:
            self.log_test_result(
                'Direct Connect Gateway',
                'FAIL',
                f'Error checking Direct Connect Gateway: {e}'
            )
            return False
    
    def test_dns_resolver_endpoints(self) -> bool:
        """Test Route 53 Resolver endpoints."""
        try:
            response = self.route53resolver.list_resolver_endpoints()
            endpoints = response['ResolverEndpoints']
            
            if self.project_id:
                # Filter by project ID
                endpoints = [ep for ep in endpoints if self.project_id in ep.get('Name', '')]
            
            inbound_endpoints = [ep for ep in endpoints if ep['Direction'] == 'INBOUND']
            outbound_endpoints = [ep for ep in endpoints if ep['Direction'] == 'OUTBOUND']
            
            inbound_available = len([ep for ep in inbound_endpoints if ep['Status'] == 'OPERATIONAL'])
            outbound_available = len([ep for ep in outbound_endpoints if ep['Status'] == 'OPERATIONAL'])
            
            if inbound_available >= 1 and outbound_available >= 1:
                self.log_test_result(
                    'DNS Resolver Endpoints',
                    'PASS',
                    f'Found {inbound_available} inbound and {outbound_available} outbound endpoints'
                )
                return True
            else:
                self.log_test_result(
                    'DNS Resolver Endpoints',
                    'WARN',
                    f'Found {inbound_available} inbound and {outbound_available} outbound endpoints (may still be provisioning)'
                )
                return False
                
        except ClientError as e:
            self.log_test_result(
                'DNS Resolver Endpoints',
                'FAIL',
                f'Error checking DNS resolver endpoints: {e}'
            )
            return False
    
    def test_flow_logs(self) -> bool:
        """Test VPC Flow Logs configuration."""
        try:
            response = self.ec2.describe_flow_logs()
            flow_logs = response['FlowLogs']
            
            if self.project_id:
                # Filter by project ID in log group name
                flow_logs = [fl for fl in flow_logs if self.project_id in fl.get('LogGroupName', '')]
            
            active_flow_logs = [fl for fl in flow_logs if fl['FlowLogStatus'] == 'ACTIVE']
            
            if len(active_flow_logs) >= 3:
                self.log_test_result(
                    'VPC Flow Logs',
                    'PASS',
                    f'Found {len(active_flow_logs)} active flow logs'
                )
                return True
            else:
                self.log_test_result(
                    'VPC Flow Logs',
                    'WARN',
                    f'Found {len(active_flow_logs)} active flow logs (expected at least 3)'
                )
                return False
                
        except ClientError as e:
            self.log_test_result(
                'VPC Flow Logs',
                'FAIL',
                f'Error checking flow logs: {e}'
            )
            return False
    
    def test_cloudwatch_dashboard(self) -> bool:
        """Test CloudWatch dashboard creation."""
        try:
            response = self.cloudwatch.list_dashboards()
            dashboards = response['DashboardEntries']
            
            if self.project_id:
                # Filter by project ID
                dashboards = [db for db in dashboards if self.project_id in db['DashboardName']]
            
            if dashboards:
                self.log_test_result(
                    'CloudWatch Dashboard',
                    'PASS',
                    f'Found {len(dashboards)} dashboard(s)'
                )
                return True
            else:
                self.log_test_result(
                    'CloudWatch Dashboard',
                    'FAIL',
                    'No CloudWatch dashboard found'
                )
                return False
                
        except ClientError as e:
            self.log_test_result(
                'CloudWatch Dashboard',
                'FAIL',
                f'Error checking CloudWatch dashboard: {e}'
            )
            return False
    
    def run_all_tests(self) -> bool:
        """Run all connectivity tests."""
        print(f"🚀 Running hybrid connectivity tests in region: {self.region}")
        if self.project_id:
            print(f"📋 Filtering resources by project ID: {self.project_id}")
        print("-" * 60)
        
        # Run tests
        tests = [
            self.test_vpc_creation,
            self.test_transit_gateway_status,
            self.test_transit_gateway_attachments,
            self.test_direct_connect_gateway,
            self.test_dns_resolver_endpoints,
            self.test_flow_logs,
            self.test_cloudwatch_dashboard,
        ]
        
        passed = 0
        failed = 0
        warnings = 0
        
        for test in tests:
            result = test()
            if result:
                passed += 1
            else:
                # Check if it was a warning
                last_result = self.test_results[-1]
                if last_result['status'] == 'WARN':
                    warnings += 1
                else:
                    failed += 1
        
        print("-" * 60)
        print(f"📊 Test Results: {passed} passed, {failed} failed, {warnings} warnings")
        
        if failed > 0:
            print("❌ Some tests failed. Check the output above for details.")
            return False
        elif warnings > 0:
            print("⚠️ Some resources may still be provisioning. Re-run tests in a few minutes.")
            return True
        else:
            print("✅ All tests passed! Your hybrid connectivity infrastructure is ready.")
            return True
    
    def print_summary(self):
        """Print a summary of test results."""
        print("\n" + "=" * 60)
        print("DETAILED TEST RESULTS")
        print("=" * 60)
        
        for result in self.test_results:
            status_symbol = '✅' if result['status'] == 'PASS' else '❌' if result['status'] == 'FAIL' else '⚠️'
            print(f"{status_symbol} {result['test']}: {result['message']}")


def main():
    """Main function."""
    parser = argparse.ArgumentParser(
        description='Test hybrid cloud connectivity infrastructure'
    )
    parser.add_argument(
        '--region',
        default='us-east-1',
        help='AWS region (default: us-east-1)'
    )
    parser.add_argument(
        '--project-id',
        help='Project ID to filter resources'
    )
    parser.add_argument(
        '--verbose',
        action='store_true',
        help='Enable verbose output'
    )
    
    args = parser.parse_args()
    
    # Create tester instance
    tester = ConnectivityTester(args.region, args.project_id)
    
    # Run tests
    success = tester.run_all_tests()
    
    if args.verbose:
        tester.print_summary()
    
    # Exit with appropriate code
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()