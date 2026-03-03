const { config } = require("../config/config");
const { startArchivoSalirIcs } = require("../windows/ics-archivo-salir");

async function runExitGestionarTask({ gestionarWindowHwnd } = {}) {
  const runner = startArchivoSalirIcs({
    windowTitleHint: config.icsMainWindowTitleHint,
    timeoutMs: config.icsExitGestionarTimeoutMs,
    pollMs: config.icsGestionarOpenPollMs,
    commandId: config.icsArchivoSalirCommandId,
    gestionarWindowHwnd
  });

  const result = await runner.result;
  if (!result.summary) {
    throw new Error("No se pudo leer respuesta de Archivo -> Salir.");
  }

  if (!result.summary.ok) {
    if (result.summary.sent && result.summary.method === "wm_command") {
      return {
        ...result.summary,
        warning:
          result.summary.error ||
          "No se pudo confirmar cierre de Gestionar, pero se envio Archivo -> Salir."
      };
    }

    throw new Error(
      result.summary.error || "No se pudo ejecutar Archivo -> Salir en ICS."
    );
  }

  return result.summary;
}

module.exports = { runExitGestionarTask };
