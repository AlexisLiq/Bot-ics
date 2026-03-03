const { config } = require("../config/config");
const { startPostSearchGestionar } = require("../windows/ics-post-search");

async function runPostSearchGestionarTask({ window }) {
  const runner = startPostSearchGestionar({
    mainWindowHwnd: window?.hwnd,
    targetProcessName: "Ejecutivo Singular",
    timeoutMs: config.icsPostSearchTimeoutMs,
    pollMs: config.icsMainWindowPollMs,
    stepDelayMs: config.icsGestionarStepDelayMs
  });

  const result = await runner.result;

  if (!result.summary) {
    throw new Error("No se pudo leer la respuesta del post-proceso en Gestionar.");
  }

  if (!result.summary.ok) {
    throw new Error(
      result.summary.error ||
        "No se pudo completar el post-proceso en Gestionar."
    );
  }

  return result.summary;
}

module.exports = { runPostSearchGestionarTask };
