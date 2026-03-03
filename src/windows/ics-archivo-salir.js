const { runPowerShellJson } = require("./run-powershell-json");

function startArchivoSalirIcs({
  windowTitleHint,
  timeoutMs,
  pollMs,
  commandId,
  gestionarWindowHwnd
}) {
  return runPowerShellJson({
    scriptRelativePath: "scripts/archivo-salir-ics.ps1",
    params: {
      WindowTitleHint: windowTitleHint,
      TimeoutMs: timeoutMs,
      PollMs: pollMs,
      CommandId: commandId,
      GestionarWindowHwnd: gestionarWindowHwnd
    },
    requireSummaryOk: true,
    windowsHide: true
  });
}

module.exports = { startArchivoSalirIcs };
