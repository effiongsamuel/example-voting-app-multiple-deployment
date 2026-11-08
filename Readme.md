# Example Voting App: 5-Tier Architecture

This project demonstrates a simple multi-service application built around a
five-tier architecture. It combines a Python vote frontend, a .NET worker,
a Node.js results dashboard, Redis for asynchronous messaging, and PostgreSQL
for durable storage. The repository also includes deployment examples for
Docker Compose, Docker Swarm, Kubernetes, and Terraform/Ansible on AWS.

## 1. Presentation Tier

This tier is responsible for user interaction and output.

- Vote app: Python web interface in [`vote/`](vote)
- Results app: Node.js dashboard in [`result/`](result)

Responsibilities:

- render the voting screen
- collect user input
- display the latest counted results in real time
- provide the user-facing entry points to the application

## 2. Application Tier

This tier contains the business logic that processes user actions and updates
system state.

- Vote service: [`vote/app.py`](vote/app.py)
- Worker service: [`worker/Worker.csproj`](worker/Worker.csproj)
- Result service: [`result/server.js`](result/server.js)

Responsibilities:

- accept incoming votes from the web client
- validate and transform vote payloads
- queue votes for downstream processing
- aggregate and read results for display
- coordinate the interaction between the front ends and the data layer

## 3. Messaging Tier

This tier decouples the user-facing components from the data-processing layer.

- Redis: message broker used as the queue between vote submission and tallying

Responsibilities:

- temporarily store submitted votes
- buffer traffic during processing spikes
- provide asynchronous communication between producers and consumers
- improve resilience and decoupling between application components

## 4. Data Tier

This tier stores the persistent application state.

- PostgreSQL database in the application stack
- Persistent storage is managed through Docker volumes and deployment
  configuration

Responsibilities:

- persist final vote totals
- serve result queries for the dashboard
- maintain durable event history for the app's state

## 5. Deployment and Infrastructure Tier

This tier handles how the application is deployed and operated across different
runtime environments.

Included deployment options:

- Docker Compose: local development setup
- Docker Swarm: clustered container deployment
- Kubernetes manifests: [`k8s-specifications/`](k8s-specifications)
- Terraform + Ansible: AWS single-host deployment in [`terraform/`](terraform)

Responsibilities:

- package and run services consistently
- manage networking, ports, and service discovery
- enable automation and repeatable infrastructure provisioning
- support multiple deployment models from lab to small-scale production

## Architecture Overview

```text
┌───────────────────────────────────────────────────────────────────────┐
│ 5. Deployment & Infrastructure Tier                                  │
│ Docker Compose | Docker Swarm | Kubernetes | Terraform + Ansible      │
└───────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌───────────────────────────────────────────────────────────────────────┐
│ 4. Data Tier                                                         │
│ PostgreSQL                                                            │
│ Persistent vote storage                                              │
└───────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌───────────────────────────────────────────────────────────────────────┐
│ 3. Messaging Tier                                                     │
│ Redis                                                                 │
│ Vote queue / asynchronous messaging                                   │
└───────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌───────────────────────────────────────────────────────────────────────┐
│ 2. Application Tier                                                   │
│ vote app  →  Redis queue  →  worker  →  PostgreSQL                   │
│ result app reads aggregation data and displays it                   │
└───────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌───────────────────────────────────────────────────────────────────────┐
│ 1. Presentation Tier                                                  │
│ Browser UI for voting and result dashboard                            │
└───────────────────────────────────────────────────────────────────────┘
```

## Runtime flow

1. A user opens the voting page.
2. The vote app accepts a selection and sends it into the application flow.
3. The vote is placed in Redis for asynchronous processing.
4. The .NET worker consumes the item from Redis.
5. The worker stores the vote in PostgreSQL.
6. The result app reads from PostgreSQL and refreshes the live dashboard.

## Architecture Diagram

![Application architecture](image/architecture.excalidraw.png)

## Local deployment with Docker Compose

