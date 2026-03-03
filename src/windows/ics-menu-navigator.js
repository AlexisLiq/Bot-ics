const { runPowerShellJson } = require("./run-powershell-json");

function startOpenGestionarMenu({
  windowTitleHint,
  timeoutMs,
  pollMs,
  commandId
}) {
  return runPowerShellJson({
    scriptRelativePath: "scripts/open-ics-gestionar.ps1",
    params: {
      WindowTitleHint: windowTitleHint,
      TimeoutMs: timeoutMs,
      PollMs: pollMs,
      CommandId: commandId
    },
    requireSummaryOk: true,
    windowsHide: true
  });
}

module.exports = { startOpenGestionarMenu };
