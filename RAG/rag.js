import { Ollama } from 'ollama'
import dotenv from "dotenv"
import { inMemoryStore } from "./embeddings/inMemory.js"
import { vectorDBStore } from "./embeddings/vectorDB.js"

const ollama = new Ollama({
  host: process.env.OLLAMA_BASE_URL, // Custom host address
})

// Load environment variables
dotenv.config()

// Configuration for vector store - support environment variables
const config = {
  store: process.env.VECTOR_STORE || 'vectorDB', // options: 'inMemory' or 'vectorDB'
  ollamaBaseUrl: process.env.OLLAMA_BASE_URL || 'http://localhost:11434',
  ollamaModel: process.env.OLLAMA_MODEL || 'llama3',
  ollamaEmbeddingModel: process.env.OLLAMA_EMBEDDING_MODEL || 'nomic-embed-text',
  temperature: parseFloat(process.env.OLLAMA_TEMPERATURE || '0.7'),
  dbHost: process.env.DB_HOST || 'localhost',
  dbPort: parseInt(process.env.DB_PORT || '5432'),
  dbUser: process.env.DB_USER || 'postgres',
  dbPassword: process.env.DB_PASSWORD || 'postgres',
  dbName: process.env.DB_NAME || 'vectordb'
}

// Initialize Ollama with configurable base URL
// const ollamaClient = new ollama.Ollama({
//   model: config.ollamaEmbeddingModel,
//   baseUrl: config.ollamaBaseUrl
// })

// Factory function to get the appropriate store based on config
function getVectorStore() {
  if (config.store === 'vectorDB') {
    // Pass database configuration to vectorDB store
    return vectorDBStore.init(config.dbHost, config.dbPort, config.dbUser, config.dbPassword, config.dbName)
  }
  return inMemoryStore
}

/*
--------------------------------
Retrieve Relevant Context
--------------------------------
*/

export async function retrieve(query, topK = 2) {
  const store = await getVectorStore()

  console.log(`[${new Date().toISOString()}] Generating query embedding for: "${query}"`)

  console.log('-----config.ollamaBaseUrl', config.ollamaBaseUrl)
  console.log('OLLAMA_HOST:', process.env.OLLAMA_HOST);

  const queryEmbedding = await ollama.embed({
    model: config.ollamaEmbeddingModel,
    prompt: query
  })

  const scores = await store.retrieve(queryEmbedding.embedding, topK)

  const context = scores.map(s => s.content).join("\n\n---\n\n")
  console.log(`[${new Date().toISOString()}] Retrieved ${scores.length} relevant documents`)
  
  return context
}

/*
--------------------------------
Ask Question
--------------------------------
*/

export async function ask(question) {
  try {
    const context = await retrieve(question, 2)

    console.log(`[${new Date().toISOString()}] Querying LLM for answer...`)

    const response = await ollama.chat({
      model: config.ollamaModel,
      messages: [
        {
          role: "system",
          content: "You are a helpful assistant that answers questions about insurance policies using the provided context. Answer based only on the context provided. If the answer is not in the context, say 'I don't have information about that in the provided documents.'"
        },
        {
          role: "user",
          content: `
Context:
${context}

Question:
${question}
`
        }
      ],
      temperature: config.temperature,
      stream: false
    })

    const answer = response.message.content
    console.log(`[${new Date().toISOString()}] Generated answer successfully`)
    
    return answer
  } catch (error) {
    console.error(`[${new Date().toISOString()}] Error in ask():`, error)
    throw new Error(`Failed to generate answer: ${error.message}`)
  }
}

/*
--------------------------------
Run
--------------------------------
*/

async function main() {
  const store = getVectorStore()
  
  // Storing the vectors based on config. 
  // In production we will have a separate indexing step and a persistent vector store into VectoDB like pgvector, PineCone, Weaviate, etc.
  // Warning: Call this function only once if you are using config.store as 'vectorDB' to avoid duplicate entries in the vector store. 
  // In production, we will have a separate indexing step and a persistent vector store.
  console.log(`Using ${config.store} vector store...`)
  // await store.indexDocuments()

  await ask("What is the surrender policy?")
  // await ask("I want to buy Mario and contra")
  
  process.exit(0)
}

// Not calling main() to avoid running the ask() function on import. This file is meant to be imported as a module in server.js and seed.js, where the ask() and retrieve() functions will be used. 
// main().catch(error => {
//   console.error("Error:", error)
//   process.exit(1)
// })