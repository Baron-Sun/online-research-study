import React from "react";
import { createRoot } from "react-dom/client";
import JudgmentTaskApp from "./JudgmentTask.jsx";

createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    <JudgmentTaskApp />
  </React.StrictMode>
);
