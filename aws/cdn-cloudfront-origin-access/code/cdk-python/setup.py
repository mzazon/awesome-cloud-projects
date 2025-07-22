"""
Setup configuration for CloudFront CDN with Origin Access Controls CDK application.

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and installation instructions.
"""

from setuptools import setup, find_packages

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    with open("requirements.txt", "r") as req_file:
        return [
            line.strip()
            for line in req_file
            if line.strip() and not line.startswith("#")
        ]

# Read the README file for long description
def read_readme():
    """Read README.md file for package description."""
    try:
        with open("README.md", "r", encoding="utf-8") as readme_file:
            return readme_file.read()
    except FileNotFoundError:
        return "CloudFront CDN with Origin Access Controls - AWS CDK Python Application"

setup(
    # Package metadata
    name="cloudfront-cdn-oac-cdk",
    version="1.0.0",
    description="AWS CDK Python application for CloudFront CDN with Origin Access Controls",
    long_description=read_readme(),
    long_description_content_type="text/markdown",
    
    # Author information
    author="AWS CDK Recipe Generator",
    author_email="recipes@aws-cdk.example.com",
    
    # URLs
    url="https://github.com/aws-samples/cdk-recipes",
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/cdk-recipes/issues",
        "Source": "https://github.com/aws-samples/cdk-recipes",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    
    # Package discovery
    packages=find_packages(exclude=["tests", "tests.*"]),
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=[
        "aws-cdk-lib>=2.166.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.35.0",
        "python-dotenv>=1.0.0",
    ],
    
    # Optional dependencies for development
    extras_require={
        "dev": [
            "pytest>=8.3.0",
            "pytest-cov>=6.0.0",
            "mypy>=1.13.0",
            "black>=24.10.0",
            "flake8>=7.1.0",
            "isort>=5.13.0",
            "bandit>=1.7.0",
            "safety>=3.2.0",
        ],
        "docs": [
            "sphinx>=8.1.0",
            "sphinx-rtd-theme>=3.0.0",
        ],
        "testing": [
            "moto>=5.0.0",
            "pytest-mock>=3.14.0",
        ],
    },
    
    # Package classification
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: HTTP Servers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Operating System :: OS Independent",
        "Framework :: AWS CDK",
        "Topic :: Internet :: WWW/HTTP :: Site Management",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "cloudfront",
        "cdn",
        "origin-access-control",
        "s3",
        "waf",
        "security",
        "content-delivery",
        "infrastructure-as-code",
        "iac",
    ],
    
    # Entry points for command-line scripts
    entry_points={
        "console_scripts": [
            "cdk-deploy=app:main",
        ],
    },
    
    # Include additional files
    include_package_data=True,
    
    # Data files to include
    package_data={
        "": [
            "*.md",
            "*.txt",
            "*.json",
            "*.yaml",
            "*.yml",
        ],
    },
    
    # Exclude patterns
    exclude_package_data={
        "": [
            "tests/*",
            "*.pyc",
            "__pycache__/*",
            "cdk.out/*",
            ".git/*",
            ".github/*",
            "node_modules/*",
        ],
    },
    
    # Zip safe configuration
    zip_safe=False,
    
    # Platform compatibility
    platforms=["any"],
    
    # License
    license="MIT",
    
    # Maintenance status
    maintainer="AWS CDK Recipes Team",
    maintainer_email="cdk-recipes@aws.example.com",
)

# Additional setup commands
if __name__ == "__main__":
    print("Setting up CloudFront CDN with Origin Access Controls CDK application...")
    print("Dependencies will be installed from requirements.txt")
    print("To install in development mode: pip install -e .")
    print("To install with dev dependencies: pip install -e .[dev]")
    print("To run tests: pytest")
    print("To deploy: cdk deploy")