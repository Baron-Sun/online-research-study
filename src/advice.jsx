import React from "react";
import { createRoot } from "react-dom/client";
import AdviceTaskApp from "./AdviceTask.jsx";

createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    <AdviceTaskApp />
  </React.StrictMode>
);
