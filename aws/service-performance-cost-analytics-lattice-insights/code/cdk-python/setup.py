"""
Setup configuration for Service Performance Cost Analytics CDK Python application.

This setup.py file configures the Python package for the CDK application that deploys
infrastructure for correlating VPC Lattice service mesh performance metrics with AWS costs.
"""

from setuptools import setup, find_packages

# Read version from a separate file or define here
VERSION = "1.0.0"

# Read long description from README if available
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "Service Performance Cost Analytics with VPC Lattice and CloudWatch Insights CDK Application"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    try:
        with open("requirements.txt", "r", encoding="utf-8") as req_file:
            return [
                line.strip() 
                for line in req_file 
                if line.strip() and not line.startswith("#") and not line.startswith("types-")
            ]
    except FileNotFoundError:
        # Fallback requirements if file not found
        return [
            "aws-cdk-lib>=2.167.0,<3.0.0",
            "constructs>=10.0.0,<11.0.0"
        ]

setup(
    name="service-performance-cost-analytics-cdk",
    version=VERSION,
    author="AWS CDK Developer",
    author_email="developer@example.com",
    description="CDK application for Service Performance Cost Analytics with VPC Lattice and CloudWatch Insights",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/service-performance-cost-analytics",
    
    # Package configuration
    packages=find_packages(),
    py_modules=["app"],
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "types-setuptools>=57.0.0"
        ]
    },
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Classification metadata
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: Site Management",
        "Topic :: System :: Monitoring",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "vpc-lattice",
        "service-mesh",
        "performance",
        "cost-analytics",
        "cloudwatch",
        "monitoring",
        "observability"
    ],
    
    # Entry points for command line tools (if needed)
    entry_points={
        "console_scripts": [
            "deploy-analytics=app:main",
        ],
    },
    
    # Include additional files
    include_package_data=True,
    
    # Zip safety
    zip_safe=False,
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/service-performance-cost-analytics/issues",
        "Source": "https://github.com/aws-samples/service-performance-cost-analytics",
        "Documentation": "https://docs.aws.amazon.com/vpc-lattice/",
        "AWS CDK": "https://aws.amazon.com/cdk/",
    }
)

# Additional setup for CDK-specific configurations
if __name__ == "__main__":
    print("Service Performance Cost Analytics CDK Application Setup")
    print("=" * 60)
    print(f"Version: {VERSION}")
    print("Description: CDK application for correlating VPC Lattice performance with AWS costs")
    print("")
    print("This setup configures a Python package for deploying:")
    print("• VPC Lattice Service Network with comprehensive monitoring")
    print("• Lambda functions for performance analysis and cost correlation")
    print("• CloudWatch Log Groups and Insights queries")
    print("• EventBridge scheduling for automated analytics")
    print("• IAM roles with appropriate permissions")
    print("• CloudWatch Dashboard for visualization")
    print("")
    print("For deployment instructions, see the README.md file.")
    print("=" * 60)