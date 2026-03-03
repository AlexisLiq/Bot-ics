const { runPowerShellJson } = require("./run-powershell-json");

function startIdentifyGestionarControls({ windowTitleHint, timeoutMs, pollMs }) {
  return runPowerShellJson({
    scriptRelativePath: "scripts/identify-ics-gestionar-controls.ps1",
    params: {
      WindowTitleHint: windowTitleHint,
      TimeoutMs: timeoutMs,
      PollMs: pollMs
    },
    requireSummaryOk: true,
    windowsHide: true
  });
}

module.exports = { startIdentifyGestionarControls };
