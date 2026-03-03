const { runPowerShellJson } = require("./run-powershell-json");

function startOperateGestionar({
  mainWindowHwnd,
  identificationInputHwnd,
  buscarButtonHwnd,
  cedula,
  stepDelayMs,
  beforeLegalDelayMs,
  timeoutMs
}) {
  return runPowerShellJson({
    scriptRelativePath: "scripts/operate-ics-gestionar.ps1",
    params: {
      MainWindowHwnd: mainWindowHwnd,
      IdentificationInputHwnd: identificationInputHwnd,
      BuscarButtonHwnd: buscarButtonHwnd,
      Cedula: cedula,
      StepDelayMs: stepDelayMs,
      BeforeLegalDelayMs: beforeLegalDelayMs
    },
    requireSummaryOk: true,
    windowsHide: true,
    timeoutMs
  });
}

module.exports = { startOperateGestionar };
