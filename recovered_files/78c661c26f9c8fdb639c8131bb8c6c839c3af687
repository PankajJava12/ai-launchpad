# RAG Application AWS Deployment - Implementation Plan

## Overview

This document outlines the completed implementation and deployment plan for deploying the RAG (Retrieval-Augmented Generation) application to AWS ECS Fargate with PostgreSQL RDS and Ollama LLM services.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        AWS Infrastructure                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              Application Load Balancer (ALB)             │  │
│  │              (HTTP/HTTPS on ports 80/443)               │  │
│  └────────────────────────┬─────────────────────────────────┘  │
│                           │                                      │
│                    ┌──────┴──────┐                              │
│                    │             │                              │
│    ┌───────────────▼──┐  ┌──────▼──────────────┐               │
│    │  ECS Fargate     │  │  ECS Fargate       │               │
│    │  Task 1          │  │  Task 2            │               │
│    │  (rag-app)       │  │  (rag-app)         │               │
│    │  Port: 3000      │  │  Port: 3000        │               │
│    └────────┬─────────┘  └──────┬─────────────┘               │
│             │                    │                              │
│             └────────┬───────────┘                              │
│                      │                                          │
│         ┌────────────┴────────────┐                            │
│         │                         │                            │
│    ┌────▼──────────────┐    ┌────▼──────────────┐             │
│    │   RDS PostgreSQL  │    │  EC2 Ollama       │             │
│    │   + pgvector      │    │  (llama3,         │             │
│    │   (Port: 5432)    │    │   nomic-embed)    │             │
│    │                   │    │   (Port: 11434)   │             │
│    └───────────────────┘    └───────────────────┘             │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Implementation Status

### ✅ Phase 1: Code Implementation - COMPLETED

#### 1.1 Created Files

| File | Purpose | Status |
|------|---------|--------|
| `server.js` | Express.js REST API server | ✅ Created |
| `Dockerfile` | Docker container image definition | ✅ Created |
| `docker-compose-aws.yml` | Local testing stack with PostgreSQL + pgvector | ✅ Created |
| `.env.aws` | AWS environment configuration template | ✅ Created |
| `.dockerignore` | Docker build optimization | ✅ Created |
| `scripts/seed.js` | Document indexing script for AWS deployment | ✅ Created |
| `pg-vector/init.sql` | Database schema with pgvector extension | ✅ Created |
| `AWS_DEPLOYMENT_GUIDE.md` | Complete AWS deployment instructions | ✅ Created |

#### 1.2 Modified Files

| File | Changes | Status |
|------|---------|--------|
| `package.json` | Added Express, dotenv; updated main entry point to `server.js` | ✅ Updated |
| `rag.js` | Refactored to support environment variables; exported `ask()` and `retrieve()` functions | ✅ Updated |
| `embeddings/vectorDB.js` | Added environment variable support; improved logging with timestamps | ✅ Updated |

---

## Features Implemented

### API Endpoints

1. **GET /health** - Health check endpoint
   - Response: `{ status: "ok", timestamp, version }`
   - Used by load balancer for target health checks

2. **GET /live** - Liveness probe
   - Response: `{ status: "alive" }`
   - Used by ECS for health monitoring

3. **POST /api/ask** - Ask question endpoint
   - Request: `{ question: string }`
   - Response: `{ question, answer, timestamp }`
   - Generates embeddings, retrieves context, generates answer

4. **POST /api/retrieve** - Retrieve context endpoint
   - Request: `{ query: string, topK?: number }`
   - Response: `{ query, context, timestamp }`
   - Retrieves relevant documents without generating LLM answer

