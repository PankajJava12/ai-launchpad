# RAG System — System Design Document

## 1. Overview

This is a **Retrieval-Augmented Generation (RAG)** system for **Insurance Policy Q&A**. It ingests insurance policy documents, chunks and embeds them into a vector store, and at query time retrieves the most semantically relevant chunks to ground an LLM's answer — eliminating hallucinations and ensuring factual responses.

**Core value proposition:** Users can ask natural-language questions about insurance policies and get accurate, context-grounded answers backed by source documents.

---

## 2. High-Level Architecture

```mermaid
graph TB
    subgraph Client["🖥️ Client Layer"]
        USER["User / API Consumer"]
    end

    subgraph API["⚡ API Layer (Express.js)"]
        SERVER["server.js<br/>Express REST API<br/>Port 3000"]
        HEALTH["/health & /live<br/>Health Probes"]
        ASK_EP["POST /api/ask"]
        RET_EP["POST /api/retrieve"]
    end

    subgraph Core["🧠 RAG Engine (rag.js)"]
        ASK["ask(question)"]
        RETRIEVE["retrieve(query, topK)"]
        CONFIG["Config Manager<br/>env-driven"]
        FACTORY["Vector Store Factory<br/>getVectorStore()"]
    end

    subgraph Embedding["📦 Embedding Layer"]
        INTERFACE["VectorStoreInterface<br/>(Abstract Base Class)"]
        INMEM["InMemoryStore<br/>Cosine Similarity"]
        VECDB["VectorDBStore<br/>pgvector"]
    end

    subgraph LLM["🤖 LLM Layer (Ollama)"]
        EMBED_MODEL["nomic-embed-text<br/>(Embedding Model)"]
        CHAT_MODEL["llama3<br/>(Chat Model)"]
    end

    subgraph Storage["🗄️ Persistence Layer"]
        PG["PostgreSQL 16<br/>+ pgvector extension"]
        DOCS["Document Files<br/>embeddings/docs/*.txt"]
    end

    USER --> SERVER
    SERVER --> ASK_EP --> ASK
    SERVER --> RET_EP --> RETRIEVE
    SERVER --> HEALTH

    ASK --> RETRIEVE
    RETRIEVE --> FACTORY
    FACTORY --> INTERFACE
    INTERFACE --> INMEM
    INTERFACE --> VECDB

    RETRIEVE --> EMBED_MODEL
    ASK --> CHAT_MODEL

    VECDB --> PG
    INMEM -.-> DOCS
    VECDB -.-> DOCS

    style Client fill:#1a1a2e,stroke:#e94560,color:#fff
    style API fill:#16213e,stroke:#0f3460,color:#fff
    style Core fill:#0f3460,stroke:#533483,color:#fff
    style Embedding fill:#533483,stroke:#e94560,color:#fff
    style LLM fill:#e94560,stroke:#fff,color:#fff
    style Storage fill:#0f3460,stroke:#e94560,color:#fff
```

---

## 3. Data Flow Pipelines

### 3.1 Indexing Pipeline (Offline — `npm run seed`)

This pipeline runs **once** to ingest documents into the vector store.

```mermaid
flowchart LR
    A["📄 .txt files<br/>embeddings/docs/"] --> B["📖 Read Files<br/>fs.readFileSync"]
    B --> C["✂️ Chunk Text<br/>500 words, 50 overlap"]
    C --> D["🧬 Generate Embeddings<br/>nomic-embed-text<br/>768-dim vectors"]
    D --> E["💾 Store in pgvector<br/>documents → chunks → embeddings"]

    style A fill:#2d3436,stroke:#6c5ce7,color:#fff
    style B fill:#2d3436,stroke:#6c5ce7,color:#fff
    style C fill:#2d3436,stroke:#a29bfe,color:#fff
    style D fill:#2d3436,stroke:#fd79a8,color:#fff
    style E fill:#2d3436,stroke:#00b894,color:#fff
```

