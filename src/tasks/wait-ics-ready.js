const { config } = require("../config/config");
const { startWaitIcsStartup } = require("../windows/ics-startup-watcher");

async function runWaitIcsReadyTask() {
  const runner = startWaitIcsStartup({
    windowTitleHint: config.icsMainWindowTitleHint,
    timeoutMs: config.icsStartupReadyTimeoutMs,
    pollMs: config.icsStartupReadyPollMs,
    stablePolls: config.icsStartupReadyStablePolls
  });

  const result = await runner.result;

  if (!result.summary) {
    throw new Error("No se pudo leer la respuesta del watcher de inicialización de ICS.");
  }

  if (!result.summary.windowFound) {
    throw new Error(
      result.summary.error ||
        "No se encontró la ventana principal de ICS para validar inicialización."
    );
  }

  if (!result.summary.ok) {
    throw new Error(
      result.summary.error ||
        "ICS no quedó listo dentro del timeout de inicialización."
    );
  }

  return result.summary;
}

module.exports = { runWaitIcsReadyTask };
