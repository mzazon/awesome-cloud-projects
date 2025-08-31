#!/usr/bin/env python3
"""
Validation script for Simple File Sharing with Transfer Family Web Apps CDK Application.

This script performs basic validation and testing of the CDK application without
actually deploying resources to AWS.
"""

import ast
import sys
import subprocess
from pathlib import Path
from typing import List, Tuple


def check_python_syntax(file_path: Path) -> Tuple[bool, str]:
    """
    Check if a Python file has valid syntax.
    
    Args:
        file_path: Path to the Python file
        
    Returns:
        Tuple of (is_valid, error_message)
    """
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            source = f.read()
        
        ast.parse(source)
        return True, ""
    except SyntaxError as e:
        return False, f"Syntax error in {file_path}: {e}"
    except Exception as e:
        return False, f"Error reading {file_path}: {e}"


def check_imports() -> Tuple[bool, List[str]]:
    """
    Check if all required imports are available.
    
    Returns:
        Tuple of (all_available, list_of_missing_modules)
    """
    required_modules = [
        'aws_cdk',
        'constructs',
        'cdk_nag',
        'boto3',
        'botocore',
    ]
    
    missing_modules = []
    
    for module in required_modules:
        try:
            __import__(module)
        except ImportError:
            missing_modules.append(module)
    
    return len(missing_modules) == 0, missing_modules


def run_cdk_synth() -> Tuple[bool, str]:
    """
    Run CDK synth to validate the application.
    
    Returns:
        Tuple of (success, output_or_error)
    """
    try:
        # Run cdk synth with minimal context
        result = subprocess.run([
            'cdk', 'synth',
            '-c', 'identity_center_instance_arn=arn:aws:sso:::instance/ssoins-test123456',
            '-c', 'identity_store_id=d-test123456',
            '-c', 'create_demo_user=false',  # Skip user creation for validation
            '-c', 'enable_cdk_nag=false',    # Skip CDK Nag for validation
        ], capture_output=True, text=True, timeout=60)
        
        if result.returncode == 0:
            return True, "CDK synth completed successfully"
        else:
            return False, f"CDK synth failed: {result.stderr}"
            
    except subprocess.TimeoutExpired:
        return False, "CDK synth timed out"
    except subprocess.CalledProcessError as e:
        return False, f"CDK synth failed: {e}"
    except Exception as e:
        return False, f"Error running CDK synth: {e}"


def check_file_structure() -> Tuple[bool, List[str]]:
    """
    Check if all required files are present.
    
    Returns:
        Tuple of (all_present, list_of_missing_files)
    """
    required_files = [
        'app.py',
        'requirements.txt',
        'setup.py',
        'cdk.json',
        'README.md',
        'deploy.sh',
        'destroy.sh',
    ]
    
    missing_files = []
    current_dir = Path('.')
    
    for file_name in required_files:
        file_path = current_dir / file_name
        if not file_path.exists():
            missing_files.append(file_name)
    
    return len(missing_files) == 0, missing_files


def validate_cdk_json() -> Tuple[bool, str]:
    """
    Validate the cdk.json configuration file.
    
    Returns:
        Tuple of (is_valid, error_message)
    """
    try:
        import json
        
        with open('cdk.json', 'r') as f:
            config = json.load(f)
        
        # Check required fields
        required_fields = ['app', 'context']
        for field in required_fields:
            if field not in config:
                return False, f"Missing required field '{field}' in cdk.json"
        
        # Check app command
        if not config['app'].startswith('python'):
            return False, "App command should start with 'python'"
        
        return True, ""
        
    except json.JSONDecodeError as e:
        return False, f"Invalid JSON in cdk.json: {e}"
    except Exception as e:
        return False, f"Error validating cdk.json: {e}"


def main():
    """Main validation function."""
    print("🔍 Validating Simple File Sharing with Transfer Family Web Apps CDK Application")
    print("=" * 80)
    print()
    
    validation_passed = True
    
    # Check file structure
    print("📁 Checking file structure...")
    files_ok, missing_files = check_file_structure()
    if files_ok:
        print("✅ All required files are present")
    else:
        print(f"❌ Missing files: {', '.join(missing_files)}")
        validation_passed = False
    print()
    
    # Check Python syntax
    print("🐍 Checking Python syntax...")
    syntax_ok, syntax_error = check_python_syntax(Path('app.py'))
    if syntax_ok:
        print("✅ Python syntax is valid")
    else:
        print(f"❌ {syntax_error}")
        validation_passed = False
    print()
    
    # Check cdk.json
    print("⚙️ Validating cdk.json...")
    json_ok, json_error = validate_cdk_json()
    if json_ok:
        print("✅ cdk.json is valid")
    else:
        print(f"❌ {json_error}")
        validation_passed = False
    print()
    
    # Check imports (only if syntax is OK)
    if syntax_ok:
        print("📦 Checking imports...")
        imports_ok, missing_modules = check_imports()
        if imports_ok:
            print("✅ All required modules are available")
        else:
            print(f"❌ Missing modules: {', '.join(missing_modules)}")
            print("💡 Run: pip install -r requirements.txt")
            validation_passed = False
        print()
        
        # Run CDK synth (only if imports are OK)
        if imports_ok:
            print("🏗️ Running CDK synth validation...")
            synth_ok, synth_message = run_cdk_synth()
            if synth_ok:
                print("✅ CDK application synthesizes correctly")
            else:
                print(f"❌ {synth_message}")
                validation_passed = False
            print()
    
    # Summary
    print("=" * 80)
    if validation_passed:
        print("🎉 All validations passed! The CDK application is ready for deployment.")
        print()
        print("Next steps:")
        print("1. Ensure IAM Identity Center is enabled in your AWS account")
        print("2. Run: ./deploy.sh")
        sys.exit(0)
    else:
        print("❌ Validation failed. Please fix the issues above before deployment.")
        sys.exit(1)


if __name__ == "__main__":
    main()