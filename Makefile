PORT ?= 9092

.PHONY: run install build dev clean

# Default: install deps, build the frontend, and serve API + UI on one port.
run: install build
	NODE_ENV=production API_PORT=$(PORT) node server/index.js

install:
	npm install

build:
	npm run build

# Two-process dev mode (Vite :5173 + API :8080), with hot reload.
dev: install
	npm run dev

clean:
	rm -rf dist node_modules server/data.sqlite server/data.sqlite-shm server/data.sqlite-wal
