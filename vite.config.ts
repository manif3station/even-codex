import { defineConfig } from 'vite';

export default defineConfig({
  root: 'even-hub',
  build: {
    outDir: '../dist',
    emptyOutDir: true,
    cssCodeSplit: false,
    rollupOptions: {
      output: {
        entryFileNames: 'assets/even-hub-app.js',
        chunkFileNames: 'assets/even-hub-app.js',
        assetFileNames: (assetInfo) => {
          if ((assetInfo.name || '').endsWith('.css')) {
            return 'assets/even-hub-app.css';
          }
          return 'assets/[name][extname]';
        },
        manualChunks: undefined,
      },
    },
  },
});
