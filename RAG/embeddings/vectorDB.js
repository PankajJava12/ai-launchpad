import pkg from "pg"
import fs from "fs"
import { VectorStoreInterface } from "./VectorStoreInterface.js"
import { Ollama } from "ollama"
import dotenv from "dotenv"

dotenv.config()

const { Client } = pkg

/*
--------------------------------
PostgreSQL pgvector Store Implementation
--------------------------------
*/

class VectorDBStore extends VectorStoreInterface {
  constructor(connectionConfig = {}) {
    super()
    this.connectionConfig = {
      host: connectionConfig.host || process.env.DB_HOST || 'localhost',
      port: connectionConfig.port || parseInt(process.env.DB_PORT || '5432'),
      user: connectionConfig.user || process.env.DB_USER || 'postgres',
      password: connectionConfig.password || process.env.DB_PASSWORD || 'postgres',
      database: connectionConfig.database || process.env.DB_NAME || 'vectordb',
      ...connectionConfig
    }
    this.ollamaBaseUrl = process.env.OLLAMA_BASE_URL || 'http://localhost:11434'
    this.ollamaEmbeddingModel = process.env.OLLAMA_EMBEDDING_MODEL || 'nomic-embed-text'
    this.ollama = new Ollama({ 
      model: this.ollamaEmbeddingModel,
      baseUrl: this.ollamaBaseUrl
    })
    this.db = null
    this.connected = false
  }

  init(host, port, user, password, database) {
    this.connectionConfig = {
      host: host || this.connectionConfig.host,
      port: port || this.connectionConfig.port,
      user: user || this.connectionConfig.user,
      password: password || this.connectionConfig.password,
      database: database || this.connectionConfig.database
    }
    return this
  }

  async connect() {
    try {
      console.log(`[${new Date().toISOString()}] Connecting to PostgreSQL at ${this.connectionConfig.host}:${this.connectionConfig.port}...`)
      
      this.db = new Client(this.connectionConfig)

      await this.db.connect()
      this.connected = true
      console.log(`[${new Date().toISOString()}] Successfully connected to PostgreSQL`)
    } catch (error) {
      console.error(`[${new Date().toISOString()}] Failed to connect to VectorDB:`, error)
      throw error
    }
  }

  async chunkText(text, chunkSize = 500, overlap = 50) {
    const words = text.split(" ")
    const chunks = []

    for (let i = 0; i < words.length; i += chunkSize - overlap) {
      chunks.push(words.slice(i, i + chunkSize).join(" "))
    }

    return chunks
  }

  async storeChunk(chunkContent, chunkIndex, documentId, embedding) {
    try {
      // Insert chunk
      const chunkResult = await this.db.query(
        `INSERT INTO chunks (document_id, chunk_index, content)
         VALUES ($1, $2, $3)
         RETURNING id`,
        [documentId, chunkIndex, chunkContent]
      )
      
      const chunkId = chunkResult.rows[0].id
      
      // Insert embedding
      await this.db.query(
        `INSERT INTO embeddings (chunk_id, embedding)
         VALUES ($1, $2)`,
        [chunkId, JSON.stringify(embedding)]
      )
      
      console.log(`[${new Date().toISOString()}] Stored chunk ${chunkIndex} with embedding`)
    } catch (error) {
      console.error(`[${new Date().toISOString()}] Error storing chunk:`, error)
      throw error
    }
  }

  async indexDocuments() {
    try {
      if (!this.connected) {
        await this.connect()
      }

      const docsPath = "./embeddings/docs"
      const files = fs.readdirSync(docsPath)

      for (const file of files) {
        try {
          const filePath = `${docsPath}/${file}`
          const text = fs.readFileSync(filePath, "utf-8")
          
          // Create document record
          const docResult = await this.db.query(
            `INSERT INTO documents (title, source)
             VALUES ($1, $2)
             RETURNING id`,
            [file.replace(/\.[^.]+$/, ''), filePath]
          )
          
          const documentId = docResult.rows[0].id
          
          // Chunk the text
          const chunks = await this.chunkText(text)

          console.log(`[${new Date().toISOString()}] Indexing document: ${file} with ${chunks.length} chunks`)

          for (let i = 0; i < chunks.length; i++) {
            const chunk = chunks[i]
            try {
              console.log(`[${new Date().toISOString()}] Embedding chunk ${i + 1}/${chunks.length}...`)
              const res = await this.ollama.embeddings({
                model: this.ollamaEmbeddingModel,
                prompt: chunk
              })
              
              await this.storeChunk(chunk, i, documentId, res.embedding)
            } catch (embedError) {
              console.error(`[${new Date().toISOString()}] Error embedding chunk ${i}:`, embedError)
            }
          }

          console.log(`[${new Date().toISOString()}] ✓ Successfully indexed: ${file}`)
        } catch (fileError) {
          console.error(`[${new Date().toISOString()}] Error indexing file ${file}:`, fileError)
        }
      }

      console.log(`[${new Date().toISOString()}] Document indexing complete`)
    } finally {
      await this.disconnect()
    }
  }

  async retrieve(queryEmbedding, topK = 2) {
    try {
      if (!this.connected) {
        await this.connect()
      }

      console.log(`[${new Date().toISOString()}] Searching pgvector for similar embeddings...`)

      const result = await this.db.query(
        `SELECT c.content, c.document_id, e.id as embedding_id, e.embedding <-> $1 as distance
         FROM embeddings e
         JOIN chunks c ON e.chunk_id = c.id
         JOIN documents d ON c.document_id = d.id
         ORDER BY e.embedding <-> $1
         LIMIT $2`,
        [JSON.stringify(queryEmbedding), topK]
      )

      console.log(`[${new Date().toISOString()}] Found ${result.rows.length} similar chunks, processing results...`)

      return result.rows.map(r => ({
        content: r.content,
        documentId: r.document_id,
        distance: r.distance
      }))
    } catch (error) {
      console.error(`[${new Date().toISOString()}] Error retrieving from VectorDB:`, error)
      throw error
    }
  }

  async disconnect() {
    try {
      if (this.connected && this.db) {
        console.log(`[${new Date().toISOString()}] Disconnecting from PostgreSQL...`)
        await this.db.end()
        this.connected = false
      }
    } catch (error) {
      console.error(`[${new Date().toISOString()}] Error disconnecting from VectorDB:`, error)
    }
  }
}

export const vectorDBStore = new VectorDBStore()

process.on('exit', async () => {
  await vectorDBStore.disconnect()
})
