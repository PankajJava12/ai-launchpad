/*
--------------------------------
Vector Store Interface
Base class defining the contract for vector store implementations
--------------------------------
*/

export class VectorStoreInterface {
  /**
   * Index documents from the docs directory
   */
  async indexDocuments() {
    throw new Error("indexDocuments() must be implemented by subclass")
  }

  /**
   * Retrieve top k similar documents for a query embedding
   * @param {Array} queryEmbedding - The embedding vector for the query
   * @param {number} topK - Number of top results to return
   * @returns {Array} - Array of objects with text and score
   */
  async retrieve(queryEmbedding, topK = 2) {
    throw new Error("retrieve() must be implemented by subclass")
  }
}
