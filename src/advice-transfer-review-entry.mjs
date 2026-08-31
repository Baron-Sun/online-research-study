const REVIEW_FLAG = "1";
const REVIEW_STUDY_ID = "study2-v4-review";

const cleanParameter = (value) => {
  if (!value || value.includes("{{%") || value.includes("%}}")) return "";
  return value.trim();
};
const randomToken = (cryptoProvider) => {
  if (typeof cryptoProvider?.randomUUID === "function") {
    return cryptoProvider.randomUUID();
  }
  if (typeof cryptoProvider?.getRandomValues !== "function") {
    throw new Error("Secure random values are unavailable in this browser.");
  }

  const bytes = new Uint8Array(16);
  cryptoProvider.getRandomValues(bytes);
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
};

export const ensureSharedReviewParticipant = ({
  location = window.location,
  history = window.history,
  cryptoProvider = window.crypto,
} = {}) => {
  const params = new URLSearchParams(location.search);
  const existingParticipant = cleanParameter(
    params.get("PROLIFIC_PID") || params.get("prolific_pid"),
  );

  if (params.get("review") !== REVIEW_FLAG || existingParticipant) return null;

  const prolificPid = `qa-review-${randomToken(cryptoProvider)}`;
  const sessionId = `qa-review-session-${randomToken(cryptoProvider)}`;

  for (const alias of [
    "prolific_pid",
    "study_id",
    "session_id",
    "PROLIFIC_PID",
    "STUDY_ID",
    "SESSION_ID",
  ]) {
    params.delete(alias);
  }
  params.set("PROLIFIC_PID", prolificPid);
  params.set("STUDY_ID", REVIEW_STUDY_ID);
  params.set("SESSION_ID", sessionId);

  const query = params.toString();
  const nextUrl = `${location.pathname}${query ? `?${query}` : ""}${location.hash || ""}`;
  history.replaceState(history.state ?? null, "", nextUrl);

  return { prolificPid, studyId: REVIEW_STUDY_ID, sessionId, nextUrl };
};
