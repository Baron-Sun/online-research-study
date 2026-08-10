import React from "react";
import { createRoot } from "react-dom/client";
import SourceDetectionTask from "./SourceDetectionTask.jsx";
import "./source-detection.css";

createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    <SourceDetectionTask />
  </React.StrictMode>,
);
