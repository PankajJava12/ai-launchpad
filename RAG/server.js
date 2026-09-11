import express from 'express'
import dotenv from 'dotenv'
import { ask, retrieve } from './rag.js'

// Load environment variables
dotenv.config()

const app = express()
const PORT = process.env.API_PORT || 3000

// Middleware
app.use(express.json())

// Health check endpoint
app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    version: '1.0.0'
  })
})

// Liveness probe for ECS/Kubernetes
app.get('/live', (req, res) => {
  res.status(200).json({ status: 'alive' })
})

// Main RAG endpoint - Ask a question
app.post('/api/ask', async (req, res) => {
  try {
    const { question } = req.body

    if (!question) {
      return res.status(400).json({
        error: 'Missing required field: question'
      })
    }

    console.log(`[${new Date().toISOString()}] Received question: ${question}`)

    const answer = await ask(question)

    return res.status(200).json({
      question,
      answer,
      timestamp: new Date().toISOString()
    })
  } catch (error) {
    console.error('Error processing question:', error)
    return res.status(500).json({
      error: 'Failed to process question',
      message: error.message
    })
  }
})

// Retrieve endpoint - Get relevant context for a query
app.post('/api/retrieve', async (req, res) => {
  try {
    const { query, topK } = req.body

    if (!query) {
      return res.status(400).json({
        error: 'Missing required field: query'
      })
    }

    console.log(`[${new Date().toISOString()}] Retrieving context for: ${query}`)

    const context = await retrieve(query, topK || 2)

    return res.status(200).json({
      query,
      context,
      timestamp: new Date().toISOString()
    })
  } catch (error) {
    console.error('Error retrieving context:', error)
    return res.status(500).json({
      error: 'Failed to retrieve context',
      message: error.message
    })
  }
})

// Root endpoint
app.get('/', (req, res) => {
  res.status(200).json({
    name: 'RAG API',
    version: '1.0.0',
    description: 'Retrieval-Augmented Generation API for Insurance Policy Q&A',
    endpoints: {
      health: 'GET /health',
      liveness: 'GET /live',
      ask: 'POST /api/ask { question: string }',
      retrieve: 'POST /api/retrieve { query: string, topK?: number }'
    }
  })
})

// Error handling middleware
app.use((err, req, res, next) => {
  console.error('Unhandled error:', err)
  res.status(500).json({
    error: 'Internal server error',
    message: process.env.NODE_ENV === 'development' ? err.message : undefined
  })
})

// Start server
const server = app.listen(PORT, () => {
  console.log(`[${new Date().toISOString()}] RAG API server running on port ${PORT}`)
  console.log(`Environment: ${process.env.NODE_ENV || 'development'}`)
  console.log(`Vector Store: ${process.env.VECTOR_STORE || 'vectorDB'}`)
  console.log(`Ollama Base URL: ${process.env.OLLAMA_BASE_URL || 'http://localhost:11434'}`)
})

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('[SIGTERM] Shutting down gracefully...')
  server.close(() => {
    console.log('Server closed')
    process.exit(0)
  })
})

process.on('SIGINT', () => {
  console.log('[SIGINT] Shutting down gracefully...')
  server.close(() => {
    console.log('Server closed')
    process.exit(0)
  })
})