**Steps:**
1. **Read** — Scan `embeddings/docs/` for `.txt` files
2. **Create Document Record** — Insert into `documents` table (title, source)
3. **Chunk** — Split text into 500-word chunks with 50-word overlap
4. **Embed** — Generate 768-dimensional vectors via `nomic-embed-text` (Ollama)
5. **Store** — Insert chunks into `chunks` table, embeddings into `embeddings` table

### 3.2 Query Pipeline (Online — `POST /api/ask`)

This pipeline runs on **every user question**.

```mermaid
flowchart LR
    Q["❓ User Question"] --> E1["🧬 Embed Question<br/>nomic-embed-text"]
    E1 --> S["🔍 Similarity Search<br/>pgvector <-> operator<br/>L2 distance"]
    S --> TOP["📋 Top-K Chunks<br/>(default: 2)"]
    TOP --> P["📝 Build Prompt<br/>System + Context + Question"]
    P --> LLM["🤖 LLM Chat<br/>llama3"]
    LLM --> A["✅ Answer"]

    style Q fill:#2d3436,stroke:#00cec9,color:#fff
    style E1 fill:#2d3436,stroke:#6c5ce7,color:#fff
    style S fill:#2d3436,stroke:#fdcb6e,color:#fff
    style TOP fill:#2d3436,stroke:#e17055,color:#fff
    style P fill:#2d3436,stroke:#a29bfe,color:#fff
    style LLM fill:#2d3436,stroke:#fd79a8,color:#fff
    style A fill:#2d3436,stroke:#00b894,color:#fff
```

**Steps:**
1. **Embed Query** — Convert user question to 768-dim vector via `nomic-embed-text`
2. **Vector Search** — Use pgvector's `<->` (L2 distance) operator to find nearest chunks
3. **Retrieve Top-K** — Return top 2 most similar chunks (configurable)
4. **Augment Prompt** — Inject retrieved context into a system prompt
5. **Generate** — Send augmented prompt to `llama3` via Ollama chat API
6. **Return** — Stream answer back to client as JSON

---

## 4. Component Breakdown

### 4.1 API Layer — [server.js](file:///Users/pankajdewangan/work/genAI-and-agenticAI/RAG/server.js)

| Endpoint | Method | Purpose |
|---|---|---|
| `/` | GET | API info & endpoint listing |
| `/health` | GET | Health check (status, timestamp, version) |
| `/live` | GET | Liveness probe for ECS/K8s |
| `/api/ask` | POST | Full RAG pipeline — question in, answer out |
| `/api/retrieve` | POST | Retrieval only — returns relevant context chunks |

- Graceful shutdown via `SIGTERM` / `SIGINT` handlers
- JSON error handling middleware
- Configurable port via `API_PORT` env var

### 4.2 RAG Engine — [rag.js](file:///Users/pankajdewangan/work/genAI-and-agenticAI/RAG/rag.js)

Core orchestration module with two exported functions:

- **`retrieve(query, topK)`** — Embeds query → searches vector store → returns context string
- **`ask(question)`** — Calls `retrieve()` → constructs prompt → calls LLM → returns answer

Uses a **factory pattern** (`getVectorStore()`) to swap between `inMemory` and `vectorDB` backends.

### 4.3 Embedding Layer — [embeddings/](file:///Users/pankajdewangan/work/genAI-and-agenticAI/RAG/embeddings)

```mermaid
classDiagram
    class VectorStoreInterface {
        <<abstract>>
        +indexDocuments()
        +retrieve(queryEmbedding, topK)
    }

    class InMemoryStore {
        -vectorDB: Array
        +indexDocuments()
        +retrieve(queryEmbedding, topK)
        -cosineSimilarity(a, b)
    }

    class VectorDBStore {
        -connectionConfig: Object
        -ollama: Ollama
        -db: pg.Client
        -connected: boolean
        +init(host, port, user, password, database)
        +connect()
        +indexDocuments()
        +retrieve(queryEmbedding, topK)
        +disconnect()
        -chunkText(text, chunkSize, overlap)
        -storeChunk(content, index, docId, embedding)
    }

    VectorStoreInterface <|-- InMemoryStore
    VectorStoreInterface <|-- VectorDBStore
```

