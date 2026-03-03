const { runPowerShellJson } = require("./run-powershell-json");

function startSelectLegalTabWithWin32({
  mainWindowHwnd,
  legalTabHwnd,
  identificationInputHwnd,
  buscarButtonHwnd,
  stepDelayMs,
  panelWaitMs,
  pollMs
}) {
  return runPowerShellJson({
    scriptRelativePath: "scripts/select-legal-tab-win32.ps1",
    params: {
      MainWindowHwnd: mainWindowHwnd,
      LegalTabHwnd: legalTabHwnd,
      IdentificationInputHwnd: identificationInputHwnd,
      BuscarButtonHwnd: buscarButtonHwnd,
      StepDelayMs: stepDelayMs,
      PanelWaitMs: panelWaitMs,
      PollMs: pollMs
    },
    requireSummaryOk: true,
    windowsHide: true,
    timeoutMs: 30000
  });
}

module.exports = { startSelectLegalTabWithWin32 };
