import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

const [owner = "", repo = ""] = (process.env.GITHUB_REPOSITORY || "").split("/");
const isUserOrOrgPage = repo === `${owner}.github.io`;

export default defineConfig({
  base: process.env.GITHUB_ACTIONS
    ? isUserOrOrgPage
      ? "/"
      : `/${repo}/`
    : "/",
  plugins: [react()],
});