| Store | Backend | Similarity | Use Case |
|---|---|---|---|
| `InMemoryStore` | JS Array | Cosine similarity (manual) | Development / Testing |
| `VectorDBStore` | PostgreSQL + pgvector | L2 distance (`<->` operator) | Production |

### 4.4 LangChain Variants — [langchain/](file:///Users/pankajdewangan/work/genAI-and-agenticAI/RAG/langchain)

Three alternative implementations using LangChain framework:

| Version | File | Approach | Key Difference |
|---|---|---|---|
| Base | `langchain-rag.js` | `PGVectorStore` + `asRetriever` | Direct LLM invoke, hardcoded docs |
| v1 | `langchain-rag_v1.js` | `RetrievalQAChain` | Uses deprecated chain API, file loading |
| v2 | `langchain-rag_v2.js` | LCEL (`RunnablePassthrough`) | Modern LangChain Expression Language |

All three use `RecursiveCharacterTextSplitter` (1000 chars, 200 overlap) and `MemoryVectorStore`.

---

## 5. Database Schema

```mermaid
erDiagram
    DOCUMENTS {
        SERIAL id PK
        VARCHAR255 title
        VARCHAR255 source
        TIMESTAMP created_at
        TIMESTAMP updated_at
    }

    CHUNKS {
        SERIAL id PK
        INTEGER document_id FK
        INTEGER chunk_index
        TEXT content
        TIMESTAMP created_at
    }

    EMBEDDINGS {
        SERIAL id PK
        INTEGER chunk_id FK "UNIQUE"
        VECTOR768 embedding
        TIMESTAMP created_at
    }

    DOCUMENTS ||--o{ CHUNKS : "has many"
    CHUNKS ||--|| EMBEDDINGS : "has one"
```

**Key design decisions:**
- **Normalized schema** — Documents → Chunks → Embeddings (1:N:1 relationship)
- **CASCADE deletes** — Deleting a document removes all its chunks and embeddings
- **IVFFlat index** on `embedding` column for fast approximate nearest-neighbor search
- **768-dimension vectors** — matching `nomic-embed-text` output dimensionality

---

## 6. Deployment Architecture

### 6.1 Local Development (Docker Compose)

```mermaid
graph TB
    subgraph Docker["🐳 Docker Compose Network (rag-network)"]
        APP["rag-app<br/>Node.js 18 Alpine<br/>:3000"]
        PG["rag-postgres<br/>pgvector/pgvector:pg16<br/>:5432"]
        PGA["rag-pgadmin<br/>pgAdmin 4<br/>:5050"]
    end

    subgraph Host["💻 Host Machine"]
        OLLAMA["Ollama<br/>llama3 + nomic-embed-text<br/>:11434"]
    end

    APP -->|"DB queries"| PG
    APP -->|"host.docker.internal:11434"| OLLAMA
    PGA -->|"Admin UI"| PG

    style Docker fill:#1e3a5f,stroke:#4fc3f7,color:#fff
    style Host fill:#2d3436,stroke:#00b894,color:#fff
```

### 6.2 AWS Production Architecture

