// langchain-rag.js

import { Ollama } from "@langchain/community/llms/ollama";
import { OllamaEmbeddings } from "@langchain/community/embeddings/ollama";
import { MemoryVectorStore } from "langchain/vectorstores/memory";
import { PGVectorStore } from "@langchain/community/vectorstores/pgvector";
import pkg from "pg";

const { Pool } = pkg;

// ------------------------------
// Config
// ------------------------------
const config = {
  store: "vectorDB", // 'inMemory' or 'vectorDB'
};

// ------------------------------
// Models
// ------------------------------
const llm = new Ollama({
  model: "llama3",
});

const embeddings = new OllamaEmbeddings({
  model: "nomic-embed-text",
});

// ------------------------------
// Postgres Setup
// ------------------------------
const pool = new Pool({
  host: "localhost",
  port: 5432,
  user: "postgres",
  password: "postgres", // change if needed
  database: "vectordb",
});

// ------------------------------
// Vector Store Factory
// ------------------------------
let vectorStore;

async function getVectorStore() {
  if (vectorStore) return vectorStore;

  if (config.store === "inMemory") {
    vectorStore = await MemoryVectorStore.fromTexts(
      [
        "Surrender policy allows partial withdrawal after 3 years.",
        "Premium payment must be done annually.",
        "Policy includes accidental coverage.",
      ],
      [{ id: 1 }, { id: 2 }, { id: 3 }],
      embeddings
    );
  } else if (config.store === "vectorDB") {
    vectorStore = await PGVectorStore.initialize(embeddings, {
      pool,
      tableName: "documents_lc",
      columns: {
        idColumnName: "id",
        vectorColumnName: "embedding",
        contentColumnName: "content",
        metadataColumnName: "metadata",
      },
    });

    // ------------------------------
    // Index documents (only once)
    // ------------------------------
    const count = await pool.query("SELECT COUNT(*) FROM documents_lc");

    if (parseInt(count.rows[0].count) === 0) {
      console.log("Indexing documents into pgvector...");

      await vectorStore.addDocuments([
        {
          pageContent:
            "Surrender policy allows partial withdrawal after 3 years.",
          metadata: { id: 1 },
        },
        {
          pageContent: "Premium payment must be done annually.",
          metadata: { id: 2 },
        },
        {
          pageContent: "Policy includes accidental coverage.",
          metadata: { id: 3 },
        },
      ]);
    }
  }

  return vectorStore;
}

// ------------------------------
// Ask Function
// ------------------------------
async function ask(question) {
  const store = await getVectorStore();

  const retriever = store.asRetriever(2);

  const docs = await retriever.invoke(question);

  const context = docs.map((d) => d.pageContent).join("\n");

  const response = await llm.invoke(`
Answer the question using the context below.

Context:
${context}

Question:
${question}
`);

  console.log("\nAnswer:\n");
  console.log(response);
}

// ------------------------------
// Main
// ------------------------------
async function main() {
  console.log(`Using ${config.store} vector store...`);

  await ask("What is the surrender policy?");

  process.exit(0);
}

main().catch(console.error);