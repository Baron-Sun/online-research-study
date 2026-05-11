import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { resolve } from "node:path";

const [owner = "", repo = ""] = (process.env.GITHUB_REPOSITORY || "").split("/");
const isUserOrOrgPage = repo === `${owner}.github.io`;

export default defineConfig({
  base: process.env.GITHUB_ACTIONS
    ? isUserOrOrgPage
      ? "/"
      : `/${repo}/`
    : "/",
  plugins: [react()],
  build: {
    rollupOptions: {
      input: {
        main: resolve(__dirname, "index.html"),
        judgment: resolve(__dirname, "judgment/index.html"),
        ratings: resolve(__dirname, "ratings/index.html"),
      },
    },
  },
});