```mermaid
graph TB
    subgraph VPC["☁️ AWS VPC (rag-vpc)"]
        subgraph PublicSubnet["🌐 Public Subnets"]
            ALB["Application Load Balancer<br/>(rag-alb)"]
            IGW["Internet Gateway<br/>(rag-igw)"]
            NAT["NAT Gateway<br/>(rag-nat)"]
            EC2["EC2 Instance<br/>Ollama Server<br/>llama3 + nomic-embed-text"]
        end

        subgraph PrivateSubnet["🔒 Private Subnets"]
            subgraph ECS["ECS Fargate Cluster (rag-cluster)"]
                TASK["Fargate Task<br/>rag-app container<br/>256 CPU / 512 MB"]
            end

            RDS["RDS PostgreSQL<br/>pgvector extension<br/>(rag-db-instance)"]
        end
    end

    subgraph AWS_Services["🔧 AWS Services"]
        ECR["ECR Repository<br/>(rag-app)"]
        CW["CloudWatch Logs<br/>(/ecs/rag-app)"]
        IAM["IAM Roles<br/>task-execution-role<br/>task-role"]
    end

    INTERNET["🌍 Internet"] --> ALB
    ALB --> TASK
    TASK --> RDS
    TASK --> EC2
    TASK -.->|"logs"| CW
    ECR -.->|"image pull"| TASK
    IGW --> INTERNET
    NAT --> IGW

    style VPC fill:#0d1b2a,stroke:#1b9aaa,color:#fff
    style PublicSubnet fill:#1b2838,stroke:#48bb78,color:#fff
    style PrivateSubnet fill:#1b2838,stroke:#e53e3e,color:#fff
    style ECS fill:#2d3748,stroke:#4299e1,color:#fff
    style AWS_Services fill:#1a202c,stroke:#ed8936,color:#fff
```

**AWS Resource Map:**

| Resource | Service | Config |
|---|---|---|
| Container Runtime | ECS Fargate | 256 CPU, 512 MB RAM |
| Container Registry | ECR | `rag-app:latest` |
| Database | RDS PostgreSQL | pgvector extension, `vectordb` |
| LLM Server | EC2 | Ollama with llama3 + nomic-embed-text |
| Load Balancer | ALB | Target group: `rag-tg` |
| Networking | VPC | Public + Private subnets, NAT Gateway |
| Logging | CloudWatch | `/ecs/rag-app` log group |
| Security | IAM | Task execution + task roles |
| Security Groups | EC2 SGs | `rag-alb-sg`, `rag-fargate-sg`, `rag-rds-sg`, `rag-ollama-sg` |

---

## 7. Technology Stack

| Layer | Technology | Purpose |
|---|---|---|
| **Runtime** | Node.js 18 (Alpine) | Application runtime |
| **API Framework** | Express.js 4.x | REST API server |
| **LLM** | Ollama (llama3) | Text generation |
| **Embeddings** | Ollama (nomic-embed-text) | 768-dim vector embeddings |
| **Vector DB** | PostgreSQL 16 + pgvector | Vector similarity search |
| **DB Client** | node-pg | PostgreSQL driver |
| **LLM Framework** | LangChain (alternative impl.) | RAG chain orchestration |
| **Containerization** | Docker (multi-stage build) | Application packaging |
| **Orchestration** | Docker Compose / ECS Fargate | Container orchestration |
| **Process Manager** | dumb-init | Signal forwarding in containers |

---

## 8. Design Patterns & Principles

| Pattern | Where | How |
|---|---|---|
| **Strategy Pattern** | `VectorStoreInterface` | Swap between InMemory and VectorDB backends via factory |
| **Factory Pattern** | `getVectorStore()` in rag.js | Env-driven store instantiation |
| **Template Method** | `VectorStoreInterface` base class | Abstract methods enforced on subclasses |
| **12-Factor App** | Config via env vars | All config externalized via `.env` / env vars |
| **Multi-stage Docker Build** | Dockerfile | Smaller image, no dev dependencies in prod |
| **Graceful Shutdown** | server.js SIGTERM/SIGINT | Clean process termination |
| **Health Check Pattern** | `/health` + `/live` endpoints | Container orchestrator integration |
| **Separation of Concerns** | server.js ↔ rag.js ↔ embeddings/ | API, orchestration, and storage are decoupled |

