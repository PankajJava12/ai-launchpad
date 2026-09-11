# AI Launchpad

> **Note:** This repository contains a significant amount of sensitive data including API keys and personal information. It has been temporarily restored for archival purposes. Please exercise extreme caution when accessing this content.

**Status:** Archived Repository

## Overview

AI Launchpad is an experimental platform designed to serve as a launching pad for AI and agentic AI projects. It currently serves as a collection point for various AI-related experiments, API integrations, and development artifacts.

## ⚠️ Security Warning

**This repository contains highly sensitive information.** Users are strongly advised to avoid cloning, downloading, or extracting files from this repository without proper security precautions.

**Critical Issues Found:**
- **Secret Keys:** The repository contains exposed API keys, including an **OR API Key**, which poses a significant security risk.
- **Personal Data:** Several files contain personal contact details such as phone numbers and email addresses.

**Recommended Action:**
For security reasons, it is recommended to keep this repository archived and avoid sharing its contents publicly.

## Project Structure

The repository contains several modules and projects, often including development versions and incomplete work. Key directories include:

- `agents`: Contains experimental agents and agentic AI projects.
- `ai-core`: Core AI-related components and utilities.
- `api-playground`: API integration experiments and test interfaces.
- `llm-utils`: Utilities for working with Large Language Models.
- `tools`: Collection of AI tools and utilities.
- `ai-playground/google-gen-ai-studio`: Project for Google GenAI Studio.

## Local Development Setup

To run any of the local examples, you typically need to install dependencies using `npm`.

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/PankajJava12/ai-launchpad.git
    ```

2.  **Navigate to the desired project directory:**
    ```bash
    cd ai-launchpad/llm-utils
    ```

3.  **Install dependencies:**
    ```bash
    npm install
    ```

4.  **Run the application:**
    ```bash
    node <filename>.js
    ```

### Setting up Environment Variables

Some projects require an `.env` file for API keys. A template is often provided.

1.  **Create a `.env` file** in the project root (or specific project directory):
    ```bash
    cp .env.example .env
    ```

2.  **Add your API keys** to the `.env` file:
    ```ini
    OPENROUTER_API_KEY=your_openrouter_api_key_here
    GEMINI_API_KEY=your_gemini_api_key_here
    ANTHROPIC_API_KEY=your_anthropic_api_key_here
    GROQ_API_KEY=your_groq_api_key_here
    ```

## Contact Information

For questions regarding this repository, please contact:
- **Email:** [EMAIL_ADDRESS]`
- **Phone:** `[PHONE_NUMBER]` (US)`
- **WhatsApp:** `[PHONE_NUMBER]`

## License

Proprietary / All Rights Reserved.
