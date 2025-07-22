"""
Setup configuration for Fine-Grained Access Control CDK Python Application

This setup.py file configures the Python package for the CDK application that
demonstrates advanced IAM policy patterns with conditions and context-aware access controls.
"""

import setuptools
from pathlib import Path

# Read README file for long description
readme_path = Path(__file__).parent / "README.md"
if readme_path.exists():
    with open(readme_path, "r", encoding="utf-8") as fh:
        long_description = fh.read()
else:
    long_description = "CDK Python application for fine-grained access control with IAM policies and conditions"

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as fh:
        requirements = [
            line.strip() 
            for line in fh.readlines() 
            if line.strip() and not line.startswith("#")
        ]
else:
    requirements = [
        "aws-cdk-lib>=2.150.0,<3.0.0",
        "constructs>=10.3.0,<11.0.0",
    ]

setuptools.setup(
    name="fine-grained-access-control-cdk",
    version="1.0.0",
    
    author="AWS Recipes Team",
    author_email="recipes@aws.com",
    
    description="CDK Python application demonstrating fine-grained access control with IAM policies and conditions",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    url="https://github.com/aws-samples/cloud-recipes",
    
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    
    install_requires=requirements,
    
    python_requires=">=3.8",
    
    classifiers=[
        # Development Status
        "Development Status :: 4 - Beta",
        
        # Intended Audience
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "Intended Audience :: Information Technology",
        
        # Topic
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: System :: Systems Administration",
        "Topic :: Security",
        
        # License
        "License :: OSI Approved :: MIT License",
        
        # Python Versions
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        
        # Operating System
        "Operating System :: OS Independent",
    ],
    
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "iam",
        "security",
        "access-control",
        "policies",
        "conditions",
        "least-privilege",
        "abac",
        "rbac"
    ],
    
    entry_points={
        "console_scripts": [
            "cdk-deploy=app:main",
        ],
    },
    
    extras_require={
        "dev": [
            "pytest>=7.4.0,<8.0.0",
            "pytest-cov>=4.1.0,<5.0.0",
            "black>=23.7.0,<24.0.0",
            "flake8>=6.0.0,<7.0.0",
            "mypy>=1.5.0,<2.0.0",
        ],
        "stubs": [
            "boto3-stubs[iam,s3,logs]>=1.34.0,<2.0.0",
        ],
    },
    
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/cloud-recipes/issues",
        "Source": "https://github.com/aws-samples/cloud-recipes",
        "Documentation": "https://github.com/aws-samples/cloud-recipes/tree/main/aws/fine-grained-access-control-iam-policies-conditions",
    },
    
    # Package data
    include_package_data=True,
    zip_safe=False,
)