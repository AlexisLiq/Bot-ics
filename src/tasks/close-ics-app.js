const { config } = require("../config/config");
const { startCloseIcsApp } = require("../windows/ics-app-closer");

async function runCloseIcsAppTask() {
  const runner = startCloseIcsApp({
    windowTitleHint: config.icsMainWindowTitleHint,
    timeoutMs: config.icsCloseAppTimeoutMs,
    pollMs: config.icsMainWindowPollMs
  });

  const result = await runner.result;
  if (!result.summary) {
    throw new Error("No se pudo leer respuesta de cierre de app ICS.");
  }

  if (!result.summary.ok) {
    throw new Error(
      result.summary.error || "No se pudo cerrar el aplicativo ICS."
    );
  }

  return result.summary;
}

module.exports = { runCloseIcsAppTask };
