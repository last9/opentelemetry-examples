import { StrictMode } from "react";
import { createRoot } from "react-dom/client";

import App from "./App";
import "./rum"; // starts L9RUM.init(); render is not blocked on it

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
