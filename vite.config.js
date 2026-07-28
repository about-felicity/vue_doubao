import { defineConfig } from "vite";
import vue from "@vitejs/plugin-vue";

export default defineConfig({
  plugins: [vue()],
  // Relative base so the page works both locally and behind an Nginx subpath
  // such as /ShanxiCustomBaojianPing/ without needing root-level routes.
  base: "./",
  build: {
    outDir: "dist",
    emptyOutDir: true,
    assetsDir: "dashboard-assets",
  },
});
