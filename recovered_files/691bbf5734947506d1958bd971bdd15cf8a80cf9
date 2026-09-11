import ollama from "ollama"
import fs from "fs"
import { VectorStoreInterface } from "./VectorStoreInterface.js"

/*
--------------------------------
In-Memory Vector Store Implementation
--------------------------------
*/

class InMemoryStore extends VectorStoreInterface {
  constructor() {
    super()
    this.vectorDB = []
  }

  async indexDocuments() {
    const files = fs.readdirSync("./embeddings/docs")

    for (const file of files) {
      const text = fs.readFileSync(`./embeddings/docs/${file}`, "utf-8")

      const embedding = await ollama.embeddings({
        model: "nomic-embed-text",
        prompt: text
      })

      this.vectorDB.push({
        text,
        embedding: embedding.embedding
      })

      console.log("Indexed document in memory:", file)
    }
  }

  async retrieve(queryEmbedding, topK = 2) {
    const scores = this.vectorDB.map(doc => ({
      content: doc.text,
      score: this.cosineSimilarity(queryEmbedding, doc.embedding)
    }))

    scores.sort((a, b) => b.score - a.score)
    return scores.slice(0, topK)
  }

  cosineSimilarity(a, b) {
    let dot = 0
    let magA = 0
    let magB = 0

    for (let i = 0; i < a.length; i++) {
      dot += a[i] * b[i]
      magA += a[i] * a[i]
      magB += b[i] * b[i]
    }

    magA = Math.sqrt(magA)
    magB = Math.sqrt(magB)

    return dot / (magA * magB)
  }
}

export const inMemoryStore = new InMemoryStore()