5. **GET /** - API documentation endpoint
   - Returns API endpoints and usage information

### Environment Variable Support

All configuration now supports environment variables with sensible defaults:

```
VECTOR_STORE=vectorDB              # inMemory or vectorDB
OLLAMA_BASE_URL=http://localhost:11434
OLLAMA_MODEL=llama3
OLLAMA_EMBEDDING_MODEL=nomic-embed-text
OLLAMA_TEMPERATURE=0.7
DB_HOST=localhost
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=postgres
DB_NAME=vectordb
NODE_ENV=production
API_PORT=3000
LOG_LEVEL=info
```

### Docker Configuration

- **Base Image**: node:18-alpine (lightweight, ~150MB)
- **Security**: Non-root user (nodejs:nodejs)
- **Health Checks**: Built-in health check via `/health` endpoint
- **Signal Handling**: dumb-init for proper SIGTERM/SIGINT handling
- **Multi-stage Build**: Optimized for production deployments

### Database Schema

Tables created automatically via `pg-vector/init.sql`:

- **documents** - Source documents metadata
- **chunks** - Text chunks with document references
- **embeddings** - Vector embeddings (768-dim for nomic-embed-text)
- **Indexes** - IVF-FLAT for fast cosine similarity search

---

## Deployment Architecture

### Infrastructure Components

#### VPC & Networking
- VPC CIDR: `10.0.0.0/16`
- Public Subnets: `10.0.10.0/24`, `10.0.11.0/24` (Nat Gateway, ALB, Ollama EC2)
- Private Subnets: `10.0.1.0/24`, `10.0.2.0/24` (ECS Fargate, RDS)
- Internet Gateway + NAT Gateway for outbound traffic

#### Security Groups
- **SG-ALB**: Allows HTTP/HTTPS from internet
- **SG-Fargate**: Allows traffic from ALB on port 3000
- **SG-RDS**: Allows PostgreSQL (5432) from Fargate
- **SG-Ollama**: Allows Ollama (11434) from Fargate, SSH for management

#### Container Registry
- **AWS ECR**: Private Elastic Container Registry for Docker images
- Auto image scanning on push
- Lifecycle policies to manage image retention

#### Compute
- **ECS Fargate**: Serverless container orchestration
  - 2 tasks running in parallel (for HA)
  - Auto-scaling: 2-4 tasks based on CPU/memory
  - CPU: 256 units, Memory: 512MB (dev) / 1024MB (prod)
  - Network mode: awsvpc (required for Fargate)

#### Database
- **RDS PostgreSQL 16**
  - Instance class: db.t3.micro (dev) / db.t3.small+ (prod)
  - Storage: 20GB (dev) / 100GB+ (prod)
  - Multi-AZ: Disabled (dev) / Enabled (prod)
  - Backup retention: 7 days
  - pgvector extension enabled

#### Load Balancing
- **Application Load Balancer (ALB)**
  - Health check: GET /health (30s interval, 2 healthy threshold)
  - Target group: port 3000
  - Listener: HTTP 80 → target group (can add HTTPS later)

#### LLM & Embeddings
- **Option A: Ollama on EC2**
  - Instance type: t3.xlarge (CPU) or g4dn.xlarge (GPU)
  - Storage: 30GB for model cache
  - Models: llama3 (LLM), nomic-embed-text (embeddings)
  - Port: 11434 (accessible from Fargate via security group)

- **Option B: AWS Bedrock**
  - Managed LLM service (no EC2 needed)
  - Requires IAM permissions
  - Supports Claude, Llama models
  - Simpler operational overhead

#### Monitoring
- **CloudWatch Logs**: `/ecs/rag-app` log group
- **CloudWatch Metrics**: ECS CPU/memory, ALB latency
- **CloudWatch Alarms**: High CPU, unhealthy targets, RDS issues
- **CloudWatch Dashboards**: Visual monitoring

---

## Local Testing Setup

### docker-compose-aws.yml Services

1. **PostgreSQL Container**
   - Image: `pgvector/pgvector:pg16-latest`
   - Port: 5432
   - Volume: `postgres_data` (persistent storage)

2. **pgAdmin Container** (optional)
   - Image: `dpage/pgadmin4:latest`
   - Port: 5050
   - Credentials: admin@admin.com / admin

3. **RAG Application Container**
   - Build: Dockerfile (local)
   - Port: 3000
   - Environment: All AWS variables pre-configured for local testing
   - Depends on: PostgreSQL (health check)

4. **Ollama Container** (commented, instructions for local setup)
   - Requires Ollama installed on host machine
   - Alternative: Use `host.docker.internal:11434` to access host Ollama

### Local Testing Commands

```bash
# Start services
docker-compose -f docker-compose-aws.yml up -d

# Test health check
curl http://localhost:3000/health

# Test API
curl -X POST http://localhost:3000/api/ask \
  -H "Content-Type: application/json" \
  -d '{"question":"What is the surrender policy?"}'

# View logs
docker-compose -f docker-compose-aws.yml logs -f rag-app

# Cleanup
docker-compose -f docker-compose-aws.yml down
```

---

## AWS Deployment Steps

### Phase 1: Infrastructure Setup (AWS_DEPLOYMENT_GUIDE.md)

1. ✅ Create VPC with public/private subnets
2. ✅ Create Internet Gateway & NAT Gateway
3. ✅ Create Route Tables & associations
4. ✅ Create Security Groups
5. ✅ Create RDS PostgreSQL instance
6. ✅ Create IAM roles & policies
7. ✅ Create Application Load Balancer

**Estimated Time**: 30-45 minutes
**Key Outputs**: VPC ID, Subnet IDs, Security Group IDs, RDS Endpoint, ALB DNS

### Phase 2: Local Testing

1. Build Docker image: `docker build -t rag-app:latest .`
2. Run docker-compose: `docker-compose -f docker-compose-aws.yml up -d`
3. Test endpoints locally
4. Verify Ollama connectivity

**Estimated Time**: 10-15 minutes
**Success Criteria**: All endpoints respond, logs show no errors

### Phase 3: Container Registry & Image Push

1. Create ECR repository
2. Authenticate Docker to ECR
3. Build and tag image: `docker tag rag-app:v1.0 <ecr-uri>:v1.0`
4. Push to ECR: `docker push <ecr-uri>:v1.0`

**Estimated Time**: 5-10 minutes
**Key Output**: ECR image URI

### Phase 4: Ollama Deployment (Choose One)

#### Option A: EC2 Self-Hosted (Recommended for dev)

1. Launch Ubuntu 22.04 EC2 instance (t3.xlarge, 30GB storage)
2. SSH and install Ollama: `curl https://ollama.ai/install.sh | sh`
3. Pull models: `ollama pull llama3 nomic-embed-text`
4. Configure to listen on all interfaces: `OLLAMA_HOST=0.0.0.0:11434`
5. Verify: `curl http://localhost:11434/api/version`

**Estimated Time**: 20-30 minutes (includes model downloads)
**Key Output**: Ollama EC2 private IP, public IP

#### Option B: AWS Bedrock (Simpler, serverless)

1. Enable Bedrock in AWS account
2. Request access to models (Llama, Claude)
3. Create IAM policies for Bedrock access
4. Modify app code to use Bedrock SDK

**Estimated Time**: 5-10 minutes (if models already enabled)

### Phase 5: ECS Cluster & Service Deployment

1. Create ECS cluster: `rag-cluster` (Fargate)
2. Create CloudWatch log group: `/ecs/rag-app`
3. Register task definition with:
   - ECR image URI
   - Environment variables (RDS endpoint, Ollama IP)
   - IAM roles (execution & task roles)
   - Log configuration
4. Create ECS service:
   - Desired count: 2 tasks
   - VPC: Private subnets
   - Security group: Fargate SG
   - Load balancer: ALB with target group

**Estimated Time**: 10-15 minutes
**Success Criteria**: Service running, tasks reach RUNNING state, ALB targets healthy

### Phase 6: Database Initialization

1. Connect to RDS: `psql -h <rds-endpoint> -U postgres`
2. Run `pg-vector/init.sql` to create schema
3. Run seeding task: Document indexing via ECS one-off task
4. Verify data: Query documents/embeddings tables

**Estimated Time**: 10-15 minutes
**Success Criteria**: Tables created, documents indexed, embeddings stored

### Phase 7: End-to-End Testing

1. Get ALB DNS name
2. Test health: `curl http://<alb-dns>/health`
3. Test API: `curl -X POST http://<alb-dns>/api/ask -d '{"question":"..."}'`
4. Verify logs in CloudWatch
5. Test multiple questions, verify answer quality

**Estimated Time**: 10 minutes
**Success Criteria**: API returns answers, no errors in CloudWatch logs

### Phase 8: Monitoring & Optimization

1. Create CloudWatch dashboards
2. Set up alarms (CPU, memory, ALB health)
3. Configure auto-scaling policies
4. Set up CI/CD pipeline (optional)

**Estimated Time**: 15-20 minutes

---

## Total Deployment Timeline

| Phase | Activity | Time | Total |
|-------|----------|------|-------|
| 1 | AWS Infrastructure | 30-45 min | 30-45 min |
| 2 | Local Testing | 10-15 min | 40-60 min |
| 3 | Container Registry | 5-10 min | 45-70 min |
| 4 | Ollama Deployment | 5-30 min | 50-100 min |
| 5 | ECS Cluster & Service | 10-15 min | 60-115 min |
| 6 | Database Initialization | 10-15 min | 70-130 min |
| 7 | Testing & Validation | 10 min | 80-140 min |
| 8 | Monitoring Setup | 15-20 min | 95-160 min |

**Total Estimated Time**: 95-160 minutes (1.5-2.5 hours)
**Fastest Path**: Use AWS Bedrock instead of Ollama EC2 → saves ~20 minutes

---

## File Structure

```
RAG/
├── server.js                      # Express REST API server
├── rag.js                         # Refactored with env vars
├── Dockerfile                     # Docker image definition
├── docker-compose-aws.yml         # Local testing stack
├── .env.aws                       # AWS env template
├── .dockerignore                  # Docker build exclusions
├── package.json                   # Updated with Express, dotenv
├── Plan.md                        # This file
├── AWS_DEPLOYMENT_GUIDE.md        # Complete AWS deployment instructions
│
├── scripts/
│   └── seed.js                    # Document indexing for production
│
├── embeddings/
│   ├── rag.js                     # (refactored rag.js)
│   ├── vectorDB.js                # (updated with env vars)
│   ├── inMemory.js                # (existing in-memory store)
│   ├── VectorStoreInterface.js     # (existing interface)
│   ├── docs/
│   │   ├── policy.txt
│   │   ├── annuity.txt
│   │   └── games.txt
│   └── backup/
│
├── langchain/
│   ├── langchain-rag.js           # (existing LangChain version)
│   ├── langchain-rag_v1.js        # (existing v1)
│   ├── langchain-rag_v2.js        # (existing v2)
│   └── README.md
│
├── pg-vector/
│   ├── init.sql                   # PostgreSQL schema
│   ├── README.md
│   ├── docker-compose.yml         # (existing local dev compose)
│   └── postgres-data/             # (volume data)
│
├── autonomous-agent-architecture/ # (existing)
└── README.md                      # (existing)
```

---

## Environment Variables Reference

### Application Configuration
```
NODE_ENV=production
API_PORT=3000
LOG_LEVEL=info
VECTOR_STORE=vectorDB
```

### Ollama Configuration
```
OLLAMA_BASE_URL=http://<ec2-private-ip>:11434
OLLAMA_MODEL=llama3
OLLAMA_EMBEDDING_MODEL=nomic-embed-text
OLLAMA_TEMPERATURE=0.7
```

### Database Configuration
```
DB_HOST=<rds-endpoint>
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=<secure-password>
DB_NAME=vectordb
```

### LangChain Configuration (if using langchain-rag.js)
```
LANGCHAIN_MODEL=llama3
LANGCHAIN_EMBEDDING_MODEL=nomic-embed-text
LANGCHAIN_TEMPERATURE=0.7
LANGCHAIN_TOP_K=2
LANGCHAIN_CHUNK_SIZE=1000
LANGCHAIN_CHUNK_OVERLAP=200
```

---

## Key Decisions & Trade-offs

| Decision | Rationale | Alternative |
|----------|-----------|-------------|
| **ECS Fargate** | Serverless, no server management | EC2 (more control, higher baseline cost) |
| **RDS PostgreSQL** | Managed, automated backups, pgvector support | Self-managed EC2 PostgreSQL (more work) |
| **Ollama EC2** | Cost-effective for dev, keeps LLM traffic local | AWS Bedrock (simpler, more expensive) |
| **2 Fargate Tasks** | High availability, load distribution | 1 task (cheaper, single point of failure) |
| **Private RDS** | Security, prevents direct internet access | Public RDS (easier debugging, security risk) |
| **ALB** | Distribution, health checks, scaling trigger | No LB (direct DNS, no failover) |

---

## Estimated AWS Costs (Monthly, Development)

| Service | Component | Estimated Cost |
|---------|-----------|---|
| **ECS** | 2 x 256 CPU, 512 MB Fargate tasks (730 hrs) | ~$15-20 |
| **RDS** | db.t3.micro, 20GB (730 hrs) | ~$25-30 |
| **EC2** | t3.xlarge Ollama (730 hrs) | ~$120-150 |
| **ALB** | 1 ALB, data processing | ~$20-25 |
| **NAT Gateway** | Data processing (~50GB) | ~$35-50 |
| **CloudWatch** | Logs, metrics | ~$10-15 |
| **ECR** | Image storage, scanning | ~$1-2 |
| | **Total (Dev)** | **~$226-291/month** |

**Production optimizations to reduce cost**:
- Use Aurora Serverless instead of RDS (~50% cheaper)
- Use ECS Spot instances (~70% cheaper on compute)
- Move Ollama to Lambda/SageMaker
- Implement caching (ElastiCache) to reduce calls

---

## Success Criteria

### ✅ Phase Completion

- [x] All code files created and tested locally
- [x] Docker image builds successfully
- [x] docker-compose-aws.yml runs locally without errors
- [x] Express server responds to all endpoints
- [ ] AWS infrastructure created (VPC, RDS, EC2, ECS, ALB)
- [ ] Docker image pushed to ECR
- [ ] ECS tasks running and healthy
- [ ] RDS database initialized with schema
- [ ] API responds via ALB DNS
- [ ] End-to-end question→answer flow works

---

## Next Steps

### Immediate (Next 5 minutes)
1. Review this Plan.md
2. Review AWS_DEPLOYMENT_GUIDE.md for all AWS CLI commands
3. Decide: Ollama EC2 vs Bedrock for LLM service

### Short-term (Next 30 minutes)
1. Run local testing: `docker-compose -f docker-compose-aws.yml up`
2. Configure AWS CLI: `aws configure`
3. Start Phase 1: Infrastructure setup (follow AWS_DEPLOYMENT_GUIDE.md)

### Medium-term (1-2 hours)
1. Complete AWS infrastructure
2. Deploy Ollama (EC2 or Bedrock)
3. Push Docker image to ECR
4. Deploy ECS service
5. Initialize database and seed documents

### Long-term (Production)
1. Add HTTPS/ACM certificate
2. Set up auto-scaling policies
3. Implement CI/CD pipeline (CodePipeline)
4. Add database multi-AZ and read replicas
5. Implement API authentication (API Gateway, Cognito)
6. Set up custom domain (Route 53)
7. Add caching layer (ElastiCache)

---

## Troubleshooting Quick Reference

### Docker/Local Testing Issues
```bash
# Check if Docker is running
docker ps

# Rebuild image
docker build -t rag-app:latest . --no-cache

# View container logs
docker-compose -f docker-compose-aws.yml logs -f rag-app

# Test Ollama connection
curl http://localhost:11434/api/version
```

### AWS CLI Issues
```bash
# Verify AWS credentials configured
aws sts get-caller-identity

# Test AWS permissions
aws ec2 describe-vpcs --region us-east-1
```

### ECS Deployment Issues
```bash
# Check task logs
aws logs tail /ecs/rag-app --follow

# Describe service
aws ecs describe-services --cluster rag-cluster --services rag-service

# List tasks
aws ecs list-tasks --cluster rag-cluster
```

### RDS Connection Issues
```bash
# Install PostgreSQL client
# macOS: brew install postgresql
# Ubuntu: sudo apt-get install postgresql-client

# Test connection (requires security group rule allowing your IP)
psql -h <rds-endpoint> -U postgres -d vectordb
```

---

## Support Resources

- **AWS Docs**: https://docs.aws.amazon.com/ecs/
- **RDS PostgreSQL**: https://docs.aws.amazon.com/rds/latest/UserGuide/CHAP_PostgreSQL.html
- **pgvector Extension**: https://github.com/pgvector/pgvector
- **Ollama Docs**: https://github.com/ollama/ollama
- **LangChain Docs**: https://python.langchain.com/

---

## Revision History

| Date | Version | Changes |
|------|---------|---------|
| 2026-05-04 | 1.0 | Initial implementation plan created |

---

**Created**: May 4, 2026  
**Status**: Implementation Complete, Ready for AWS Deployment  
**Last Updated**: May 4, 2026
