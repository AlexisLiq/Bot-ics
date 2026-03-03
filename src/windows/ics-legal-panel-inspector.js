const { runPowerShellJson } = require("./run-powershell-json");

function startInspectLegalPanel({
  mainWindowHwnd,
  sampleLimit,
  maxNodes,
  timeoutMs
}) {
  return runPowerShellJson({
    scriptRelativePath: "scripts/inspect-ics-legal-panel.ps1",
    params: {
      MainWindowHwnd: mainWindowHwnd,
      SampleLimit: sampleLimit,
      MaxNodes: maxNodes
    },
    requireSummaryOk: true,
    windowsHide: true,
    timeoutMs
  });
}

module.exports = { startInspectLegalPanel };
