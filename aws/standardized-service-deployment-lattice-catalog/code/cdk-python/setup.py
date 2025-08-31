"""
Setup configuration for Standardized Service Deployment with VPC Lattice and Service Catalog CDK Application

This setup.py file configures the Python package for the CDK application that creates
a standardized service deployment infrastructure using AWS Service Catalog and VPC Lattice.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="standardized-service-deployment-lattice-catalog",
    version="1.0.0",
    author="AWS Recipe Generator",
    author_email="example@example.com",
    description="CDK Python application for standardized VPC Lattice service deployment via Service Catalog",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/example/standardized-service-deployment-lattice-catalog",
    project_urls={
        "Bug Tracker": "https://github.com/example/standardized-service-deployment-lattice-catalog/issues",
    },
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
        "Topic :: Internet :: WWW/HTTP",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
    ],
    packages=setuptools.find_packages(),
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.150.0",
        "constructs>=10.0.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "types-requests>=2.28.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "deploy-service-catalog=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "vpc-lattice",
        "service-catalog",
        "infrastructure",
        "standardization",
        "service-mesh",
        "governance",
        "self-service",
        "microservices",
        "networking",
        "cloudformation",
        "devops",
    ],
    zip_safe=False,
)