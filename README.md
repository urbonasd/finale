# Terraform AWS Infra for a Web App

This project contains Terraform code for a basic AWS infrastructure with a containerized Node.js web app. It also includes a GitHub Actions workflow for CI with security scanning.

## Infrastructure

Following AWS resources are created:

*   **VPC**: New VPC to isolate the application.
*   **Public Subnet**: A subnet accessible from the internet.
*   **Internet Gateway and Route Table**: To allow internet traffic.
*   **Security Group**: A firewall to control traffic.
*   **ECR (Elastic Container Registry)**: A private Docker container registry to store the application's image.
*   **ECS (Elastic Container Service)**: A service to run the application.
*   **Application Load Balancer**: Distributes incoming traffic.

## Application

The application is a simple "Hello World" Node.js application using Express framework.
