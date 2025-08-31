"""
Setup configuration for the AWS CDK Python application
Automated Service Lifecycle Management with VPC Lattice and EventBridge
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="service-lifecycle-cdk",
    version="1.0.0",
    author="AWS CDK Developer",
    author_email="developer@example.com",
    description="CDK application for automated service lifecycle management",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/example/service-lifecycle-cdk",
    project_urls={
        "Bug Tracker": "https://github.com/example/service-lifecycle-cdk/issues",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/example/service-lifecycle-cdk",
    },
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
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
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
    ],
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.110.0,<3.0.0",
        "constructs>=10.0.0,<12.0.0",
        "boto3>=1.34.0",
    ],
    extras_require={
        "dev": [
            "mypy>=1.8.0",
            "pytest>=7.4.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
        ],
        "test": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "moto>=4.2.0",  # For mocking AWS services in tests
        ],
    },
    entry_points={
        "console_scripts": [
            "service-lifecycle-cdk=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "infrastructure",
        "microservices",
        "vpc-lattice",
        "eventbridge",
        "lambda",
        "automation",
        "monitoring",
        "scaling",
    ],
    license="MIT",
    zip_safe=False,
)