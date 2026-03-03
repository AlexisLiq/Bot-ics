const { config } = require("../config/config");
const { startIdentifyGestionarControls } = require("../windows/ics-gestionar-controls");

async function runIdentifyGestionarControlsTask() {
  const runner = startIdentifyGestionarControls({
    windowTitleHint: config.icsMainWindowTitleHint,
    timeoutMs: config.icsMainWindowTimeoutMs,
    pollMs: config.icsMainWindowPollMs
  });

  const result = await runner.result;

  if (!result.summary) {
    throw new Error("No se pudo leer la respuesta del identificador de controles de Gestionar.");
  }

  if (!result.summary.windowFound) {
    throw new Error(
      result.summary.error ||
        "No se encontro la ventana principal de ICS para identificar controles en Gestionar."
    );
  }

  const requiredKeys = ["identificationInput", "buscarButton", "legalTab"];
  const missing = requiredKeys.filter((key) => !(result.summary.found || {})[key]);
  if (!result.summary.ok || missing.length > 0) {
    const missingText = missing.length > 0 ? ` Faltantes: ${missing.join(", ")}.` : "";

    throw new Error(
      (result.summary.error ||
        "No se pudieron identificar todos los controles requeridos en Gestionar.") + missingText
    );
  }

  return result.summary;
}

module.exports = { runIdentifyGestionarControlsTask };
