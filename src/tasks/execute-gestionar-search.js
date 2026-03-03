const { config } = require("../config/config");
const { startOperateGestionar } = require("../windows/ics-gestionar-operator");

async function runExecuteGestionarSearchTask({ window, controls, cedula }) {
  const normalizedCedula = String(cedula || "").trim();
  if (!normalizedCedula) {
    throw new Error(
      "Falta cedula para ejecutar la busqueda en Gestionar."
    );
  }

  const runner = startOperateGestionar({
    mainWindowHwnd: window?.hwnd,
    identificationInputHwnd: controls?.identificationInput?.hwnd,
    buscarButtonHwnd: controls?.buscarButton?.hwnd,
    cedula: normalizedCedula,
    stepDelayMs: config.icsGestionarStepDelayMs,
    beforeLegalDelayMs: config.icsBeforeLegalDelayMs,
    timeoutMs: config.icsOperateGestionarTimeoutMs
  });

  const result = await runner.result;

  if (!result.summary) {
    throw new Error("No se pudo leer la respuesta de la secuencia en Gestionar.");
  }

  if (!result.summary.ok) {
    const baseError =
      result.summary.error ||
      "No se pudo completar la secuencia Cedula -> Buscar en Gestionar.";
    throw new Error(
      `${baseError}`
    );
  }

  return result.summary;
}

module.exports = { runExecuteGestionarSearchTask };
