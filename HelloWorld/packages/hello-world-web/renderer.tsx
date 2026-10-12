import { createRoot } from "react-dom/client";
import "./styles.css";

function HelloWorld() {
  return <main>Hello, world!</main>;
}

createRoot(document.getElementById("root")!).render(<HelloWorld />);
