"""
Setup configuration for AWS CDK Python Cost Monitoring application.

This setup.py file configures the Python package for the cost monitoring
CDK application, including dependencies, metadata, and entry points.
"""

from setuptools import setup, find_packages


def read_requirements():
    """Read requirements from requirements.txt file."""
    with open("requirements.txt", "r") as f:
        return [line.strip() for line in f if line.strip() and not line.startswith("#")]


setup(
    name="cost-monitoring-cdk",
    version="1.0.0",
    description="AWS CDK Python application for cost monitoring with Cost Explorer and Budgets",
    long_description="""
    This CDK application creates a comprehensive cost monitoring solution using:
    - AWS Budgets for proactive spending alerts
    - SNS for real-time notifications
    - Multiple alert thresholds (50%, 75%, 90% actual, 100% forecasted)
    - Email notifications for budget alerts
    
    The application follows AWS best practices for cost management and provides
    a foundation for advanced cost governance workflows.
    """,
    long_description_content_type="text/plain",
    author="AWS Solutions Architecture",
    author_email="solutions@amazon.com",
    url="https://github.com/aws-samples/cost-monitoring-cdk",
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Monitoring",
        "Topic :: Office/Business :: Financial",
    ],
    keywords="aws cdk budgets cost-monitoring sns notifications financial-management",
    packages=find_packages(exclude=["tests", "tests.*"]),
    python_requires=">=3.8",
    install_requires=read_requirements(),
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "mypy>=1.5.0",
            "black>=23.7.0",
            "flake8>=6.0.0",
            "types-setuptools>=68.0.0",
        ]
    },
    entry_points={
        "console_scripts": [
            "cost-monitoring-cdk=app:main",
        ],
    },
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/cost-monitoring-cdk/issues",
        "Source": "https://github.com/aws-samples/cost-monitoring-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    include_package_data=True,
    zip_safe=False,
)