---

## 9. Scalability Considerations

```mermaid
graph LR
    subgraph Current["Current State"]
        C1["Single Fargate Task"]
        C2["Single RDS Instance"]
        C3["Single EC2 Ollama"]
    end

    subgraph Scale["Scaling Options"]
        S1["ECS Auto-Scaling<br/>+ ALB load distribution"]
        S2["RDS Read Replicas<br/>+ Connection Pooling"]
        S3["Multiple Ollama Instances<br/>or AWS Bedrock"]
        S4["Dedicated Vector DB<br/>(Pinecone, Weaviate)"]
    end

    C1 --> S1
    C2 --> S2
    C3 --> S3
    C2 --> S4

    style Current fill:#2d3436,stroke:#e17055,color:#fff
    style Scale fill:#2d3436,stroke:#00b894,color:#fff
```

| Bottleneck | Current Limit | Scaling Path |
|---|---|---|
| **API Throughput** | Single Fargate task | ECS service auto-scaling behind ALB |
| **Vector Search** | pgvector on RDS | Dedicated vector DB (Pinecone/Weaviate) at 10M+ vectors |
| **LLM Inference** | Single EC2 Ollama | GPU instances, multiple replicas, or AWS Bedrock |
| **Embedding Generation** | Synchronous, single-threaded | Batch processing, queue-based indexing |
| **DB Connections** | Single `pg.Client` per request | Connection pooling (`pg.Pool`) |

---

## 10. Request Lifecycle — End-to-End

```mermaid
sequenceDiagram
    actor User
    participant API as Express API<br/>(server.js)
    participant RAG as RAG Engine<br/>(rag.js)
    participant Embed as Ollama<br/>(nomic-embed-text)
    participant VDB as pgvector<br/>(PostgreSQL)
    participant LLM as Ollama<br/>(llama3)

    User->>API: POST /api/ask { question }
    API->>RAG: ask(question)
    RAG->>RAG: retrieve(question, topK=2)
    RAG->>Embed: embed({ model, prompt })
    Embed-->>RAG: 768-dim vector

    RAG->>VDB: SELECT ... ORDER BY embedding <-> $1 LIMIT 2
    VDB-->>RAG: Top-2 chunks (content, distance)

    RAG->>RAG: Build context string
    RAG->>LLM: chat({ system prompt, context + question })
    LLM-->>RAG: Generated answer

    RAG-->>API: answer string
    API-->>User: { question, answer, timestamp }
```

---

## 11. File Structure Summary

```
RAG/
├── server.js                          # Express API — entry point
├── rag.js                             # RAG engine — retrieve + ask
├── package.json                       # Dependencies & scripts
├── Dockerfile                         # Multi-stage production build
├── docker-compose-aws.yml             # Full-stack Docker Compose
├── .env.aws                           # AWS environment template
├── task-definition.json               # ECS Fargate task definition
├── cleanup.sh                         # AWS resource teardown script
│
├── embeddings/
│   ├── VectorStoreInterface.js        # Abstract base class
│   ├── inMemory.js                    # In-memory store (dev)
│   ├── vectorDB.js                    # pgvector store (prod)
│   ├── README.md                      # Embedding architecture docs
│   └── docs/                          # Source documents
│       ├── annuity.txt
│       ├── games.txt
│       └── policy.txt
│
├── pg-vector/
│   ├── init.sql                       # DB schema + pgvector setup
│   ├── docker-compose.yml             # Standalone pgvector compose
│   └── postgres-data/                 # Persistent volume
│
├── langchain/                         # Alternative LangChain implementations
│   ├── langchain-rag.js               # Base — PGVectorStore
│   ├── langchain-rag_v1.js            # v1 — RetrievalQAChain
│   └── langchain-rag_v2.js            # v2 — LCEL (modern)
│
└── scripts/
    └── seed.js                        # Document indexing script
```
