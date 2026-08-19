import React from "react";
import { createRoot } from "react-dom/client";
import AdviceTransferTask from "./AdviceTransferTask.jsx";
import "./source-detection.css";
import "./advice-transfer.css";

createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    <AdviceTransferTask />
  </React.StrictMode>,
);
