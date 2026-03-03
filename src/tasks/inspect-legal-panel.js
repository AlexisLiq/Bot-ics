const { config } = require("../config/config");
const { startInspectLegalPanel } = require("../windows/ics-legal-panel-inspector");

async function runInspectLegalPanelTask({ window } = {}) {
  const runner = startInspectLegalPanel({
    mainWindowHwnd: window?.hwnd,
    sampleLimit: config.icsDebugLegalPanelSampleLimit,
    maxNodes: config.icsDebugLegalPanelMaxNodes,
    timeoutMs: config.icsDebugLegalInspectorTimeoutMs
  });

  const result = await runner.result;
  if (!result.summary) {
    throw new Error("No se pudo leer respuesta del inspector de panel Legal.");
  }

  if (!result.summary.ok) {
    throw new Error(
      result.summary.error || "No se pudo inspeccionar el panel Legal."
    );
  }

  return result.summary;
}

module.exports = { runInspectLegalPanelTask };
