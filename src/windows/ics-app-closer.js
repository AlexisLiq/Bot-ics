const { runPowerShellJson } = require("./run-powershell-json");

function startCloseIcsApp({ windowTitleHint, timeoutMs, pollMs }) {
  return runPowerShellJson({
    scriptRelativePath: "scripts/close-ics-app.ps1",
    params: {
      WindowTitleHint: windowTitleHint,
      TimeoutMs: timeoutMs,
      PollMs: pollMs
    },
    requireSummaryOk: true,
    windowsHide: true
  });
}

module.exports = { startCloseIcsApp };
