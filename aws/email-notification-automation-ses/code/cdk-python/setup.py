"""
Setup configuration for Automated Email Notification Systems CDK Python application.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="automated-email-notification-systems",
    version="1.0.0",
    author="AWS CDK Developer",
    author_email="developer@example.com",
    description="CDK Python application for automated email notification systems using SES, Lambda, and EventBridge",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/your-org/automated-email-notification-systems",
    project_urls={
        "Bug Tracker": "https://github.com/your-org/automated-email-notification-systems/issues",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Typing :: Typed",
    ],
    package_dir={"": "src"},
    packages=setuptools.find_packages(where="src"),
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.100.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0.0,<8.0.0",
            "pytest-cov>=4.0.0,<5.0.0",
            "black>=22.0.0,<24.0.0",
            "isort>=5.10.0,<6.0.0",
            "mypy>=1.0.0,<2.0.0",
            "flake8>=5.0.0,<7.0.0",
            "bandit>=1.7.0,<2.0.0",
            "safety>=2.0.0,<3.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0,<7.0.0",
            "sphinx-rtd-theme>=1.0.0,<2.0.0",
        ],
        "typing": [
            "boto3-stubs[essential]>=1.26.0",
            "types-requests>=2.28.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "email-notification-app=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "cloud-development-kit",
        "email",
        "notifications",
        "ses",
        "lambda",
        "eventbridge",
        "serverless",
        "event-driven",
        "automation",
    ],
    include_package_data=True,
    zip_safe=False,
)