-- PostgreSQL initialization script for RAG application
-- Creates necessary tables and extensions

-- Enable pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- Create documents table
CREATE TABLE IF NOT EXISTS documents (
  id SERIAL PRIMARY KEY,
  title VARCHAR(255) NOT NULL,
  source VARCHAR(255),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create chunks table
CREATE TABLE IF NOT EXISTS chunks (
  id SERIAL PRIMARY KEY,
  document_id INTEGER NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
  chunk_index INTEGER NOT NULL,
  content TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create embeddings table
CREATE TABLE IF NOT EXISTS embeddings (
  id SERIAL PRIMARY KEY,
  chunk_id INTEGER NOT NULL UNIQUE REFERENCES chunks(id) ON DELETE CASCADE,
  embedding VECTOR(768),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for faster queries
CREATE INDEX IF NOT EXISTS idx_embeddings_vector ON embeddings USING ivfflat (embedding vector_cosine_ops);
CREATE INDEX IF NOT EXISTS idx_chunks_document ON chunks(document_id);
CREATE INDEX IF NOT EXISTS idx_documents_title ON documents(title);

-- Grant permissions to postgres user
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO postgres;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO postgres;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO postgres;
