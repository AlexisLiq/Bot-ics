const { config } = require("../config/config");
const { startOpenGestionarMenu } = require("../windows/ics-menu-navigator");

async function runOpenGestionarMenuTask() {
  const runner = startOpenGestionarMenu({
    windowTitleHint: config.icsMainWindowTitleHint,
    timeoutMs: config.icsGestionarOpenTimeoutMs,
    pollMs: config.icsGestionarOpenPollMs,
    commandId: config.icsGestionarCommandId
  });

  const result = await runner.result;

  if (!result.summary) {
    throw new Error("No se pudo leer la respuesta del script para abrir Gestion -> Gestionar.");
  }

  if (!result.summary.windowFound) {
    throw new Error(
      result.summary.error ||
        "No se encontro la ventana principal de ICS para abrir Gestion -> Gestionar."
    );
  }

  if (!result.summary.menuSent || !result.summary.ok) {
    throw new Error(
      result.summary.error ||
        "No se pudo invocar Gestion -> Gestionar por WM_COMMAND."
    );
  }

  return result.summary;
}

module.exports = { runOpenGestionarMenuTask };
