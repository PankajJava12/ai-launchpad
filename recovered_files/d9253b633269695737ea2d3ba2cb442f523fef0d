1 Start the container
docker compose up -d

2 Login into container and query:
docker exec -it pgvector-db psql -U postgres -d vectordb

OR

Open pgAdmin in browser
`http://localhost:5050`

Credentials
Email: admin@admin.com
Password: admin

Connect pgAdmin to Postgres

Inside pgAdmin:
- Right click Servers
- Click Register → Server

General tab
Name: pgvector-local
Connection tab
Host: postgres
Port: 5432
Username: postgres
Password: postgres
Database: vectordb

Important:
Host = postgres
because Docker services communicate via service name.

- Enable pgvector extension

Open Query Tool and run:

`CREATE EXTENSION vector;`

Verify:

`SELECT * FROM pg_extension;`

- You should see:

`vector`

- Create vector table

Example:
```
CREATE TABLE documents (
  id SERIAL PRIMARY KEY,
  content TEXT,
  embedding VECTOR(768)
);

(768 if using nomic-embed-text from Ollama.)
```

- Test similarity search

Example:
```
SELECT content
FROM documents
ORDER BY embedding <-> '[0.1,0.2,0.3]'
LIMIT 3;
```
