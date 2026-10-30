import { defineConfig } from 'vite'
import { attachParty, lanHosts } from './server/party.mjs'

export default defineConfig({
  server: { port: 5178, strictPort: true, host: process.env.HOST || '10.0.4.94' },
  preview: { port: 5178, strictPort: true, host: process.env.HOST || '10.0.4.94' },
  base: './',
  plugins: [
    {
      name: 'sword-party',
      configureServer(server) {
        server.middlewares.use('/api/link', (_req, res) => {
          res.setHeader('content-type', 'application/json')
          res.end(JSON.stringify({ hosts: lanHosts(), port: server.config.server.port || 5178 }))
        })
        if (server.httpServer) attachParty(server.httpServer)
      },
    },
  ],
})