Install [Docker Desktop](https://www.docker.com/products/docker-desktop) or
Docker Engine with the Compose plugin on Linux.

From the repository root, start the stack:

```shell
docker compose up
```

The application is available at:

- Vote app: <http://localhost:8082>
- Results app: <http://localhost:8081>

To run the prebuilt image version instead:

```shell
docker compose -f docker-compose.images.yml up -d
```

To stop the environment:

```shell
docker compose down
```

## Docker Swarm deployment

Initialize a swarm if needed:

```shell
docker swarm init
```

Deploy the stack:

```shell
docker stack deploy --compose-file docker-stack.yml vote
```

## Kubernetes deployment

The [`k8s-specifications/`](k8s-specifications) directory contains the
Kubernetes manifests for the application.

```shell
kubectl apply -f k8s-specifications/
kubectl get pods
kubectl get svc
```

The vote app is exposed on port `31000` and the results app on port `31001`.

To remove the resources:

```shell
kubectl delete -f k8s-specifications/
```

## AWS deployment architecture (2 Availability Zones)

This repository includes an AWS reference architecture that is designed around a
VPC spanning two Availability Zones rather than a single EC2 host. The VPC
views in the repository show the environment as a distributed network with
subnets in both `eu-north-1a` and `eu-north-1b`, and the EC2 instance view shows
servers running across both zones.

### VPC and subnet layout

The AWS VPC diagram in ![`image/vpc.png`](image/vpc.png) shows a VPC named
`voting-app-dev-vpc` and confirms the network is active in the selected AWS
region. The VPC details view in ![`image/vpc-details.png`](image/vpc-details.png)
illustrates the main network structure: the VPC contains multiple subnets split
across two availability zones, with route tables and network connections for the
application components. The layout includes separate subnets for the vote,
result, worker, Redis, and database services, which matches the multi-tier
application design in this repository.

The resource map in ![`image/vpc-details.png`](image/vpc-details.png) makes the
multi-AZ design clear:

- one set of subnets in `eu-north-1a`
- a second set of subnets in `eu-north-1b`
- routing and connectivity between the app tiers and the public/private network
  boundaries
- a VPC topology suitable for deploying the voting stack across isolated AZ
  segments

### EC2 instances across Availability Zones

The image ![`image/servers in available zone.png`](image/servers%20in%20available%20zone.png)
shows the EC2 instance view for the region, with the application instances spread
across both availability zones. The table lists multiple `t3.small` and
`m7i-flex.large` instances running in `eu-north-1a` and `eu-north-1b`, which
reflects a two-AZ deployment pattern rather than a single-server design.

This means the AWS architecture represented in the repository is best described as
an application stack distributed across two availability zones, with the VPC,
subnets, route tables, and EC2 hosts distributed for resilience and network
segmentation.

### Terraform and Ansible

The repository also includes Terraform and Ansible automation to provision the
AWS infrastructure and deploy the application stack. The infrastructure can be
used as a lab or small non-production deployment model, but the reference
architecture displayed in the images is a multi-AZ design and not a single-host
deployment.

### Prerequisites

- AWS account and credentials
- Terraform `>= 1.5.0`
- Ansible Core installed on the machine running Terraform
- Existing EC2 key pair or `create_key_pair = true`

### Deploy

```shell
cd terraform
terraform init
terraform validate
terraform plan
terraform apply
```

Terraform output includes the URLs and connection details for the deployed app.

### Remove the AWS resources

```shell
cd terraform
terraform destroy
```

## Project structure

- [`vote/`](vote) - Python voting UI
- [`result/`](result) - Node.js results dashboard
- [`worker/`](worker) - .NET consumer service
- [`k8s-specifications/`](k8s-specifications) - Kubernetes manifests
- [`ansible/`](ansible) - automation for deployment
- [`terraform/`](terraform) - AWS infrastructure as code
- [`docker-compose.yml`](docker-compose.yml) - local Compose deployment
- [`docker-stack.yml`](docker-stack.yml) - Docker Swarm deployment

## Notes

- The application accepts one vote per client browser.
- This project is an educational example of a distributed application and
  infrastructure automation workflow.
- It is intentionally simple and useful for learning service boundaries,
  messaging, data persistence, and deployment patterns.
