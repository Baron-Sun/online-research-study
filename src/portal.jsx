import React, { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";

const TailwindLoader = ({ children }) => {
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    if (document.querySelector('script[src*="tailwindcss"]')) {
      setLoaded(true);
      return;
    }

    const script = document.createElement("script");
    script.src = "https://cdn.tailwindcss.com";
    script.onload = () => setLoaded(true);
    script.onerror = () => setLoaded(true);
    document.head.appendChild(script);
  }, []);

  if (!loaded) {
    return (
      <div className="min-h-screen bg-slate-50 text-slate-700 flex items-center justify-center">
        Loading...
      </div>
    );
  }

  return children;
};

const Portal = () => (
  <main className="min-h-screen bg-slate-50 text-slate-900">
    <div className="mx-auto max-w-4xl px-5 py-10 md:px-8">
      <header className="mb-8 border-b border-slate-200 pb-6">
        <p className="mb-2 text-xs font-semibold uppercase tracking-[0.18em] text-slate-500">
          Northwestern University Research Study
        </p>
        <h1 className="text-3xl font-semibold tracking-tight text-slate-950 md:text-[2.4rem]">
          Online Research Study
        </h1>
      </header>

      <section className="rounded-lg border border-slate-200 bg-white p-6 shadow-sm">
        <h2 className="text-xl font-semibold text-slate-950">
          Research Task Links
        </h2>
        <p className="mt-2 text-sm leading-6 text-slate-600">
          These are separate task entry points for researcher setup and testing.
          Crowdsourcing participants should receive the specific task link
          assigned to their study.
        </p>

        <div className="mt-6 grid gap-4 md:grid-cols-3">
          <a
            className="rounded-lg border border-slate-200 bg-slate-50 p-5 transition hover:bg-white hover:shadow-sm"
            href="./advice/"
          >
            <span className="block text-sm font-semibold uppercase tracking-wide text-slate-500">
              Task A
            </span>
            <span className="mt-2 block text-lg font-semibold text-slate-950">
              Advice Exposure Task
            </span>
            <span className="mt-2 block text-sm leading-6 text-slate-600">
              One post with prior comments, one related post, one advice
              response, and brief follow-up questions.
            </span>
          </a>

          <a
            className="rounded-lg border border-slate-200 bg-slate-50 p-5 transition hover:bg-white hover:shadow-sm"
            href="./judgment/"
          >
            <span className="block text-sm font-semibold uppercase tracking-wide text-slate-500">
              Task B
            </span>
            <span className="mt-2 block text-lg font-semibold text-slate-950">
              Single Post Response Task
            </span>
            <span className="mt-2 block text-sm leading-6 text-slate-600">
              One post, one category response, written explanation, and brief
              follow-up questions.
            </span>
          </a>

          <a
            className="rounded-lg border border-slate-200 bg-slate-50 p-5 transition hover:bg-white hover:shadow-sm"
            href="./ratings/"
          >
            <span className="block text-sm font-semibold uppercase tracking-wide text-slate-500">
              Task C
            </span>
            <span className="mt-2 block text-lg font-semibold text-slate-950">
              Multi-Post Rating Task
            </span>
            <span className="mt-2 block text-sm leading-6 text-slate-600">
              Five posts, three rating questions per post, then one final
              submission.
            </span>
          </a>
        </div>
      </section>
    </div>
  </main>
);

createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    <TailwindLoader>
      <Portal />
    </TailwindLoader>
  </React.StrictMode>
);
